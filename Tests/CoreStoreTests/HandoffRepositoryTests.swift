import XCTest
@testable import AppCore
@testable import CoreStore

final class HandoffRepositoryTests: XCTestCase {
    func test_repositories_round_trip_project_thread_and_handoff() throws {
        let db = try TestDatabase.make()
        let projectRepository = ProjectRepository(db)
        let threadRepository = ThreadRepository(db)
        let handoffRepository = HandoffRepository(db)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let project = Project(
            id: "project-42",
            title: "Shield",
            summary: "Operational collaboration workspace",
            status: .active,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let thread = AppCore.Thread(
            id: "thread-42",
            projectID: project.id,
            title: "Webhook auth bug",
            intentType: .task,
            status: .active,
            createdBy: "human",
            assignedActorIDs: [],
            updatedAt: timestamp
        )
        let handoff = Handoff.example(id: "handoff-42", threadID: thread.id)

        try projectRepository.create(project)
        try threadRepository.create(thread)
        try handoffRepository.create(handoff)

        XCTAssertEqual(try projectRepository.get(id: project.id), project)
        XCTAssertEqual(try threadRepository.list(projectID: project.id), [thread])
        XCTAssertEqual(try handoffRepository.get(id: handoff.id), handoff)
    }
}
