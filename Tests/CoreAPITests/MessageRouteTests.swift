import AppCore
import CoreStore
import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import CoreAPI

final class MessageRouteTests: XCTestCase {
    func test_routes_require_auth_and_create_visible_searchable_message() async throws {
        let app = try TestApp.make()
        let body = try Self.requestBody(
            CreateMessageRequest(
                actorID: "bash",
                body: "Please inspect the relay singularity marker.",
                format: .markdown,
                replyToMessageID: "message-api-1",
                mentionedActorIDs: ["codex-main", "codex-main", " reviewer "]
            )
        )
        let postHeaders = TestApp.actorHeaders(idempotencyKey: "message-create-1")

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .get
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }

            let created = ValueBox<Message>()
            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: postHeaders,
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                await created.set(try Self.decode(Message.self, from: response.body))
            }

            let createdMessage = await created.get()
            let message = try XCTUnwrap(createdMessage)
            XCTAssertEqual(message.actorID, "bash")
            XCTAssertEqual(message.replyToMessageID, "message-api-1")
            XCTAssertEqual(message.mentionedActorIDs, ["codex-main", "reviewer"])

            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: postHeaders,
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let retried = try Self.decode(Message.self, from: response.body)
                XCTAssertEqual(retried.id, message.id)
                XCTAssertEqual(retried.createdAt, message.createdAt)
            }

            try await client.execute(
                uri: "/threads/thread-api/messages?limit=2",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let messages = try Self.decode([Message].self, from: response.body)
                XCTAssertEqual(messages.count, 2)
                XCTAssertEqual(messages.last?.id, message.id)
            }

            try await client.execute(
                uri: "/search?q=singularity",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let results = try Self.decode([SearchResult].self, from: response.body)
                XCTAssertEqual(results.map(\.objectID), [message.id])
            }

            try await client.execute(
                uri: "/recents",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let recents = try Self.decode([RecentItem].self, from: response.body)
                XCTAssertTrue(recents.contains { $0.type == .messageAdded && $0.threadID == "thread-api" })
                XCTAssertEqual(
                    recents.filter { $0.eventID == "message-added:\(message.id)" }.count,
                    1
                )
            }

            try await client.execute(
                uri: "/threads/thread-api",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let thread = try Self.decode(AppCore.Thread.self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(thread.updatedAt, message.createdAt)
            }
        }
    }

    func test_get_supports_before_timestamp_and_post_rejects_invalid_reply() async throws {
        let app = try TestApp.make()
        let invalidReplyBody = try Self.requestBody(
            CreateMessageRequest(
                actorID: "bash",
                body: "Replying nowhere",
                replyToMessageID: "missing-message"
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/threads/thread-api/messages?before_created_at=2023-11-14T22%3A30%3A30Z&before_message_id=message-api-2&limit=10",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let messages = try Self.decode([Message].self, from: response.body)
                XCTAssertEqual(messages.map(\.id), ["message-api-1"])
            }

            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: TestApp.actorHeaders(idempotencyKey: "invalid-reply"),
                body: ByteBuffer(string: invalidReplyBody)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
            }
        }
    }

    func test_post_requires_actor_scope_rejects_spoofing_and_conflicting_retry() async throws {
        let app = try TestApp.make()
        let spoofedBody = try Self.requestBody(
            CreateMessageRequest(actorID: "someone-else", body: "Spoof attempt")
        )
        let firstBody = try Self.requestBody(
            CreateMessageRequest(actorID: "bash", body: "First payload")
        )
        let changedBody = try Self.requestBody(
            CreateMessageRequest(actorID: "bash", body: "Changed payload")
        )
        let retryHeaders = TestApp.actorHeaders(idempotencyKey: "same-logical-write")

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: TestApp.authorizedHeaders,
                body: ByteBuffer(string: firstBody)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }

            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: TestApp.actorHeaders(idempotencyKey: "spoof-attempt"),
                body: ByteBuffer(string: spoofedBody)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }

            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: retryHeaders,
                body: ByteBuffer(string: firstBody)
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }

            try await client.execute(
                uri: "/threads/thread-api/messages",
                method: .post,
                headers: retryHeaders,
                body: ByteBuffer(string: changedBody)
            ) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func test_http_composite_cursor_preserves_precision_across_equal_timestamps() async throws {
        let app = try TestApp.make()
        let firstPage = ValueBox<[Message]>()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/threads/thread-api/messages?limit=2",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                await firstPage.set(try Self.decode([Message].self, from: response.body))
            }

            let firstPageValue = await firstPage.get()
            let page = try XCTUnwrap(firstPageValue)
            XCTAssertEqual(page.map(\.id), ["message-api-same-b", "message-api-same-c"])
            let cursorMessage = try XCTUnwrap(page.first)
            let encodedDate = PreciseDateCodec.string(from: cursorMessage.createdAt)
                .replacingOccurrences(of: ":", with: "%3A")

            try await client.execute(
                uri: "/threads/thread-api/messages?limit=10&before_created_at=\(encodedDate)&before_message_id=\(cursorMessage.id)",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let older = try Self.decode([Message].self, from: response.body)
                XCTAssertTrue(older.map(\.id).contains("message-api-same-a"))
                XCTAssertFalse(older.map(\.id).contains("message-api-same-b"))
                XCTAssertFalse(older.map(\.id).contains("message-api-same-c"))
            }
        }
    }

    private static func requestBody<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(buffer.readableBytesView))
    }
}

private actor ValueBox<Value> {
    private var value: Value?

    func set(_ value: Value) {
        self.value = value
    }

    func get() -> Value? {
        value
    }
}
