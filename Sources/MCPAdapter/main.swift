import Foundation

let server = MCPServer(
    client: try CoreAPIClient.live(),
    actorID: ProcessInfo.processInfo.environment["AGENT_RELAY_ACTOR_ID"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
)

try await server.run()
