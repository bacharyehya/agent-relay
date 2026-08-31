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

    func test_cloud_sync_is_push_driven_and_only_local_outbox_is_scanned() {
        XCTAssertTrue(RelayCloudModel.usesPushDrivenCloudSync)
        XCTAssertEqual(RelayCloudModel.localOutboxScanIntervalSeconds, 1)
    }
}
