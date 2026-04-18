import AppCore
import Foundation

enum CoreAPIClientError: Error {
    case invalidResponse
    case httpStatus(Int, String)
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

private struct UpdateHandoffPayload: Codable, Sendable {
    let status: HandoffStatus
    let resolution: String?
}

protocol CoreAPIClientProtocol: Sendable {
    func listInbox(actorID: String) async throws -> [Handoff]
    func listRecents() async throws -> [RecentItemPayload]
    func getThread(threadID: String, mode: String) async throws -> ThreadContextPayload
    func createHandoff(_ request: CreateHandoffPayload) async throws -> Handoff
    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff
}

struct CoreAPIClient: CoreAPIClientProtocol {
    let baseURL: URL
    let authToken: String
    let session: URLSession

    init(baseURL: URL, authToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) throws -> CoreAPIClient {
        try CoreAPIClient(
            baseURL: AppRuntimeConfiguration.coreServiceURL(environment: environment),
            authToken: AppRuntimeConfiguration.loadOrCreateAuthToken(environment: environment),
            session: session
        )
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

    private func send<T: Decodable, Body: Encodable>(path: String, method: String, payload: Body) async throws -> T {
        let encoder = makeEncoder()
        let body = try encoder.encode(payload)
        let data = try await perform(url: baseURL.appending(path: path), method: method, body: body)
        return try makeDecoder().decode(T.self, from: data)
    }

    private func perform(url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
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
}
