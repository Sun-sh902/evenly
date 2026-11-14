import Foundation

// Mirrors the JSON returned by the Evenly server. Amounts are integer minor units.

struct Member: Codable, Identifiable, Hashable {
    let id: String
    var name: String
}

struct Share: Codable, Hashable {
    let memberId: String
    let share: Int
    let weight: Double?
}

struct Entry: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let note: String
    let category: String
    let amount: Int
    let paidBy: String
    let splitMode: String
    let date: String
    let createdAt: String
    let updatedAt: String
    let shares: [Share]

    var isTransfer: Bool { kind == "transfer" }
    var recipient: String? { isTransfer ? shares.first?.memberId : nil }
}

struct Balance: Codable, Hashable {
    let memberId: String
    let paid: Int
    let owed: Int
    let net: Int
}

struct Transfer: Codable, Hashable {
    let from: String
    let to: String
    let amount: Int
}

struct Stats: Codable, Hashable {
    let totalSpent: Int
    let expenseCount: Int
    let byCategory: [String: Int]
    let settled: Bool
}

struct GroupSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let currency: String
    let digits: Int
    let createdAt: String
    let updatedAt: String
    let revision: Int
    let members: [Member]
    let entries: [Entry]
    let balances: [Balance]
    let transfers: [Transfer]
    let stats: Stats

    func member(_ id: String?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    func name(of id: String?) -> String { member(id)?.name ?? "Someone" }

    func net(of id: String) -> Int { balances.first { $0.memberId == id }?.net ?? 0 }

    func colorIndex(of id: String) -> Int { members.firstIndex { $0.id == id } ?? 0 }

    func format(_ minor: Int, signed: Bool = false) -> String {
        Money.format(minor, currency: currency, digits: digits, signed: signed)
    }
}

struct CurrencyInfo: Codable, Hashable {
    let symbol: String
    let digits: Int
}

struct Meta: Codable {
    let currencies: [String: CurrencyInfo]
    let categories: [String]
}

struct EntryResponse: Codable {
    let entryId: String
    let group: GroupSnapshot
}

struct MemberResponse: Codable {
    let memberId: String
    let group: GroupSnapshot
}

// MARK: - Request payloads

struct SplitParticipant: Encodable, Equatable {
    let memberId: String
    let value: String?
}

struct SplitPayload: Encodable, Equatable {
    let mode: String
    let participants: [SplitParticipant]
}

struct ExpensePayload: Encodable {
    var kind = "expense"
    let title: String
    let amount: String
    let paidBy: String
    let category: String
    let date: String
    let note: String
    let split: SplitPayload
}

struct TransferPayload: Encodable {
    var kind = "transfer"
    let amount: String
    let paidBy: String
    let to: String
    let date: String
    let title: String
}

/// A group remembered on this device, for the home screen list.
struct RecentGroup: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var currency: String
    var digits: Int
    var memberNames: [String]
    var total: Int
    var seen: Date
}
