import AppCore
import Foundation
import GRDB

public struct HandoffRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func create(_ handoff: Handoff) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO handoffs (
                    id, thread_id, title, summary, ask, status,
                    priority, created_by, assigned_to, source_refs, resolution
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    handoff.id,
                    handoff.threadID,
                    handoff.title,
                    handoff.summary,
                    handoff.ask,
                    handoff.status.rawValue,
                    handoff.priority.rawValue,
                    handoff.createdBy,
                    handoff.assignedTo,
                    try Self.encodeSourceRefs(handoff.sourceRefs),
                    handoff.resolution,
                ]
            )
        }
    }

    public func list(threadID: String) throws -> [Handoff] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, thread_id, title, summary, ask, status,
                       priority, created_by, assigned_to, source_refs, resolution
                FROM handoffs
                WHERE thread_id = ?
                ORDER BY rowid ASC
                """,
                arguments: [threadID]
            )

            return try rows.map(Self.handoff(from:))
        }
    }

    public func get(id: String) throws -> Handoff? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT id, thread_id, title, summary, ask, status,
                       priority, created_by, assigned_to, source_refs, resolution
                FROM handoffs
                WHERE id = ?
                """,
                arguments: [id]
            ).map(Self.handoff(from:))
        }
    }

    public func update(_ handoff: Handoff) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE handoffs
                SET title = ?,
                    summary = ?,
                    ask = ?,
                    status = ?,
                    priority = ?,
                    created_by = ?,
                    assigned_to = ?,
                    source_refs = ?,
                    resolution = ?
                WHERE id = ?
                """,
                arguments: [
                    handoff.title,
                    handoff.summary,
                    handoff.ask,
                    handoff.status.rawValue,
                    handoff.priority.rawValue,
                    handoff.createdBy,
                    handoff.assignedTo,
                    try Self.encodeSourceRefs(handoff.sourceRefs),
                    handoff.resolution,
                    handoff.id,
                ]
            )
        }
    }

    static func handoff(from row: Row) throws -> Handoff {
        Handoff(
            id: row["id"],
            threadID: row["thread_id"],
            title: row["title"],
            summary: row["summary"],
            ask: row["ask"],
            status: HandoffStatus(rawValue: row["status"]) ?? .open,
            priority: HandoffPriority(rawValue: row["priority"]) ?? .medium,
            createdBy: row["created_by"],
            assignedTo: row["assigned_to"],
            sourceRefs: try decodeSourceRefs(row["source_refs"]),
            resolution: row["resolution"]
        )
    }

    static func encodeSourceRefs(_ sourceRefs: [String]) throws -> String {
        let data = try JSONEncoder().encode(sourceRefs)
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeSourceRefs(_ rawValue: String) throws -> [String] {
        let data = Data(rawValue.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }
}
