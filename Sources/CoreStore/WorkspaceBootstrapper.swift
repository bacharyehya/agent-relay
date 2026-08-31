import AppCore
import Foundation
import GRDB

public struct WorkspaceBootstrapper {
    public static let defaultProjectID = "project-agent-relay"
    public static let defaultThreadID = "thread-general"

    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Ensures the built-in room exists without changing or removing any user
    /// projects. This also upgrades databases created before Agent Relay had a
    /// default message room.
    @discardableResult
    public func ensureDefaultWorkspace(now: Date = .now) throws -> Bool {
        try dbQueue.write { db in
            var createdSomething = false

            if try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM projects WHERE id = ?",
                arguments: [Self.defaultProjectID]
            ) == 0 {
                try db.execute(
                    sql: """
                    INSERT INTO projects (id, title, summary, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        Self.defaultProjectID,
                        "Agent Relay",
                        "Local agent collaboration workspace",
                        ProjectStatus.active.rawValue,
                        now,
                        now,
                    ]
                )
                createdSomething = true
            }

            if let existingProjectID = try String.fetchOne(
                db,
                sql: "SELECT project_id FROM threads WHERE id = ?",
                arguments: [Self.defaultThreadID]
            ) {
                guard existingProjectID == Self.defaultProjectID else {
                    throw DatabaseError(message: "thread-general belongs to another project")
                }
            } else {
                let assignedActorIDs = String(
                    decoding: try JSONEncoder().encode(["codex-main", "codex-research"]),
                    as: UTF8.self
                )
                try db.execute(
                    sql: """
                    INSERT INTO threads (
                        id, project_id, title, intent_type, status,
                        created_by, assigned_actor_ids, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        Self.defaultThreadID,
                        Self.defaultProjectID,
                        "General",
                        ThreadIntentType.task.rawValue,
                        ThreadStatus.active.rawValue,
                        "bash",
                        assignedActorIDs,
                        now,
                    ]
                )
                createdSomething = true
            }

            return createdSomething
        }
    }

    @discardableResult
    public func seedDefaultWorkspaceIfEmpty(now: Date = .now) throws -> Bool {
        try ensureDefaultWorkspace(now: now)
    }
}
