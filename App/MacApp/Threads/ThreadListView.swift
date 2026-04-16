import AppCore
import SwiftUI

struct ThreadListView: View {
    let threads: [AppCore.Thread]
    @Binding var selection: String?
    let onSelect: (AppCore.Thread) -> Void

    var body: some View {
        List(threads, selection: $selection) { thread in
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.headline)
                Text(thread.intentType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selection = thread.id
                onSelect(thread)
            }
            .tag(thread.id)
        }
        .navigationTitle("Threads")
    }
}
