import SwiftUI

struct AgentListView: View {
    private let agents = [
        (id: "codex-main", role: "General collaborator"),
        (id: "codex-research", role: "Research collaborator"),
    ]

    var body: some View {
        List(agents, id: \.id) { agent in
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(agent.id)")
                        .font(.headline)
                    Text(agent.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("ChatGPT")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .padding(.vertical, 5)
        }
        .navigationTitle("Agents")
        .safeAreaInset(edge: .bottom) {
            Text("Mention either agent in General. Only explicit board messages are visible; private model reasoning is never exposed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.bar)
        }
    }
}
