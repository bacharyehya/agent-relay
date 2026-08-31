import XCTest
@testable import RelayCloudUI

@MainActor
final class RelayCloudModelCapabilityTests: XCTestCase {
    func test_storeClientDoesNotExposeLocalAgentHostingByDefault() async {
        let model = RelayCloudModel()

        XCTAssertFalse(model.allowsLocalAgentHosting)
        await model.installLocalMacAgents()
        XCTAssertEqual(
            model.errorMessage,
            "Install and open Agent Relay Host to connect a Codex agent on this Mac."
        )
    }

    func test_hostMustOptIntoLocalAgentHostingExplicitly() {
        let model = RelayCloudModel(allowsLocalAgentHosting: true)

        XCTAssertTrue(model.allowsLocalAgentHosting)
    }
}
