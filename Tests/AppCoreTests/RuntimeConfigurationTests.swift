import Foundation
import XCTest
@testable import AppCore

final class RuntimeConfigurationTests: XCTestCase {
    func test_loadOrCreateAuthToken_generatesStableNonDefaultToken() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let first = try AppRuntimeConfiguration.loadOrCreateAuthToken(
            environment: [:],
            supportDirectory: rootDirectory
        )
        let second = try AppRuntimeConfiguration.loadOrCreateAuthToken(
            environment: [:],
            supportDirectory: rootDirectory
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, "dev-token")
        XCTAssertGreaterThan(first.count, 32)
    }

    func test_loadOrCreateAuthToken_handlesSpacesAndRepairsExistingPermissions() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Agent Relay \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let tokenURL = rootDirectory.appendingPathComponent(
            AppRuntimeConfiguration.authTokenFileName,
            isDirectory: false
        )
        try "existing-token".write(to: tokenURL, atomically: true, encoding: .utf8)
        let tokenPath = tokenURL.path(percentEncoded: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: tokenPath
        )

        let token = try AppRuntimeConfiguration.loadOrCreateAuthToken(
            environment: [:],
            supportDirectory: rootDirectory
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenPath)

        XCTAssertEqual(token, "existing-token")
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func test_databaseURL_uses_support_directory_instead_of_working_directory() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let databaseURL = try AppRuntimeConfiguration.databaseURL(
            environment: [:],
            supportDirectory: rootDirectory
        )

        XCTAssertEqual(databaseURL.deletingLastPathComponent(), rootDirectory)
        XCTAssertEqual(databaseURL.lastPathComponent, "agent-relay.sqlite")
    }

    func test_loadOrCreateAuthToken_prefers_environment_override() throws {
        let token = try AppRuntimeConfiguration.loadOrCreateAuthToken(
            environment: ["AGENT_RELAY_AUTH_TOKEN": "explicit-token"],
            supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        XCTAssertEqual(token, "explicit-token")
    }

    func test_actor_credentials_are_stable_independent_and_scoped() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Agent Relay \(UUID().uuidString)", isDirectory: true)
        let store = try ActorCredentialStore(supportDirectory: rootDirectory)

        let bashCredential = try store.loadOrCreate(actorID: "bash")
        let repeatedBashCredential = try store.loadOrCreate(actorID: "bash")
        let agentCredential = try store.loadOrCreate(actorID: "codex-main")

        XCTAssertEqual(bashCredential, repeatedBashCredential)
        XCTAssertNotEqual(bashCredential, agentCredential)
        XCTAssertTrue(store.validates(credential: bashCredential, actorID: "bash"))
        XCTAssertFalse(store.validates(credential: bashCredential, actorID: "codex-main"))
        XCTAssertThrowsError(try store.loadOrCreate(actorID: "../escape"))

        let credentialURL = rootDirectory
            .appendingPathComponent(ActorCredentialStore.directoryName, isDirectory: true)
            .appendingPathComponent("bash", isDirectory: false)
        let credentialPath = credentialURL.path(percentEncoded: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: credentialPath
        )

        XCTAssertEqual(try store.load(actorID: "bash"), bashCredential)
        let attributes = try FileManager.default.attributesOfItem(atPath: credentialPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
