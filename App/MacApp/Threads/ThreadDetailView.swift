import AppCore
import Foundation
import SwiftUI

struct ThreadDetailView: View {
    let client: any AppAPIClientProtocol
    let threadID: String?
    let seedContext: AppThreadContext?

    var body: some View {
        Group {
            if let threadID {
                ThreadDetailContentView(client: client, threadID: threadID, seedContext: seedContext)
                    .id(threadID)
            } else {
                ScrollView {
                    Text("Select a thread to see recent messages and handoffs.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
    }
}

private struct ThreadDetailContentView: View {
    @State private var model: ThreadDetailViewModel
    @State private var draftMessage = ""
    @State private var replyToMessage: Message?

    init(
        client: any AppAPIClientProtocol,
        threadID: String,
        seedContext: AppThreadContext?
    ) {
        _model = State(
            initialValue: ThreadDetailViewModel(
                client: client,
                threadID: threadID,
                initialContext: seedContext
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Text(model.threadContext?.thread.title ?? "Select a thread")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Spacer()

                            Button {
                                Task {
                                    await model.refreshMessages()
                                }
                            } label: {
                                if model.isRefreshingMessages {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(model.isRefreshingMessages)
                            .help("Refresh this conversation")
                        }

                        if let errorMessage = model.errorMessage, model.threadContext == nil {
                            ContentUnavailableView(
                                "Thread Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(errorMessage)
                            )
                        } else {
                            HandoffComposerView { title, summary, ask, assignedTo in
                                Task {
                                    await model.createHandoff(
                                        title: title,
                                        summary: summary,
                                        ask: ask,
                                        assignedTo: assignedTo
                                    )
                                }
                            }

                            if let errorMessage = model.errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            if let context = model.threadContext {
                                if context.messages.isEmpty {
                                    ContentUnavailableView(
                                        "No Messages Yet",
                                        systemImage: "bubble.left.and.bubble.right",
                                        description: Text("Start the conversation below or mention an agent with @name.")
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(context.messages) { message in
                                            MessageRowView(
                                                message: message,
                                                replyToMessage: context.messages.first {
                                                    $0.id == message.replyToMessageID
                                                },
                                                onReply: {
                                                    replyToMessage = message
                                                }
                                            )
                                            .id(message.id)
                                        }
                                    }
                                }

                                if !model.handoffs.isEmpty {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Handoffs")
                                            .font(.headline)

                                        ForEach(model.handoffs) { handoff in
                                            HandoffCardView(
                                                handoff: handoff,
                                                onAccept: {
                                                    Task {
                                                        await model.acceptHandoff(id: handoff.id)
                                                    }
                                                },
                                                onBlock: {
                                                    Task {
                                                        await model.blockHandoff(id: handoff.id)
                                                    }
                                                },
                                                onRespond: { body in
                                                    Task {
                                                        await model.respondHandoff(id: handoff.id, body: body)
                                                    }
                                                },
                                                onResolve: {
                                                    Task {
                                                        await model.resolveHandoff(id: handoff.id)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onChange(of: model.threadContext?.messages.last?.id) { _, messageID in
                    guard let messageID else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(messageID, anchor: .bottom)
                    }
                }
            }

            Divider()

            ThreadMessageComposer(
                text: $draftMessage,
                replyToMessage: replyToMessage,
                isSending: model.isSendingMessage,
                onCancelReply: {
                    replyToMessage = nil
                },
                onSend: {
                    let body = draftMessage
                    let replyToMessageID = replyToMessage?.id
                    Task {
                        if await model.postMessage(body: body, replyToMessageID: replyToMessageID) {
                            draftMessage = ""
                            replyToMessage = nil
                        }
                    }
                }
            )
        }
        .task {
            await model.loadIfNeeded()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    break
                }
                await model.refreshMessages()
            }
        }
    }
}

private struct ThreadMessageComposer: View {
    @Binding var text: String
    let replyToMessage: Message?
    let isSending: Bool
    let onCancelReply: () -> Void
    let onSend: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mentions: [String] {
        ThreadDetailViewModel.mentionedActorIDs(in: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyToMessage {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                    Text("Replying to \(replyToMessage.actorID == "bash" ? "Bash" : replyToMessage.actorID)")
                        .font(.caption.weight(.semibold))
                    Text(replyToMessage.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel", systemImage: "xmark", action: onCancelReply)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Message the room — use @agent to mention someone")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 54, maxHeight: 110)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedText.isEmpty || isSending)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            if !mentions.isEmpty {
                Text("Mentioning \(mentions.map { "@\($0)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("You are posting as Bash. Command-Return sends.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
