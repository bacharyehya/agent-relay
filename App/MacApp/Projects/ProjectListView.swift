import AppCore
import SwiftUI

struct ProjectListView: View {
    let projects: [Project]
    @Binding var selection: String?

    var body: some View {
        List(projects, selection: $selection) { project in
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                Text(project.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(project.id)
        }
        .navigationTitle("Projects")
    }
}
