import XCTest
@testable import Evenly

final class SplitCalculatorTests: XCTestCase {
    let ids = ["a", "b", "c"]
    let fmt: (Int) -> String = { Money.format($0, currency: "USD", digits: 2) }

    private func preview(_ amount: Int?, _ mode: SplitMode, included: Set<String>? = nil, values: [String: String] = [:]) -> SplitPreview {
        SplitCalculator.preview(amount: amount, mode: mode, memberIds: ids, included: included ?? Set(ids),
                                values: values, format: fmt, digits: 2)
    }

    func testEqualSplitGivesRemainderToFirst() {
        let p = preview(1000, .equal)
        XCTAssertEqual([p.shares["a"], p.shares["b"], p.shares["c"]], [334, 333, 333])
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.message, "$3.33+ each")
    }

    func testExcludedPeopleOweNothing() {
        let p = preview(900, .equal, included: ["a", "c"])
        XCTAssertEqual(p.shares["b"], 0)
        XCTAssertEqual(p.shares["a"], 450)
    }

    func testExactMustAddUp() {
        let short = preview(1000, .exact, values: ["a": "2.50", "b": "5"])
        XCTAssertFalse(short.isValid)
        XCTAssertEqual(short.message, "$2.50 left to assign")
        let over = preview(1000, .exact, values: ["a": "8", "b": "5"])
        XCTAssertEqual(over.message, "$3.00 over the total")
        let exact = preview(1000, .exact, values: ["a": "2.50", "b": "7.50"])
        XCTAssertTrue(exact.isValid)
        XCTAssertEqual(exact.tone, .good)
        XCTAssertFalse(preview(1000, .exact, values: ["a": "x"]).isValid)
    }

    func testSharesAndPercent() {
        let shares = preview(900, .shares, values: ["a": "2", "b": "1", "c": "0"])
        XCTAssertEqual([shares.shares["a"], shares.shares["b"], shares.shares["c"]], [600, 300, 0])
        XCTAssertTrue(shares.isValid)
        let percent = preview(1000, .percent, values: ["a": "70", "b": "20", "c": "10"])
        XCTAssertTrue(percent.isValid)
        XCTAssertEqual(percent.shares["a"], 700)
        let partial = preview(1000, .percent, values: ["a": "50"])
        XCTAssertFalse(partial.isValid)
        XCTAssertEqual(partial.message, "50% left to assign")
    }

    func testNobodyIncludedIsInvalid() {
        XCTAssertFalse(preview(1000, .equal, included: []).isValid)
    }

    func testSeedValuesStartValid() {
        for mode in SplitMode.allCases {
            let values = SplitCalculator.seed(mode: mode, ids: ids, amount: 1000, digits: 2)
            XCTAssertTrue(preview(1000, mode, values: values).isValid, "\(mode) seed should be valid")
        }
        XCTAssertEqual(SplitCalculator.seed(mode: .percent, ids: ids, amount: nil, digits: 2), ["a": "33.33", "b": "33.33", "c": "33.34"])
    }
}

final class InviteLinkTests: XCTestCase {
    func testWebLinks() {
        let p = InviteLink.parse("http://192.168.1.20:4173/g/Fk9HAuaE2C4z")
        XCTAssertEqual(p?.groupId, "Fk9HAuaE2C4z")
        XCTAssertEqual(p?.server?.absoluteString, "http://192.168.1.20:4173")
        XCTAssertEqual(InviteLink.parse("https://evenly.example.com/g/abc123XYZ/")?.server?.absoluteString, "https://evenly.example.com")
    }

    func testCustomSchemeAndBareIds() {
        XCTAssertEqual(InviteLink.parse("evenly://g/abc123XYZ")?.groupId, "abc123XYZ")
        XCTAssertEqual(InviteLink.parse("evenly://g/abc123XYZ?server=https://e.example.com")?.server?.host, "e.example.com")
        XCTAssertEqual(InviteLink.parse("  Fk9HAuaE2C4z \n"), InviteLink.Parsed(groupId: "Fk9HAuaE2C4z", server: nil))
    }

    func testRejectsJunk() {
        XCTAssertNil(InviteLink.parse(""))
        XCTAssertNil(InviteLink.parse("https://example.com/"))
        XCTAssertNil(InviteLink.parse("https://example.com/x/abc123"))
        XCTAssertNil(InviteLink.parse("ftp://example.com/g/abc123"))
        XCTAssertNil(InviteLink.parse("not a link at all"))
    }

    func testServerAddressNormalisation() {
        XCTAssertEqual(AppState.normalize("192.168.1.5:4173")?.absoluteString, "http://192.168.1.5:4173")
        XCTAssertEqual(AppState.normalize("https://evenly.example.com/some/path?q=1")?.absoluteString, "https://evenly.example.com")
        XCTAssertNil(AppState.normalize("   "))
    }
}
