import XCTest
@testable import StipendCore

final class PeriodUsageClientTests: XCTestCase {
    func testFetchesPercentsTokensAndGrokBot() async throws {
        let log = RequestLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let http = ScriptedHTTP { request in
            log.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("GetCurrentPeriodUsage") {
                let body = #"{"billingCycleStart":"2026-04-02T00:00:00Z","planUsage":{"autoPercentUsed":62,"apiPercentUsed":40}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            if path.hasSuffix("GetAggregatedUsageEvents") {
                let body = #"{"aggregations":[{"modelIntent":"composer-2.5","inputTokens":"1000"},{"modelIntent":"claude-sonnet","outputTokens":"2000"}]}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            let sand = #"{"usagePercent":46,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":1760086400000}"#
            return HTTPResponse(statusCode: 200, data: Data(sand.utf8))
        }
        let snapshot = try await PeriodUsageClient(http: http, now: { now }).fetch(token: "test-token", now: now, calendar: calendar)
        XCTAssertEqual(snapshot.cursorModels.percent, 62)
        XCTAssertEqual(snapshot.otherModels.percent, 40)
        XCTAssertEqual(snapshot.cursorModels.periodTokens, 1000)
        XCTAssertEqual(snapshot.otherModels.periodTokens, 2000)
        XCTAssertEqual(snapshot.grokBot.percent, 46)
        XCTAssertFalse(snapshot.cursorStale)
        XCTAssertFalse(snapshot.grokStale)

        let requests = log.all()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.host, "api2.cursor.sh")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(requests[0].httpBody, Data("{}".utf8))
    }

    func testUnauthorizedStopsBeforeLaterRequests() async {
        let log = RequestLog()
        let http = ScriptedHTTP { request in
            log.append(request)
            return HTTPResponse(statusCode: 401, data: Data("{}".utf8))
        }
        do {
            _ = try await PeriodUsageClient(http: http, now: { Date() }).fetch(token: "test-token", now: Date(), calendar: .current)
            XCTFail("expected unauthorized")
        } catch UsageClientError.unauthorized {
            XCTAssertEqual(log.all().count, 1)
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testSandFailureKeepsCursorPools() async throws {
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("GetCurrentPeriodUsage") {
                let body = #"{"billingCycleStart":"2026-04-02T00:00:00Z","planUsage":{"autoPercentUsed":10,"apiPercentUsed":20}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            if path.hasSuffix("GetAggregatedUsageEvents") {
                return HTTPResponse(statusCode: 200, data: Data(#"{"aggregations":[]}"#.utf8))
            }
            return HTTPResponse(statusCode: 500, data: Data())
        }
        let snapshot = try await PeriodUsageClient(http: http, now: { Date(timeIntervalSince1970: 10) }).fetch(
            token: "test-token",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: .current
        )
        XCTAssertEqual(snapshot.cursorModels.percent, 10)
        XCTAssertEqual(snapshot.grokBot.allowance, .unknown)
        XCTAssertNil(snapshot.grokBot.percent)
        XCTAssertTrue(snapshot.grokStale)
        XCTAssertFalse(snapshot.cursorStale)
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLRequest] = []
    func append(_ request: URLRequest) {
        lock.lock()
        items.append(request)
        lock.unlock()
    }
    func all() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private struct ScriptedHTTP: HTTPSending {
    var handler: @Sendable (URLRequest) throws -> HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try handler(request)
    }
}
