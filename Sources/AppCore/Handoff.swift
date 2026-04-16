import Foundation

public struct Handoff: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var threadID: String
    public var title: String
    public var summary: String
    public var ask: String
    public var status: HandoffStatus
    public var priority: HandoffPriority
    public var createdBy: String
    public var assignedTo: String
    public var sourceRefs: [String]
    public var resolution: String?

    public init(
        id: String,
        threadID: String,
        title: String,
        summary: String,
        ask: String,
        status: HandoffStatus = .open,
        priority: HandoffPriority = .medium,
        createdBy: String = "human",
        assignedTo: String = "agent",
        sourceRefs: [String] = [],
        resolution: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.title = title
        self.summary = summary
        self.ask = ask
        self.status = status
        self.priority = priority
        self.createdBy = createdBy
        self.assignedTo = assignedTo
        self.sourceRefs = sourceRefs
        self.resolution = resolution
    }

    public mutating func transition(to next: HandoffStatus) throws {
        switch (status, next) {
        case (.open, .accepted),
             (.open, .blocked),
             (.open, .responded),
             (.accepted, .blocked),
             (.accepted, .responded),
             (.blocked, .accepted),
             (.responded, .resolved),
             (_, .canceled):
            status = next
        default:
            throw HandoffTransitionError.invalid(status, next)
        }
    }

    public static func example(
        id: String = "handoff-1",
        threadID: String = "thread-1",
        status: HandoffStatus = .open,
        title: String = "Fix webhook auth bug"
    ) -> Handoff {
        Handoff(
            id: id,
            threadID: threadID,
            title: title,
            summary: "Investigate intermittent auth failures",
            ask: "Confirm the root cause and provide the minimal fix.",
            status: status,
            sourceRefs: ["message-1"]
        )
    }

    public static func example(
        id: String = "handoff-1",
        threadID: String = "thread-1",
        status: HandoffStatus = .open
    ) -> Handoff {
        example(id: id, threadID: threadID, status: status, title: "Fix webhook auth bug")
    }
}

public enum HandoffStatus: String, Codable, Sendable {
    case open
    case accepted
    case blocked
    case responded
    case resolved
    case canceled
}

public enum HandoffPriority: String, Codable, Sendable {
    case low
    case medium
    case high
}

public enum HandoffTransitionError: Error, Equatable, Sendable {
    case invalid(HandoffStatus, HandoffStatus)
}
