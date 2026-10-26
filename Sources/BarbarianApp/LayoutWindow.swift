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
        window.bringForward()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRefreshing()
        controller.isPinnedOpen = false
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow.hosting(
            LayoutView(model: model),
            title: "Arrange Menu Bar",
            size: NSSize(width: 1100, height: 250),
            styleMask: [.titled, .closable, .resizable]
        )
        window.delegate = self
        return window
    }
}

/// An item or divider being dragged in the Arrange window. Only x matters:
/// the strip is one row.
struct EntryDrag: Equatable {
    let entry: MenuBarLayout.Entry
    /// The pointer, in the canvas's coordinates.
    var pointerX: CGFloat
    /// The pointer's offset from the entry's center when the drag began, so
    /// the entry stays where it was grabbed.
    let grabOffsetX: CGFloat
    /// Where the entry would land among the other entries.
    var targetIndex: Int
    /// The strip without the dragged entry, which the drag hit-tests against.
    let othersStrip: ArrangeStrip

    var entryCenterX: CGFloat {
        pointerX - grabOffsetX
    }
}

/// What the Arrange window shows: the managed entries in display order and
/// the strip they make.
struct ArrangeContent {
    let layout: MenuBarLayout
    let entries: [MenuBarLayout.Entry]
    let strip: ArrangeStrip
    let presentation: ItemPresentation
    /// Each item's width in the strip, by window ID. Worked out once per
    /// layout, since it measures text.
    let widths: [WindowID: CGFloat]

    static let metrics = ArrangeStrip.Metrics(height: 64, spacing: 2, sectionPadding: 6, minimumSectionWidth: 90)
    static let nameFont = NSFont.systemFont(ofSize: 11)
    private static let dividerWidth: CGFloat = 26
    private static let notDrawnWidth: CGFloat = 34

    init(layout: MenuBarLayout, pendingOrder: [WindowID]?, drag: EntryDrag?, presentation: ItemPresentation, widths: [WindowID: CGFloat]) {
        self.layout = layout
        self.presentation = presentation
        self.widths = widths
        entries = layout.entries(inOrder: pendingOrder, moving: drag?.entry, to: drag?.targetIndex ?? 0)
        strip = Self.strip(for: entries, widths: widths)
    }

    /// A divider's role where the window shows it: the left one plays Always
    /// Hidden, as in the menu bar, so a dragged divider shows the role it
    /// will take.
    func dividerRole(of divider: MenuBarLayout.Entry) -> BarbarianCore.Divider {
        let firstDivider = entries.first { if case .divider = $0 { true } else { false } }
        return firstDivider?.id == divider.id ? .alwaysHidden : .hidden
    }

    static func strip(for entries: [MenuBarLayout.Entry], widths: [WindowID: CGFloat]) -> ArrangeStrip {
        ArrangeStrip(elements: entries.map { entry in
            switch entry {
            case .divider: .divider(width: dividerWidth)
            case .item(let item): .item(width: widths[item.windowID] ?? notDrawnWidth)
            }
        }, metrics: metrics)
    }

    /// Every item's width: its name's, within limits, or a small fixed
    /// width for an item its app is not drawing, which shows no name.
    static func widths(of layout: MenuBarLayout, presentation: ItemPresentation) -> [WindowID: CGFloat] {
        let items = layout.entries.compactMap(\.item) + layout.systemItems
        return Dictionary(items.map { item in
            let textWidth = (presentation.name(of: item) as NSString).size(withAttributes: [.font: nameFont]).width
            let width = layout.isNotDrawn(item) ? notDrawnWidth : min(max(textWidth.rounded(.up) + 14, 56), 120)
            return (item.windowID, width)
        }, uniquingKeysWith: { first, _ in first })
    }
}

@Observable
final class LayoutEditorModel {
    private(set) var layout: MenuBarLayout?
    private(set) var presentation = ItemPresentation(items: [], images: nil)
    private var widths: [WindowID: CGFloat] = [:]
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
        layout.map { ArrangeContent(layout: $0, pendingOrder: pendingOrder, drag: drag, presentation: presentation, widths: widths) }
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
        guard drag == nil, !isMoving else { return }
        let latest = controller.currentLayout()
        if let pendingOrder, let latest, latest.hasOrder(pendingOrder) {
            self.pendingOrder = nil
        }
        guard latest != layout else { return }
        layout = latest
        presentation = ItemPresentation(layout: latest, images: controller.itemImages)
        widths = latest.map { ArrangeContent.widths(of: $0, presentation: presentation) } ?? [:]
    }

    func dragChanged(_ entry: MenuBarLayout.Entry, pointerX: CGFloat, startX: CGFloat) {
        guard canDrag else { return }
        if drag == nil {
            guard let content, let index = content.entries.firstIndex(of: entry) else { return }
            drag = EntryDrag(
                entry: entry,
                pointerX: pointerX,
                grabOffsetX: startX - content.strip.frames[index].midX,
                targetIndex: index,
                othersStrip: ArrangeContent.strip(for: content.entries.filter { $0.id != entry.id }, widths: widths)
            )
        }
        guard var drag else { return }
        drag.pointerX = pointerX
        let target = drag.othersStrip.insertionIndex(at: drag.entryCenterX)
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
        guard canDrag, let destination = content.layout.destination(moving: drag.entry.id, to: drag.targetIndex) else { return }
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

struct LayoutView: View {
    let model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.accessibilityGranted {
                AccessibilityBanner(onAllow: AccessibilityPermission.requestAndOpenSettings)
            }
            ScrollView(.horizontal) {
                if let content = model.content {
                    ArrangeCanvas(
                        content: content,
                        drag: model.drag,
                        landingEntry: model.landingEntry,
                        canDrag: model.canDrag,
                        onDragChanged: model.dragChanged(_:pointerX:startX:),
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
    let drag: EntryDrag?
    var landingEntry: WindowID?
    let canDrag: Bool
    var onDragChanged: (MenuBarLayout.Entry, CGFloat, CGFloat) -> Void = { _, _, _ in }
    var onDragEnded: () -> Void = {}

    static let coordinateSpace = "arrange"
    static let spring = Animation.spring(duration: 0.34, bounce: 0.12)
    private static let headerHeight: CGFloat = 34
    private static let trailingGap: CGFloat = 10
    private static let iconWidth: CGFloat = 40

    var body: some View {
        let strip = content.strip
        let stripHeight = ArrangeContent.metrics.height
        let systemItems = content.layout.systemItems
        let trailingX = strip.width + Self.trailingGap
        let systemItemsWidth = systemItems.map { content.widths[$0.windowID] ?? 0 }.reduce(0, +)
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(MenuBarSection.allCases, strip.sectionSpans)), id: \.0) { section, span in
                SectionBackground(
                    section: section,
                    frame: CGRect(x: span.lowerBound, y: Self.headerHeight, width: span.upperBound - span.lowerBound, height: stripHeight),
                    isDropTarget: drag.map { span.contains($0.entryCenterX) } ?? false
                )
            }
            ForEach(Array(content.entries.enumerated()), id: \.element.id) { index, entry in
                entryView(entry, frame: strip.frames[index].offsetBy(dx: 0, dy: Self.headerHeight))
            }
            HStack(spacing: 0) {
                Image(nsImage: BattleAxeIcon.image())
                    .frame(width: Self.iconWidth, height: stripHeight)
                    .help("Barbarian")
                ForEach(systemItems) { item in
                    itemChip(item, status: .placedByMacOS, isLifted: false)
                        .frame(width: content.widths[item.windowID], height: stripHeight)
                }
            }
            .offset(x: trailingX, y: Self.headerHeight)
        }
        .frame(width: trailingX + Self.iconWidth + systemItemsWidth, height: Self.headerHeight + stripHeight, alignment: .topLeading)
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    @ViewBuilder
    private func entryView(_ entry: MenuBarLayout.Entry, frame: CGRect) -> some View {
        let isLifted = drag?.entry.id == entry.id
        let isDraggable = canDrag && entry.item.map { !content.layout.isNotDrawn($0) } ?? true
        let centerX = isLifted ? drag?.entryCenterX ?? frame.midX : frame.midX
        let center = CGPoint(x: centerX, y: frame.midY)
        Group {
            switch entry {
            case .divider:
                DividerChip(role: content.dividerRole(of: entry), isLifted: isLifted)
            case .item(let item):
                let status: ItemChip.Status = content.layout.isNotDrawn(item) ? .notDrawn : (item.isOnScreen ? .shown : .doesNotFit)
                itemChip(item, status: status, isLifted: isLifted)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .pointerStyle(isDraggable ? (isLifted ? .grabActive : .grabIdle) : nil)
        .position(center)
        .animation(isLifted ? nil : Self.spring, value: center)
        .zIndex(isLifted || landingEntry == entry.id ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
                .onChanged { value in onDragChanged(entry, value.location.x, value.startLocation.x) }
                .onEnded { _ in onDragEnded() },
            isEnabled: isDraggable
        )
    }

    private func itemChip(_ item: MenuBarItem, status: ItemChip.Status, isLifted: Bool) -> ItemChip {
        ItemChip(
            name: content.presentation.name(of: item),
            icon: content.presentation.icon(of: item, size: 22),
            status: status,
            isLifted: isLifted
        )
    }
}

private extension MenuBarSection {
    var caption: String {
        switch self {
        case .alwaysHidden: "Option-click the axe"
        case .hidden: "Click the axe or hover"
        case .shown: "Always visible"
        }
    }

    var tint: Color {
        switch self {
        case .alwaysHidden: .purple
        case .hidden: .blue
        case .shown: .gray
        }
    }
}

private struct SectionBackground: View {
    let section: MenuBarSection
    let frame: CGRect
    let isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(section.title).font(.system(size: 12, weight: .semibold))
            Text(section.caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .fixedSize()
        .offset(x: frame.minX + 4)
        .animation(ArrangeCanvas.spring, value: frame.minX)

        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(section.tint.opacity(isDropTarget ? 0.2 : 0.1))
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
    enum Status { case shown, doesNotFit, notDrawn, placedByMacOS }

    let name: String
    let icon: NSImage?
    let status: Status
    let isLifted: Bool

    @State private var isHovered = false

    var body: some View {
        Group {
            if status == .notDrawn {
                iconImage
                    .scaleEffect(0.6)
                    .frame(width: 26, height: 26)
                    .opacity(0.5)
                    .background(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            } else {
                VStack(spacing: 4) {
                    iconImage
                        .frame(height: 24)
                        .opacity(status == .doesNotFit ? 0.45 : 1)
                    Text(name)
                        .font(Font(ArrangeContent.nameFont))
                        .lineLimit(1)
                        .foregroundStyle(status == .doesNotFit ? .secondary : .primary)
                    if status == .doesNotFit {
                        Text("Doesn't fit").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
                .opacity(status == .placedByMacOS ? 0.45 : 1)
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
        .onHover { isHovered = status != .placedByMacOS && $0 }
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
        switch status {
        case .shown: name
        case .doesNotFit: "\(name) doesn't fit in the menu bar right now"
        case .notDrawn: "\(name) isn't showing right now. Its app shows it only sometimes."
        case .placedByMacOS: "\(name) is placed by macOS"
        }
    }
}

private struct DividerChip: View {
    let role: BarbarianCore.Divider
    let isLifted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: role.symbolName)
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
