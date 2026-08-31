import XCTest
@testable import CodexRelayWorker

final class WorkerCadenceTests: XCTestCase {
    func test_cloud_workers_default_to_a_budget_safe_poll_interval() {
        XCTAssertEqual(
            WorkerConfiguration.defaultPollIntervalMilliseconds(for: .local),
            1_500
        )
        XCTAssertEqual(
            WorkerConfiguration.defaultPollIntervalMilliseconds(for: .cloud),
            15_000
        )
    }

    func test_poll_failures_back_off_without_exceeding_one_minute() {
        XCTAssertEqual(CodexRelayWorkerMain.retryDelayMilliseconds(base: 1_500, consecutiveFailures: 1), 5_000)
        XCTAssertEqual(CodexRelayWorkerMain.retryDelayMilliseconds(base: 1_500, consecutiveFailures: 2), 10_000)
        XCTAssertEqual(CodexRelayWorkerMain.retryDelayMilliseconds(base: 15_000, consecutiveFailures: 2), 30_000)
        XCTAssertEqual(CodexRelayWorkerMain.retryDelayMilliseconds(base: 15_000, consecutiveFailures: 3), 60_000)
        XCTAssertEqual(CodexRelayWorkerMain.retryDelayMilliseconds(base: 15_000, consecutiveFailures: 12), 60_000)
    }
}
