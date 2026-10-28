import AppKit
import BarbarianCore
import BarbarianSystem
import SwiftUI

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

    /// Where the menu bar's room ends in the strip, and how many items lie
    /// left of it. When the bar is full, macOS leaves out the leftmost
    /// items, so the items that do not fit sit left of one point. Nil when
    /// everything fits.
    let overflow: (endX: CGFloat, itemCount: Int)?
    /// The items that would not fit in this order.
    let itemsThatDoNotFit: Set<WindowID>
    /// Whether the menu bar's room ends at a notch, as on a MacBook's
    /// built-in display, rather than at the front app's menus.
    let isCutOffByNotch: Bool

    static let metrics = ArrangeStrip.Metrics(height: 64, spacing: 2, sectionPadding: 6, minimumSectionWidth: 90)
    static let nameFont = NSFont.systemFont(ofSize: 11)
    private static let dividerWidth: CGFloat = 26
    private static let minimumItemWidth: CGFloat = 56

    init(layout: MenuBarLayout, pendingOrder: [WindowID]?, drag: EntryDrag?, presentation: ItemPresentation, widths: [WindowID: CGFloat], isCutOffByNotch: Bool) {
        self.layout = layout
        self.isCutOffByNotch = isCutOffByNotch
        self.presentation = presentation
        self.widths = widths
        let entries = layout.entries(inOrder: pendingOrder, moving: drag?.entry, to: drag?.targetIndex ?? 0)
        let strip = Self.strip(for: entries, widths: widths)
        self.entries = entries
        self.strip = strip
        let positionsThatDoNotFit = layout.positionsThatDoNotFitWithEverySectionShown(inOrder: entries)
        itemsThatDoNotFit = Set(positionsThatDoNotFit.map { entries[$0].id })
        overflow = positionsThatDoNotFit.last.map { (strip.gapX(after: $0), positionsThatDoNotFit.count) }
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
            case .item(let item): .item(width: widths[item.windowID] ?? minimumItemWidth)
            }
        }, metrics: metrics)
    }

    /// Every item's width: its name's, within limits.
    static func widths(of layout: MenuBarLayout, presentation: ItemPresentation) -> [WindowID: CGFloat] {
        let items = layout.entries.compactMap(\.item) + layout.systemItems
        return Dictionary(items.map { item in
            let textWidth = (presentation.name(of: item) as NSString).size(withAttributes: [.font: nameFont]).width
            return (item.windowID, min(max(textWidth.rounded(.up) + 14, minimumItemWidth), 120))
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
    /// The canvas width from the start of a drag until its move settles, so
    /// the panel, which is pinned by its right edge, does not resize and
    /// shift the strip under the pointer.
    private(set) var frozenCanvasWidth: CGFloat?

    /// The order shown after a drop, kept until the menu bar reports it, so
    /// the dropped entry does not jump back while the move is under way.
    private var pendingOrder: [WindowID]?
    private var isCutOffByNotch = false
    /// The layout read before the panel revealed every section. Items their
    /// app is not drawing keep the place they had in it.
    @ObservationIgnored private var baseline: MenuBarLayout?
    @ObservationIgnored private var baselineState = HidingState.showingShownOnly
    @ObservationIgnored private unowned let controller: AppController
    @ObservationIgnored private var refreshTimer: Timer?

    private static let pendingOrderTimeout: Duration = .seconds(2)
    private static let settleInterval: Duration = .milliseconds(100)
    private static let maximumSettleReads = 30

    init(controller: AppController) {
        self.controller = controller
    }

    var content: ArrangeContent? {
        layout.map { ArrangeContent(layout: $0, pendingOrder: pendingOrder, drag: drag, presentation: presentation, widths: widths, isCutOffByNotch: isCutOffByNotch) }
    }

    var canDrag: Bool { accessibilityGranted && !isMoving && pendingOrder == nil }

    /// Reads the layout the menu bar shows before the panel reveals every
    /// section. Call before revealing.
    func takeBaseline() {
        baseline = controller.currentLayout()
        baselineState = controller.state
    }

    /// Waits until the reveal has changed the menu bar and two reads in a
    /// row then agree, then shows that layout without animating it. Two
    /// reads can agree before the window server applies the reveal, so
    /// agreement counts only once the bar differs from the baseline, unless
    /// every section was already shown.
    func loadSettledLayout() async {
        var hasChanged = baselineState == .showingAll
        var previous = readLayout()
        for _ in 0..<Self.maximumSettleReads {
            try? await Task.sleep(for: Self.settleInterval)
            let raw = controller.currentLayout()
            hasChanged = hasChanged || raw != baseline
            let current = readLayout(raw)
            if hasChanged, current == previous { break }
            previous = current
        }
        accessibilityGranted = AccessibilityPermission.isGranted
        isCutOffByNotch = controller.iconScreen?.auxiliaryTopRightArea != nil
        apply(previous)
    }

    func startRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Shows the menu bar's current layout, animating any change. While a
    /// dropped order is pending, only a layout in that order is shown.
    func refresh() {
        accessibilityGranted = AccessibilityPermission.isGranted
        isCutOffByNotch = controller.iconScreen?.auxiliaryTopRightArea != nil
        guard drag == nil, !isMoving else { return }
        let latest = readLayout()
        if let pendingOrder {
            guard let latest, latest.hasOrder(pendingOrder) else { return }
            withAnimation(ArrangeCanvas.spring) {
                self.pendingOrder = nil
                frozenCanvasWidth = nil
                apply(latest)
            }
            return
        }
        guard latest != layout else { return }
        withAnimation(ArrangeCanvas.spring) { apply(latest) }
    }

    private func readLayout(_ latest: MenuBarLayout? = nil) -> MenuBarLayout? {
        guard let latest = latest ?? controller.currentLayout() else { return nil }
        return baseline.map { latest.keepingStaleItems(asIn: $0, revealedFrom: baselineState) } ?? latest
    }

    private func apply(_ latest: MenuBarLayout?) {
        layout = latest
        presentation = ItemPresentation(layout: latest, images: controller.itemImages)
        widths = latest.map { ArrangeContent.widths(of: $0, presentation: presentation) } ?? [:]
    }

    /// The lifted entry follows the pointer without animation. The other
    /// entries spring to their new places when the drop target changes.
    func dragChanged(_ entry: MenuBarLayout.Entry, pointerX: CGFloat, startX: CGFloat) {
        guard canDrag else { return }
        if drag == nil {
            guard let content, let index = content.entries.firstIndex(of: entry) else { return }
            frozenCanvasWidth = ArrangeCanvas.width(of: content)
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
            withAnimation(ArrangeCanvas.spring) { self.drag = drag }
        } else {
            self.drag = drag
        }
    }

    func dragEnded() {
        guard let drag, let content else { return }
        let droppedOrder = content.entries.map(\.id)
        let destination = canDrag ? content.layout.destination(moving: drag.entry.id, to: drag.targetIndex) : nil
        withAnimation(ArrangeCanvas.spring) {
            self.drag = nil
            landingEntry = drag.entry.id
            if destination != nil { pendingOrder = droppedOrder } else { frozenCanvasWidth = nil }
        }
        clearLanding(drag.entry.id)
        guard let destination else { return }
        let ownerPID = drag.entry.item?.ownerPID ?? ProcessInfo.processInfo.processIdentifier
        let name = drag.entry.item.map(presentation.name(of:)) ?? "the divider"
        isMoving = true
        Task {
            do {
                try await MenuBarItemEvents.move(drag.entry.id, ownerPID: ownerPID, to: destination)
                errorMessage = nil
                isMoving = false
                await settle()
            } catch {
                errorMessage = "Barbarian couldn't move \(name). Try again."
                isMoving = false
                showCurrentLayout()
            }
        }
    }

    private func clearLanding(_ entry: WindowID) {
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
            try? await Task.sleep(for: Self.settleInterval)
        }
        if pendingOrder != nil { showCurrentLayout() }
    }

    /// Drops the pending order and shows what the menu bar reports.
    private func showCurrentLayout() {
        let latest = readLayout()
        withAnimation(ArrangeCanvas.spring) {
            pendingOrder = nil
            frozenCanvasWidth = nil
            apply(latest)
        }
    }
}

/// The Arrange panel's content. It sizes itself to the strip, up to
/// `maximumCanvasWidth`, past which the strip scrolls.
struct LayoutView: View {
    let model: LayoutEditorModel
    let maximumCanvasWidth: CGFloat
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Text("Drag items or the dividers to rearrange. You can also hold ⌘ and drag icons in the menu bar itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !model.accessibilityGranted {
                AccessibilityBanner(onAllow: AccessibilityPermission.requestAndOpenSettings)
            }
            if let content = model.content {
                ScrollView(.horizontal) {
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
                .frame(width: min(model.frozenCanvasWidth ?? ArrangeCanvas.width(of: content), maximumCanvasWidth))
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 18, trailing: 16))
        .fixedSize()
        .background {
            PanelBackground(material: .popover).clipShape(LayoutPanel.shape)
        }
        .overlay {
            LayoutPanel.shape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

/// The window's own translucent material, which shows the dimmed screen
/// behind the panel through a blur.
private struct PanelBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
    /// The margin between a section's edge and its entries, the same on
    /// all four sides.
    private static let stripInset = ArrangeContent.metrics.sectionPadding
    private static let trailingGap: CGFloat = 10
    private static let iconWidth: CGFloat = 40
    private static let overflowLabelHeight: CGFloat = 20
    private static let overflowColor = Color.orange

    /// The canvas's width for `content`: the strip, then Barbarian's icon
    /// and macOS's items.
    static func width(of content: ArrangeContent) -> CGFloat {
        let systemItemsWidth = content.layout.systemItems.map { content.widths[$0.windowID] ?? 0 }.reduce(0, +)
        return content.strip.width + trailingGap + iconWidth + systemItemsWidth
    }

    var body: some View {
        let strip = content.strip
        let stripHeight = ArrangeContent.metrics.height
        let sectionHeight = stripHeight + 2 * Self.stripInset
        let stripY = Self.headerHeight + Self.stripInset
        let systemItems = content.layout.systemItems
        let trailingX = strip.width + Self.trailingGap
        let systemItemsWidth = systemItems.map { content.widths[$0.windowID] ?? 0 }.reduce(0, +)
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(MenuBarSection.allCases, strip.sectionSpans)), id: \.0) { section, span in
                SectionBackground(
                    section: section,
                    frame: CGRect(x: span.lowerBound, y: Self.headerHeight, width: span.upperBound - span.lowerBound, height: sectionHeight),
                    isDropTarget: drag.map { span.contains($0.entryCenterX) } ?? false
                )
            }
            if let overflow = content.overflow {
                overflowMarks(endX: overflow.endX, itemCount: overflow.itemCount, sectionSpans: strip.sectionSpans, sectionHeight: sectionHeight)
            }
            ForEach(Array(content.entries.enumerated()), id: \.element.id) { index, entry in
                entryView(entry, frame: strip.frames[index].offsetBy(dx: 0, dy: stripY))
            }
            if !systemItems.isEmpty {
                SectionHeading(title: "Placed by macOS", caption: "Can't be moved", isDimmed: true)
                    .offset(x: trailingX + Self.iconWidth + 4)
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
            .offset(x: trailingX, y: stripY)
        }
        .frame(
            width: trailingX + Self.iconWidth + systemItemsWidth,
            height: Self.headerHeight + sectionHeight + Self.overflowLabelHeight,
            alignment: .topLeading
        )
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    private func overflowLabel(itemCount: Int) -> String {
        if content.isCutOffByNotch { return "← Cut off by the notch" }
        return itemCount == 1 ? "← No room for this one right now" : "← No room for these \(itemCount) right now"
    }

    /// Shading over the items that do not fit, inside their sections, a
    /// dashed line where the room ends, and one label under the line.
    @ViewBuilder
    private func overflowMarks(endX: CGFloat, itemCount: Int, sectionSpans: [ClosedRange<CGFloat>], sectionHeight: CGFloat) -> some View {
        ForEach(Array(sectionSpans.enumerated()), id: \.offset) { _, span in
            let shadedWidth = min(span.upperBound, endX) - span.lowerBound
            if shadedWidth > 0 {
                DiagonalLines(spacing: 8)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 4)
                    .frame(width: span.upperBound - span.lowerBound, height: sectionHeight)
                    .clipShape(SectionBackground.shape)
                    .frame(width: shadedWidth, height: sectionHeight, alignment: .leading)
                    .clipped()
                    .offset(x: span.lowerBound, y: Self.headerHeight)
            }
        }
        Path { path in
            path.move(to: CGPoint(x: endX, y: Self.headerHeight - 4))
            path.addLine(to: CGPoint(x: endX, y: Self.headerHeight + sectionHeight + Self.overflowLabelHeight))
        }
        .stroke(Self.overflowColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        Text(overflowLabel(itemCount: itemCount))
            .font(.system(size: 11))
            .foregroundStyle(Self.overflowColor)
            .fixedSize()
            .frame(width: endX - 6, alignment: .trailing)
            .offset(y: Self.headerHeight + sectionHeight + 3)
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
                let status: ItemChip.Status = content.layout.isNotDrawn(item) ? .notDrawn : (content.itemsThatDoNotFit.contains(item.windowID) ? .doesNotFit : .shown)
                itemChip(item, status: status, isLifted: isLifted)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .pointerStyle(isDraggable ? (isLifted ? .grabActive : .grabIdle) : nil)
        .position(center)
        .transaction { transaction in
            if isLifted { transaction.animation = nil }
        }
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

private struct SectionHeading: View {
    let title: String
    let caption: String
    let isDimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isDimmed ? .secondary : .primary)
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

private struct SectionBackground: View {
    static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    let section: MenuBarSection
    let frame: CGRect
    let isDropTarget: Bool

    var body: some View {
        SectionHeading(title: section.title, caption: section.caption, isDimmed: false)
            .offset(x: frame.minX + 4)

        Self.shape
            .fill(section.tint.opacity(0.1))
            .overlay {
                ZStack {
                    Self.shape.fill(section.tint.opacity(0.1))
                    Self.shape.strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                }
                .animation(.easeOut(duration: 0.15)) { $0.opacity(isDropTarget ? 1 : 0) }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}

private struct ItemChip: View {
    enum Status { case shown, doesNotFit, notDrawn, placedByMacOS }

    let name: String
    let icon: NSImage?
    let status: Status
    let isLifted: Bool

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        let isNotDrawn = status == .notDrawn
        VStack(spacing: isNotDrawn ? 3 : 4) {
            if isNotDrawn {
                iconImage
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
                    .opacity(0.5)
                    .background(Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            } else {
                iconImage.frame(height: 24)
            }
            Text(name)
                .font(Font(ArrangeContent.nameFont))
                .lineLimit(1)
                .foregroundStyle(isNotDrawn ? .secondary : .primary)
            if isNotDrawn {
                Text("Not showing").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .opacity(isDimmed ? 0.45 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isLifted {
                Self.shape
                    .fill(.regularMaterial)
                    .overlay { GlassBevel(shape: Self.shape) }
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            } else if isHovered {
                Self.shape
                    .fill(.white.opacity(colorScheme == .dark ? 0.07 : 0.45))
                    .overlay { GlassBevel(shape: Self.shape) }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 1.5, y: 1)
            }
        }
        .contentShape(Self.shape)
        .scaleEffect(isLifted ? 1.08 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isLifted)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = status != .placedByMacOS && $0 }
        .help(help)
    }

    private var isDimmed: Bool {
        status == .doesNotFit || status == .placedByMacOS
    }

    @ViewBuilder private var iconImage: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: icon.size.width, maxHeight: icon.size.height)
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

/// A thin edge lit from above, bright along the top and fading down, as on
/// a pane of glass.
private struct GlassBevel<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.9), .white.opacity(colorScheme == .dark ? 0.03 : 0.2)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.75
        )
    }
}

/// Parallel lines from bottom left to top right, filling the frame.
private struct DiagonalLines: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            var x = rect.minX - rect.height
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += spacing
            }
        }
    }
}

private struct DividerChip: View {
    let role: BarbarianCore.Divider
    let isLifted: Bool

    var body: some View {
        VStack(spacing: 5) {
            Capsule().frame(width: 3, height: 16)
            Image(systemName: role.symbolName)
                .font(.system(size: 9, weight: .heavy))
            Capsule().frame(width: 3, height: 16)
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
