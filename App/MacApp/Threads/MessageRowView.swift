import AppCore
import SwiftUI

struct MessageRowView: View {
    let message: Message
    let replyToMessage: Message?
    var onReply: (() -> Void)?

    private var isBashMessage: Bool {
        message.actorID == "bash" || message.actorID == "human"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isBashMessage {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(isBashMessage ? "Bash" : message.actorID)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isBashMessage ? Color.accentColor : .secondary)

                    Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 8)

                    if let onReply {
                        Button(action: onReply) {
                            Image(systemName: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reply to this message")
                    }
                }

                if let replyToMessage {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(replyToMessage.actorID == "bash" ? "Bash" : replyToMessage.actorID)")
                            .font(.caption2.weight(.semibold))
                        Text(String(replyToMessage.body.prefix(120)))
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.45))
                            .frame(width: 3)
                    }
                } else if message.replyToMessageID != nil {
                    Label("Reply to an earlier message", systemImage: "arrowshape.turn.up.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.body)
                    .font(.body)
                    .textSelection(.enabled)

                if !message.mentionedActorIDs.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "at")
                        Text(message.mentionedActorIDs.map { "@\($0)" }.joined(separator: "  "))
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: 620, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isBashMessage ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08))
            )

            if !isBashMessage {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
