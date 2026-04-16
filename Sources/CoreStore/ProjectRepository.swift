import AppCore
import Foundation
import GRDB

public struct ProjectRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func create(_ project: Project) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO projects (id, title, summary, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    project.id,
                    project.title,
                    project.summary,
                    project.status.rawValue,
                    project.createdAt,
                    project.updatedAt,
                ]
            )
        }
    }

    public func list() throws -> [Project] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, title, summary, status, created_at, updated_at
                FROM projects
                ORDER BY updated_at DESC
                """
            )

            return rows.map(Self.project(from:))
        }
    }

    public func get(id: String) throws -> Project? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT id, title, summary, status, created_at, updated_at
                FROM projects
                WHERE id = ?
                """,
                arguments: [id]
            ).map(Self.project(from:))
        }
    }

    private static func project(from row: Row) -> Project {
        Project(
            id: row["id"],
            title: row["title"],
            summary: row["summary"],
            status: ProjectStatus(rawValue: row["status"]) ?? .active,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
