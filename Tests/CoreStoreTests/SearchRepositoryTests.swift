import XCTest
@testable import CoreStore

final class SearchRepositoryTests: XCTestCase {
    func test_search_returns_handoff_and_message_hits() throws {
        let db = try TestDatabase.seeded()
        let results = try SearchRepository(db).search("webhook auth")

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(Set(results.map(\.objectType)), ["handoff", "message"])
    }
}
