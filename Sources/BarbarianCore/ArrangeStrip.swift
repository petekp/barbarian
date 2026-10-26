import CoreGraphics

/// Where the Arrange window draws the managed part of the menu bar: one row,
/// left to right, items and the two dividers in menu bar order.
///
/// The window draws entries at these frames and hit-tests the pointer
/// against a strip without the dragged entry, never against the frames
/// entries are animating through, so an entry sliding under the pointer
/// cannot change the drop target.
public struct ArrangeStrip: Sendable, Equatable {
    public enum Element: Sendable, Equatable {
        case item(width: CGFloat)
        case divider(width: CGFloat)
    }

    public struct Metrics: Sendable, Equatable {
        public var height: CGFloat
        public var spacing: CGFloat
        /// Space between a section's edge and its first or last entry.
        public var sectionPadding: CGFloat
        /// An empty section keeps this much room, so there is somewhere to
        /// drop into it.
        public var minimumSectionWidth: CGFloat

        public init(height: CGFloat, spacing: CGFloat, sectionPadding: CGFloat, minimumSectionWidth: CGFloat) {
            self.height = height
            self.spacing = spacing
            self.sectionPadding = sectionPadding
            self.minimumSectionWidth = minimumSectionWidth
        }
    }

    /// One frame per element, in order.
    public let frames: [CGRect]
    /// The x span of each section, left to right: Always Hidden, Hidden,
    /// Shown. Sections follow the dividers' positions.
    public let sectionSpans: [ClosedRange<CGFloat>]
    public let width: CGFloat

    public init(elements: [Element], metrics: Metrics) {
        var frames: [CGRect] = []
        var spans: [ClosedRange<CGFloat>] = []
        var sectionStart: CGFloat = 0
        var sectionHasItems = false
        var x = metrics.sectionPadding

        func closeSection() -> CGFloat {
            let contentEnd = sectionHasItems ? x - metrics.spacing + metrics.sectionPadding : sectionStart
            let end = max(contentEnd, sectionStart + metrics.minimumSectionWidth)
            spans.append(sectionStart...end)
            return end
        }

        for element in elements {
            switch element {
            case .item(let width):
                frames.append(CGRect(x: x, y: 0, width: width, height: metrics.height))
                x += width + metrics.spacing
                sectionHasItems = true
            case .divider(let width):
                let dividerX = closeSection() + metrics.spacing
                frames.append(CGRect(x: dividerX, y: 0, width: width, height: metrics.height))
                sectionStart = dividerX + width + metrics.spacing
                sectionHasItems = false
                x = sectionStart + metrics.sectionPadding
            }
        }
        width = closeSection()
        self.frames = frames
        sectionSpans = spans
    }

    /// Where an entry centered at `x` would be inserted among this strip's
    /// elements: the number of elements whose middle is left of `x`.
    public func insertionIndex(at x: CGFloat) -> Int {
        frames.filter { $0.midX < x }.count
    }
}
