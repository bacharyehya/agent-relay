import AppCore
import Foundation

public enum RelayCloudError: LocalizedError, Equatable, Sendable {
    case invalidServerURL
    case invalidResponse
    case server(status: Int, message: String)
    case missingCredential

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid HTTPS Relay server address."
        case .invalidResponse:
            return "The Relay service returned an invalid response."
        case let .server(_, message):
            return message
        case .missingCredential:
            return "This device is not signed into Agent Relay."
        }
    }
}

public struct RelayCloudAPI: Sendable {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) throws {
        guard let scheme = baseURL.scheme?.lowercased(), ["https", "http"].contains(scheme), baseURL.host != nil else {
            throw RelayCloudError.invalidServerURL
        }
        #if !DEBUG
        guard scheme == "https" else { throw RelayCloudError.invalidServerURL }
        #endif
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func health() async throws -> RelayServiceHealth {
        try await send(path: "health", requiresToken: false)
    }

    public func bootstrap(
        key: String,
        workspaceName: String,
        actorID: String,
        displayName: String,
        deviceName: String
    ) async throws -> RelayEnrollmentEnvelope {
        try await send(
            path: "v1/bootstrap",
            method: "POST",
            body: [
                "workspaceName": workspaceName,
                "actorID": actorID,
                "displayName": displayName,
                "deviceName": deviceName,
            ],
            headers: ["X-Relay-Bootstrap-Key": key],
            requiresToken: false
        )
    }

    public func enroll(code: String, deviceName: String) async throws -> RelayEnrollmentEnvelope {
        try await send(
            path: "v1/enroll",
            method: "POST",
            body: ["code": code, "deviceName": deviceName],
            requiresToken: false
        )
    }

    public func me() async throws -> RelayIdentityEnvelope {
        try await send(path: "v1/me")
    }

    public func sync(after cursor: Int, limit: Int = 300) async throws -> RelaySyncSnapshot {
        try await send(path: "v1/sync", query: ["after": String(cursor), "limit": String(limit)])
    }

    public func listRooms() async throws -> [RelayCloudRoom] {
        try await send(path: "v1/rooms")
    }

    public func createRoom(name: String, topic: String) async throws -> RelayCloudRoom {
        try await send(path: "v1/rooms", method: "POST", body: ["name": name, "topic": topic])
    }

    public func messages(roomID: String, after cursor: Int = 0, limit: Int = 200) async throws -> [RelayCloudMessage] {
        try await send(
            path: "v1/rooms/\(roomID)/messages",
            query: ["after": String(cursor), "limit": String(limit)]
        )
    }

    public func messages(roomID: String, before cursor: Int?, limit: Int = 200) async throws -> [RelayCloudMessage] {
        var query = ["limit": String(limit)]
        if let cursor { query["before"] = String(cursor) }
        return try await send(path: "v1/rooms/\(roomID)/messages", query: query)
    }

    public func postMessage(
        roomID: String,
        message: RelayPostMessage,
        idempotencyKey: String
    ) async throws -> RelayCloudMessage {
        try await send(
            path: "v1/rooms/\(roomID)/messages",
            method: "POST",
            body: message,
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    public func mentions(after cursor: Int = 0, limit: Int = 200) async throws -> [RelayCloudMessage] {
        try await send(path: "v1/mentions", query: ["after": String(cursor), "limit": String(limit)])
    }

    public func search(_ query: String, limit: Int = 50) async throws -> [RelayCloudMessage] {
        try await send(path: "v1/search", query: ["q": query, "limit": String(limit)])
    }

    public func markRead(roomID: String, sequence: Int) async throws -> RelayReadReceipt {
        try await send(path: "v1/rooms/\(roomID)/read", method: "POST", body: ["sequence": sequence])
    }

    public func updatePresence(state: String, deviceName: String) async throws -> RelayPresence {
        try await send(path: "v1/presence", method: "POST", body: ["state": state, "deviceName": deviceName])
    }

    public func createAgentInvitation(actorID: String, displayName: String) async throws -> RelayInvitation {
        try await send(
            path: "v1/invitations",
            method: "POST",
            body: ["kind": "agent", "actorID": actorID, "displayName": displayName]
        )
    }

    public func createHumanDeviceInvitation() async throws -> RelayInvitation {
        try await send(path: "v1/invitations", method: "POST", body: ["kind": "human-device"])
    }

    public func devices() async throws -> [RelayDeviceSummary] {
        try await send(path: "v1/devices")
    }

    public func revokeDevice(id: String) async throws -> RelayDeviceSummary {
        try await send(path: "v1/devices/\(id)/revoke", method: "POST", body: EmptyBody())
    }

    private func send<Response: Decodable>(
        path: String,
        query: [String: String] = [:],
        method: String = "GET",
        headers: [String: String] = [:],
        requiresToken: Bool = true
    ) async throws -> Response {
        try await send(path: path, query: query, method: method, bodyData: nil, headers: headers, requiresToken: requiresToken)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        query: [String: String] = [:],
        method: String,
        body: Body,
        headers: [String: String] = [:],
        requiresToken: Bool = true
    ) async throws -> Response {
        let data = try Self.encoder.encode(body)
        return try await send(
            path: path,
            query: query,
            method: method,
            bodyData: data,
            headers: headers,
            requiresToken: requiresToken
        )
    }

    private func send<Response: Decodable>(
        path: String,
        query: [String: String],
        method: String,
        bodyData: Data?,
        headers: [String: String],
        requiresToken: Bool
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted(by: { $0.key < $1.key }).map(URLQueryItem.init(name:value:))
        }
        guard let url = components?.url else { throw RelayCloudError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if requiresToken {
            guard let token, !token.isEmpty else { throw RelayCloudError.missingCredential }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw RelayCloudError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            throw RelayCloudError.server(
                status: httpResponse.statusCode,
                message: envelope?.error ?? "Relay responded with status \(httpResponse.statusCode)."
            )
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw RelayCloudError.invalidResponse
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = PreciseDateCodec.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }()
}

private struct ErrorEnvelope: Decodable {
    let error: String
}

private struct EmptyBody: Encodable {}
