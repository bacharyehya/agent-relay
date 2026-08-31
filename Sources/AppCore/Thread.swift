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

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case title
        case intentType
        case status
        case createdBy
        case assignedActorIDs
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        intentType = try container.decode(ThreadIntentType.self, forKey: .intentType)
        status = try container.decode(ThreadStatus.self, forKey: .status)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        assignedActorIDs = try container.decode([String].self, forKey: .assignedActorIDs)
        if let timestamp = try? container.decode(String.self, forKey: .updatedAt) {
            guard let decodedDate = PreciseDateCodec.date(from: timestamp) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .updatedAt,
                    in: container,
                    debugDescription: "updatedAt must be an ISO-8601 timestamp"
                )
            }
            updatedAt = decodedDate
        } else {
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encode(intentType, forKey: .intentType)
        try container.encode(status, forKey: .status)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(assignedActorIDs, forKey: .assignedActorIDs)
        try container.encode(PreciseDateCodec.string(from: updatedAt), forKey: .updatedAt)
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
