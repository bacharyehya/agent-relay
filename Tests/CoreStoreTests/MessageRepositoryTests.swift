import AppCore
import Foundation
import XCTest
@testable import CoreStore

final class MessageRepositoryTests: XCTestCase {
    func test_create_and_list_preserves_reply_mentions_and_updates_thread() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_500)
        let message = Message(
            id: "message-reply",
            threadID: "thread-search",
            actorID: "codex-main",
            body: "Replying to Bash and tagging the reviewer.",
            replyToMessageID: "message-search",
            mentionedActorIDs: ["bash", "reviewer"],
            createdAt: timestamp
        )

        try repository.create(message)

        XCTAssertEqual(try repository.get(id: message.id), message)
        XCTAssertEqual(try repository.list(threadID: message.threadID).last, message)
        XCTAssertEqual(try ThreadRepository(db).get(id: message.threadID)?.updatedAt, timestamp)
    }

    func test_list_supports_bounded_before_pagination_in_display_order() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)
        let secondTimestamp = Date(timeIntervalSince1970: 1_700_000_200)
        let thirdTimestamp = Date(timeIntervalSince1970: 1_700_000_300)
        try repository.create(
            Message(
                id: "message-second",
                threadID: "thread-search",
                actorID: "codex-main",
                body: "Second",
                createdAt: secondTimestamp
            )
        )
        try repository.create(
            Message(
                id: "message-third",
                threadID: "thread-search",
                actorID: "bash",
                body: "Third",
                createdAt: thirdTimestamp
            )
        )

        XCTAssertEqual(
            try repository.list(threadID: "thread-search", limit: 2).map(\.id),
            ["message-second", "message-third"]
        )
        XCTAssertEqual(
            try repository.list(
                threadID: "thread-search",
                limit: 10,
                before: MessageCursor(createdAt: thirdTimestamp, messageID: "message-third")
            ).map(\.id),
            ["message-search", "message-second"]
        )
    }

    func test_composite_cursor_does_not_skip_equal_timestamps() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_400)
        for id in ["same-a", "same-b", "same-c"] {
            try repository.create(
                Message(
                    id: id,
                    threadID: "thread-search",
                    actorID: "bash",
                    body: id,
                    createdAt: timestamp
                )
            )
        }

        let latest = try repository.list(threadID: "thread-search", limit: 2)
        XCTAssertEqual(latest.map(\.id), ["same-b", "same-c"])

        let older = try repository.list(
            threadID: "thread-search",
            limit: 10,
            before: MessageCursor(message: try XCTUnwrap(latest.first))
        )
        XCTAssertTrue(older.map(\.id).contains("same-a"))
        XCTAssertFalse(older.map(\.id).contains("same-b"))
        XCTAssertFalse(older.map(\.id).contains("same-c"))
    }

    func test_idempotent_create_returns_original_and_rejects_changed_payload() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)
        let original = Message(
            id: "idempotent-original",
            threadID: "thread-search",
            actorID: "bash",
            body: "One logical post"
        )

        let first = try repository.createIdempotently(original, idempotencyKey: "client-key")
        var retry = original
        retry.id = "idempotent-retry"
        retry.createdAt = original.createdAt.addingTimeInterval(10)
        let second = try repository.createIdempotently(retry, idempotencyKey: "client-key")

        XCTAssertTrue(first.wasCreated)
        XCTAssertFalse(second.wasCreated)
        XCTAssertEqual(second.message.id, original.id)
        XCTAssertEqual(second.message.createdAt, first.message.createdAt)
        XCTAssertEqual(try repository.get(id: original.id)?.createdAt, first.message.createdAt)

        retry.body = "A different logical post"
        XCTAssertThrowsError(
            try repository.createIdempotently(retry, idempotencyKey: "client-key")
        ) { error in
            XCTAssertEqual(error as? MessageRepositoryError, .idempotencyKeyConflict("client-key"))
        }
    }

    func test_reply_target_must_exist_in_same_thread() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)

        XCTAssertThrowsError(
            try repository.create(
                Message(
                    id: "bad-reply",
                    threadID: "thread-search",
                    actorID: "bash",
                    body: "No target",
                    replyToMessageID: "missing"
                )
            )
        ) { error in
            XCTAssertEqual(error as? MessageRepositoryError, .replyMessageNotFound("missing"))
        }
    }

    func test_list_mentions_is_exact_across_rooms_and_newest_first() throws {
        let db = try TestDatabase.seeded()
        let repository = MessageRepository(db)
        try repository.create(
            Message(
                id: "mention-main",
                threadID: "thread-search",
                actorID: "bash",
                body: "@codex-main review this",
                mentionedActorIDs: ["codex-main"],
                createdAt: Date(timeIntervalSince1970: 1_700_000_600)
            )
        )
        try repository.create(
            Message(
                id: "mention-main-newer",
                threadID: "thread-search",
                actorID: "reviewer",
                body: "@codex-main second",
                mentionedActorIDs: ["codex-main"],
                createdAt: Date(timeIntervalSince1970: 1_700_000_700)
            )
        )
        try repository.create(
            Message(
                id: "mention-main-similar",
                threadID: "thread-search",
                actorID: "bash",
                body: "@codex-main-2 only",
                mentionedActorIDs: ["codex-main-2"],
                createdAt: Date(timeIntervalSince1970: 1_700_000_800)
            )
        )

        XCTAssertEqual(
            try repository.listMentions(actorID: "codex-main").map(\.id),
            ["mention-main-newer", "mention-main"]
        )
    }
}
