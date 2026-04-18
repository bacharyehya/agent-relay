import SwiftUI

struct ProjectsWorkspaceView: View {
    let client: any AppAPIClientProtocol
    @State private var model: ProjectsWorkspaceViewModel

    init(client: any AppAPIClientProtocol) {
        self.client = client
        _model = State(initialValue: ProjectsWorkspaceViewModel(client: client))
    }

    var body: some View {
        @Bindable var bindableModel = model

        Group {
            if let errorMessage = model.errorMessage, model.projects.isEmpty {
                ContentUnavailableView(
                    "Projects Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                HSplitView {
                    ProjectListView(
                        projects: model.projects,
                        selection: $bindableModel.selectedProjectID
                    )

                    if let projectID = model.selectedProjectID {
                        ProjectDetailView(client: client, projectID: projectID)
                            .id(projectID)
                    } else {
                        ContentUnavailableView(
                            "No Projects",
                            systemImage: "square.grid.2x2",
                            description: Text("Create or sync a project to start collaborating.")
                        )
                    }
                }
            }
        }
        .task {
            await model.load()
        }
    }
}
