import Foundation

enum CursorJSON {
    static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func dictionary(_ object: [String: Any], key: String) -> [String: Any]? {
        object[key] as? [String: Any]
    }

    static func array(_ object: [String: Any], key: String) -> [[String: Any]]? {
        object[key] as? [[String: Any]]
    }

    static func bool(_ object: [String: Any], key: String) -> Bool? {
        object[key] as? Bool
    }

    static func firstDouble(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key], let double = asDouble(value) {
                return double
            }
        }
        return nil
    }

    static func firstInt(_ object: [String: Any], keys: [String]) -> Int? {
        guard let double = firstDouble(object, keys: keys) else { return nil }
        return Int(double.rounded())
    }

    static func timestamp(_ value: Any) -> Date? {
        if let string = value as? String {
            if let date = parseISO(string) { return date }
            if let double = Double(string) { return timestamp(from: double) }
            return nil
        }
        guard let double = asDouble(value) else { return nil }
        return timestamp(from: double)
    }

    static func firstTimestamp(_ object: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = object[key], let date = timestamp(value) {
                return date
            }
        }
        return nil
    }

    private static func timestamp(from value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        if value >= 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }

    /// JSON 数字 0 和 1 不能当成布尔值丢掉，只有 JSON 布尔值才返回 nil。
    private static func asDouble(_ value: Any) -> Double? {
        if value is NSNull { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let string = value as? String, let double = Double(string), double.isFinite {
            return double
        }
        return nil
    }

    private static func parseISO(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
