import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// The Arrange Menu Bar window: one section per row group, items in menu bar
/// order, left to right. Dragging an item opens a gap where it will land, and
/// dropping it moves the real item there.
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

/// An item being dragged in the Arrange window.
struct ItemDrag: Equatable {
    struct Target: Equatable {
        var section: MenuBarSection
        var index: Int
    }

    let item: MenuBarItem
    /// The pointer, in the canvas's coordinates.
    var pointer: CGPoint
    /// The pointer's offset from the item's center when the drag began, so
    /// the item stays where it was grabbed.
    let grabOffset: CGSize
    var target: Target

    var itemCenter: CGPoint {
        CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
    }
}

/// One group of items in the Arrange window, in display order.
struct ArrangeSection: Equatable, Identifiable {
    let title: String
    /// Nil for items that are not in the menu bar, which cannot be dragged.
    let section: MenuBarSection?
    var items: [MenuBarItem]

    var id: String { title }

    static let managedOrder: [MenuBarSection] = [.shown, .hidden, .alwaysHidden]

    /// The sections as the window shows them: the layout's order, or the order
    /// of a drop still being carried out, with a dragged item at its target.
    static func sections(
        from layout: MenuBarLayout,
        pendingOrder: [MenuBarSection: [WindowID]]?,
        drag: ItemDrag?
    ) -> [ArrangeSection] {
        let itemsByID = Dictionary(
            layout.entries.compactMap(\.item).map { ($0.windowID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var sections = managedOrder.map { section in
            let items = pendingOrder?[section].map { $0.compactMap { itemsByID[$0] } } ?? layout.items(in: section)
            return ArrangeSection(title: section.title, section: section, items: items)
        }
        if let drag, let targetIndex = sections.firstIndex(where: { $0.section == drag.target.section }) {
            for index in sections.indices {
                sections[index].items.removeAll { $0.windowID == drag.item.windowID }
            }
            let insertAt = min(max(drag.target.index, 0), sections[targetIndex].items.count)
            sections[targetIndex].items.insert(drag.item, at: insertAt)
        }
        if !layout.unplacedItems.isEmpty {
            sections.append(ArrangeSection(title: "Not in the Menu Bar", section: nil, items: layout.unplacedItems))
        }
        return sections
    }

    /// Why an item is dimmed, when it is not on screen. Items not in the menu
    /// bar get none: their section's title says it.
    static func offScreenNote(
        for item: MenuBarItem,
        in section: MenuBarSection?,
        layout: MenuBarLayout,
        visibleStatusArea: ClosedRange<CGFloat>
    ) -> String? {
        guard !item.isOnScreen, section != nil else { return nil }
        return layout.isHiddenByItsApp(item, visibleStatusArea: visibleStatusArea) ? "Not showing" : "Doesn't fit"
    }
}

extension ArrangeGrid.Metrics {
    static let arrange = ArrangeGrid.Metrics(
        slotSize: CGSize(width: 84, height: 80),
        slotSpacing: 4,
        wellInset: 8,
        headerHeight: 28,
        sectionSpacing: 18
    )
}

@Observable
final class LayoutEditorModel {
    private(set) var layout: MenuBarLayout?
    private(set) var presentation = ItemPresentation(items: [])
    private(set) var visibleStatusArea = AppController.visibleStatusArea()
    private(set) var drag: ItemDrag?
    private(set) var isMoving = false
    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    var errorMessage: String?

    /// The order shown after a drop, kept until the menu bar reports it, so
    /// the dropped item does not jump back while the move is under way.
    private var pendingOrder: [MenuBarSection: [WindowID]]?
    @ObservationIgnored private unowned let controller: AppController
    @ObservationIgnored private var refreshTimer: Timer?

    private static let pendingOrderTimeout: Duration = .seconds(2)

    init(controller: AppController) {
        self.controller = controller
    }

    var sections: [ArrangeSection] {
        guard let layout else { return [] }
        return ArrangeSection.sections(from: layout, pendingOrder: pendingOrder, drag: drag)
    }

    /// The item last dropped, kept above its neighbors while it springs into
    /// its slot.
    private(set) var landingItem: WindowID?

    var canDrag: Bool { accessibilityGranted && !isMoving && pendingOrder == nil }

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
        visibleStatusArea = AppController.visibleStatusArea()
        guard drag == nil, !isMoving else { return }
        let latest = controller.currentLayout()
        if let pendingOrder, let latest, latest.matches(pendingOrder, ignoring: notDrawnItems(in: latest)) {
            self.pendingOrder = nil
        }
        guard latest != layout else { return }
        layout = latest
        presentation = ItemPresentation(items: (latest?.entries.compactMap(\.item) ?? []) + (latest?.unplacedItems ?? []))
    }

    func dragChanged(_ item: MenuBarItem, pointer: CGPoint, start: CGPoint, grid: ArrangeGrid) {
        guard canDrag, let section = layout?.section(of: item.windowID) else { return }
        let current = sections
        if drag == nil {
            guard
                let sectionIndex = current.firstIndex(where: { $0.section == section }),
                let index = current[sectionIndex].items.firstIndex(where: { $0.windowID == item.windowID })
            else {
                return
            }
            let slot = grid.sections[sectionIndex].slotFrames[index]
            drag = ItemDrag(
                item: item,
                pointer: pointer,
                grabOffset: CGSize(width: start.x - slot.midX, height: start.y - slot.midY),
                target: .init(section: section, index: index)
            )
        }
        guard var drag else { return }
        drag.pointer = pointer
        if let target = target(at: drag.itemCenter, sections: current, grid: grid), target != drag.target {
            drag.target = target
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        self.drag = drag
    }

    func dragEnded() {
        guard let drag else { return }
        let droppedOrder = Dictionary(uniqueKeysWithValues: sections.compactMap { section in
            section.section.map { ($0, section.items.map(\.windowID)) }
        })
        self.drag = nil
        land(drag.item.windowID)
        guard
            canDrag,
            let layout,
            let destination = layout.destination(
                inserting: drag.item.windowID,
                into: drag.target.section,
                at: drag.target.index,
                unreliableNeighbors: notDrawnItems(in: layout)
            )
        else {
            return
        }
        pendingOrder = droppedOrder
        isMoving = true
        Task {
            do {
                try await MenuBarItemEvents.move(drag.item.windowID, ownerPID: drag.item.ownerPID, to: destination)
                errorMessage = nil
            } catch {
                pendingOrder = nil
                errorMessage = String(describing: error)
            }
            isMoving = false
            await settle()
        }
    }

    private func land(_ item: WindowID) {
        landingItem = item
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if landingItem == item { landingItem = nil }
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
    }

    func offScreenNote(for item: MenuBarItem, in section: MenuBarSection?) -> String? {
        guard let layout else { return nil }
        return ArrangeSection.offScreenNote(for: item, in: section, layout: layout, visibleStatusArea: visibleStatusArea)
    }

    /// Refreshes until the menu bar reports the dropped order, or gives up
    /// and shows what it reports.
    private func settle() async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.pendingOrderTimeout
        while pendingOrder != nil, clock.now < deadline {
            refresh()
            try? await Task.sleep(for: .milliseconds(100))
        }
        pendingOrder = nil
        refresh()
    }

    private func target(at point: CGPoint, sections: [ArrangeSection], grid: ArrangeGrid) -> ItemDrag.Target? {
        guard let drag else { return nil }
        let candidates = sections.indices.filter { sections[$0].section != nil }
        guard
            let sectionIndex = grid.section(nearest: point, among: candidates),
            let section = sections[sectionIndex].section
        else {
            return nil
        }
        var slotGrid = grid
        if section != drag.target.section {
            // Hit-test the layout the window will show once the gap moves
            // into this section, so the drop can land past its last item.
            var counts = sections.map(\.items.count)
            if let gapIndex = sections.firstIndex(where: { $0.section == drag.target.section }) {
                counts[gapIndex] -= 1
            }
            counts[sectionIndex] += 1
            slotGrid = ArrangeGrid(width: grid.width, slotCounts: counts, metrics: grid.metrics)
        }
        return .init(section: section, index: slotGrid.slot(at: point, in: sectionIndex))
    }

    private func notDrawnItems(in layout: MenuBarLayout) -> Set<WindowID> {
        Set(layout.entries.compactMap(\.item).filter { layout.isHiddenByItsApp($0, visibleStatusArea: visibleStatusArea) }.map(\.windowID))
    }
}

private extension MenuBarLayout {
    /// Whether each section holds `order`'s items in its order. Items in
    /// `ignoring` report stale frames, so their place is not compared.
    func matches(_ order: [MenuBarSection: [WindowID]], ignoring: Set<WindowID>) -> Bool {
        order.allSatisfy { section, ids in
            items(in: section).map(\.windowID).filter { !ignoring.contains($0) } == ids.filter { !ignoring.contains($0) }
        }
    }
}

struct LayoutView: View {
    let model: LayoutEditorModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if !model.accessibilityGranted {
                    AccessibilityBanner(onAllow: model.requestAccessibility)
                }
                ArrangeCanvas(
                    sections: model.sections,
                    presentation: model.presentation,
                    drag: model.drag,
                    landingItem: model.landingItem,
                    canDrag: model.canDrag,
                    note: model.offScreenNote(for:in:),
                    onDragChanged: model.dragChanged(_:pointer:start:grid:),
                    onDragEnded: model.dragEnded
                )
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
                Text("You can also hold ⌘ and drag icons in the menu bar itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

/// The sections and their items, drawn at the frames `ArrangeGrid` gives.
/// Every item lives in this one view, so an item moving between sections
/// animates as one continuous move.
struct ArrangeCanvas: View {
    let sections: [ArrangeSection]
    let presentation: ItemPresentation
    let drag: ItemDrag?
    let landingItem: WindowID?
    let canDrag: Bool
    let note: (MenuBarItem, MenuBarSection?) -> String?
    let onDragChanged: (MenuBarItem, CGPoint, CGPoint, ArrangeGrid) -> Void
    let onDragEnded: () -> Void

    @State private var width: CGFloat

    static let coordinateSpace = "arrange"
    static let spring = Animation.spring(duration: 0.34, bounce: 0.12)

    init(
        sections: [ArrangeSection],
        presentation: ItemPresentation,
        drag: ItemDrag?,
        landingItem: WindowID? = nil,
        canDrag: Bool,
        note: @escaping (MenuBarItem, MenuBarSection?) -> String?,
        onDragChanged: @escaping (MenuBarItem, CGPoint, CGPoint, ArrangeGrid) -> Void = { _, _, _, _ in },
        onDragEnded: @escaping () -> Void = {},
        initialWidth: CGFloat = 600
    ) {
        self.sections = sections
        self.presentation = presentation
        self.drag = drag
        self.landingItem = landingItem
        self.canDrag = canDrag
        self.note = note
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        _width = State(initialValue: initialWidth)
    }

    var body: some View {
        let grid = ArrangeGrid(width: width, slotCounts: sections.map(\.items.count), metrics: .arrange)
        ZStack(alignment: .topLeading) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                SectionBackground(
                    section: section,
                    frames: grid.sections[index],
                    isDropTarget: drag != nil && drag?.target.section == section.section
                )
            }
            // One flat list keyed by window, so an item that changes section
            // keeps its view and slides between them.
            ForEach(placements(in: grid), id: \.item.windowID) { placement in
                chip(placement.item, in: placement.section, slot: placement.slot, grid: grid)
            }
        }
        .frame(maxWidth: .infinity, minHeight: grid.height, maxHeight: grid.height, alignment: .topLeading)
        .animation(Self.spring, value: grid.height)
        .coordinateSpace(.named(Self.coordinateSpace))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
    }

    private struct Placement {
        let item: MenuBarItem
        let section: ArrangeSection
        let slot: CGRect
    }

    private func placements(in grid: ArrangeGrid) -> [Placement] {
        sections.enumerated().flatMap { sectionIndex, section in
            section.items.enumerated().map { index, item in
                Placement(item: item, section: section, slot: grid.sections[sectionIndex].slotFrames[index])
            }
        }
    }

    private func chip(_ item: MenuBarItem, in section: ArrangeSection, slot: CGRect, grid: ArrangeGrid) -> some View {
        let isLifted = drag?.item.windowID == item.windowID
        let isDraggable = canDrag && section.section != nil
        let center = isLifted ? drag?.itemCenter ?? slot.center : slot.center
        return ItemChip(
            name: presentation.name(of: item),
            icon: presentation.icon(of: item, size: 32),
            note: note(item, section.section),
            isDimmed: !item.isOnScreen,
            isLifted: isLifted
        )
        .frame(width: slot.width, height: slot.height)
        .pointerStyle(isDraggable ? (isLifted ? .grabActive : .grabIdle) : nil)
        .position(center)
        .animation(isLifted ? nil : Self.spring, value: center)
        .zIndex(isLifted || landingItem == item.windowID ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
                .onChanged { value in onDragChanged(item, value.location, value.startLocation, grid) }
                .onEnded { _ in onDragEnded() },
            isEnabled: isDraggable
        )
    }
}

private struct SectionBackground: View {
    let section: ArrangeSection
    let frames: ArrangeGrid.Section
    let isDropTarget: Bool

    var body: some View {
        Text(section.title)
            .font(.headline)
            .frame(width: frames.headerFrame.width, height: frames.headerFrame.height, alignment: .topLeading)
            .position(frames.headerFrame.center)
            .animation(ArrangeCanvas.spring, value: frames.headerFrame)

        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isDropTarget ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.6)))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1.5)
            }
            .overlay {
                if section.items.isEmpty {
                    Text("Drop items here").foregroundStyle(.tertiary)
                }
            }
            .frame(width: frames.wellFrame.width, height: frames.wellFrame.height)
            .position(frames.wellFrame.center)
            .animation(ArrangeCanvas.spring, value: frames.wellFrame)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
    }
}

private struct ItemChip: View {
    let name: String
    let icon: NSImage?
    let note: String?
    let isDimmed: Bool
    let isLifted: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: "questionmark.square.dashed").font(.title)
                }
            }
            .frame(height: 34)
            .opacity(isDimmed ? 0.5 : 1)
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(isDimmed ? .secondary : .primary)
            if let note {
                Text(note)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isLifted ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.06 : 0)))
                .shadow(color: .black.opacity(isLifted ? 0.22 : 0), radius: isLifted ? 12 : 0, y: isLifted ? 6 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isLifted ? 1.08 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isLifted)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(note.map { "\(name): \($0)" } ?? name)
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

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
