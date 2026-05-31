import XCTest
@testable import WatchMyBackCore

final class ActivityLogCompactorTests: XCTestCase {
    func testMergesConsecutiveSameActivityIntoOneBlock() {
        let goalID = UUID()
        let samples = [
            sample(at: 0, goalID: goalID),
            sample(at: 60, goalID: goalID),
            sample(at: 120, goalID: goalID)
        ]

        let blocks = ActivityLogCompactor.compact(samples: samples)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].sampleCount, 3)
        XCTAssertEqual(blocks[0].durationSeconds, 180)
        XCTAssertEqual(blocks[0].activitySummary, "Watching a recorded lecture")
    }

    func testSplitsWhenActivityChanges() {
        let goalID = UUID()
        let samples = [
            sample(at: 0, goalID: goalID, summary: "Watching a recorded lecture"),
            sample(at: 60, goalID: goalID, summary: "Practicing coding questions")
        ]

        let blocks = ActivityLogCompactor.compact(samples: samples)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.activitySummary), [
            "Practicing coding questions",
            "Watching a recorded lecture"
        ])
    }

    func testSplitsAfterLongGap() {
        let goalID = UUID()
        let samples = [
            sample(at: 0, goalID: goalID),
            sample(at: 900, goalID: goalID)
        ]

        let blocks = ActivityLogCompactor.compact(samples: samples, maxGap: 10 * 60)

        XCTAssertEqual(blocks.count, 2)
    }

    private func sample(
        at offset: TimeInterval,
        goalID: UUID,
        summary: String = "Watching a recorded lecture"
    ) -> ActivitySample {
        ActivitySample(
            timestamp: Date(timeIntervalSince1970: offset),
            appName: "SenPlayer",
            bundleIdentifier: "com.example.player",
            goalID: goalID,
            focusState: .onGoal,
            activityCategory: "video_learning",
            activitySummary: summary,
            confidence: 0.9,
            durationSeconds: 60,
            nudgeShown: false
        )
    }
}
