import AppCore
import SwiftUI

struct MessageRowView: View {
    let message: Message
    let replyToMessage: Message?
    var onReply: (() -> Void)?

    private var isBashMessage: Bool {
        message.actorID == "bash" || message.actorID == "human"
    }

    private var profile: RelayAgentProfile {
        isBashMessage
            ? RelayAgentProfile(
                id: "bash",
                displayName: "Bash",
                role: "Human",
                summary: "",
                machine: "",
                symbolName: "person.fill"
            )
            : RelayAgentProfile.profile(for: message.actorID)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isBashMessage {
                Spacer(minLength: 86)
            } else {
                RelayAgentAvatar(actorID: message.actorID, size: 34)
            }

            VStack(alignment: isBashMessage ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if !isBashMessage {
                        Text(profile.displayName)
                            .fontWeight(.bold)
                        Text(profile.role.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(RelayPalette.faint)
                    }

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(RelayPalette.faint)

                    if isBashMessage {
                        Text("YOU")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(RelayPalette.faint)
                    }
                }
                .font(.caption)

                VStack(alignment: .leading, spacing: 8) {
                    if let replyToMessage {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("↳ \(replyAuthor(for: replyToMessage))")
                                .font(.caption2.weight(.bold))
                            Text(String(replyToMessage.body.prefix(140)))
                                .font(.caption)
                                .lineLimit(2)
                        }
                        .foregroundStyle(isBashMessage ? Color.black.opacity(0.58) : RelayPalette.muted)
                        .padding(.leading, 9)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(isBashMessage ? Color.black.opacity(0.28) : Color.white.opacity(0.28))
                                .frame(width: 3)
                        }
                    } else if message.replyToMessageID != nil {
                        Label("Reply to an earlier message", systemImage: "arrowshape.turn.up.left")
                            .font(.caption2)
                            .foregroundStyle(isBashMessage ? Color.black.opacity(0.58) : RelayPalette.muted)
                    }

                    Text(.init(message.body))
                        .font(.body)
                        .foregroundStyle(isBashMessage ? RelayPalette.humanInk : RelayPalette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if !message.mentionedActorIDs.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "at")
                            Text(message.mentionedActorIDs.map {
                                $0.replacingOccurrences(of: "codex-", with: "")
                            }.joined(separator: " · "))
                            .lineLimit(1)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isBashMessage ? Color.black.opacity(0.54) : RelayPalette.muted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 690, alignment: .leading)
                .background(
                    isBashMessage ? RelayPalette.humanBubble : RelayPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    if !isBashMessage {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(RelayPalette.hairline, lineWidth: 1)
                    }
                }

                if let onReply {
                    Button(action: onReply) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RelayPalette.faint)
                }
            }

            if !isBashMessage {
                Spacer(minLength: 86)
            }
        }
        .frame(maxWidth: .infinity, alignment: isBashMessage ? .trailing : .leading)
    }

    private func replyAuthor(for message: Message) -> String {
        if message.actorID == "bash" || message.actorID == "human" {
            return "Bash"
        }
        return RelayAgentProfile.profile(for: message.actorID).displayName
    }
}
