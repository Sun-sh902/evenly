import SwiftUI
import XCTest
@testable import Evenly

/// Timings for the work that grows with a group's history. Each test prints a
/// per-call figure so before/after numbers can be compared on the same machine.
@MainActor
final class PerformanceTests: XCTestCase {
    override func setUp() { Localizer.shared.choice = .english }
    override func tearDown() { Localizer.shared.choice = .system }

    /// A group with `count` entries spread over the past `days` days, five people each.
    static func bigGroup(_ count: Int, days: Int = 365, id: String = "g") -> GroupSnapshot {
        let members = (0..<5).map { Member(id: "m\($0)", name: "Person \($0)") }
        let today = Date()
        let entries: [Entry] = (0..<count).map { i in
            let day = Day.string(from: Calendar.current.date(byAdding: .day, value: -(i % days), to: today)!)
            let shares = members.map { Share(memberId: $0.id, share: 200, weight: nil) }
            return Entry(id: "e\(i)", kind: i % 10 == 0 ? "transfer" : "expense", title: "Dinner \(i)", note: i % 3 == 0 ? "with friends" : "",
                         category: ["food", "transport", "stay"][i % 3], amount: 1000, paidBy: members[i % 5].id, splitMode: "equal",
                         date: day, createdAt: "2026-01-01T00:00:00.\(String(format: "%03d", i % 1000))Z", updatedAt: "", shares: i % 10 == 0 ? [shares[1]] : shares)
        }
        let stored = LocalBackend.StoredGroup(id: id, name: "Big", currency: "USD", createdAt: "", updatedAt: "", revision: 1,
                                              members: members, entries: entries)
        return LocalBackend.snapshot(stored)
    }

    /// Views only render for real inside a visible window.
    static func window(_ host: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let w = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        w.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        w.rootViewController = host
        w.isHidden = false
        return w
    }

    private func time(_ label: String, repeats: Int = 1, _ body: () -> Void) -> Double {
        body() // warm up
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<repeats { body() }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(repeats)
        print("PERF \(label): \(String(format: "%.3f", ms)) ms")
        return ms
    }

    func testSnapshotOf2000Entries() {
        let g = Self.bigGroup(2000)
        let stored = LocalBackend.StoredGroup(id: g.id, name: g.name, currency: g.currency, createdAt: "", updatedAt: "", revision: 1,
                                              members: g.members, entries: g.entries)
        _ = time("snapshot 2000 entries", repeats: 10) { _ = LocalBackend.snapshot(stored) }
    }

    func testDayLabels() {
        let days = (0..<365).map { Day.string(from: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!) }
        _ = time("Day.label x365", repeats: 5) { for d in days { _ = Day.label(d) } }
    }

    func testDashboardFor20GroupsOf500() {
        let groups = (0..<20).map { Self.bigGroup(500, id: "g\($0)") }
        _ = time("Dashboard.build 20x500", repeats: 10) { _ = Dashboard.build(groups: groups, me: { _ in "m0" }) }
    }

    func testActivityListFirstLayout() {
        let g = Self.bigGroup(2000)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        let window = Self.window(host)
        defer { window.isHidden = true }
        _ = time("ActivitySection 2000 entries, first layout", repeats: 3) {
            host.rootView = AnyView(ScrollView {
                LazyVStack {
                    ActivitySection(group: g, me: "m0", query: .constant(""), filter: .constant(.all), onOpen: { _ in }, onAdd: {})
                }
            })
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            host.rootView = AnyView(EmptyView())
            host.view.layoutIfNeeded()
        }
    }

    func testActivitySearchKeystroke() {
        let g = Self.bigGroup(2000)
        var query = "din"
        let binding = Binding(get: { query }, set: { query = $0 })
        let host = UIHostingController(rootView: AnyView(ScrollView {
            LazyVStack { ActivitySection(group: g, me: "m0", query: binding, filter: .constant(.all), onOpen: { _ in }, onAdd: {}) }
        }))
        let window = Self.window(host)
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        var n = 0
        _ = time("ActivitySection search keystroke", repeats: 5) {
            n += 1
            query = n % 2 == 0 ? "dinner 1" : "dinner"
            host.rootView = AnyView(ScrollView {
                LazyVStack { ActivitySection(group: g, me: "m0", query: binding, filter: .constant(.all), onOpen: { _ in }, onAdd: {}) }
            })
            host.view.layoutIfNeeded()
        }
    }
}

@MainActor
final class DashboardCacheTests: XCTestCase {
    func testUnchangedGroupsAreRecognised() {
        let a = PerformanceTests.bigGroup(3, id: "a")
        let b = PerformanceTests.bigGroup(3, id: "b")
        XCTAssertTrue(AppState.sameVersions([a, b], [a, b]))
        XCTAssertFalse(AppState.sameVersions([a, b], [b, a]), "order matters")
        XCTAssertFalse(AppState.sameVersions([a], [a, b]))
    }

    func testDashboardStillCountsMonthsAfterEarlyExit() {
        let g = PerformanceTests.bigGroup(400, days: 400)
        let d = Dashboard.build(groups: [g], me: { _ in "m0" })
        // Every 10th entry is a payment; the rest are 10.00 expenses spread one per day.
        let expected = g.entries.filter { !$0.isTransfer && $0.date.prefix(7) == Day.today.prefix(7) }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(d.primary?.spentThisMonth, expected)
        XCTAssertEqual(d.primary?.monthly.count, Dashboard.monthsShown)
        XCTAssertEqual(d.recent.count, Dashboard.recentCount)
        XCTAssertEqual(d.recent.first?.entry.id, g.entries.first?.id)
    }
}
