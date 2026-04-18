import AppCore
import CoreAPI
import CoreStore
import Foundation

@main
struct CoreServiceMain {
    static func main() async throws {
        let environmentVariables = ProcessInfo.processInfo.environment
        let databaseURL = try AppRuntimeConfiguration.databaseURL(environment: environmentVariables)
        let authToken = try AppRuntimeConfiguration.loadOrCreateAuthToken(environment: environmentVariables)
        let host = environmentVariables["AGENT_RELAY_CORE_HOST"] ?? AppRuntimeConfiguration.defaultCoreHost
        let port = Int(environmentVariables["AGENT_RELAY_CORE_PORT"] ?? "") ?? AppRuntimeConfiguration.defaultCorePort

        let databaseQueue = try AppDatabase.makeDatabaseQueue(path: databaseURL.path())
        let environment = AppEnvironment(
            projectRepository: ProjectRepository(databaseQueue),
            threadRepository: ThreadRepository(databaseQueue),
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            inboxRepository: InboxRepository(databaseQueue),
            notificationRepository: NotificationRepository(databaseQueue),
            searchRepository: SearchRepository(databaseQueue),
            authToken: AuthToken(authToken)
        )
        let app = CoreAPIApp.makeApplication(
            environment: environment,
            host: host,
            port: port
        )

        try await app.runService()
    }
}
