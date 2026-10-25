import Foundation

/// 非有限值不进入快照。展示小数位由 PercentText 决定，这里保留原始数值。
private func finitePercent(_ value: Double) -> Double? {
    value.isFinite ? value : nil
}

public enum PeriodUsageParserError: Error, Equatable {
    case unrecognized
}

public enum ModelPoolKind: Equatable, Sendable {
    case cursorModels
    case otherModels
}

public enum PeriodPercentParser {
    /// 百分比和周期边界至少要有一类。只有额度上限、没有百分比也没有周期时拒绝。
    /// 套餐刚续费或已经到期时，响应可能只有 billingCycleEnd，百分比保持 nil。
    public static func parse(_ data: Data) throws -> PeriodPercents {
        guard let root = CursorJSON.object(data) else {
            throw PeriodUsageParserError.unrecognized
        }
        let usage = CursorJSON.dictionary(root, key: "planUsage") ?? root
        let cursor = CursorJSON.firstDouble(usage, keys: ["autoPercentUsed"]).flatMap(finitePercent)
        let other = CursorJSON.firstDouble(usage, keys: ["apiPercentUsed"]).flatMap(finitePercent)
        let start = CursorJSON.firstTimestamp(root, keys: ["billingCycleStart"])
            ?? CursorJSON.firstTimestamp(usage, keys: ["billingCycleStart"])
        let end = CursorJSON.firstTimestamp(root, keys: ["billingCycleEnd"])
            ?? CursorJSON.firstTimestamp(usage, keys: ["billingCycleEnd"])
        guard cursor != nil || other != nil || start != nil || end != nil else {
            throw PeriodUsageParserError.unrecognized
        }
        return PeriodPercents(cursorPercent: cursor, otherPercent: other, periodStart: start, periodEnd: end)
    }
}

public enum PlanInfoParser {
    /// GetPlanInfo 的周期结束时间在 planInfo.billingCycleEnd。没有结束时间就无法显示套餐期限。
    public static func periodEnd(_ data: Data) throws -> Date {
        guard let root = CursorJSON.object(data) else {
            throw PeriodUsageParserError.unrecognized
        }
        let info = CursorJSON.dictionary(root, key: "planInfo") ?? root
        guard let end = CursorJSON.firstTimestamp(info, keys: ["billingCycleEnd"])
            ?? CursorJSON.firstTimestamp(root, keys: ["billingCycleEnd"]) else {
            throw PeriodUsageParserError.unrecognized
        }
        return end
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
        cursorPercent: Double?,
        otherPercent: Double?
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
        let percent = CursorJSON.firstDouble(root, keys: ["usagePercent"]).flatMap(finitePercent)
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
