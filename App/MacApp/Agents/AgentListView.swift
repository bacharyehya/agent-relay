import AppCore
import SwiftUI

struct AgentListView: View {
    let statuses: [AgentRuntimeStatus]

    init(statuses: [AgentRuntimeStatus] = []) {
        self.statuses = statuses
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THE ROOM")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(RelayPalette.faint)
                    Text("Meet your agents")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("They share one visible conversation, but each has a deliberately different job.")
                        .font(.subheadline)
                        .foregroundStyle(RelayPalette.muted)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(RelayAgentProfile.known) { profile in
                        RelayAgentCard(
                            profile: profile,
                            status: statuses.first(where: { $0.actorID == profile.id })
                        )
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(RelayPalette.muted)
                    Text("Only the messages agents deliberately post are visible here. Private chain-of-thought is never copied into the room.")
                        .font(.caption)
                        .foregroundStyle(RelayPalette.muted)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(32)
        }
        .background(RelayPalette.canvas)
    }
}

private struct RelayAgentCard: View {
    let profile: RelayAgentProfile
    let status: AgentRuntimeStatus?

    private var statusLabel: String {
        if let status { return status.phase.relayLabel }
        return profile.id == RelayAgentProfile.m5.id ? "Remote" : "Starting"
    }

    private var statusColor: Color {
        if let status { return status.phase.relayColor }
        return profile.id == RelayAgentProfile.m5.id ? RelayPalette.warning : RelayPalette.faint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 13) {
                RelayAgentAvatar(actorID: profile.id, size: 43)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.title3.weight(.bold))
                    Text("@\(profile.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(RelayPalette.faint)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                }
            }

            Text(profile.role.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.1)
                .foregroundStyle(RelayPalette.muted)

            Text(profile.summary)
                .font(.subheadline)
                .foregroundStyle(RelayPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Label(profile.machine, systemImage: "laptopcomputer")
                Spacer()
                Text(status?.detail ?? (profile.id == RelayAgentProfile.m5.id ? "Connected over SSH" : "Waiting for runtime"))
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(RelayPalette.faint)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RelayPalette.hairline, lineWidth: 1)
        }
    }
}
