import AppCore
import Foundation

enum PreviewData {
    @MainActor
    static func makeAppModel() -> AppModel {
        AppModel(client: PreviewAppAPIClient())
    }
}

private struct PreviewAppAPIClient: AppAPIClientProtocol {
    func fetchHealth() async throws -> AppHealth {
        AppHealth(status: "ok")
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        [
            Handoff.example(id: "handoff-preview-blocked", status: .blocked, title: "Confirm missing scope"),
            Handoff.example(id: "handoff-preview-open", status: .open, title: "Patch webhook auth"),
        ]
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        [
            AppRecentItem(
                eventID: "event-preview-1",
                type: .handoffBlocked,
                threadID: "thread-api",
                handoffID: "handoff-preview-blocked",
                body: "Blocked waiting on token scope confirmation.",
                createdAt: .now
            )
        ]
    }

    func search(query: String) async throws -> [AppSearchResult] {
        [
            AppSearchResult(
                objectID: "handoff-preview-open",
                objectType: "handoff",
                body: "Patch webhook auth and confirm scope."
            ),
            AppSearchResult(
                objectID: "message-preview-2",
                objectType: "message",
                body: "Root cause is a stale token scope."
            ),
        ]
    }

    func fetchProjects() async throws -> [Project] {
        [Project.example(id: "project-api")]
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        [.example(id: "thread-api", projectID: projectID, title: "Webhook auth bug")]
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        AppThreadContext(
            thread: .example(id: threadID, title: "Webhook auth bug"),
            messages: [
                Message.example(id: "message-preview-1", threadID: threadID),
                Message(
                    id: "message-preview-2",
                    threadID: threadID,
                    actorID: "chatgpt",
                    body: "Root cause is a stale token scope.",
                    format: .markdown
                ),
            ],
            handoffs: [
                Handoff.example(id: "handoff-preview", threadID: threadID, status: .open, title: "Confirm scope fix")
            ]
        )
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        Handoff(
            id: "handoff-preview-created",
            threadID: request.threadID,
            title: request.title,
            summary: request.summary,
            ask: request.ask,
            priority: request.priority,
            createdBy: request.createdBy,
            assignedTo: request.assignedTo,
            sourceRefs: request.sourceRefs
        )
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        var handoff = Handoff.example(id: id, status: status)
        handoff.resolution = resolution
        return handoff
    }
}
