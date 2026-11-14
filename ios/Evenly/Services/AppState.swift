import Foundation
import Observation

/// Where groups are stored.
enum StorageMode: String, CaseIterable, Identifiable {
    /// On this iPhone only. Works offline, no Mac or server needed.
    case device
    /// On an Evenly server, shareable with others by link.
    case server

    var id: String { rawValue }
    var label: String { self == .device ? t("This iPhone") : t("Evenly server") }
}

/// App wide state: storage mode, server address, the group list, and
/// per-group "which one are you" choices.
@MainActor
@Observable
final class AppState {
    static let defaultServer = "http://127.0.0.1:4173"

    private let defaults: UserDefaults
    let local: LocalBackend

    var mode: StorageMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            path = []
            Task { await refreshLocalGroups() }
        }
    }
    var serverAddress: String {
        didSet { defaults.set(serverAddress, forKey: Keys.server) }
    }
    /// Server groups this device has opened (servers cannot list groups).
    private(set) var recents: [RecentGroup] = []
    /// Groups stored on this iPhone.
    private(set) var localGroups: [GroupSnapshot] = []
    /// Latest snapshots of the server groups in `recents`, for the home dashboard.
    private(set) var serverGroups: [GroupSnapshot] = []
    var path: [String] = []
    var pendingNotice: String?
    var categories: [String] = LocalBackend.categories

    private enum Keys {
        static let mode = "evenly.mode"
        static let server = "evenly.server"
        static let recents = "evenly.recents"
        static func me(_ id: String) -> String { "evenly.me.\(id)" }
        static func lastPayer(_ id: String) -> String { "evenly.lastPayer.\(id)" }
    }

    init(defaults: UserDefaults = .standard, localFile: URL = LocalBackend.defaultFileURL()) {
        self.defaults = defaults
        local = LocalBackend(fileURL: localFile)
        serverAddress = defaults.string(forKey: Keys.server) ?? Self.defaultServer
        var saved: [RecentGroup] = []
        if let data = defaults.data(forKey: Keys.recents),
           let list = try? JSONDecoder().decode([RecentGroup].self, from: data) {
            saved = list
        }
        recents = saved
        // New installs keep data on the phone. Installs that already use a server stay on it,
        // so nobody's groups seem to vanish after an update.
        if let raw = defaults.string(forKey: Keys.mode), let m = StorageMode(rawValue: raw) {
            mode = m
        } else {
            mode = saved.isEmpty ? .device : .server
        }
    }

    var serverURL: URL? { Self.normalize(serverAddress) }

    var client: APIClient? { serverURL.map(APIClient.init(baseURL:)) }

    /// The backend for the current mode.
    var backend: (any EvenlyBackend)? { mode == .device ? local : client }

    var isLocal: Bool { mode == .device }

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

    // MARK: Group list

    /// What the home screen shows for the current mode.
    var groupList: [RecentGroup] {
        switch mode {
        case .server:
            return recents
        case .device:
            return localGroups.map { g in
                RecentGroup(id: g.id, name: g.name, currency: g.currency, digits: g.digits,
                            memberNames: g.members.map(\.name), total: g.stats.totalSpent,
                            seen: Self.parseTimestamp(g.updatedAt) ?? Date())
            }
        }
    }

    func refreshLocalGroups() async {
        localGroups = (try? await local.listGroups()) ?? []
    }

    /// Groups with full data for the home dashboard in the current mode.
    var dashboardGroups: [GroupSnapshot] { isLocal ? localGroups : serverGroups }

    /// Reloads whatever the home screen needs for the current mode.
    func refreshHome() async {
        if isLocal {
            await refreshLocalGroups()
            return
        }
        guard let client else { serverGroups = []; return }
        let ids = recents.map(\.id)
        var fetched: [String: GroupSnapshot] = [:]
        await withTaskGroup(of: (String, GroupSnapshot?).self) { tasks in
            for id in ids {
                tasks.addTask { (id, try? await client.group(id)) }
            }
            for await (id, g) in tasks { if let g { fetched[id] = g } }
        }
        // Keep the "most recently opened first" order; unreachable groups are simply left out.
        serverGroups = ids.compactMap { fetched[$0] }
    }

    func remember(_ g: GroupSnapshot) {
        if mode == .device {
            localGroups.removeAll { $0.id == g.id }
            localGroups.insert(g, at: 0)
            return
        }
        let item = RecentGroup(
            id: g.id, name: g.name, currency: g.currency, digits: g.digits,
            memberNames: g.members.map(\.name), total: g.stats.totalSpent, seen: Date()
        )
        recents.removeAll { $0.id == g.id }
        recents.insert(item, at: 0)
        serverGroups.removeAll { $0.id == g.id }
        serverGroups.insert(g, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        saveRecents()
    }

    func forget(_ id: String) {
        recents.removeAll { $0.id == id }
        localGroups.removeAll { $0.id == id }
        serverGroups.removeAll { $0.id == id }
        defaults.removeObject(forKey: Keys.me(id))
        defaults.removeObject(forKey: Keys.lastPayer(id))
        saveRecents()
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Keys.recents) }
    }

    /// Copies every server group this device knows about onto the iPhone.
    /// Returns how many were copied; groups that fail to load are skipped.
    func importServerGroups() async throws -> Int {
        guard let client else { throw APIError(status: 0, message: "no server address set", field: nil) }
        var copied = 0
        var lastError: Error?
        for r in recents {
            do {
                if let g = try await client.group(r.id) {
                    try await local.importGroup(g)
                    copied += 1
                }
            } catch {
                lastError = error
            }
        }
        if copied == 0, let lastError { throw lastError }
        await refreshLocalGroups()
        return copied
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
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

    // MARK: Deep links (always server groups)

    func open(_ url: URL) {
        guard let parsed = InviteLink.parse(url.absoluteString) else { return }
        open(parsed)
    }

    func open(_ parsed: InviteLink.Parsed) {
        if mode != .server {
            mode = .server
            pendingNotice = t("Switched to server mode to open a shared group")
        }
        if let server = parsed.server, Self.normalize(server.absoluteString) != serverURL {
            serverAddress = server.absoluteString
            pendingNotice = t("Connected to %@", server.host ?? server.absoluteString)
        }
        path = [parsed.groupId]
    }

    func refreshMeta() async {
        guard let backend, let meta = try? await backend.meta() else { return }
        categories = meta.categories
    }
}
