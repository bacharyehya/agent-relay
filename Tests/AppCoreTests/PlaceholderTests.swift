import XCTest
@testable import AppCore

final class PlaceholderTests: XCTestCase {
    func test_placeholder_value_is_stable() {
        XCTAssertEqual(AppCorePlaceholder.value, "AppCore")
    }
}
