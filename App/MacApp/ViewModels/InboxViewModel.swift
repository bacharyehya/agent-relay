import AppCore
import Observation

@MainActor
@Observable
final class InboxViewModel {
    let client: any AppAPIClientProtocol
    let actorID: String

    var items: [Handoff] = []
    var recentItems: [AppRecentItem] = []
    var searchResults: [AppSearchResult] = []
    var selectedThreadID: String?
    var selectedThreadContext: AppThreadContext?

    init(client: any AppAPIClientProtocol, actorID: String = "chatgpt") {
        self.client = client
        self.actorID = actorID
    }

    func load() async {
        do {
            let inbox = try await client.fetchInbox(actorID: actorID)
            items = inbox.sorted(by: isHigherPriority(_:_:))
            if let first = items.first {
                await selectThread(id: first.threadID)
            } else {
                selectedThreadID = nil
                selectedThreadContext = nil
            }
        } catch {
            items = []
            selectedThreadID = nil
            selectedThreadContext = nil
        }
    }

    func loadRecents() async {
        do {
            recentItems = try await client.fetchRecents()
        } catch {
            recentItems = []
        }
    }

    func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try await client.search(query: trimmed)
        } catch {
            searchResults = []
        }
    }

    func selectThread(id: String?) async {
        guard let id else {
            selectedThreadID = nil
            selectedThreadContext = nil
            return
        }

        selectedThreadID = id
        do {
            selectedThreadContext = try await client.fetchThreadContext(threadID: id, mode: "recent")
        } catch {
            selectedThreadContext = nil
        }
    }

    private func isHigherPriority(_ lhs: Handoff, _ rhs: Handoff) -> Bool {
        statusRank(lhs.status) < statusRank(rhs.status)
    }

    private func statusRank(_ status: HandoffStatus) -> Int {
        switch status {
        case .blocked:
            return 0
        case .open:
            return 1
        case .accepted:
            return 2
        case .responded:
            return 3
        case .resolved:
            return 4
        case .canceled:
            return 5
        }
    }
}
