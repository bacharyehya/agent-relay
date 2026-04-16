import XCTest
@testable import AppCore
@testable import CoreStore

final class EventRepositoryTests: XCTestCase {
    func test_event_repository_persists_recorded_events() throws {
        let db = try TestDatabase.seeded()
        let repository = EventRepository(db)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
        let event = Event(
            id: "event-1",
            type: .handoffBlocked,
            projectID: "project-search",
            threadID: "thread-search",
            handoffID: "handoff-search",
            actorID: "chatgpt",
            body: "Blocked on missing auth scope",
            createdAt: timestamp
        )

        try repository.record(event)

        XCTAssertEqual(try repository.list(limit: 10).last, event)
    }
}
