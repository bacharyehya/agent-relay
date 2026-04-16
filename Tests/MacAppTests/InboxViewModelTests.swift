import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class InboxViewModelTests: XCTestCase {
    func test_inbox_sorts_blocked_handoffs_before_recent_responses() async throws {
        let client = StubAppAPIClient(
            inboxItems: [
                Handoff.example(id: "handoff-responded", status: .responded),
                Handoff.example(id: "handoff-blocked", status: .blocked),
            ]
        )
        let model = InboxViewModel(client: client)

        await model.load()

        XCTAssertEqual(model.items.first?.status, .blocked)
    }
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    let inboxItems: [Handoff]

    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        inboxItems
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        []
    }

    func search(query: String) async throws -> [AppSearchResult] {
        []
    }

    func fetchProjects() async throws -> [Project] {
        []
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        []
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        AppThreadContext(thread: .example(id: threadID), messages: [], handoffs: [])
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        Handoff.example(threadID: request.threadID)
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        var handoff = Handoff.example(id: id, status: status)
        handoff.resolution = resolution
        return handoff
    }
}
