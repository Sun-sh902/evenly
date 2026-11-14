import Foundation

/// Swift port of src/ledger.js. The rules and messages match the server exactly
/// so a group behaves the same whether it lives on this iPhone or on a server.
enum Ledger {
    static let splitModes = ["equal", "exact", "shares", "percent"]

    static func invalid(_ message: String, _ field: String? = nil) -> APIError {
        APIError(status: 400, message: message, field: field)
    }

    /// Turns split instructions into integer shares that always sum to `amount`.
    static func resolveSplit(amount: Int, split: SplitPayload, digits: Int) throws -> [Share] {
        guard splitModes.contains(split.mode) else {
            throw invalid("split.mode must be one of \(splitModes.joined(separator: ", "))", "split.mode")
        }
        let ps = split.participants
        guard !ps.isEmpty else { throw invalid("choose at least one person to split with", "split.participants") }
        var seen = Set<String>()
        for p in ps where !seen.insert(p.memberId).inserted {
            throw invalid("a person appears twice in the split", "split.participants")
        }

        switch split.mode {
        case "equal":
            let parts = Money.allocate(amount, weights: ps.map { _ in 1 })
            return zip(ps, parts).map { Share(memberId: $0.memberId, share: $1, weight: nil) }

        case "exact":
            let shares = try ps.map { p -> Int in
                if p.value == "0" { return 0 }
                guard let raw = p.value, let v = Money.parse(raw, digits: digits) else {
                    throw invalid("every exact amount must be a valid number", "split.participants")
                }
                return v
            }
            guard shares.reduce(0, +) == amount else { throw invalid("exact amounts must add up to the total", "split.participants") }
            return zip(ps, shares).map { Share(memberId: $0.memberId, share: $1, weight: nil) }

        default: // shares and percent are weight based
            let label = split.mode == "percent" ? "percentage" : "share"
            let weights = try ps.map { p -> Double in
                guard let w = jsNumber(p.value), w.isFinite, w >= 0, w <= 1e6 else {
                    throw invalid("every \(label) must be a non-negative number", "split.participants")
                }
                return w
            }
            let total = weights.reduce(0, +)
            if split.mode == "percent" && abs(total - 100) > 1e-6 {
                throw invalid("percentages must add up to 100", "split.participants")
            }
            guard total > 0 else { throw invalid("at least one share must be greater than zero", "split.participants") }
            let parts = Money.allocate(amount, weights: weights)
            return zip(ps, zip(parts, weights)).map { Share(memberId: $0.memberId, share: $1.0, weight: $1.1) }
        }
    }

    /// Mirrors JavaScript's Number(value) for the inputs the app sends.
    static func jsNumber(_ value: String?) -> Double? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return 0 }
        return Double(t)
    }

    /// Net balance per member: positive means the group owes them.
    static func balances(members: [Member], entries: [Entry]) -> [Balance] {
        var paid: [String: Int] = [:]
        var owed: [String: Int] = [:]
        for e in entries {
            paid[e.paidBy, default: 0] += e.amount
            for s in e.shares { owed[s.memberId, default: 0] += s.share }
        }
        return members.map { m in
            let p = paid[m.id] ?? 0, o = owed[m.id] ?? 0
            return Balance(memberId: m.id, paid: p, owed: o, net: p - o)
        }
    }

    /// Greedy settle-up identical to the server: largest debtor pays largest creditor.
    static func transfers(_ balances: [Balance]) -> [Transfer] {
        struct Side { let id: String; var amt: Int }
        var creditors = balances.filter { $0.net > 0 }.map { Side(id: $0.memberId, amt: $0.net) }
        var debtors = balances.filter { $0.net < 0 }.map { Side(id: $0.memberId, amt: -$0.net) }
        let order: (Side, Side) -> Bool = { $0.amt != $1.amt ? $0.amt > $1.amt : $0.id < $1.id }
        var out: [Transfer] = []
        while !creditors.isEmpty && !debtors.isEmpty {
            creditors.sort(by: order)
            debtors.sort(by: order)
            let amt = min(creditors[0].amt, debtors[0].amt)
            out.append(Transfer(from: debtors[0].id, to: creditors[0].id, amount: amt))
            creditors[0].amt -= amt
            debtors[0].amt -= amt
            if creditors[0].amt == 0 { creditors.removeFirst() }
            if debtors[0].amt == 0 { debtors.removeFirst() }
        }
        return out
    }
}
