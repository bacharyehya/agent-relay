import AppCore
import Foundation
import GRDB

public enum MessageRepositoryError: Error, Equatable, Sendable {
    case replyMessageNotFound(String)
    case replyMessageThreadMismatch(String)
    case idempotencyKeyConflict(String)
}

public struct MessageCreationResult: Equatable, Sendable {
    public let message: Message
    public let wasCreated: Bool

    public init(message: Message, wasCreated: Bool) {
        self.message = message
        self.wasCreated = wasCreated
    }
}

public struct MessageRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func create(_ message: Message) throws {
        _ = try createIdempotently(message, idempotencyKey: nil)
    }

    /// Creates a message once for a thread/actor/idempotency-key tuple. A
    /// retry with the same payload returns the original message; reusing the
    /// key for a different payload is rejected.
    public func createIdempotently(
        _ message: Message,
        idempotencyKey: String
    ) throws -> MessageCreationResult {
        try createIdempotently(message, idempotencyKey: Optional(idempotencyKey))
    }

    private func createIdempotently(
        _ message: Message,
        idempotencyKey: String?
    ) throws -> MessageCreationResult {
        try dbQueue.write { db in
            if let idempotencyKey,
               let existingRow = try Row.fetchOne(
                   db,
                   sql: """
                   SELECT id, thread_id, actor_id, body, format,
                          reply_to_message_id, mentioned_actor_ids, created_at
                   FROM messages
                   WHERE thread_id = ? AND actor_id = ? AND client_idempotency_key = ?
                   """,
                   arguments: [message.threadID, message.actorID, idempotencyKey]
               )
            {
                let existing = try Self.message(from: existingRow)
                guard Self.sameClientPayload(existing, message) else {
                    throw MessageRepositoryError.idempotencyKeyConflict(idempotencyKey)
                }
                return MessageCreationResult(message: existing, wasCreated: false)
            }

            if let replyToMessageID = message.replyToMessageID {
                guard let replyThreadID = try String.fetchOne(
                    db,
                    sql: "SELECT thread_id FROM messages WHERE id = ?",
                    arguments: [replyToMessageID]
                ) else {
                    throw MessageRepositoryError.replyMessageNotFound(replyToMessageID)
                }
                guard replyThreadID == message.threadID else {
                    throw MessageRepositoryError.replyMessageThreadMismatch(replyToMessageID)
                }
            }

            try db.execute(
                sql: """
                INSERT INTO messages (
                    id, thread_id, actor_id, body, format,
                    reply_to_message_id, mentioned_actor_ids, created_at,
                    client_idempotency_key
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id,
                    message.threadID,
                    message.actorID,
                    message.body,
                    message.format.rawValue,
                    message.replyToMessageID,
                    try Self.encodeIDs(message.mentionedActorIDs),
                    message.createdAt,
                    idempotencyKey,
                ]
            )

            try db.execute(
                sql: "UPDATE threads SET updated_at = ? WHERE id = ?",
                arguments: [message.createdAt, message.threadID]
            )

            // Re-read so the response, future cursors, and idempotent retries
            // all use SQLite/GRDB's canonical stored timestamp precision.
            guard let storedRow = try Row.fetchOne(
                db,
                sql: """
                SELECT id, thread_id, actor_id, body, format,
                       reply_to_message_id, mentioned_actor_ids, created_at
                FROM messages
                WHERE id = ?
                """,
                arguments: [message.id]
            ) else {
                preconditionFailure("Inserted message could not be read back")
            }
            return MessageCreationResult(
                message: try Self.message(from: storedRow),
                wasCreated: true
            )
        }
    }

    public func get(id: String) throws -> Message? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT id, thread_id, actor_id, body, format,
                       reply_to_message_id, mentioned_actor_ids, created_at
                FROM messages
                WHERE id = ?
                """,
                arguments: [id]
            ).map(Self.message(from:))
        }
    }

    /// Returns a bounded page in chronological display order. `before` is an
    /// exclusive `(createdAt, messageID)` cursor, so equal timestamps page
    /// without gaps or duplicates.
    public func list(
        threadID: String,
        limit: Int = 100,
        before: MessageCursor? = nil
    ) throws -> [Message] {
        let boundedLimit = min(max(limit, 1), 200)

        return try dbQueue.read { db in
            let rows: [Row]
            if let before {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, thread_id, actor_id, body, format,
                           reply_to_message_id, mentioned_actor_ids, created_at
                    FROM messages
                    WHERE thread_id = ?
                      AND (created_at < ? OR (created_at = ? AND id < ?))
                    ORDER BY created_at DESC, id DESC
                    LIMIT ?
                    """,
                    arguments: [
                        threadID,
                        before.createdAt,
                        before.createdAt,
                        before.messageID,
                        boundedLimit,
                    ]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, thread_id, actor_id, body, format,
                           reply_to_message_id, mentioned_actor_ids, created_at
                    FROM messages
                    WHERE thread_id = ?
                    ORDER BY created_at DESC, id DESC
                    LIMIT ?
                    """,
                    arguments: [threadID, boundedLimit]
                )
            }

            return try rows.reversed().map(Self.message(from:))
        }
    }

    /// Returns the newest direct chat mentions for an actor across all rooms.
    /// Formal handoffs intentionally remain a separate inbox concept.
    public func listMentions(actorID: String, limit: Int = 100) throws -> [Message] {
        let boundedLimit = min(max(limit, 1), 200)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT messages.id, messages.thread_id, messages.actor_id,
                       messages.body, messages.format,
                       messages.reply_to_message_id,
                       messages.mentioned_actor_ids,
                       messages.created_at
                FROM messages, json_each(messages.mentioned_actor_ids) AS mention
                WHERE mention.value = ?
                ORDER BY messages.created_at DESC, messages.id DESC
                LIMIT ?
                """,
                arguments: [actorID, boundedLimit]
            )
            return try rows.map(Self.message(from:))
        }
    }

    static func message(from row: Row) throws -> Message {
        Message(
            id: row["id"],
            threadID: row["thread_id"],
            actorID: row["actor_id"],
            body: row["body"],
            format: MessageFormat(rawValue: row["format"]) ?? .markdown,
            replyToMessageID: row["reply_to_message_id"],
            mentionedActorIDs: try decodeIDs(row["mentioned_actor_ids"]),
            createdAt: row["created_at"]
        )
    }

    private static func encodeIDs(_ ids: [String]) throws -> String {
        let data = try JSONEncoder().encode(ids)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeIDs(_ rawValue: String) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(rawValue.utf8))
    }

    private static func sameClientPayload(_ lhs: Message, _ rhs: Message) -> Bool {
        lhs.threadID == rhs.threadID
            && lhs.actorID == rhs.actorID
            && lhs.body == rhs.body
            && lhs.format == rhs.format
            && lhs.replyToMessageID == rhs.replyToMessageID
            && lhs.mentionedActorIDs == rhs.mentionedActorIDs
    }
}
