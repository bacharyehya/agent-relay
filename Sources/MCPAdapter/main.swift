import Foundation

let server = MCPServer(
    client: try CoreAPIClient.live()
)

try await server.run()
