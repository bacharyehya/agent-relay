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
}

private struct StubAppAPIClient: AppAPIClientProtocol {
    let projectThreads: [AppCore.Thread]

    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchProjects() async throws -> [Project] {
        []
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        projectThreads
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
