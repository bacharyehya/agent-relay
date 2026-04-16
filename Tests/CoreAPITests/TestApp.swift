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

        try ProjectRepository(databaseQueue).create(project)
        try ThreadRepository(databaseQueue).create(thread)

        let environment = AppEnvironment(
            projectRepository: ProjectRepository(databaseQueue),
            threadRepository: ThreadRepository(databaseQueue),
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            authToken: AuthToken(token)
        )
        return CoreAPIApp.makeApplication(environment: environment)
    }

    static var authorizedHeaders: HTTPFields {
        [.authorization: "Bearer \(token)"]
    }
}
