import XCTest

final class DatabaseMigrationTests: XCTestCase {
    func test_migrator_creates_projects_threads_messages_handoffs_tables() throws {
        let db = try TestDatabase.make()
        let names = try db.tableNames()

        XCTAssertTrue(names.contains("projects"))
        XCTAssertTrue(names.contains("threads"))
        XCTAssertTrue(names.contains("messages"))
        XCTAssertTrue(names.contains("handoffs"))
    }
}
