import AppCore
import Foundation
import XCTest
@testable import MCPAdapter

final class MCPServerTests: XCTestCase {
    func test_initialize_ping_and_tool_descriptors_follow_mcp_handshake() async throws {
        let server = MCPServer(client: MCPStubClient(), actorID: "codex-main")
        let initialize = try XCTUnwrap(
            try await server.handle(
                line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
            )
        )
        let initializeJSON = try Self.json(initialize)
        let result = try XCTUnwrap(initializeJSON["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertTrue((result["instructions"] as? String)?.contains("codex-main") == true)

        let initialized = try await server.handle(
            line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        )
        XCTAssertNil(initialized)

        let ping = try XCTUnwrap(
            try await server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        )
        XCTAssertNotNil(try Self.json(ping)["result"] as? [String: Any])

        let list = try XCTUnwrap(
            try await server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        )
        let listResult = try XCTUnwrap(try Self.json(list)["result"] as? [String: Any])
        let tools = try XCTUnwrap(listResult["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "get_messages" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "post_message" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "list_projects" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "list_rooms" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "list_actors" })
        XCTAssertTrue(tools.allSatisfy { $0["inputSchema"] is [String: Any] })
    }

    func test_post_message_rejects_actor_spoofing() async throws {
        let server = MCPServer(client: MCPStubClient(), actorID: "codex-main")
        let response = try XCTUnwrap(
            try await server.handle(
                line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"post_message","arguments":{"thread_id":"thread-1","body":"hello","idempotency_key":"spoof-test","actor_id":"someone-else"}}}"#
            )
        )
        let result = try XCTUnwrap(try Self.json(response)["result"] as? [String: Any])

        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertTrue((content.first?["text"] as? String)?.contains("codex-main") == true)
    }

    func test_post_message_uses_bound_actor_identity() async throws {
        let server = MCPServer(client: MCPStubClient(), actorID: "codex-main")
        let response = try XCTUnwrap(
            try await server.handle(
                line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"post_message","arguments":{"thread_id":"thread-1","body":"hello","idempotency_key":"bound-test","mentioned_actor_ids":["bash"]}}}"#
            )
        )
        let result = try XCTUnwrap(try Self.json(response)["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertTrue((content.first?["text"] as? String)?.contains("codex-main") == true)
    }

    func test_discovery_and_message_cursor_are_directly_reusable() async throws {
        let server = MCPServer(client: MCPStubClient(), actorID: "codex-main")
        let actorsResponse = try XCTUnwrap(
            try await server.handle(
                line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_actors","arguments":{}}}"#
            )
        )
        XCTAssertTrue(actorsResponse.contains("bash"))
        XCTAssertTrue(actorsResponse.contains("codex-main"))

        let messagesResponse = try XCTUnwrap(
            try await server.handle(
                line: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_messages","arguments":{"thread_id":"thread-1","limit":1}}}"#
            )
        )
        let result = try XCTUnwrap(try Self.json(messagesResponse)["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let page = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let cursor = try XCTUnwrap(page["nextCursor"] as? [String: Any])
        XCTAssertNotNil(cursor["created_at"] as? String)
        XCTAssertEqual(cursor["message_id"] as? String, "message-visible")
        XCTAssertNil(cursor["createdAt"])
        XCTAssertNil(cursor["messageID"])
    }

    func test_unbound_server_does_not_advertise_post_message_and_invalid_json_is_parse_error() async throws {
        let server = MCPServer(client: MCPStubClient())
        let list = try XCTUnwrap(
            try await server.handle(line: #"{"jsonrpc":"2.0","id":8,"method":"tools/list"}"#)
        )
        let listResult = try XCTUnwrap(try Self.json(list)["result"] as? [String: Any])
        let tools = try XCTUnwrap(listResult["tools"] as? [[String: Any]])
        XCTAssertFalse(tools.contains { $0["name"] as? String == "post_message" })

        let invalid = try XCTUnwrap(try await server.handle(line: "{"))
        let error = try XCTUnwrap(try Self.json(invalid)["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
    }

    private static func json(_ rawValue: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(rawValue.utf8)) as? [String: Any]
        )
    }
}

private struct MCPStubClient: CoreAPIClientProtocol {
    func listProjects() async throws -> [Project] {
        [.example(id: "project-1")]
    }

    func listThreads(projectID: String) async throws -> [AppCore.Thread] {
        [AppCore.Thread(
            id: "thread-1",
            projectID: projectID,
            title: "General",
            createdBy: "bash",
            assignedActorIDs: ["codex-main"]
        )]
    }

    func listInbox(actorID: String) async throws -> [Handoff] { [] }

    func listRecents() async throws -> [RecentItemPayload] { [] }

    func getThread(threadID: String, mode: String) async throws -> ThreadContextPayload {
        ThreadContextPayload(thread: .example(id: threadID), messages: [], handoffs: [])
    }

    func getMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message] {
        [Message(
            id: "message-visible",
            threadID: threadID,
            actorID: "bash",
            body: "Visible",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123456789)
        )]
    }

    func postMessage(threadID: String, request: CreateMessagePayload) async throws -> Message {
        Message(
            id: "message-posted",
            threadID: threadID,
            actorID: request.actorID,
            body: request.body,
            format: request.format,
            replyToMessageID: request.replyToMessageID,
            mentionedActorIDs: request.mentionedActorIDs
        )
    }

    func createHandoff(_ request: CreateHandoffPayload) async throws -> Handoff {
        .example(threadID: request.threadID, title: request.title)
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        var handoff = Handoff.example(id: id)
        try handoff.transition(to: status)
        handoff.resolution = resolution
        return handoff
    }
}
