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

    func testSplitsWhenAppChanges() {
        let goalID = UUID()
        let samples = [
            sample(at: 0, goalID: goalID, appName: "SenPlayer", bundleIdentifier: "com.example.player"),
            sample(at: 60, goalID: goalID, appName: "Codex", bundleIdentifier: "com.openai.codex")
        ]

        let blocks = ActivityLogCompactor.compact(samples: samples)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.appName), ["Codex", "SenPlayer"])
    }

    func testSplitsWhenGoalChanges() {
        let firstGoalID = UUID()
        let secondGoalID = UUID()
        let samples = [
            sample(at: 0, goalID: firstGoalID),
            sample(at: 60, goalID: secondGoalID)
        ]

        let blocks = ActivityLogCompactor.compact(samples: samples)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.goalID), [secondGoalID, firstGoalID])
    }

    private func sample(
        at offset: TimeInterval,
        goalID: UUID,
        summary: String = "Watching a recorded lecture",
        appName: String = "SenPlayer",
        bundleIdentifier: String = "com.example.player"
    ) -> ActivitySample {
        ActivitySample(
            timestamp: Date(timeIntervalSince1970: offset),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
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
