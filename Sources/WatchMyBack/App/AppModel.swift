import Foundation
import Combine
import AppKit
import CoreGraphics
import WatchMyBackCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var goals: [Goal] = []
    @Published var selectedGoalID: UUID?
    @Published private(set) var recentSamples: [ActivitySample] = []
    @Published private(set) var activityWindowSummary = ActivityWindowSummary.empty()
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
    @Published private(set) var statusMessage = "Paused. Resume when you want Focula to observe focus hours."
    @Published private(set) var lastError: String?
    @Published private(set) var isSampling = false
    @Published private(set) var runtimeStatuses: [ModelRuntimeStatus] = []
    @Published private(set) var isInstallingBuiltInModel = false
    @Published private(set) var isTestingModel = false
    @Published private(set) var screenRecordingPermission = ScreenCapturePermissionDiagnostics.current()
    @Published private(set) var builtInModelFolders: [BuiltInModelFolder] = []
    @Published private(set) var isSystemSleeping = false

    private var store: DatabaseStore?
    private let appProvider: FrontmostAppProviding
    private let captureProvider: ScreenSnapshotProviding
    private let builtInRuntime = BuiltInRuntimeController()
    private let runtimeDetector = ModelRuntimeDetector()
    private let deduplicator = FrameDeduplicator()
    private let nudgeCoordinator = NudgeCoordinator()
    private let activityWindowAnalyzer = ActivityWindowAnalyzer()
    private let activitySampleRetentionDays = 14
    private let activitySampleRetentionPerGoal = 240
    private var timer: Timer?
    private var permissionRefreshTimer: Timer?
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private var screenshotContextFrames: [ScreenshotContextFrame] = []
    private var lastSampleAt: Date?

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
        startSleepWakeObservers()
        startPermissionRefreshTimer()
        NotificationNudgePresenter.shared.requestAuthorization()
        updateIdleTrackingStatus()
        if !settings.paused {
            startTimer()
        }
    }

    var activeGoal: Goal? {
        activeGoals.first ?? goals.first
    }

    var activeGoals: [Goal] {
        goals.filter(\.isActive)
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

    func shutdown() {
        stopTimer()
        stopSleepWakeObservers()
        builtInRuntime.stop()
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
        settings.sampleIntervalSeconds = min(max(15, value), 300)
        saveSettings()
        if !settings.paused && !isSystemSleeping {
            stopTimer()
            startTimer()
        }
    }

    func updateSamplingStrategy(_ value: SamplingStrategy) {
        settings.samplingStrategy = value
        saveSettings()
        if !settings.paused && !isSystemSleeping {
            stopTimer()
            startTimer()
        }
    }

    func updateMonitoringRules(_ value: MonitoringRules) {
        settings.monitoringRules = value
        saveSettings()
    }

    func updateNotificationPreferences(_ value: NotificationPreferences) {
        settings.notificationPreferences = value
        saveSettings()
    }

    func updateActivityLogVisibility(_ value: ActivityLogVisibility) {
        settings.activityLogVisibility = value
        saveSettings()
    }

    func updatePersistActivitySummaries(_ value: Bool) {
        settings.persistActivitySummaries = value
        saveSettings()
    }

    func saveMission(_ mission: Goal) {
        var mission = mission
        mission.title = mission.title.trimmingCharacters(in: .whitespacesAndNewlines)
        mission.description = mission.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mission.title.isEmpty else {
            lastError = "Mission needs a title."
            return
        }

        if goals.isEmpty {
            mission.isActive = true
        } else if goals.filter({ $0.id != mission.id }).allSatisfy({ !$0.isActive }) {
            mission.isActive = true
        }

        if store == nil {
            if let index = goals.firstIndex(where: { $0.id == mission.id }) {
                goals[index] = mission
            } else {
                goals.append(mission)
            }
            goals.sort { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive
                }
                return lhs.title < rhs.title
            }
            selectedGoalID = mission.id
            statusMessage = "\(mission.title) mission saved."
            return
        }

        do {
            try store?.saveGoal(mission)
            selectedGoalID = mission.id
            statusMessage = "\(mission.title) mission saved."
            reloadFromStore()
        } catch {
            lastError = "Could not save mission: \(error.localizedDescription)"
        }
    }

    func activateMission(_ mission: Goal) {
        setMissionTracking(mission, enabled: true)
    }

    func setMissionTracking(_ mission: Goal, enabled: Bool) {
        var mission = mission
        mission.isActive = enabled
        saveMission(mission)
    }

    func setMissionsTracking(ids: Set<UUID>, enabled: Bool) {
        let selected = goals.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }

        for var mission in selected {
            mission.isActive = enabled
            saveMission(mission)
        }
        statusMessage = "\(selected.count) mission\(selected.count == 1 ? "" : "s") \(enabled ? "tracking" : "paused")."
    }

    func deleteMissions(ids: Set<UUID>) {
        let selected = goals.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        selected.forEach(deleteMission)
        statusMessage = "\(selected.count) mission\(selected.count == 1 ? "" : "s") removed."
    }

    func duplicateMission(_ mission: Goal) {
        var copy = mission
        copy.id = UUID()
        copy.title = "\(mission.title) Copy"
        copy.isActive = false
        saveMission(copy)
    }

    func deleteMission(_ mission: Goal) {
        if store == nil {
            goals.removeAll { $0.id == mission.id }
            if goals.isEmpty {
                let starter = Goal.starter
                goals = [starter]
                selectedGoalID = starter.id
            } else {
                ensureActiveMissionAfterDeleting(missionID: mission.id)
            }
            statusMessage = "\(mission.title) mission removed."
            return
        }

        do {
            try store?.deleteGoal(id: mission.id)
            if try store?.fetchGoals().isEmpty == true {
                selectedGoalID = try store?.seedDefaultGoalIfNeeded().id
            }
            reloadFromStore()
            ensureActiveMissionAfterDeleting(missionID: mission.id)
            statusMessage = "\(mission.title) mission removed."
        } catch {
            lastError = "Could not remove mission: \(error.localizedDescription)"
        }
    }

    func togglePaused() {
        settings.paused.toggle()
        saveSettings()

        if settings.paused {
            stopTimer()
            updateIdleTrackingStatus()
        } else {
            updateIdleTrackingStatus()
            if !isSystemSleeping {
                startTimer()
            }
            Task { await sampleNow(manual: true) }
        }
    }

    func sampleNow(manual: Bool = false) async {
        guard !isSampling else { return }
        guard !isSystemSleeping else {
            statusMessage = "Quiet: Mac is sleeping. Tracking resumes after wake."
            return
        }
        let trackingGoals = activeGoals
        guard !trackingGoals.isEmpty else {
            statusMessage = "No tracking missions. Turn on tracking for at least one mission."
            return
        }

        let now = Date()
        let scheduledGoals = trackingGoals.filter { $0.schedule.contains(now) }
        if !manual, scheduledGoals.isEmpty {
            statusMessage = "Quiet: outside quest hours for tracking missions."
            return
        }
        let eligibleGoals = manual ? trackingGoals : scheduledGoals
        let attributionGoal = attributionGoal(from: eligibleGoals)
        let classifierGoal = classifierGoalContext(for: attributionGoal, activeGoals: eligibleGoals)

        isSampling = true
        defer { isSampling = false }

        let app = appProvider.currentApp()
        let result = await classifyCurrentScreen(goal: classifierGoal, app: app)

        var sample = ActivitySample(
            timestamp: now,
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            goalID: attributionGoal.id,
            focusState: result.focusState,
            activityCategory: result.activityCategory,
            activitySummary: settings.persistActivitySummaries
                ? ActivitySummaryRedactor.redact(result.activitySummary)
                : nil,
            confidence: result.confidence,
            durationSeconds: sampleDuration(at: now),
            nudgeShown: false
        )

        let windowSummary = activityWindowAnalyzer.summarize(samples: recentSamples, including: sample, now: now)
        let shouldNudge = windowSummary.isSustainedDrift && nudgeCoordinator.shouldNudge(
            focusState: .offGoal,
            schedule: attributionGoal.schedule,
            paused: settings.paused,
            now: now
        )
        sample.nudgeShown = shouldNudge

        if shouldNudge, settings.notificationPreferences.notifyOnSustainedDrift {
            NotificationNudgePresenter.shared.show(goal: attributionGoal, appName: app.appName)
            nudgeCoordinator.recordNudge(at: now)
        }

        do {
            try store?.saveActivitySample(sample)
            try pruneStoredActivitySamples(now: now)
            lastSampleAt = now
            activityWindowSummary = windowSummary
            lastFocusState = result.focusState
            statusMessage = statusText(for: sample, goal: attributionGoal, windowSummary: windowSummary)
            reloadFromStore()
        } catch {
            lastError = "Could not save sample: \(error.localizedDescription)"
        }
    }

    private func classifyCurrentScreen(goal: Goal, app: FrontmostAppSnapshot) async -> VisionClassifierResult {
        do {
            let capture = try await captureProvider.captureContextJPEGData(
                focusedWindowFrame: app.windowFrame,
                maxDimension: 1280,
                quality: 0.55
            )
            let imageData = capture.primaryImageData
            rememberContextFrame(imageData, app: app)
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
                contextImageData: capture.contextImageData + contextImageDataForCurrentFrame(),
                goal: goal,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier
            )
        } catch ScreenSnapshotError.permissionDenied {
            refreshScreenRecordingPermission()
            ScreenRecordingPermissionPresenter.shared.present()
            lastError = "Screen Recording permission is required before Focula can classify activity."
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

    private func attributionGoal(from goals: [Goal]) -> Goal {
        if let selectedGoalID,
           let selected = goals.first(where: { $0.id == selectedGoalID }) {
            return selected
        }
        return goals[0]
    }

    private func classifierGoalContext(for goal: Goal, activeGoals: [Goal]) -> Goal {
        var contextualGoal = goal
        let relatedGoals = activeGoals.filter { $0.id != goal.id }
        let relatedGoalText = relatedGoals
            .map { "- \($0.title): \($0.description)" }
            .joined(separator: "\n")
        var descriptionParts = ["Classify against all tracking missions that are inside quest hours."]
        descriptionParts.append("Primary mission: \(goal.title)\n\(goal.description)")
        if !relatedGoalText.isEmpty {
            descriptionParts.append("Other active tracking missions:")
            descriptionParts.append(relatedGoalText)
        }
        if settings.monitoringRules.unmatchedActivityIsSideTracked {
            descriptionParts.append("Treat visible activity that does not match any tracking goal as side tracked when confidence is reasonable.")
        }
        contextualGoal.description = descriptionParts
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
        contextualGoal.allowedApps = uniqued(goal.allowedApps + relatedGoals.flatMap(\.allowedApps))
        contextualGoal.blockedApps = uniqued(goal.blockedApps + relatedGoals.flatMap(\.blockedApps))
        contextualGoal.onGoalExamples = uniqued(goal.onGoalExamples + relatedGoals.flatMap(\.onGoalExamples))
        contextualGoal.offGoalExamples = uniqued(goal.offGoalExamples + relatedGoals.flatMap(\.offGoalExamples))
        return contextualGoal
    }

    private func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            seen.insert(value).inserted
        }
    }

    private func reloadFromStore() {
        do {
            if let fetchedGoals = try store?.fetchGoals(), !fetchedGoals.isEmpty {
                goals = fetchedGoals
            }
            recentSamples = try store?.fetchRecentSamples(limit: 240) ?? []
            activityWindowSummary = activityWindowAnalyzer.summarize(samples: recentSamples)
            stats = try store?.dailyStats(for: Date()) ?? stats
            lastFocusState = recentSamples.first?.focusState ?? lastFocusState
        } catch {
            lastError = "Could not reload activity: \(error.localizedDescription)"
        }
    }

    private func ensureActiveMissionAfterDeleting(missionID: UUID) {
        if selectedGoalID == missionID {
            selectedGoalID = activeGoal?.id
        }

        if goals.contains(where: \.isActive) {
            return
        }

        guard var fallback = goals.first else {
            return
        }

        fallback.isActive = true
        if store == nil {
            if let index = goals.firstIndex(where: { $0.id == fallback.id }) {
                goals[index] = fallback
            }
        } else {
            do {
                try store?.saveGoal(fallback)
                reloadFromStore()
            } catch {
                lastError = "Could not activate fallback mission: \(error.localizedDescription)"
            }
        }
        selectedGoalID = fallback.id
    }

    private func saveSettings() {
        do {
            try store?.saveSettings(settings)
        } catch {
            lastError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func updateIdleTrackingStatus() {
        if isSystemSleeping {
            statusMessage = "Quiet: Mac is sleeping. Tracking resumes after wake."
        } else if settings.paused {
            statusMessage = "Paused. No screenshots or activity samples are being captured."
        } else if activeGoals.isEmpty {
            statusMessage = "No tracking missions. Turn on tracking for at least one mission."
        } else if activeGoals.count == 1, let activeGoal {
            statusMessage = "Tracking quest hours for \(activeGoal.title). Screenshots are classified locally and discarded."
        } else {
            statusMessage = "Tracking quest hours for \(activeGoals.count) tracking missions. Screenshots are classified locally and discarded."
        }
    }

    private func clearResolvedSetupStatusIfNeeded() {
        guard !isSampling else { return }
        guard settings.modelSelection.provider == .builtInGemma,
              settings.builtInModelStatus.installState == .ready
        else { return }

        if statusMessage == "Finish local model setup in Settings before Scout can summarize activity."
            || statusMessage == "Install or test the selected built-in Gemma model in Settings." {
            updateIdleTrackingStatus()
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
        clearResolvedSetupStatusIfNeeded()
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
        guard !isSystemSleeping else { return }
        let interval = nextSampleInterval()
        guard interval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.sampleNow()
                if !self.settings.paused && !self.isSystemSleeping {
                    self.startTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func nextSampleInterval() -> TimeInterval {
        SamplingPolicy.nextInterval(
            strategy: settings.samplingStrategy,
            configuredInterval: settings.sampleIntervalSeconds,
            idleSeconds: recentInputIdleSeconds()
        )
    }

    private func recentInputIdleSeconds() -> TimeInterval {
        [
            CGEventType.mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .scrollWheel,
            .keyDown
        ]
        .map {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: $0
            )
        }
        .min() ?? 300
    }

    private func sampleDuration(at now: Date) -> TimeInterval {
        SamplingPolicy.sampleDuration(
            lastSampleAt: lastSampleAt,
            now: now,
            fallbackInterval: settings.sampleIntervalSeconds
        )
    }

    private func pruneStoredActivitySamples(now: Date) throws {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -activitySampleRetentionDays,
            to: now
        ) else { return }

        _ = try store?.pruneActivitySamples(
            olderThan: cutoff,
            keepingRecentPerGoal: activitySampleRetentionPerGoal
        )
    }

    private func rememberContextFrame(_ imageData: Data, app: FrontmostAppSnapshot) {
        screenshotContextFrames.append(ScreenshotContextFrame(
            timestamp: Date(),
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            imageData: imageData
        ))
        pruneContextFrames()
    }

    private func contextImageDataForCurrentFrame() -> [Data] {
        pruneContextFrames()
        return screenshotContextFrames
            .dropLast()
            .suffix(5)
            .map(\.imageData)
    }

    private func pruneContextFrames(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-300)
        screenshotContextFrames = Array(
            screenshotContextFrames
                .filter { $0.timestamp >= cutoff }
                .suffix(6)
        )
    }

    private func startPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenRecordingPermission()
            }
        }
    }

    private func startSleepWakeObservers() {
        stopSleepWakeObservers()
        let center = NSWorkspace.shared.notificationCenter
        sleepWakeObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleSystemWillSleep()
                }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleSystemDidWake()
                }
            }
        ]
    }

    private func stopSleepWakeObservers() {
        sleepWakeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        sleepWakeObservers.removeAll()
    }

    private func handleSystemWillSleep() {
        isSystemSleeping = true
        stopTimer()
        builtInRuntime.stop()
        statusMessage = "Quiet: Mac is sleeping. Tracking resumes after wake."
        refreshRuntimeStatuses()
    }

    private func handleSystemDidWake() {
        isSystemSleeping = false
        updateIdleTrackingStatus()
        refreshRuntimeStatuses()
        if !settings.paused {
            startTimer()
        }
    }

    private func statusText(
        for sample: ActivitySample,
        goal: Goal,
        windowSummary: ActivityWindowSummary
    ) -> String {
        switch sample.activityCategory {
        case "built_in_model_not_ready":
            return "Finish local model setup in Settings before Scout can summarize activity."
        case "built_in_model_runtime_error":
            return "Local model needs a test or restart in Settings."
        case "screen_recording_permission_missing":
            return "Grant Screen Recording so Scout can classify activity locally."
        case "cloud_blocked":
            return "Cloud classification is blocked until screenshot opt-in is enabled."
        case "classifier_unavailable", "parse_failed":
            return "The selected model did not return a usable activity result. Check model settings."
        default:
            break
        }

        if sample.nudgeShown {
            return "Comeback nudge sent after sustained drift from \(goal.title)."
        }

        switch windowSummary.state {
        case .drifting:
            return "Drift is building. Focula will nudge after cooldown and schedule checks."
        case .onTrack:
            return "On mission for \(goal.title)."
        case .mixed:
            return "Gathering recent activity context for \(goal.title)."
        case .unknown:
            if !screenRecordingPermission.isGranted {
                return "Screen Recording is required before Focula can classify activity."
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

private struct ScreenshotContextFrame {
    let timestamp: Date
    let appName: String
    let bundleIdentifier: String?
    let imageData: Data
}
