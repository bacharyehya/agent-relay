import AppCore
import SwiftUI

struct AgentListView: View {
    private let actors: [Actor] = [
        .example(id: "chatgpt"),
        Actor(
            id: "claude",
            type: .agent,
            displayName: "Claude",
            capabilities: ["analysis", "summarization"]
        ),
        Actor(
            id: "codex-worker-3",
            type: .agent,
            displayName: "Codex Worker 3",
            capabilities: ["implementation", "verification"]
        ),
    ]

    var body: some View {
        List(actors) { actor in
            VStack(alignment: .leading, spacing: 4) {
                Text(actor.displayName)
                    .font(.headline)
                Text(actor.capabilities.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Agents")
    }
}
