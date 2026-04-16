import AppCore
import Foundation
import GRDB

public struct NotificationRepository {
    private let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func actionableEvents(limit: Int = 20) throws -> [Event] {
        try EventRepository(dbQueue)
            .list(limit: limit)
            .filter(NotificationRule.shouldNotifyHuman(for:))
    }
}
