import XCTest
@testable import CGBarStatCore

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
                let body = #"{"billingCycleStart":"2026-04-02T00:00:00Z","billingCycleEnd":"2027-02-02T00:00:00Z","planUsage":{"autoPercentUsed":62,"apiPercentUsed":40}}"#
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
        XCTAssertEqual(snapshot.periodEnd, ISO8601DateFormatter().date(from: "2027-02-02T00:00:00Z"))
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
            XCTAssertEqual(log.all().count, 2)
            XCTAssertTrue(log.all().contains { $0.url?.path.hasSuffix("GetPlanInfo") == true })
            XCTAssertFalse(log.all().contains { $0.url?.path.hasSuffix("GetAggregatedUsageEvents") == true })
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testRejectedPeriodUsageStillReadsPlanExpiry() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("GetCurrentPeriodUsage") {
                return HTTPResponse(statusCode: 401, data: Data("{}".utf8))
            }
            if path.hasSuffix("GetPlanInfo") {
                let body = #"{"planInfo":{"billingCycleEnd":"2027-02-02T00:00:00Z"}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        let snapshot = try await PeriodUsageClient(http: http, now: { now }).fetch(token: "test-token", now: now, calendar: .current)
        XCTAssertNil(snapshot.cursorModels.percent)
        XCTAssertNil(snapshot.cursorModels.periodTokens)
        XCTAssertEqual(snapshot.periodEnd, ISO8601DateFormatter().date(from: "2027-02-02T00:00:00Z"))
        XCTAssertEqual(snapshot.grokBot.allowance, .unknown)
        XCTAssertTrue(snapshot.grokStale)
    }

    func testCycleWithoutPercentsStillSucceeds() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("GetCurrentPeriodUsage") {
                let body = #"{"billingCycleEnd":"2026-01-02T00:00:00Z"}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 500, data: Data())
        }
        let snapshot = try await PeriodUsageClient(http: http, now: { now }).fetch(token: "test-token", now: now, calendar: .current)
        XCTAssertNil(snapshot.cursorModels.percent)
        XCTAssertEqual(snapshot.periodEnd, ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z"))
        XCTAssertFalse(snapshot.cursorStale)
    }

    func testUnauthorizedAccessIsRefreshedOnce() async throws {
        let log = RequestLog()
        let http = ScriptedHTTP { request in
            log.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("oauth/token") {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = #"{"access_token":"new-access","refresh_token":"new-refresh"}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            if path.hasSuffix("GetCurrentPeriodUsage") {
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
                    return HTTPResponse(statusCode: 401, data: Data(#"{"code":"unauthenticated"}"#.utf8))
                }
                let body = #"{"billingCycleEnd":"2027-02-02T00:00:00Z","planUsage":{"autoPercentUsed":12,"apiPercentUsed":3}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            if path.hasSuffix("GetPlanInfo") {
                return HTTPResponse(statusCode: 401, data: Data("{}".utf8))
            }
            return HTTPResponse(statusCode: 500, data: Data())
        }
        let prepared = try await PeriodUsageClient(http: http, now: { Date(timeIntervalSince1970: 1_800_000_000) }).fetchPrepared(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: .current
        )
        XCTAssertEqual(prepared.accessToken, "new-access")
        XCTAssertEqual(prepared.refreshToken, "new-refresh")
        XCTAssertEqual(prepared.snapshot.cursorModels.percent, 12)
        XCTAssertEqual(prepared.snapshot.otherModels.percent, 3)
        XCTAssertFalse(prepared.snapshot.cursorStale)
        let periodRequests = log.all().filter { $0.url?.path.hasSuffix("GetCurrentPeriodUsage") == true }
        XCTAssertEqual(periodRequests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer old-access", "Bearer new-access"])
        XCTAssertEqual(log.all().filter { $0.url?.path.hasSuffix("oauth/token") == true }.count, 1)
    }

    func testDashboardCookieIsUsedWhenBearerIsRejected() async throws {
        let log = RequestLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = ScriptedHTTP { request in
            log.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("get-current-period-usage") {
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                XCTAssertTrue(cookie.hasPrefix("WorkosCursorSessionToken="))
                XCTAssertTrue(cookie.contains("user_test%3A%3Aopaque-token"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Connect-Protocol-Version"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
                XCTAssertEqual(request.url?.host, "cursor.com")
                let body = #"{"billingCycleEnd":"2027-02-02T00:00:00Z","planUsage":{"autoPercentUsed":12,"apiPercentUsed":3}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        let prepared = try await PeriodUsageClient(http: http, now: { now }).fetchPrepared(
            accessToken: "opaque-token",
            refreshToken: "old-refresh",
            sessionUserId: "google-oauth2|user_test",
            now: now,
            calendar: .current
        )
        XCTAssertEqual(prepared.accessToken, "opaque-token")
        XCTAssertEqual(prepared.refreshToken, "old-refresh")
        XCTAssertEqual(prepared.snapshot.cursorModels.percent, 12)
        XCTAssertEqual(prepared.snapshot.otherModels.percent, 3)
        XCTAssertFalse(prepared.snapshot.cursorStale)
        XCTAssertEqual(log.all().filter { $0.url?.host == "cursor.com" }.count, 1)
        XCTAssertFalse(log.all().contains { $0.url?.path.hasSuffix("oauth/token") == true })
    }

    func testStoredSessionPairIsSentWithoutExtraUserId() async throws {
        let log = RequestLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = ScriptedHTTP { request in
            log.append(request)
            if request.url?.host == "cursor.com" {
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "WorkosCursorSessionToken=user_test%3A%3Aopaque-token"
                )
                let body = #"{"billingCycleEnd":"2027-02-02T00:00:00Z","planUsage":{"autoPercentUsed":4,"apiPercentUsed":5}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        let prepared = try await PeriodUsageClient(http: http, now: { now }).fetchPrepared(
            accessToken: "user_test::opaque-token",
            refreshToken: "old-refresh",
            sessionUserId: "google-oauth2|user_test",
            now: now,
            calendar: .current
        )
        XCTAssertEqual(prepared.snapshot.cursorModels.percent, 4)
        XCTAssertEqual(prepared.snapshot.otherModels.percent, 5)
        XCTAssertEqual(log.all().filter { $0.url?.host == "cursor.com" }.count, 1)
    }

    func testDashboardFollowsAllowlistedRedirect() async throws {
        let log = RequestLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = ScriptedHTTP { request in
            log.append(request)
            let host = request.url?.host ?? ""
            if host == "cursor.com" {
                return HTTPResponse(
                    statusCode: 307,
                    data: Data(),
                    location: URL(string: "https://www.cursor.com/api/dashboard/get-current-period-usage")
                )
            }
            if host == "www.cursor.com" {
                let body = #"{"billingCycleEnd":"2027-02-02T00:00:00Z","planUsage":{"autoPercentUsed":8,"apiPercentUsed":1}}"#
                return HTTPResponse(statusCode: 200, data: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        let prepared = try await PeriodUsageClient(http: http, now: { now }).fetchPrepared(
            accessToken: "opaque-token",
            refreshToken: "old-refresh",
            sessionUserId: "user_test",
            now: now,
            calendar: .current
        )
        XCTAssertEqual(prepared.snapshot.cursorModels.percent, 8)
        XCTAssertTrue(log.all().contains { $0.url?.host == "www.cursor.com" })
        XCTAssertFalse(log.all().contains { $0.url?.path.hasSuffix("oauth/token") == true })
    }

    func testDashboardDoesNotFollowForeignRedirect() async {
        let log = RequestLog()
        let http = ScriptedHTTP { request in
            log.append(request)
            if request.url?.host == "cursor.com" {
                return HTTPResponse(
                    statusCode: 307,
                    data: Data(),
                    location: URL(string: "https://evil.example/steal")
                )
            }
            if request.url?.path.hasSuffix("oauth/token") == true {
                return HTTPResponse(statusCode: 200, data: Data(#"{"access_token":"","shouldLogout":true}"#.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        do {
            _ = try await PeriodUsageClient(http: http, now: { Date() }).fetchPrepared(
                accessToken: "opaque-token",
                refreshToken: "old-refresh",
                sessionUserId: "user_test",
                now: Date(),
                calendar: .current
            )
            XCTFail("expected login expired")
        } catch UsageClientError.loginExpired {
            XCTAssertFalse(log.all().contains { $0.url?.host == "evil.example" })
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testDashboardRejectionStillAsksForLoginAgain() async {
        let log = RequestLog()
        let http = ScriptedHTTP { request in
            log.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("oauth/token") {
                return HTTPResponse(statusCode: 200, data: Data(#"{"access_token":"","shouldLogout":true}"#.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        do {
            _ = try await PeriodUsageClient(http: http, now: { Date() }).fetchPrepared(
                accessToken: "opaque-token",
                refreshToken: "old-refresh",
                sessionUserId: "google-oauth2|user_test",
                now: Date(),
                calendar: .current
            )
            XCTFail("expected login expired")
        } catch UsageClientError.loginExpired {
            XCTAssertEqual(log.all().filter { $0.url?.host == "cursor.com" }.count, 2)
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testRefreshLogoutDoesNotReturnToken() async {
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("oauth/token") {
                return HTTPResponse(statusCode: 200, data: Data(#"{"shouldLogout":true,"access_token":"ignored"}"#.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        do {
            _ = try await PeriodUsageClient(http: http, now: { Date() }).refreshSession(refreshToken: "old-refresh")
            XCTFail("expected login expired")
        } catch UsageClientError.loginExpired {
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testRejectedRefreshAsksForLoginAgain() async {
        let http = ScriptedHTTP { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("oauth/token") {
                return HTTPResponse(statusCode: 200, data: Data(#"{"access_token":"","shouldLogout":true}"#.utf8))
            }
            return HTTPResponse(statusCode: 401, data: Data())
        }
        do {
            _ = try await PeriodUsageClient(http: http, now: { Date() }).fetchPrepared(
                accessToken: "old-access",
                refreshToken: "old-refresh",
                now: Date(),
                calendar: .current
            )
            XCTFail("expected login expired")
        } catch UsageClientError.loginExpired {
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
