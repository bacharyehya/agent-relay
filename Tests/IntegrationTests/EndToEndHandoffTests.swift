import AppCore
@testable import CoreAPI
import CoreStore
import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

final class EndToEndHandoffTests: XCTestCase {
    func test_create_accept_respond_and_resolve_handoff_flow() async throws {
        let system = try await TestSystem.make()
        let handoff = try await system.createHandoff()

        try await system.accept(handoff.id)
        try await system.respond(handoff.id, body: "Root cause is token mismatch")
        try await system.resolve(handoff.id)

        let resolvedHandoff = try await system.fetchHandoff(handoff.id)

        XCTAssertEqual(resolvedHandoff.status, .resolved)
    }
}

private struct TestSystem {
    let app: Application<RouterResponder<BasicRequestContext>>

    static func make() async throws -> TestSystem {
        let databaseQueue = try AppDatabase.makeInMemoryDatabase()
        let timestamp = Date(timeIntervalSince1970: 1_700_002_000)
        let project = Project(
            id: "project-e2e",
            title: "Shield",
            summary: "Integration fixture",
            status: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let thread = AppCore.Thread(
            id: "thread-e2e",
            projectID: project.id,
            title: "Webhook auth",
            intentType: .bug,
            status: .active,
            createdBy: "human",
            assignedActorIDs: ["chatgpt"],
            updatedAt: timestamp
        )

        try ProjectRepository(databaseQueue).create(project)
        try ThreadRepository(databaseQueue).create(thread)

        let environment = AppEnvironment(
            projectRepository: ProjectRepository(databaseQueue),
            threadRepository: ThreadRepository(databaseQueue),
            handoffRepository: HandoffRepository(databaseQueue),
            eventRepository: EventRepository(databaseQueue),
            inboxRepository: InboxRepository(databaseQueue),
            notificationRepository: NotificationRepository(databaseQueue),
            searchRepository: SearchRepository(databaseQueue),
            authToken: AuthToken("test-token")
        )
        return TestSystem(app: CoreAPIApp.makeApplication(environment: environment))
    }

    func createHandoff() async throws -> Handoff {
        let encoder = JSONEncoder()
        let body = try XCTUnwrap(
            String(
                data: encoder.encode(
                    CreateHandoffRequest(
                        threadID: "thread-e2e",
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

        let created = ValueBox<Handoff>()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/handoffs",
                method: .post,
                headers: Self.authorizedHeaders,
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                await created.set(try Self.decode(Handoff.self, from: response.body))
            }
        }

        guard let handoff = await created.get() else {
            throw TestSystemError.missingDecodedValue
        }
        return handoff
    }

    func accept(_ id: String) async throws {
        _ = try await update(id: id, status: .accepted, resolution: nil)
    }

    func respond(_ id: String, body: String) async throws {
        _ = try await update(id: id, status: .responded, resolution: body)
    }

    func resolve(_ id: String) async throws {
        _ = try await update(id: id, status: .resolved, resolution: nil)
    }

    func fetchHandoff(_ id: String) async throws -> Handoff {
        let handoff = ValueBox<Handoff>()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/handoffs/\(id)",
                method: .get,
                headers: Self.authorizedHeaders
            ) { response in
                XCTAssertEqual(response.status, .ok)
                await handoff.set(try Self.decode(Handoff.self, from: response.body))
            }
        }

        guard let handoff = await handoff.get() else {
            throw TestSystemError.missingDecodedValue
        }
        return handoff
    }

    private func update(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        let encoder = JSONEncoder()
        let body = try XCTUnwrap(
            String(
                data: encoder.encode(UpdateHandoffRequest(status: status, resolution: resolution)),
                encoding: .utf8
            )
        )

        let handoff = ValueBox<Handoff>()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/handoffs/\(id)",
                method: .put,
                headers: Self.authorizedHeaders,
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                await handoff.set(try Self.decode(Handoff.self, from: response.body))
            }
        }

        guard let handoff = await handoff.get() else {
            throw TestSystemError.missingDecodedValue
        }
        return handoff
    }

    private static var authorizedHeaders: HTTPFields {
        [.authorization: "Bearer test-token"]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let data = Data(buffer.readableBytesView)
        return try JSONDecoder().decode(T.self, from: data)
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

private enum TestSystemError: Error {
    case missingDecodedValue
}
