import XCTest
@testable import StipendCore

final class UsageParsersTests: XCTestCase {
    func testPeriodPercentsRoundAndKeepMissingPoolNil() throws {
        let json = """
        {"billingCycleStart":"2026-04-02T00:00:00Z","planUsage":{"autoPercentUsed":62.4,"apiPercentUsed":"2.6"}}
        """.data(using: .utf8)!
        let parsed = try PeriodPercentParser.parse(json)
        XCTAssertEqual(parsed.cursorPercent ?? -1, 62.4, accuracy: 0.000_001)
        XCTAssertEqual(parsed.otherPercent ?? -1, 2.6, accuracy: 0.000_001)
        XCTAssertNotNil(parsed.periodStart)
    }

    func testPeriodAcceptsMillisecondString() throws {
        let json = #"{"autoPercentUsed":10,"billingCycleStart":"1768399334000"}"#.data(using: .utf8)!
        let parsed = try PeriodPercentParser.parse(json)
        XCTAssertEqual(parsed.cursorPercent, 10)
        XCTAssertNil(parsed.otherPercent)
        XCTAssertNotNil(parsed.periodStart)
    }

    func testPeriodRejectsObjectWithoutPercents() {
        let json = #"{"planUsage":{"limit":8000}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try PeriodPercentParser.parse(json)) { error in
            XCTAssertEqual(error as? PeriodUsageParserError, .unrecognized)
        }
    }

    func testClassifierSplitsCursorAndOtherModels() {
        XCTAssertEqual(ModelPoolClassifier.kind(for: "Composer-2.5"), .cursorModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "grok-4.5"), .cursorModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "auto"), .cursorModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "auto-fast"), .cursorModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "cursor-small"), .cursorModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "claude-4.6-sonnet"), .otherModels)
        XCTAssertEqual(ModelPoolClassifier.kind(for: "gpt-5"), .otherModels)
    }

    func testAggregationSumsTokenFieldsAndDuplicateModels() throws {
        let json = """
        {"aggregations":[
          {"modelIntent":"composer-2.5","inputTokens":"1000","outputTokens":"2000","cacheWriteTokens":"300","cacheReadTokens":"700"},
          {"modelIntent":"composer-2.5","inputTokens":"1000"},
          {"modelIntent":"claude-sonnet","inputTokens":500,"outputTokens":500}
        ]}
        """.data(using: .utf8)!
        let models = try AggregationParser.models(json)
        XCTAssertEqual(models.first { $0.name == "composer-2.5" }?.tokens, 5000)
        XCTAssertEqual(models.first { $0.name == "claude-sonnet" }?.tokens, 1000)
    }

    func testAssemblerSplitsPools() {
        let period = [
            ModelUsage(name: "composer-2.5", tokens: 4000),
            ModelUsage(name: "claude-sonnet", tokens: 6000),
        ]
        let today = [
            ModelUsage(name: "composer-2.5", tokens: 1000),
            ModelUsage(name: "claude-sonnet", tokens: 500),
        ]
        let pools = PoolAssembler.assemble(period: period, today: today, cursorPercent: 62, otherPercent: 40)
        XCTAssertEqual(pools.cursor.percent, 62)
        XCTAssertEqual(pools.cursor.periodTokens, 4000)
        XCTAssertEqual(pools.cursor.todayTokens, 1000)
        XCTAssertEqual(pools.other.periodTokens, 6000)
        XCTAssertEqual(pools.other.todayTokens, 500)
        XCTAssertEqual(pools.other.models, [ModelUsage(name: "claude-sonnet", tokens: 6000)])
    }

    func testSandUsageReadsResetAndDoesNotInventSevenDays() throws {
        let json = #"{"usagePercent":46.2,"nextResetTimestampUtc":"1760000000000","hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
        let usage = try SandUsageParser.parse(json)
        XCTAssertEqual(usage.allowance, .included)
        XCTAssertEqual(usage.percent ?? -1, 46.2, accuracy: 0.000_001)
        XCTAssertEqual(usage.resetAt, Date(timeIntervalSince1970: 1_760_000_000))
    }

    func testSandUsageWithoutResetStaysNil() throws {
        let json = #"{"usagePercent":12,"hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
        let usage = try SandUsageParser.parse(json)
        XCTAssertNil(usage.resetAt)
        XCTAssertEqual(usage.percent, 12)
    }

    func testPooledEnterpriseHasNoPersonalPercent() throws {
        let json = #"{"usagePercent":80,"usesPooledEnterpriseAllowance":true,"nextResetTimestampUtc":1760000000000}"#.data(using: .utf8)!
        let usage = try SandUsageParser.parse(json)
        XCTAssertEqual(usage.allowance, .notIncluded)
        XCTAssertNil(usage.percent)
        XCTAssertNil(usage.resetAt)
    }

    func testEmptySandObjectIsUnrecognized() {
        XCTAssertThrowsError(try SandUsageParser.parse(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? PeriodUsageParserError, .unrecognized)
        }
    }

    func testPeriodPercentsAcceptZeroAndOneAsNumbers() throws {
        let json = #"{"planUsage":{"autoPercentUsed":0,"apiPercentUsed":1}}"#.data(using: .utf8)!
        let parsed = try PeriodPercentParser.parse(json)
        XCTAssertEqual(parsed.cursorPercent, 0)
        XCTAssertEqual(parsed.otherPercent, 1)
    }

    func testPeriodRejectsBooleanPercentAsUnrecognized() {
        let json = #"{"planUsage":{"autoPercentUsed":true}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try PeriodPercentParser.parse(json)) { error in
            XCTAssertEqual(error as? PeriodUsageParserError, .unrecognized)
        }
    }

    func testAggregationCountsInputTokenOne() throws {
        let json = #"{"aggregations":[{"modelIntent":"composer-2.5","inputTokens":1}]}"#.data(using: .utf8)!
        let models = try AggregationParser.models(json)
        XCTAssertEqual(models.first { $0.name == "composer-2.5" }?.tokens, 1)
    }

    func testSandUsageAcceptsZeroPercent() throws {
        let json = #"{"usagePercent":0,"hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
        let usage = try SandUsageParser.parse(json)
        XCTAssertEqual(usage.allowance, .included)
        XCTAssertEqual(usage.percent, 0)
    }
}
