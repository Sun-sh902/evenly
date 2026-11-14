import Foundation
import XCTest

/// Throwaway UserDefaults for tests. `removePersistentDomain` clears the keys but
/// leaves an empty plist behind, so the file itself is deleted too.
func makeTestDefaults(_ testCase: XCTestCase, prefix: String = "evenly-tests") -> UserDefaults {
    let name = "\(prefix)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    testCase.addTeardownBlock {
        defaults.removePersistentDomain(forName: name)
        let prefs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences").appendingPathComponent("\(name).plist")
        try? FileManager.default.removeItem(at: prefs)
    }
    return defaults
}
