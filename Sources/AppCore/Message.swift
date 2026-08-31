import Foundation

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var threadID: String
    public var actorID: String
    public var body: String
    public var format: MessageFormat
    public var replyToMessageID: String?
    public var mentionedActorIDs: [String]
    public var createdAt: Date

    public init(
        id: String,
        threadID: String,
        actorID: String,
        body: String,
        format: MessageFormat = .markdown,
        replyToMessageID: String? = nil,
        mentionedActorIDs: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.threadID = threadID
        self.actorID = actorID
        self.body = body
        self.format = format
        self.replyToMessageID = replyToMessageID
        self.mentionedActorIDs = mentionedActorIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case actorID
        case body
        case format
        case replyToMessageID
        case mentionedActorIDs
        case createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadID = try container.decode(String.self, forKey: .threadID)
        actorID = try container.decode(String.self, forKey: .actorID)
        body = try container.decode(String.self, forKey: .body)
        format = try container.decode(MessageFormat.self, forKey: .format)
        replyToMessageID = try container.decodeIfPresent(String.self, forKey: .replyToMessageID)
        mentionedActorIDs = try container.decodeIfPresent([String].self, forKey: .mentionedActorIDs) ?? []
        if let timestamp = try? container.decode(String.self, forKey: .createdAt) {
            guard let decodedDate = PreciseDateCodec.date(from: timestamp) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .createdAt,
                    in: container,
                    debugDescription: "createdAt must be an ISO-8601 timestamp"
                )
            }
            createdAt = decodedDate
        } else {
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(actorID, forKey: .actorID)
        try container.encode(body, forKey: .body)
        try container.encode(format, forKey: .format)
        try container.encodeIfPresent(replyToMessageID, forKey: .replyToMessageID)
        try container.encode(mentionedActorIDs, forKey: .mentionedActorIDs)
        try container.encode(PreciseDateCodec.string(from: createdAt), forKey: .createdAt)
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
