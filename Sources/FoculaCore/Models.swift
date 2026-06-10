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
        title: "Ship Focula",
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
    public var activitySummary: String?
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
        activitySummary: String? = nil,
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
        self.activitySummary = activitySummary
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

    public var defaultEndpoint: URL? {
        switch self {
        case .builtInGemma:
            nil
        case .oMLX:
            URL(string: "http://127.0.0.1:8123/v1/chat/completions")
        case .lmStudio:
            URL(string: "http://127.0.0.1:1234/v1/chat/completions")
        case .openAICompatible:
            URL(string: "http://127.0.0.1:1234/v1/chat/completions")
        case .cloudOptIn:
            URL(string: "https://api.openai.com/v1/chat/completions")
        }
    }

    public var defaultModelID: String {
        switch self {
        case .builtInGemma:
            BuiltInModelCatalog.defaultModel.id
        case .oMLX:
            "mlx-community/gemma-4-e2b-it-4bit"
        case .lmStudio:
            "local-vision"
        case .openAICompatible:
            "local-vision"
        case .cloudOptIn:
            "gpt-4.1-mini"
        }
    }

    public var setupSummary: String {
        switch self {
        case .builtInGemma:
            "App-managed local MLX runtime. Install one built-in model below; no external app is required."
        case .oMLX:
            "Optional external oMLX-compatible server. Configure the local chat-completions endpoint only if you already run it."
        case .lmStudio:
            "Optional LM Studio local server. Start LM Studio's OpenAI-compatible server, then use its endpoint and loaded model id here."
        case .openAICompatible:
            "Manual OpenAI-compatible vision endpoint. Use this for any local server that supports /v1/chat/completions with image input."
        case .cloudOptIn:
            "Cloud vision endpoint. Screenshots are blocked until the explicit cloud opt-in below is enabled."
        }
    }
}

public struct BuiltInModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var repository: String
    public var precision: String
    public var estimatedDownloadSize: String
    public var expectedMemory: String
    public var localOnlyNotice: String
    public var isRecommended: Bool
    public var isInstallable: Bool

    public init(
        id: String,
        displayName: String,
        repository: String,
        precision: String,
        estimatedDownloadSize: String,
        expectedMemory: String,
        localOnlyNotice: String,
        isRecommended: Bool = false,
        isInstallable: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.repository = repository
        self.precision = precision
        self.estimatedDownloadSize = estimatedDownloadSize
        self.expectedMemory = expectedMemory
        self.localOnlyNotice = localOnlyNotice
        self.isRecommended = isRecommended
        self.isInstallable = isInstallable
    }
}

public enum BuiltInModelCatalog {
    public static let gemma4E2B4Bit = BuiltInModelDescriptor(
        id: "mlx-community/gemma-4-e2b-it-4bit",
        displayName: "Gemma 4 E2B Vision 4-bit",
        repository: "mlx-community/gemma-4-e2b-it-4bit",
        precision: "4-bit MLX",
        estimatedDownloadSize: "about 3.6 GB",
        expectedMemory: "8 GB unified memory recommended",
        localOnlyNotice: "Smallest built-in option. Classifies screenshots locally; raw images are discarded after each request.",
        isRecommended: true
    )

    public static let gemma4E2B8Bit = BuiltInModelDescriptor(
        id: "mlx-community/gemma-4-e2b-it-8bit",
        displayName: "Gemma 4 E2B Vision 8-bit",
        repository: "mlx-community/gemma-4-e2b-it-8bit",
        precision: "8-bit MLX",
        estimatedDownloadSize: "about 5.9 GB",
        expectedMemory: "12 GB unified memory recommended",
        localOnlyNotice: "Higher precision than 4-bit while staying smaller than BF16. Screenshots stay local and are discarded."
    )

    public static let gemma4E2BBF16 = BuiltInModelDescriptor(
        id: "mlx-community/gemma-4-e2b-it-bf16",
        displayName: "Gemma 4 E2B Vision BF16",
        repository: "mlx-community/gemma-4-e2b-it-bf16",
        precision: "BF16 MLX",
        estimatedDownloadSize: "about 10.3 GB",
        expectedMemory: "16 GB unified memory recommended",
        localOnlyNotice: "Largest built-in option. Use when quality matters more than storage and memory."
    )

    public static let gemma4E2BQATMobileTransformers = BuiltInModelDescriptor(
        id: "google/gemma-4-E2B-it-qat-mobile-transformers",
        displayName: "Gemma 4 E2B QAT Mobile",
        repository: "google/gemma-4-E2B-it-qat-mobile-transformers",
        precision: "QAT mobile Transformers",
        estimatedDownloadSize: "about 1 GB memory footprint",
        expectedMemory: "Not supported by the built-in MLX runtime yet",
        localOnlyNotice: "Google's smaller QAT mobile checkpoint is tracked here, but Focula cannot run it until the sidecar supports LiteRT or Transformers mobile tensors.",
        isInstallable: false
    )

    public static let all: [BuiltInModelDescriptor] = [
        gemma4E2B4Bit,
        gemma4E2B8Bit,
        gemma4E2BBF16,
        gemma4E2BQATMobileTransformers
    ]

    public static let defaultModel = gemma4E2B4Bit

    public static let legacyDefaultRepositories: Set<String> = [
        "google/gemma-4-E2B-it",
        "google/gemma-4-e2b-it"
    ]

    // Backward-compatible alias for older settings and tests.
    public static let gemma4E2B = gemma4E2B4Bit

    public static func descriptor(for id: String) -> BuiltInModelDescriptor? {
        if let descriptor = all.first(where: { $0.id == id || $0.repository == id }) {
            return descriptor
        }

        if legacyDefaultRepositories.contains(id) {
            return defaultModel
        }

        return nil
    }

    public static func descriptorOrDefault(for id: String) -> BuiltInModelDescriptor {
        descriptor(for: id) ?? defaultModel
    }
}

public struct ModelSelection: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var modelID: String
    public var endpoint: URL?
    public var cloudClassificationAllowed: Bool

    public init(
        provider: ModelProvider = .builtInGemma,
        modelID: String = BuiltInModelCatalog.defaultModel.id,
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
            modelID: BuiltInModelCatalog.defaultModel.id,
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
            modelID: BuiltInModelCatalog.defaultModel.id,
            installState: .missing,
            statusMessage: "Built-in model not installed.",
            storagePath: storagePath,
            isVisionCapable: true,
            isUsable: false
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

public enum SamplingStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case responsive
    case quiet
    case manualOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .responsive: "Responsive"
        case .quiet: "Quiet"
        case .manualOnly: "Manual only"
        }
    }

    public var summary: String {
        switch self {
        case .balanced: "Adjusts based on recent activity and backs off when idle."
        case .responsive: "Checks more often after input or app changes."
        case .quiet: "Checks less often to reduce background work."
        case .manualOnly: "Only samples when you click Scout Now."
        }
    }
}

public enum ActivityLogVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case allActivity
    case focusOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allActivity: "All activity"
        case .focusOnly: "Focus time only"
        }
    }
}

public struct MonitoringRules: Codable, Equatable, Sendable {
    public var anyTrackingGoalCountsAsFocused: Bool
    public var unmatchedActivityIsSideTracked: Bool

    public init(
        anyTrackingGoalCountsAsFocused: Bool = true,
        unmatchedActivityIsSideTracked: Bool = true
    ) {
        self.anyTrackingGoalCountsAsFocused = anyTrackingGoalCountsAsFocused
        self.unmatchedActivityIsSideTracked = unmatchedActivityIsSideTracked
    }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var notifyOnSustainedDrift: Bool
    public var notifyOnRuntimeFailure: Bool

    public init(
        notifyOnSustainedDrift: Bool = true,
        notifyOnRuntimeFailure: Bool = true
    ) {
        self.notifyOnSustainedDrift = notifyOnSustainedDrift
        self.notifyOnRuntimeFailure = notifyOnRuntimeFailure
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var endpoint: URL
    public var model: String
    public var modelSelection: ModelSelection
    public var builtInModelStatus: ModelRuntimeStatus
    public var modelTelemetry: ModelTelemetry
    public var sampleIntervalSeconds: TimeInterval
    public var samplingStrategy: SamplingStrategy
    public var monitoringRules: MonitoringRules
    public var notificationPreferences: NotificationPreferences
    public var activityLogVisibility: ActivityLogVisibility
    public var persistActivitySummaries: Bool
    public var paused: Bool

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
        model: String = BuiltInModelCatalog.defaultModel.id,
        modelSelection: ModelSelection = .builtInGemma(),
        builtInModelStatus: ModelRuntimeStatus = .builtInDefault(),
        modelTelemetry: ModelTelemetry = ModelTelemetry(),
        sampleIntervalSeconds: TimeInterval = 60,
        samplingStrategy: SamplingStrategy = .balanced,
        monitoringRules: MonitoringRules = MonitoringRules(),
        notificationPreferences: NotificationPreferences = NotificationPreferences(),
        activityLogVisibility: ActivityLogVisibility = .allActivity,
        persistActivitySummaries: Bool = true,
        paused: Bool = true
    ) {
        self.endpoint = endpoint
        self.model = model
        self.modelSelection = modelSelection
        self.builtInModelStatus = builtInModelStatus
        self.modelTelemetry = modelTelemetry
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.samplingStrategy = samplingStrategy
        self.monitoringRules = monitoringRules
        self.notificationPreferences = notificationPreferences
        self.activityLogVisibility = activityLogVisibility
        self.persistActivitySummaries = persistActivitySummaries
        self.paused = paused
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case modelSelection
        case builtInModelStatus
        case modelTelemetry
        case sampleIntervalSeconds
        case samplingStrategy
        case monitoringRules
        case notificationPreferences
        case activityLogVisibility
        case persistActivitySummaries
        case paused
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultEndpoint = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
        endpoint = try container.decodeIfPresent(URL.self, forKey: .endpoint) ?? defaultEndpoint
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? BuiltInModelCatalog.defaultModel.id
        var decodedSelection = try container.decodeIfPresent(ModelSelection.self, forKey: .modelSelection) ?? .builtInGemma()
        var decodedStatus = try container.decodeIfPresent(ModelRuntimeStatus.self, forKey: .builtInModelStatus) ?? .builtInDefault()
        if decodedSelection.provider == .builtInGemma {
            let descriptor = BuiltInModelCatalog.descriptorOrDefault(for: decodedSelection.modelID)
            decodedSelection.modelID = descriptor.id
            decodedSelection.endpoint = nil
            model = descriptor.id
            decodedStatus.modelID = descriptor.id
        }
        modelSelection = decodedSelection
        builtInModelStatus = decodedStatus
        modelTelemetry = try container.decodeIfPresent(ModelTelemetry.self, forKey: .modelTelemetry) ?? ModelTelemetry()
        sampleIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleIntervalSeconds) ?? 60
        samplingStrategy = try container.decodeIfPresent(SamplingStrategy.self, forKey: .samplingStrategy) ?? .balanced
        monitoringRules = try container.decodeIfPresent(MonitoringRules.self, forKey: .monitoringRules) ?? MonitoringRules()
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
        activityLogVisibility = try container.decodeIfPresent(ActivityLogVisibility.self, forKey: .activityLogVisibility) ?? .allActivity
        persistActivitySummaries = try container.decodeIfPresent(Bool.self, forKey: .persistActivitySummaries) ?? true
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? true
    }
}
