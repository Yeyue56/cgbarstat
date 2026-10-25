import XCTest
@testable import CGBarStatCore

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
        XCTAssertEqual(MenuBarLabel.cursorModels(snapshot).percentText, "62.4%")
        XCTAssertEqual(MenuBarLabel.otherModels(snapshot).percentText, "2.60%")
        XCTAssertEqual(MenuBarLabel.grokBot(snapshot).abbreviation, "GB")
        XCTAssertEqual(MenuBarLabel.grokBot(snapshot).percentText, "46.0%")
        XCTAssertEqual(MenuBarLabel.cursorModels(snapshot).accessibilityText, "Cursor Models 62.4%")
    }

    func testPercentKeepsOneDecimalUntilSingleDigits() {
        XCTAssertEqual(PercentText.format(62.44), "62.4%")
        XCTAssertEqual(PercentText.format(62.45), "62.5%")
        XCTAssertEqual(PercentText.format(10), "10.0%")
        XCTAssertEqual(PercentText.format(9.994), "9.99%")
        XCTAssertEqual(PercentText.format(9.996), "10.0%")
        XCTAssertEqual(PercentText.format(2.6), "2.60%")
        XCTAssertEqual(PercentText.format(0), "0.00%")
        XCTAssertEqual(PercentText.format(100.26), "100.3%")
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
        XCTAssertEqual(panel.percentText, "62.0%")
        XCTAssertEqual(panel.periodTokensText, "10K")
        XCTAssertEqual(panel.todayShareText, "今日 25.0%")
        XCTAssertEqual(panel.todayTokensText, "2.5K")
        XCTAssertEqual(panel.rows.map(\.name), ["claude-sonnet", "gpt-5"])
        XCTAssertEqual(panel.rows.map(\.percentText), ["75.0%", "25.0%"])
        XCTAssertEqual(panel.rows.map(\.tokensText), ["7.5K", "2.5K"])
        XCTAssertEqual(panel.rows[0].fraction, 0.75, accuracy: 0.001)
        XCTAssertNil(panel.staleText)
    }

    func testMissingTokensStayDash() {
        let pool = ModelPool(percent: 10, periodTokens: nil, todayTokens: nil, models: [])
        let panel = PoolPanelCopy.make(pool: pool, isStale: true)
        XCTAssertEqual(panel.percentText, "10.0%")
        XCTAssertEqual(panel.periodTokensText, "—")
        XCTAssertEqual(panel.todayShareText, "今日 —")
        XCTAssertEqual(panel.todayTokensText, "—")
        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertEqual(panel.staleText, "数据已过期")
    }

    func testPlanExpiryUsesDayHourCountdownUntilItEnds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(PlanExpiry.text(now: now, periodEnd: nil))
        XCTAssertEqual(PlanExpiry.text(now: now, periodEnd: now), "套餐已过期")
        XCTAssertEqual(PlanExpiry.text(now: now, periodEnd: now.addingTimeInterval(-1)), "套餐已过期")
        XCTAssertEqual(PlanExpiry.text(now: now, periodEnd: now.addingTimeInterval(90 * 60)), "1小时30分钟后过期")
        XCTAssertEqual(PlanExpiry.text(now: now, periodEnd: now.addingTimeInterval(26 * 3600)), "1天2小时后过期")
    }

    func testPoolPanelShowsPlanExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let pool = ModelPool(percent: 10, periodTokens: nil, todayTokens: nil, models: [])
        let panel = PoolPanelCopy.make(
            pool: pool,
            isStale: false,
            now: now,
            periodEnd: now.addingTimeInterval(26 * 3600)
        )
        XCTAssertEqual(panel.expiryText, "1天2小时后过期")
        XCTAssertNil(panel.staleText)
    }

    func testResetCountdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: nil), "重置时间未知")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(-5)), "0小时0分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(30)), "0小时1分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(90 * 60)), "1小时30分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(23 * 3600)), "23小时0分钟")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(24 * 3600)), "1天0小时")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(26 * 3600)), "1天2小时")
        XCTAssertEqual(ResetCountdown.text(now: now, resetAt: now.addingTimeInterval(59 * 60)), "0小时59分钟")
    }

    func testGrokPanelAppendsResetSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = GrokBotUsage(allowance: .included, percent: 46, resetAt: now.addingTimeInterval(90 * 60))
        XCTAssertEqual(GrokPanelCopy.make(usage: soon, now: now, isStale: false).resetText, "1小时30分钟后重置")
        let later = GrokBotUsage(allowance: .included, percent: 46, resetAt: now.addingTimeInterval(26 * 3600))
        XCTAssertEqual(GrokPanelCopy.make(usage: later, now: now, isStale: false).resetText, "1天2小时后重置")
        let unknown = GrokBotUsage(allowance: .included, percent: 12, resetAt: nil)
        XCTAssertEqual(GrokPanelCopy.make(usage: unknown, now: now, isStale: false).resetText, "重置时间未知")
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
            cursorModels: ModelPool(percent: cursor, periodTokens: nil, todayTokens: nil, models: []),
            otherModels: ModelPool(percent: other, periodTokens: nil, todayTokens: nil, models: []),
            grokBot: GrokBotUsage(allowance: .included, percent: grok, resetAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 10),
            cursorStale: false,
            grokStale: false
        )
    }
}
