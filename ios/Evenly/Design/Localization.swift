import Foundation
import Observation

/// The language the app shows, chosen in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese

    var id: String { rawValue }

    /// Each language is named in itself so people can always find their own.
    var displayName: String {
        switch self {
        case .system: t("Follow system")
        case .english: "English"
        case .chinese: "简体中文"
        }
    }
}

/// Holds the current language. Views read it through `t(...)`, and because the
/// class is @Observable, every screen re-renders the moment the language changes.
@Observable
final class Localizer {
    static let shared = Localizer()

    private static let key = "evenly.language"
    private let defaults: UserDefaults

    var choice: AppLanguage {
        didSet { defaults.set(choice.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Whether Chinese is in effect right now (for "Follow system", the device's first language decides).
    var isChinese: Bool {
        switch choice {
        case .english: false
        case .chinese: true
        case .system: Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }

    /// Locale for system controls (date pickers) and date formatting.
    var locale: Locale { isChinese ? Locale(identifier: "zh-Hans") : Locale(identifier: "en_US") }

    func translate(_ key: String) -> String {
        guard isChinese else { return key }
        return Translations.zhHans[key] ?? key
    }
}

/// Translates an English source string. Placeholders are `%@`; pass every argument
/// as a String so formats can never mismatch, e.g. `t("%@ paid %@", payer, name)`.
func t(_ key: String, _ args: String...) -> String {
    let format = Localizer.shared.translate(key)
    guard !args.isEmpty else { return format }
    return String(format: format, arguments: args.map { $0 as CVarArg })
}

/// Singular/plural English keys that collapse to one Chinese form.
func tCount(_ n: Int, one: String, other: String) -> String {
    t(n == 1 ? one : other, String(n))
}

/// Error messages come from the server or the on-device store in English.
/// Known messages are translated; anything unrecognised is shown as is.
func translateError(_ message: String) -> String {
    let l = Localizer.shared
    guard l.isChinese else { return message }
    if let exact = Translations.zhHansErrors[message] { return exact }
    for (pattern, template) in Translations.zhHansErrorPatterns {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) else { continue }
        var out = template
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: message) else { continue }
            let value = String(message[r])
            out = out.replacingOccurrences(of: "$\(i)", with: Translations.zhHansFields[value] ?? value)
        }
        return out
    }
    return message
}
