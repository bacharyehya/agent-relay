import SwiftUI

struct AgentListView: View {
    var body: some View {
        ContentUnavailableView(
            "Agent Directory Coming Soon",
            systemImage: "person.2",
            description: Text("Agent discovery is not wired to the core service yet, so the app avoids showing fake participants.")
        )
        .navigationTitle("Agents")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
