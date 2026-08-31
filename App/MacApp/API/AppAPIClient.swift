import Foundation
import AppCore

enum AppAPIClientError: Error {
    case invalidResponse
    case httpStatus(Int, String)
    case actorIdentityMismatch(expected: String, received: String)
}

extension AppAPIClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The local core service returned an invalid response."
        case let .httpStatus(statusCode, body):
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBody.isEmpty {
                return "The local core service responded with status \(statusCode)."
            }
            return "The local core service responded with status \(statusCode): \(trimmedBody)"
        case let .actorIdentityMismatch(expected, received):
            return "This app is bound to \(expected), not \(received)."
        }
    }
}

struct AppHealth: Codable, Equatable, Sendable {
    let status: String
}

struct AppRecentItem: Codable, Equatable, Identifiable, Sendable {
    let eventID: String
    let type: EventType
    let threadID: String?
    let handoffID: String?
    let body: String
    let createdAt: Date

    var id: String { eventID }
}

struct AppSearchResult: Codable, Equatable, Identifiable, Sendable {
    let objectID: String
    let objectType: String
    let body: String

    var id: String { "\(objectType):\(objectID)" }
}

struct AppThreadContext: Codable, Equatable, Sendable {
    let thread: AppCore.Thread
    var messages: [Message]
    var handoffs: [Handoff]
}

struct AppPostMessageRequest: Encodable, Equatable, Sendable {
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

struct AppCreateHandoffRequest: Codable, Sendable {
    let threadID: String
    let title: String
    let summary: String
    let ask: String
    let priority: HandoffPriority
    let createdBy: String
    let assignedTo: String
    let sourceRefs: [String]
}

private struct AppUpdateHandoffRequest: Codable, Sendable {
    let status: HandoffStatus
    let resolution: String?
}

protocol AppAPIClientProtocol: Sendable {
    func fetchHealth() async throws -> AppHealth
    func fetchInbox(actorID: String) async throws -> [Handoff]
    func fetchRecents() async throws -> [AppRecentItem]
    func search(query: String) async throws -> [AppSearchResult]
    func fetchProjects() async throws -> [Project]
    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread]
    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext
    func fetchThreadMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message]
    func fetchMentions(actorID: String, limit: Int) async throws -> [Message]
    func postMessage(threadID: String, request: AppPostMessageRequest) async throws -> Message
    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff
    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff
}

extension AppAPIClientProtocol {
    func fetchMentions(actorID: String, limit: Int) async throws -> [Message] { [] }
}

struct AppAPIClient: AppAPIClientProtocol {
    let baseURL: URL
    let authToken: String
    let actorID: String
    let actorCredential: String
    let session: URLSession

    init(
        baseURL: URL,
        authToken: String,
        actorID: String = "bash",
        actorCredential: String,
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
    ) throws -> AppAPIClient {
        let actorID = "bash"
        return try AppAPIClient(
            baseURL: AppRuntimeConfiguration.coreServiceURL(environment: environment),
            authToken: AppRuntimeConfiguration.loadOrCreateAuthToken(environment: environment),
            actorID: actorID,
            actorCredential: AppRuntimeConfiguration.loadOrCreateActorCredential(
                actorID: actorID,
                environment: environment
            ),
            session: session
        )
    }

    func fetchHealth() async throws -> AppHealth {
        try await decode(path: "health", method: "GET")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        try await decode(path: "inbox/\(actorID)", method: "GET")
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        try await decode(path: "recents", method: "GET")
    }

    func search(query: String) async throws -> [AppSearchResult] {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else {
            throw AppAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func fetchProjects() async throws -> [Project] {
        try await decode(path: "projects", method: "GET")
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        try await decode(path: "projects/\(projectID)/threads", method: "GET")
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        var components = URLComponents(url: baseURL.appending(path: "threads/\(threadID)/context"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "mode", value: mode)]
        guard let url = components?.url else {
            throw AppAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func fetchThreadMessages(threadID: String, limit: Int = 100, before: MessageCursor? = nil) async throws -> [Message] {
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
            throw AppAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func fetchMentions(actorID: String, limit: Int = 100) async throws -> [Message] {
        var components = URLComponents(
            url: baseURL.appending(path: "mentions/\(actorID)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else {
            throw AppAPIClientError.invalidResponse
        }
        return try await decode(url: url, method: "GET")
    }

    func postMessage(threadID: String, request: AppPostMessageRequest) async throws -> Message {
        guard request.actorID == actorID else {
            throw AppAPIClientError.actorIdentityMismatch(expected: actorID, received: request.actorID)
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

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        try await send(path: "handoffs", method: "POST", payload: request)
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        try await send(
            path: "handoffs/\(id)",
            method: "PUT",
            payload: AppUpdateHandoffRequest(status: status, resolution: resolution)
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
        let body = try makeEncoder().encode(payload)
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
            throw AppAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppAPIClientError.httpStatus(
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
