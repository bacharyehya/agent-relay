import XCTest
@testable import MacAppSupport

@MainActor
final class AppModelTests: XCTestCase {
    func test_app_model_shows_degraded_when_service_is_unreachable() async {
        let client = FailingAppAPIClient()
        let model = AppModel(client: client)

        await model.refresh()

        XCTAssertEqual(model.serviceState, .degraded)
    }
}

private struct FailingAppAPIClient: AppAPIClientProtocol {
    func fetchHealth() async throws -> AppHealth {
        throw URLError(.cannotConnectToHost)
    }
}
