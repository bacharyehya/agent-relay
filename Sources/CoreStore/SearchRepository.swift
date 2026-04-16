import AppCore
import Foundation
import GRDB

public struct SearchResult: Equatable, Sendable {
    public var objectID: String
    public var objectType: String
    public var body: String

    public init(objectID: String, objectType: String, body: String) {
        self.objectID = objectID
        self.objectType = objectType
        self.body = body
    }
}

public struct SearchRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func index(message: Message) throws {
        try upsert(objectID: message.id, objectType: "message", body: message.body)
    }

    public func index(handoff: Handoff) throws {
        try upsert(
            objectID: handoff.id,
            objectType: "handoff",
            body: [handoff.title, handoff.summary, handoff.ask]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    public func search(_ query: String) throws -> [SearchResult] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT object_id, object_type, body
                FROM search_index
                WHERE search_index MATCH ?
                ORDER BY object_type, object_id
                """,
                arguments: [query]
            )

            return rows.map {
                SearchResult(
                    objectID: $0["object_id"],
                    objectType: $0["object_type"],
                    body: $0["body"]
                )
            }
        }
    }

    private func upsert(objectID: String, objectType: String, body: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM search_index
                WHERE object_id = ? AND object_type = ?
                """,
                arguments: [objectID, objectType]
            )
            try db.execute(
                sql: """
                INSERT INTO search_index (object_id, object_type, body)
                VALUES (?, ?, ?)
                """,
                arguments: [objectID, objectType, body]
            )
        }
    }
}
