import AppCore
import CoreStore
import Foundation
import Hummingbird

extension Project: ResponseCodable {}
extension AppCore.Thread: ResponseCodable {}
extension Message: ResponseCodable {}
extension Handoff: ResponseCodable {}
extension RecentItem: ResponseCodable {}
extension SearchResult: ResponseCodable {}
extension ThreadContext: ResponseCodable {}

public final class AppEnvironment: @unchecked Sendable {
    public let projectRepository: ProjectRepository
    public let threadRepository: ThreadRepository
    public let handoffRepository: HandoffRepository
    public let eventRepository: EventRepository
    public let inboxRepository: InboxRepository
    public let notificationRepository: NotificationRepository
    public let searchRepository: SearchRepository
    public let eventStream: EventStream
    public let authToken: AuthToken

    public init(
        projectRepository: ProjectRepository,
        threadRepository: ThreadRepository,
        handoffRepository: HandoffRepository,
        eventRepository: EventRepository,
        inboxRepository: InboxRepository,
        notificationRepository: NotificationRepository,
        searchRepository: SearchRepository,
        eventStream: EventStream = EventStream(),
        authToken: AuthToken
    ) {
        self.projectRepository = projectRepository
        self.threadRepository = threadRepository
        self.handoffRepository = handoffRepository
        self.eventRepository = eventRepository
        self.inboxRepository = inboxRepository
        self.notificationRepository = notificationRepository
        self.searchRepository = searchRepository
        self.eventStream = eventStream
        self.authToken = authToken
    }

    public func requireAuthorization(for request: Request) throws {
        guard authToken.matches(request: request) else {
            throw HTTPError(.unauthorized, message: "Missing or invalid bearer token")
        }
    }
}

public enum CoreAPIApp {
    public static func makeApplication(
        environment: AppEnvironment
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)

        HealthRoutes.register(on: router)
        ProjectRoutes.register(on: router, environment: environment)
        ThreadRoutes.register(on: router, environment: environment)
        HandoffRoutes.register(on: router, environment: environment)
        SearchRoutes.register(on: router, environment: environment)

        return Application(
            router: router,
            configuration: .init(
                address: .hostname(port: 8080),
                serverName: "AgentRelayCore"
            )
        )
    }
}
