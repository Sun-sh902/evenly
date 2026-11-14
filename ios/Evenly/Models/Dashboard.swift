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
    static let recentCount = 5

    static func build(groups: [GroupSnapshot], me: (GroupSnapshot) -> String?, now: Date = Date(),
                      calendar: Calendar = .current) -> Dashboard {
        var byCurrency: [String: Totals] = [:]
        var groupCount: [String: Int] = [:]
        var summaries: [GroupSummary] = []
        var activity: [Activity] = []
        var knowsYou = false

        // Entry dates are "YYYY-MM-DD", so the month is just the first seven characters.
        // Comparing those strings is far cheaper than parsing every date.
        let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
        var monthSlot: [Substring: Int] = [:]
        for back in 0..<monthsShown {
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { continue }
            let c = calendar.dateComponents([.year, .month], from: start)
            monthSlot[Substring(String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0))] = monthsShown - 1 - back
        }
        func monthIndex(_ day: String) -> Int? { monthSlot[day.prefix(7)] }
        let oldestMonth = monthSlot.min { $0.value < $1.value }?.key ?? ""

        for g in groups {
            var t = byCurrency[g.currency] ?? Totals(currency: g.currency, digits: g.digits, monthly: Array(repeating: 0, count: monthsShown))
            groupCount[g.currency, default: 0] += 1
            let mine = me(g)
            if let mine {
                knowsYou = true
                let net = g.net(of: mine)
                if net > 0 { t.owedToYou += net } else { t.youOwe -= net }
            }
            for e in g.entries {
                // Entries are newest first: once one is older than the oldest month shown, so are the rest.
                if e.date.prefix(7) < oldestMonth { break }
                guard !e.isTransfer, let i = monthIndex(e.date) else { continue }
                t.monthly[i] += e.amount
                if i == monthsShown - 1 { t.spentThisMonth += e.amount }
            }
            byCurrency[g.currency] = t
            summaries.append(GroupSummary(group: g, yourNet: mine.map { g.net(of: $0) }))
            // Snapshots list entries newest first, so only each group's first few can make the top five.
            activity += g.entries.prefix(recentCount).map { Activity(entry: $0, groupId: g.id, groupName: g.name, currency: g.currency, digits: g.digits) }
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
        return Dashboard(totals: totals, groups: summaries, recent: Array(recent.prefix(recentCount)), knowsYou: knowsYou)
    }
}
