import CoreGraphics

/// Where the Arrange window draws each section and item slot. Sections stack
/// top to bottom. Each has a header and a well, and slots wrap inside the
/// well left to right.
///
/// The window draws items at these frames and hit-tests the pointer against
/// them too. Hit-testing the frames items are animating through instead would
/// let an item sliding under the pointer change the drop target mid-slide.
public struct ArrangeGrid: Sendable, Equatable {
    public struct Metrics: Sendable, Equatable {
        public var slotSize: CGSize
        public var slotSpacing: CGFloat
        public var wellInset: CGFloat
        public var headerHeight: CGFloat
        public var sectionSpacing: CGFloat

        public init(slotSize: CGSize, slotSpacing: CGFloat, wellInset: CGFloat, headerHeight: CGFloat, sectionSpacing: CGFloat) {
            self.slotSize = slotSize
            self.slotSpacing = slotSpacing
            self.wellInset = wellInset
            self.headerHeight = headerHeight
            self.sectionSpacing = sectionSpacing
        }
    }

    public struct Section: Sendable, Equatable {
        public let headerFrame: CGRect
        public let wellFrame: CGRect
        public let slotFrames: [CGRect]
    }

    public let width: CGFloat
    public let metrics: Metrics
    public let columns: Int
    public let sections: [Section]
    public let height: CGFloat

    /// - Parameter slotCounts: the number of slots in each section, top to
    ///   bottom. An empty section still gets a well one slot high, so there is
    ///   somewhere to drop.
    public init(width: CGFloat, slotCounts: [Int], metrics: Metrics) {
        self.width = width
        self.metrics = metrics
        let pitch = metrics.slotSize.width + metrics.slotSpacing
        let usableWidth = width - 2 * metrics.wellInset + metrics.slotSpacing
        let columns = max(1, Int(usableWidth / pitch))
        self.columns = columns

        var sections: [Section] = []
        var y: CGFloat = 0
        for count in slotCounts {
            let headerFrame = CGRect(x: 0, y: y, width: width, height: metrics.headerHeight)
            let rows = max(1, (count + columns - 1) / columns)
            let wellHeight = 2 * metrics.wellInset + CGFloat(rows) * metrics.slotSize.height + CGFloat(rows - 1) * metrics.slotSpacing
            let wellFrame = CGRect(x: 0, y: headerFrame.maxY, width: width, height: wellHeight)
            let slotFrames = (0..<count).map { index in
                CGRect(
                    x: wellFrame.minX + metrics.wellInset + CGFloat(index % columns) * pitch,
                    y: wellFrame.minY + metrics.wellInset + CGFloat(index / columns) * (metrics.slotSize.height + metrics.slotSpacing),
                    width: metrics.slotSize.width,
                    height: metrics.slotSize.height
                )
            }
            sections.append(Section(headerFrame: headerFrame, wellFrame: wellFrame, slotFrames: slotFrames))
            y = wellFrame.maxY + metrics.sectionSpacing
        }
        self.sections = sections
        height = max(0, y - metrics.sectionSpacing)
    }

    /// The section among `candidates` nearest `point` vertically. A point
    /// on a section's header or well belongs to that section.
    public func section(nearest point: CGPoint, among candidates: [Int]) -> Int? {
        candidates.min { distance(from: point.y, to: $0) < distance(from: point.y, to: $1) }
    }

    /// The slot of `section` under `point`, clamped to the section's slots.
    /// Points between slots or past the last one count as the nearest slot.
    public func slot(at point: CGPoint, in section: Int) -> Int {
        let frames = sections[section].slotFrames
        guard let first = frames.first else { return 0 }
        let pitchX = metrics.slotSize.width + metrics.slotSpacing
        let pitchY = metrics.slotSize.height + metrics.slotSpacing
        let rows = (frames.count + columns - 1) / columns
        let column = min(max(Int(((point.x - first.minX + metrics.slotSpacing / 2) / pitchX).rounded(.down)), 0), columns - 1)
        let row = min(max(Int(((point.y - first.minY + metrics.slotSpacing / 2) / pitchY).rounded(.down)), 0), rows - 1)
        return min(row * columns + column, frames.count - 1)
    }

    private func distance(from y: CGFloat, to section: Int) -> CGFloat {
        let top = sections[section].headerFrame.minY
        let bottom = sections[section].wellFrame.maxY
        if y < top { return top - y }
        if y > bottom { return y - bottom }
        return 0
    }
}
