import XCTest
@testable import AppCore
@testable import MCPAdapter

final class ListInboxToolTests: XCTestCase {
    func test_list_inbox_tool_returns_handoff_summaries() async throws {
        let client = StubCoreAPIClient(result: [.example(title: "Fix webhook bug")])
        let tool = ListInboxTool(client: client)

        let output = try await tool.run(actorID: "chatgpt")

        XCTAssertTrue(output.contains("Fix webhook bug"))
    }
}

private struct StubCoreAPIClient: CoreAPIClientProtocol {
    let result: [Handoff]

    func listInbox(actorID: String) async throws -> [Handoff] {
        result
    }

    func listRecents() async throws -> [RecentItemPayload] {
        []
    }

    func getThread(threadID: String, mode: String) async throws -> ThreadContextPayload {
        ThreadContextPayload(thread: AppCore.Thread.example(id: threadID), messages: [], handoffs: [])
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
