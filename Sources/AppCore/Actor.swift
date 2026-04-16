import Foundation

public struct Actor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: ActorType
    public var displayName: String
    public var avatar: String?
    public var capabilities: [String]
    public var authReference: String?
    public var status: ActorStatus

    public init(
        id: String,
        type: ActorType,
        displayName: String,
        avatar: String? = nil,
        capabilities: [String] = [],
        authReference: String? = nil,
        status: ActorStatus = .active
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.avatar = avatar
        self.capabilities = capabilities
        self.authReference = authReference
        self.status = status
    }

    public static func example(id: String = "chatgpt") -> Actor {
        Actor(
            id: id,
            type: .agent,
            displayName: "ChatGPT",
            capabilities: ["analysis", "implementation"]
        )
    }
}

public enum ActorType: String, Codable, Sendable {
    case human
    case agent
}

public enum ActorStatus: String, Codable, Sendable {
    case active
    case paused
    case unavailable
}
