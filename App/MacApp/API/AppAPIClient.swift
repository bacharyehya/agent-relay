import Foundation
import AppCore

enum AppAPIClientError: Error {
    case invalidResponse
    case httpStatus(Int, String)
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
    let messages: [Message]
    var handoffs: [Handoff]
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
    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff
    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff
}

struct AppAPIClient: AppAPIClientProtocol {
    let baseURL: URL
    let authToken: String
    let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        authToken: String = ProcessInfo.processInfo.environment["AGENT_RELAY_AUTH_TOKEN"] ?? "dev-token",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
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

    private func send<T: Decodable, Body: Encodable>(path: String, method: String, payload: Body) async throws -> T {
        let body = try makeEncoder().encode(payload)
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
}
