import Foundation

public enum FocusState: String, Codable, Equatable, Sendable {
    case onGoal = "on_goal"
    case maybe
    case offGoal = "off_goal"
    case unknown
}

public struct FocusSchedule: Codable, Equatable, Sendable {
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(weekdays: Set<Int>, startMinute: Int, endMinute: Int) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public static let weekdaysNineToFive = FocusSchedule(
        weekdays: [2, 3, 4, 5, 6],
        startMinute: 9 * 60,
        endMinute: 17 * 60
    )

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard weekdays.contains(weekday) else { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        if startMinute <= endMinute {
            return minuteOfDay >= startMinute && minuteOfDay < endMinute
        }

        return minuteOfDay >= startMinute || minuteOfDay < endMinute
    }
}

public struct Goal: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var description: String
    public var schedule: FocusSchedule
    public var allowedApps: [String]
    public var blockedApps: [String]
    public var onGoalExamples: [String]
    public var offGoalExamples: [String]
    public var dailyTargetMinutes: Int
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        schedule: FocusSchedule,
        allowedApps: [String],
        blockedApps: [String],
        onGoalExamples: [String],
        offGoalExamples: [String],
        dailyTargetMinutes: Int,
        isActive: Bool
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.schedule = schedule
        self.allowedApps = allowedApps
        self.blockedApps = blockedApps
        self.onGoalExamples = onGoalExamples
        self.offGoalExamples = offGoalExamples
        self.dailyTargetMinutes = dailyTargetMinutes
        self.isActive = isActive
    }

    public static let starter = Goal(
        title: "Ship Watch My Back",
        description: "Build, test, and polish the local-first macOS focus assistant.",
        schedule: .weekdaysNineToFive,
        allowedApps: ["Xcode", "Terminal", "Codex", "Safari", "Notes"],
        blockedApps: ["YouTube", "Netflix", "TikTok"],
        onGoalExamples: ["Writing Swift code", "Reviewing tests", "Reading Apple docs"],
        offGoalExamples: ["Watching unrelated videos", "Browsing social feeds"],
        dailyTargetMinutes: 180,
        isActive: true
    )
}

public struct ActivitySample: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var appName: String
    public var bundleIdentifier: String?
    public var goalID: UUID
    public var focusState: FocusState
    public var activityCategory: String
    public var confidence: Double
    public var durationSeconds: TimeInterval
    public var nudgeShown: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        appName: String,
        bundleIdentifier: String?,
        goalID: UUID,
        focusState: FocusState,
        activityCategory: String,
        confidence: Double,
        durationSeconds: TimeInterval,
        nudgeShown: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.goalID = goalID
        self.focusState = focusState
        self.activityCategory = activityCategory
        self.confidence = confidence
        self.durationSeconds = durationSeconds
        self.nudgeShown = nudgeShown
    }
}

public struct DailyStats: Equatable, Sendable {
    public var date: Date
    public var focusSeconds: TimeInterval
    public var offGoalSeconds: TimeInterval
    public var unknownSeconds: TimeInterval
    public var recoveryCount: Int
    public var xp: Int

    public init(
        date: Date,
        focusSeconds: TimeInterval,
        offGoalSeconds: TimeInterval,
        unknownSeconds: TimeInterval,
        recoveryCount: Int,
        xp: Int
    ) {
        self.date = date
        self.focusSeconds = focusSeconds
        self.offGoalSeconds = offGoalSeconds
        self.unknownSeconds = unknownSeconds
        self.recoveryCount = recoveryCount
        self.xp = xp
    }

    public var focusRatio: Double {
        let total = focusSeconds + offGoalSeconds + unknownSeconds
        guard total > 0 else { return 0 }
        return focusSeconds / total
    }
}

public struct StreakCalculator {
    public static func dayCounts(stats: DailyStats, targetMinutes: Int) -> Bool {
        stats.focusRatio >= 0.7 && stats.focusSeconds >= TimeInterval(targetMinutes * 60)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var endpoint: URL
    public var model: String
    public var sampleIntervalSeconds: TimeInterval
    public var paused: Bool

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
        model: String = "local-vision",
        sampleIntervalSeconds: TimeInterval = 60,
        paused: Bool = true
    ) {
        self.endpoint = endpoint
        self.model = model
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.paused = paused
    }
}
