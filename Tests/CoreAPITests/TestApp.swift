import AppCore
@testable import CoreAPI
import CoreStore
import Foundation
import Hummingbird
import HTTPTypes

enum TestApp {
    static let token = "test-token"
    static let actorCredentialStore: ActorCredentialStore = {
        let supportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "agent-relay-core-api-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        return try! ActorCredentialStore(supportDirectory: supportDirectory)
    }()
    static let bashCredential = try! actorCredentialStore.loadOrCreate(actorID: "bash")

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
        let preciseSharedTimestamp = timestamp.addingTimeInterval(60.123456789)
        let sameTimestampMessages = ["message-api-same-a", "message-api-same-b", "message-api-same-c"].map {
            Message(
                id: $0,
                threadID: thread.id,
                actorID: "bash",
                body: $0,
                format: .markdown,
                createdAt: preciseSharedTimestamp
            )
        }
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
        let messageRepository = MessageRepository(databaseQueue)
        try messageRepository.create(firstMessage)
        try messageRepository.create(secondMessage)
        for message in sameTimestampMessages {
            try messageRepository.create(message)
        }
        try HandoffRepository(databaseQueue).create(openHandoff)
        try HandoffRepository(databaseQueue).create(blockedHandoff)
        let searchRepository = SearchRepository(databaseQueue)
        try searchRepository.index(message: firstMessage)
        try searchRepository.index(message: secondMessage)
        for message in sameTimestampMessages {
            try searchRepository.index(message: message)
        }
        try searchRepository.index(handoff: openHandoff)
        try searchRepository.index(handoff: blockedHandoff)
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
            messageRepository: messageRepository,
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            inboxRepository: InboxRepository(databaseQueue),
            notificationRepository: NotificationRepository(databaseQueue),
            searchRepository: searchRepository,
            authToken: AuthToken(token),
            actorCredentialStore: Self.actorCredentialStore
        )
        return CoreAPIApp.makeApplication(environment: environment)
    }

    static var authorizedHeaders: HTTPFields {
        [.authorization: "Bearer \(token)"]
    }

    static func actorHeaders(
        actorID: String = "bash",
        idempotencyKey: String = UUID().uuidString
    ) -> HTTPFields {
        var headers = authorizedHeaders
        let actorName = HTTPField.Name(ActorCredential.actorHeader)!
        let credentialName = HTTPField.Name(ActorCredential.credentialHeader)!
        let idempotencyName = HTTPField.Name("Idempotency-Key")!

        headers[actorName] = actorID
        headers[credentialName] = bashCredential
        headers[idempotencyName] = idempotencyKey
        return headers
    }
}
