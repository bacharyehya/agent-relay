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
}
