import AppCore
import SwiftUI

struct MentionsView: View {
    let messages: [Message]
    let onOpenRoom: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATTENTION")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(RelayPalette.faint)
                    Text("Mentions")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Direct @mentions across your active rooms. Formal handoffs remain a separate durable workflow.")
                        .font(.subheadline)
                        .foregroundStyle(RelayPalette.muted)
                }

                if messages.isEmpty {
                    ContentUnavailableView(
                        "Nothing needs you",
                        systemImage: "at",
                        description: Text("New direct mentions will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach(messages) { message in
                            Button(action: onOpenRoom) {
                                HStack(alignment: .top, spacing: 13) {
                                    RelayAgentAvatar(actorID: message.actorID, size: 38)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(message.actorID == "bash" ? "Bash" : RelayAgentProfile.profile(for: message.actorID).displayName)
                                                .font(.headline)
                                            Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(RelayPalette.faint)
                                            Spacer()
                                            Label("General", systemImage: "number")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(RelayPalette.muted)
                                        }

                                        Text(message.body)
                                            .font(.subheadline)
                                            .foregroundStyle(RelayPalette.ink)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(RelayPalette.hairline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(32)
        }
        .background(RelayPalette.canvas)
    }
}
