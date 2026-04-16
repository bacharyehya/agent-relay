import AppCore
import Observation

@MainActor
@Observable
final class ProjectDetailViewModel {
    let client: any AppAPIClientProtocol
    let projectID: String
    var threads: [AppCore.Thread] = []
    var selectedThreadID: String?
    var threadContext: AppThreadContext?

    init(client: any AppAPIClientProtocol, projectID: String) {
        self.client = client
        self.projectID = projectID
    }

    func load() async {
        do {
            threads = try await client.fetchProjectThreads(projectID: projectID)
            if let firstThread = threads.first {
                selectedThreadID = firstThread.id
                threadContext = try await client.fetchThreadContext(threadID: firstThread.id, mode: "recent")
            }
        } catch {
            threads = []
            threadContext = nil
        }
    }

    func selectThread(_ thread: AppCore.Thread) async {
        selectedThreadID = thread.id
        do {
            threadContext = try await client.fetchThreadContext(threadID: thread.id, mode: "recent")
        } catch {
            threadContext = nil
        }
    }
}
