import SwiftUI

struct PauseAgentsView: View {
    let controller: ServiceController

    var body: some View {
        Toggle(
            "Pause agent access",
            isOn: Binding(
                get: { controller.agentAccessPaused },
                set: { paused in
                    Task {
                        try? await controller.setAgentAccessPaused(paused)
                    }
                }
            )
        )
        .toggleStyle(.switch)
    }
}
