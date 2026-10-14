import XCTest
@testable import StipendCore

final class HoverSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testHoverShowsAfterDelayAndHidesAfterLeave() {
        var phase = HoverReducer.reduce(.idle, .pointerEnteredItem(t0))
        XCTAssertEqual(phase, .pendingShow(since: t0))
        XCTAssertFalse(phase.showsPanel)
        phase = HoverReducer.reduce(phase, .tick(t0.addingTimeInterval(0.17)))
        XCTAssertEqual(phase, .pendingShow(since: t0))
        phase = HoverReducer.reduce(phase, .tick(t0.addingTimeInterval(0.18)))
        XCTAssertEqual(phase, .preview)
        let left = t0.addingTimeInterval(1)
        phase = HoverReducer.reduce(phase, .pointerExitedItem(left))
        phase = HoverReducer.reduce(phase, .tick(left.addingTimeInterval(0.28)))
        XCTAssertEqual(phase, .idle)
    }

    func testCrossingIntoPanelCancelsHide() {
        let hiding = HoverPhase.pendingHide(since: t0)
        XCTAssertEqual(HoverReducer.reduce(hiding, .pointerEnteredPanel(t0.addingTimeInterval(0.1))), .preview)
    }

    func testClickPinsUntilOutsideClick() {
        XCTAssertEqual(HoverReducer.reduce(.idle, .clickItem), .pinned)
        XCTAssertEqual(HoverReducer.reduce(.pinned, .pointerExitedItem(t0)), .pinned)
        XCTAssertEqual(HoverReducer.reduce(.pinned, .clickOutside), .idle)
    }

    func testOpeningOneMeterClosesTheOthers() {
        var phases = MeterOrder.visualOrder.reduce(into: [Meter: HoverPhase]()) { $0[$1] = .idle }
        phases = MeterFocus.apply(phases: phases, meter: .cursorModels, event: .clickItem)
        XCTAssertEqual(phases[.cursorModels], .pinned)
        XCTAssertEqual(phases[.otherModels], .idle)
        XCTAssertEqual(phases[.grokBot], .idle)
        phases[.otherModels] = .preview
        phases = MeterFocus.apply(phases: phases, meter: .grokBot, event: .clickItem)
        XCTAssertEqual(phases[.grokBot], .pinned)
        XCTAssertEqual(phases[.cursorModels], .idle)
        XCTAssertEqual(phases[.otherModels], .idle)
    }

    func testVisualOrderIsLeftToRight() {
        XCTAssertEqual(MeterOrder.visualOrder, [.cursorModels, .otherModels, .grokBot])
        XCTAssertEqual(MeterOrder.creationOrder, [.grokBot, .otherModels, .cursorModels])
        XCTAssertEqual(Array(MeterOrder.creationOrder.reversed()), MeterOrder.visualOrder)
    }

    func testTimingConstants() {
        XCTAssertEqual(HoverTiming.showDelay, 0.18)
        XCTAssertEqual(HoverTiming.hideDelay, 0.28)
        XCTAssertEqual(HoverTiming.panelOverlapPoints, 1)
    }
}
