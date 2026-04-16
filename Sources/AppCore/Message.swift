import Foundation

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var threadID: String
    public var actorID: String
    public var body: String
    public var format: MessageFormat
    public var createdAt: Date

    public init(
        id: String,
        threadID: String,
        actorID: String,
        body: String,
        format: MessageFormat = .markdown,
        createdAt: Date = .now
    ) {
        self.id = id
        self.threadID = threadID
        self.actorID = actorID
        self.body = body
        self.format = format
        self.createdAt = createdAt
    }

    public static func example(id: String = "message-1", threadID: String = "thread-1") -> Message {
        Message(
            id: id,
            threadID: threadID,
            actorID: "human",
            body: "Investigating webhook auth mismatch."
        )
    }
}

public enum MessageFormat: String, Codable, Sendable {
    case markdown
    case plainText
}
