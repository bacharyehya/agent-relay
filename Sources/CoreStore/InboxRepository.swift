import AppCore
import Foundation
import GRDB

public enum ThreadContextMode: String, Codable, Sendable {
    case recent
    case recentAndReferenced
    case handoffFocused
}

public struct RecentItem: Codable, Equatable, Sendable {
    public var eventID: String
    public var type: EventType
    public var threadID: String?
    public var handoffID: String?
    public var body: String
    public var createdAt: Date

    public init(
        eventID: String,
        type: EventType,
        threadID: String?,
        handoffID: String?,
        body: String,
        createdAt: Date
    ) {
        self.eventID = eventID
        self.type = type
        self.threadID = threadID
        self.handoffID = handoffID
        self.body = body
        self.createdAt = createdAt
    }
}

public struct ThreadContext: Codable, Equatable, Sendable {
    public var thread: AppCore.Thread
    public var messages: [Message]
    public var handoffs: [Handoff]

    public init(thread: AppCore.Thread, messages: [Message], handoffs: [Handoff]) {
        self.thread = thread
        self.messages = messages
        self.handoffs = handoffs
    }
}

public enum InboxRepositoryError: Error, Equatable, Sendable {
    case threadNotFound(String)
}

public struct InboxRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func inbox(for actorID: String) throws -> [Handoff] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, thread_id, title, summary, ask, status,
                       priority, created_by, assigned_to, source_refs, resolution
                FROM handoffs
                WHERE assigned_to = ?
                  AND status IN ('open', 'blocked')
                ORDER BY CASE status
                    WHEN 'open' THEN 0
                    WHEN 'blocked' THEN 1
                    ELSE 2
                END, rowid ASC
                """,
                arguments: [actorID]
            )

            return try rows.map(HandoffRepository.handoff(from:))
        }
    }

    public func recents(limit: Int = 20) throws -> [RecentItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, type, thread_id, handoff_id, body, created_at
                FROM events
                ORDER BY created_at DESC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map {
                RecentItem(
                    eventID: $0["id"],
                    type: EventType(rawValue: $0["type"]) ?? .messageAdded,
                    threadID: $0["thread_id"],
                    handoffID: $0["handoff_id"],
                    body: $0["body"],
                    createdAt: $0["created_at"]
                )
            }
        }
    }

    public func threadContext(
        threadID: String,
        mode: ThreadContextMode
    ) throws -> ThreadContext {
        try dbQueue.read { db in
            guard let threadRow = try Row.fetchOne(
                db,
                sql: """
                SELECT id, project_id, title, intent_type, status,
                       created_by, assigned_actor_ids, updated_at
                FROM threads
                WHERE id = ?
                """,
                arguments: [threadID]
            ) else {
                throw InboxRepositoryError.threadNotFound(threadID)
            }

            let messageLimit: Int = switch mode {
            case .handoffFocused:
                3
            case .recent, .recentAndReferenced:
                10
            }

            let messageRows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, thread_id, actor_id, body, format, created_at
                FROM messages
                WHERE thread_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                arguments: [threadID, messageLimit]
            )

            var messages = messageRows.map(Self.message(from:))
            messages.reverse()

            let handoffRows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, thread_id, title, summary, ask, status,
                       priority, created_by, assigned_to, source_refs, resolution
                FROM handoffs
                WHERE thread_id = ?
                ORDER BY CASE status
                    WHEN 'open' THEN 0
                    WHEN 'blocked' THEN 1
                    WHEN 'accepted' THEN 2
                    WHEN 'responded' THEN 3
                    WHEN 'resolved' THEN 4
                    ELSE 5
                END, rowid ASC
                """,
                arguments: [threadID]
            )

            return ThreadContext(
                thread: try ThreadRepository.thread(from: threadRow),
                messages: messages,
                handoffs: try handoffRows.map(HandoffRepository.handoff(from:))
            )
        }
    }

    private static func message(from row: Row) -> Message {
        Message(
            id: row["id"],
            threadID: row["thread_id"],
            actorID: row["actor_id"],
            body: row["body"],
            format: MessageFormat(rawValue: row["format"]) ?? .markdown,
            createdAt: row["created_at"]
        )
    }
}
