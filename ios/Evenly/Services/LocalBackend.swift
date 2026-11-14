import Foundation

/// Stores groups on this iPhone in a single JSON file. Validation, rounding and
/// error messages mirror src/store.js so behaviour matches the server exactly.
actor LocalBackend: EvenlyBackend {
    nonisolated var isLocal: Bool { true }

    static let categories = ["general", "food", "groceries", "transport", "stay", "fun", "utilities", "shopping"]
    private enum Limits { static let groupName = 60, memberName = 32, title = 80, note = 280, members = 50 }

    struct StoredGroup: Codable {
        var id: String
        var name: String
        var currency: String
        var createdAt: String
        var updatedAt: String
        var revision: Int
        var members: [Member]
        var entries: [Entry]
    }

    private struct Database: Codable {
        var version = 1
        var groups: [StoredGroup] = []
    }

    private let fileURL: URL
    private var db: Database?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: Application Support, which is included in iCloud and computer backups.
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Evenly", isDirectory: true).appendingPathComponent("groups.json")
    }

    // MARK: Persistence

    private func load() throws -> Database {
        if let db { return db }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            db = Database()
            return db!
        }
        do {
            let loaded = try JSONDecoder().decode(Database.self, from: Data(contentsOf: fileURL))
            db = loaded
            return loaded
        } catch {
            throw APIError(status: 500, message: "could not read the data saved on this iPhone", field: nil)
        }
    }

    private func save(_ next: Database) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(next)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            db = next
        } catch {
            throw APIError(status: 500, message: "could not save on this iPhone", field: nil)
        }
    }

    /// Runs a mutation against one group, bumps its revision and saves.
    private func mutate<T>(_ groupId: String, _ body: (inout StoredGroup) throws -> T) throws -> (T, StoredGroup) {
        var next = try load()
        guard let i = next.groups.firstIndex(where: { $0.id == groupId }) else { throw APIError(status: 404, message: "group not found", field: nil) }
        var g = next.groups[i]
        let result = try body(&g)
        g.updatedAt = Self.timestamp()
        g.revision += 1
        next.groups[i] = g
        try save(next)
        return (result, g)
    }

    private func find(_ id: String) throws -> StoredGroup {
        guard let g = try load().groups.first(where: { $0.id == id }) else { throw APIError(status: 404, message: "group not found", field: nil) }
        return g
    }

    // MARK: EvenlyBackend

    func health() async throws -> Bool { _ = try load(); return true }

    func meta() async throws -> Meta {
        let currencies = Dictionary(uniqueKeysWithValues: Money.currencyCodes.map {
            ($0, CurrencyInfo(symbol: Money.symbol(for: $0), digits: Money.digits(for: $0)))
        })
        return Meta(currencies: currencies, categories: Self.categories)
    }

    func listGroups() async throws -> [GroupSnapshot] {
        try load().groups.map(Self.snapshot).sorted { $0.updatedAt > $1.updatedAt }
    }

    func createGroup(name: String, currency: String, members: [String]) async throws -> GroupSnapshot {
        let cleanName = try Self.cleanText(name, field: "name", max: Limits.groupName)
        guard Money.currencyCodes.contains(currency) else {
            throw Ledger.invalid("currency must be one of \(Money.currencyCodes.joined(separator: ", "))", "currency")
        }
        guard !members.isEmpty else { throw Ledger.invalid("add at least one person", "members") }
        guard members.count <= Limits.members else { throw Ledger.invalid("a group can have at most \(Limits.members) people", "members") }
        var people: [Member] = []
        for raw in members {
            let n = try Self.cleanText(raw, field: "member name", max: Limits.memberName)
            try Self.assertUnique(n, in: people)
            people.append(Member(id: Self.newId(10), name: n))
        }
        let now = Self.timestamp()
        let g = StoredGroup(id: Self.newId(12), name: cleanName, currency: currency, createdAt: now, updatedAt: now,
                            revision: 1, members: people, entries: [])
        var next = try load()
        next.groups.append(g)
        try save(next)
        return Self.snapshot(g)
    }

    func group(_ id: String, knownRevision: Int?) async throws -> GroupSnapshot? {
        let g = try find(id)
        if let knownRevision, knownRevision == g.revision { return nil }
        return Self.snapshot(g)
    }

    func updateGroup(_ id: String, name: String?, currency: String?) async throws -> GroupSnapshot {
        let (_, g) = try mutate(id) { g in
            if let name { g.name = try Self.cleanText(name, field: "name", max: Limits.groupName) }
            if let currency, currency != g.currency {
                guard Money.currencyCodes.contains(currency) else { throw Ledger.invalid("unsupported currency", "currency") }
                if Money.digits(for: currency) != Money.digits(for: g.currency) && !g.entries.isEmpty {
                    throw APIError(status: 409, message: "cannot switch to a currency with different decimals once expenses exist", field: nil)
                }
                g.currency = currency
            }
        }
        return Self.snapshot(g)
    }

    func deleteGroup(_ id: String) async throws {
        var next = try load()
        guard next.groups.contains(where: { $0.id == id }) else { throw APIError(status: 404, message: "group not found", field: nil) }
        next.groups.removeAll { $0.id == id }
        try save(next)
    }

    func addMember(_ groupId: String, name: String) async throws -> MemberResponse {
        let (memberId, g) = try mutate(groupId) { g -> String in
            let n = try Self.cleanText(name, field: "member name", max: Limits.memberName)
            try Self.assertUnique(n, in: g.members)
            guard g.members.count < Limits.members else { throw Ledger.invalid("a group can have at most \(Limits.members) people", "members") }
            let m = Member(id: Self.newId(10), name: n)
            g.members.append(m)
            return m.id
        }
        return MemberResponse(memberId: memberId, group: Self.snapshot(g))
    }

    func renameMember(_ groupId: String, memberId: String, name: String) async throws -> GroupSnapshot {
        let (_, g) = try mutate(groupId) { g in
            guard let i = g.members.firstIndex(where: { $0.id == memberId }) else { throw APIError(status: 404, message: "person not found", field: nil) }
            let n = try Self.cleanText(name, field: "member name", max: Limits.memberName)
            try Self.assertUnique(n, in: g.members, except: memberId)
            g.members[i].name = n
        }
        return Self.snapshot(g)
    }

    func removeMember(_ groupId: String, memberId: String) async throws -> GroupSnapshot {
        let (_, g) = try mutate(groupId) { g in
            guard g.members.contains(where: { $0.id == memberId }) else { throw APIError(status: 404, message: "person not found", field: nil) }
            let used = g.entries.contains { $0.paidBy == memberId || $0.shares.contains { $0.memberId == memberId } }
            if used { throw APIError(status: 409, message: "this person is part of existing expenses; remove or edit those first", field: nil) }
            if g.members.count <= 1 { throw APIError(status: 409, message: "a group needs at least one person", field: nil) }
            g.members.removeAll { $0.id == memberId }
        }
        return Self.snapshot(g)
    }

    func addExpense(_ groupId: String, _ payload: ExpensePayload) async throws -> EntryResponse {
        try insert(groupId) { g in try Self.normalizeExpense(payload, in: g) }
    }

    func addTransfer(_ groupId: String, _ payload: TransferPayload) async throws -> EntryResponse {
        try insert(groupId) { g in try Self.normalizeTransfer(payload, in: g) }
    }

    func updateExpense(_ groupId: String, entryId: String, _ payload: ExpensePayload) async throws -> GroupSnapshot {
        try replace(groupId, entryId) { g in try Self.normalizeExpense(payload, in: g) }
    }

    func updateTransfer(_ groupId: String, entryId: String, _ payload: TransferPayload) async throws -> GroupSnapshot {
        try replace(groupId, entryId) { g in try Self.normalizeTransfer(payload, in: g) }
    }

    func deleteEntry(_ groupId: String, entryId: String) async throws -> GroupSnapshot {
        let (_, g) = try mutate(groupId) { g in
            guard g.entries.contains(where: { $0.id == entryId }) else { throw APIError(status: 404, message: "expense not found", field: nil) }
            g.entries.removeAll { $0.id == entryId }
        }
        return Self.snapshot(g)
    }

    func exportCSV(_ groupId: String) async throws -> Data {
        let s = Self.snapshot(try find(groupId))
        func esc(_ v: String) -> String {
            var t = v
            if let f = t.first, "=+-@\t\r".contains(f) { t = "'" + t }
            if t.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" }) { t = "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            return t
        }
        var rows = [["date", "kind", "title", "category", "amount", "currency", "paid_by"] + s.members.map { "share_\($0.name)" }]
        for e in s.entries.reversed() {
            let share = Dictionary(uniqueKeysWithValues: e.shares.map { ($0.memberId, $0.share) })
            rows.append([e.date, e.kind, e.title, e.category, Money.plain(e.amount, digits: s.digits), s.currency, s.name(of: e.paidBy)]
                        + s.members.map { Money.plain(share[$0.id] ?? 0, digits: s.digits) })
        }
        return Data((rows.map { $0.map(esc).joined(separator: ",") }.joined(separator: "\n") + "\n").utf8)
    }

    nonisolated func inviteLink(for groupId: String) -> URL? { nil }

    /// Copies a group fetched from a server onto this iPhone, keeping its ids.
    func importGroup(_ s: GroupSnapshot) throws {
        var next = try load()
        let g = StoredGroup(id: s.id, name: s.name, currency: s.currency, createdAt: s.createdAt, updatedAt: s.updatedAt,
                            revision: s.revision, members: s.members, entries: s.entries)
        if let i = next.groups.firstIndex(where: { $0.id == s.id }) { next.groups[i] = g } else { next.groups.append(g) }
        try save(next)
    }

    // MARK: Entry helpers

    private func insert(_ groupId: String, _ make: (StoredGroup) throws -> Entry) throws -> EntryResponse {
        let (entryId, g) = try mutate(groupId) { g -> String in
            let e = try make(g)
            g.entries.append(e)
            return e.id
        }
        return EntryResponse(entryId: entryId, group: Self.snapshot(g))
    }

    private func replace(_ groupId: String, _ entryId: String, _ make: (StoredGroup) throws -> Entry) throws -> GroupSnapshot {
        let (_, g) = try mutate(groupId) { g in
            guard let i = g.entries.firstIndex(where: { $0.id == entryId }) else { throw APIError(status: 404, message: "expense not found", field: nil) }
            let fresh = try make(g)
            let old = g.entries[i]
            g.entries[i] = Entry(id: old.id, kind: fresh.kind, title: fresh.title, note: fresh.note, category: fresh.category,
                                 amount: fresh.amount, paidBy: fresh.paidBy, splitMode: fresh.splitMode, date: fresh.date,
                                 createdAt: old.createdAt, updatedAt: fresh.updatedAt, shares: fresh.shares)
        }
        return Self.snapshot(g)
    }

    private static func parseAmount(_ raw: String, currency: String) throws -> Int {
        let digits = Money.digits(for: currency)
        guard let amount = Money.parse(raw, digits: digits), amount > 0 else {
            throw Ledger.invalid(digits > 0 ? "amount must be a positive number with up to \(digits) decimals" : "amount must be a positive whole number", "amount")
        }
        return amount
    }

    static func normalizeExpense(_ p: ExpensePayload, in g: StoredGroup) throws -> Entry {
        guard p.kind == "expense" else { throw Ledger.invalid("kind must be expense or transfer", "kind") }
        let amount = try parseAmount(p.amount, currency: g.currency)
        let ids = Set(g.members.map(\.id))
        guard ids.contains(p.paidBy) else { throw Ledger.invalid("paidBy must be someone in this group", "paidBy") }
        let title = try cleanText(p.title, field: "title", max: Limits.title)
        guard categories.contains(p.category) else { throw Ledger.invalid("category must be one of \(categories.joined(separator: ", "))", "category") }
        let shares = try Ledger.resolveSplit(amount: amount, split: p.split, digits: Money.digits(for: g.currency))
        guard shares.allSatisfy({ ids.contains($0.memberId) }) else {
            throw Ledger.invalid("split includes someone who is not in this group", "split.participants")
        }
        let now = timestamp()
        return Entry(id: newId(12), kind: "expense", title: title,
                     note: try cleanText(p.note, field: "note", max: Limits.note, required: false),
                     category: p.category, amount: amount, paidBy: p.paidBy, splitMode: p.split.mode,
                     date: try cleanDate(p.date), createdAt: now, updatedAt: now, shares: shares)
    }

    static func normalizeTransfer(_ p: TransferPayload, in g: StoredGroup) throws -> Entry {
        let amount = try parseAmount(p.amount, currency: g.currency)
        let ids = Set(g.members.map(\.id))
        guard ids.contains(p.paidBy) else { throw Ledger.invalid("paidBy must be someone in this group", "paidBy") }
        guard ids.contains(p.to) else { throw Ledger.invalid("transfer needs a recipient in this group", "to") }
        guard p.to != p.paidBy else { throw Ledger.invalid("cannot pay yourself", "to") }
        let title = try cleanText(p.title, field: "title", max: Limits.title, required: false)
        let now = timestamp()
        return Entry(id: newId(12), kind: "transfer", title: title.isEmpty ? "Settlement" : title, note: "",
                     category: "transfer", amount: amount, paidBy: p.paidBy, splitMode: "equal",
                     date: try cleanDate(p.date), createdAt: now, updatedAt: now,
                     shares: [Share(memberId: p.to, share: amount, weight: nil)])
    }

    // MARK: Snapshot

    static func snapshot(_ g: StoredGroup) -> GroupSnapshot {
        let order = Dictionary(uniqueKeysWithValues: g.members.enumerated().map { ($1.id, $0) })
        // Newest date first; ties go to the most recently entered, matching the server's
        // `ORDER BY date DESC, created_at DESC, rowid DESC` (entries are stored in insertion order).
        let entries = g.entries.enumerated()
            .sorted { a, b in
                if a.element.date != b.element.date { return a.element.date > b.element.date }
                if a.element.createdAt != b.element.createdAt { return a.element.createdAt > b.element.createdAt }
                return a.offset > b.offset
            }
            .map { pair in
                let e = pair.element
                return Entry(id: e.id, kind: e.kind, title: e.title, note: e.note, category: e.category, amount: e.amount,
                             paidBy: e.paidBy, splitMode: e.splitMode, date: e.date, createdAt: e.createdAt, updatedAt: e.updatedAt,
                             shares: e.shares.sorted { (order[$0.memberId] ?? 0) < (order[$1.memberId] ?? 0) })
            }
        let balances = Ledger.balances(members: g.members, entries: entries)
        let spent = entries.filter { !$0.isTransfer }
        var byCategory: [String: Int] = [:]
        for e in spent { byCategory[e.category, default: 0] += e.amount }
        return GroupSnapshot(
            id: g.id, name: g.name, currency: g.currency, digits: Money.digits(for: g.currency),
            createdAt: g.createdAt, updatedAt: g.updatedAt, revision: g.revision,
            members: g.members, entries: entries, balances: balances, transfers: Ledger.transfers(balances),
            stats: Stats(totalSpent: spent.reduce(0) { $0 + $1.amount }, expenseCount: spent.count,
                         byCategory: byCategory, settled: balances.allSatisfy { $0.net == 0 })
        )
    }

    // MARK: Cleaning

    static func cleanText(_ value: String, field: String, max: Int, required: Bool = true) throws -> String {
        // Same as the server: ASCII control characters become spaces, then whitespace collapses.
        // (CharacterSet.controlCharacters would also strip zero-width joiners and break emoji.)
        let collapsed = value.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : String($0) }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.isEmpty {
            if required { throw Ledger.invalid("\(field) is required", field) }
            return ""
        }
        guard collapsed.count <= max else { throw Ledger.invalid("\(field) must be at most \(max) characters", field) }
        return collapsed
    }

    static func cleanDate(_ value: String) throws -> String {
        if value.isEmpty { return Day.today }
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw Ledger.invalid("date must be YYYY-MM-DD", "date")
        }
        guard let d = Day.date(from: value), Day.string(from: d) == value else {
            throw Ledger.invalid("date is not a real calendar day", "date")
        }
        return value
    }

    static func assertUnique(_ name: String, in members: [Member], except: String? = nil) throws {
        if members.contains(where: { $0.id != except && $0.name.lowercased() == name.lowercased() }) {
            throw APIError(status: 409, message: "someone called \"\(name)\" is already in this group", field: nil)
        }
    }

    private static let alphabet = Array("23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")
    static func newId(_ length: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next(upperBound: UInt(alphabet.count)))] })
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
