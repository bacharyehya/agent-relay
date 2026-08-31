import AppCore
import Foundation

struct GetMessagesTool {
    let client: any CoreAPIClientProtocol

    func run(threadID: String, limit: Int = 100, before: MessageCursor? = nil) async throws -> String {
        let messages = try await client.getMessages(threadID: threadID, limit: limit, before: before)
        let page = MessagePageOutput(
            messages: messages,
            nextCursor: messages.first.map(MessageCursor.init(message:))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(page), as: UTF8.self)
    }
}

private struct MessagePageOutput: Encodable {
    let messages: [Message]
    let nextCursor: MessageCursor?
}

struct PostMessageTool {
    let client: any CoreAPIClientProtocol
    let actorID: String?

    func run(
        threadID: String,
        body: String,
        format: MessageFormat = .markdown,
        replyToMessageID: String? = nil,
        mentionedActorIDs: [String] = [],
        idempotencyKey: String,
        requestedActorID: String? = nil
    ) async throws -> String {
        guard let actorID, !actorID.isEmpty else {
            throw MessageToolError.missingBoundActorIdentity
        }
        if let requestedActorID, requestedActorID != actorID {
            throw MessageToolError.actorIdentityMismatch(expected: actorID, received: requestedActorID)
        }

        let message = try await client.postMessage(
            threadID: threadID,
            request: CreateMessagePayload(
                actorID: actorID,
                body: body,
                format: format,
                replyToMessageID: replyToMessageID,
                mentionedActorIDs: mentionedActorIDs,
                idempotencyKey: idempotencyKey
            )
        )
        return "Posted message \(message.id) as \(message.actorID)."
    }
}

enum MessageToolError: LocalizedError, Equatable {
    case missingBoundActorIdentity
    case actorIdentityMismatch(expected: String, received: String)

    var errorDescription: String? {
        switch self {
        case .missingBoundActorIdentity:
            return "AGENT_RELAY_ACTOR_ID must be set before post_message can be used"
        case let .actorIdentityMismatch(expected, received):
            return "post_message identity is bound to \(expected), not \(received)"
        }
    }
}
