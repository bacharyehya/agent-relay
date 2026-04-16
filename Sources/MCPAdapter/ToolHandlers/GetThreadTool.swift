import Foundation

struct GetThreadTool {
    let client: any CoreAPIClientProtocol

    func run(threadID: String, mode: String = "recent") async throws -> String {
        let context = try await client.getThread(threadID: threadID, mode: mode)
        let messageLines = context.messages.map { "\($0.actorID): \($0.body)" }
        let handoffLines = context.handoffs.map { "[\($0.status.rawValue)] \($0.title)" }

        return [
            "Thread: \(context.thread.title)",
            "Messages:",
            messageLines.isEmpty ? "(none)" : messageLines.joined(separator: "\n"),
            "Handoffs:",
            handoffLines.isEmpty ? "(none)" : handoffLines.joined(separator: "\n"),
        ].joined(separator: "\n")
    }
}
