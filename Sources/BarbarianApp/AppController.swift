import AppKit
import BarbarianCore
import BarbarianSystem

/// Owns Barbarian's status items and decides what the menu bar shows.
final class AppController: NSObject, NSApplicationDelegate {
    private var controlItems: ControlItems!
    private(set) var state: HidingState = .showingShownOnly
    private var pointerLastInMenuBarAt = Date()
    private var hoverStartedAt: Date?
    private var pollTimer: Timer?
    private var mouseDownMonitor: Any?
    private var iconPressMonitor: Any?
    private var hotKeys: [GlobalHotKey] = []
    private var commandObserver: NSObjectProtocol?
    private lazy var itemAccess = ItemAccess(controller: self)
    private lazy var layoutPanel = LayoutPanel(controller: self)
    private lazy var settingsWindow = SettingsWindowController(controller: self)
    private let statusMessage = StatusMessage()
    let itemImages = ItemImageCache { Preferences.shared.showsItemImages }

    /// Keeps every section on screen while the Arrange panel is open.
    var isPinnedOpen = false {
        didSet { setState(isPinnedOpen ? .showingAll : .showingShownOnly) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlItems = ControlItems()
        iconPressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let wasIconPress = MainActor.assumeIsolated { self?.handleIconPress(event) ?? false }
            return wasIconPress ? nil : event
        }
        apply()
        startPolling()
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutsideBarbarian() }
        }
        registerHotKeys()
        Preferences.shared.onShortcutsChange = { [weak self] in self?.registerHotKeys() }
        LaunchAtLogin.enableOnFirstLaunch()
        settingsWindow.showOnFirstLaunch()
        commandObserver = CommandChannel.listen { [weak self] in self?.perform($0) }
    }

    private func perform(_ command: Command) {
        switch command {
        case .showHidden: setState(.showingHidden)
        case .showAll: setState(.showingAll)
        case .hide: setState(.showingShownOnly)
        case .openMenu: showMenu()
        case .openLayout: openLayoutPanel()
        case .closeLayout: layoutPanel.close()
        case .openItem(let id):
            guard let item = MenuBarWindowList.item(id) else { return }
            access(item)
        }
    }

    // MARK: Reading the menu bar

    /// The active menu bar: the one holding Barbarian's icon. Menu bar
    /// items' own windows are there.
    private func activeMenuBar(in windows: [MenuBarItem] = MenuBarWindowList.allWindows()) -> MenuBar? {
        guard let iconID = controlItems.icon.windowID else { return nil }
        return MenuBar(holding: { $0.windowID == iconID }, in: windows)
    }

    /// The display whose menu bar holds Barbarian's icon.
    var activeDisplay: MenuBarDisplay? {
        activeMenuBar()?.display
    }

    func currentLayout() -> MenuBarLayout? {
        guard let ids = controlItems.ids, let menuBar = activeMenuBar() else { return nil }
        return MenuBarLayout(items: menuBar.items, controls: ids, statusArea: menuBar.display.statusArea)
    }

    /// Captures the active menu bar's on-screen items for the items menu and
    /// the Arrange panel.
    func captureItemImages() {
        guard itemImages.isOn(), let items = activeMenuBar()?.items else { return }
        Task { await itemImages.capture(items) }
    }

    // MARK: Hiding and revealing

    func setState(_ newState: HidingState) {
        if newState != .showingShownOnly && state == .showingShownOnly {
            pointerLastInMenuBarAt = Date()
        }
        let revealsMore = newState.revealsMore(than: state)
        state = newState
        apply()
        if revealsMore { captureRevealedItems() }
    }

    /// Revealed items are on screen, so their images can be captured once
    /// they have been drawn.
    private func captureRevealedItems() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            captureItemImages()
        }
    }

    func toggle(_ target: HidingState) {
        setState(state == target ? .showingShownOnly : target)
    }

    private func apply() {
        controlItems.apply(state, layout: currentLayout())
    }

    /// Acts on a press of the icon and consumes it, as macOS's own items act
    /// on press. Left to AppKit, a click highlights the icon while pressed
    /// and clears it on release, which fights the highlight that shows a
    /// section is revealed and makes the icon flicker.
    private func handleIconPress(_ event: NSEvent) -> Bool {
        guard event.window != nil, event.window === controlItems.icon.button?.window else { return false }
        let wantsMenu = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        if wantsMenu {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            toggle(.showingAll)
        } else {
            toggle(.showingHidden)
        }
        return true
    }

    /// Pops the menu up from Barbarian's icon. `performClick` returns once
    /// the menu closes.
    func showMenu() {
        captureItemImages()
        let menu = ItemsMenu.make(layout: currentLayout(), controller: self)
        controlItems.icon.menu = menu
        controlItems.icon.button?.performClick(nil)
        controlItems.icon.menu = nil
        controlItems.highlightIcon(state)
    }

    func openSettings() {
        settingsWindow.show()
    }

    /// The screen whose menu bar holds Barbarian's icon.
    var iconScreen: NSScreen? {
        controlItems.icon.button?.window?.screen
    }

    func openLayoutPanel() {
        layoutPanel.show()
    }

    func access(_ item: MenuBarItem) {
        itemAccess.open(item)
    }

    func showMessage(_ text: String) {
        guard let button = controlItems.icon.button else { return }
        statusMessage.show(text, below: button)
    }

    private func clickedOutsideBarbarian() {
        guard state != .showingShownOnly, !isPinnedOpen, !Self.isInMenuBar(MenuBarDisplay.pointerLocation) else { return }
        setState(.showingShownOnly)
    }

    // MARK: Polling the pointer

    /// One timer drives hover-to-reveal and auto-rehide.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let now = Date()
        let pointer = MenuBarDisplay.pointerLocation
        if Self.isInMenuBar(pointer) { pointerLastInMenuBarAt = now }

        if state == .showingShownOnly {
            revealIfHovering(pointer: pointer, now: now)
            return
        }
        guard !itemAccess.isBusy else { return }
        let rehidePolicy = AutoRehidePolicy(delay: Preferences.shared.rehideDelay)
        let shouldRehide = rehidePolicy.shouldRehide(
            now: now,
            pointerLastInMenuBarAt: pointerLastInMenuBarAt,
            isMenuOpen: !MenuBarWindowList.openMenuOwners().isEmpty,
            isPinnedOpen: isPinnedOpen
        )
        if shouldRehide { setState(.showingShownOnly) }
    }

    /// Reveals the Hidden section when the pointer rests on the empty
    /// stretch of a menu bar left of the shown items: the visible part of the
    /// collapsed Hidden divider, between the app's menus and the items.
    private func revealIfHovering(pointer: CGPoint, now: Date) {
        let hoverDelay: TimeInterval = 0.4
        guard Preferences.shared.revealsOnHover, let region = hoverRegion(at: pointer), region.contains(pointer) else {
            hoverStartedAt = nil
            return
        }
        if let started = hoverStartedAt {
            if now.timeIntervalSince(started) >= hoverDelay {
                hoverStartedAt = nil
                setState(.showingHidden)
            }
        } else {
            hoverStartedAt = now
        }
    }

    /// The empty stretch of the menu bar under `pointer`. It starts at the
    /// notch, or on a display without one where the app's menus end, which
    /// only Accessibility can tell. The pointer may be in a menu bar holding
    /// copies of Barbarian's windows, so they are found by owner.
    private func hoverRegion(at pointer: CGPoint) -> CGRect? {
        guard let display = MenuBarDisplay.withMenuBar(containing: pointer) else { return nil }
        let windows = MenuBarWindowList.allWindows()
        let menuBar = MenuBar(display: display, windows: windows)
        guard
            let layout = MenuBarLayout(items: menuBar.items, barbarianPID: ProcessInfo.processInfo.processIdentifier, statusArea: display.statusArea),
            let dividerID = layout.windowID(of: .hidden),
            let divider = menuBar.items.first(where: { $0.windowID == dividerID })?.frame
        else {
            return nil
        }
        let left: CGFloat
        if display.hasNotch {
            left = display.statusArea.lowerBound
        } else {
            guard
                let active = activeMenuBar(in: windows)?.display,
                let appMenusWidth = AppMenus.width(onActiveDisplayAt: active.bounds.minX)
            else {
                return nil
            }
            left = display.bounds.minX + appMenusWidth
        }
        let region = CGRect(x: left, y: display.bounds.minY, width: divider.maxX - left, height: display.menuBarHeight)
        return region.width > 0 ? region : nil
    }

    static func isInMenuBar(_ point: CGPoint) -> Bool {
        MenuBarDisplay.withMenuBar(containing: point) != nil
    }

    // MARK: Hot keys

    func registerHotKeys() {
        suspendHotKeys()
        let preferences = Preferences.shared
        let bindings: [(Shortcut?, () -> Void)] = [
            (preferences.showHiddenShortcut, { [weak self] in self?.toggle(.showingHidden) }),
            (preferences.itemsMenuShortcut, { [weak self] in self?.showMenu() }),
        ]
        hotKeys = bindings.compactMap { shortcut, action in
            shortcut.flatMap { GlobalHotKey(keyCode: $0.keyCode, modifiers: $0.carbonModifiers, handler: action) }
        }
    }

    /// Stops the shortcuts while Settings records a new one, so typing the
    /// current shortcut records it instead of running it.
    func suspendHotKeys() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
    }
}
