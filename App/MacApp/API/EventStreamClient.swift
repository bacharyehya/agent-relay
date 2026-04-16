import AppCore
import Foundation

protocol EventStreamClientProtocol: Sendable {
    func stream() -> AsyncStream<Event>
}

struct EventStreamClient: EventStreamClientProtocol {
    func stream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
