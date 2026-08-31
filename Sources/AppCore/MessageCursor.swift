import Foundation

/// Stable pagination position for message history. The ID breaks ties when
/// multiple messages have the same timestamp.
public struct MessageCursor: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let messageID: String

    public init(createdAt: Date, messageID: String) {
        self.createdAt = createdAt
        self.messageID = messageID
    }

    public init(message: Message) {
        self.init(createdAt: message.createdAt, messageID: message.id)
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case messageID = "message_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCreatedAt = try container.decode(String.self, forKey: .createdAt)
        guard let createdAt = PreciseDateCodec.date(from: rawCreatedAt) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "createdAt must be an RFC 3339 timestamp"
            )
        }
        self.createdAt = createdAt
        self.messageID = try container.decode(String.self, forKey: .messageID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PreciseDateCodec.string(from: createdAt), forKey: .createdAt)
        try container.encode(messageID, forKey: .messageID)
    }
}
