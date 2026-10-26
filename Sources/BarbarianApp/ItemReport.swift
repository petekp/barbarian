import Foundation
import BarbarianCore
import BarbarianSystem

/// `Barbarian --print-items`: one line per menu bar item, left to right,
/// for checking positions from a terminal while Barbarian runs.
enum ItemReport {
    static func print(_ items: [MenuBarItem]) {
        let layout = MenuBarLayout(runningBarbarianIn: items)

        let accessibilityNames = AccessibilityItemNames.names(for: items)
        for item in items.sorted(by: { ($0.frame.minX, $0.windowID) < ($1.frame.minX, $1.windowID) }) {
            let section = layout?.section(of: item.windowID)?.rawValue ?? (layout?.controls.icon == item.windowID ? "icon" : "-")
            let fields = [
                "\(item.windowID)",
                item.ownerName,
                item.title ?? "-",
                accessibilityNames[item.windowID] ?? "-",
                "x=\(Int(item.frame.minX))",
                "w=\(Int(item.frame.width))",
                item.isOnScreen ? "on" : "off",
                section,
            ]
            Swift.print(fields.joined(separator: "\t"))
        }
    }
}

extension MenuBarLayout {
    /// The layout read without knowing Barbarian's control items' IDs, as a
    /// separate process must, and as Barbarian must for a menu bar that holds
    /// copies of its windows. Barbarian's three windows are, left to right,
    /// the Always Hidden divider, the Hidden divider and the icon.
    init?(runningBarbarianIn items: [MenuBarItem]) {
        let barbarianWindows = items
            .filter { $0.ownerName == "Barbarian" }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.windowID)
        guard barbarianWindows.count == 3 else { return nil }
        self.init(
            items: items,
            controls: ControlItemIDs(
                icon: barbarianWindows[2],
                hiddenDivider: barbarianWindows[1],
                alwaysHiddenDivider: barbarianWindows[0]
            )
        )
    }
}
