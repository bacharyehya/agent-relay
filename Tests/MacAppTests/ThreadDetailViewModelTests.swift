import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class ThreadDetailViewModelTests: XCTestCase {
    func test_accept_handoff_updates_local_card_state() async throws {
        let client = StubAppAPIClient()
        let model = ThreadDetailViewModel(client: client, threadID: "thread-1")

        await model.acceptHandoff(id: "handoff-1")

        XCTAssertEqual(model.handoffs.first?.status, .accepted)
    }
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        []
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
        AppThreadContext(
            thread: .example(id: threadID),
            messages: [],
            handoffs: [.example(id: "handoff-1", threadID: threadID)]
        )
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        Handoff(
            id: "handoff-created",
            threadID: request.threadID,
            title: request.title,
            summary: request.summary,
            ask: request.ask,
            priority: request.priority,
            createdBy: request.createdBy,
            assignedTo: request.assignedTo,
            sourceRefs: request.sourceRefs
        )
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        var handoff = Handoff.example(id: id, status: status)
        handoff.resolution = resolution
        return handoff
    }
}
