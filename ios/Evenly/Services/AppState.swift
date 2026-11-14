import Foundation
import Observation

/// App wide state: server address, groups remembered on this device, and
/// per-group "which one are you" choices. Everything here is device local.
@MainActor
@Observable
final class AppState {
    static let defaultServer = "http://127.0.0.1:4173"

    private let defaults: UserDefaults

    var serverAddress: String {
        didSet { defaults.set(serverAddress, forKey: Keys.server) }
    }
    private(set) var recents: [RecentGroup] = []
    var path: [String] = []
    var pendingNotice: String?
    var categories: [String] = ["general", "food", "groceries", "transport", "stay", "fun", "utilities", "shopping"]

    private enum Keys {
        static let server = "evenly.server"
        static let recents = "evenly.recents"
        static func me(_ id: String) -> String { "evenly.me.\(id)" }
        static func lastPayer(_ id: String) -> String { "evenly.lastPayer.\(id)" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverAddress = defaults.string(forKey: Keys.server) ?? Self.defaultServer
        if let data = defaults.data(forKey: Keys.recents),
           let list = try? JSONDecoder().decode([RecentGroup].self, from: data) {
            recents = list
        }
    }

    var serverURL: URL? { Self.normalize(serverAddress) }

    var client: APIClient? { serverURL.map(APIClient.init(baseURL:)) }

    /// Accepts "192.168.1.5:4173" or "https://evenly.example.com/" and returns a clean origin.
    nonisolated static func normalize(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        guard var comps = URLComponents(string: s), let host = comps.host, !host.isEmpty else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    // MARK: Recents

    func remember(_ g: GroupSnapshot) {
        let item = RecentGroup(
            id: g.id, name: g.name, currency: g.currency, digits: g.digits,
            memberNames: g.members.map(\.name), total: g.stats.totalSpent, seen: Date()
        )
        recents.removeAll { $0.id == g.id }
        recents.insert(item, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        saveRecents()
    }

    func forget(_ id: String) {
        recents.removeAll { $0.id == id }
        defaults.removeObject(forKey: Keys.me(id))
        defaults.removeObject(forKey: Keys.lastPayer(id))
        saveRecents()
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Keys.recents) }
    }

    // MARK: Identity

    func me(in g: GroupSnapshot) -> String? {
        guard let id = defaults.string(forKey: Keys.me(g.id)), g.member(id) != nil else { return nil }
        return id
    }

    func setMe(_ memberId: String?, groupId: String) {
        if let memberId { defaults.set(memberId, forKey: Keys.me(groupId)) } else { defaults.removeObject(forKey: Keys.me(groupId)) }
        meVersion += 1
    }

    /// Bumped so views observing identity re-render after a change.
    private(set) var meVersion = 0

    func lastPayer(groupId: String) -> String? { defaults.string(forKey: Keys.lastPayer(groupId)) }
    func setLastPayer(_ id: String, groupId: String) { defaults.set(id, forKey: Keys.lastPayer(groupId)) }

    // MARK: Deep links

    func open(_ url: URL) {
        guard let parsed = InviteLink.parse(url.absoluteString) else { return }
        open(parsed)
    }

    func open(_ parsed: InviteLink.Parsed) {
        if let server = parsed.server, Self.normalize(server.absoluteString) != serverURL {
            serverAddress = server.absoluteString
            pendingNotice = "Connected to \(server.host ?? server.absoluteString)"
        }
        path = [parsed.groupId]
    }

    func refreshMeta() async {
        guard let client, let meta = try? await client.meta() else { return }
        categories = meta.categories
    }
}
