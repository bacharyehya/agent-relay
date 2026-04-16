import Foundation
import AppCore

struct AppHealth: Codable, Equatable, Sendable {
    let status: String
}

struct AppThreadContext: Codable, Equatable, Sendable {
    let thread: AppCore.Thread
    let messages: [Message]
    let handoffs: [Handoff]
}

protocol AppAPIClientProtocol: Sendable {
    func fetchHealth() async throws -> AppHealth
    func fetchProjects() async throws -> [Project]
    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread]
    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext
}

struct AppAPIClient: AppAPIClientProtocol {
    let baseURL: URL
    let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchHealth() async throws -> AppHealth {
        let (data, response) = try await session.data(from: baseURL.appending(path: "health"))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AppHealth.self, from: data)
    }

    func fetchProjects() async throws -> [Project] {
        try await decode(path: "projects")
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        try await decode(path: "projects/\(projectID)/threads")
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        var components = URLComponents(url: baseURL.appending(path: "threads/\(threadID)/context"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "mode", value: mode)]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        return try await decode(url: url)
    }

    private func decode<T: Decodable>(path: String) async throws -> T {
        try await decode(url: baseURL.appending(path: path))
    }

    private func decode<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
