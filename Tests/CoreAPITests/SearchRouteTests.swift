import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import CoreAPI

final class SearchRouteTests: XCTestCase {
    func test_search_route_returns_indexed_handoffs_and_messages() async throws {
        let app = try TestApp.make()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/search?q=webhook auth",
                method: .get,
                headers: TestApp.authorizedHeaders
            ) { response in
                let results = try Self.decode([SearchResultPayload].self, from: response.body)
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(Set(results.map(\.objectType)), ["handoff", "message"])
            }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let data = Data(buffer.readableBytesView)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct SearchResultPayload: Decodable {
    let objectID: String
    let objectType: String
    let body: String

    private enum CodingKeys: String, CodingKey {
        case objectID = "objectID"
        case objectType = "objectType"
        case body
    }
}
