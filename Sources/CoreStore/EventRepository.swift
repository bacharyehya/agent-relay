import AppCore
import Foundation
import GRDB

public struct EventRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func record(_ event: Event) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO events (
                    id, type, project_id, thread_id, handoff_id,
                    actor_id, body, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id,
                    event.type.rawValue,
                    event.projectID,
                    event.threadID,
                    event.handoffID,
                    event.actorID,
                    event.body,
                    event.createdAt,
                ]
            )
        }
    }

    public func list(limit: Int = 50) throws -> [Event] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, type, project_id, thread_id, handoff_id,
                       actor_id, body, created_at
                FROM events
                ORDER BY created_at ASC
                LIMIT ?
                """,
                arguments: [limit]
            )

            return rows.map {
                Event(
                    id: $0["id"],
                    type: EventType(rawValue: $0["type"]) ?? .messageAdded,
                    projectID: $0["project_id"],
                    threadID: $0["thread_id"],
                    handoffID: $0["handoff_id"],
                    actorID: $0["actor_id"],
                    body: $0["body"],
                    createdAt: $0["created_at"]
                )
            }
        }
    }
}
