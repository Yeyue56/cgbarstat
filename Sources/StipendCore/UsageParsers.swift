import Foundation

public enum PeriodUsageParserError: Error, Equatable {
    case unrecognized
}

public enum ModelPoolKind: Equatable, Sendable {
    case cursorModels
    case otherModels
}

public enum PeriodPercentParser {
    /// 至少要读到 auto 或 api 其中一个百分比。缺失的那个保持 nil。
    public static func parse(_ data: Data) throws -> PeriodPercents {
        guard let root = CursorJSON.object(data) else {
            throw PeriodUsageParserError.unrecognized
        }
        let usage = CursorJSON.dictionary(root, key: "planUsage") ?? root
        let cursor = CursorJSON.firstDouble(usage, keys: ["autoPercentUsed"]).flatMap(roundedPercent)
        let other = CursorJSON.firstDouble(usage, keys: ["apiPercentUsed"]).flatMap(roundedPercent)
        guard cursor != nil || other != nil else {
            throw PeriodUsageParserError.unrecognized
        }
        let start = CursorJSON.firstTimestamp(root, keys: ["billingCycleStart"])
        return PeriodPercents(cursorPercent: cursor, otherPercent: other, periodStart: start)
    }

    private static func roundedPercent(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(value.rounded())
    }
}

public enum ModelPoolClassifier {
    public static func kind(for modelIntent: String) -> ModelPoolKind {
        let name = modelIntent.lowercased()
        if name == "auto" || name.hasPrefix("auto-") || name.contains("composer") || name.contains("grok") || name.contains("cursor") {
            return .cursorModels
        }
        return .otherModels
    }
}

public enum AggregationParser {
    /// 同一 modelIntent 的多行 Tokens 相加。没有模型名的行丢弃。
    public static func models(_ data: Data) throws -> [ModelUsage] {
        guard let root = CursorJSON.object(data),
              let rows = CursorJSON.array(root, key: "aggregations") else {
            throw PeriodUsageParserError.unrecognized
        }
        var totals: [String: Int] = [:]
        for row in rows {
            guard let name = row["modelIntent"] as? String, !name.isEmpty else { continue }
            let tokens = tokenCount(row)
            totals[name, default: 0] += tokens
        }
        return totals.map { ModelUsage(name: $0.key, tokens: $0.value) }
    }

    private static func tokenCount(_ row: [String: Any]) -> Int {
        let keys = ["inputTokens", "outputTokens", "cacheWriteTokens", "cacheReadTokens"]
        return keys.reduce(0) { partial, key in
            partial + (CursorJSON.firstInt(row, keys: [key]) ?? 0)
        }
    }
}

public enum PoolAssembler {
    public static func assemble(
        period: [ModelUsage],
        today: [ModelUsage],
        cursorPercent: Int?,
        otherPercent: Int?
    ) -> (cursor: ModelPool, other: ModelPool) {
        let periodCursor = belonging(period, to: .cursorModels)
        let periodOther = belonging(period, to: .otherModels)
        let todayCursor = belonging(today, to: .cursorModels)
        let todayOther = belonging(today, to: .otherModels)
        return (
            ModelPool(
                percent: cursorPercent,
                periodTokens: sum(periodCursor),
                todayTokens: sum(todayCursor),
                models: periodCursor
            ),
            ModelPool(
                percent: otherPercent,
                periodTokens: sum(periodOther),
                todayTokens: sum(todayOther),
                models: periodOther
            )
        )
    }

    private static func belonging(_ models: [ModelUsage], to kind: ModelPoolKind) -> [ModelUsage] {
        models.filter { ModelPoolClassifier.kind(for: $0.name) == kind && $0.tokens > 0 }
    }

    private static func sum(_ models: [ModelUsage]) -> Int {
        models.reduce(0) { $0 + $1.tokens }
    }
}

public enum SandUsageParser {
    public static func parse(_ data: Data) throws -> GrokBotUsage {
        guard let root = CursorJSON.object(data) else {
            throw PeriodUsageParserError.unrecognized
        }
        let pooled = CursorJSON.bool(root, key: "usesPooledEnterpriseAllowance")
        let hasLimit = CursorJSON.bool(root, key: "hasNonZeroIncludedLimit")
        let percent = CursorJSON.firstDouble(root, keys: ["usagePercent"]).flatMap { value -> Int? in
            guard value.isFinite else { return nil }
            return Int(value.rounded())
        }
        if pooled == nil && hasLimit == nil && percent == nil {
            throw PeriodUsageParserError.unrecognized
        }
        if pooled == true || hasLimit == false {
            return GrokBotUsage(allowance: .notIncluded, percent: nil, resetAt: nil)
        }
        guard let percent else {
            throw PeriodUsageParserError.unrecognized
        }
        let reset = CursorJSON.firstTimestamp(root, keys: ["nextResetTimestampUtc"])
        return GrokBotUsage(allowance: .included, percent: percent, resetAt: reset)
    }
}
