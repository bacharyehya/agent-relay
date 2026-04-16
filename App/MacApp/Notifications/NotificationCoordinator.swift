import AppCore
import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator {
    private let center: any UserNotificationCenterControlling

    init(center: any UserNotificationCenterControlling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func handle(event: Event) async throws {
        guard NotificationRule.shouldNotifyHuman(for: event) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title(for: event)
        content.body = event.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    func observe(events: AsyncStream<Event>) async {
        for await event in events {
            try? await handle(event: event)
        }
    }

    private func title(for event: Event) -> String {
        switch event.type {
        case .handoffBlocked:
            return "Blocked handoff"
        case .handoffAssignedToHuman:
            return "Handoff assigned to you"
        case .humanReplyRequested:
            return "Reply requested"
        case .serviceFailure:
            return "Service issue"
        default:
            return "AgentRelay"
        }
    }
}

@MainActor
protocol UserNotificationCenterControlling {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: UserNotificationCenterControlling {}
