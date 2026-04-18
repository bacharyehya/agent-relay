import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class ProjectDetailViewModelTests: XCTestCase {
    func test_project_detail_loads_threads_for_selected_project() async throws {
        let client = StubAppAPIClient(projectThreads: [.example(title: "Webhook auth bug")])
        let model = ProjectDetailViewModel(client: client, projectID: "shield")

        await model.load()

        XCTAssertEqual(model.threads.first?.title, "Webhook auth bug")
    }

    func test_project_detail_load_records_error_when_thread_fetch_fails() async {
        let client = StubAppAPIClient(
            projectThreads: [],
            projectThreadsError: URLError(.cannotConnectToHost)
        )
        let model = ProjectDetailViewModel(client: client, projectID: "shield")

        await model.load()

        XCTAssertEqual(model.threads, [])
        XCTAssertNil(model.threadContext)
        XCTAssertNotNil(model.errorMessage)
    }
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    let projectThreads: [AppCore.Thread]
    let projectThreadsError: Error?

    init(projectThreads: [AppCore.Thread], projectThreadsError: Error? = nil) {
        self.projectThreads = projectThreads
        self.projectThreadsError = projectThreadsError
    }

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
        if let projectThreadsError {
            throw projectThreadsError
        }
        return projectThreads
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
