import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// `Barbarian --render-arrange <file.png> [--lift <window ID> <index>]` draws
/// the Arrange window's strip for the current menu bar to a PNG, without
/// opening a window. `--lift` draws one item or divider mid-drag over the gap
/// it would open at `index` among the other entries.
enum ArrangeSnapshot {

    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--render-arrange"), flag + 1 < arguments.count else {
            return fail("usage: Barbarian --render-arrange <file.png> [--lift <window ID> <index>]")
        }
        let output = URL(fileURLWithPath: arguments[flag + 1])
        guard
            let (items, display) = MenuBarWindowList.itemsInRunningBarbarianMenuBar(),
            let layout = MenuBarLayout(runningBarbarianIn: items)
        else {
            return fail("Barbarian is not running, or its three status items were not found.")
        }
        captureImages(of: items)
        let presentation = ItemPresentation(items: layout.entries.compactMap(\.item) + layout.systemItems)

        var drag: EntryDrag?
        if let lift = arguments.firstIndex(of: "--lift") {
            guard
                lift + 2 < arguments.count,
                let id = WindowID(arguments[lift + 1]),
                let entry = layout.entries.first(where: { $0.id == id }),
                let index = Int(arguments[lift + 2])
            else {
                return fail("--lift takes a managed item's or divider's window ID and an index.")
            }
            drag = liftedDrag(of: entry, to: index, in: layout, presentation: presentation, visibleStatusArea: display.statusArea)
        }

        let content = ArrangeContent(
            layout: layout,
            pendingOrder: nil,
            drag: drag,
            presentation: presentation,
            visibleStatusArea: display.statusArea
        )
        let canvas = ArrangeCanvas(content: content, presentation: presentation, drag: drag, canDrag: true)
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(
            content: canvas
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

    /// A drag whose entry hovers just off its target, as it would under the
    /// pointer.
    private static func liftedDrag(
        of entry: MenuBarLayout.Entry,
        to index: Int,
        in layout: MenuBarLayout,
        presentation: ItemPresentation,
        visibleStatusArea: ClosedRange<CGFloat>
    ) -> EntryDrag {
        let placeholder = EntryDrag(entry: entry, pointer: .zero, grabOffset: .zero, targetIndex: index)
        let content = ArrangeContent(
            layout: layout,
            pendingOrder: nil,
            drag: placeholder,
            presentation: presentation,
            visibleStatusArea: visibleStatusArea
        )
        let frame = content.entries.firstIndex(of: entry).map { content.strip.frames[$0] } ?? .zero
        return EntryDrag(entry: entry, pointer: CGPoint(x: frame.midX + 12, y: frame.midY), grabOffset: .zero, targetIndex: index)
    }

    /// Fills `ItemImageCache` before drawing, when this process has Screen
    /// Recording permission.
    private static func captureImages(of items: [MenuBarItem]) {
        var isDone = false
        Task {
            await ItemImageCache.shared.capture(items)
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
