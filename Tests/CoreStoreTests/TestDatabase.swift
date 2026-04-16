import AppCore
import Foundation
import GRDB
@testable import CoreStore

enum TestDatabase {
    static func make() throws -> DatabaseQueue {
        try AppDatabase.makeInMemoryDatabase()
    }

    static func seeded() throws -> DatabaseQueue {
        let db = try make()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let project = Project(
            id: "project-search",
            title: "Shield",
            summary: "Search fixture",
            status: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let thread = AppCore.Thread(
            id: "thread-search",
            projectID: project.id,
            title: "Webhook auth investigation",
            intentType: .bug,
            status: .active,
            createdBy: "human",
            assignedActorIDs: ["chatgpt"],
            updatedAt: timestamp
        )
        let message = Message(
            id: "message-search",
            threadID: thread.id,
            actorID: "human",
            body: "The webhook auth token fails after rotation.",
            format: .markdown,
            createdAt: timestamp
        )
        let handoff = Handoff(
            id: "handoff-search",
            threadID: thread.id,
            title: "Fix webhook auth",
            summary: "Track down the auth mismatch",
            ask: "Identify why webhook auth fails after token rotation.",
            status: .open,
            priority: .high,
            createdBy: "human",
            assignedTo: "chatgpt",
            sourceRefs: [message.id]
        )

        try ProjectRepository(db).create(project)
        try ThreadRepository(db).create(thread)
        try db.write { database in
            try database.execute(
                sql: """
                INSERT INTO messages (id, thread_id, actor_id, body, format, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id,
                    message.threadID,
                    message.actorID,
                    message.body,
                    message.format.rawValue,
                    message.createdAt,
                ]
            )
        }
        try HandoffRepository(db).create(handoff)

        let searchRepository = SearchRepository(db)
        try searchRepository.index(message: message)
        try searchRepository.index(handoff: handoff)
        try EventRepository(db).record(
            Event(
                id: "event-search",
                type: .handoffCreated,
                projectID: project.id,
                threadID: thread.id,
                handoffID: handoff.id,
                actorID: "human",
                body: "Created search fixture handoff",
                createdAt: timestamp
            )
        )

        return db
    }
}

extension DatabaseQueue {
    func tableNames() throws -> [String] {
        try read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                ORDER BY name
                """
            )
        }
    }
}
