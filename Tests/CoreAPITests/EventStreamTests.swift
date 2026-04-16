import AppCore
import XCTest
@testable import CoreAPI

final class EventStreamTests: XCTestCase {
    func test_event_stream_delivers_published_events() async throws {
        let stream = EventStream()
        let event = Event.example(type: .handoffBlocked)
        let subscription = await stream.subscribe()
        let nextEvent = Task {
            var iterator = subscription.makeAsyncIterator()
            return await iterator.next()
        }

        await stream.publish(event)

        let received = await nextEvent.value
        XCTAssertEqual(received, event)
    }
}
