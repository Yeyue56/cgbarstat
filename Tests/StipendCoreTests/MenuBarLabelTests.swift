import XCTest
@testable import StipendCore

final class MenuBarLabelTests: XCTestCase {
    func testTokenUnits() {
        XCTAssertEqual(TokenQuantity.format(0), "0")
        XCTAssertEqual(TokenQuantity.format(999), "999")
        XCTAssertEqual(TokenQuantity.format(1000), "1K")
        XCTAssertEqual(TokenQuantity.format(1200), "1.2K")
        XCTAssertEqual(TokenQuantity.format(1499), "1.5K")
        XCTAssertEqual(TokenQuantity.format(999_950), "1M")
        XCTAssertEqual(TokenQuantity.format(1_000_000), "1M")
        XCTAssertEqual(TokenQuantity.format(1_500_000), "1.5M")
        XCTAssertEqual(TokenQuantity.format(1_000_000_000), "1B")
    }

    func testStatusItemsKeepAbbreviationsWithoutPercent() {
        let labels = MenuBarLabel.placeholders()
        XCTAssertEqual(labels.map(\.abbreviation), ["CM", "OM", "GB"])
        XCTAssertEqual(labels.map(\.percentText), ["—", "—", "—"])
    }

    func testStatusItemsUseRoundedPercents() {
        let snapshot = sampleSnapshot(cursor: 62.4, other: 2.6, grok: 46)
        XCTAssertEqual(MenuBarLabel.cursorModels(snapshot).abbreviation, "CM")
        XCTAssertEqual(MenuBarLabel.cursorModels(snapshot).percentText, "62%")
        XCTAssertEqual(MenuBarLabel.otherModels(snapshot).percentText, "3%")
        XCTAssertEqual(MenuBarLabel.grokBot(snapshot).abbreviation, "GB")
        XCTAssertEqual(MenuBarLabel.grokBot(snapshot).percentText, "46%")
        XCTAssertEqual(MenuBarLabel.cursorModels(snapshot).accessibilityText, "Cursor Models 62%")
    }

    func testPoolPanelShowsTodayShareAndModelRows() {
        let pool = ModelPool(
            percent: 62,
            periodTokens: 10_000,
            todayTokens: 2_500,
            models: [
                ModelUsage(name: "claude-sonnet", tokens: 7_500),
                ModelUsage(name: "gpt-5", tokens: 2_500),
            ]
        )
        let panel = PoolPanelCopy.make(pool: pool, isStale: false)
        XCTAssertEqual(panel.percentText, "62%")
        XCTAssertEqual(panel.periodTokensText, "10K")
        XCTAssertEqual(panel.todayShareText, "今日 25%")
        XCTAssertEqual(panel.todayTokensText, "2.5K")
        XCTAssertEqual(panel.rows.map(\.name), ["claude-sonnet", "gpt-5"])
        XCTAssertEqual(panel.rows.map(\.percentText), ["75%", "25%"])
        XCTAssertEqual(panel.rows.map(\.tokensText), ["7.5K", "2.5K"])
        XCTAssertEqual(panel.rows[0].fraction, 0.75, accuracy: 0.001)
        XCTAssertNil(panel.staleText)
    }

    func testMissingTokensStayDash() {
        let pool = ModelPool(percent: 10, periodTokens: nil, todayTokens: nil, models: [])
        let panel = PoolPanelCopy.make(pool: pool, isStale: true)
        XCTAssertEqual(panel.percentText, "10%")
        XCTAssertEqual(panel.periodTokensText, "—")
        XCTAssertEqual(panel.todayShareText, "今日 —")
        XCTAssertEqual(panel.todayTokensText, "—")
        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertEqual(panel.staleText, "数据已过期")
    }

    func testResetCountdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: nil), "重置时间未知")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(-5)), "0分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(30)), "1分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(90 * 60)), "0天1小时")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(26 * 3600)), "1天2小时")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(59 * 60)), "59分钟")
    }

    func testGrokPanelWithoutAllowance() {
        let usage = GrokBotUsage(allowance: .notIncluded, percent: nil, resetAt: nil)
        let panel = GrokPanelCopy.make(usage: usage, now: Date(), isStale: false)
        XCTAssertEqual(panel.percentText, "—")
        XCTAssertEqual(panel.allowanceText, "当前账号没有单独的 Grok Bot 额度")
        XCTAssertNil(panel.resetText)
    }

    private func sampleSnapshot(cursor: Double, other: Double, grok: Double) -> UsageSnapshot {
        UsageSnapshot(
            cursorModels: ModelPool(percent: Int(cursor.rounded()), periodTokens: nil, todayTokens: nil, models: []),
            otherModels: ModelPool(percent: Int(other.rounded()), periodTokens: nil, todayTokens: nil, models: []),
            grokBot: GrokBotUsage(allowance: .included, percent: Int(grok.rounded()), resetAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 10),
            cursorStale: false,
            grokStale: false
        )
    }
}
