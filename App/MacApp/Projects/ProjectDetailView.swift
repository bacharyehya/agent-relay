import SwiftUI

struct ProjectDetailView: View {
    @State private var model: ProjectDetailViewModel

    init(client: any AppAPIClientProtocol, projectID: String) {
        _model = State(initialValue: ProjectDetailViewModel(client: client, projectID: projectID))
    }

    var body: some View {
        @Bindable var bindableModel = model

        HSplitView {
            ThreadListView(
                threads: model.threads,
                selection: $bindableModel.selectedThreadID
            ) { thread in
                Task {
                    await model.selectThread(thread)
                }
            }

            ThreadDetailView(context: model.threadContext)
        }
        .task {
            await model.load()
        }
    }
}
