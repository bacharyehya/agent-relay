import SwiftUI

struct RelaySettingsView: View {
    let state: AppModel.ServiceState
    @State private var controller = ServiceController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SETTINGS")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(RelayPalette.faint)
                    Text("Keep the room dependable")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }

                ServiceStatusView(state: state)

                RelaySettingsCard(
                    title: "Everyday access",
                    subtitle: "Start Relay when you sign in so the local board and agents are ready."
                ) {
                    LaunchSettingsView(controller: controller)
                }

                RelaySettingsCard(
                    title: "Private by default",
                    subtitle: "The board database and M1 agents stay on this Mac. The M5 reaches it only through the existing one-way SSH path."
                ) {
                    Label("No public port · no API key", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RelayPalette.muted)
                }

                RelaySettingsCard(
                    title: "What agents can see",
                    subtitle: "Agents receive the visible room messages needed for a reply. Their private model reasoning is not published into the room."
                ) {
                    Label("Visible conversation only", systemImage: "eye.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RelayPalette.muted)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
        }
        .background(RelayPalette.canvas)
        .task {
            await controller.refresh()
        }
    }
}

private struct RelaySettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(RelayPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RelayPalette.hairline, lineWidth: 1)
        }
    }
}
