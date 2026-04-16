import AppCore
import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import CoreAPI

final class HandoffRouteTests: XCTestCase {
    func test_handoff_routes_require_auth_and_support_create_fetch_and_update() async throws {
        let app = try TestApp.make()
        let encoder = JSONEncoder()
        let createBody = try XCTUnwrap(
            String(
                data: encoder.encode(
                    CreateHandoffRequest(
                        threadID: "thread-api",
                        title: "Fix webhook auth bug",
                        summary: "Track the token mismatch",
                        ask: "Find the minimal fix.",
                        priority: .high,
                        createdBy: "human",
                        assignedTo: "chatgpt",
                        sourceRefs: []
                    )
                ),
                encoding: .utf8
            )
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/handoffs",
                method: .post,
                body: ByteBuffer(string: createBody)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }

            var createdHandoff: Handoff?
            try await client.execute(
                uri: "/handoffs",
                method: .post,
                headers: TestApp.authorizedHeaders,
                body: ByteBuffer(string: createBody)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                createdHandoff = try Self.decode(Handoff.self, from: response.body)
                XCTAssertEqual(createdHandoff?.status, .open)
            }

            let handoff = try XCTUnwrap(createdHandoff)

            try await client.execute(
                uri: "/handoffs/\(handoff.id)",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let fetched = try Self.decode(Handoff.self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(fetched.id, handoff.id)
            }

            let updateBody = try XCTUnwrap(
                String(
                    data: encoder.encode(UpdateHandoffRequest(status: .accepted, resolution: nil)),
                    encoding: .utf8
                )
            )

            try await client.execute(
                uri: "/handoffs/\(handoff.id)",
                method: .put,
                headers: TestApp.authorizedHeaders,
                body: ByteBuffer(string: updateBody)
            ) { response in
                let updated = try Self.decode(Handoff.self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(updated.status, .accepted)
            }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let data = Data(buffer.readableBytesView)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
