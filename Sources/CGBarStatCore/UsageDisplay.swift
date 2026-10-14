import Foundation

public enum UsageDisplay: Equatable, Sendable {
    case ready(UsageSnapshot)
    case signedOut
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
        case .signedOut, .unavailable:
            return MenuBarLabel.placeholders()
        }
    }

    public static func success(_ snapshot: UsageSnapshot) -> UsageDisplay {
        .ready(snapshot)
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
    public static let panelMinimumInterval: TimeInterval = 30

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
