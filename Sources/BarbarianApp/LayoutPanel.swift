import AppKit
import SwiftUI

/// The Arrange Menu Bar panel: the managed part of the menu bar as one strip,
/// left to right, with both dividers. Dragging an item or a divider opens a
/// gap where it will land, and dropping it moves the real one there.
///
/// It opens at the top right of the display that holds Barbarian's icon,
/// just below the menu bar, and dims every display below the menu bar while
/// open. A click on the dimmed area, Escape or the close button closes it.
final class LayoutPanel: NSObject, NSWindowDelegate {
    static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    private unowned let controller: AppController
    private let model: LayoutEditorModel
    private var panel: NSPanel?
    private var dimmingWindows: [NSWindow] = []
    private var screen: NSScreen?

    /// Space between the panel and the screen's right edge and the menu bar.
    private static let margin: CGFloat = 8
    private static let fadeDuration: TimeInterval = 0.18
    private static let dimming: CGFloat = 0.35
    private static let dimmingLevel = NSWindow.Level.modalPanel
    private static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)

    init(controller: AppController) {
        self.controller = controller
        self.model = LayoutEditorModel(controller: controller)
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func show() {
        guard let screen = controller.iconScreen ?? NSScreen.main else { return }
        self.screen = screen
        controller.isPinnedOpen = true
        model.startRefreshing()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let maximumCanvasWidth = screen.frame.width - 2 * Self.margin - 36
        (panel.contentViewController as? NSHostingController<LayoutView>)?.rootView =
            LayoutView(model: model, maximumCanvasWidth: maximumCanvasWidth, onClose: { [weak self] in self?.close() })
        pin(panel)

        showDimming()
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        fade(in: [panel] + dimmingWindows)
    }

    func close() {
        guard isOpen else { return }
        model.stopRefreshing()
        controller.isPinnedOpen = false
        let windows = [panel].compactMap { $0 } + dimmingWindows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { windows.forEach { $0.orderOut(nil) } }
        }
        dimmingWindows = []
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        pin(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = Self.panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: LayoutView(model: model, maximumCanvasWidth: 1000, onClose: {}))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        return panel
    }

    /// Keeps the panel's top right corner just below the menu bar at the
    /// screen's right edge as its size follows the strip.
    private func pin(_ panel: NSPanel) {
        guard let screen else { return }
        let size = panel.frame.size
        let menuBarBottom = screen.visibleFrame.maxY
        panel.setFrameOrigin(NSPoint(x: screen.frame.maxX - Self.margin - size.width, y: menuBarBottom - Self.margin - size.height))
        panel.invalidateShadow()
    }

    private func showDimming() {
        dimmingWindows.forEach { $0.orderOut(nil) }
        dimmingWindows = NSScreen.screens.map { screen in
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            var frame = screen.frame
            frame.size.height -= menuBarHeight
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(Self.dimming)
            window.level = Self.dimmingLevel
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = ClickView { [weak self] in self?.close() }
            window.alphaValue = 0
            window.orderFrontRegardless()
            return window
        }
    }

    private func fade(in windows: [NSWindow]) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }
}

/// A borderless panel can't become key on its own, and the panel needs key
/// status for Escape to close it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ClickView: NSView {
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
