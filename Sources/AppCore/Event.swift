import Foundation

public struct Event: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: EventType
    public var projectID: String?
    public var threadID: String?
    public var handoffID: String?
    public var actorID: String?
    public var body: String
    public var createdAt: Date

    public init(
        id: String,
        type: EventType,
        projectID: String? = nil,
        threadID: String? = nil,
        handoffID: String? = nil,
        actorID: String? = nil,
        body: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.projectID = projectID
        self.threadID = threadID
        self.handoffID = handoffID
        self.actorID = actorID
        self.body = body
        self.createdAt = createdAt
    }

    public static func example(type: EventType = .handoffCreated) -> Event {
        Event(
            id: "event-1",
            type: type,
            projectID: "project-1",
            threadID: "thread-1",
            handoffID: "handoff-1",
            actorID: "chatgpt",
            body: "Example event"
        )
    }
}

public enum EventType: String, Codable, Sendable {
    case projectCreated
    case threadCreated
    case messageAdded
    case handoffCreated
    case handoffAccepted
    case handoffBlocked
    case handoffResponded
    case handoffResolved
    case handoffAssignedToHuman
    case humanReplyRequested
    case serviceFailure
}
