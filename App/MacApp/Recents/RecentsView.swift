import SwiftUI

struct RecentsView: View {
    @State private var model: InboxViewModel

    init(client: any AppAPIClientProtocol) {
        _model = State(initialValue: InboxViewModel(client: client))
    }

    var body: some View {
        HSplitView {
            List(model.recentItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.body)
                        .font(.headline)
                    Text(item.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        await model.selectThread(id: item.threadID)
                    }
                }
            }
            .navigationTitle("Recents")

            ThreadDetailView(
                client: model.client,
                threadID: model.selectedThreadID,
                seedContext: model.selectedThreadContext
            )
        }
        .task {
            await model.loadRecents()
        }
    }
}
