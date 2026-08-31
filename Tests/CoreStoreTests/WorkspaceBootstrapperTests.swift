import AppCore
import Foundation
import XCTest
@testable import CoreStore

final class WorkspaceBootstrapperTests: XCTestCase {
    func test_seeds_default_workspace_once_on_empty_database() throws {
        let db = try TestDatabase.make()
        let bootstrapper = WorkspaceBootstrapper(db)
        let timestamp = Date(timeIntervalSince1970: 1_700_009_000)

        XCTAssertTrue(try bootstrapper.seedDefaultWorkspaceIfEmpty(now: timestamp))
        XCTAssertFalse(try bootstrapper.seedDefaultWorkspaceIfEmpty(now: timestamp.addingTimeInterval(1)))

        let projects = try ProjectRepository(db).list()
        XCTAssertEqual(projects.map(\.title), ["Agent Relay"])
        let threads = try ThreadRepository(db).list(projectID: WorkspaceBootstrapper.defaultProjectID)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].title, "General")
        XCTAssertEqual(threads[0].createdBy, "bash")
        XCTAssertEqual(threads[0].assignedActorIDs, ["codex-main", "codex-research"])
    }

    func test_adds_relay_room_without_changing_an_existing_project() throws {
        let db = try TestDatabase.seeded()

        XCTAssertTrue(try WorkspaceBootstrapper(db).ensureDefaultWorkspace())
        XCTAssertEqual(
            Set(try ProjectRepository(db).list().map(\.id)),
            Set(["project-search", WorkspaceBootstrapper.defaultProjectID])
        )
        XCTAssertEqual(
            try ThreadRepository(db)
                .list(projectID: WorkspaceBootstrapper.defaultProjectID)
                .map(\.id),
            [WorkspaceBootstrapper.defaultThreadID]
        )
    }
}
