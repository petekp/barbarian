import AppKit
import BarbarianCore
import BarbarianSystem
import Carbon.HIToolbox

/// Owns Barbarian's status items and decides what the menu bar shows.
final class AppController: NSObject, NSApplicationDelegate {
    private var controlItems: ControlItems!
    private(set) var state: HidingState = .showingShownOnly
    private var rehidePolicy = AutoRehidePolicy()
    private var pointerLastInMenuBarAt = Date()
    private var hoverStartedAt: Date?
    private var pollTimer: Timer?
    private var mouseDownMonitor: Any?
    private var hotKeys: [GlobalHotKey] = []
    private var commandObserver: NSObjectProtocol?
    private lazy var itemAccess = ItemAccess(controller: self)
    private lazy var layoutWindow = LayoutWindowController(controller: self)

    /// Keeps every section on screen while the layout window is open.
    var isPinnedOpen = false {
        didSet { setState(isPinnedOpen ? .showingAll : .showingShownOnly) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlItems = ControlItems()
        if let button = controlItems.icon.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        apply()
        startPolling()
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutsideBarbarian() }
        }
        registerHotKeys()
        commandObserver = CommandChannel.listen { [weak self] in self?.perform($0) }
    }

    private func perform(_ command: Command) {
        switch command {
        case .showHidden: setState(.showingHidden)
        case .showAll: setState(.showingAll)
        case .hide: setState(.showingShownOnly)
        case .openMenu: showMenu()
        case .openLayout: openLayoutWindow()
        case .closeLayout: layoutWindow.close()
        case .openItem(let id):
            guard let item = MenuBarWindowList.items().first(where: { $0.windowID == id }) else { return }
            access(item)
        }
    }

    // MARK: Reading the menu bar

    func currentLayout() -> MenuBarLayout? {
        guard let ids = controlItems.ids else { return nil }
        return MenuBarLayout(items: MenuBarWindowList.items(), controls: ids)
    }

    // MARK: Hiding and revealing

    func setState(_ newState: HidingState) {
        if newState != .showingShownOnly && state == .showingShownOnly {
            pointerLastInMenuBarAt = Date()
        }
        state = newState
        apply()
    }

    func toggle(_ target: HidingState) {
        setState(state == target ? .showingShownOnly : target)
    }

    private func apply() {
        controlItems.apply(state, layout: currentLayout())
    }

    @objc private func iconClicked() {
        guard let event = NSApp.currentEvent else { return }
        let wantsMenu = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if wantsMenu {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            toggle(.showingAll)
        } else {
            toggle(.showingHidden)
        }
    }

    /// Pops the menu up from Barbarian's icon. `performClick` returns once
    /// the menu closes.
    func showMenu() {
        let menu = ItemsMenu.make(layout: currentLayout(), controller: self)
        controlItems.icon.menu = menu
        controlItems.icon.button?.performClick(nil)
        controlItems.icon.menu = nil
    }

    func openLayoutWindow() {
        layoutWindow.show()
    }

    func access(_ item: MenuBarItem) {
        itemAccess.open(item)
    }

    private func clickedOutsideBarbarian() {
        guard state != .showingShownOnly, !isPinnedOpen, !Self.isPointerInMenuBar() else { return }
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
        let pointerInMenuBar = Self.isPointerInMenuBar()
        if pointerInMenuBar { pointerLastInMenuBarAt = now }

        if state == .showingShownOnly {
            revealIfHovering(now: now)
            return
        }
        guard !itemAccess.isBusy else { return }
        let shouldRehide = rehidePolicy.shouldRehide(
            now: now,
            pointerLastInMenuBarAt: pointerLastInMenuBarAt,
            isMenuOpen: !MenuBarWindowList.openMenuOwners().isEmpty,
            isPinnedOpen: isPinnedOpen
        )
        if shouldRehide { setState(.showingShownOnly) }
    }

    /// Reveals the Hidden section when the pointer rests on the visible part
    /// of the collapsed Hidden divider, which is the empty stretch of menu
    /// bar left of the shown items.
    private func revealIfHovering(now: Date) {
        let hoverDelay: TimeInterval = 0.4
        guard Self.isPointerInMenuBar(), let divider = hiddenDividerVisibleFrame() else {
            hoverStartedAt = nil
            return
        }
        let pointer = Self.pointerLocationInWindowListCoordinates()
        guard divider.contains(pointer) else {
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

    private func hiddenDividerVisibleFrame() -> CGRect? {
        guard
            let layout = currentLayout(),
            let dividerID = layout.windowID(of: .hidden),
            let frame = MenuBarWindowList.frame(of: dividerID)
        else {
            return nil
        }
        let statusArea = Self.visibleStatusArea()
        let statusAreaRect = CGRect(x: statusArea.lowerBound, y: 0, width: statusArea.upperBound - statusArea.lowerBound, height: frame.height)
        let visible = frame.intersection(statusAreaRect)
        return visible.isEmpty ? nil : visible
    }

    /// The display whose top-left corner is the origin of window-list
    /// coordinates. `NSScreen.main` is the display with keyboard focus instead.
    static var primaryScreen: NSScreen? { NSScreen.screens.first }

    /// The x range where status items can appear on the primary display:
    /// right of the notch when there is one.
    static func visibleStatusArea() -> ClosedRange<CGFloat> {
        guard let screen = primaryScreen else { return 0...0 }
        let leftEdge = screen.auxiliaryTopRightArea?.minX ?? 0
        return leftEdge...screen.frame.width
    }

    static func isPointerInMenuBar() -> Bool {
        guard let screen = primaryScreen else { return false }
        let pointer = NSEvent.mouseLocation
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return screen.frame.contains(pointer) && pointer.y >= screen.frame.maxY - max(menuBarHeight, 24)
    }

    /// The pointer in window-list coordinates: origin at the top left of the
    /// main display, y growing downward.
    static func pointerLocationInWindowListCoordinates() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    // MARK: Hot keys

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey | cmdKey
        let bindings: [(Int, () -> Void)] = [
            (kVK_ANSI_B, { [weak self] in self?.toggle(.showingHidden) }),
            (kVK_ANSI_M, { [weak self] in self?.showMenu() }),
        ]
        hotKeys = bindings.compactMap { GlobalHotKey(keyCode: $0.0, modifiers: modifiers, handler: $0.1) }
    }
}
