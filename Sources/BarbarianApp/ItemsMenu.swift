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
            let presentation = ItemPresentation(layout: layout, images: controller.itemImages)
            var sections: [(title: String, items: [MenuBarItem])] = [MenuBarSection.shown, .hidden, .alwaysHidden].map { section in
                (section.title, layout.items(in: section).filter { !layout.isNotDrawn($0) })
            }
            sections.append(("Not in the Menu Bar", layout.unplacedItems))
            let icons = IconColumn(items: sections.flatMap(\.items), presentation: presentation)
            for (title, items) in sections {
                addSection(title, items: items, presentation: presentation, icons: icons, to: menu, target: target)
            }
        }

        if !AccessibilityPermission.isGranted {
            menu.addItem(.separator())
            let grant = NSMenuItem(title: "Allow Accessibility to Open Hidden Items…", action: #selector(MenuTarget.grantAccessibility), keyEquivalent: "")
            grant.target = target
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        addCommand("Show Hidden Items", #selector(MenuTarget.showHidden), to: menu, target: target, checked: controller.state == .showingHidden)
        addCommand("Show All Items", #selector(MenuTarget.showAll), to: menu, target: target, checked: controller.state == .showingAll)
        addCommand("Arrange Menu Bar…", #selector(MenuTarget.arrange), to: menu, target: target)
        menu.addItem(.separator())
        addCommand("Settings…", #selector(MenuTarget.openSettings), to: menu, target: target, keyEquivalent: ",")
        addCommand("About Barbarian", #selector(MenuTarget.showAbout), to: menu, target: target)
        addCommand("Quit Barbarian", #selector(NSApplication.terminate(_:)), to: menu, target: NSApp, keyEquivalent: "q")
        return menu
    }

    private static func addSection(
        _ title: String,
        items: [MenuBarItem],
        presentation: ItemPresentation,
        icons: IconColumn,
        to menu: NSMenu,
        target: MenuTarget
    ) {
        guard !items.isEmpty else { return }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem.sectionHeader(title: title))
        for item in items {
            let menuItem = NSMenuItem(title: presentation.name(of: item), action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
            menuItem.image = icons.image(of: item)
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

/// Items' icons drawn at one width, so the names beside them line up. The
/// width is the widest icon's, up to `maximumWidth`. A wider icon is scaled
/// down to fit, and narrower ones are centered.
private struct IconColumn {
    private static let maximumWidth: CGFloat = 36
    private let icons: [WindowID: NSImage]
    private let width: CGFloat

    init(items: [MenuBarItem], presentation: ItemPresentation) {
        icons = Dictionary(items.compactMap { item in presentation.icon(of: item).map { (item.windowID, $0) } }, uniquingKeysWith: { first, _ in first })
        width = min(Self.maximumWidth, icons.values.map(\.size.width).max() ?? 0)
    }

    func image(of item: MenuBarItem) -> NSImage? {
        guard let icon = icons[item.windowID] else { return nil }
        let scale = min(1, width / icon.size.width)
        let iconSize = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
        let image = NSImage(size: NSSize(width: width, height: iconSize.height), flipped: false) { bounds in
            icon.draw(in: NSRect(x: (bounds.width - iconSize.width) / 2, y: 0, width: iconSize.width, height: iconSize.height))
            return true
        }
        image.isTemplate = icon.isTemplate
        return image
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

    @objc func grantAccessibility() { AccessibilityPermission.requestAndOpenSettings() }

    @objc func openSettings() { controller?.openSettings() }

    @objc func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
