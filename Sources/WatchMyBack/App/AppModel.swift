import Foundation
import Combine
import AppKit
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
    @Published private(set) var builtInModelFolders: [BuiltInModelFolder] = []

    private var store: DatabaseStore?
    private let appProvider: FrontmostAppProviding
    private let captureProvider: ScreenSnapshotProviding
    private let builtInRuntime = BuiltInRuntimeController()
    private let runtimeDetector = ModelRuntimeDetector()
    private let deduplicator = FrameDeduplicator()
    private let nudgeCoordinator = NudgeCoordinator()
    private let activityWindowAnalyzer = ActivityWindowAnalyzer()
    private var timer: Timer?
    private var permissionRefreshTimer: Timer?

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
            normalizeBuiltInModelSelection()
            settings.builtInModelStatus = builtInRuntime.currentStatus(for: selectedBuiltInModelDescriptor)
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
        refreshBuiltInModelFolders()
        startPermissionRefreshTimer()
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

    var selectedBuiltInModelDescriptor: BuiltInModelDescriptor {
        if settings.modelSelection.provider == .builtInGemma {
            return BuiltInModelCatalog.descriptorOrDefault(for: settings.modelSelection.modelID)
        }
        return BuiltInModelCatalog.descriptorOrDefault(for: settings.builtInModelStatus.modelID)
    }

    var selectedModelLabel: String {
        settings.modelSelection.provider == .builtInGemma
            ? selectedBuiltInModelDescriptor.displayName
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

    func openBuiltInModelsFolder() {
        do {
            let url = try ModelSupportPaths.builtInModelsRoot()
            NSWorkspace.shared.open(url)
            refreshBuiltInModelFolders()
        } catch {
            lastError = "Could not open model folder: \(error.localizedDescription)"
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
        let previousProvider = settings.modelSelection.provider
        settings.modelSelection.provider = provider

        switch provider {
        case .builtInGemma:
            let descriptor = BuiltInModelCatalog.descriptor(for: settings.builtInModelStatus.modelID)
                ?? BuiltInModelCatalog.descriptor(for: settings.modelSelection.modelID)
                ?? BuiltInModelCatalog.defaultModel
            settings.modelSelection.modelID = descriptor.id
            settings.modelSelection.endpoint = nil
            settings.model = descriptor.id
            settings.builtInModelStatus = builtInRuntime.currentStatus(for: descriptor)
        case .oMLX:
            applyProviderDefaultsIfNeeded(provider, previousProvider: previousProvider)
        case .lmStudio:
            applyProviderDefaultsIfNeeded(provider, previousProvider: previousProvider)
        case .openAICompatible:
            applyProviderDefaultsIfNeeded(provider, previousProvider: previousProvider)
        case .cloudOptIn:
            applyProviderDefaultsIfNeeded(provider, previousProvider: previousProvider)
            settings.modelSelection.cloudClassificationAllowed = false
        }

        saveSettings()
        refreshRuntimeStatuses()
    }

    func selectBuiltInModel(id: String) {
        let descriptor = BuiltInModelCatalog.descriptorOrDefault(for: id)
        if settings.builtInModelStatus.modelID != descriptor.id {
            builtInRuntime.stop()
        }
        settings.modelSelection.provider = .builtInGemma
        settings.modelSelection.modelID = descriptor.id
        settings.modelSelection.endpoint = nil
        settings.model = descriptor.id
        settings.builtInModelStatus = builtInRuntime.currentStatus(for: descriptor)
        statusMessage = settings.builtInModelStatus.statusMessage
        saveSettings()
        refreshRuntimeStatuses()
    }

    func updateCloudClassificationAllowed(_ allowed: Bool) {
        settings.modelSelection.cloudClassificationAllowed = allowed
        saveSettings()
        refreshRuntimeStatuses()
    }

    func resetSelectedProviderDefaults() {
        let provider = settings.modelSelection.provider
        guard provider != .builtInGemma else { return }
        settings.modelSelection.modelID = provider.defaultModelID
        settings.modelSelection.endpoint = provider.defaultEndpoint
        settings.model = provider.defaultModelID
        if let endpoint = provider.defaultEndpoint {
            settings.endpoint = endpoint
        }
        saveSettings()
        refreshRuntimeStatuses()
    }

    func installBuiltInModel() async {
        guard !isInstallingBuiltInModel else { return }
        let descriptor = selectedBuiltInModelDescriptor
        isInstallingBuiltInModel = true
        settings.builtInModelStatus = ModelRuntimeStatus(
            provider: .builtInGemma,
            modelID: descriptor.id,
            installState: .downloading,
            statusMessage: "Installing private Python runtime and downloading \(descriptor.displayName)...",
            storagePath: try? ModelSupportPaths.builtInModelRoot(for: descriptor).path,
            isVisionCapable: true,
            isUsable: false
        )
        statusMessage = settings.builtInModelStatus.statusMessage
        saveSettings()
        refreshRuntimeStatuses()

        do {
            settings.builtInModelStatus = try await builtInRuntime.installModel(descriptor)
            statusMessage = "\(descriptor.displayName) ready. Screenshots stay local and are discarded after classification."
        } catch {
            settings.builtInModelStatus = ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: descriptor.id,
                installState: .failed,
                statusMessage: "Built-in model install failed.",
                storagePath: try? ModelSupportPaths.builtInModelRoot(for: descriptor).path,
                isVisionCapable: true,
                isUsable: false
            )
            lastError = error.localizedDescription
        }

        isInstallingBuiltInModel = false
        saveSettings()
        refreshRuntimeStatuses()
        refreshBuiltInModelFolders()
    }

    func deleteBuiltInModel() {
        deleteBuiltInModelFolders(paths: Set(settings.builtInModelStatus.storagePath.map { [$0] } ?? []))
    }

    func deleteBuiltInModelFolders(paths: Set<String>) {
        do {
            let deletedCount = paths.count
            try builtInRuntime.deleteModelFolders(paths: Array(paths))
            settings.builtInModelStatus = builtInRuntime.currentStatus(for: selectedBuiltInModelDescriptor)
            statusMessage = "Deleted \(deletedCount) selected model folder\(deletedCount == 1 ? "" : "s")."
            saveSettings()
            refreshRuntimeStatuses()
            refreshBuiltInModelFolders()
        } catch {
            lastError = "Could not delete selected model folders: \(error.localizedDescription)"
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
                let descriptor = selectedBuiltInModelDescriptor
                try await builtInRuntime.ensureRunning(model: descriptor)
                settings.builtInModelStatus = builtInRuntime.currentStatus(for: descriptor)
                statusMessage = "\(descriptor.displayName) sidecar responded."
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

        var sample = ActivitySample(
            timestamp: now,
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            goalID: goal.id,
            focusState: result.focusState,
            activityCategory: result.activityCategory,
            confidence: result.confidence,
            durationSeconds: settings.sampleIntervalSeconds,
            nudgeShown: false
        )

        let windowSummary = activityWindowAnalyzer.summarize(samples: [sample] + recentSamples, now: now)
        let shouldNudge = windowSummary.isSustainedDrift && nudgeCoordinator.shouldNudge(
            focusState: .offGoal,
            schedule: goal.schedule,
            paused: settings.paused,
            now: now
        )
        sample.nudgeShown = shouldNudge

        if shouldNudge {
            NotificationNudgePresenter.shared.show(goal: goal, appName: app.appName)
            nudgeCoordinator.recordNudge(at: now)
        }

        do {
            try store?.saveActivitySample(sample)
            lastFocusState = result.focusState
            statusMessage = statusText(for: sample, goal: goal, windowSummary: windowSummary)
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
                let descriptor = selectedBuiltInModelDescriptor
                guard settings.builtInModelStatus.installState == .ready else {
                    return BuiltInGemmaClient.notReadyFallback()
                }
                try await builtInRuntime.ensureRunning(model: descriptor)
                settings.builtInModelStatus = builtInRuntime.currentStatus(for: descriptor)
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
            settings.builtInModelStatus = builtInRuntime.currentStatus(for: selectedBuiltInModelDescriptor)
        }
        runtimeStatuses = runtimeDetector.statuses(
            selected: settings.modelSelection,
            builtInStatus: settings.builtInModelStatus
        )
    }

    private func applyProviderDefaultsIfNeeded(_ provider: ModelProvider, previousProvider: ModelProvider) {
        let shouldResetModel = previousProvider != provider
            || BuiltInModelCatalog.descriptor(for: settings.modelSelection.modelID) != nil
            || settings.modelSelection.modelID.isEmpty
        if shouldResetModel {
            settings.modelSelection.modelID = provider.defaultModelID
            settings.model = provider.defaultModelID
        }

        if previousProvider != provider || settings.modelSelection.endpoint == nil {
            settings.modelSelection.endpoint = provider.defaultEndpoint
        }

        if let endpoint = settings.modelSelection.endpoint {
            settings.endpoint = endpoint
        }
    }

    func refreshBuiltInModelFolders() {
        do {
            builtInModelFolders = try ModelSupportPaths.installedBuiltInModelFolders()
        } catch {
            lastError = "Could not inspect built-in model folders: \(error.localizedDescription)"
            builtInModelFolders = []
        }
    }

    private func normalizeBuiltInModelSelection() {
        guard settings.modelSelection.provider == .builtInGemma else { return }
        let descriptor = BuiltInModelCatalog.descriptorOrDefault(for: settings.modelSelection.modelID)
        settings.modelSelection.modelID = descriptor.id
        settings.modelSelection.endpoint = nil
        settings.model = descriptor.id
        settings.builtInModelStatus.modelID = descriptor.id
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

    private func startPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenRecordingPermission()
            }
        }
    }

    private func statusText(
        for sample: ActivitySample,
        goal: Goal,
        windowSummary: ActivityWindowSummary
    ) -> String {
        if sample.nudgeShown {
            return "Comeback nudge sent after sustained drift from \(goal.title)."
        }

        switch windowSummary.state {
        case .drifting:
            return "Drift is building. Watch My Back will nudge after cooldown and schedule checks."
        case .onTrack:
            return "On mission for \(goal.title)."
        case .mixed:
            return "Gathering recent activity context for \(goal.title)."
        case .unknown:
            if !screenRecordingPermission.isGranted {
                return "Screen Recording is required before Watch My Back can classify activity."
            }
            if settings.modelSelection.provider == .builtInGemma,
               settings.builtInModelStatus.installState != .ready {
                return "Install or test the selected built-in Gemma model in Settings."
            }
            return "Unknown: check the selected provider endpoint, model id, and runtime status in Settings."
        case .noSamples:
            return "First check-in recorded for \(goal.title)."
        }
    }
}
