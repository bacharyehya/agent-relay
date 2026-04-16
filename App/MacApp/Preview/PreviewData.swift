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
}
