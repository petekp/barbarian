import CoreGraphics
import Testing
import BarbarianCore

private let metrics = ArrangeGrid.Metrics(
    slotSize: CGSize(width: 80, height: 70), slotSpacing: 10, wellInset: 10, headerHeight: 20, sectionSpacing: 16
)

@Test func slotsWrapIntoRowsThatFitTheWidth() {
    let grid = ArrangeGrid(width: 290, slotCounts: [4], metrics: metrics)

    #expect(grid.columns == 3)
    #expect(grid.sections[0].slotFrames[2].origin == CGPoint(x: 190, y: 30))
    #expect(grid.sections[0].slotFrames[3].origin == CGPoint(x: 10, y: 110))
    #expect(grid.sections[0].wellFrame.height == 170)
}

@Test func anEmptySectionKeepsAWellOneSlotHigh() {
    let grid = ArrangeGrid(width: 290, slotCounts: [0, 1], metrics: metrics)

    #expect(grid.sections[0].wellFrame.height == 90)
    #expect(grid.sections[1].headerFrame.minY == 126)
    #expect(grid.height == 236)
}

@Test func thePointerPicksTheSlotUnderItClampedToTheSection() {
    let grid = ArrangeGrid(width: 290, slotCounts: [4], metrics: metrics)

    #expect(grid.slot(at: CGPoint(x: 120, y: 60), in: 0) == 1)
    #expect(grid.slot(at: CGPoint(x: 280, y: 150), in: 0) == 3)
    #expect(grid.slot(at: CGPoint(x: -50, y: -50), in: 0) == 0)
}

@Test func thePointerPicksTheNearestCandidateSection() {
    let grid = ArrangeGrid(width: 290, slotCounts: [1, 1, 1], metrics: metrics)

    #expect(grid.section(nearest: CGPoint(x: 0, y: 5), among: [0, 1, 2]) == 0)
    #expect(grid.section(nearest: CGPoint(x: 0, y: 150), among: [0, 1, 2]) == 1)
    #expect(grid.section(nearest: CGPoint(x: 0, y: 900), among: [0, 1]) == 1)
}
