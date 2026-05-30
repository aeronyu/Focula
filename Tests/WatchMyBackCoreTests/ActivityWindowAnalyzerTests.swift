import Foundation
import XCTest
@testable import WatchMyBackCore

final class ActivityWindowAnalyzerTests: XCTestCase {
    func testSummarizeReturnsNoSamplesWhenWindowIsEmpty() {
        let analyzer = ActivityWindowAnalyzer(windowDuration: 20 * 60, driftThreshold: 20 * 60)
        let summary = analyzer.summarize(samples: [], now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(summary.state, .noSamples)
        XCTAssertEqual(summary.sampleCount, 0)
        XCTAssertFalse(summary.isSustainedDrift)
    }

    func testSummarizeMarksOnTrackWhenAlignedTimeDominates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let analyzer = ActivityWindowAnalyzer(windowDuration: 20 * 60, driftThreshold: 20 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-120), state: .onGoal, duration: 120),
            sample(at: now.addingTimeInterval(-60), state: .maybe, duration: 60)
        ]

        let summary = analyzer.summarize(samples: samples, now: now)

        XCTAssertEqual(summary.state, .onTrack)
        XCTAssertEqual(summary.alignedCount, 1)
        XCTAssertEqual(summary.maybeCount, 1)
        XCTAssertEqual(summary.alignedSeconds, 120)
        XCTAssertFalse(summary.isSustainedDrift)
    }

    func testSummarizeMarksDriftingOnlyAfterSustainedOffGoalTimeAndMinimumSamples() {
        let now = Date(timeIntervalSince1970: 1_000)
        let analyzer = ActivityWindowAnalyzer(
            windowDuration: 20 * 60,
            driftThreshold: 20 * 60,
            minimumSamplesForDrift: 2
        )
        let samples = [
            sample(at: now.addingTimeInterval(-1_000), state: .offGoal, duration: 600),
            sample(at: now.addingTimeInterval(-400), state: .offGoal, duration: 600)
        ]

        let summary = analyzer.summarize(samples: samples, now: now)

        XCTAssertEqual(summary.state, .drifting)
        XCTAssertEqual(summary.offGoalCount, 2)
        XCTAssertEqual(summary.offGoalSeconds, 1_200)
        XCTAssertTrue(summary.isSustainedDrift)
    }

    func testSummarizeDoesNotMarkSingleLongOffGoalSampleAsSustainedDrift() {
        let now = Date(timeIntervalSince1970: 1_000)
        let analyzer = ActivityWindowAnalyzer(
            windowDuration: 20 * 60,
            driftThreshold: 20 * 60,
            minimumSamplesForDrift: 2
        )
        let samples = [
            sample(at: now.addingTimeInterval(-600), state: .offGoal, duration: 1_200)
        ]

        let summary = analyzer.summarize(samples: samples, now: now)

        XCTAssertEqual(summary.state, .mixed)
        XCTAssertFalse(summary.isSustainedDrift)
    }

    func testSummarizeIgnoresSamplesOutsideWindow() {
        let now = Date(timeIntervalSince1970: 2_000)
        let analyzer = ActivityWindowAnalyzer(windowDuration: 20 * 60, driftThreshold: 20 * 60)
        let samples = [
            sample(at: now.addingTimeInterval(-2_000), state: .offGoal, duration: 600),
            sample(at: now.addingTimeInterval(-60), state: .onGoal, duration: 60)
        ]

        let summary = analyzer.summarize(samples: samples, now: now)

        XCTAssertEqual(summary.sampleCount, 1)
        XCTAssertEqual(summary.state, .onTrack)
        XCTAssertEqual(summary.offGoalSeconds, 0)
    }

    func testSummarizeIncludingCandidateSampleUsesSameRollingWindow() {
        let now = Date(timeIntervalSince1970: 3_000)
        let analyzer = ActivityWindowAnalyzer(
            windowDuration: 20 * 60,
            driftThreshold: 20 * 60,
            minimumSamplesForDrift: 2
        )
        let storedSamples = [
            sample(at: now.addingTimeInterval(-2_000), state: .offGoal, duration: 600),
            sample(at: now.addingTimeInterval(-500), state: .offGoal, duration: 600)
        ]
        let candidate = sample(at: now, state: .offGoal, duration: 600)

        let summary = analyzer.summarize(samples: storedSamples, including: candidate, now: now)

        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(summary.offGoalSeconds, 1_200)
        XCTAssertTrue(summary.isSustainedDrift)
    }

    private func sample(
        at date: Date,
        state: FocusState,
        duration: TimeInterval
    ) -> ActivitySample {
        ActivitySample(
            timestamp: date,
            appName: "Test App",
            bundleIdentifier: "com.example.test",
            goalID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            focusState: state,
            activityCategory: state.rawValue,
            confidence: 0.9,
            durationSeconds: duration,
            nudgeShown: false
        )
    }
}
