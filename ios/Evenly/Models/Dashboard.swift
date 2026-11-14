import Foundation

/// Everything the home screen shows, derived from the groups and from which
/// member "you" are in each. Pure, so it is unit tested without any UI.
struct Dashboard: Equatable {
    /// Totals for one currency. Amounts in different currencies are never added together.
    struct Totals: Equatable {
        var currency: String
        var digits: Int
        var owedToYou = 0
        var youOwe = 0
        var spentThisMonth = 0
        /// Spending per month, oldest first, ending with the current month.
        var monthly: [Int] = []
        var net: Int { owedToYou - youOwe }
    }

    struct Activity: Equatable, Identifiable {
        let entry: Entry
        let groupId: String
        let groupName: String
        let currency: String
        let digits: Int
        var id: String { "\(groupId)/\(entry.id)" }
    }

    struct GroupSummary: Equatable, Identifiable {
        let group: GroupSnapshot
        /// Your net in this group, or nil when you haven't said which member you are.
        let yourNet: Int?
        var id: String { group.id }
    }

    /// Main currency first (most groups, then most spending), others after.
    var totals: [Totals]
    var groups: [GroupSummary]
    var recent: [Activity]
    /// True when at least one group knows which member you are.
    var knowsYou: Bool

    var primary: Totals? { totals.first }

    static let monthsShown = 6

    static func build(groups: [GroupSnapshot], me: (GroupSnapshot) -> String?, now: Date = Date(),
                      calendar: Calendar = .current) -> Dashboard {
        var byCurrency: [String: Totals] = [:]
        var groupCount: [String: Int] = [:]
        var summaries: [GroupSummary] = []
        var activity: [Activity] = []
        var knowsYou = false

        let monthStarts: [Date] = (0..<monthsShown).reversed().compactMap { back in
            calendar.date(byAdding: .month, value: -back, to: calendar.dateInterval(of: .month, for: now)!.start)
        }
        func monthIndex(_ day: String) -> Int? {
            guard let d = Day.date(from: day) else { return nil }
            for (i, start) in monthStarts.enumerated().reversed() where d >= start {
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                return d < end ? i : nil
            }
            return nil
        }

        for g in groups {
            var t = byCurrency[g.currency] ?? Totals(currency: g.currency, digits: g.digits, monthly: Array(repeating: 0, count: monthsShown))
            groupCount[g.currency, default: 0] += 1
            let mine = me(g)
            if let mine {
                knowsYou = true
                let net = g.net(of: mine)
                if net > 0 { t.owedToYou += net } else { t.youOwe -= net }
            }
            for e in g.entries where !e.isTransfer {
                if let i = monthIndex(e.date) {
                    t.monthly[i] += e.amount
                    if i == monthsShown - 1 { t.spentThisMonth += e.amount }
                }
            }
            byCurrency[g.currency] = t
            summaries.append(GroupSummary(group: g, yourNet: mine.map { g.net(of: $0) }))
            activity += g.entries.map { Activity(entry: $0, groupId: g.id, groupName: g.name, currency: g.currency, digits: g.digits) }
        }

        let totals = byCurrency.values.sorted {
            let (a, b) = (groupCount[$0.currency] ?? 0, groupCount[$1.currency] ?? 0)
            if a != b { return a > b }
            let (sa, sb) = ($0.monthly.reduce(0, +), $1.monthly.reduce(0, +))
            return sa != sb ? sa > sb : $0.currency < $1.currency
        }
        let recent = activity.sorted {
            $0.entry.date != $1.entry.date ? $0.entry.date > $1.entry.date : $0.entry.createdAt > $1.entry.createdAt
        }
        return Dashboard(totals: totals, groups: summaries, recent: Array(recent.prefix(5)), knowsYou: knowsYou)
    }
}
