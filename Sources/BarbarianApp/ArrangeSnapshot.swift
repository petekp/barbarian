import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// `Barbarian --render-arrange <file.png> [--lift <window ID> <index>] [--item-images]`
/// draws the Arrange window's strip for the current menu bar to a PNG,
/// without opening a window. `--lift` draws one item or divider mid-drag over
/// the gap it would open at `index` among the other entries. Items show their
/// app's icon unless `--item-images` captures their own images, which makes
/// macOS show a screen recording alert for this process.
enum ArrangeSnapshot {
    static func run(arguments: [String]) -> Int32 {
        guard let output = RenderCommand.outputURL(after: "--render-arrange", in: arguments, usage: "<file.png> [--lift <window ID> <index>] [--item-images]") else {
            return 1
        }
        guard let barbarian = RunningBarbarian(), let layout = barbarian.layout else {
            return RenderCommand.fail("Barbarian is not running, or its three status items were not found.")
        }
        var images: ItemImageCache?
        if arguments.contains("--item-images") {
            let cache = ItemImageCache()
            capture(barbarian.menuBar.items, into: cache)
            images = cache
        }
        let presentation = ItemPresentation(layout: layout, images: images)
        let widths = ArrangeContent.widths(of: layout, presentation: presentation)

        var drag: EntryDrag?
        if let lift = arguments.firstIndex(of: "--lift") {
            guard
                lift + 2 < arguments.count,
                let id = WindowID(arguments[lift + 1]),
                let entry = layout.entries.first(where: { $0.id == id }),
                let index = Int(arguments[lift + 2])
            else {
                return RenderCommand.fail("--lift takes a managed item's or divider's window ID and an index.")
            }
            drag = liftedDrag(of: entry, to: index, in: layout, widths: widths)
        }

        let content = ArrangeContent(layout: layout, pendingOrder: nil, drag: drag, presentation: presentation, widths: widths)
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(
            content: ArrangeCanvas(content: content, drag: drag, canDrag: true)
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage else { return RenderCommand.fail("Rendering failed.") }
        return RenderCommand.writePNG(NSBitmapImageRep(cgImage: image), to: output)
    }

    /// A drag whose entry hovers just off its target, as it would under the
    /// pointer.
    private static func liftedDrag(of entry: MenuBarLayout.Entry, to index: Int, in layout: MenuBarLayout, widths: [WindowID: CGFloat]) -> EntryDrag {
        let entries = layout.entries(inOrder: nil, moving: entry, to: index)
        let strip = ArrangeContent.strip(for: entries, widths: widths)
        let frame = entries.firstIndex(of: entry).map { strip.frames[$0] } ?? .zero
        let othersStrip = ArrangeContent.strip(for: layout.entries.filter { $0.id != entry.id }, widths: widths)
        return EntryDrag(entry: entry, pointerX: frame.midX + 12, grabOffsetX: 0, targetIndex: index, othersStrip: othersStrip)
    }

    /// Fills `images` before drawing, when this process has Screen
    /// Recording permission.
    private static func capture(_ items: [MenuBarItem], into images: ItemImageCache) {
        var isDone = false
        Task {
            await images.capture(items)
            isDone = true
        }
        while !isDone {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
