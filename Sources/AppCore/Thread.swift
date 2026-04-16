import Foundation

public struct Thread: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var projectID: String
    public var title: String
    public var intentType: ThreadIntentType
    public var status: ThreadStatus
    public var createdBy: String
    public var assignedActorIDs: [String]
    public var updatedAt: Date

    public init(
        id: String,
        projectID: String,
        title: String,
        intentType: ThreadIntentType = .task,
        status: ThreadStatus = .active,
        createdBy: String = "human",
        assignedActorIDs: [String] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.intentType = intentType
        self.status = status
        self.createdBy = createdBy
        self.assignedActorIDs = assignedActorIDs
        self.updatedAt = updatedAt
    }

    public static func example(id: String = "thread-1", projectID: String = "project-1") -> Thread {
        Thread(id: id, projectID: projectID, title: "Webhook auth bug")
    }

    public static func example(
        id: String = "thread-1",
        projectID: String = "project-1",
        title: String
    ) -> Thread {
        Thread(id: id, projectID: projectID, title: title)
    }
}

public enum ThreadIntentType: String, Codable, Sendable {
    case task
    case question
    case bug
    case decision
    case review
}

public enum ThreadStatus: String, Codable, Sendable {
    case active
    case waiting
    case closed
}
