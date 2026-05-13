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
    @Published private(set) var runtimeStatuses: [ModelRuntimeStatus] = []
    @Published private(set) var isInstallingBuiltInModel = false
    @Published private(set) var isTestingModel = false
    @Published private(set) var screenRecordingPermission = ScreenCapturePermissionDiagnostics.current()

    private var store: DatabaseStore?
    private let appProvider: FrontmostAppProviding
    private let captureProvider: ScreenSnapshotProviding
    private let builtInRuntime = BuiltInRuntimeController()
    private let runtimeDetector = ModelRuntimeDetector()
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
            settings.builtInModelStatus = builtInRuntime.currentStatus()
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

        refreshRuntimeStatuses()
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
        (settings.modelSelection.endpoint ?? settings.endpoint).absoluteString
    }

    var selectedModelStatus: ModelRuntimeStatus? {
        runtimeStatuses.first(where: { $0.provider == settings.modelSelection.provider })
    }

    var selectedModelLabel: String {
        settings.modelSelection.provider == .builtInGemma
            ? BuiltInModelCatalog.gemma4E2B.displayName
            : settings.modelSelection.displayName
    }

    var selectedModelStatusText: String {
        selectedModelStatus?.statusMessage ?? settings.builtInModelStatus.statusMessage
    }

    var screenRecordingPermissionLabel: String {
        screenRecordingPermission.isGranted ? "Enabled" : "Needs permission"
    }

    func refreshScreenRecordingPermission() {
        screenRecordingPermission = .current()
    }

    func openScreenRecordingGuide() {
        refreshScreenRecordingPermission()
        if !screenRecordingPermission.isGranted {
            ScreenRecordingPermissionPresenter.shared.present()
        }
    }

    func updateEndpoint(_ value: String) {
        guard let url = URL(string: value), url.scheme != nil else { return }
        settings.endpoint = url
        settings.modelSelection.endpoint = url
        saveSettings()
        refreshRuntimeStatuses()
    }

    func updateModelName(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        settings.model = cleaned
        settings.modelSelection.modelID = cleaned
        saveSettings()
        refreshRuntimeStatuses()
    }

    func switchModelProvider(_ provider: ModelProvider) {
        settings.modelSelection.provider = provider

        switch provider {
        case .builtInGemma:
            settings.modelSelection.modelID = BuiltInModelCatalog.gemma4E2B.id
            settings.modelSelection.endpoint = nil
            settings.model = BuiltInModelCatalog.gemma4E2B.id
        case .oMLX:
            settings.modelSelection.modelID = settings.modelSelection.modelID.isEmpty ? "mlx-community/gemma-4-e2b-it" : settings.modelSelection.modelID
            settings.modelSelection.endpoint = settings.modelSelection.endpoint ?? URL(string: "http://127.0.0.1:8123/v1/chat/completions")!
        case .lmStudio:
            settings.modelSelection.modelID = settings.modelSelection.modelID.isEmpty ? "local-vision" : settings.modelSelection.modelID
            settings.modelSelection.endpoint = settings.modelSelection.endpoint ?? URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
        case .openAICompatible:
            settings.modelSelection.modelID = settings.modelSelection.modelID.isEmpty ? settings.model : settings.modelSelection.modelID
            settings.modelSelection.endpoint = settings.modelSelection.endpoint ?? settings.endpoint
        case .cloudOptIn:
            settings.modelSelection.modelID = settings.modelSelection.modelID.isEmpty ? "cloud-vision" : settings.modelSelection.modelID
            settings.modelSelection.endpoint = settings.modelSelection.endpoint ?? settings.endpoint
            settings.modelSelection.cloudClassificationAllowed = false
        }

        saveSettings()
        refreshRuntimeStatuses()
    }

    func updateCloudClassificationAllowed(_ allowed: Bool) {
        settings.modelSelection.cloudClassificationAllowed = allowed
        saveSettings()
        refreshRuntimeStatuses()
    }

    func installBuiltInModel() async {
        guard !isInstallingBuiltInModel else { return }
        isInstallingBuiltInModel = true
        settings.builtInModelStatus = ModelRuntimeStatus(
            provider: .builtInGemma,
            modelID: BuiltInModelCatalog.gemma4E2B.id,
            installState: .downloading,
            statusMessage: "Installing private Python runtime and downloading Gemma 4 E2B...",
            storagePath: try? ModelSupportPaths.builtInModelRoot().path,
            isVisionCapable: true,
            isUsable: false
        )
        statusMessage = settings.builtInModelStatus.statusMessage
        saveSettings()
        refreshRuntimeStatuses()

        do {
            settings.builtInModelStatus = try await builtInRuntime.installDefaultModel()
            statusMessage = "Built-in Gemma ready. Screenshots stay local and are discarded after classification."
        } catch {
            settings.builtInModelStatus = ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: BuiltInModelCatalog.gemma4E2B.id,
                installState: .failed,
                statusMessage: "Built-in model install failed.",
                storagePath: try? ModelSupportPaths.builtInModelRoot().path,
                isVisionCapable: true,
                isUsable: false
            )
            lastError = error.localizedDescription
        }

        isInstallingBuiltInModel = false
        saveSettings()
        refreshRuntimeStatuses()
    }

    func deleteBuiltInModel() {
        do {
            settings.builtInModelStatus = try builtInRuntime.deleteDefaultModel()
            statusMessage = "Built-in model removed. Install again before using built-in Gemma."
            saveSettings()
            refreshRuntimeStatuses()
        } catch {
            lastError = "Could not delete built-in model: \(error.localizedDescription)"
        }
    }

    func pauseModelRuntime() {
        builtInRuntime.stop()
        statusMessage = "Built-in model sidecar paused."
        refreshRuntimeStatuses()
    }

    func testSelectedModel() async {
        guard !isTestingModel else { return }
        isTestingModel = true
        defer { isTestingModel = false }

        if settings.modelSelection.provider == .builtInGemma {
            do {
                try await builtInRuntime.ensureRunning()
                settings.builtInModelStatus = builtInRuntime.currentStatus()
                statusMessage = "Built-in Gemma sidecar responded."
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Built-in Gemma is not ready."
            }
        } else if settings.modelSelection.provider == .cloudOptIn,
                  !settings.modelSelection.cloudClassificationAllowed {
            statusMessage = "Cloud model blocked until screenshot opt-in is enabled."
        } else {
            statusMessage = "Provider configured. Classification test will run on the next sample."
        }

        saveSettings()
        refreshRuntimeStatuses()
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

            if settings.modelSelection.provider == .builtInGemma {
                guard settings.builtInModelStatus.installState == .ready else {
                    return BuiltInGemmaClient.notReadyFallback()
                }
                try await builtInRuntime.ensureRunning()
                settings.builtInModelStatus = builtInRuntime.currentStatus()
                refreshRuntimeStatuses()
            }

            let client = ModelRouter.classifier(
                for: settings,
                builtInClient: BuiltInGemmaClient(endpoint: builtInRuntime.endpoint)
            )
            return await client.classify(
                imageData: imageData,
                goal: goal,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier
            )
        } catch ScreenSnapshotError.permissionDenied {
            refreshScreenRecordingPermission()
            ScreenRecordingPermissionPresenter.shared.present()
            lastError = "Screen Recording permission is required before Watch My Back can classify activity."
            return VisionClassifierResult(
                focusState: .unknown,
                activityCategory: "screen_recording_permission_missing",
                confidence: 0,
                evidenceCodes: ["screen_recording_permission_required"],
                nudgeSuggested: false
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

    private func refreshRuntimeStatuses() {
        if settings.builtInModelStatus.installState != .downloading {
            settings.builtInModelStatus = builtInRuntime.currentStatus()
        }
        runtimeStatuses = runtimeDetector.statuses(
            selected: settings.modelSelection,
            builtInStatus: settings.builtInModelStatus
        )
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
            "Unknown: model runtime or Screen Recording permission may need setup."
        }
    }
}
