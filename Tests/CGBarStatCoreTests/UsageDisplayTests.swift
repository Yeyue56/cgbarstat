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

    func testUsageRejectionKeepsPreviousSnapshot() {
        let current = sample(cursor: 62, grok: 10, cursorStale: false, grokStale: false)
        let kept = DisplayUpdate.keepingLastSnapshot(current: .ready(current), cached: nil)
        guard case .ready(let snapshot) = kept else { return XCTFail("expected ready") }
        XCTAssertEqual(snapshot.cursorModels.percent, 62)
        XCTAssertTrue(snapshot.cursorStale)
        XCTAssertTrue(snapshot.grokStale)
    }

    func testUsageRejectionWithoutSnapshotIsUnavailable() {
        XCTAssertEqual(DisplayUpdate.keepingLastSnapshot(current: .signedOut, cached: nil), .unavailable)
    }

    func testMergeKeepsPreviousPoolsWhenIncomingHasNoNumbers() {
        let previous = sample(cursor: 62, grok: 10, cursorStale: false, grokStale: false)
        var incoming = sample(cursor: 0, grok: 10, cursorStale: false, grokStale: true)
        incoming.cursorModels = .empty
        incoming.otherModels = .empty
        incoming.periodEnd = Date(timeIntervalSince1970: 2_000)
        let merged = DisplayUpdate.merged(previous: previous, incoming: incoming)
        XCTAssertEqual(merged.cursorModels.percent, 62)
        XCTAssertTrue(merged.cursorStale)
        XCTAssertEqual(merged.grokBot.percent, 10)
        XCTAssertTrue(merged.grokStale)
        XCTAssertEqual(merged.periodEnd, Date(timeIntervalSince1970: 2_000))
    }

    func testMergeReplacesPoolsWhenRenewedPlanHasPercents() {
        let previous = sample(cursor: 62, grok: 10, cursorStale: true, grokStale: true)
        var incoming = sample(cursor: 4, grok: 8, cursorStale: false, grokStale: false)
        incoming.periodEnd = Date(timeIntervalSince1970: 5_000)
        let merged = DisplayUpdate.merged(previous: previous, incoming: incoming)
        XCTAssertEqual(merged.cursorModels.percent, 4)
        XCTAssertFalse(merged.cursorStale)
        XCTAssertEqual(merged.periodEnd, Date(timeIntervalSince1970: 5_000))
    }

    func testPanelRefreshWaitsThirtySeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(RefreshPolicy.shouldRefresh(lastSuccess: now.addingTimeInterval(-29), now: now, reason: .panelOpened))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(lastSuccess: now.addingTimeInterval(-30), now: now, reason: .panelOpened))
        XCTAssertEqual(RefreshPolicy.timerInterval, 300)
        XCTAssertEqual(RefreshPolicy.loginExpiredInterval, 15)
        XCTAssertEqual(RefreshPolicy.timerInterval(for: .loginExpired), 15)
        XCTAssertEqual(RefreshPolicy.timerInterval(for: .signedOut), 300)
        XCTAssertEqual(RefreshPolicy.timerInterval(for: .encryptedLogin), 300)
        XCTAssertEqual(DisplayUpdate.labels(for: .encryptedLogin).map(\.percentText), ["—", "—", "—"])
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
