import XCTest
@testable import MetronomeCore

final class BPMTests: XCTestCase {
    func testClampWithinRangeReturnsSameValue() {
        XCTAssertEqual(BPM.clamp(160), 160)
    }

    func testClampBelowRangeReturnsLowerBound() {
        XCTAssertEqual(BPM.clamp(50), 120)
    }

    func testClampAboveRangeReturnsUpperBound() {
        XCTAssertEqual(BPM.clamp(999), 200)
    }

    func testClampAtLowerBoundaryReturnsLowerBound() {
        XCTAssertEqual(BPM.clamp(120), 120)
    }

    func testClampAtUpperBoundaryReturnsUpperBound() {
        XCTAssertEqual(BPM.clamp(200), 200)
    }

    func testDefaultValueIsWithinRange() {
        XCTAssertTrue(BPM.range.contains(BPM.defaultValue))
    }
}
