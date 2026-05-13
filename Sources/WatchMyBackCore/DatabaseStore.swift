import Foundation
import SQLite3

public enum DatabaseStoreError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case decodeFailed
}

public final class DatabaseStore {
    private let db: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            throw DatabaseStoreError.openFailed(message)
        }

        self.db = handle
        try createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func applicationStoreURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Watch My Back", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("watch-my-back.sqlite")
    }

    public func saveGoal(_ goal: Goal) throws {
        let sql = """
        INSERT OR REPLACE INTO goals (
            id, title, description, schedule_json, allowed_apps_json, blocked_apps_json,
            on_goal_examples_json, off_goal_examples_json, daily_target_minutes, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try withStatement(sql) { statement in
            bindText(statement, 1, goal.id.uuidString)
            bindText(statement, 2, goal.title)
            bindText(statement, 3, goal.description)
            bindText(statement, 4, try encodeString(goal.schedule))
            bindText(statement, 5, try encodeString(goal.allowedApps))
            bindText(statement, 6, try encodeString(goal.blockedApps))
            bindText(statement, 7, try encodeString(goal.onGoalExamples))
            bindText(statement, 8, try encodeString(goal.offGoalExamples))
            sqlite3_bind_int(statement, 9, Int32(goal.dailyTargetMinutes))
            sqlite3_bind_int(statement, 10, goal.isActive ? 1 : 0)
            try step(statement)
        }
    }

    public func fetchGoals() throws -> [Goal] {
        let sql = """
        SELECT id, title, description, schedule_json, allowed_apps_json, blocked_apps_json,
               on_goal_examples_json, off_goal_examples_json, daily_target_minutes, is_active
        FROM goals ORDER BY is_active DESC, title ASC;
        """

        return try withStatement(sql) { statement in
            var goals: [Goal] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = UUID(uuidString: columnText(statement, 0)) else {
                    throw DatabaseStoreError.decodeFailed
                }

                goals.append(Goal(
                    id: id,
                    title: columnText(statement, 1),
                    description: columnText(statement, 2),
                    schedule: try decodeString(columnText(statement, 3)),
                    allowedApps: try decodeString(columnText(statement, 4)),
                    blockedApps: try decodeString(columnText(statement, 5)),
                    onGoalExamples: try decodeString(columnText(statement, 6)),
                    offGoalExamples: try decodeString(columnText(statement, 7)),
                    dailyTargetMinutes: Int(sqlite3_column_int(statement, 8)),
                    isActive: sqlite3_column_int(statement, 9) == 1
                ))
            }
            return goals
        }
    }

    public func seedDefaultGoalIfNeeded() throws -> Goal {
        let goals = try fetchGoals()
        if let active = goals.first(where: \.isActive) {
            return active
        }

        let starter = Goal.starter
        try saveGoal(starter)
        return starter
    }

    public func saveActivitySample(_ sample: ActivitySample) throws {
        let sql = """
        INSERT INTO activity_samples (
            id, timestamp, app_name, bundle_identifier, goal_id, focus_state,
            activity_category, confidence, duration_seconds, nudge_shown
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try withStatement(sql) { statement in
            bindText(statement, 1, sample.id.uuidString)
            sqlite3_bind_double(statement, 2, sample.timestamp.timeIntervalSince1970)
            bindText(statement, 3, sample.appName)
            bindNullableText(statement, 4, sample.bundleIdentifier)
            bindText(statement, 5, sample.goalID.uuidString)
            bindText(statement, 6, sample.focusState.rawValue)
            bindText(statement, 7, sample.activityCategory)
            sqlite3_bind_double(statement, 8, sample.confidence)
            sqlite3_bind_double(statement, 9, sample.durationSeconds)
            sqlite3_bind_int(statement, 10, sample.nudgeShown ? 1 : 0)
            try step(statement)
        }
    }

    public func fetchRecentSamples(limit: Int = 24) throws -> [ActivitySample] {
        let sql = """
        SELECT id, timestamp, app_name, bundle_identifier, goal_id, focus_state,
               activity_category, confidence, duration_seconds, nudge_shown
        FROM activity_samples
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            var samples: [ActivitySample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                samples.append(try decodeSample(statement))
            }
            return samples
        }
    }

    public func dailyStats(for date: Date, calendar: Calendar = .current) throws -> DailyStats {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw DatabaseStoreError.decodeFailed
        }

        let sql = """
        SELECT focus_state, duration_seconds, nudge_shown
        FROM activity_samples
        WHERE timestamp >= ? AND timestamp < ?
        ORDER BY timestamp ASC;
        """

        return try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            var focusSeconds: TimeInterval = 0
            var offGoalSeconds: TimeInterval = 0
            var unknownSeconds: TimeInterval = 0
            var recoveryCount = 0
            var previousWasNudgedOffGoal = false

            while sqlite3_step(statement) == SQLITE_ROW {
                let state = FocusState(rawValue: columnText(statement, 0)) ?? .unknown
                let duration = sqlite3_column_double(statement, 1)
                let nudgeShown = sqlite3_column_int(statement, 2) == 1

                switch state {
                case .onGoal:
                    focusSeconds += duration
                    if previousWasNudgedOffGoal {
                        recoveryCount += 1
                    }
                    previousWasNudgedOffGoal = false
                case .maybe, .unknown:
                    unknownSeconds += duration
                    previousWasNudgedOffGoal = false
                case .offGoal:
                    offGoalSeconds += duration
                    previousWasNudgedOffGoal = nudgeShown
                }
            }

            let xp = Int(focusSeconds / 60) + recoveryCount * 10
            return DailyStats(
                date: start,
                focusSeconds: focusSeconds,
                offGoalSeconds: offGoalSeconds,
                unknownSeconds: unknownSeconds,
                recoveryCount: recoveryCount,
                xp: xp
            )
        }
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let sql = "INSERT OR REPLACE INTO settings (id, settings_json) VALUES ('default', ?);"
        try withStatement(sql) { statement in
            bindText(statement, 1, try encodeString(settings))
            try step(statement)
        }
    }

    public func fetchSettings() throws -> AppSettings {
        let sql = "SELECT settings_json FROM settings WHERE id = 'default';"
        return try withStatement(sql) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return AppSettings()
            }
            return try decodeString(columnText(statement, 0))
        }
    }

    public func schemaContainsScreenshotStorage() throws -> Bool {
        let sql = "SELECT sql FROM sqlite_master WHERE type = 'table';"
        return try withStatement(sql) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                let tableSQL = columnText(statement, 0).lowercased()
                if tableSQL.contains("screenshot")
                    || tableSQL.contains("image_bytes")
                    || tableSQL.contains("ocr_text")
                    || tableSQL.contains("visible_text")
                {
                    return true
                }
            }
            return false
        }
    }

    private func createTables() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS goals (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            schedule_json TEXT NOT NULL,
            allowed_apps_json TEXT NOT NULL,
            blocked_apps_json TEXT NOT NULL,
            on_goal_examples_json TEXT NOT NULL,
            off_goal_examples_json TEXT NOT NULL,
            daily_target_minutes INTEGER NOT NULL,
            is_active INTEGER NOT NULL
        );
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS activity_samples (
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
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS settings (
            id TEXT PRIMARY KEY,
            settings_json TEXT NOT NULL
        );
        """)
    }

    private func execute(_ sql: String) throws {
        try withStatement(sql) { statement in
            try step(statement)
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DatabaseStoreError.decodeFailed
        }
        return string
    }

    private func decodeString<T: Decodable>(_ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw DatabaseStoreError.decodeFailed
        }
        return try decoder.decode(T.self, from: data)
    }

    private func decodeSample(_ statement: OpaquePointer) throws -> ActivitySample {
        guard let id = UUID(uuidString: columnText(statement, 0)),
              let goalID = UUID(uuidString: columnText(statement, 4))
        else {
            throw DatabaseStoreError.decodeFailed
        }

        return ActivitySample(
            id: id,
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            appName: columnText(statement, 2),
            bundleIdentifier: columnNullableText(statement, 3),
            goalID: goalID,
            focusState: FocusState(rawValue: columnText(statement, 5)) ?? .unknown,
            activityCategory: columnText(statement, 6),
            confidence: sqlite3_column_double(statement, 7),
            durationSeconds: sqlite3_column_double(statement, 8),
            nudgeShown: sqlite3_column_int(statement, 9) == 1
        )
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
    sqlite3_bind_text(statement, index, value, -1, transientDestructor)
}

private func bindNullableText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
    if let value {
        bindText(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: pointer)
}

private func columnNullableText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnText(statement, index)
}
