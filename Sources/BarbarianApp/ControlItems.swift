import AppKit
import BarbarianCore

/// Barbarian's own status items: its icon and the two dividers.
///
/// A divider hides the items on its left by stretching to a length no menu
/// bar can fit. macOS then lays out the dividers' left neighbors off screen.
final class ControlItems {
    let icon: NSStatusItem
    private let dividers: [Divider: NSStatusItem]

    private static let collapsedDividerLength: CGFloat = 10_000
    private static let iconAutosaveName = "BarbarianIcon"

    init() {
        Self.placeIconRightmostOnFirstLaunch()
        icon = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        icon.autosaveName = Self.iconAutosaveName
        icon.button?.image = Self.symbol("line.3.horizontal.decrease", description: "Barbarian")

        // A status item without a saved position appears at the left end of
        // the status items, so on first launch both dividers start left of
        // every item and nothing is hidden. Creating Hidden first leaves
        // Always Hidden furthest left.
        var dividers: [Divider: NSStatusItem] = [:]
        for divider in [Divider.hidden, .alwaysHidden] {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Barbarian\(divider.rawValue.capitalizedFirst)Divider"
            dividers[divider] = item
        }
        self.dividers = dividers
    }

    var ids: ControlItemIDs? {
        guard
            let icon = icon.windowID,
            let hidden = dividers[.hidden]?.windowID,
            let alwaysHidden = dividers[.alwaysHidden]?.windowID
        else {
            return nil
        }
        return ControlItemIDs(icon: icon, hiddenDivider: hidden, alwaysHiddenDivider: alwaysHidden)
    }

    /// Collapses or expands each divider for `state`. `layout` says which
    /// divider currently plays which role; see `MenuBarLayout`.
    func apply(_ state: HidingState, layout: MenuBarLayout?) {
        for (identity, item) in dividers {
            guard let button = item.button else { continue }
            let divider = layout?.role(of: item.windowID) ?? identity
            if state.isCollapsed(divider) {
                item.length = Self.collapsedDividerLength
                button.image = nil
                button.cell?.isEnabled = false
                button.isHighlighted = false
            } else {
                item.length = NSStatusItem.variableLength
                button.cell?.isEnabled = true
                button.image = Self.dividerImage(divider)
            }
        }
    }

    /// Ice and other menu bar managers seed this key so their icon starts
    /// next to the system items. Position 0 is the right end of the items
    /// third-party apps can occupy.
    private static func placeIconRightmostOnFirstLaunch() {
        let key = "NSStatusItem Preferred Position \(iconAutosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(0, forKey: key)
        }
    }

    private static func dividerImage(_ divider: Divider) -> NSImage? {
        switch divider {
        case .hidden: symbol("chevron.compact.left", description: "Hidden items divider")
        case .alwaysHidden: symbol("chevron.left.2", description: "Always Hidden items divider")
        }
    }

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}

extension NSStatusItem {
    var windowID: WindowID? {
        guard let number = button?.window?.windowNumber, number > 0 else { return nil }
        return WindowID(number)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
