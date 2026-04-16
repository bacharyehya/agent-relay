import SwiftUI

struct SearchView: View {
    @State private var model: InboxViewModel
    @State private var query = ""

    init(client: any AppAPIClientProtocol) {
        _model = State(initialValue: InboxViewModel(client: client))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search handoffs and messages", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await model.runSearch(query)
                        }
                    }

                Button("Search") {
                    Task {
                        await model.runSearch(query)
                    }
                }
            }

            List(model.searchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.objectType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.body)
                        .font(.body)
                        .lineLimit(3)
                }
            }
        }
        .padding(20)
        .navigationTitle("Search")
    }
}
