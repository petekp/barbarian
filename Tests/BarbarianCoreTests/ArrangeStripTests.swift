import CoreGraphics
import Testing
import BarbarianCore

private let metrics = ArrangeStrip.Metrics(height: 50, spacing: 4, sectionPadding: 8, minimumSectionWidth: 60)

@Test func entriesSitLeftToRightWithDividersBetweenSections() {
    let strip = ArrangeStrip(
        elements: [.item(width: 40), .divider(width: 20), .item(width: 30), .item(width: 30), .divider(width: 20), .item(width: 50)],
        metrics: metrics
    )

    #expect(strip.frames.map(\.minX) == [8, 64, 96, 130, 172, 204])
    #expect(strip.sectionSpans == [0...60, 88...168, 196...262])
    #expect(strip.width == 262)
}

@Test func anEmptySectionKeepsRoomToDropInto() {
    let strip = ArrangeStrip(elements: [.divider(width: 20), .divider(width: 20), .item(width: 40)], metrics: metrics)

    #expect(strip.sectionSpans[0] == 0...60)
    #expect(strip.sectionSpans[1] == 88...148)
    #expect(strip.frames[1].minX == 152)
}

@Test func theInsertionIndexCountsEntriesWhoseMiddleIsLeftOfThePoint() {
    let strip = ArrangeStrip(elements: [.item(width: 40), .item(width: 40), .item(width: 40)], metrics: metrics)

    #expect(strip.insertionIndex(at: 0) == 0)
    #expect(strip.insertionIndex(at: 30) == 1)
    #expect(strip.insertionIndex(at: 500) == 3)
}
