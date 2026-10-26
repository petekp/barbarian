import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// `Barbarian --render-arrange <file.png> [--lift <window ID> <section> <index>]`
/// draws the Arrange window's items for the current menu bar to a PNG,
/// without opening a window. `--lift` draws one item mid-drag over the gap it
/// would open at `index` in `section` (shown, hidden or alwaysHidden).
enum ArrangeSnapshot {
    private static let width: CGFloat = 600

    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--render-arrange"), flag + 1 < arguments.count else {
            return fail("usage: Barbarian --render-arrange <file.png> [--lift <window ID> <section> <index>]")
        }
        let output = URL(fileURLWithPath: arguments[flag + 1])
        captureItemImages()
        let items = MenuBarWindowList.items()
        guard let layout = MenuBarLayout(runningBarbarianIn: items) else {
            return fail("Barbarian is not running, or its three status items were not found.")
        }

        var drag: ItemDrag?
        if let lift = arguments.firstIndex(of: "--lift") {
            guard
                lift + 3 < arguments.count,
                let id = WindowID(arguments[lift + 1]),
                let item = layout.entries.compactMap(\.item).first(where: { $0.windowID == id }),
                let section = MenuBarSection(rawValue: arguments[lift + 2]),
                let index = Int(arguments[lift + 3])
            else {
                return fail("--lift takes a managed item's window ID, a section and an index.")
            }
            drag = liftedDrag(of: item, to: .init(section: section, index: index), in: layout)
        }

        let visibleStatusArea = AppController.visibleStatusArea()
        let canvas = ArrangeCanvas(
            sections: ArrangeSection.sections(from: layout, pendingOrder: nil, drag: drag),
            presentation: ItemPresentation(items: layout.entries.compactMap(\.item) + layout.unplacedItems),
            drag: drag,
            canDrag: true,
            note: { ArrangeSection.offScreenNote(for: $0, in: $1, layout: layout, visibleStatusArea: visibleStatusArea) },
            initialWidth: width
        )
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(
            content: canvas
                .frame(width: width)
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = 2
        guard
            let image = renderer.cgImage,
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            return fail("Rendering failed.")
        }
        do {
            try png.write(to: output)
        } catch {
            return fail("Could not write \(output.path): \(error.localizedDescription)")
        }
        return 0
    }

    /// A drag whose item hovers just off its target slot, as it would under
    /// the pointer.
    private static func liftedDrag(of item: MenuBarItem, to target: ItemDrag.Target, in layout: MenuBarLayout) -> ItemDrag {
        let placeholder = ItemDrag(item: item, pointer: .zero, grabOffset: .zero, target: target)
        let sections = ArrangeSection.sections(from: layout, pendingOrder: nil, drag: placeholder)
        let grid = ArrangeGrid(width: width, slotCounts: sections.map(\.items.count), metrics: .arrange)
        var slot = CGRect.zero
        for (sectionIndex, section) in sections.enumerated() {
            if let index = section.items.firstIndex(where: { $0.windowID == item.windowID }) {
                slot = grid.sections[sectionIndex].slotFrames[index]
            }
        }
        return ItemDrag(item: item, pointer: CGPoint(x: slot.midX + 14, y: slot.midY + 10), grabOffset: .zero, target: target)
    }

    /// Fills `ItemImageCache` before drawing, when this process has Screen
    /// Recording permission.
    private static func captureItemImages() {
        _ = NSApplication.shared
        var isDone = false
        Task {
            await ItemImageCache.shared.captureNow()
            isDone = true
        }
        while !isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}
