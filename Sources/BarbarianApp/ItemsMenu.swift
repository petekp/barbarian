import AppKit
import BarbarianCore
import BarbarianSystem

/// The menu behind Barbarian's icon: every managed item by section, so an
/// item that is hidden or does not fit is still one click or keystroke away.
/// Typing an item's name selects it, which NSMenu provides.
enum ItemsMenu {
    static func make(layout: MenuBarLayout?, controller: AppController) -> NSMenu {
        let menu = NSMenu()
        let target = MenuTarget.shared
        target.controller = controller

        if let layout {
            let presentation = ItemPresentation(items: layout.entries.compactMap(\.item) + layout.unplacedItems)
            let visibleStatusArea = AppController.visibleStatusArea()
            let isOffered = { (item: MenuBarItem) in !layout.isHiddenByItsApp(item, visibleStatusArea: visibleStatusArea) }
            for section in [MenuBarSection.shown, .hidden, .alwaysHidden] {
                let items = layout.items(in: section).filter(isOffered)
                addSection(section.title, items: items, presentation: presentation, to: menu, target: target)
            }
            addSection("Not in the Menu Bar", items: layout.unplacedItems, presentation: presentation, to: menu, target: target)
        }

        if !AccessibilityPermission.isGranted {
            menu.addItem(.separator())
            let grant = NSMenuItem(title: "Allow Accessibility to Open Hidden Items…", action: #selector(MenuTarget.grantAccessibility), keyEquivalent: "")
            grant.target = target
            menu.addItem(grant)
        }
        if !ScreenRecordingPermission.isGranted {
            if AccessibilityPermission.isGranted { menu.addItem(.separator()) }
            let grant = NSMenuItem(title: "Show Items' Own Icons…", action: #selector(MenuTarget.grantScreenRecording), keyEquivalent: "")
            grant.target = target
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        addCommand("Show Hidden Items", #selector(MenuTarget.showHidden), to: menu, target: target, checked: controller.state == .showingHidden)
        addCommand("Show All Items", #selector(MenuTarget.showAll), to: menu, target: target, checked: controller.state == .showingAll)
        addCommand("Arrange Menu Bar…", #selector(MenuTarget.arrange), to: menu, target: target)
        menu.addItem(.separator())
        addCommand("Open at Login", #selector(MenuTarget.toggleLaunchAtLogin), to: menu, target: target, checked: LaunchAtLogin.isEnabled)
        addCommand("Quit Barbarian", #selector(NSApplication.terminate(_:)), to: menu, target: NSApp, keyEquivalent: "q")
        return menu
    }

    private static func addSection(
        _ title: String,
        items: [MenuBarItem],
        presentation: ItemPresentation,
        to menu: NSMenu,
        target: MenuTarget
    ) {
        guard !items.isEmpty else { return }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem.sectionHeader(title: title))
        for item in items {
            let menuItem = NSMenuItem(title: presentation.name(of: item), action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
            menuItem.image = presentation.icon(of: item)
            menuItem.representedObject = item
            menuItem.target = target
            menu.addItem(menuItem)
        }
    }

    private static func addCommand(
        _ title: String,
        _ action: Selector,
        to menu: NSMenu,
        target: AnyObject,
        checked: Bool = false,
        keyEquivalent: String = ""
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.state = checked ? .on : .off
        menu.addItem(item)
    }
}

/// NSMenuItem actions need an Objective-C target.
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    weak var controller: AppController?

    @objc func open(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        controller?.access(item)
    }

    @objc func showHidden() { controller?.toggle(.showingHidden) }
    @objc func showAll() { controller?.toggle(.showingAll) }
    @objc func arrange() { controller?.openLayoutWindow() }

    @objc func grantAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    @objc func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc func grantScreenRecording() {
        ScreenRecordingPermission.request()
        ScreenRecordingPermission.openSettings()
    }
}
