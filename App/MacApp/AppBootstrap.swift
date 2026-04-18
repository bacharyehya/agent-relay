import AppCore
import Foundation

enum AppBootstrap {
    @MainActor
    static func makeAppModel() -> AppModel {
        do {
            return AppModel(client: try AppAPIClient.live())
        } catch {
            return AppModel(client: BootstrapFailureAppAPIClient(underlyingError: error))
        }
    }
}

private struct BootstrapFailureAppAPIClient: AppAPIClientProtocol {
    let underlyingError: Error

    func fetchHealth() async throws -> AppHealth {
        throw underlyingError
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        throw underlyingError
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        throw underlyingError
    }

    func search(query: String) async throws -> [AppSearchResult] {
        throw underlyingError
    }

    func fetchProjects() async throws -> [Project] {
        throw underlyingError
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        throw underlyingError
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        throw underlyingError
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        throw underlyingError
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        throw underlyingError
    }
}
