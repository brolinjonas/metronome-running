import XCTest
@testable import MetronomeCore

final class ClickIntervalTests: XCTestCase {
    func testSecondsForBPM60IsOneSecond() {
        XCTAssertEqual(ClickInterval.seconds(forBPM: 60), 1.0, accuracy: 0.0001)
    }

    func testSecondsForBPM120IsHalfSecond() {
        XCTAssertEqual(ClickInterval.seconds(forBPM: 120), 0.5, accuracy: 0.0001)
    }

    func testSampleCountForBPM120At44100Hz() {
        // 120 BPM -> 0.5s per beat; 44100 * 0.5 = 22050 samples
        XCTAssertEqual(ClickInterval.sampleCount(forBPM: 120, sampleRate: 44100), 22050, accuracy: 0.001)
    }

    func testSampleCountForBPM160At48000Hz() {
        // 160 BPM -> 0.375s per beat; 48000 * 0.375 = 18000 samples
        XCTAssertEqual(ClickInterval.sampleCount(forBPM: 160, sampleRate: 48000), 18000, accuracy: 0.001)
    }
}
