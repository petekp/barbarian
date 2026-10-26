import Foundation
import BarbarianCore
import BarbarianSystem

/// `Barbarian --print-items`: one line per item in the active menu bar, left
/// to right, for checking positions from a terminal while Barbarian runs.
enum ItemReport {
    static func print() {
        guard let barbarian = RunningBarbarian() else {
            FileHandle.standardError.write(Data("Barbarian is not running.\n".utf8))
            return
        }
        let items = barbarian.menuBar.items
        let layout = barbarian.layout
        let accessibilityLabels = AccessibilityItemLabels.labels(for: items)
        for item in items.sorted(by: { ($0.frame.minX, $0.windowID) < ($1.frame.minX, $1.windowID) }) {
            let section = layout?.section(of: item.windowID)?.rawValue ?? (layout?.controls.icon == item.windowID ? "icon" : "-")
            let fields = [
                "\(item.windowID)",
                item.ownerName,
                item.title ?? "-",
                accessibilityLabels[item.windowID]?.name ?? "-",
                "x=\(Int(item.frame.minX))",
                "w=\(Int(item.frame.width))",
                item.isOnScreen ? "on" : "off",
                section,
            ]
            Swift.print(fields.joined(separator: "\t"))
        }
    }
}

/// The running Barbarian's menu bar as a separate process sees it. Its icon
/// window is the one titled with its autosave name, which needs Screen
/// Recording, as the terminal running these commands has.
struct RunningBarbarian {
    let menuBar: MenuBar
    let layout: MenuBarLayout?

    init?() {
        let windows = MenuBarWindowList.allWindows()
        guard
            let icon = windows.first(where: { $0.ownerName == "Barbarian" && $0.title == ControlItems.iconAutosaveName }),
            let menuBar = MenuBar(holding: { $0.windowID == icon.windowID }, in: windows)
        else {
            return nil
        }
        self.menuBar = menuBar
        layout = MenuBarLayout(items: menuBar.items, barbarianPID: icon.ownerPID, statusArea: menuBar.display.statusArea)
    }
}
