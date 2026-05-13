import XCTest
@testable import WatchMyBackCore

final class DatabaseStoreTests: XCTestCase {
    func testPersistsGoalsAndActivityWithoutScreenshotBytes() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-my-back-\(UUID().uuidString).sqlite")
            .path
        let store = try DatabaseStore(path: path)
        let goal = Goal(
            title: "Ship Watch My Back",
            description: "Build native macOS focus app",
            schedule: FocusSchedule.weekdaysNineToFive,
            allowedApps: ["Xcode", "Terminal"],
            blockedApps: ["YouTube"],
            onGoalExamples: ["Writing Swift code"],
            offGoalExamples: ["Watching unrelated videos"],
            dailyTargetMinutes: 180,
            isActive: true
        )

        try store.saveGoal(goal)
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1_800),
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            goalID: goal.id,
            focusState: .onGoal,
            activityCategory: "coding",
            confidence: 0.9,
            durationSeconds: 60,
            nudgeShown: false
        )
        try store.saveActivitySample(sample)

        XCTAssertEqual(try store.fetchGoals().map(\.title), ["Ship Watch My Back"])
        let stats = try store.dailyStats(
            for: Date(timeIntervalSince1970: 1_800),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(stats.focusSeconds, 60)
        XCTAssertEqual(stats.xp, 1)
        XCTAssertFalse(try store.schemaContainsScreenshotStorage())
    }
}
