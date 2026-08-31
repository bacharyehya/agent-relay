import AppCore
import Foundation
import SwiftUI

struct ThreadDetailView: View {
    let client: any AppAPIClientProtocol
    let threadID: String?
    let seedContext: AppThreadContext?
    let serviceState: AppModel.ServiceState?
    let agentStatuses: [AgentRuntimeStatus]

    init(
        client: any AppAPIClientProtocol,
        threadID: String?,
        seedContext: AppThreadContext?,
        serviceState: AppModel.ServiceState? = nil,
        agentStatuses: [AgentRuntimeStatus] = []
    ) {
        self.client = client
        self.threadID = threadID
        self.seedContext = seedContext
        self.serviceState = serviceState
        self.agentStatuses = agentStatuses
    }

    var body: some View {
        Group {
            if let threadID {
                ThreadDetailContentView(
                    client: client,
                    threadID: threadID,
                    seedContext: seedContext,
                    serviceState: serviceState,
                    agentStatuses: agentStatuses
                )
                .id(threadID)
            } else {
                ContentUnavailableView(
                    "Choose a conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select an item to open it in the room.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RelayPalette.canvas)
            }
        }
    }
}

private struct ThreadDetailContentView: View {
    @State private var model: ThreadDetailViewModel
    @State private var draftMessage = ""
    @State private var replyToMessage: Message?
    @State private var showingHandoffComposer = false
    let serviceState: AppModel.ServiceState?
    let agentStatuses: [AgentRuntimeStatus]

    init(
        client: any AppAPIClientProtocol,
        threadID: String,
        seedContext: AppThreadContext?,
        serviceState: AppModel.ServiceState?,
        agentStatuses: [AgentRuntimeStatus]
    ) {
        _model = State(
            initialValue: ThreadDetailViewModel(
                client: client,
                threadID: threadID,
                initialContext: seedContext
            )
        )
        self.serviceState = serviceState
        self.agentStatuses = agentStatuses
    }

    var body: some View {
        VStack(spacing: 0) {
            RelayRoomHeader(
                title: model.threadContext?.thread.title ?? "General",
                serviceState: serviceState,
                agentStatuses: agentStatuses,
                isRefreshing: model.isRefreshingMessages,
                onRefresh: {
                    Task { await model.refreshMessages() }
                },
                onNewHandoff: {
                    showingHandoffComposer = true
                }
            )

            Rectangle()
                .fill(RelayPalette.hairline)
                .frame(height: 1)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        if let errorMessage = model.errorMessage {
                            RelayErrorBanner(message: errorMessage)
                        }

                        if let context = model.threadContext {
                            if context.messages.isEmpty {
                                RelayEmptyRoomView()
                                    .padding(.top, 70)
                            } else {
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

                            if !model.handoffs.isEmpty {
                                RelayHandoffShelf(
                                    handoffs: model.handoffs,
                                    onAccept: { handoff in
                                        Task { await model.acceptHandoff(id: handoff.id) }
                                    },
                                    onBlock: { handoff in
                                        Task { await model.blockHandoff(id: handoff.id) }
                                    },
                                    onRespond: { handoff, body in
                                        Task { await model.respondHandoff(id: handoff.id, body: body) }
                                    },
                                    onResolve: { handoff in
                                        Task { await model.resolveHandoff(id: handoff.id) }
                                    }
                                )
                                .padding(.top, 18)
                            }
                        } else if model.errorMessage == nil {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.threadContext?.messages.last?.id) { _, messageID in
                    guard let messageID else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        scrollProxy.scrollTo(messageID, anchor: .bottom)
                    }
                }
            }

            Rectangle()
                .fill(RelayPalette.hairline)
                .frame(height: 1)

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
        .background(RelayPalette.canvas)
        .sheet(isPresented: $showingHandoffComposer) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New handoff")
                            .font(.title2.bold())
                        Text("Create a durable assignment without cluttering the chat composer.")
                            .font(.subheadline)
                            .foregroundStyle(RelayPalette.muted)
                    }
                    Spacer()
                    Button("Close", systemImage: "xmark") {
                        showingHandoffComposer = false
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }

                HandoffComposerView { title, summary, ask, assignedTo in
                    Task {
                        await model.createHandoff(
                            title: title,
                            summary: summary,
                            ask: ask,
                            assignedTo: assignedTo
                        )
                        showingHandoffComposer = false
                    }
                }
            }
            .padding(24)
            .frame(width: 560)
            .background(RelayPalette.canvas)
            .preferredColorScheme(.dark)
        }
        .task {
            await model.loadIfNeeded()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                await model.refreshMessages()
            }
        }
    }
}

private struct RelayRoomHeader: View {
    let title: String
    let serviceState: AppModel.ServiceState?
    let agentStatuses: [AgentRuntimeStatus]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onNewHandoff: () -> Void

    private var isConnected: Bool {
        serviceState == nil || serviceState == .healthy
    }

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("GROUP CHAT")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(RelayPalette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RelayPalette.surfaceRaised, in: Capsule())
                }
                Text("You, Main, Research, and M5")
                    .font(.caption)
                    .foregroundStyle(RelayPalette.muted)
            }

            Spacer()

            HStack(spacing: -7) {
                ForEach(RelayAgentProfile.known) { profile in
                    RelayAgentAvatar(actorID: profile.id, size: 28)
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(isConnected ? RelayPalette.healthy : RelayPalette.danger)
                    .frame(width: 7, height: 7)
                Text(isConnected ? "CONNECTED" : "RECOVERING")
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
            }
            .foregroundStyle(RelayPalette.muted)

            Button(action: onNewHandoff) {
                Label("Handoff", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help("Refresh the room")
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(RelayPalette.canvas)
    }
}

private struct RelayErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(RelayPalette.danger)
        .padding(11)
        .background(RelayPalette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(RelayPalette.danger.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct RelayEmptyRoomView: View {
    var body: some View {
        VStack(spacing: 14) {
            RelayAppMark(size: 74)
            Text("The room is open")
                .font(.title2.bold())
            Text("Say hello, or mention an agent below to begin.")
                .font(.subheadline)
                .foregroundStyle(RelayPalette.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RelayHandoffShelf: View {
    let handoffs: [Handoff]
    let onAccept: (Handoff) -> Void
    let onBlock: (Handoff) -> Void
    let onRespond: (Handoff, String) -> Void
    let onResolve: (Handoff) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HANDOFFS")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(RelayPalette.faint)
                Spacer()
                Text("\(handoffs.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(RelayPalette.faint)
            }

            ForEach(handoffs) { handoff in
                HandoffCardView(
                    handoff: handoff,
                    onAccept: { onAccept(handoff) },
                    onBlock: { onBlock(handoff) },
                    onRespond: { onRespond(handoff, $0) },
                    onResolve: { onResolve(handoff) }
                )
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
        VStack(alignment: .leading, spacing: 9) {
            if let replyToMessage {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                    Text("Replying to \(RelayAgentProfile.profile(for: replyToMessage.actorID).displayName)")
                        .fontWeight(.semibold)
                    Text(replyToMessage.body)
                        .foregroundStyle(RelayPalette.muted)
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel", systemImage: "xmark", action: onCancelReply)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                }
                .font(.caption)
            }

            HStack(spacing: 7) {
                Text("MESSAGE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(RelayPalette.faint)

                ForEach(RelayAgentProfile.known) { profile in
                    Button {
                        insertMention(profile.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: profile.symbolName)
                            Text(profile.displayName)
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RelayPalette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Mention @\(profile.id)")
                }

                Spacer()

                if !mentions.isEmpty {
                    Text(mentions.map { "@\($0)" }.joined(separator: " · "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(RelayPalette.muted)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .bottom, spacing: 11) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Talk to the room…")
                            .foregroundStyle(RelayPalette.faint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 48, maxHeight: 105)
                        .padding(.horizontal, 4)
                }
                .padding(3)
                .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RelayPalette.hairline, lineWidth: 1)
                }

                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .black))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(RelayPalette.humanBubble, in: Circle())
                    .foregroundStyle(RelayPalette.humanInk)
                }
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty || isSending)
                .opacity(trimmedText.isEmpty ? 0.36 : 1)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack {
                Text("Posting as Bash")
                Spacer()
                Text("⌘↩ to send")
            }
            .font(.caption2)
            .foregroundStyle(RelayPalette.faint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(RelayPalette.sidebar)
    }

    private func insertMention(_ actorID: String) {
        guard !ThreadDetailViewModel.mentionedActorIDs(in: text).contains(actorID) else {
            return
        }
        if !text.isEmpty, text.last?.isWhitespace == false {
            text.append(" ")
        }
        text.append("@\(actorID) ")
    }
}
