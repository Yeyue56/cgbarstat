import Foundation

/// 百分比文案。绝对值四舍五入到百分位后达到 10，则保留 1 位小数；否则保留 2 位。末尾 0 保留。
public enum PercentText {
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        let hundredths = rounded(magnitude, places: 2)
        if hundredths >= 10 {
            return sign + render(rounded(magnitude, places: 1), places: 1) + "%"
        }
        return sign + render(hundredths, places: 2) + "%"
    }

    private static func rounded(_ value: Double, places: Int) -> Decimal {
        var input = Decimal(string: String(value)) ?? Decimal(value)
        var output = Decimal()
        NSDecimalRound(&output, &input, places, .plain)
        return output
    }

    private static func render(_ value: Decimal, places: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.roundingMode = .halfUp
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
}

/// 以 1000 进位格式化 Tokens。四舍五入到一位小数；结果达到 1000 时升到下一单位。
public enum TokenQuantity {
    public static func format(_ count: Int) -> String {
        let sign = count < 0 ? "-" : ""
        var value = Double(abs(count))
        let units = ["", "K", "M", "B"]
        var unitIndex = 0
        while unitIndex < units.count - 1 && value >= 1000 {
            value /= 1000
            unitIndex += 1
        }
        if unitIndex < units.count - 1 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 1000 {
                value = rounded / 1000
                unitIndex += 1
            } else {
                value = rounded
            }
        }
        let suffix = units[unitIndex]
        if suffix.isEmpty {
            return sign + String(abs(count))
        }
        if abs(value - value.rounded()) < 0.05 {
            return sign + String(Int(value.rounded())) + suffix
        }
        return sign + String(format: "%.1f", value) + suffix
    }
}

public struct StatusItemLabel: Equatable, Sendable {
    public var abbreviation: String
    public var percentText: String
    public var accessibilityText: String

    public init(abbreviation: String, percentText: String, accessibilityText: String) {
        self.abbreviation = abbreviation
        self.percentText = percentText
        self.accessibilityText = accessibilityText
    }
}

public enum MenuBarLabel {
    public static func placeholders() -> [StatusItemLabel] {
        [
            item(abbreviation: "CM", percent: nil, name: "Cursor Models"),
            item(abbreviation: "OM", percent: nil, name: "Other Models"),
            item(abbreviation: "GB", percent: nil, name: "Grok Bot"),
        ]
    }

    public static func cursorModels(_ snapshot: UsageSnapshot) -> StatusItemLabel {
        item(abbreviation: "CM", percent: snapshot.cursorModels.percent, name: "Cursor Models")
    }

    public static func otherModels(_ snapshot: UsageSnapshot) -> StatusItemLabel {
        item(abbreviation: "OM", percent: snapshot.otherModels.percent, name: "Other Models")
    }

    public static func grokBot(_ snapshot: UsageSnapshot) -> StatusItemLabel {
        item(abbreviation: "GB", percent: snapshot.grokBot.percent, name: "Grok Bot")
    }

    public static func item(abbreviation: String, percent: Double?, name: String) -> StatusItemLabel {
        guard let percent else {
            return StatusItemLabel(
                abbreviation: abbreviation,
                percentText: "—",
                accessibilityText: "\(name) 无数据"
            )
        }
        let text = PercentText.format(percent)
        return StatusItemLabel(
            abbreviation: abbreviation,
            percentText: text,
            accessibilityText: "\(name) \(text)"
        )
    }
}

public struct ModelRow: Equatable, Sendable {
    public var name: String
    public var fraction: Double
    public var percentText: String
    public var tokensText: String

    public init(name: String, fraction: Double, percentText: String, tokensText: String) {
        self.name = name
        self.fraction = fraction
        self.percentText = percentText
        self.tokensText = tokensText
    }
}

public struct PoolPanelModel: Equatable, Sendable {
    public var percentText: String
    public var periodTokensText: String
    public var todayShareText: String
    public var todayTokensText: String
    public var rows: [ModelRow]
    public var expiryText: String?
    public var staleText: String?

    public init(
        percentText: String,
        periodTokensText: String,
        todayShareText: String,
        todayTokensText: String,
        rows: [ModelRow],
        expiryText: String?,
        staleText: String?
    ) {
        self.percentText = percentText
        self.periodTokensText = periodTokensText
        self.todayShareText = todayShareText
        self.todayTokensText = todayTokensText
        self.rows = rows
        self.expiryText = expiryText
        self.staleText = staleText
    }
}

public enum PlanExpiry {
    /// 没有 billingCycleEnd 时不显示。已经到期时不用「0小时0分钟」，以免和仍在计时的套餐混淆。
    public static func text(now: Date, periodEnd: Date?) -> String? {
        guard let periodEnd else { return nil }
        if periodEnd.timeIntervalSince(now) <= 0 {
            return "套餐已过期"
        }
        return ResetCountdown.text(now: now, resetAt: periodEnd) + "后过期"
    }
}

public enum PoolPanelCopy {
    /// 模型行按本期 Tokens 从高到低。占比分母是本池本期 Tokens，不是额度上限。
    public static func make(pool: ModelPool, isStale: Bool, now: Date = Date(), periodEnd: Date? = nil) -> PoolPanelModel {
        let percentText = pool.percent.map(PercentText.format) ?? "—"
        let periodText = pool.periodTokens.map(TokenQuantity.format) ?? "—"
        let todayText = pool.todayTokens.map(TokenQuantity.format) ?? "—"
        let todayShare: String
        if let today = pool.todayTokens, let period = pool.periodTokens {
            if period > 0 {
                let percent = Double(today) / Double(period) * 100
                todayShare = "今日 \(PercentText.format(percent))"
            } else {
                todayShare = "今日 \(PercentText.format(0))"
            }
        } else {
            todayShare = "今日 —"
        }
        let rows = modelRows(models: pool.models, periodTokens: pool.periodTokens)
        return PoolPanelModel(
            percentText: percentText,
            periodTokensText: periodText,
            todayShareText: todayShare,
            todayTokensText: todayText,
            rows: rows,
            expiryText: PlanExpiry.text(now: now, periodEnd: periodEnd),
            staleText: isStale ? "数据已过期" : nil
        )
    }

    private static func modelRows(models: [ModelUsage], periodTokens: Int?) -> [ModelRow] {
        guard let periodTokens, periodTokens > 0 else { return [] }
        return models
            .filter { $0.tokens > 0 }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens { return lhs.name < rhs.name }
                return lhs.tokens > rhs.tokens
            }
            .map { model in
                let fraction = min(1, max(0, Double(model.tokens) / Double(periodTokens)))
                let percent = Double(model.tokens) / Double(periodTokens) * 100
                return ModelRow(
                    name: model.name,
                    fraction: fraction,
                    percentText: PercentText.format(percent),
                    tokensText: TokenQuantity.format(model.tokens)
                )
            }
    }
}

public enum ResetCountdown {
    /// 不足 1 天时向上取整为小时和分钟；达到 1 天时显示天和小时，天数可以为 1 以上，小时是余数。
    public static func text(now: Date, resetAt: Date?) -> String {
        guard let resetAt else { return "重置时间未知" }
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "0小时0分钟" }
        let minutesTotal = Int((remaining / 60).rounded(.up))
        if minutesTotal < 24 * 60 {
            return "\(minutesTotal / 60)小时\(minutesTotal % 60)分钟"
        }
        let hoursTotal = max(Int(remaining / 3600), minutesTotal / 60)
        return "\(hoursTotal / 24)天\(hoursTotal % 24)小时"
    }
}

public struct GrokPanelModel: Equatable, Sendable {
    public var percentText: String
    public var resetText: String?
    public var allowanceText: String?
    public var staleText: String?

    public init(percentText: String, resetText: String?, allowanceText: String?, staleText: String?) {
        self.percentText = percentText
        self.resetText = resetText
        self.allowanceText = allowanceText
        self.staleText = staleText
    }
}

public enum GrokPanelCopy {
    public static func make(usage: GrokBotUsage, now: Date, isStale: Bool) -> GrokPanelModel {
        if usage.allowance == .notIncluded {
            return GrokPanelModel(
                percentText: "—",
                resetText: nil,
                allowanceText: "当前账号没有单独的 Grok Bot 额度",
                staleText: isStale ? "数据已过期" : nil
            )
        }
        return GrokPanelModel(
            percentText: usage.percent.map(PercentText.format) ?? "—",
            resetText: resetLine(now: now, resetAt: usage.resetAt),
            allowanceText: nil,
            staleText: isStale ? "数据已过期" : nil
        )
    }

    /// 有重置时刻时在时间后加上「后重置」。没有时间戳时保持「重置时间未知」。
    private static func resetLine(now: Date, resetAt: Date?) -> String {
        let countdown = ResetCountdown.text(now: now, resetAt: resetAt)
        guard resetAt != nil else { return countdown }
        return countdown + "后重置"
    }
}
