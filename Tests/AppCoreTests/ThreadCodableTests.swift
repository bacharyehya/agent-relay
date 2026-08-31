import Foundation
import XCTest
@testable import AppCore

final class ThreadCodableTests: XCTestCase {
    func test_round_trip_preserves_fractional_updated_timestamp() throws {
        let original = AppCore.Thread(
            id: "thread-precise",
            projectID: "project-1",
            title: "Precise thread",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000.789)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppCore.Thread.self, from: data)

        XCTAssertEqual(decoded.updatedAt, original.updatedAt)
        XCTAssertNotNil(
            String(decoding: data, as: UTF8.self).range(
                of: #"\.\d{9}Z"#,
                options: .regularExpression
            )
        )
    }

    func test_decoding_legacy_numeric_updated_timestamp() throws {
        let json = #"{"id":"thread-1","projectID":"project-1","title":"Legacy","intentType":"task","status":"active","createdBy":"human","assignedActorIDs":[],"updatedAt":0}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let thread = try decoder.decode(AppCore.Thread.self, from: Data(json.utf8))

        XCTAssertEqual(thread.updatedAt, Date(timeIntervalSince1970: 0))
    }
}
