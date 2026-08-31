import Foundation
import XCTest
@testable import AppCore

final class MessageCodableTests: XCTestCase {
    func test_decoding_legacy_message_defaults_collaboration_metadata() throws {
        let json = #"{"id":"message-1","threadID":"thread-1","actorID":"bash","body":"Hello","format":"markdown","createdAt":0}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let message = try decoder.decode(Message.self, from: Data(json.utf8))

        XCTAssertNil(message.replyToMessageID)
        XCTAssertEqual(message.mentionedActorIDs, [])
    }

    func test_round_trip_preserves_fractional_timestamp_for_stable_pagination() throws {
        let original = Message(
            id: "message-precise",
            threadID: "thread-1",
            actorID: "bash",
            body: "Precise",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.789)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertNotNil(
            String(decoding: data, as: UTF8.self).range(
                of: #"\.\d{9}Z"#,
                options: .regularExpression
            )
        )
    }
}
