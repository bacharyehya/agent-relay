import SwiftUI

struct ProjectDetailView: View {
    private let client: any AppAPIClientProtocol
    @State private var model: ProjectDetailViewModel

    init(client: any AppAPIClientProtocol, projectID: String) {
        self.client = client
        _model = State(initialValue: ProjectDetailViewModel(client: client, projectID: projectID))
    }

    var body: some View {
        @Bindable var bindableModel = model

        Group {
            if let errorMessage = model.errorMessage, model.threads.isEmpty {
                ContentUnavailableView(
                    "Project Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                HSplitView {
                    ThreadListView(
                        threads: model.threads,
                        selection: $bindableModel.selectedThreadID
                    ) { thread in
                        Task {
                            await model.selectThread(thread)
                        }
                    }

                    ThreadDetailView(
                        client: client,
                        threadID: model.selectedThreadID,
                        seedContext: model.threadContext
                    )
                }
            }
        }
        .task {
            await model.load()
        }
    }
}
