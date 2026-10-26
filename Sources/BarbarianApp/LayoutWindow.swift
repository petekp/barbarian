import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

/// The Arrange Menu Bar window: the managed part of the menu bar as one
/// strip, left to right, with both dividers. Dragging an item or a divider
/// opens a gap where it will land, and dropping it moves the real one there.
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
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 250),
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

/// An item or divider being dragged in the Arrange window.
struct EntryDrag: Equatable {
    let entry: MenuBarLayout.Entry
    /// The pointer, in the canvas's coordinates.
    var pointer: CGPoint
    /// The pointer's offset from the entry's center when the drag began, so
    /// the entry stays where it was grabbed.
    let grabOffset: CGSize
    /// Where the entry would land among the other entries.
    var targetIndex: Int

    var entryCenter: CGPoint {
        CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
    }
}

/// What the Arrange window shows: the managed entries in display order, how
/// wide each is, and the strip they make.
struct ArrangeContent {
    let layout: MenuBarLayout
    let entries: [MenuBarLayout.Entry]
    let strip: ArrangeStrip
    private let notDrawn: Set<WindowID>

    static let metrics = ArrangeStrip.Metrics(height: 64, spacing: 2, sectionPadding: 6, minimumSectionWidth: 90)
    static let nameFont = NSFont.systemFont(ofSize: 11)
    static let dividerWidth: CGFloat = 26
    static let notDrawnWidth: CGFloat = 34

    /// The layout's order, or the order of a drop still being carried out,
    /// with a dragged entry at its target.
    init(
        layout: MenuBarLayout,
        pendingOrder: [WindowID]?,
        drag: EntryDrag?,
        presentation: ItemPresentation,
        visibleStatusArea: ClosedRange<CGFloat>
    ) {
        self.layout = layout
        notDrawn = layout.notDrawnItems(visibleStatusArea: visibleStatusArea)
        let entriesByID = Dictionary(layout.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries = pendingOrder?.compactMap { entriesByID[$0] } ?? layout.entries
        if let drag {
            entries.removeAll { $0.id == drag.entry.id }
            entries.insert(drag.entry, at: min(max(drag.targetIndex, 0), entries.count))
        }
        self.entries = entries
        strip = Self.strip(for: entries, notDrawn: notDrawn, presentation: presentation)
    }

    func isNotDrawn(_ item: MenuBarItem) -> Bool {
        notDrawn.contains(item.windowID)
    }

    /// The strip without `entry`, which a drag hit-tests against.
    func stripWithout(_ entry: MenuBarLayout.Entry, presentation: ItemPresentation) -> ArrangeStrip {
        Self.strip(for: entries.filter { $0.id != entry.id }, notDrawn: notDrawn, presentation: presentation)
    }

    private static func strip(
        for entries: [MenuBarLayout.Entry],
        notDrawn: Set<WindowID>,
        presentation: ItemPresentation
    ) -> ArrangeStrip {
        ArrangeStrip(elements: entries.map { entry in
            switch entry {
            case .divider: .divider(width: dividerWidth)
            case .item(let item) where notDrawn.contains(item.windowID): .item(width: notDrawnWidth)
            case .item(let item): .item(width: itemWidth(name: presentation.name(of: item)))
            }
        }, metrics: metrics)
    }

    static func itemWidth(name: String) -> CGFloat {
        let textWidth = (name as NSString).size(withAttributes: [.font: nameFont]).width
        return min(max(textWidth.rounded(.up) + 14, 56), 120)
    }
}

extension MenuBarLayout {
    /// Managed items their app is not drawing right now.
    func notDrawnItems(visibleStatusArea: ClosedRange<CGFloat>) -> Set<WindowID> {
        Set(entries.compactMap(\.item).filter { isHiddenByItsApp($0, visibleStatusArea: visibleStatusArea) }.map(\.windowID))
    }
}

@Observable
final class LayoutEditorModel {
    private(set) var layout: MenuBarLayout?
    private(set) var presentation = ItemPresentation(items: [])
    private(set) var visibleStatusArea: ClosedRange<CGFloat> = 0...0
    private(set) var drag: EntryDrag?
    private(set) var isMoving = false
    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    private(set) var errorMessage: String?
    /// The entry last dropped, kept above its neighbors while it springs
    /// into place.
    private(set) var landingEntry: WindowID?

    /// The order shown after a drop, kept until the menu bar reports it, so
    /// the dropped entry does not jump back while the move is under way.
    private var pendingOrder: [WindowID]?
    @ObservationIgnored private unowned let controller: AppController
    @ObservationIgnored private var refreshTimer: Timer?

    private static let pendingOrderTimeout: Duration = .seconds(2)

    init(controller: AppController) {
        self.controller = controller
    }

    var content: ArrangeContent? {
        layout.map {
            ArrangeContent(
                layout: $0,
                pendingOrder: pendingOrder,
                drag: drag,
                presentation: presentation,
                visibleStatusArea: visibleStatusArea
            )
        }
    }

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
        visibleStatusArea = controller.visibleStatusArea()
        guard drag == nil, !isMoving else { return }
        let latest = controller.currentLayout()
        if let pendingOrder, let latest, latest.matches(pendingOrder, ignoring: latest.notDrawnItems(visibleStatusArea: visibleStatusArea)) {
            self.pendingOrder = nil
        }
        guard latest != layout else { return }
        layout = latest
        presentation = ItemPresentation(items: (latest?.entries.compactMap(\.item) ?? []) + (latest?.systemItems ?? []))
    }

    func dragChanged(_ entry: MenuBarLayout.Entry, pointer: CGPoint, start: CGPoint) {
        guard canDrag, let content else { return }
        if drag == nil {
            guard let index = content.entries.firstIndex(of: entry) else { return }
            let frame = content.strip.frames[index]
            drag = EntryDrag(
                entry: entry,
                pointer: pointer,
                grabOffset: CGSize(width: start.x - frame.midX, height: 0),
                targetIndex: index
            )
        }
        guard var drag else { return }
        drag.pointer = pointer
        let target = content.stripWithout(entry, presentation: presentation).insertionIndex(at: drag.entryCenter.x)
        if target != drag.targetIndex {
            drag.targetIndex = target
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        self.drag = drag
    }

    func dragEnded() {
        guard let drag, let content else { return }
        let droppedOrder = content.entries.map(\.id)
        self.drag = nil
        land(drag.entry.id)
        guard
            canDrag,
            let layout,
            let destination = layout.destination(
                moving: drag.entry.id,
                to: drag.targetIndex,
                unreliableNeighbors: layout.notDrawnItems(visibleStatusArea: visibleStatusArea)
            )
        else {
            return
        }
        let ownerPID = drag.entry.item?.ownerPID ?? ProcessInfo.processInfo.processIdentifier
        let name = drag.entry.item.map(presentation.name(of:)) ?? "the divider"
        pendingOrder = droppedOrder
        isMoving = true
        Task {
            do {
                try await MenuBarItemEvents.move(drag.entry.id, ownerPID: ownerPID, to: destination)
                errorMessage = nil
            } catch {
                pendingOrder = nil
                errorMessage = "Barbarian couldn't move \(name). Try again."
            }
            isMoving = false
            await settle()
        }
    }

    private func land(_ entry: WindowID) {
        landingEntry = entry
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if landingEntry == entry { landingEntry = nil }
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
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
}

private extension MenuBarLayout {
    /// Whether the entries are in `order`. Items in `ignoring` report stale
    /// frames, so their place is not compared.
    func matches(_ order: [WindowID], ignoring: Set<WindowID>) -> Bool {
        entries.map(\.id).filter { !ignoring.contains($0) } == order.filter { !ignoring.contains($0) }
    }
}

struct LayoutView: View {
    let model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.accessibilityGranted {
                AccessibilityBanner(onAllow: model.requestAccessibility)
            }
            ScrollView(.horizontal) {
                if let content = model.content {
                    ArrangeCanvas(
                        content: content,
                        presentation: model.presentation,
                        drag: model.drag,
                        landingEntry: model.landingEntry,
                        canDrag: model.canDrag,
                        onDragChanged: model.dragChanged(_:pointer:start:),
                        onDragEnded: model.dragEnded
                    )
                    .padding(.vertical, 4)
                }
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Text("Drag items or the dividers to rearrange. You can also hold ⌘ and drag icons in the menu bar itself.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }
}

/// The strip: section backgrounds and headers, the managed entries at the
/// frames `ArrangeStrip` gives, then Barbarian's icon and macOS's items.
/// Every entry lives in one view keyed by window ID, so an entry dropped in
/// another section slides there as one move.
struct ArrangeCanvas: View {
    let content: ArrangeContent
    let presentation: ItemPresentation
    let drag: EntryDrag?
    var landingEntry: WindowID?
    let canDrag: Bool
    var onDragChanged: (MenuBarLayout.Entry, CGPoint, CGPoint) -> Void = { _, _, _ in }
    var onDragEnded: () -> Void = {}

    static let coordinateSpace = "arrange"
    static let spring = Animation.spring(duration: 0.34, bounce: 0.12)
    private static let headerHeight: CGFloat = 34
    private static let trailingGap: CGFloat = 10

    private static let sections: [(title: String, caption: String, tint: Color)] = [
        ("Always Hidden", "Option-click the axe", .purple),
        ("Hidden", "Click the axe or hover", .blue),
        ("Shown", "Always visible", .gray),
    ]

    var body: some View {
        let strip = content.strip
        let stripHeight = ArrangeContent.metrics.height
        let trailingX = strip.width + Self.trailingGap
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(Self.sections.indices, strip.sectionSpans)), id: \.0) { index, span in
                SectionBackground(
                    title: Self.sections[index].title,
                    caption: Self.sections[index].caption,
                    tint: Self.sections[index].tint,
                    frame: CGRect(x: span.lowerBound, y: Self.headerHeight, width: span.upperBound - span.lowerBound, height: stripHeight),
                    headerHeight: Self.headerHeight,
                    isDropTarget: drag.map { span.contains($0.entryCenter.x) } ?? false
                )
            }
            ForEach(Array(content.entries.enumerated()), id: \.element.id) { index, entry in
                entryView(entry, frame: strip.frames[index].offsetBy(dx: 0, dy: Self.headerHeight))
            }
            SystemItems(icon: BattleAxeIcon.image(), items: content.layout.systemItems, presentation: presentation, height: stripHeight)
                .offset(x: trailingX, y: Self.headerHeight)
        }
        .frame(
            width: trailingX + SystemItems.width(of: content.layout.systemItems, presentation: presentation),
            height: Self.headerHeight + stripHeight,
            alignment: .topLeading
        )
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    @ViewBuilder
    private func entryView(_ entry: MenuBarLayout.Entry, frame: CGRect) -> some View {
        let isLifted = drag?.entry.id == entry.id
        let isDraggable = canDrag && entry.item.map { !content.isNotDrawn($0) } ?? true
        let center = isLifted ? CGPoint(x: drag?.entryCenter.x ?? frame.midX, y: frame.midY) : CGPoint(x: frame.midX, y: frame.midY)
        Group {
            switch entry {
            case .divider(let role, _):
                DividerChip(role: role, isLifted: isLifted)
            case .item(let item):
                ItemChip(
                    name: presentation.name(of: item),
                    icon: presentation.icon(of: item, size: 22),
                    state: content.isNotDrawn(item) ? .notDrawn : (item.isOnScreen ? .shown : .doesNotFit),
                    isLifted: isLifted
                )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .pointerStyle(isDraggable ? (isLifted ? .grabActive : .grabIdle) : nil)
        .position(center)
        .animation(isLifted ? nil : Self.spring, value: center)
        .zIndex(isLifted || landingEntry == entry.id ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
                .onChanged { value in onDragChanged(entry, value.location, value.startLocation) }
                .onEnded { _ in onDragEnded() },
            isEnabled: isDraggable
        )
    }
}

private struct SectionBackground: View {
    let title: String
    let caption: String
    let tint: Color
    let frame: CGRect
    let headerHeight: CGFloat
    let isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .fixedSize()
        .offset(x: frame.minX + 4)
        .animation(ArrangeCanvas.spring, value: frame.minX)

        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(isDropTarget ? 0.2 : 0.1))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1.5)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .animation(ArrangeCanvas.spring, value: frame)
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
    }
}

private struct ItemChip: View {
    enum State { case shown, doesNotFit, notDrawn }

    let name: String
    let icon: NSImage?
    let state: State
    let isLifted: Bool

    @SwiftUI.State private var isHovered = false

    var body: some View {
        Group {
            if state == .notDrawn {
                iconImage
                    .scaleEffect(0.6)
                    .frame(width: 26, height: 26)
                    .opacity(0.5)
                    .background(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            } else {
                VStack(spacing: 4) {
                    iconImage
                        .frame(height: 24)
                        .opacity(state == .doesNotFit ? 0.45 : 1)
                    Text(name)
                        .font(Font(ArrangeContent.nameFont))
                        .lineLimit(1)
                        .foregroundStyle(state == .doesNotFit ? .secondary : .primary)
                    if state == .doesNotFit {
                        Text("Doesn't fit").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isLifted ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.06 : 0)))
                .shadow(color: .black.opacity(isLifted ? 0.22 : 0), radius: isLifted ? 10 : 0, y: isLifted ? 5 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(isLifted ? 1.08 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isLifted)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
    }

    @ViewBuilder private var iconImage: some View {
        if let icon {
            Image(nsImage: icon)
        } else {
            Image(systemName: "questionmark.square.dashed").font(.title3)
        }
    }

    private var help: String {
        switch state {
        case .shown: name
        case .doesNotFit: "\(name) doesn't fit in the menu bar right now"
        case .notDrawn: "\(name) isn't showing right now. Its app shows it only sometimes."
        }
    }
}

private struct DividerChip: View {
    let role: BarbarianCore.Divider
    let isLifted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: role == .alwaysHidden ? "chevron.left.2" : "chevron.left")
                .font(.system(size: 9, weight: .heavy))
            Capsule().frame(width: 3, height: 34)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .scaleEffect(isLifted ? 1.12 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isLifted)
        .help(role == .alwaysHidden ? "Items left of this divider are Always Hidden" : "Items left of this divider are Hidden")
    }
}

/// Barbarian's icon and the items right of it, which macOS places. Shown
/// for context and not draggable.
private struct SystemItems: View {
    let icon: NSImage
    let items: [MenuBarItem]
    let presentation: ItemPresentation
    let height: CGFloat

    static let iconWidth: CGFloat = 40

    static func width(of items: [MenuBarItem], presentation: ItemPresentation) -> CGFloat {
        iconWidth + items.map { ArrangeContent.itemWidth(name: presentation.name(of: $0)) }.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: icon)
                .frame(width: Self.iconWidth, height: height)
                .help("Barbarian")
            ForEach(items) { item in
                VStack(spacing: 4) {
                    if let image = presentation.icon(of: item, size: 22) {
                        Image(nsImage: image).frame(height: 24)
                    }
                    Text(presentation.name(of: item)).font(Font(ArrangeContent.nameFont)).lineLimit(1)
                }
                .frame(width: ArrangeContent.itemWidth(name: presentation.name(of: item)), height: height)
                .opacity(0.45)
                .help("\(presentation.name(of: item)) is placed by macOS")
            }
        }
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
