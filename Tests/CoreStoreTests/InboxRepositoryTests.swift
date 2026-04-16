import XCTest
@testable import CoreStore

final class InboxRepositoryTests: XCTestCase {
    func test_inbox_returns_open_and_blocked_handoffs_for_actor() throws {
        let db = try TestDatabase.seeded()
        let items = try InboxRepository(db).inbox(for: "chatgpt")

        XCTAssertEqual(items.map(\.status), [.open, .blocked])
    }
}
