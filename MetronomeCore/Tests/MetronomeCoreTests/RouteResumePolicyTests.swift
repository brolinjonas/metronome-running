import XCTest
@testable import MetronomeCore

final class RouteResumePolicyTests: XCTestCase {
    private let stopDate = Date(timeIntervalSinceReferenceDate: 1_000)

    func testNoInterruptionStopMeansNoResume() {
        XCTAssertFalse(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: nil,
                routeReturnedAt: stopDate
            )
        )
    }

    func testResumesWhenRouteReturnsShortlyAfterStop() {
        XCTAssertTrue(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(10)
            )
        )
    }

    func testDoesNotResumeAfterWindowExpires() {
        XCTAssertFalse(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(RouteResumePolicy.defaultWindow + 1)
            )
        )
    }

    func testResumesExactlyAtWindowBoundary() {
        XCTAssertTrue(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(RouteResumePolicy.defaultWindow)
            )
        )
    }

    func testDoesNotResumeWhenClockRunsBackwards() {
        XCTAssertFalse(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(-1)
            )
        )
    }

    func testCustomWindowIsRespected() {
        XCTAssertTrue(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(50),
                window: 60
            )
        )
        XCTAssertFalse(
            RouteResumePolicy.shouldResume(
                stoppedByInterruptionAt: stopDate,
                routeReturnedAt: stopDate.addingTimeInterval(70),
                window: 60
            )
        )
    }
}
