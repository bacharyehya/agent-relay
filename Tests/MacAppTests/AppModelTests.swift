import AppCore
import XCTest
@testable import MacAppSupport

@MainActor
final class AppModelTests: XCTestCase {
    func test_app_model_shows_degraded_when_service_is_unreachable() async {
        let client = FailingAppAPIClient()
        let model = AppModel(client: client)

        await model.refresh()

        XCTAssertEqual(model.serviceState, .degraded)
    }
}

private struct FailingAppAPIClient: AppAPIClientProtocol {
    func fetchHealth() async throws -> AppHealth {
        throw URLError(.cannotConnectToHost)
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
