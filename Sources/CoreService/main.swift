import CoreAPI
import CoreStore
import Foundation

@main
struct CoreServiceMain {
    static func main() async throws {
        let environmentVariables = ProcessInfo.processInfo.environment
        let databasePath = environmentVariables["AGENT_RELAY_DB_PATH"]
            ?? (FileManager.default.currentDirectoryPath + "/agent-relay.sqlite")
        let authToken = environmentVariables["AGENT_RELAY_AUTH_TOKEN"] ?? "dev-token"

        let databaseQueue = try AppDatabase.makeDatabaseQueue(path: databasePath)
        let environment = AppEnvironment(
            projectRepository: ProjectRepository(databaseQueue),
            threadRepository: ThreadRepository(databaseQueue),
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            inboxRepository: InboxRepository(databaseQueue),
            authToken: AuthToken(authToken)
        )
        let app = CoreAPIApp.makeApplication(environment: environment)

        try await app.runService()
    }
}
