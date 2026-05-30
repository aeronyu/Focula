import XCTest
import SQLite3
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
            activitySummary: "Working in Xcode",
            confidence: 0.9,
            durationSeconds: 60,
            nudgeShown: false
        )
        try store.saveActivitySample(sample)

        XCTAssertEqual(try store.fetchGoals().map(\.title), ["Ship Watch My Back"])
        XCTAssertEqual(try store.fetchRecentSamples(limit: 1).first?.activitySummary, "Working in Xcode")
        let stats = try store.dailyStats(
            for: Date(timeIntervalSince1970: 1_800),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(stats.focusSeconds, 60)
        XCTAssertEqual(stats.xp, 1)
        XCTAssertFalse(try store.schemaContainsScreenshotStorage())
    }

    func testMigratesExistingActivityTableForOptionalSummary() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-my-back-legacy-\(UUID().uuidString).sqlite")
            .path
        try createLegacyActivitySamplesTable(path: path)

        let store = try DatabaseStore(path: path)
        let goal = Goal.starter
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 2_400),
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            goalID: goal.id,
            focusState: .onGoal,
            activityCategory: "terminal_work",
            activitySummary: "Running local checks",
            confidence: 0.8,
            durationSeconds: 60,
            nudgeShown: false
        )

        try store.saveActivitySample(sample)

        XCTAssertEqual(try store.fetchRecentSamples(limit: 1).first?.activitySummary, "Running local checks")
    }

    func testDeletesGoalWithoutDeletingActivityHistory() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-my-back-delete-\(UUID().uuidString).sqlite")
            .path
        let store = try DatabaseStore(path: path)
        let goal = Goal.starter
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 3_000),
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            goalID: goal.id,
            focusState: .onGoal,
            activityCategory: "coding",
            activitySummary: "Editing Swift",
            confidence: 0.9,
            durationSeconds: 60,
            nudgeShown: false
        )

        try store.saveGoal(goal)
        try store.saveActivitySample(sample)
        try store.deleteGoal(id: goal.id)

        XCTAssertTrue(try store.fetchGoals().isEmpty)
        XCTAssertEqual(try store.fetchRecentSamples(limit: 1).first?.activitySummary, "Editing Swift")
    }

    private func createLegacyActivitySamplesTable(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            XCTFail("Could not open legacy sqlite database")
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE activity_samples (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            app_name TEXT NOT NULL,
            bundle_identifier TEXT,
            goal_id TEXT NOT NULL,
            focus_state TEXT NOT NULL,
            activity_category TEXT NOT NULL,
            confidence REAL NOT NULL,
            duration_seconds REAL NOT NULL,
            nudge_shown INTEGER NOT NULL
        );
        """

        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
