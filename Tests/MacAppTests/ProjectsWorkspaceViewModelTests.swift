import XCTest
@testable import AppCore
@testable import MacAppSupport

@MainActor
final class ProjectsWorkspaceViewModelTests: XCTestCase {
    func test_load_selects_first_project_when_none_is_selected() async {
        let client = StubProjectsAppAPIClient(
            projects: [
                Project(
                    id: "project-a",
                    title: "Alpha",
                    summary: "First project",
                    status: .active,
                    createdAt: .now,
                    updatedAt: .now
                ),
                Project(
                    id: "project-b",
                    title: "Beta",
                    summary: "Second project",
                    status: .active,
                    createdAt: .now,
                    updatedAt: .now
                ),
            ]
        )
        let model = ProjectsWorkspaceViewModel(client: client)

        await model.load()

        XCTAssertEqual(model.projects.map(\.id), ["project-a", "project-b"])
        XCTAssertEqual(model.selectedProjectID, "project-a")
    }

    func test_load_records_error_when_project_fetch_fails() async {
        let client = StubProjectsAppAPIClient(
            projects: [],
            projectsError: URLError(.cannotConnectToHost)
        )
        let model = ProjectsWorkspaceViewModel(client: client)

        await model.load()

        XCTAssertEqual(model.projects, [])
        XCTAssertNil(model.selectedProjectID)
        XCTAssertNotNil(model.errorMessage)
    }
}

private struct StubProjectsAppAPIClient: AppAPIClientProtocol {
    let projects: [Project]
    let projectsError: Error?

    init(projects: [Project], projectsError: Error? = nil) {
        self.projects = projects
        self.projectsError = projectsError
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
        if let projectsError {
            throw projectsError
        }
        return projects
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
