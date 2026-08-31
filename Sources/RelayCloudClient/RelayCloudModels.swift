import AppCore
import Foundation

public struct RelayWorkspace: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RelayCloudActor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let type: ActorType
    public let displayName: String
    public let role: String
    public let status: ActorStatus

    public init(id: String, type: ActorType, displayName: String, role: String, status: ActorStatus) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.role = role
        self.status = status
    }
}

public struct RelayCloudRoom: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let title: String
    public let topic: String
    public let isArchived: Bool
    public let updatedAt: Date
    public let lastReadSequence: Int?
    public let latestSequence: Int?
    public let unreadCount: Int?

    public init(
        id: String,
        name: String,
        title: String,
        topic: String,
        isArchived: Bool,
        updatedAt: Date,
        lastReadSequence: Int? = nil,
        latestSequence: Int? = nil,
        unreadCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.topic = topic
        self.isArchived = isArchived
        self.updatedAt = updatedAt
        self.lastReadSequence = lastReadSequence
        self.latestSequence = latestSequence
        self.unreadCount = unreadCount
    }
}

public struct RelayCloudMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sequence: Int
    public let roomID: String
    public let threadID: String
    public let actorID: String
    public let body: String
    public let format: MessageFormat
    public let replyToMessageID: String?
    public let mentionedActorIDs: [String]
    public let createdAt: Date
    public let editedAt: Date?
    public let idempotentReplay: Bool?

    public init(
        id: String,
        sequence: Int,
        roomID: String,
        threadID: String,
        actorID: String,
        body: String,
        format: MessageFormat,
        replyToMessageID: String?,
        mentionedActorIDs: [String],
        createdAt: Date,
        editedAt: Date?,
        idempotentReplay: Bool? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.roomID = roomID
        self.threadID = threadID
        self.actorID = actorID
        self.body = body
        self.format = format
        self.replyToMessageID = replyToMessageID
        self.mentionedActorIDs = mentionedActorIDs
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.idempotentReplay = idempotentReplay
    }
}

public struct RelayPresence: Codable, Equatable, Sendable {
    public let actorID: String
    public let deviceName: String
    public let state: String
    public let lastSeenAt: Date
}

public struct RelayReadReceipt: Codable, Equatable, Sendable {
    public let roomID: String
    public let lastReadSequence: Int
    public let updatedAt: Date
}

public struct RelayIdentityEnvelope: Codable, Equatable, Sendable {
    public let workspace: RelayWorkspace
    public let actor: RelayCloudActor
    public let device: RelayDeviceSummary
}

public struct RelayEnrollmentEnvelope: Codable, Equatable, Sendable {
    public let workspace: RelayWorkspace
    public let actor: RelayCloudActor
    public let device: RelayDeviceSummary
    public let token: String
    public let room: RelayCloudRoom?
}

public struct RelayDeviceSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let actorID: String?
    public let actorType: String?
    public let displayName: String?
    public let deviceName: String?
    public let createdAt: Date?
    public let lastUsedAt: Date?
    public let revokedAt: Date?
    public let isCurrent: Bool?
}

public struct RelayInvitation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let actorID: String
    public let displayName: String
    public let code: String
    public let expiresAt: Date
}

public struct RelaySyncSnapshot: Codable, Equatable, Sendable {
    public let workspace: RelayWorkspace
    public let currentActorID: String
    public let actors: [RelayCloudActor]
    public let rooms: [RelayCloudRoom]
    public let messages: [RelayCloudMessage]
    public let readReceipts: [RelayReadReceipt]
    public let presence: [RelayPresence]
    public let nextCursor: Int
    public let hasMore: Bool
}

public struct RelayServiceHealth: Codable, Equatable, Sendable {
    public let status: String
    public let service: String
    public let version: String
}

public struct RelayStoredSession: Codable, Equatable, Sendable {
    public let serverURL: URL
    public let workspace: RelayWorkspace
    public let actor: RelayCloudActor
    public let deviceID: String
    public let deviceName: String

    public init(
        serverURL: URL,
        workspace: RelayWorkspace,
        actor: RelayCloudActor,
        deviceID: String,
        deviceName: String
    ) {
        self.serverURL = serverURL
        self.workspace = workspace
        self.actor = actor
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

public struct RelayPostMessage: Encodable, Equatable, Sendable {
    public let body: String
    public let format: MessageFormat
    public let replyToMessageID: String?
    public let mentionedActorIDs: [String]

    public init(
        body: String,
        format: MessageFormat = .markdown,
        replyToMessageID: String? = nil,
        mentionedActorIDs: [String] = []
    ) {
        self.body = body
        self.format = format
        self.replyToMessageID = replyToMessageID
        self.mentionedActorIDs = mentionedActorIDs
    }
}
