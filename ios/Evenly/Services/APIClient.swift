import Foundation

struct APIError: LocalizedError, Equatable {
    let status: Int
    let message: String
    let field: String?

    var errorDescription: String? {
        let text = translateError(message)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func transport(_ error: Error) -> APIError {
        APIError(status: 0, message: "could not reach the server. Check the server address in Settings", field: nil)
    }
}

/// Thin async client for the Evenly HTTP API.
struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: Endpoints

    func health() async throws -> Bool {
        struct Health: Decodable { let ok: Bool }
        let h: Health = try await request("GET", "/api/health")
        return h.ok
    }

    func meta() async throws -> Meta {
        try await request("GET", "/api/meta")
    }

    func createGroup(name: String, currency: String, members: [String]) async throws -> GroupSnapshot {
        struct Body: Encodable { let name: String; let currency: String; let members: [String] }
        return try await request("POST", "/api/groups", body: Body(name: name, currency: currency, members: members))
    }

    /// Returns nil when the server reports the group has not changed since `knownRevision`.
    func group(_ id: String, knownRevision: Int? = nil) async throws -> GroupSnapshot? {
        var headers: [String: String] = [:]
        if let knownRevision { headers["If-None-Match"] = "W/\"\(id)-\(knownRevision)\"" }
        let (data, status) = try await raw("GET", "/api/groups/\(id)", headers: headers)
        if status == 304 { return nil }
        return try decode(GroupSnapshot.self, data)
    }

    func updateGroup(_ id: String, name: String?, currency: String?) async throws -> GroupSnapshot {
        struct Body: Encodable { let name: String?; let currency: String? }
        return try await request("PATCH", "/api/groups/\(id)", body: Body(name: name, currency: currency))
    }

    func deleteGroup(_ id: String) async throws {
        _ = try await raw("DELETE", "/api/groups/\(id)")
    }

    func addMember(_ groupId: String, name: String) async throws -> MemberResponse {
        struct Body: Encodable { let name: String }
        return try await request("POST", "/api/groups/\(groupId)/members", body: Body(name: name))
    }

    func renameMember(_ groupId: String, memberId: String, name: String) async throws -> GroupSnapshot {
        struct Body: Encodable { let name: String }
        return try await request("PATCH", "/api/groups/\(groupId)/members/\(memberId)", body: Body(name: name))
    }

    func removeMember(_ groupId: String, memberId: String) async throws -> GroupSnapshot {
        try await request("DELETE", "/api/groups/\(groupId)/members/\(memberId)")
    }

    func addEntry<B: Encodable>(_ groupId: String, _ body: B) async throws -> EntryResponse {
        try await request("POST", "/api/groups/\(groupId)/entries", body: body)
    }

    func updateEntry<B: Encodable>(_ groupId: String, entryId: String, _ body: B) async throws -> GroupSnapshot {
        try await request("PUT", "/api/groups/\(groupId)/entries/\(entryId)", body: body)
    }

    func deleteEntry(_ groupId: String, entryId: String) async throws -> GroupSnapshot {
        try await request("DELETE", "/api/groups/\(groupId)/entries/\(entryId)")
    }

    func exportCSV(_ groupId: String) async throws -> Data {
        try await raw("GET", "/api/groups/\(groupId)/export.csv").0
    }

    /// Web link to a group on this server, used for sharing.
    func webLink(for groupId: String) -> URL {
        baseURL.appendingPathComponent("g").appendingPathComponent(groupId)
    }

    // MARK: Plumbing

    private struct NoBody: Encodable {}

    private func request<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await request(method, path, body: Optional<NoBody>.none)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        let data = try body.map { try JSONEncoder().encode($0) }
        let (bytes, _) = try await raw(method, path, body: data)
        return try decode(T.self, bytes)
    }

    private func raw(_ method: String, _ path: String, body: Data? = nil, headers: [String: String] = [:]) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError(status: 0, message: "invalid server address", field: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || status == 304 { return (data, status) }

        struct ErrorBody: Decodable { let error: String; let field: String? }
        if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            throw APIError(status: status, message: e.error, field: e.field)
        }
        throw APIError(status: status, message: "request failed (\(status))", field: nil)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError(status: 0, message: "the server sent something unexpected. Is this an Evenly server?", field: nil)
        }
    }
}
