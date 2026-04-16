import XCTest
@testable import AppCore

final class HandoffStateMachineTests: XCTestCase {
    func test_handoff_can_move_from_open_to_accepted_to_responded_to_resolved() throws {
        var handoff = Handoff.example(status: .open)

        try handoff.transition(to: .accepted)
        try handoff.transition(to: .responded)
        try handoff.transition(to: .resolved)

        XCTAssertEqual(handoff.status, .resolved)
    }

    func test_handoff_rejects_invalid_transition_from_open_to_resolved() {
        var handoff = Handoff.example(status: .open)

        XCTAssertThrowsError(try handoff.transition(to: .resolved)) { error in
            XCTAssertEqual(
                error as? HandoffTransitionError,
                .invalid(.open, .resolved)
            )
        }
    }
}
