import Foundation

public enum CursorAPI {
    public static let periodUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let planInfo = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
    public static let aggregatedUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents")!
    public static let sandUsage = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
    public static let oauthToken = URL(string: "https://api2.cursor.sh/oauth/token")!
    public static let dashboardPeriodUsage = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!
    /// Cursor 桌面端公开的 OAuth client id，不是用户密钥。
    public static let oauthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
}

public struct RefreshedCursorSession: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?

    public init(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct PreparedUsageFetch: Equatable, Sendable {
    public var snapshot: UsageSnapshot
    public var accessToken: String
    public var refreshToken: String?

    public init(snapshot: UsageSnapshot, accessToken: String, refreshToken: String?) {
        self.snapshot = snapshot
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public enum UsageClientError: Error, Equatable {
    case unauthorized
    /// 服务端要求退出。保存的 refresh token 已不能换新的 access token。
    case loginExpired
    case transport
    case unrecognized
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var data: Data
    public var location: URL?

    public init(statusCode: Int, data: Data, location: URL? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.location = location
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

    /// access token 被拒绝时用 refresh token 换一次，再用新 token 拉用量。
    /// 返回的令牌只交给调用方写回 Cursor 的数据库，不进入快照。
    public func fetchPrepared(
        accessToken: String,
        refreshToken: String?,
        sessionUserId: String? = nil,
        now: Date,
        calendar: Calendar
    ) async throws -> PreparedUsageFetch {
        do {
            let snapshot = try await fetch(token: accessToken, now: now, calendar: calendar)
            return PreparedUsageFetch(snapshot: snapshot, accessToken: accessToken, refreshToken: refreshToken)
        } catch UsageClientError.unauthorized {
            for cookie in CursorSessionCookie.candidates(userId: sessionUserId, accessToken: accessToken) {
                if let snapshot = try? await fetchDashboard(
                    cookie: cookie,
                    accessToken: accessToken,
                    now: now,
                    calendar: calendar
                ) {
                    return PreparedUsageFetch(snapshot: snapshot, accessToken: accessToken, refreshToken: refreshToken)
                }
            }
            guard let refreshToken, !refreshToken.isEmpty else {
                throw UsageClientError.loginExpired
            }
            let refreshed: RefreshedCursorSession
            do {
                refreshed = try await refreshSession(refreshToken: refreshToken)
            } catch UsageClientError.loginExpired {
                throw UsageClientError.loginExpired
            }
            let snapshot = try await fetch(token: refreshed.accessToken, now: now, calendar: calendar)
            return PreparedUsageFetch(
                snapshot: snapshot,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? refreshToken
            )
        }
    }

    public func refreshSession(refreshToken: String) async throws -> RefreshedCursorSession {
        let payload: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": CursorAPI.oauthClientID,
            "refresh_token": refreshToken,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await post(CursorAPI.oauthToken, token: nil, body: body, connect: false)
        do {
            return try TokenRefreshParser.parse(data)
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.unrecognized
        }
    }

    public func fetch(token: String, now: Date, calendar: Calendar) async throws -> UsageSnapshot {
        let periodData: Data
        do {
            periodData = try await request(CursorAPI.periodUsage, token: token, body: Data("{}".utf8))
        } catch UsageClientError.unauthorized {
            // 本机令牌还在。用量接口拒绝不等于未登录，套餐过期时会走这里。
            return try await snapshotWhenPeriodRejected(token: token, now: now)
        }
        return try await snapshot(fromPeriod: periodData, token: token, now: now, calendar: calendar)
    }

    /// api2 的 Bearer 被拒绝时，仪表盘仍可能认同一枚会话。
    /// 自动重定向仍拒绝；只手动再请求一次允许名单里的 HTTPS 地址。
    private func fetchDashboard(cookie: String, accessToken: String, now: Date, calendar: Calendar) async throws -> UsageSnapshot {
        let data = try await post(
            CursorAPI.dashboardPeriodUsage,
            token: nil,
            cookie: cookie,
            origin: "https://cursor.com",
            referer: "https://cursor.com/dashboard/spending",
            body: Data("{}".utf8),
            connect: false
        )
        return try await snapshot(fromPeriod: data, token: accessToken, now: now, calendar: calendar)
    }

    private func snapshot(fromPeriod periodData: Data, token: String, now: Date, calendar: Calendar) async throws -> UsageSnapshot {
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
            grokStale: grokStale,
            periodEnd: percents.periodEnd
        )
    }

    /// 用量接口返回 401/403 时改读套餐期限。期限接口同样拒绝，才把 unauthorized 交回去。
    private func snapshotWhenPeriodRejected(token: String, now: Date) async throws -> UsageSnapshot {
        let planData = try await request(CursorAPI.planInfo, token: token, body: Data("{}".utf8))
        let end: Date
        do {
            end = try PlanInfoParser.periodEnd(planData)
        } catch {
            throw UsageClientError.unrecognized
        }
        var grok = GrokBotUsage.unknown
        var grokStale = true
        if let sandData = try? await request(CursorAPI.sandUsage, token: token, body: Data("{}".utf8)),
           let parsed = try? SandUsageParser.parse(sandData) {
            grok = parsed
            grokStale = false
        }
        return UsageSnapshot(
            cursorModels: .empty,
            otherModels: .empty,
            grokBot: grok,
            fetchedAt: now,
            cursorStale: false,
            grokStale: grokStale,
            periodEnd: end
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
        try await post(url, token: token, body: body)
    }

    private func post(
        _ url: URL,
        token: String?,
        cookie: String? = nil,
        origin: String? = nil,
        referer: String? = nil,
        body: Data,
        connect: Bool = true,
        redirected: Bool = false
    ) async throws -> Data {
        guard url.scheme == "https", let host = url.host, Self.allowedHosts.contains(host) else {
            throw UsageClientError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if connect {
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        }
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
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
        if (300..<400).contains(response.statusCode) {
            guard !redirected,
                  let location = response.location,
                  location.scheme == "https",
                  let host = location.host,
                  Self.allowedHosts.contains(host) else {
                throw UsageClientError.transport
            }
            return try await post(
                location,
                token: token,
                cookie: cookie,
                origin: origin,
                referer: referer,
                body: body,
                connect: connect,
                redirected: true
            )
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw UsageClientError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UsageClientError.transport
        }
        return response.data
    }

    private static let allowedHosts: Set<String> = ["api2.cursor.sh", "cursor.com", "www.cursor.com"]
}

enum CursorSessionCookie {
    /// 本机 access token 已经带 `::` 时，它本身就是仪表盘会话，不再套一层用户标识。
    static func candidates(userId: String?, accessToken: String) -> [String] {
        var headers: [String] = []
        func append(_ header: String) {
            if !headers.contains(header) { headers.append(header) }
        }
        if accessToken.contains("::") {
            append(header(pair: accessToken))
        }
        if let userId {
            for id in userIds(from: userId) where !id.isEmpty {
                append(header(userId: id, accessToken: accessToken))
            }
        }
        return headers
    }

    /// `::` 必须编码。用户标识里 `|` 后面的一段是仪表盘常用的 user id。
    static func header(userId: String, accessToken: String) -> String {
        header(pair: "\(userId)::\(accessToken)")
    }

    static func userIds(from authId: String) -> [String] {
        var ids = [authId]
        if let suffix = authId.split(separator: "|", omittingEmptySubsequences: true).last {
            let text = String(suffix)
            if text != authId { ids.append(text) }
        }
        return ids
    }

    private static func header(pair: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        let encoded = pair.addingPercentEncoding(withAllowedCharacters: allowed) ?? pair
        return "WorkosCursorSessionToken=\(encoded)"
    }
}

enum TokenRefreshParser {
    /// shouldLogout 或缺少 access token 时不把响应当成新登录。
    static func parse(_ data: Data) throws -> RefreshedCursorSession {
        guard let root = CursorJSON.object(data) else {
            throw UsageClientError.unrecognized
        }
        if CursorJSON.bool(root, key: "shouldLogout") == true {
            throw UsageClientError.loginExpired
        }
        let access = string(root, keys: ["access_token", "accessToken"])
        guard let access, !access.isEmpty else {
            throw UsageClientError.unrecognized
        }
        let refresh = string(root, keys: ["refresh_token", "refreshToken"])
        return RefreshedCursorSession(accessToken: access, refreshToken: refresh)
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
