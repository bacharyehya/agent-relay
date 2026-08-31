import Foundation

/// Stable pagination position for message history. The ID breaks ties when
/// multiple messages have the same timestamp.
public struct MessageCursor: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let messageID: String
    public let sequence: Int?

    public init(createdAt: Date, messageID: String, sequence: Int? = nil) {
        self.createdAt = createdAt
        self.messageID = messageID
        self.sequence = sequence
    }

    public init(message: Message) {
        self.init(createdAt: message.createdAt, messageID: message.id, sequence: message.sequence)
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case messageID = "message_id"
        case sequence
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
        self.sequence = try container.decodeIfPresent(Int.self, forKey: .sequence)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PreciseDateCodec.string(from: createdAt), forKey: .createdAt)
        try container.encode(messageID, forKey: .messageID)
        try container.encodeIfPresent(sequence, forKey: .sequence)
    }
}
