import AppCore
import Foundation

enum CoreAPIClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case missingActorCredential
    case actorIdentityMismatch(expected: String, received: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Agent Relay core service returned an invalid response."
        case let .httpStatus(status, body):
            return "The Agent Relay core service returned HTTP \(status): \(body)"
        case .missingActorCredential:
            return "AGENT_RELAY_ACTOR_ID and its local actor credential are required to post messages."
        case let .actorIdentityMismatch(expected, received):
            return "This MCP server is bound to \(expected), not \(received)."
        }
    }
}

struct RecentItemPayload: Codable, Equatable, Sendable {
    let eventID: String
    let type: EventType
    let threadID: String?
    let handoffID: String?
    let body: String
    let createdAt: Date
}

struct ThreadContextPayload: Codable, Equatable, Sendable {
    let thread: AppCore.Thread
    let messages: [Message]
    let handoffs: [Handoff]
}

struct CreateHandoffPayload: Codable, Sendable {
    let threadID: String
    let title: String
    let summary: String
    let ask: String
    let priority: HandoffPriority
    let createdBy: String
    let assignedTo: String
    let sourceRefs: [String]
}

struct CreateMessagePayload: Encodable, Sendable {
    let actorID: String
    let body: String
    let format: MessageFormat
    let replyToMessageID: String?
    let mentionedActorIDs: [String]
    let idempotencyKey: String

    init(
        actorID: String,
        body: String,
        format: MessageFormat,
        replyToMessageID: String?,
        mentionedActorIDs: [String],
        idempotencyKey: String = UUID().uuidString.lowercased()
    ) {
        self.actorID = actorID
        self.body = body
        self.format = format
        self.replyToMessageID = replyToMessageID
        self.mentionedActorIDs = mentionedActorIDs
        self.idempotencyKey = idempotencyKey
    }

    private enum CodingKeys: String, CodingKey {
        case actorID
        case body
        case format
        case replyToMessageID
        case mentionedActorIDs
    }
}

private struct UpdateHandoffPayload: Codable, Sendable {
    let status: HandoffStatus
    let resolution: String?
}

protocol CoreAPIClientProtocol: Sendable {
    func listProjects() async throws -> [Project]
    func listThreads(projectID: String) async throws -> [AppCore.Thread]
    func listInbox(actorID: String) async throws -> [Handoff]
    func listRecents() async throws -> [RecentItemPayload]
    func getThread(threadID: String, mode: String) async throws -> ThreadContextPayload
    func getMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message]
    func postMessage(threadID: String, request: CreateMessagePayload) async throws -> Message
    func createHandoff(_ request: CreateHandoffPayload) async throws -> Handoff
    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff
}

struct CoreAPIClient: CoreAPIClientProtocol {
    let baseURL: URL
    let authToken: String
    let actorID: String?
    let actorCredential: String?
    let session: URLSession

    init(
        baseURL: URL,
        authToken: String,
        actorID: String? = nil,
        actorCredential: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.actorID = actorID
        self.actorCredential = actorCredential
        self.session = session
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) throws -> CoreAPIClient {
        let actorID = environment["AGENT_RELAY_ACTOR_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedActorID = actorID.flatMap { $0.isEmpty ? nil : $0 }
        let actorCredential = try normalizedActorID.map {
            try AppRuntimeConfiguration.loadOrCreateActorCredential(
                actorID: $0,
                environment: environment
            )
        }
        return try CoreAPIClient(
            baseURL: AppRuntimeConfiguration.coreServiceURL(environment: environment),
            authToken: AppRuntimeConfiguration.loadOrCreateAuthToken(environment: environment),
            actorID: normalizedActorID,
            actorCredential: actorCredential,
            session: session
        )
    }

    func listProjects() async throws -> [Project] {
        try await decode(path: "projects", method: "GET")
    }

    func listThreads(projectID: String) async throws -> [AppCore.Thread] {
        try await decode(path: "projects/\(projectID)/threads", method: "GET")
    }

    func listInbox(actorID: String) async throws -> [Handoff] {
        try await decode(path: "inbox/\(actorID)", method: "GET")
    }

    func listRecents() async throws -> [RecentItemPayload] {
        try await decode(path: "recents", method: "GET")
    }

    func getThread(threadID: String, mode: String) async throws -> ThreadContextPayload {
        var components = URLComponents(url: baseURL.appending(path: "threads/\(threadID)/context"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "mode", value: mode)]
        guard let url = components?.url else {
            throw CoreAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func getMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message] {
        var components = URLComponents(
            url: baseURL.appending(path: "threads/\(threadID)/messages"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            queryItems.append(URLQueryItem(name: "before_created_at", value: Self.iso8601String(from: before.createdAt)))
            queryItems.append(URLQueryItem(name: "before_message_id", value: before.messageID))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw CoreAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func postMessage(threadID: String, request: CreateMessagePayload) async throws -> Message {
        guard let actorID, let actorCredential else {
            throw CoreAPIClientError.missingActorCredential
        }
        guard request.actorID == actorID else {
            throw CoreAPIClientError.actorIdentityMismatch(expected: actorID, received: request.actorID)
        }
        return try await send(
            path: "threads/\(threadID)/messages",
            method: "POST",
            payload: request,
            additionalHeaders: [
                ActorCredential.actorHeader: actorID,
                ActorCredential.credentialHeader: actorCredential,
                "Idempotency-Key": request.idempotencyKey,
            ]
        )
    }

    func createHandoff(_ request: CreateHandoffPayload) async throws -> Handoff {
        try await send(path: "handoffs", method: "POST", payload: request)
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        try await send(
            path: "handoffs/\(id)",
            method: "PUT",
            payload: UpdateHandoffPayload(status: status, resolution: resolution)
        )
    }

    private func decode<T: Decodable>(path: String, method: String) async throws -> T {
        try await decode(url: baseURL.appending(path: path), method: method)
    }

    private func decode<T: Decodable>(url: URL, method: String) async throws -> T {
        let data = try await perform(url: url, method: method, body: nil)
        return try makeDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        payload: Body,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        let encoder = makeEncoder()
        let body = try encoder.encode(payload)
        let data = try await perform(
            url: baseURL.appending(path: path),
            method: method,
            body: body,
            additionalHeaders: additionalHeaders
        )
        return try makeDecoder().decode(T.self, from: data)
    }

    private func perform(
        url: URL,
        method: String,
        body: Data?,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoreAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CoreAPIClientError.httpStatus(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func iso8601String(from date: Date) -> String {
        PreciseDateCodec.string(from: date)
    }
}
