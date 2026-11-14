import Foundation

/// Everything the app needs from a place that stores groups. Two implementations:
/// `LocalBackend` keeps data on this iPhone; `APIClient` talks to an Evenly server.
protocol EvenlyBackend: Sendable {
    /// True when data lives on this device (no network, no sharing).
    var isLocal: Bool { get }

    func health() async throws -> Bool
    func meta() async throws -> Meta
    /// Every group this backend can enumerate. Servers cannot list groups, so they return [].
    func listGroups() async throws -> [GroupSnapshot]

    func createGroup(name: String, currency: String, members: [String]) async throws -> GroupSnapshot
    /// Returns nil when the group has not changed since `knownRevision`.
    func group(_ id: String, knownRevision: Int?) async throws -> GroupSnapshot?
    func updateGroup(_ id: String, name: String?, currency: String?) async throws -> GroupSnapshot
    func deleteGroup(_ id: String) async throws

    func addMember(_ groupId: String, name: String) async throws -> MemberResponse
    func renameMember(_ groupId: String, memberId: String, name: String) async throws -> GroupSnapshot
    func removeMember(_ groupId: String, memberId: String) async throws -> GroupSnapshot

    func addExpense(_ groupId: String, _ payload: ExpensePayload) async throws -> EntryResponse
    func addTransfer(_ groupId: String, _ payload: TransferPayload) async throws -> EntryResponse
    func updateExpense(_ groupId: String, entryId: String, _ payload: ExpensePayload) async throws -> GroupSnapshot
    func updateTransfer(_ groupId: String, entryId: String, _ payload: TransferPayload) async throws -> GroupSnapshot
    func deleteEntry(_ groupId: String, entryId: String) async throws -> GroupSnapshot

    func exportCSV(_ groupId: String) async throws -> Data
    /// A link others can open to join, or nil when the group cannot be shared.
    func inviteLink(for groupId: String) -> URL?
}

extension APIClient: EvenlyBackend {
    var isLocal: Bool { false }
    func listGroups() async throws -> [GroupSnapshot] { [] }
    func addExpense(_ groupId: String, _ payload: ExpensePayload) async throws -> EntryResponse { try await addEntry(groupId, payload) }
    func addTransfer(_ groupId: String, _ payload: TransferPayload) async throws -> EntryResponse { try await addEntry(groupId, payload) }
    func updateExpense(_ groupId: String, entryId: String, _ payload: ExpensePayload) async throws -> GroupSnapshot {
        try await updateEntry(groupId, entryId: entryId, payload)
    }
    func updateTransfer(_ groupId: String, entryId: String, _ payload: TransferPayload) async throws -> GroupSnapshot {
        try await updateEntry(groupId, entryId: entryId, payload)
    }
    func inviteLink(for groupId: String) -> URL? { webLink(for: groupId) }
}
