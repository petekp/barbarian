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
    private unowned let controller: AppController
    private let model: LayoutEditorModel
    private var panel: NSPanel?
    private var hosting: NSHostingController<LayoutView>?
    private var dimmingWindows: [NSWindow] = []
    private var screen: NSScreen?
    /// Waits for the revealed menu bar to settle, then shows the panel.
    private var opening: Task<Void, Never>?

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
        guard !isOpen, opening == nil, let screen = controller.iconScreen ?? NSScreen.main else { return }
        self.screen = screen
        model.takeBaseline()
        controller.isPinnedOpen = true
        opening = Task {
            await model.loadSettledLayout()
            guard !Task.isCancelled else { return }
            opening = nil
            present()
            model.startRefreshing()
        }
    }

    private func present() {
        guard let screen else { return }
        let view = LayoutView(model: model, maximumWidth: screen.frame.width - 2 * Self.margin, onClose: { [weak self] in self?.close() })
        let panel: NSPanel
        if let existing = self.panel, let hosting {
            panel = existing
            hosting.rootView = view
        } else {
            panel = makePanel(showing: view)
        }
        pin(panel)

        showDimming(on: NSScreen.screens)
        panel.alphaValue = 0
        panel.bringForward()
        fade([panel] + dimmingWindows, to: 1)
    }

    func close() {
        guard isOpen || opening != nil else { return }
        opening?.cancel()
        opening = nil
        model.stopRefreshing()
        controller.isPinnedOpen = false
        let windows = [panel].compactMap { $0 } + dimmingWindows
        dimmingWindows = []
        fade(windows, to: 0) {
            windows.forEach { $0.orderOut(nil) }
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        pin(panel)
    }

    private func makePanel(showing view: LayoutView) -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = Self.panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    /// Keeps the panel's top right corner just below the menu bar at the
    /// screen's right edge as its size follows the strip.
    private func pin(_ panel: NSPanel) {
        guard let screen else { return }
        let size = panel.frame.size
        let menuBarBottom = screen.frame.maxY - screen.menuBarHeight
        panel.setFrameOrigin(NSPoint(x: screen.frame.maxX - Self.margin - size.width, y: menuBarBottom - Self.margin - size.height))
        panel.invalidateShadow()
    }

    private func showDimming(on screens: [NSScreen]) {
        dimmingWindows = screens.map { screen in
            var frame = screen.frame
            frame.size.height -= screen.menuBarHeight
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

    private func fade(_ windows: [NSWindow], to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            windows.forEach { $0.animator().alphaValue = alpha }
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
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
