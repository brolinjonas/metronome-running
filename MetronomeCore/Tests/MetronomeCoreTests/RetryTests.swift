import XCTest
@testable import MetronomeCore

final class RetryTests: XCTestCase {
    private struct TestError: Error, Equatable {
        let id: Int
    }

    func testFirstSuccessDoesNotRetry() async throws {
        var operationCalls = 0
        var beforeRetryCalls = 0

        let result = try await Retry.run(
            attempts: 3,
            beforeRetry: { beforeRetryCalls += 1 },
            operation: { operationCalls += 1; return "ok" }
        )

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(operationCalls, 1)
        XCTAssertEqual(beforeRetryCalls, 0)
    }

    func testRetriesAfterFailureAndReturnsSuccess() async throws {
        var operationCalls = 0
        var beforeRetryCalls = 0

        let result = try await Retry.run(
            attempts: 3,
            beforeRetry: { beforeRetryCalls += 1 },
            operation: {
                operationCalls += 1
                if operationCalls < 3 { throw TestError(id: operationCalls) }
                return "ok"
            }
        )

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(operationCalls, 3)
        XCTAssertEqual(beforeRetryCalls, 2)
    }

    func testThrowsLastErrorAfterExhaustingAttempts() async {
        var operationCalls = 0

        do {
            _ = try await Retry.run(
                attempts: 3,
                beforeRetry: {},
                operation: { () -> String in
                    operationCalls += 1
                    throw TestError(id: operationCalls)
                }
            )
            XCTFail("Expected Retry.run to throw")
        } catch let error as TestError {
            XCTAssertEqual(error, TestError(id: 3))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertEqual(operationCalls, 3)
    }

    func testBeforeRetryThrowingAbortsImmediately() async {
        var operationCalls = 0

        do {
            _ = try await Retry.run(
                attempts: 3,
                beforeRetry: { throw CancellationError() },
                operation: { () -> String in
                    operationCalls += 1
                    throw TestError(id: operationCalls)
                }
            )
            XCTFail("Expected Retry.run to throw")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertEqual(operationCalls, 1)
    }
}
