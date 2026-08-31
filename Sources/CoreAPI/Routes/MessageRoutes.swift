import AppCore
import CoreStore
import Foundation
import Hummingbird
import HTTPTypes

struct CreateMessageRequest: Codable {
    let actorID: String?
    let body: String
    let format: MessageFormat?
    let replyToMessageID: String?
    let mentionedActorIDs: [String]?

    init(
        actorID: String? = nil,
        body: String,
        format: MessageFormat? = nil,
        replyToMessageID: String? = nil,
        mentionedActorIDs: [String]? = nil
    ) {
        self.actorID = actorID
        self.body = body
        self.format = format
        self.replyToMessageID = replyToMessageID
        self.mentionedActorIDs = mentionedActorIDs
    }
}

public enum MessageRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        environment: AppEnvironment
    ) {
        router.get("threads/:threadID/messages") { request, context -> [Message] in
            try environment.requireAuthorization(for: request)
            let threadID = try context.parameters.require("threadID")
            guard try environment.threadRepository.get(id: threadID) != nil else {
                throw HTTPError(.notFound, message: "Thread not found")
            }

            let limit = try parseLimit(request.uri.queryParameters["limit"].map(String.init))
            let before = try parseCursor(
                createdAt: request.uri.queryParameters["before_created_at"].map(String.init),
                messageID: request.uri.queryParameters["before_message_id"].map(String.init)
            )
            return try environment.messageRepository.list(
                threadID: threadID,
                limit: limit,
                before: before
            )
        }

        router.post("threads/:threadID/messages") { request, context -> Message in
            try environment.requireAuthorization(for: request)
            let actorID = try environment.requireActorIdentity(for: request)
            let threadID = try context.parameters.require("threadID")
            guard let thread = try environment.threadRepository.get(id: threadID) else {
                throw HTTPError(.notFound, message: "Thread not found")
            }
            guard let payload = try? await request.decode(as: CreateMessageRequest.self, context: context) else {
                throw HTTPError(.badRequest, message: "Invalid message payload")
            }

            let body = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                throw HTTPError(.badRequest, message: "body is required")
            }
            if let claimedActorID = payload.actorID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !claimedActorID.isEmpty,
               claimedActorID != actorID
            {
                throw HTTPError(.forbidden, message: "Message actor does not match the authenticated actor")
            }

            let idempotencyHeader = HTTPField.Name("Idempotency-Key")!
            guard let rawIdempotencyKey = request.headers[idempotencyHeader] else {
                throw HTTPError(.badRequest, message: "Idempotency-Key is required")
            }
            let idempotencyKey = rawIdempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...200).contains(idempotencyKey.count) else {
                throw HTTPError(.badRequest, message: "Idempotency-Key must be between 1 and 200 characters")
            }

            var seenActorIDs = Set<String>()
            let mentionedActorIDs = (payload.mentionedActorIDs ?? []).compactMap { rawValue -> String? in
                let actorID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !actorID.isEmpty, seenActorIDs.insert(actorID).inserted else {
                    return nil
                }
                return actorID
            }

            let timestamp = Date()
            let message = Message(
                id: UUID().uuidString.lowercased(),
                threadID: threadID,
                actorID: actorID,
                body: body,
                format: payload.format ?? .markdown,
                replyToMessageID: payload.replyToMessageID,
                mentionedActorIDs: mentionedActorIDs,
                createdAt: timestamp
            )

            let creationResult: MessageCreationResult
            do {
                creationResult = try environment.messageRepository.createIdempotently(
                    message,
                    idempotencyKey: idempotencyKey
                )
            } catch MessageRepositoryError.replyMessageNotFound(_) {
                throw HTTPError(.badRequest, message: "Reply target was not found")
            } catch MessageRepositoryError.replyMessageThreadMismatch(_) {
                throw HTTPError(.badRequest, message: "Reply target belongs to another thread")
            } catch MessageRepositoryError.idempotencyKeyConflict(_) {
                throw HTTPError(.conflict, message: "Idempotency-Key was already used for a different message")
            }

            // These derived side effects are deliberately repaired on a
            // successful retry if a prior request committed the message but
            // stopped before indexing or event delivery.
            try environment.searchRepository.index(message: creationResult.message)
            let event = Event(
                id: "message-added:\(creationResult.message.id)",
                type: .messageAdded,
                projectID: thread.projectID,
                threadID: thread.id,
                actorID: creationResult.message.actorID,
                body: "\(creationResult.message.actorID): \(creationResult.message.body)",
                createdAt: creationResult.message.createdAt
            )
            let insertedEvent = try environment.eventRepository.recordIfAbsent(event)
            if insertedEvent {
                await environment.eventStream.publish(event)
            }
            return creationResult.message
        }
    }

    private static func parseLimit(_ rawValue: String?) throws -> Int {
        guard let rawValue else { return 100 }
        guard let limit = Int(rawValue), (1...200).contains(limit) else {
            throw HTTPError(.badRequest, message: "limit must be between 1 and 200")
        }
        return limit
    }

    private static func parseCursor(createdAt: String?, messageID: String?) throws -> MessageCursor? {
        guard createdAt != nil || messageID != nil else { return nil }
        guard let createdAt, let messageID, !messageID.isEmpty else {
            throw HTTPError(
                .badRequest,
                message: "before_created_at and before_message_id must be supplied together"
            )
        }

        guard let date = PreciseDateCodec.date(from: createdAt) else {
            throw HTTPError(.badRequest, message: "before_created_at must be an ISO-8601 timestamp")
        }
        return MessageCursor(createdAt: date, messageID: messageID)
    }
}
