import XCTest
@testable import Evenly

final class LocalizationTests: XCTestCase {
    private var saved: AppLanguage = .system

    override func setUp() {
        saved = Localizer.shared.choice
    }

    override func tearDown() {
        Localizer.shared.choice = saved
    }

    /// Scans the app's Swift sources for every `t("...")`, `one: "..."` and `other: "..."`
    /// literal and requires a Chinese translation with matching placeholders.
    func testEveryUIStringHasAChineseTranslation() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Evenly")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Translations.swift" }
        XCTAssertGreaterThan(files.count, 10, "should find the app sources")

        let pattern = try NSRegularExpression(pattern: #"(?:\bt\(|\bone:\s*|\bother:\s*)"((?:[^"\\]|\\.)*)""#)
        var keys = Set(["All", "Expenses", "Payments", "Settlement"]) // used via rawValue / stored titles
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for m in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let literal = String(source[Range(m.range(at: 1), in: source)!])
                keys.insert(literal.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
            }
        }
        XCTAssertGreaterThan(keys.count, 150)

        let missing = keys.filter { Translations.zhHans[$0] == nil }.sorted()
        XCTAssertEqual(missing, [], "missing Chinese translations")

        func placeholders(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }
        for key in keys {
            guard let zh = Translations.zhHans[key] else { continue }
            XCTAssertEqual(placeholders(key), placeholders(zh), "placeholder count differs for \"\(key)\"")
            XCTAssertFalse(zh.contains("%d") || zh.contains("%s"), "only %@ placeholders are allowed: \(zh)")
        }
    }

    func testSwitchingLanguageChangesText() {
        Localizer.shared.choice = .english
        XCTAssertEqual(t("Settle up"), "Settle up")
        XCTAssertEqual(t("%@ paid %@", "Ana", "Ben"), "Ana paid Ben")
        XCTAssertEqual(tCount(1, one: "%@ person", other: "%@ people"), "1 person")
        XCTAssertEqual(tCount(3, one: "%@ person", other: "%@ people"), "3 people")
        XCTAssertEqual(CategoryStyle.of("food").label, "Food & drink")

        Localizer.shared.choice = .chinese
        XCTAssertEqual(t("Settle up"), "结清")
        XCTAssertEqual(t("%@ paid %@", "Ana", "Ben"), "Ana 付给了 Ben")
        XCTAssertEqual(tCount(3, one: "%@ person", other: "%@ people"), "3 人")
        XCTAssertEqual(t("%@%% left to assign", "50"), "还有 50% 未分配")
        XCTAssertEqual(CategoryStyle.of("food").label, "餐饮")
        XCTAssertEqual(SplitMode.shares.label, "份数")
        XCTAssertEqual(Day.label("2026-11-13", now: Day.date(from: "2026-11-13")!), "今天")
        XCTAssertEqual(Localizer.shared.locale.identifier, "zh-Hans")
    }

    func testSplitPreviewMessagesAreTranslated() {
        Localizer.shared.choice = .chinese
        let p = SplitCalculator.preview(amount: 1000, mode: .exact, memberIds: ["a", "b"], included: ["a", "b"],
                                        values: ["a": "2.50"], format: { Money.format($0, currency: "CNY", digits: 2) }, digits: 2)
        XCTAssertEqual(p.message, "还有 ¥7.50 未分配")
    }

    func testErrorsAreTranslated() {
        Localizer.shared.choice = .chinese
        XCTAssertEqual(APIError(status: 404, message: "group not found", field: nil).errorDescription, "找不到这个群组")
        XCTAssertEqual(APIError(status: 409, message: "someone called \"Ken\" is already in this group", field: nil).errorDescription,
                       "群组里已经有叫「Ken」的人了")
        XCTAssertEqual(APIError(status: 400, message: "member name must be at most 32 characters", field: nil).errorDescription,
                       "名字最多 32 个字")
        XCTAssertEqual(APIError(status: 400, message: "title is required", field: nil).errorDescription, "请填写描述")
        XCTAssertEqual(APIError(status: 400, message: "amount must be a positive number with up to 2 decimals", field: nil).errorDescription,
                       "金额必须是正数，最多 2 位小数")
        // Unknown messages fall back to the original text.
        XCTAssertEqual(APIError(status: 500, message: "brand new problem", field: nil).errorDescription, "Brand new problem")

        Localizer.shared.choice = .english
        XCTAssertEqual(APIError(status: 404, message: "group not found", field: nil).errorDescription, "Group not found")
    }

    func testChoiceIsRemembered() {
        let d = makeTestDefaults(self, prefix: "evenly-lang")
        let a = Localizer(defaults: d)
        XCTAssertEqual(a.choice, .system)
        a.choice = .chinese
        XCTAssertEqual(Localizer(defaults: d).choice, .chinese)
    }
}
