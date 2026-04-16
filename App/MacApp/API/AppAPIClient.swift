import Foundation

struct AppHealth: Codable, Equatable, Sendable {
    let status: String
}

protocol AppAPIClientProtocol: Sendable {
    func fetchHealth() async throws -> AppHealth
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
}
