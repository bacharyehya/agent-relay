import AppCore
import CoreStore
import Foundation
import Hummingbird
import HTTPTypes

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
    public let messageRepository: MessageRepository
    public let handoffRepository: HandoffRepository
    public let eventRepository: EventRepository
    public let inboxRepository: InboxRepository
    public let notificationRepository: NotificationRepository
    public let searchRepository: SearchRepository
    public let eventStream: EventStream
    public let authToken: AuthToken
    public let actorCredentialStore: ActorCredentialStore

    public init(
        projectRepository: ProjectRepository,
        threadRepository: ThreadRepository,
        messageRepository: MessageRepository,
        handoffRepository: HandoffRepository,
        eventRepository: EventRepository,
        inboxRepository: InboxRepository,
        notificationRepository: NotificationRepository,
        searchRepository: SearchRepository,
        eventStream: EventStream = EventStream(),
        authToken: AuthToken,
        actorCredentialStore: ActorCredentialStore
    ) {
        self.projectRepository = projectRepository
        self.threadRepository = threadRepository
        self.messageRepository = messageRepository
        self.handoffRepository = handoffRepository
        self.eventRepository = eventRepository
        self.inboxRepository = inboxRepository
        self.notificationRepository = notificationRepository
        self.searchRepository = searchRepository
        self.eventStream = eventStream
        self.authToken = authToken
        self.actorCredentialStore = actorCredentialStore
    }

    public func requireAuthorization(for request: Request) throws {
        guard authToken.matches(request: request) else {
            throw HTTPError(.unauthorized, message: "Missing or invalid bearer token")
        }
    }

    /// Resolves a message sender from an actor-scoped proof. The JSON body is
    /// never authoritative for sender identity.
    public func requireActorIdentity(for request: Request) throws -> String {
        let actorHeader = HTTPField.Name(ActorCredential.actorHeader)!
        let credentialHeader = HTTPField.Name(ActorCredential.credentialHeader)!
        guard
            let rawActorID = request.headers[actorHeader],
            let credential = request.headers[credentialHeader]
        else {
            throw HTTPError(.unauthorized, message: "Missing actor-scoped credential")
        }

        let actorID = rawActorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            ActorCredentialStore.isValidActorID(actorID),
            actorCredentialStore.validates(credential: credential, actorID: actorID)
        else {
            throw HTTPError(.unauthorized, message: "Invalid actor-scoped credential")
        }
        return actorID
    }
}

public enum CoreAPIApp {
    public static func makeApplication(
        environment: AppEnvironment,
        host: String = AppRuntimeConfiguration.defaultCoreHost,
        port: Int = AppRuntimeConfiguration.defaultCorePort
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)

        HealthRoutes.register(on: router)
        ProjectRoutes.register(on: router, environment: environment)
        ThreadRoutes.register(on: router, environment: environment)
        MessageRoutes.register(on: router, environment: environment)
        HandoffRoutes.register(on: router, environment: environment)
        SearchRoutes.register(on: router, environment: environment)

        return Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port),
                serverName: "AgentRelayCore"
            )
        )
    }
}
