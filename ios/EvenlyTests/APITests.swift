import XCTest
@testable import Evenly

/// Decoding test against a fixed payload, plus an end-to-end test against a
/// running Evenly server. The end-to-end test is skipped when no server is up;
/// point it elsewhere with the EVENLY_TEST_SERVER environment variable.
final class APITests: XCTestCase {
    func testDecodesServerSnapshot() throws {
        let json = """
        {"id":"abc123def456","name":"Trip","currency":"EUR","digits":2,"createdAt":"2026-11-08T10:00:00Z",
         "updatedAt":"2026-11-08T10:00:00Z","revision":3,
         "members":[{"id":"m1","name":"Ana"},{"id":"m2","name":"Ben"}],
         "entries":[{"id":"e1","kind":"expense","title":"Dinner","note":"","category":"food","amount":1000,"paidBy":"m1",
           "splitMode":"shares","date":"2026-11-08","createdAt":"x","updatedAt":"x",
           "shares":[{"memberId":"m1","share":500,"weight":1},{"memberId":"m2","share":500,"weight":null}]}],
         "balances":[{"memberId":"m1","paid":1000,"owed":500,"net":500},{"memberId":"m2","paid":0,"owed":500,"net":-500}],
         "transfers":[{"from":"m2","to":"m1","amount":500}],
         "stats":{"totalSpent":1000,"expenseCount":1,"byCategory":{"food":1000},"settled":false},
         "display":{"totalSpent":"10.00"}}
        """
        let g = try JSONDecoder().decode(GroupSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(g.revision, 3)
        XCTAssertEqual(g.name(of: "m2"), "Ben")
        XCTAssertEqual(g.net(of: "m2"), -500)
        XCTAssertEqual(g.entries.first?.shares.last?.weight, nil)
        XCTAssertEqual(g.format(g.stats.totalSpent), "€10.00")
    }

    func testPayloadOmitsValueForEqualSplits() throws {
        let p = SplitPayload(mode: "equal", participants: [SplitParticipant(memberId: "a", value: nil)])
        let text = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(text.contains("value"))
    }

    func testEndToEndAgainstRunningServer() async throws {
        let address = ProcessInfo.processInfo.environment["EVENLY_TEST_SERVER"] ?? "http://127.0.0.1:4173"
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: address)))
        guard (try? await client.health()) == true else {
            throw XCTSkip("No Evenly server at \(address); start one with `npm start` to run this test.")
        }

        var g = try await client.createGroup(name: "iOS test", currency: "USD", members: ["Ana", "Ben", "Cleo"])
        let ids = g.members.map(\.id)
        let payload = ExpensePayload(
            title: "Dinner", amount: "100", paidBy: ids[0], category: "food", date: "2026-11-13", note: "",
            split: SplitPayload(mode: "equal", participants: ids.map { SplitParticipant(memberId: $0, value: nil) })
        )
        g = try await client.addEntry(g.id, payload).group
        XCTAssertEqual(g.entries.first?.shares.map(\.share), [3334, 3333, 3333])
        XCTAssertEqual(g.net(of: ids[0]), 6666)

        // Conditional GET: unchanged group answers 304, which the client reports as nil.
        let unchanged = try await client.group(g.id, knownRevision: g.revision)
        XCTAssertNil(unchanged)

        // Server-side validation errors surface with their field.
        do {
            _ = try await client.addEntry(g.id, TransferPayload(amount: "5", paidBy: ids[0], to: ids[0], date: "2026-11-13", title: "x"))
            XCTFail("expected a validation error")
        } catch let e as APIError {
            XCTAssertEqual(e.status, 400)
            XCTAssertEqual(e.field, "to")
        }

        // Settle everything and confirm the group ends at zero.
        for t in g.transfers {
            g = try await client.addEntry(g.id, TransferPayload(
                amount: Money.plain(t.amount, digits: 2), paidBy: t.from, to: t.to, date: "2026-11-13", title: "Settlement"
            )).group
        }
        XCTAssertTrue(g.stats.settled)
        XCTAssertTrue(g.transfers.isEmpty)

        try await client.deleteGroup(g.id)
        do {
            _ = try await client.group(g.id)
            XCTFail("expected 404")
        } catch let e as APIError {
            XCTAssertEqual(e.status, 404)
        }
    }
}
