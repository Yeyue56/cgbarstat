import Foundation

public enum UsageDisplay: Equatable, Sendable {
    case ready(UsageSnapshot)
    case signedOut
    case loginExpired
    /// 数据库里的登录已加密，钥匙串还没允许解密。
    case encryptedLogin
    case unavailable
}

public enum FailedPart: Equatable, Sendable {
    case cursorModels
    case grokBot
}

public enum DisplayUpdate {
    public static func signedOut() -> UsageDisplay { .signedOut }

    public static func labels(for display: UsageDisplay) -> [StatusItemLabel] {
        switch display {
        case .ready(let snapshot):
            return [
                MenuBarLabel.cursorModels(snapshot),
                MenuBarLabel.otherModels(snapshot),
                MenuBarLabel.grokBot(snapshot),
            ]
        case .signedOut, .loginExpired, .encryptedLogin, .unavailable:
            return MenuBarLabel.placeholders()
        }
    }

    public static func success(_ snapshot: UsageSnapshot) -> UsageDisplay {
        .ready(snapshot)
    }

    /// 本地已经读到令牌，但这次没有拿到新的用量。保留上一份快照并标成过期数据。
    /// 没有上一份时用 unavailable，不能记成 signedOut：套餐到期的拒绝和未登录不是同一件事。
    public static func keepingLastSnapshot(current: UsageDisplay, cached: UsageSnapshot?) -> UsageDisplay {
        if case .ready(var previous) = current {
            previous.cursorStale = true
            previous.grokStale = true
            return .ready(previous)
        }
        if var cached {
            cached.cursorStale = true
            cached.grokStale = true
            return .ready(cached)
        }
        return .unavailable
    }

    /// 新响应没有模型池数字时，沿用上一份 CM/OM，避免一次套餐接口拒绝把百分比清掉。
    /// 新的 periodEnd 仍然采用。Grok 这次没有读到时沿用上一份。
    public static func merged(previous: UsageSnapshot?, incoming: UsageSnapshot) -> UsageSnapshot {
        guard let previous else { return incoming }
        var copy = incoming
        if incoming.grokStale {
            copy.grokBot = previous.grokBot
            copy.grokStale = true
        }
        let hasPoolNumbers = incoming.cursorModels.percent != nil
            || incoming.otherModels.percent != nil
            || incoming.cursorModels.periodTokens != nil
            || incoming.otherModels.periodTokens != nil
        if !hasPoolNumbers {
            copy.cursorModels = previous.cursorModels
            copy.otherModels = previous.otherModels
            copy.cursorStale = true
        }
        if copy.periodEnd == nil {
            copy.periodEnd = previous.periodEnd
        }
        return copy
    }

    /// Cursor 失败时保留上一份 CM/OM，并接收这次成功的 Grok。Grok 失败时保留上一份 Grok，并接收这次的两个模型池。
    public static func failure(previous: UsageSnapshot?, incoming: UsageSnapshot, failedPart: FailedPart) -> UsageDisplay {
        guard var previous else {
            return .ready(incoming)
        }
        switch failedPart {
        case .cursorModels:
            previous.cursorStale = true
            previous.grokBot = incoming.grokBot
            previous.grokStale = incoming.grokStale
            previous.fetchedAt = incoming.fetchedAt
        case .grokBot:
            previous.grokStale = true
            previous.cursorModels = incoming.cursorModels
            previous.otherModels = incoming.otherModels
            previous.cursorStale = incoming.cursorStale
            previous.fetchedAt = incoming.fetchedAt
        }
        return .ready(previous)
    }
}

public enum RefreshReason: Equatable, Sendable {
    case launch
    case timer
    case wake
    case panelOpened
}

public enum RefreshPolicy {
    public static let timerInterval: TimeInterval = 300
    /// 登录被拒绝后缩短间隔，重新登录写入新令牌后不用退出本应用。
    public static let loginExpiredInterval: TimeInterval = 15
    public static let panelMinimumInterval: TimeInterval = 30

    public static func timerInterval(for display: UsageDisplay) -> TimeInterval {
        if case .loginExpired = display {
            return loginExpiredInterval
        }
        return timerInterval
    }

    public static func shouldRefresh(lastSuccess: Date?, now: Date, reason: RefreshReason) -> Bool {
        switch reason {
        case .launch, .timer, .wake:
            return true
        case .panelOpened:
            guard let lastSuccess else { return true }
            return now.timeIntervalSince(lastSuccess) >= panelMinimumInterval
        }
    }
}
