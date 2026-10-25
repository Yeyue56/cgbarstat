import Foundation

/**
 * 模块：用量快照
 * 职责：保存三个状态项可展示的数据。
 * 边界：不包含访问令牌，不发起网络请求。
 */
public struct ModelUsage: Equatable, Sendable, Codable {
    public var name: String
    public var tokens: Int

    public init(name: String, tokens: Int) {
        self.name = name
        self.tokens = tokens
    }
}

public struct ModelPool: Equatable, Sendable, Codable {
    /// 额度百分比。nil 表示这次没有可读百分比，状态栏下行显示 —。
    public var percent: Double?
    /// 本期 Tokens。nil 表示聚合请求没有成功，不把 nil 显示成 0。
    public var periodTokens: Int?
    public var todayTokens: Int?
    public var models: [ModelUsage]

    public init(percent: Double?, periodTokens: Int?, todayTokens: Int?, models: [ModelUsage]) {
        self.percent = percent
        self.periodTokens = periodTokens
        self.todayTokens = todayTokens
        self.models = models
    }

    public static let empty = ModelPool(percent: nil, periodTokens: nil, todayTokens: nil, models: [])
}

public enum GrokAllowance: String, Equatable, Sendable, Codable {
    case included
    case notIncluded
    case unknown
}

public struct GrokBotUsage: Equatable, Sendable, Codable {
    public var allowance: GrokAllowance
    public var percent: Double?
    /// 只有响应给出 nextResetTimestampUtc 时才有值。不要用周期起点加 7 天填这个字段。
    public var resetAt: Date?

    public init(allowance: GrokAllowance, percent: Double?, resetAt: Date?) {
        self.allowance = allowance
        self.percent = percent
        self.resetAt = resetAt
    }

    public static let unknown = GrokBotUsage(allowance: .unknown, percent: nil, resetAt: nil)
}

public struct UsageSnapshot: Equatable, Sendable, Codable {
    public var cursorModels: ModelPool
    public var otherModels: ModelPool
    public var grokBot: GrokBotUsage
    public var fetchedAt: Date
    public var cursorStale: Bool
    public var grokStale: Bool
    /// 套餐周期结束时间，来自 billingCycleEnd。没有该字段时不推断到期日。
    public var periodEnd: Date?

    public init(
        cursorModels: ModelPool,
        otherModels: ModelPool,
        grokBot: GrokBotUsage,
        fetchedAt: Date,
        cursorStale: Bool,
        grokStale: Bool,
        periodEnd: Date? = nil
    ) {
        self.cursorModels = cursorModels
        self.otherModels = otherModels
        self.grokBot = grokBot
        self.fetchedAt = fetchedAt
        self.cursorStale = cursorStale
        self.grokStale = grokStale
        self.periodEnd = periodEnd
    }
}

public struct PeriodPercents: Equatable, Sendable {
    public var cursorPercent: Double?
    public var otherPercent: Double?
    public var periodStart: Date?
    public var periodEnd: Date?

    public init(cursorPercent: Double?, otherPercent: Double?, periodStart: Date?, periodEnd: Date? = nil) {
        self.cursorPercent = cursorPercent
        self.otherPercent = otherPercent
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }
}

public enum CGBarStatCoreMarker {
    public static let productName = "CGBarStat"
}
