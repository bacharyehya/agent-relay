import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class InboxViewModelTests: XCTestCase {
    func test_inbox_sorts_blocked_handoffs_before_recent_responses() async throws {
        let actorRecorder = ActorIDRecorder()
        let client = StubAppAPIClient(
            actorRecorder: actorRecorder,
            inboxItems: [
                Handoff.example(id: "handoff-responded", status: .responded),
                Handoff.example(id: "handoff-blocked", status: .blocked),
            ]
        )
        let model = InboxViewModel(client: client)

        await model.load()

        XCTAssertEqual(model.items.first?.status, .blocked)
    }

    func test_inbox_defaults_to_human_actor() async throws {
        let actorRecorder = ActorIDRecorder()
        let client = StubAppAPIClient(actorRecorder: actorRecorder, inboxItems: [])
        let model = InboxViewModel(client: client)

        await model.load()

        let actorIDs = await actorRecorder.values
        XCTAssertEqual(actorIDs, ["human"])
    }

    func test_inbox_records_error_when_fetch_fails() async {
        let actorRecorder = ActorIDRecorder()
        let client = StubAppAPIClient(
            actorRecorder: actorRecorder,
            inboxError: AppAPIClientError.httpStatus(401, "Missing bearer token"),
            inboxItems: []
        )
        let model = InboxViewModel(client: client)

        await model.load()

        XCTAssertEqual(model.items, [])
        XCTAssertNil(model.selectedThreadID)
        XCTAssertNotNil(model.errorMessage)
    }
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    let actorRecorder: ActorIDRecorder
    let inboxError: Error?
    let inboxItems: [Handoff]

    init(
        actorRecorder: ActorIDRecorder = ActorIDRecorder(),
        inboxError: Error? = nil,
        inboxItems: [Handoff]
    ) {
        self.actorRecorder = actorRecorder
        self.inboxError = inboxError
        self.inboxItems = inboxItems
    }

    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        await actorRecorder.record(actorID)
        if let inboxError {
            throw inboxError
        }
        return inboxItems
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

actor ActorIDRecorder {
    private(set) var values: [String] = []

    func record(_ actorID: String) {
        values.append(actorID)
    }
}
