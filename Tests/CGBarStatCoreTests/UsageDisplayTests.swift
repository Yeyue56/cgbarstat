import XCTest
@testable import CGBarStatCore

final class UsageDisplayTests: XCTestCase {
    func testSignedOutKeepsThreeAbbreviations() {
        let labels = MenuBarLabel.placeholders()
        XCTAssertEqual(DisplayUpdate.labels(for: .signedOut).map(\.abbreviation), labels.map(\.abbreviation))
        XCTAssertEqual(DisplayUpdate.labels(for: .signedOut).map(\.percentText), ["—", "—", "—"])
    }

    func testCursorFailureKeepsPreviousCursorAndNewGrok() {
        let previous = sample(cursor: 62, grok: 10, cursorStale: false, grokStale: false)
        var incoming = sample(cursor: 70, grok: 46, cursorStale: false, grokStale: false)
        incoming.cursorModels.percent = nil
        incoming.cursorStale = true
        let merged = DisplayUpdate.failure(previous: previous, incoming: incoming, failedPart: .cursorModels)
        guard case .ready(let snapshot) = merged else { return XCTFail("expected ready") }
        XCTAssertEqual(snapshot.cursorModels.percent, 62)
        XCTAssertTrue(snapshot.cursorStale)
        XCTAssertEqual(snapshot.grokBot.percent, 46)
        XCTAssertFalse(snapshot.grokStale)
    }

    func testPanelRefreshWaitsThirtySeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(RefreshPolicy.shouldRefresh(lastSuccess: now.addingTimeInterval(-29), now: now, reason: .panelOpened))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(lastSuccess: now.addingTimeInterval(-30), now: now, reason: .panelOpened))
        XCTAssertEqual(RefreshPolicy.timerInterval, 300)
    }

    private func sample(cursor: Int, grok: Int, cursorStale: Bool, grokStale: Bool) -> UsageSnapshot {
        UsageSnapshot(
            cursorModels: ModelPool(percent: Double(cursor), periodTokens: 1000, todayTokens: 100, models: []),
            otherModels: ModelPool(percent: 20, periodTokens: 500, todayTokens: 50, models: []),
            grokBot: GrokBotUsage(allowance: .included, percent: Double(grok), resetAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 10),
            cursorStale: cursorStale,
            grokStale: grokStale
        )
    }
}
