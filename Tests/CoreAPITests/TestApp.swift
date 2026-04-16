import AppCore
@testable import CoreAPI
import CoreStore
import Foundation
import Hummingbird

enum TestApp {
    static let token = "test-token"

    static func make() throws -> Application<RouterResponder<BasicRequestContext>> {
        let databaseQueue = try AppDatabase.makeInMemoryDatabase()
        let timestamp = Date(timeIntervalSince1970: 1_700_001_000)
        let project = Project(
            id: "project-api",
            title: "Shield",
            summary: "API fixture",
            status: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let thread = AppCore.Thread(
            id: "thread-api",
            projectID: project.id,
            title: "Webhook auth",
            intentType: .bug,
            status: .active,
            createdBy: "human",
            assignedActorIDs: ["chatgpt"],
            updatedAt: timestamp
        )
        let firstMessage = Message(
            id: "message-api-1",
            threadID: thread.id,
            actorID: "human",
            body: "Webhook auth failed after rotation.",
            format: .markdown,
            createdAt: timestamp
        )
        let secondMessage = Message(
            id: "message-api-2",
            threadID: thread.id,
            actorID: "chatgpt",
            body: "Investigating token scope mismatch.",
            format: .markdown,
            createdAt: timestamp.addingTimeInterval(30)
        )
        let openHandoff = Handoff(
            id: "handoff-api-open",
            threadID: thread.id,
            title: "Fix webhook auth",
            summary: "Find the token issue",
            ask: "Identify the minimal fix.",
            status: .open,
            priority: .high,
            createdBy: "human",
            assignedTo: "chatgpt",
            sourceRefs: [firstMessage.id]
        )
        let blockedHandoff = Handoff(
            id: "handoff-api-blocked",
            threadID: thread.id,
            title: "Confirm missing scope",
            summary: "Need auth scope check",
            ask: "Verify the missing scope.",
            status: .blocked,
            priority: .medium,
            createdBy: "human",
            assignedTo: "chatgpt",
            sourceRefs: [secondMessage.id]
        )

        try ProjectRepository(databaseQueue).create(project)
        try ThreadRepository(databaseQueue).create(thread)
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO messages (id, thread_id, actor_id, body, format, created_at)
                VALUES (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    firstMessage.id,
                    firstMessage.threadID,
                    firstMessage.actorID,
                    firstMessage.body,
                    firstMessage.format.rawValue,
                    firstMessage.createdAt,
                    secondMessage.id,
                    secondMessage.threadID,
                    secondMessage.actorID,
                    secondMessage.body,
                    secondMessage.format.rawValue,
                    secondMessage.createdAt,
                ]
            )
        }
        try HandoffRepository(databaseQueue).create(openHandoff)
        try HandoffRepository(databaseQueue).create(blockedHandoff)
        try EventRepository(databaseQueue).record(
            Event(
                id: "event-api-1",
                type: .handoffCreated,
                projectID: project.id,
                threadID: thread.id,
                handoffID: openHandoff.id,
                actorID: "human",
                body: "Created open handoff",
                createdAt: timestamp
            )
        )
        try EventRepository(databaseQueue).record(
            Event(
                id: "event-api-2",
                type: .handoffBlocked,
                projectID: project.id,
                threadID: thread.id,
                handoffID: blockedHandoff.id,
                actorID: "chatgpt",
                body: "Blocked handoff pending scope",
                createdAt: timestamp.addingTimeInterval(30)
            )
        )

        let environment = AppEnvironment(
            projectRepository: ProjectRepository(databaseQueue),
            threadRepository: ThreadRepository(databaseQueue),
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            inboxRepository: InboxRepository(databaseQueue),
            notificationRepository: NotificationRepository(databaseQueue),
            authToken: AuthToken(token)
        )
        return CoreAPIApp.makeApplication(environment: environment)
    }

    static var authorizedHeaders: HTTPFields {
        [.authorization: "Bearer \(token)"]
    }
}
