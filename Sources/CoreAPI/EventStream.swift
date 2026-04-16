import AppCore
import Foundation

public actor EventStream {
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    public init() {}

    public func subscribe() -> AsyncStream<Event> {
        let id = UUID()

        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { _ in
                Task {
                    await self.removeSubscriber(id)
                }
            }
        }
    }

    public func publish(_ event: Event) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
