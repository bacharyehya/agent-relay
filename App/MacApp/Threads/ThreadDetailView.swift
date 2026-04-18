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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.threadContext?.thread.title ?? "Select a thread")
                    .font(.title2)
                    .fontWeight(.semibold)

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
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(context.messages) { message in
                                MessageRowView(message: message)
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
        .task {
            await model.loadIfNeeded()
        }
    }
}
