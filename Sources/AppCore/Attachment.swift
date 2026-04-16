import Foundation

public struct Attachment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: AttachmentKind
    public var name: String
    public var location: String
    public var projectID: String?
    public var threadID: String?
    public var handoffID: String?
    public var createdAt: Date

    public init(
        id: String,
        kind: AttachmentKind,
        name: String,
        location: String,
        projectID: String? = nil,
        threadID: String? = nil,
        handoffID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.location = location
        self.projectID = projectID
        self.threadID = threadID
        self.handoffID = handoffID
        self.createdAt = createdAt
    }
}

public enum AttachmentKind: String, Codable, Sendable {
    case file
    case link
    case image
    case artifact
}
