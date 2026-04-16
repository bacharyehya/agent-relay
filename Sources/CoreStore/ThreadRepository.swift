import AppCore
import Foundation
import GRDB

public struct ThreadRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func create(_ thread: AppCore.Thread) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO threads (
                    id, project_id, title, intent_type, status,
                    created_by, assigned_actor_ids, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    thread.id,
                    thread.projectID,
                    thread.title,
                    thread.intentType.rawValue,
                    thread.status.rawValue,
                    thread.createdBy,
                    try Self.encodeIDs(thread.assignedActorIDs),
                    thread.updatedAt,
                ]
            )
        }
    }

    public func list(projectID: String) throws -> [AppCore.Thread] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, project_id, title, intent_type, status,
                       created_by, assigned_actor_ids, updated_at
                FROM threads
                WHERE project_id = ?
                ORDER BY updated_at DESC
                """,
                arguments: [projectID]
            )

            return try rows.map(Self.thread(from:))
        }
    }

    public func get(id: String) throws -> AppCore.Thread? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT id, project_id, title, intent_type, status,
                       created_by, assigned_actor_ids, updated_at
                FROM threads
                WHERE id = ?
                """,
                arguments: [id]
            ).map(Self.thread(from:))
        }
    }

    private static func thread(from row: Row) throws -> AppCore.Thread {
        AppCore.Thread(
            id: row["id"],
            projectID: row["project_id"],
            title: row["title"],
            intentType: ThreadIntentType(rawValue: row["intent_type"]) ?? .task,
            status: ThreadStatus(rawValue: row["status"]) ?? .active,
            createdBy: row["created_by"],
            assignedActorIDs: try decodeIDs(row["assigned_actor_ids"]),
            updatedAt: row["updated_at"]
        )
    }

    private static func encodeIDs(_ ids: [String]) throws -> String {
        let data = try JSONEncoder().encode(ids)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeIDs(_ rawValue: String) throws -> [String] {
        let data = Data(rawValue.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }
}
