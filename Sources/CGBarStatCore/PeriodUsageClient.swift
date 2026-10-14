import Foundation

public enum CursorAPI {
    public static let periodUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let aggregatedUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents")!
    public static let sandUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
}

public enum UsageClientError: Error, Equatable {
    case unauthorized
    case transport
    case unrecognized
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var data: Data
    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/**
 * 拉取两个模型池和 Grok Bot。
 * 错误值不携带响应正文，避免把令牌写进日志。
 */
public struct PeriodUsageClient: Sendable {
    public var http: any HTTPSending
    public var now: @Sendable () -> Date

    public init(http: any HTTPSending, now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.now = now
    }

    public func fetch(token: String, now: Date, calendar: Calendar) async throws -> UsageSnapshot {
        let periodData = try await request(CursorAPI.periodUsage, token: token, body: Data("{}".utf8))
        let percents: PeriodPercents
        do {
            percents = try PeriodPercentParser.parse(periodData)
        } catch {
            throw UsageClientError.unrecognized
        }
        var cursor = ModelPool(percent: percents.cursorPercent, periodTokens: nil, todayTokens: nil, models: [])
        var other = ModelPool(percent: percents.otherPercent, periodTokens: nil, todayTokens: nil, models: [])
        if let start = percents.periodStart, start <= now {
            let periodModels = try? await models(token: token, from: start, to: now)
            let todayStart = calendar.startOfDay(for: now)
            let todayModels = try? await models(token: token, from: todayStart, to: now)
            if let periodModels, let todayModels {
                let assembled = PoolAssembler.assemble(
                    period: periodModels,
                    today: todayModels,
                    cursorPercent: percents.cursorPercent,
                    otherPercent: percents.otherPercent
                )
                cursor = assembled.cursor
                other = assembled.other
            }
        }
        var grok = GrokBotUsage.unknown
        var grokStale = true
        if let sandData = try? await request(CursorAPI.sandUsage, token: token, body: Data("{}".utf8)),
           let parsed = try? SandUsageParser.parse(sandData) {
            grok = parsed
            grokStale = false
        }
        return UsageSnapshot(
            cursorModels: cursor,
            otherModels: other,
            grokBot: grok,
            fetchedAt: now,
            cursorStale: false,
            grokStale: grokStale
        )
    }

    private func models(token: String, from start: Date, to end: Date) async throws -> [ModelUsage] {
        let payload: [String: Any] = [
            "teamId": -1,
            "startDate": Int(start.timeIntervalSince1970 * 1000),
            "endDate": Int(end.timeIntervalSince1970 * 1000),
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(CursorAPI.aggregatedUsage, token: token, body: body)
        return try AggregationParser.models(data)
    }

    private func request(_ url: URL, token: String, body: Data) async throws -> Data {
        guard url.scheme == "https", url.host == "api2.cursor.sh" else {
            throw UsageClientError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.transport
        }
        if response.data.count > 1_048_576 {
            throw UsageClientError.transport
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw UsageClientError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.transport
        }
        return response.data
    }
}
