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

public enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case builtInGemma
    case oMLX
    case lmStudio
    case openAICompatible
    case cloudOptIn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .builtInGemma: "Built-in Gemma"
        case .oMLX: "oMLX"
        case .lmStudio: "LM Studio"
        case .openAICompatible: "OpenAI-compatible"
        case .cloudOptIn: "Cloud opt-in"
        }
    }

    public var isExternal: Bool {
        switch self {
        case .builtInGemma: false
        case .oMLX, .lmStudio, .openAICompatible, .cloudOptIn: true
        }
    }
}

public struct BuiltInModelDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var repository: String
    public var estimatedDownloadSize: String
    public var expectedMemory: String
    public var localOnlyNotice: String

    public init(
        id: String,
        displayName: String,
        repository: String,
        estimatedDownloadSize: String,
        expectedMemory: String,
        localOnlyNotice: String
    ) {
        self.id = id
        self.displayName = displayName
        self.repository = repository
        self.estimatedDownloadSize = estimatedDownloadSize
        self.expectedMemory = expectedMemory
        self.localOnlyNotice = localOnlyNotice
    }
}

public enum BuiltInModelCatalog {
    public static let gemma4E2B = BuiltInModelDescriptor(
        id: "google/gemma-4-E2B-it",
        displayName: "Gemma 4 E2B Vision",
        repository: "google/gemma-4-E2B-it",
        estimatedDownloadSize: "about 10 GB",
        expectedMemory: "16 GB unified memory recommended",
        localOnlyNotice: "Classifies screenshots locally; raw images are discarded after each request."
    )

    public static let all: [BuiltInModelDescriptor] = [gemma4E2B]
}

public struct ModelSelection: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var modelID: String
    public var endpoint: URL?
    public var cloudClassificationAllowed: Bool

    public init(
        provider: ModelProvider = .builtInGemma,
        modelID: String = BuiltInModelCatalog.gemma4E2B.id,
        endpoint: URL? = nil,
        cloudClassificationAllowed: Bool = false
    ) {
        self.provider = provider
        self.modelID = modelID
        self.endpoint = endpoint
        self.cloudClassificationAllowed = cloudClassificationAllowed
    }

    public static func builtInGemma() -> ModelSelection {
        ModelSelection(
            provider: .builtInGemma,
            modelID: BuiltInModelCatalog.gemma4E2B.id,
            endpoint: nil,
            cloudClassificationAllowed: false
        )
    }

    public var displayName: String {
        "\(provider.displayName) - \(modelID)"
    }

    public var canSendScreenshots: Bool {
        provider != .cloudOptIn || cloudClassificationAllowed
    }
}

public enum BuiltInModelInstallState: String, Codable, Equatable, Sendable {
    case missing
    case downloading
    case ready
    case failed

    public func nextForDownloadStart() -> BuiltInModelInstallState {
        .downloading
    }

    public func nextForDownloadSuccess() -> BuiltInModelInstallState {
        .ready
    }

    public func nextForDownloadFailure() -> BuiltInModelInstallState {
        .failed
    }

    public func nextForDelete() -> BuiltInModelInstallState {
        .missing
    }
}

public struct ModelRuntimeStatus: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var modelID: String
    public var installState: BuiltInModelInstallState
    public var statusMessage: String
    public var storagePath: String?
    public var isVisionCapable: Bool
    public var isUsable: Bool

    public init(
        provider: ModelProvider,
        modelID: String,
        installState: BuiltInModelInstallState,
        statusMessage: String,
        storagePath: String? = nil,
        isVisionCapable: Bool,
        isUsable: Bool
    ) {
        self.provider = provider
        self.modelID = modelID
        self.installState = installState
        self.statusMessage = statusMessage
        self.storagePath = storagePath
        self.isVisionCapable = isVisionCapable
        self.isUsable = isUsable
    }

    public static func builtInDefault(storagePath: String? = nil) -> ModelRuntimeStatus {
        ModelRuntimeStatus(
            provider: .builtInGemma,
            modelID: BuiltInModelCatalog.gemma4E2B.id,
            installState: .missing,
            statusMessage: "Built-in model not installed.",
            storagePath: storagePath,
            isVisionCapable: true,
            isUsable: true
        )
    }
}

public struct ModelTelemetry: Codable, Equatable, Sendable {
    public var lastLatencyMilliseconds: Double?
    public var parseFailureCount: Int
    public var successCount: Int
    public var lastVerifiedAt: Date?

    public init(
        lastLatencyMilliseconds: Double? = nil,
        parseFailureCount: Int = 0,
        successCount: Int = 0,
        lastVerifiedAt: Date? = nil
    ) {
        self.lastLatencyMilliseconds = lastLatencyMilliseconds
        self.parseFailureCount = parseFailureCount
        self.successCount = successCount
        self.lastVerifiedAt = lastVerifiedAt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var endpoint: URL
    public var model: String
    public var modelSelection: ModelSelection
    public var builtInModelStatus: ModelRuntimeStatus
    public var modelTelemetry: ModelTelemetry
    public var sampleIntervalSeconds: TimeInterval
    public var paused: Bool

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
        model: String = BuiltInModelCatalog.gemma4E2B.id,
        modelSelection: ModelSelection = .builtInGemma(),
        builtInModelStatus: ModelRuntimeStatus = .builtInDefault(),
        modelTelemetry: ModelTelemetry = ModelTelemetry(),
        sampleIntervalSeconds: TimeInterval = 60,
        paused: Bool = true
    ) {
        self.endpoint = endpoint
        self.model = model
        self.modelSelection = modelSelection
        self.builtInModelStatus = builtInModelStatus
        self.modelTelemetry = modelTelemetry
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.paused = paused
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case modelSelection
        case builtInModelStatus
        case modelTelemetry
        case sampleIntervalSeconds
        case paused
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultEndpoint = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
        endpoint = try container.decodeIfPresent(URL.self, forKey: .endpoint) ?? defaultEndpoint
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? BuiltInModelCatalog.gemma4E2B.id
        modelSelection = try container.decodeIfPresent(ModelSelection.self, forKey: .modelSelection) ?? .builtInGemma()
        builtInModelStatus = try container.decodeIfPresent(ModelRuntimeStatus.self, forKey: .builtInModelStatus) ?? .builtInDefault()
        modelTelemetry = try container.decodeIfPresent(ModelTelemetry.self, forKey: .modelTelemetry) ?? ModelTelemetry()
        sampleIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleIntervalSeconds) ?? 60
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? true
    }
}
