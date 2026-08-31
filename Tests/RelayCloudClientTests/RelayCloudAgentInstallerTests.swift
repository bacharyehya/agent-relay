import Foundation
import XCTest
@testable import RelayCloudClient

final class RelayCloudAgentInstallerTests: XCTestCase {
    func test_installStoresIndependentTokensAndSortedRuntimeConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try RelayCloudAgentInstaller.install(
            serverURL: fixture.serverURL,
            roomID: "room-general",
            actorID: "codex-m5",
            token: fixture.token(suffix: "m5"),
            environment: fixture.environment
        )
        let configuration = try RelayCloudAgentInstaller.install(
            serverURL: fixture.serverURL,
            roomID: "room-general",
            actorID: "codex-design",
            token: fixture.token(suffix: "design"),
            environment: fixture.environment
        )

        XCTAssertEqual(configuration.actorIDs, ["codex-design", "codex-m5"])
        XCTAssertEqual(try RelayCloudAgentInstaller.load(environment: fixture.environment), configuration)

        for actorID in configuration.actorIDs {
            let tokenURL = try RelayCloudAgentInstaller.tokenFileURL(
                actorID: actorID,
                environment: fixture.environment
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path())
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }

        let agentDirectory = fixture.root.appendingPathComponent(
            RelayCloudAgentInstaller.directoryName,
            isDirectory: true
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: agentDirectory.path())
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func test_installRejectsDifferentRelayWithoutWritingTheNewActorToken() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try RelayCloudAgentInstaller.install(
            serverURL: fixture.serverURL,
            roomID: "room-general",
            actorID: "codex-main",
            token: fixture.token(suffix: "main"),
            environment: fixture.environment
        )

        XCTAssertThrowsError(
            try RelayCloudAgentInstaller.install(
                serverURL: URL(string: "https://other-relay.example")!,
                roomID: "room-general",
                actorID: "codex-m5",
                token: fixture.token(suffix: "m5"),
                environment: fixture.environment
            )
        ) { error in
            XCTAssertEqual(error as? RelayCloudAgentInstallerError, .differentRelayAlreadyConfigured)
        }

        let rejectedTokenURL = try RelayCloudAgentInstaller.tokenFileURL(
            actorID: "codex-m5",
            environment: fixture.environment
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedTokenURL.path()))
    }

    func test_installRejectsUnsafeActorAndMalformedToken() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(
            try RelayCloudAgentInstaller.install(
                serverURL: fixture.serverURL,
                roomID: "room-general",
                actorID: "../escape",
                token: fixture.token(suffix: "bad-actor"),
                environment: fixture.environment
            )
        ) { error in
            XCTAssertEqual(error as? RelayCloudAgentInstallerError, .invalidActorID)
        }

        XCTAssertThrowsError(
            try RelayCloudAgentInstaller.install(
                serverURL: fixture.serverURL,
                roomID: "room-general",
                actorID: "codex-m5",
                token: "not-an-agent-token",
                environment: fixture.environment
            )
        ) { error in
            XCTAssertEqual(error as? RelayCloudAgentInstallerError, .invalidAgentToken)
        }
    }
}

private struct Fixture {
    let root: URL
    let environment: [String: String]
    let serverURL = URL(string: "https://relay.example")!

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentRelayInstallerTests-\(UUID().uuidString)", isDirectory: true)
        environment = ["AGENT_RELAY_SUPPORT_DIR": root.path()]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func token(suffix: String) -> String {
        "relay_agent_abcdefghijklmnopqrstuvwxyz0123456789_\(suffix)"
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
