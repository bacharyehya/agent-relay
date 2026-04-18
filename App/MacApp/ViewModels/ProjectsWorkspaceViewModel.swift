import AppCore
import Observation

@MainActor
@Observable
final class ProjectsWorkspaceViewModel {
    let client: any AppAPIClientProtocol
    var projects: [Project] = []
    var selectedProjectID: String?
    var errorMessage: String?

    init(client: any AppAPIClientProtocol) {
        self.client = client
    }

    func load() async {
        do {
            projects = try await client.fetchProjects()
            errorMessage = nil
            if let selectedProjectID,
               projects.contains(where: { $0.id == selectedProjectID })
            {
                return
            }
            selectedProjectID = projects.first?.id
        } catch {
            projects = []
            selectedProjectID = nil
            errorMessage = error.localizedDescription
        }
    }
}
