import Foundation
import Combine
import WatchMyBackCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var goals: [Goal] = []
    @Published var selectedGoalID: UUID?
    @Published private(set) var recentSamples: [ActivitySample] = []
    @Published private(set) var stats = DailyStats(
        date: Date(),
        focusSeconds: 0,
        offGoalSeconds: 0,
        unknownSeconds: 0,
        recoveryCount: 0,
        xp: 0
    )
    @Published var settings = AppSettings()
    @Published private(set) var lastFocusState: WatchMyBackCore.FocusState = .unknown
    @Published private(set) var statusMessage = "Paused. Resume when you want Watch My Back to observe focus hours."
    @Published private(set) var lastError: String?
    @Published private(set) var isSampling = false

    private var store: DatabaseStore?
    private let appProvider: FrontmostAppProviding
    private let captureProvider: ScreenSnapshotProviding
    private let deduplicator = FrameDeduplicator()
    private let nudgeCoordinator = NudgeCoordinator()
    private var timer: Timer?

    init(
        appProvider: FrontmostAppProviding = NSWorkspaceFrontmostAppProvider(),
        captureProvider: ScreenSnapshotProviding = ScreenCaptureKitSnapshotProvider()
    ) {
        self.appProvider = appProvider
        self.captureProvider = captureProvider

        do {
            let url = try DatabaseStore.applicationStoreURL()
            let store = try DatabaseStore(path: url.path)
            self.store = store
            settings = try store.fetchSettings()
            let activeGoal = try store.seedDefaultGoalIfNeeded()
            selectedGoalID = activeGoal.id
            reloadFromStore()
        } catch {
            self.store = nil
            let starter = Goal.starter
            goals = [starter]
            selectedGoalID = starter.id
            lastError = "Local database unavailable: \(error.localizedDescription)"
        }

        NotificationNudgePresenter.shared.requestAuthorization()
        if !settings.paused {
            startTimer()
        }
    }

    var activeGoal: Goal? {
        goals.first(where: { $0.isActive }) ?? goals.first
    }

    var selectedGoal: Goal? {
        guard let selectedGoalID else { return activeGoal }
        return goals.first(where: { $0.id == selectedGoalID }) ?? activeGoal
    }

    var menuBarSystemImage: String {
        switch lastFocusState {
        case .onGoal: "scope"
        case .maybe: "gauge.medium"
        case .offGoal: "bell.badge"
        case .unknown: settings.paused ? "pause.circle" : "eye"
        }
    }

    var endpointString: String {
        settings.endpoint.absoluteString
    }

    func updateEndpoint(_ value: String) {
        guard let url = URL(string: value), url.scheme != nil else { return }
        settings.endpoint = url
        saveSettings()
    }

    func updateModelName(_ value: String) {
        settings.model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSettings()
    }

    func updateSampleInterval(_ value: TimeInterval) {
        settings.sampleIntervalSeconds = max(15, value)
        saveSettings()
        if !settings.paused {
            stopTimer()
            startTimer()
        }
    }

    func togglePaused() {
        settings.paused.toggle()
        saveSettings()

        if settings.paused {
            stopTimer()
            statusMessage = "Paused. No screenshots or activity samples are being captured."
        } else {
            statusMessage = "Tracking focus hours. Screenshots are classified locally and discarded."
            startTimer()
            Task { await sampleNow(manual: true) }
        }
    }

    func sampleNow(manual: Bool = false) async {
        guard !isSampling else { return }
        guard let goal = activeGoal else {
            statusMessage = "No active goal. Add a goal before tracking."
            return
        }

        let now = Date()
        if !manual, !goal.schedule.contains(now) {
            statusMessage = "Quiet: outside focus hours for \(goal.title)."
            return
        }

        isSampling = true
        defer { isSampling = false }

        let app = appProvider.currentApp()
        let result = await classifyCurrentScreen(goal: goal, app: app)
        let shouldNudge = nudgeCoordinator.shouldNudge(
            focusState: result.focusState,
            schedule: goal.schedule,
            paused: settings.paused,
            now: now
        )

        if shouldNudge {
            NotificationNudgePresenter.shared.show(goal: goal, appName: app.appName)
            nudgeCoordinator.recordNudge(at: now)
        }

        let sample = ActivitySample(
            timestamp: now,
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            goalID: goal.id,
            focusState: result.focusState,
            activityCategory: result.activityCategory,
            confidence: result.confidence,
            durationSeconds: settings.sampleIntervalSeconds,
            nudgeShown: shouldNudge
        )

        do {
            try store?.saveActivitySample(sample)
            lastFocusState = result.focusState
            statusMessage = statusText(for: sample, goal: goal)
            reloadFromStore()
        } catch {
            lastError = "Could not save sample: \(error.localizedDescription)"
        }
    }

    private func classifyCurrentScreen(goal: Goal, app: FrontmostAppSnapshot) async -> VisionClassifierResult {
        do {
            let imageData = try await captureProvider.captureJPEGData(maxDimension: 1280, quality: 0.55)
            guard deduplicator.shouldClassify(imageData) else {
                return VisionClassifierResult(
                    focusState: .maybe,
                    activityCategory: "unchanged_screen",
                    confidence: 0.3,
                    evidenceCodes: ["duplicate_frame_skipped"],
                    nudgeSuggested: false
                )
            }

            let client = LocalVisionClient(endpoint: settings.endpoint, model: settings.model)
            return await client.classify(
                imageData: imageData,
                goal: goal,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier
            )
        } catch {
            lastError = "Screen capture unavailable: \(error.localizedDescription)"
            return .fallback()
        }
    }

    private func reloadFromStore() {
        do {
            if let fetchedGoals = try store?.fetchGoals(), !fetchedGoals.isEmpty {
                goals = fetchedGoals
            }
            recentSamples = try store?.fetchRecentSamples(limit: 30) ?? []
            stats = try store?.dailyStats(for: Date()) ?? stats
            lastFocusState = recentSamples.first?.focusState ?? lastFocusState
        } catch {
            lastError = "Could not reload activity: \(error.localizedDescription)"
        }
    }

    private func saveSettings() {
        do {
            try store?.saveSettings(settings)
        } catch {
            lastError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: settings.sampleIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sampleNow()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func statusText(for sample: ActivitySample, goal: Goal) -> String {
        switch sample.focusState {
        case .onGoal:
            "On mission for \(goal.title) in \(sample.appName)."
        case .maybe:
            "Maybe related: \(sample.activityCategory) in \(sample.appName)."
        case .offGoal:
            sample.nudgeShown
                ? "Nudge sent: \(sample.appName) looked off-goal."
                : "Off-goal detected, cooldown active."
        case .unknown:
            "Unknown: local vision endpoint or Screen Recording permission may need setup."
        }
    }
}
