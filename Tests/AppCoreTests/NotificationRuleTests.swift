import XCTest
@testable import AppCore

final class NotificationRuleTests: XCTestCase {
    func test_blocked_handoff_requires_human_notification() {
        let event = Event.example(type: .handoffBlocked)

        XCTAssertTrue(NotificationRule.shouldNotifyHuman(for: event))
    }
}
