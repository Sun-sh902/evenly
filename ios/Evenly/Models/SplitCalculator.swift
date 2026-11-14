import Foundation

enum SplitMode: String, CaseIterable, Identifiable {
    case equal, exact, shares, percent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .equal: "Equally"
        case .exact: "Exact"
        case .shares: "Shares"
        case .percent: "Percent"
        }
    }
    var summary: String {
        switch self {
        case .equal: "split equally"
        case .exact: "exact amounts"
        case .shares: "by shares"
        case .percent: "by percent"
        }
    }
}

/// Live preview of a split, using the same rules as the server so the numbers
/// the user sees are exactly the numbers that get saved.
struct SplitPreview: Equatable {
    enum Tone: Equatable { case neutral, good, bad }
    var shares: [String: Int]
    var isValid: Bool
    var message: String
    var tone: Tone
}

enum SplitCalculator {
    static func preview(
        amount: Int?,
        mode: SplitMode,
        memberIds: [String],
        included: Set<String>,
        values: [String: String],
        format: (Int) -> String,
        digits: Int
    ) -> SplitPreview {
        let total = amount ?? 0
        let ids = memberIds.filter { included.contains($0) }
        var shares = Dictionary(uniqueKeysWithValues: memberIds.map { ($0, 0) })
        guard !ids.isEmpty else {
            return SplitPreview(shares: shares, isValid: false, message: "Pick at least one person", tone: .bad)
        }

        switch mode {
        case .equal:
            for (i, v) in Money.allocate(total, weights: ids.map { _ in 1 }).enumerated() { shares[ids[i]] = v }
            let each = total / ids.count
            let msg = total > 0 ? "\(format(each))\(total % ids.count == 0 ? "" : "+") each" : ""
            return SplitPreview(shares: shares, isValid: total > 0, message: msg, tone: .neutral)

        case .exact:
            var sum = 0
            var parsedAll = true
            for id in ids {
                let raw = values[id] ?? ""
                let v = raw.isEmpty ? 0 : Money.parse(raw, digits: digits)
                if v == nil { parsedAll = false }
                shares[id] = v ?? 0
                sum += v ?? 0
            }
            let left = total - sum
            if !parsedAll { return SplitPreview(shares: shares, isValid: false, message: "Check the amounts", tone: .bad) }
            if left == 0 && total > 0 { return SplitPreview(shares: shares, isValid: true, message: "Adds up exactly", tone: .good) }
            let msg = left > 0 ? "\(format(left)) left to assign" : "\(format(-left)) over the total"
            return SplitPreview(shares: shares, isValid: false, message: msg, tone: .bad)

        case .shares, .percent:
            let fallback = mode == .shares ? "1" : "0"
            let weights = ids.map { max(0, Double(values[$0] ?? fallback) ?? 0) }
            let sum = weights.reduce(0, +)
            if sum > 0 {
                for (i, v) in Money.allocate(total, weights: weights).enumerated() { shares[ids[i]] = v }
            }
            if mode == .percent {
                let diff = ((100 - sum) * 100).rounded() / 100
                if diff == 0 { return SplitPreview(shares: shares, isValid: total > 0, message: "100% assigned", tone: .good) }
                let msg = diff > 0 ? "\(clean(diff))% left to assign" : "\(clean(-diff))% too much"
                return SplitPreview(shares: shares, isValid: false, message: msg, tone: .bad)
            }
            if sum <= 0 { return SplitPreview(shares: shares, isValid: false, message: "Give someone a share", tone: .bad) }
            return SplitPreview(shares: shares, isValid: total > 0, message: "\(clean(sum)) share\(sum == 1 ? "" : "s") in total", tone: .neutral)
        }
    }

    /// Default values when switching into a mode, so every mode starts valid.
    static func seed(mode: SplitMode, ids: [String], amount: Int?, digits: Int) -> [String: String] {
        switch mode {
        case .equal:
            return [:]
        case .shares:
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, "1") })
        case .percent:
            guard !ids.isEmpty else { return [:] }
            let base = (100.0 / Double(ids.count) * 100).rounded(.down) / 100
            var out: [String: String] = [:]
            for (i, id) in ids.enumerated() {
                let v = i == ids.count - 1 ? ((100 - base * Double(ids.count - 1)) * 100).rounded() / 100 : base
                out[id] = clean(v)
            }
            return out
        case .exact:
            guard let amount, amount > 0, !ids.isEmpty else { return [:] }
            let parts = Money.allocate(amount, weights: ids.map { _ in 1 })
            return Dictionary(uniqueKeysWithValues: zip(ids, parts.map { Money.plain($0, digits: digits) }))
        }
    }

    static func clean(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}

/// Extracts a group id from a pasted invite link or a bare id.
enum InviteLink {
    struct Parsed: Equatable {
        let groupId: String
        let server: URL?
    }

    static func parse(_ text: String) -> Parsed? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if isId(s) { return Parsed(groupId: s, server: nil) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "evenly" {
            // evenly://g/<id>  or  evenly://g/<id>?server=https://host
            let comps = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
            guard comps.count == 2, comps[0] == "g", isId(comps[1]) else { return nil }
            let server = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "server" }?.value.flatMap(URL.init(string:))
            return Parsed(groupId: comps[1], server: server)
        }
        guard scheme == "http" || scheme == "https", let host = url.host else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 2, path[0] == "g", isId(path[1]) else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = url.port
        return Parsed(groupId: path[1], server: origin.url)
    }

    static func isId(_ s: String) -> Bool {
        (6...40).contains(s.count) && s.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "_" || $0 == "-" }
    }
}
