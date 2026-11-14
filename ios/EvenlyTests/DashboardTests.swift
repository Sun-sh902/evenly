import XCTest
@testable import Evenly

final class DashboardTests: XCTestCase {
    private let now = Day.date(from: "2026-11-13")!

    private func group(_ id: String, currency: String = "CNY", members: [String], balances: [Int],
                       entries: [(date: String, amount: Int, transfer: Bool)] = []) -> GroupSnapshot {
        let ms = members.enumerated().map { Member(id: "\(id)-m\($0.offset)", name: $0.element) }
        let es = entries.enumerated().map { i, e in
            Entry(id: "\(id)-e\(i)", kind: e.transfer ? "transfer" : "expense", title: "x\(i)", note: "", category: "food",
                  amount: e.amount, paidBy: ms[0].id, splitMode: "equal", date: e.date, createdAt: "2026-11-13T00:00:0\(i)Z",
                  updatedAt: "", shares: [])
        }
        let bs = zip(ms, balances).map { Balance(memberId: $0.id, paid: 0, owed: 0, net: $1) }
        return GroupSnapshot(id: id, name: id.capitalized, currency: currency, digits: Money.digits(for: currency),
                             createdAt: "", updatedAt: "", revision: 1, members: ms, entries: es, balances: bs, transfers: [],
                             stats: Stats(totalSpent: es.filter { !$0.isTransfer }.reduce(0) { $0 + $1.amount },
                                          expenseCount: es.count, byCategory: [:], settled: balances.allSatisfy { $0 == 0 }))
    }

    func testBalancesAddUpAcrossGroupsInTheSameCurrency() {
        let a = group("trip", members: ["Me", "Lin"], balances: [60000, -60000])
        let b = group("flat", members: ["Me", "Wei"], balances: [-15000, 15000])
        let d = Dashboard.build(groups: [a, b], me: { $0.members[0].id }, now: now)
        XCTAssertTrue(d.knowsYou)
        XCTAssertEqual(d.primary?.owedToYou, 60000)
        XCTAssertEqual(d.primary?.youOwe, 15000)
        XCTAssertEqual(d.primary?.net, 45000)
        XCTAssertEqual(d.groups.map(\.yourNet), [60000, -15000])
    }

    func testCurrenciesAreNeverMixed() {
        let cny1 = group("a", currency: "CNY", members: ["Me", "X"], balances: [100, -100])
        let cny2 = group("b", currency: "CNY", members: ["Me", "X"], balances: [200, -200])
        let jpy = group("c", currency: "JPY", members: ["Me", "X"], balances: [-5000, 5000])
        let d = Dashboard.build(groups: [jpy, cny1, cny2], me: { $0.members[0].id }, now: now)
        XCTAssertEqual(d.totals.map(\.currency), ["CNY", "JPY"], "the currency used by most groups comes first")
        XCTAssertEqual(d.totals[0].owedToYou, 300)
        XCTAssertEqual(d.totals[1].youOwe, 5000)
        XCTAssertEqual(d.totals[1].digits, 0)
    }

    func testUnknownIdentityShowsNoBalance() {
        let a = group("trip", members: ["Me", "Lin"], balances: [600, -600])
        let d = Dashboard.build(groups: [a], me: { _ in nil }, now: now)
        XCTAssertFalse(d.knowsYou)
        XCTAssertEqual(d.primary?.owedToYou, 0)
        XCTAssertNil(d.groups[0].yourNet)
    }

    func testMonthlySpendingIgnoresPaymentsAndOldMonths() {
        let a = group("trip", members: ["Me"], balances: [0], entries: [
            ("2026-11-02", 1000, false), ("2026-11-10", 500, false),
            ("2026-11-11", 9999, true),            // a payment, not spending
            ("2026-10-31", 300, false),            // last month
            ("2026-06-15", 700, false),            // 5 months ago, still shown
            ("2026-05-31", 800, false),            // 6 months ago, outside the window
        ])
        let d = Dashboard.build(groups: [a], me: { _ in nil }, now: now)
        XCTAssertEqual(d.primary?.spentThisMonth, 1500)
        XCTAssertEqual(d.primary?.monthly, [700, 0, 0, 0, 300, 1500])
    }

    func testRecentActivityIsNewestFirstAcrossGroupsAndCapped() {
        let a = group("a", members: ["Me"], balances: [0], entries: [("2026-11-01", 1, false), ("2026-11-05", 2, false), ("2026-11-09", 3, false)])
        let b = group("b", members: ["Me"], balances: [0], entries: [("2026-11-03", 4, false), ("2026-11-12", 5, false), ("2026-11-07", 6, true)])
        let d = Dashboard.build(groups: [a, b], me: { _ in nil }, now: now)
        XCTAssertEqual(d.recent.map(\.entry.amount), [5, 3, 6, 2, 4])
        XCTAssertEqual(d.recent.first?.groupName, "B")
    }

    func testWalletStackPeeksAndOpens() {
        typealias L = WalletLayout
        let closed = L.frames(count: 3, open: nil)
        XCTAssertEqual(closed.frames.map(\.y), [0, L.peek, 2 * L.peek])
        XCTAssertEqual(closed.total, 2 * L.peek + L.collapsedHeight, "the last card shows in full")

        let open = L.frames(count: 3, open: 0)
        XCTAssertEqual(open.frames[0].height, L.openHeight)
        XCTAssertEqual(open.frames[1].y, L.openHeight + L.gap, "the next card clears the open one")
        XCTAssertEqual(open.frames[2].y, L.openHeight + L.gap + L.peek, "cards after it keep their peek")

        let last = L.frames(count: 2, open: 1)
        XCTAssertEqual(last.total, L.peek + L.openHeight)
        XCTAssertEqual(L.frames(count: 0, open: nil).total, 0)
    }

    func testNeighbouringCardsAreOneToneApart() {
        let steps = (0..<20).map(WalletTone.step)
        XCTAssertEqual(Array(steps.prefix(8)), [0, 1, 2, 3, 2, 1, 0, 1])
        for (a, b) in zip(steps, steps.dropFirst()) { XCTAssertEqual(abs(a - b), 1) }
    }

    func testCardsBehindTheOpenOneRecede() {
        XCTAssertEqual(WalletLayout.recede(index: 0, open: nil), 0)
        XCTAssertEqual(WalletLayout.recede(index: 2, open: 2), 0, "the open card stays in focus")
        XCTAssertGreaterThan(WalletLayout.recede(index: 0, open: 2), WalletLayout.recede(index: 1, open: 2), "deeper cards recede more")
        XCTAssertLessThanOrEqual(WalletLayout.recede(index: 0, open: 9), 1)
        XCTAssertLessThan(WalletLayout.recede(index: 3, open: 2), WalletLayout.recede(index: 1, open: 2))
    }

    func testRollingNumberKeepsDigitsAnchoredFromTheRight() {
        let small = RollingNumber.cells("+¥999.50")
        let big = RollingNumber.cells("+¥1,000.50")
        XCTAssertEqual(small.last?.id, 0)
        XCTAssertEqual(big.last?.id, 0)
        // The cents and ones digits keep the same wheel when the number grows.
        XCTAssertEqual(small.first { $0.id == 3 }?.char, "9")
        XCTAssertEqual(big.first { $0.id == 3 }?.char, "0")
        XCTAssertEqual(small.compactMap(\.digit), [9, 9, 9, 5, 0])
        XCTAssertNil(RollingNumber.Cell(id: 0, char: "¥").digit)
    }

    func testLongAmountsShrinkButNeverVanish() {
        XCTAssertEqual(RollingNumber.fittedSize(for: "+¥3,114.47"), 56)
        XCTAssertLessThan(RollingNumber.fittedSize(for: "+¥1,234,567.89"), 56)
        XCTAssertEqual(RollingNumber.fittedSize(for: String(repeating: "9", count: 60)), 32)
    }

    func testRevealHappensOncePerDay() {
        let d = makeTestDefaults(self, prefix: "evenly-reveal")
        let day = Day.date(from: "2026-11-13")!
        XCTAssertTrue(DailyReveal.claim(d, now: day))
        XCTAssertFalse(DailyReveal.claim(d, now: day.addingTimeInterval(3600)))
        XCTAssertTrue(DailyReveal.claim(d, now: day.addingTimeInterval(86_400)))
    }

    @MainActor
    func testAppearanceChoiceIsRememberedAndRevealCoversTheScreen() {
        let d = makeTestDefaults(self, prefix: "evenly-appearance")
        XCTAssertEqual(AppearanceController(defaults: d).choice, .system)
        d.set("dark", forKey: AppearanceController.key)
        XCTAssertEqual(AppearanceController(defaults: d).choice, .dark)
        XCTAssertEqual(AppAppearance.dark.style, .dark)
        XCTAssertEqual(AppAppearance.system.style, .unspecified)

        let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
        XCTAssertEqual(AppearanceController.coveringRadius(from: .zero, in: rect), 500, accuracy: 0.001)
        XCTAssertEqual(AppearanceController.coveringRadius(from: CGPoint(x: 150, y: 200), in: rect), 250, accuracy: 0.001)
    }

    func testUnsettledGroupsWithoutYouAreReportedNotSilentlyDropped() {
        let known = group("a", members: ["Me", "Ana"], balances: [500, -500], entries: [])
        let unknownOwing = group("b", members: ["Me", "Ben"], balances: [-226, 226], entries: [])
        let unknownSettled = group("c", members: ["X", "Y"], balances: [0, 0], entries: [])
        let d = Dashboard.build(groups: [known, unknownOwing, unknownSettled],
                                me: { $0.id == "a" ? $0.members[0].id : nil }, now: now)
        XCTAssertEqual(d.primary?.net, 500, "only the group that knows you is in the totals")
        XCTAssertEqual(d.uncountedGroups, 1, "the unsettled group without you is reported")
        XCTAssertNil(d.groups[2].yourNet)
        XCTAssertTrue(d.groups[2].group.stats.settled, "a group settled for everyone can still say so")
    }

    func testOnlyALeadingSignIsPulledLeft() {
        XCTAssertEqual(RollingNumber.opticalInset(for: "+¥3,114.47", size: 100), 5.4, accuracy: 0.001)
        XCTAssertEqual(RollingNumber.opticalInset(for: "-$12.00", size: 100), 5.4, accuracy: 0.001)
        XCTAssertEqual(RollingNumber.opticalInset(for: "¥0.00", size: 100), 0)
        XCTAssertEqual(RollingNumber.opticalInset(for: "", size: 100), 0)
    }
}
