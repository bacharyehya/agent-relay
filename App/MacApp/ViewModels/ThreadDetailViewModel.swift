import AppCore
import Foundation
import Observation

@MainActor
@Observable
final class ThreadDetailViewModel {
    let client: any AppAPIClientProtocol
    let threadID: String
    var threadContext: AppThreadContext?
    var errorMessage: String?
    var isRefreshingMessages = false
    var isSendingMessage = false
    private var pendingPost: (body: String, replyToMessageID: String?, idempotencyKey: String)?

    init(
        client: any AppAPIClientProtocol,
        threadID: String,
        initialContext: AppThreadContext? = nil
    ) {
        self.client = client
        self.threadID = threadID
        self.threadContext = initialContext
    }

    var handoffs: [Handoff] {
        threadContext?.handoffs ?? []
    }

    func loadIfNeeded() async {
        if threadContext == nil {
            await loadContext()
        }
        guard threadContext != nil else {
            return
        }

        await refreshMessages()
    }

    func refreshMessages() async {
        guard !isRefreshingMessages else {
            return
        }
        if threadContext == nil {
            await loadContext()
        }
        guard threadContext != nil else {
            return
        }

        isRefreshingMessages = true
        defer { isRefreshingMessages = false }
        do {
            threadContext?.messages = try await client.fetchThreadMessages(
                threadID: threadID,
                limit: 100,
                before: nil
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func postMessage(body: String, replyToMessageID: String?) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty, !isSendingMessage else {
            return false
        }
        guard await ensureContextLoaded() else {
            return false
        }

        isSendingMessage = true
        defer { isSendingMessage = false }
        let idempotencyKey: String
        if let pendingPost,
           pendingPost.body == trimmedBody,
           pendingPost.replyToMessageID == replyToMessageID
        {
            idempotencyKey = pendingPost.idempotencyKey
        } else {
            idempotencyKey = UUID().uuidString.lowercased()
            pendingPost = (trimmedBody, replyToMessageID, idempotencyKey)
        }
        do {
            let message = try await client.postMessage(
                threadID: threadID,
                request: AppPostMessageRequest(
                    actorID: "bash",
                    body: trimmedBody,
                    format: .markdown,
                    replyToMessageID: replyToMessageID,
                    mentionedActorIDs: Self.mentionedActorIDs(in: trimmedBody),
                    idempotencyKey: idempotencyKey
                )
            )
            upsert(message)
            pendingPost = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func mentionedActorIDs(in body: String) -> [String] {
        let fragments = body.split { character in
            !(character.isLetter || character.isNumber || character == "@" || character == "_" || character == "-")
        }
        var mentions: [String] = []
        var seen = Set<String>()
        for fragment in fragments where fragment.first == "@" {
            let actorID = String(fragment.dropFirst())
            guard !actorID.isEmpty, !actorID.contains("@"), seen.insert(actorID).inserted else {
                continue
            }
            mentions.append(actorID)
        }
        return mentions
    }

    func acceptHandoff(id: String) async {
        await updateHandoff(id: id, status: .accepted, resolution: nil)
    }

    func blockHandoff(id: String) async {
        await updateHandoff(id: id, status: .blocked, resolution: nil)
    }

    func respondHandoff(id: String, body: String) async {
        await updateHandoff(id: id, status: .responded, resolution: body)
    }

    func resolveHandoff(id: String) async {
        await updateHandoff(id: id, status: .resolved, resolution: nil)
    }

    func createHandoff(title: String, summary: String, ask: String, assignedTo: String) async {
        guard await ensureContextLoaded() else {
            return
        }

        do {
            let handoff = try await client.createHandoff(
                AppCreateHandoffRequest(
                    threadID: threadID,
                    title: title,
                    summary: summary,
                    ask: ask,
                    priority: .medium,
                    createdBy: "human",
                    assignedTo: assignedTo,
                    sourceRefs: []
                )
            )
            threadContext?.handoffs.insert(handoff, at: 0)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }
    }

    private func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async {
        guard await ensureContextLoaded() else {
            return
        }

        do {
            let updated = try await client.updateHandoff(id: id, status: status, resolution: resolution)
            replace(updated)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }
    }

    private func ensureContextLoaded() async -> Bool {
        if threadContext == nil {
            await loadContext()
        }
        return threadContext != nil
    }

    private func loadContext() async {
        do {
            threadContext = try await client.fetchThreadContext(threadID: threadID, mode: "recent")
            errorMessage = nil
        } catch {
            threadContext = nil
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ handoff: Handoff) {
        guard let index = threadContext?.handoffs.firstIndex(where: { $0.id == handoff.id }) else {
            return
        }
        threadContext?.handoffs[index] = handoff
    }

    private func upsert(_ message: Message) {
        guard threadContext != nil else {
            return
        }
        if let index = threadContext?.messages.firstIndex(where: { $0.id == message.id }) {
            threadContext?.messages[index] = message
        } else {
            threadContext?.messages.append(message)
        }
        threadContext?.messages.sort {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
