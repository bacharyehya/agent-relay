import AppCore
import Observation

@MainActor
@Observable
final class ThreadDetailViewModel {
    let client: any AppAPIClientProtocol
    let threadID: String
    var threadContext: AppThreadContext?
    var errorMessage: String?

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
        guard threadContext == nil else {
            return
        }

        do {
            threadContext = try await client.fetchThreadContext(threadID: threadID, mode: "recent")
            errorMessage = nil
        } catch {
            threadContext = nil
            errorMessage = error.localizedDescription
        }
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
            await loadIfNeeded()
        }
        return threadContext != nil
    }

    private func replace(_ handoff: Handoff) {
        guard let index = threadContext?.handoffs.firstIndex(where: { $0.id == handoff.id }) else {
            return
        }
        threadContext?.handoffs[index] = handoff
    }
}
