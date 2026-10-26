import Foundation
import BarbarianCore

/// `Barbarian --print-items`: one line per menu bar item, left to right,
/// for checking positions from a terminal while Barbarian runs.
enum ItemReport {
    static func print(_ items: [MenuBarItem]) {
        let barbarianWindows = items
            .filter { $0.ownerName == "Barbarian" }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.windowID)
        let layout: MenuBarLayout? = barbarianWindows.count == 3
            ? MenuBarLayout(
                items: items,
                controls: ControlItemIDs(
                    icon: barbarianWindows[2],
                    hiddenDivider: barbarianWindows[1],
                    alwaysHiddenDivider: barbarianWindows[0]
                )
            )
            : nil

        for item in items.sorted(by: { ($0.frame.minX, $0.windowID) < ($1.frame.minX, $1.windowID) }) {
            let section = layout?.section(of: item.windowID)?.rawValue ?? (layout?.controls.icon == item.windowID ? "icon" : "-")
            let fields = [
                "\(item.windowID)",
                item.ownerName,
                item.title ?? "-",
                "x=\(Int(item.frame.minX))",
                "w=\(Int(item.frame.width))",
                item.isOnScreen ? "on" : "off",
                section,
            ]
            Swift.print(fields.joined(separator: "\t"))
        }
    }
}
