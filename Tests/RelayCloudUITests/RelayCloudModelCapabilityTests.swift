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

    func test_cloud_sync_uses_bounded_backoff() {
        XCTAssertEqual(RelayCloudModel.syncDelaySeconds(consecutiveFailures: 0), 15)
        XCTAssertEqual(RelayCloudModel.syncDelaySeconds(consecutiveFailures: 1), 15)
        XCTAssertEqual(RelayCloudModel.syncDelaySeconds(consecutiveFailures: 2), 30)
        XCTAssertEqual(RelayCloudModel.syncDelaySeconds(consecutiveFailures: 3), 60)
        XCTAssertEqual(RelayCloudModel.syncDelaySeconds(consecutiveFailures: 20), 60)
    }
}
