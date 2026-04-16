import XCTest
@testable import MacAppSupport

@MainActor
final class ServiceControllerTests: XCTestCase {
    func test_service_controller_reports_paused_when_agent_access_is_disabled() async throws {
        let controller = ServiceController(storage: .inMemory)

        try await controller.setAgentAccessPaused(true)

        let paused = try await controller.isAgentAccessPaused()

        XCTAssertTrue(paused)
    }
}
