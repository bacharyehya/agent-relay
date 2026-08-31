import AppCore
import Foundation

enum RelayCoreAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Agent Relay Core returned an invalid response."
        case let .httpStatus(status, body):
            "Agent Relay Core returned HTTP \(status): \(body)"
        }
    }
}

struct RelayPostMessageRequest: Codable, Equatable, Sendable {
    let actorID: String
    let body: String
    let format: MessageFormat
    let replyToMessageID: String?
    let mentionedActorIDs: [String]
}

protocol RelayCoreAPIClientProtocol: Sendable {
    func getMessages(
        threadID: String,
        limit: Int,
        before: MessageCursor?
    ) async throws -> [Message]
    func postMessage(
        threadID: String,
        request: RelayPostMessageRequest,
        idempotencyKey: String
    ) async throws -> Message
}

struct RelayCoreAPIClient: RelayCoreAPIClientProtocol {
    let baseURL: URL
    let authToken: String
    let actorID: String
    let actorCredential: String
    let session: URLSession

    init(
        baseURL: URL,
        authToken: String,
        actorID: String,
        actorCredential: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.actorID = actorID
        self.actorCredential = actorCredential
        self.session = session
    }

    func getMessages(
        threadID: String,
        limit: Int = 100,
        before: MessageCursor? = nil
    ) async throws -> [Message] {
        var components = URLComponents(
            url: baseURL.appending(path: "threads/\(threadID)/messages"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            queryItems.append(
                URLQueryItem(
                    name: "before_created_at",
                    value: Self.iso8601String(from: before.createdAt)
                )
            )
            queryItems.append(
                URLQueryItem(name: "before_message_id", value: before.messageID)
            )
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw RelayCoreAPIError.invalidResponse
        }
        let data = try await perform(url: url, method: "GET", body: nil, idempotencyKey: nil)
        return try Self.makeDecoder().decode([Message].self, from: data)
    }

    func postMessage(
        threadID: String,
        request: RelayPostMessageRequest,
        idempotencyKey: String
    ) async throws -> Message {
        let body = try Self.makeEncoder().encode(request)
        let data = try await perform(
            url: baseURL.appending(path: "threads/\(threadID)/messages"),
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
        return try Self.makeDecoder().decode(Message.self, from: data)
    }

    private func perform(
        url: URL,
        method: String,
        body: Data?,
        idempotencyKey: String?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.setValue(actorID, forHTTPHeaderField: ActorCredential.actorHeader)
            request.setValue(actorCredential, forHTTPHeaderField: ActorCredential.credentialHeader)
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RelayCoreAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw RelayCoreAPIError.httpStatus(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func iso8601String(from date: Date) -> String {
        PreciseDateCodec.string(from: date)
    }
}
