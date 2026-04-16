import Hummingbird
import HummingbirdTesting
import XCTest
@testable import CoreAPI

final class HealthRouteTests: XCTestCase {
    func test_health_endpoint_returns_ok() async throws {
        let app = try TestApp.make()

        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(String(buffer: response.body), #"{"status":"ok"}"#)
            }
        }
    }
}
