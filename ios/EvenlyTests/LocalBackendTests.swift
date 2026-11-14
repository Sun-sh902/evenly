import XCTest
@testable import Evenly

/// The on-device store must behave exactly like the server: same rounding,
/// same balances, same settle-up suggestions, same validation errors.
final class LocalBackendTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("evenly-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeBackend() -> LocalBackend {
        LocalBackend(fileURL: dir.appendingPathComponent("groups.json"))
    }

    private func everyone(_ g: GroupSnapshot) -> SplitPayload {
        SplitPayload(mode: "equal", participants: g.members.map { SplitParticipant(memberId: $0.id, value: nil) })
    }

    private func expense(_ title: String, _ amount: String, by payer: String, split: SplitPayload,
                         category: String = "general", date: String = "2026-11-10") -> ExpensePayload {
        ExpensePayload(title: title, amount: amount, paidBy: payer, category: category, date: date, note: "", split: split)
    }

    func testFullTripSettlesToZero() async throws {
        let b = makeBackend()
        var g = try await b.createGroup(name: "  Lisbon   trip ", currency: "EUR", members: ["Ana", "Ben", "Cleo"])
        XCTAssertEqual(g.name, "Lisbon trip")
        XCTAssertEqual(g.revision, 1)
        let (a, bn, c) = (g.members[0].id, g.members[1].id, g.members[2].id)

        g = try await b.addExpense(g.id, expense("Dinner", "100", by: a, split: everyone(g), category: "food")).group
        XCTAssertEqual(g.entries[0].shares.map(\.share), [3334, 3333, 3333])

        g = try await b.addExpense(g.id, expense("Taxi", "30.50", by: bn, split: SplitPayload(mode: "exact", participants: [
            SplitParticipant(memberId: bn, value: "10.50"), SplitParticipant(memberId: c, value: "20"),
        ]))).group
        g = try await b.addExpense(g.id, expense("Flat", "450", by: c, split: SplitPayload(mode: "shares", participants: [
            SplitParticipant(memberId: a, value: "1"), SplitParticipant(memberId: bn, value: "1"), SplitParticipant(memberId: c, value: "1"),
        ]), category: "stay", date: "2026-11-09")).group
        g = try await b.addExpense(g.id, expense("Museum", "40", by: a, split: SplitPayload(mode: "percent", participants: [
            SplitParticipant(memberId: a, value: "25"), SplitParticipant(memberId: bn, value: "75"),
        ]), category: "fun", date: "2026-11-11")).group

        XCTAssertEqual(g.stats.totalSpent, 62050)
        XCTAssertEqual(g.stats.expenseCount, 4)
        XCTAssertEqual(g.stats.byCategory["stay"], 45000)
        XCTAssertEqual(g.balances.reduce(0) { $0 + $1.net }, 0)
        XCTAssertEqual(g.net(of: a), 14000 - 19334)
        XCTAssertEqual(g.entries.map(\.date), ["2026-11-11", "2026-11-10", "2026-11-10", "2026-11-09"])
        XCTAssertEqual(g.revision, 5)

        for t in g.transfers {
            g = try await b.addTransfer(g.id, TransferPayload(amount: Money.plain(t.amount, digits: 2), paidBy: t.from, to: t.to,
                                                              date: "2026-11-12", title: "")).group
        }
        XCTAssertTrue(g.stats.settled)
        XCTAssertTrue(g.transfers.isEmpty)
        XCTAssertEqual(g.entries.first?.title, "Settlement")
        XCTAssertEqual(g.stats.totalSpent, 62050, "payments are not spending")
    }

    func testEditDeleteAndConditionalReads() async throws {
        let b = makeBackend()
        var g = try await b.createGroup(name: "Flat", currency: "USD", members: ["Dee", "Eli"])
        let (dee, eli) = (g.members[0].id, g.members[1].id)
        let added = try await b.addExpense(g.id, expense("Rent", "2000", by: dee, split: everyone(g)))
        XCTAssertEqual(added.group.net(of: eli), -100000)

        g = try await b.updateExpense(g.id, entryId: added.entryId, expense("Rent (Nov)", "1800", by: eli, split: everyone(g), category: "utilities"))
        XCTAssertEqual(g.entries[0].title, "Rent (Nov)")
        XCTAssertEqual(g.entries[0].id, added.entryId)
        XCTAssertEqual(g.net(of: dee), -90000)

        let unchanged = try await b.group(g.id, knownRevision: g.revision)
        XCTAssertNil(unchanged, "same revision reads as not modified")

        g = try await b.deleteEntry(g.id, entryId: added.entryId)
        XCTAssertTrue(g.entries.isEmpty)
        await assertStatus(404) { _ = try await b.deleteEntry(g.id, entryId: added.entryId) }
    }

    func testMembersRules() async throws {
        let b = makeBackend()
        var g = try await b.createGroup(name: "Club", currency: "USD", members: ["Fay"])
        let fay = g.members[0].id
        let gus = try await b.addMember(g.id, name: "Gus").memberId
        await assertStatus(409) { _ = try await b.addMember(g.id, name: "gus") }
        await assertStatus(400) { _ = try await b.addMember(g.id, name: "   ") }
        await assertStatus(400) { _ = try await b.addMember(g.id, name: String(repeating: "x", count: 33)) }

        g = try await b.renameMember(g.id, memberId: gus, name: "Gustav")
        XCTAssertTrue(g.members.contains { $0.name == "Gustav" })
        await assertStatus(409) { _ = try await b.renameMember(g.id, memberId: gus, name: "Fay") }

        _ = try await b.addExpense(g.id, expense("Snacks", "9", by: fay, split: everyone(g)))
        await assertStatus(409) { _ = try await b.removeMember(g.id, memberId: gus) }

        let hal = try await b.addMember(g.id, name: "Hal").memberId
        g = try await b.removeMember(g.id, memberId: hal)
        XCTAssertEqual(g.members.count, 2)
        // Emoji names survive cleaning intact.
        g = try await b.addMember(g.id, name: "Mia 👩‍👩‍👧").group
        XCTAssertEqual(g.members.last?.name, "Mia 👩‍👩‍👧")
    }

    func testValidationMatchesServerFields() async throws {
        let b = makeBackend()
        let g = try await b.createGroup(name: "V", currency: "JPY", members: ["Jo", "Ki"])
        let (jo, ki) = (g.members[0].id, g.members[1].id)
        let split = everyone(g)
        let cases: [(ExpensePayload, String)] = [
            (expense("Ramen", "15.5", by: jo, split: split), "amount"),
            (expense("Ramen", "0", by: jo, split: split), "amount"),
            (expense("Ramen", "-5", by: jo, split: split), "amount"),
            (expense("", "1500", by: jo, split: split), "title"),
            (expense("Ramen", "1500", by: "ghost", split: split), "paidBy"),
            (expense("Ramen", "1500", by: jo, split: split, category: "yachts"), "category"),
            (expense("Ramen", "1500", by: jo, split: split, date: "2026-02-30"), "date"),
            (expense("Ramen", "1500", by: jo, split: split, date: "yesterday"), "date"),
            (expense("Ramen", "1500", by: jo, split: SplitPayload(mode: "equal", participants: [])), "split.participants"),
            (expense("Ramen", "1500", by: jo, split: SplitPayload(mode: "exact", participants: [SplitParticipant(memberId: jo, value: "1000")])), "split.participants"),
            (expense("Ramen", "1500", by: jo, split: SplitPayload(mode: "magic", participants: [SplitParticipant(memberId: jo, value: nil)])), "split.mode"),
        ]
        for (payload, field) in cases {
            do {
                _ = try await b.addExpense(g.id, payload)
                XCTFail("expected \(field) error")
            } catch let e as APIError {
                XCTAssertEqual(e.status, 400)
                XCTAssertEqual(e.field, field, "\(payload.title) \(payload.amount) \(payload.date)")
            }
        }
        do {
            _ = try await b.addTransfer(g.id, TransferPayload(amount: "100", paidBy: jo, to: jo, date: "", title: ""))
            XCTFail("expected to error")
        } catch let e as APIError { XCTAssertEqual(e.field, "to") }

        let ok = try await b.addExpense(g.id, expense("Ramen", "1500", by: ki, split: split))
        XCTAssertEqual(ok.group.entries[0].shares.map(\.share), [750, 750])
        await assertStatus(409) { _ = try await b.updateGroup(g.id, name: nil, currency: "USD") }
        let renamed = try await b.updateGroup(g.id, name: "Tokyo", currency: "KRW")
        XCTAssertEqual(renamed.currency, "KRW")
    }

    func testDataSurvivesRestartAndDelete() async throws {
        let first = makeBackend()
        let g = try await first.createGroup(name: "Keep", currency: "USD", members: ["A", "B"])
        _ = try await first.addExpense(g.id, expense("T", "12", by: g.members[0].id, split: everyone(g)))

        let second = makeBackend() // a fresh instance reads the same file, like an app relaunch
        let again = try await second.group(g.id, knownRevision: nil)
        XCTAssertEqual(again?.entries.count, 1)
        XCTAssertEqual(again?.balances.first?.net, 600)
        let listed = try await second.listGroups()
        XCTAssertEqual(listed.map(\.id), [g.id])

        try await second.deleteGroup(g.id)
        let third = makeBackend()
        let afterDelete = try await third.listGroups()
        XCTAssertTrue(afterDelete.isEmpty)
        await assertStatus(404) { _ = try await third.group(g.id, knownRevision: nil) }
    }

    func testSameDayEntriesKeepNewestFirstOrder() async throws {
        let b = makeBackend()
        let g = try await b.createGroup(name: "Order", currency: "USD", members: ["A"])
        let titles = ["first", "second", "third", "fourth", "fifth"]
        for title in titles {
            _ = try await b.addExpense(g.id, expense(title, "1", by: g.members[0].id, split: everyone(g), date: "2026-01-01"))
        }
        let got = try await b.group(g.id, knownRevision: nil)?.entries.map(\.title)
        XCTAssertEqual(got, titles.reversed())
    }

    func testCSVMatchesServerFormat() async throws {
        let b = makeBackend()
        let g = try await b.createGroup(name: "CSV", currency: "USD", members: ["Ann", "Bo"])
        _ = try await b.addExpense(g.id, expense("=HYPERLINK(\"x\"), dinner", "10", by: g.members[0].id, split: everyone(g), date: "2026-01-01"))
        let text = String(decoding: try await b.exportCSV(g.id), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "date,kind,title,category,amount,currency,paid_by,share_Ann,share_Bo")
        XCTAssertEqual(lines[1], "2026-01-01,expense,\"'=HYPERLINK(\"\"x\"\"), dinner\",general,10.00,USD,Ann,5.00,5.00")
    }

    func testRandomisedLedgersAlwaysSettle() {
        for _ in 0..<300 {
            let n = Int.random(in: 2...9)
            let members = (0..<n).map { Member(id: "m\($0)", name: "P\($0)") }
            var entries: [Entry] = []
            for k in 0..<Int.random(in: 1...20) {
                let amount = Int.random(in: 1...100_000)
                var parts = members.filter { _ in Bool.random() }
                if parts.isEmpty { parts = [members[0]] }
                let shares = try! Ledger.resolveSplit(amount: amount, split: SplitPayload(mode: "equal", participants: parts.map {
                    SplitParticipant(memberId: $0.id, value: nil)
                }), digits: 2)
                entries.append(Entry(id: "e\(k)", kind: "expense", title: "x", note: "", category: "general", amount: amount,
                                     paidBy: members.randomElement()!.id, splitMode: "equal", date: "2026-01-01",
                                     createdAt: "", updatedAt: "", shares: shares))
            }
            let balances = Ledger.balances(members: members, entries: entries)
            XCTAssertEqual(balances.reduce(0) { $0 + $1.net }, 0)
            let transfers = Ledger.transfers(balances)
            XCTAssertLessThanOrEqual(transfers.count, n - 1)
            var net = Dictionary(uniqueKeysWithValues: balances.map { ($0.memberId, $0.net) })
            for t in transfers {
                net[t.from]! += t.amount
                net[t.to]! -= t.amount
            }
            XCTAssertTrue(net.values.allSatisfy { $0 == 0 })
        }
    }

    /// Runs one scenario on the iPhone store and on a real server and requires identical results.
    func testParityWithRunningServer() async throws {
        let address = ProcessInfo.processInfo.environment["EVENLY_TEST_SERVER"] ?? "http://127.0.0.1:4173"
        let server = APIClient(baseURL: try XCTUnwrap(URL(string: address)))
        guard (try? await server.health()) == true else {
            throw XCTSkip("No Evenly server at \(address); start one with `npm start` to run the parity test.")
        }
        let local = makeBackend()
        let backends: [any EvenlyBackend] = [local, server]
        var results: [GroupSnapshot] = []
        for b in backends {
            var g = try await b.createGroup(name: "Parity", currency: "EUR", members: ["Ana", "Ben", "Cleo", "Dev"])
            let ids = g.members.map(\.id)
            let all = SplitPayload(mode: "equal", participants: ids.map { SplitParticipant(memberId: $0, value: nil) })
            let steps: [ExpensePayload] = [
                ExpensePayload(title: "Hotel", amount: "612.00", paidBy: ids[2], category: "stay", date: "2026-11-01", note: "", split: all),
                ExpensePayload(title: "Taxi", amount: "38.40", paidBy: ids[1], category: "transport", date: "2026-11-01", note: "", split: all),
                ExpensePayload(title: "Shop", amount: "86.75", paidBy: ids[0], category: "groceries", date: "2026-11-02", note: "", split: SplitPayload(mode: "exact", participants: [
                    SplitParticipant(memberId: ids[0], value: "30"), SplitParticipant(memberId: ids[1], value: "30.75"), SplitParticipant(memberId: ids[2], value: "26"),
                ])),
                ExpensePayload(title: "Show", amount: "100", paidBy: ids[1], category: "fun", date: "2026-11-03", note: "", split: SplitPayload(mode: "percent", participants: [
                    SplitParticipant(memberId: ids[0], value: "33.33"), SplitParticipant(memberId: ids[1], value: "33.33"), SplitParticipant(memberId: ids[3], value: "33.34"),
                ])),
                ExpensePayload(title: "Dinner", amount: "184.55", paidBy: ids[0], category: "food", date: "2026-11-03", note: "", split: SplitPayload(mode: "shares", participants: [
                    SplitParticipant(memberId: ids[0], value: "2"), SplitParticipant(memberId: ids[1], value: "1"), SplitParticipant(memberId: ids[2], value: "1.5"), SplitParticipant(memberId: ids[3], value: "1"),
                ])),
            ]
            for s in steps { g = try await b.addExpense(g.id, s).group }
            g = try await b.addTransfer(g.id, TransferPayload(amount: "50", paidBy: ids[3], to: ids[2], date: "2026-11-04", title: "")).group
            results.append(g)
            if !b.isLocal { try await b.deleteGroup(g.id) }
        }
        let (l, s) = (results[0], results[1])
        // Member ids differ between stores, so compare by position.
        func byPosition(_ g: GroupSnapshot) -> [Int] { g.balances.map(\.net) }
        func transfers(_ g: GroupSnapshot) -> [String] {
            let pos = Dictionary(uniqueKeysWithValues: g.members.enumerated().map { ($1.id, $0) })
            return g.transfers.map { "\(pos[$0.from]!)->\(pos[$0.to]!):\($0.amount)" }
        }
        func shares(_ g: GroupSnapshot) -> [[Int]] { g.entries.map { $0.shares.map(\.share) } }
        XCTAssertEqual(byPosition(l), byPosition(s))
        XCTAssertEqual(transfers(l), transfers(s))
        XCTAssertEqual(shares(l), shares(s))
        XCTAssertEqual(l.entries.map(\.title), s.entries.map(\.title))
        XCTAssertEqual(l.stats, s.stats)
        XCTAssertEqual(l.revision, s.revision)
    }

    private func assertStatus(_ status: Int, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected HTTP-style status \(status)", file: file, line: line)
        } catch let e as APIError {
            XCTAssertEqual(e.status, status, e.message, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}

@MainActor
final class StorageModeTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { makeTestDefaults(self) }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("evenly-mode-\(UUID().uuidString)/groups.json")
    }

    func testNewInstallDefaultsToThisIPhone() {
        let app = AppState(defaults: freshDefaults(), localFile: tempFile())
        XCTAssertEqual(app.mode, .device)
        XCTAssertTrue(app.backend?.isLocal == true)
    }

    func testExistingServerUsersStayOnServer() throws {
        let d = freshDefaults()
        let recent = RecentGroup(id: "abc123def456", name: "Old", currency: "USD", digits: 2, memberNames: ["A"], total: 0, seen: Date())
        d.set(try JSONEncoder().encode([recent]), forKey: "evenly.recents")
        let app = AppState(defaults: d, localFile: tempFile())
        XCTAssertEqual(app.mode, .server)
        app.mode = .device
        XCTAssertEqual(AppState(defaults: d, localFile: tempFile()).mode, .device, "the choice is remembered")
    }

    func testInviteLinksSwitchToServerMode() {
        let app = AppState(defaults: freshDefaults(), localFile: tempFile())
        app.open(InviteLink.Parsed(groupId: "abc123def456", server: URL(string: "http://192.168.1.9:4173")))
        XCTAssertEqual(app.mode, .server)
        XCTAssertEqual(app.serverURL?.absoluteString, "http://192.168.1.9:4173")
        XCTAssertEqual(app.path, ["abc123def456"])
    }

    func testLocalGroupsAppearInHomeList() async throws {
        let app = AppState(defaults: freshDefaults(), localFile: tempFile())
        let g = try await app.local.createGroup(name: "Weekend", currency: "CNY", members: ["Me", "You"])
        await app.refreshLocalGroups()
        XCTAssertEqual(app.groupList.map(\.id), [g.id])
        XCTAssertEqual(app.groupList.first?.memberNames, ["Me", "You"])
    }
}
