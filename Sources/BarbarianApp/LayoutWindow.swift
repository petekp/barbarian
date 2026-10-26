import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// The Arrange Menu Bar window: one row per section, items in menu bar
/// order. Dragging an item onto another drops it to that item's left.
/// Dragging it onto a row's empty space makes it the row's rightmost item.
final class LayoutWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private let model: LayoutEditorModel
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
        self.model = LayoutEditorModel(controller: controller)
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        controller.isPinnedOpen = true
        model.startRefreshing()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // macOS can refuse activation to a background app, as when a
        // terminal command opens this window. The window still comes forward.
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRefreshing()
        controller.isPinnedOpen = false
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Arrange Menu Bar"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LayoutView(model: model))
        window.center()
        window.delegate = self
        return window
    }
}

@Observable
final class LayoutEditorModel {
    private(set) var layout: MenuBarLayout?
    private(set) var presentation = ItemPresentation(items: [])
    private(set) var isMoving = false
    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    var errorMessage: String?

    @ObservationIgnored private unowned let controller: AppController
    @ObservationIgnored private var refreshTimer: Timer?

    init(controller: AppController) {
        self.controller = controller
    }

    func startRefreshing() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        accessibilityGranted = AccessibilityPermission.isGranted
        guard !isMoving else { return }
        let latest = controller.currentLayout()
        guard latest != layout else { return }
        layout = latest
        presentation = ItemPresentation(items: (latest?.entries.compactMap(\.item) ?? []) + (latest?.unplacedItems ?? []))
    }

    func drop(_ itemID: WindowID, before neighborID: WindowID) {
        perform(itemID) { $0.destination(placing: itemID, before: neighborID) }
    }

    func drop(_ itemID: WindowID, appendingTo section: MenuBarSection) {
        perform(itemID) { $0.destination(appending: itemID, to: section) }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    private func perform(_ itemID: WindowID, destination: (MenuBarLayout) -> MoveDestination?) {
        guard
            accessibilityGranted, !isMoving,
            let layout = controller.currentLayout(),
            let item = MenuBarWindowList.items().first(where: { $0.windowID == itemID }),
            let destination = destination(layout)
        else {
            return
        }
        isMoving = true
        Task {
            defer {
                isMoving = false
                refresh()
            }
            do {
                try await MenuBarItemEvents.move(itemID, ownerPID: item.ownerPID, to: destination)
                errorMessage = nil
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }
}

struct LayoutView: View {
    let model: LayoutEditorModel

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.accessibilityGranted {
                AccessibilityBanner(onAllow: model.requestAccessibility)
            }
            ForEach([MenuBarSection.shown, .hidden, .alwaysHidden], id: \.self) { section in
                SectionRow(
                    title: section.title,
                    items: model.layout?.items(in: section) ?? [],
                    presentation: model.presentation,
                    isEnabled: model.accessibilityGranted && !model.isMoving,
                    onDropBefore: model.drop(_:before:),
                    onAppend: { model.drop($0, appendingTo: section) }
                )
            }
            if let unplaced = model.layout?.unplacedItems, !unplaced.isEmpty {
                SectionRow(
                    title: "Not in the Menu Bar",
                    items: unplaced,
                    presentation: model.presentation,
                    isEnabled: false,
                    onDropBefore: { _, _ in },
                    onAppend: { _ in }
                )
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Spacer(minLength: 0)
            Text("You can also hold ⌘ and drag icons in the menu bar itself. Icons left of the ‹ divider are hidden.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AccessibilityBanner: View {
    let onAllow: () -> Void

    var body: some View {
        HStack {
            Text("Barbarian needs Accessibility permission to move items from this window.")
            Spacer()
            Button("Open Settings", action: onAllow)
        }
        .padding(10)
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SectionRow: View {
    let title: String
    let items: [MenuBarItem]
    let presentation: ItemPresentation
    let isEnabled: Bool
    let onDropBefore: (WindowID, WindowID) -> Void
    let onAppend: (WindowID) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        ItemChip(item: item, presentation: presentation)
                            .draggable(String(item.windowID))
                            .dropDestination(for: String.self) { ids, _ in
                                guard isEnabled, let id = ids.first.flatMap(WindowID.init) else { return false }
                                onDropBefore(id, item.windowID)
                                return true
                            }
                    }
                    if items.isEmpty {
                        Text("Drop items here").foregroundStyle(.tertiary).padding(.horizontal, 8)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .dropDestination(for: String.self) { ids, _ in
                guard isEnabled, let id = ids.first.flatMap(WindowID.init) else { return false }
                onAppend(id)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

private struct ItemChip: View {
    let item: MenuBarItem
    let presentation: ItemPresentation

    var body: some View {
        VStack(spacing: 3) {
            if let icon = presentation.icon(of: item, size: 28) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "questionmark.square.dashed").font(.title2)
            }
            Text(presentation.name(of: item))
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 68)
        }
        .padding(4)
        .opacity(item.isOnScreen ? 1 : 0.55)
        .help(item.isOnScreen ? presentation.name(of: item) : "\(presentation.name(of: item)) is off screen")
    }
}
