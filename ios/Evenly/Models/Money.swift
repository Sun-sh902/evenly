import Foundation

/// Money helpers matching the server rules in src/money.js.
enum Money {
    static let symbols: [String: String] = [
        "USD": "$", "EUR": "€", "GBP": "£", "CAD": "CA$", "AUD": "A$", "CHF": "CHF ",
        "CNY": "¥", "HKD": "HK$", "SGD": "S$", "INR": "₹", "MXN": "MX$", "BRL": "R$",
        "SEK": "kr ", "JPY": "¥", "KRW": "₩",
    ]

    static let currencyCodes = ["USD", "EUR", "GBP", "CAD", "AUD", "CHF", "CNY", "HKD", "SGD", "INR", "MXN", "BRL", "SEK", "JPY", "KRW"]

    static func digits(for currency: String) -> Int {
        ["JPY", "KRW"].contains(currency) ? 0 : 2
    }

    static func symbol(for currency: String) -> String {
        symbols[currency] ?? "\(currency) "
    }

    /// Parses "1,234.50" into minor units. Returns nil for anything that is not a
    /// non-negative amount with at most `digits` decimals and 12 whole digits.
    static func parse(_ text: String, digits: Int) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= (digits > 0 ? 2 : 1) else { return nil }
        let whole = parts[0]
        let frac = parts.count == 2 ? parts[1] : ""
        guard (1...12).contains(whole.count), whole.allSatisfy(\.isASCIIDigit) else { return nil }
        if parts.count == 2 {
            guard (1...digits).contains(frac.count), frac.allSatisfy(\.isASCIIDigit) else { return nil }
        }
        let padded = (String(frac) + String(repeating: "0", count: digits)).prefix(digits)
        guard let w = Int(whole), let f = digits > 0 ? Int(padded) : 0 else { return nil }
        return w * pow10(digits) + f
    }

    /// Plain decimal string the API accepts, e.g. 1250 -> "12.50".
    static func plain(_ minor: Int, digits: Int) -> String {
        guard digits > 0 else { return String(minor) }
        let sign = minor < 0 ? "-" : ""
        let base = pow10(digits)
        let abs = Swift.abs(minor)
        let frac = String(abs % base)
        return "\(sign)\(abs / base).\(String(repeating: "0", count: digits - frac.count))\(frac)"
    }

    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    /// Display string such as "€1,141.65", "-$3.00" or "+¥500".
    static func format(_ minor: Int, currency: String, digits: Int, signed: Bool = false) -> String {
        let abs = Swift.abs(minor)
        let base = pow10(digits)
        let whole = grouping.string(from: NSNumber(value: abs / base)) ?? String(abs / base)
        var body = symbol(for: currency) + whole
        if digits > 0 {
            let frac = String(abs % base)
            body += "." + String(repeating: "0", count: digits - frac.count) + frac
        }
        if minor < 0 { return "-" + body }
        if signed && minor > 0 { return "+" + body }
        return body
    }

    /// Largest remainder allocation: parts always sum exactly to `total`.
    static func allocate(_ total: Int, weights: [Double]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0, !weights.isEmpty else { return weights.map { _ in 0 } }
        let raw = weights.map { Double(total) * $0 / sum }
        var parts = raw.map { Int($0.rounded(.down)) }
        var left = total - parts.reduce(0, +)
        let order = raw.enumerated()
            .map { (index: $0.offset, frac: $0.element - $0.element.rounded(.down)) }
            .sorted { $0.frac != $1.frac ? $0.frac > $1.frac : $0.index < $1.index }
        var k = 0
        while left > 0 {
            parts[order[k % order.count].index] += 1
            left -= 1
            k += 1
        }
        k = order.count - 1
        while left < 0 {
            let i = order[(k % order.count + order.count) % order.count].index
            if parts[i] > 0 { parts[i] -= 1; left += 1 }
            k -= 1
        }
        return parts
    }

    static func pow10(_ n: Int) -> Int {
        var r = 1
        for _ in 0..<max(0, n) { r *= 10 }
        return r
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Day strings ("YYYY-MM-DD") in the device's own calendar day.
enum Day {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
    static var today: String { string(from: Date()) }

    static func label(_ iso: String, now: Date = Date()) -> String {
        if iso == string(from: now) { return t("Today") }
        if let y = Calendar.current.date(byAdding: .day, value: -1, to: now), iso == string(from: y) { return t("Yesterday") }
        guard let d = date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Localizer.shared.locale
        let sameYear = Calendar.current.component(.year, from: d) == Calendar.current.component(.year, from: now)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "EEE MMM d" : "EEE MMM d yyyy")
        return f.string(from: d)
    }
}
