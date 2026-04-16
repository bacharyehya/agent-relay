import AppCore
import SwiftUI

struct InboxView: View {
    @State private var model: InboxViewModel

    init(client: any AppAPIClientProtocol) {
        _model = State(initialValue: InboxViewModel(client: client))
    }

    var body: some View {
        @Bindable var bindableModel = model

        HSplitView {
            List(model.items, selection: $bindableModel.selectedThreadID) { handoff in
                VStack(alignment: .leading, spacing: 4) {
                    Text(handoff.title)
                        .font(.headline)
                    Text(handoff.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await model.selectThread(id: handoff.threadID)
                    }
                }
                .tag(handoff.threadID)
            }
            .navigationTitle("Inbox")

            ThreadDetailView(
                client: model.client,
                threadID: model.selectedThreadID,
                seedContext: model.selectedThreadContext
            )
        }
        .task {
            await model.load()
        }
    }
}
