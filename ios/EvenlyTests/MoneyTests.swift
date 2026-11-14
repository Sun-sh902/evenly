import XCTest
@testable import Evenly

final class MoneyTests: XCTestCase {
    func testParseMatchesServerRules() {
        XCTAssertEqual(Money.parse("12.34", digits: 2), 1234)
        XCTAssertEqual(Money.parse("12.3", digits: 2), 1230)
        XCTAssertEqual(Money.parse("12", digits: 2), 1200)
        XCTAssertEqual(Money.parse("1,234.50", digits: 2), 123_450)
        XCTAssertEqual(Money.parse(" 7 ", digits: 2), 700)
        XCTAssertEqual(Money.parse("500", digits: 0), 500)
        XCTAssertNil(Money.parse("5.5", digits: 0))
        XCTAssertNil(Money.parse("12.345", digits: 2))
        XCTAssertNil(Money.parse("-3", digits: 2))
        XCTAssertNil(Money.parse("1.", digits: 2))
        XCTAssertNil(Money.parse(".5", digits: 2))
        XCTAssertNil(Money.parse("abc", digits: 2))
        XCTAssertNil(Money.parse("", digits: 2))
        XCTAssertNil(Money.parse("1.2.3", digits: 2))
        XCTAssertNil(Money.parse("1234567890123", digits: 2))
    }

    func testPlainRoundTrips() {
        XCTAssertEqual(Money.plain(1234, digits: 2), "12.34")
        XCTAssertEqual(Money.plain(5, digits: 2), "0.05")
        XCTAssertEqual(Money.plain(-1050, digits: 2), "-10.50")
        XCTAssertEqual(Money.plain(700, digits: 0), "700")
        for v in [0, 1, 99, 100, 123_456_789] {
            XCTAssertEqual(Money.parse(Money.plain(v, digits: 2), digits: 2), v)
        }
    }

    func testFormat() {
        XCTAssertEqual(Money.format(114_165, currency: "EUR", digits: 2), "€1,141.65")
        XCTAssertEqual(Money.format(-300, currency: "USD", digits: 2), "-$3.00")
        XCTAssertEqual(Money.format(500, currency: "JPY", digits: 0, signed: true), "+¥500")
        XCTAssertEqual(Money.format(0, currency: "GBP", digits: 2, signed: true), "£0.00")
    }

    func testAllocateAlwaysSumsToTotal() {
        XCTAssertEqual(Money.allocate(100, weights: [1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(Money.allocate(1000, weights: [1, 2, 1]), [250, 500, 250])
        XCTAssertEqual(Money.allocate(1, weights: [1, 1]), [1, 0])
        XCTAssertEqual(Money.allocate(5, weights: [0, 0]), [0, 0])
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let total = Int.random(in: 0...10_000_000, using: &rng)
            let weights = (0..<Int.random(in: 1...9, using: &rng)).map { _ in Double.random(in: 0.01...10, using: &rng) }
            let parts = Money.allocate(total, weights: weights)
            XCTAssertEqual(parts.reduce(0, +), total)
            XCTAssertTrue(parts.allSatisfy { $0 >= 0 })
        }
    }

    func testDayStrings() {
        let d = Day.date(from: "2026-02-28")!
        XCTAssertEqual(Day.string(from: d), "2026-02-28")
        let now = Day.date(from: "2026-11-13")!
        XCTAssertEqual(Day.label("2026-11-13", now: now), "Today")
        XCTAssertEqual(Day.label("2026-11-12", now: now), "Yesterday")
    }
}
