import AppCore
import CoreStore
import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import CoreAPI

final class InboxRouteTests: XCTestCase {
    func test_inbox_route_returns_open_and_blocked_handoffs_for_actor() async throws {
        let app = try TestApp.make()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/inbox/chatgpt",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let items = try Self.decode([Handoff].self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(items.map(\.status), [.open, .blocked])
            }
        }
    }

    func test_thread_context_route_returns_bounded_messages_and_handoffs() async throws {
        let app = try TestApp.make()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/threads/thread-api/context?mode=recent",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let context = try Self.decode(ThreadContext.self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(context.thread.id, "thread-api")
                XCTAssertEqual(context.messages.count, 2)
                XCTAssertEqual(context.handoffs.count, 2)
            }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let data = Data(buffer.readableBytesView)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
