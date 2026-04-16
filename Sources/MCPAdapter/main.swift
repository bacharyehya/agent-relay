import Foundation

let environment = ProcessInfo.processInfo.environment
let baseURL = URL(string: environment["AGENT_RELAY_CORE_URL"] ?? "http://127.0.0.1:8080")!
let authToken = environment["AGENT_RELAY_AUTH_TOKEN"] ?? "dev-token"
let server = MCPServer(
    client: CoreAPIClient(
        baseURL: baseURL,
        authToken: authToken
    )
)

try await server.run()
