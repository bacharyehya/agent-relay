import Foundation

struct ListInboxTool {
    let client: any CoreAPIClientProtocol

    func run(actorID: String) async throws -> String {
        let items = try await client.listInbox(actorID: actorID)
        guard !items.isEmpty else {
            return "Inbox is empty for \(actorID)."
        }

        return items
            .map { "- [\($0.status.rawValue)] \($0.title)" }
            .joined(separator: "\n")
    }
}
