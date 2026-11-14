import Foundation
import Observation

/// Loads one group, keeps it fresh, and applies changes. Every mutation returns
/// the full snapshot from the server, so the UI never computes balances itself.
@MainActor
@Observable
final class GroupStore {
    enum Phase: Equatable { case loading, ready, missing, failed(String) }

    let groupId: String
    private(set) var group: GroupSnapshot?
    private(set) var phase: Phase = .loading
    var toast: String?
    /// Set while a sheet is open so background refreshes never yank data mid-edit.
    var isEditing = false

    private weak var app: AppState?

    /// Bound once: a group lives either on this iPhone or on a server.
    private let backend: (any EvenlyBackend)?

    init(groupId: String, app: AppState) {
        self.groupId = groupId
        self.app = app
        backend = app.backend
    }

    /// Local data can only change on this device, so there is nothing to poll for.
    var needsPolling: Bool { !(backend?.isLocal ?? true) }

    var inviteLink: URL? { backend?.inviteLink(for: groupId) }

    func load() async {
        guard let backend else { phase = .failed(t("Set a server address in Settings.")); return }
        if group == nil { phase = .loading }
        do {
            if let g = try await backend.group(groupId, knownRevision: nil) { apply(g) }
        } catch let e as APIError where e.status == 404 {
            app?.forget(groupId)
            phase = .missing
        } catch {
            if group == nil { phase = .failed(error.localizedDescription) } else { toast = error.localizedDescription }
        }
    }

    /// Cheap conditional refresh; the server answers 304 when nothing changed.
    func refresh(announce: Bool = false) async {
        guard let backend, let current = group, !isEditing else { return }
        do {
            if let fresh = try await backend.group(groupId, knownRevision: current.revision), fresh.revision > current.revision {
                apply(fresh)
                if announce { toast = t("Updated with the latest changes") }
            }
        } catch let e as APIError where e.status == 404 {
            app?.forget(groupId)
            phase = .missing
        } catch {
            // Offline or server restarting: keep showing what we have.
        }
    }

    func pollForever(every seconds: Double = 12) async {
        guard needsPolling else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { break }
            await refresh(announce: true)
        }
    }

    private func apply(_ g: GroupSnapshot) {
        group = g
        phase = .ready
        app?.remember(g)
    }

    // MARK: Mutations. Each throws APIError so sheets can show inline messages.

    private func requireClient() throws -> any EvenlyBackend {
        guard let backend else { throw APIError(status: 0, message: "no server configured", field: nil) }
        return backend
    }

    func saveExpense(_ payload: ExpensePayload, editing entryId: String?) async throws {
        let c = try requireClient()
        if let entryId {
            apply(try await c.updateExpense(groupId, entryId: entryId, payload))
        } else {
            apply(try await c.addExpense(groupId, payload).group)
        }
        app?.setLastPayer(payload.paidBy, groupId: groupId)
    }

    func savePayment(_ payload: TransferPayload, editing entryId: String?) async throws {
        let c = try requireClient()
        if let entryId {
            apply(try await c.updateTransfer(groupId, entryId: entryId, payload))
        } else {
            apply(try await c.addTransfer(groupId, payload).group)
        }
    }

    func deleteEntry(_ entryId: String) async throws {
        apply(try await requireClient().deleteEntry(groupId, entryId: entryId))
    }

    func addMember(_ name: String) async throws {
        apply(try await requireClient().addMember(groupId, name: name).group)
    }

    func renameMember(_ memberId: String, to name: String) async throws {
        apply(try await requireClient().renameMember(groupId, memberId: memberId, name: name))
    }

    func removeMember(_ memberId: String) async throws {
        apply(try await requireClient().removeMember(groupId, memberId: memberId))
    }

    func updateGroup(name: String, currency: String) async throws {
        apply(try await requireClient().updateGroup(groupId, name: name, currency: currency))
    }

    func deleteGroup() async throws {
        try await requireClient().deleteGroup(groupId)
        app?.forget(groupId)
    }

    func exportCSV() async throws -> URL {
        let data = try await requireClient().exportCSV(groupId)
        let safe = (group?.name ?? "evenly").replacingOccurrences(of: "[^A-Za-z0-9-_ ]", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "evenly" : safe).csv")
        try data.write(to: url, options: .atomic)
        return url
    }
}
