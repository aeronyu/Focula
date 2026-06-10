import SwiftUI
import FoculaCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showInstallConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var selectedModelFolderPaths: Set<String> = []
    @State private var selectedTab: SettingsTab = .model

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsPage(modelPage)
                .tabItem { Label("Model", systemImage: "cpu") }
                .tag(SettingsTab.model)

            settingsPage(privacyPage)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)

            settingsPage(monitoringPage)
                .tabItem { Label("Monitoring", systemImage: "scope") }
                .tag(SettingsTab.monitoring)

            settingsPage(samplingPage)
                .tabItem { Label("Sampling", systemImage: "waveform.path.ecg") }
                .tag(SettingsTab.sampling)

            settingsPage(notificationPage)
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag(SettingsTab.notifications)
        }
        .frame(minWidth: 720, minHeight: 620)
        .onAppear {
            model.refreshBuiltInModelFolders()
            syncSelectedModelFoldersIfNeeded()
        }
        .onChange(of: model.builtInModelFolders) { _, _ in
            selectedModelFolderPaths = selectedModelFolderPaths.intersection(Set(model.builtInModelFolders.map(\.path)))
            syncSelectedModelFoldersIfNeeded()
        }
        .alert(installConfirmationTitle, isPresented: $showInstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(model.settings.builtInModelStatus.installState == .ready ? "Reinstall" : "Download") {
                Task { await model.installBuiltInModel() }
            }
        } message: {
            Text(installConfirmationMessage)
        }
        .alert("Delete selected model folders?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Folders", role: .destructive) {
                model.deleteBuiltInModelFolders(paths: selectedModelFolderPaths)
                selectedModelFolderPaths.removeAll()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private func settingsPage<Content: View>(_ content: Content) -> some View {
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity)
        }
    }

    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Runtime") {
                Picker(
                    "Runtime",
                    selection: Binding(
                        get: { model.settings.modelSelection.provider },
                        set: { model.switchModelProvider($0) }
                    )
                ) {
                    ForEach(ModelProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                LabeledContent("Current", value: model.selectedModelLabel)
                LabeledContent("Status", value: model.selectedModelStatusText)
                Text(model.settings.modelSelection.provider.setupSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.settings.modelSelection.provider != .builtInGemma {
                SettingsCard(providerSettingsTitle) {
                    TextField("Endpoint", text: Binding(get: { model.endpointString }, set: { model.updateEndpoint($0) }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: Binding(get: { model.settings.modelSelection.modelID }, set: { model.updateModelName($0) }))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button { model.resetSelectedProviderDefaults() } label: {
                            Label("Use Defaults", systemImage: "arrow.counterclockwise")
                        }
                        Button { Task { await model.testSelectedModel() } } label: {
                            Label("Test Connection", systemImage: "checkmark.circle")
                        }
                        .disabled(model.isTestingModel)
                    }
                    providerPermissionView
                }
            }

            SettingsCard("Built-in local models") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(BuiltInModelCatalog.all) { descriptor in
                        BuiltInModelCard(
                            descriptor: descriptor,
                            isSelected: descriptor.id == model.selectedBuiltInModelDescriptor.id
                        ) {
                            model.selectBuiltInModel(id: descriptor.id)
                        }
                    }
                }

                if let path = model.settings.builtInModelStatus.storagePath {
                    LabeledContent("Storage") {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                installedModelFolders
                builtInModelActions

                Text(model.selectedBuiltInModelDescriptor.localOnlyNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Permissions") {
                LabeledContent("Screen Recording", value: model.screenRecordingPermissionLabel)
                HStack {
                    Button { model.openScreenRecordingGuide() } label: {
                        Label("Open Permission Guide", systemImage: "camera.viewfinder")
                    }
                    .disabled(model.screenRecordingPermission.isGranted)
                    Button { model.refreshScreenRecordingPermission() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                Text("The guide opens System Settings and shows a draggable Focula tile for Screen & System Audio Recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerPermissionView: some View {
        Group {
            if model.settings.modelSelection.provider == .cloudOptIn {
                Toggle(
                    "Allow screenshots to leave this Mac",
                    isOn: Binding(
                        get: { model.settings.modelSelection.cloudClassificationAllowed },
                        set: { model.updateCloudClassificationAllowed($0) }
                    )
                )
                Text("Cloud classification stays blocked until this is enabled.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(providerHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var installedModelFolders: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Installed folders")
                    .font(.subheadline)
                Spacer()
                Button {
                    model.refreshBuiltInModelFolders()
                    syncSelectedModelFoldersIfNeeded()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if model.builtInModelFolders.isEmpty {
                Text("No built-in model folders found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.builtInModelFolders) { folder in
                    Toggle(isOn: modelFolderSelectionBinding(folder.path)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                            Text(folder.folderName)
                                .font(.caption.monospaced())
                                .foregroundStyle(folder.isLegacy ? .orange : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var builtInModelActions: some View {
        HStack {
            Button { showInstallConfirmation = true } label: {
                Label(
                    model.settings.builtInModelStatus.installState == .ready ? "Reinstall" : "Install",
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(model.isInstallingBuiltInModel || !model.selectedBuiltInModelDescriptor.isInstallable)

            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .disabled(model.isInstallingBuiltInModel || selectedModelFolderPaths.isEmpty)

            Button { Task { await model.testSelectedModel() } } label: {
                Label("Test", systemImage: "checkmark.circle")
            }
            .disabled(model.isTestingModel || model.isInstallingBuiltInModel || !model.selectedBuiltInModelDescriptor.isInstallable)

            Button { model.openBuiltInModelsFolder() } label: {
                Label("Open Folder", systemImage: "folder")
            }
        }
    }

    private var privacyPage: some View {
        SettingsCard("Privacy") {
            Toggle(isOn: Binding(
                get: { model.settings.persistActivitySummaries },
                set: { enabled in model.updatePersistActivitySummaries(enabled) }
            )) {
                SettingLabel(
                    title: "Save safe activity summaries",
                    info: "Stores only short redacted activity phrases for the dashboard log. Raw screenshots, OCR, visible text, prompts, and image data are never stored."
                )
            }
            Text("When enabled, Focula stores a short redacted activity summary for the dashboard feed. Raw screenshots, OCR, visible text, prompts, and image data are still not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Activity log", selection: Binding(
                get: { model.settings.activityLogVisibility },
                set: { visibility in model.updateActivityLogVisibility(visibility) }
            )) {
                ForEach(ActivityLogVisibility.allCases) { visibility in
                    Text(visibility.displayName).tag(visibility)
                }
            }
        }
    }

    private var monitoringPage: some View {
        SettingsCard("Monitoring Rules") {
            Toggle(isOn: Binding(
                get: { model.settings.monitoringRules.anyTrackingGoalCountsAsFocused },
                set: { enabled in updateAnyGoalRule(enabled) }
            )) {
                SettingLabel(
                    title: "Any tracking goal can count as focused",
                    info: "When enabled, visible work that clearly matches any saved tracking goal can be counted as focused, even if it is not the currently selected mission."
                )
            }
            Toggle(isOn: Binding(
                get: { model.settings.monitoringRules.unmatchedActivityIsSideTracked },
                set: { enabled in updateUnmatchedRule(enabled) }
            )) {
                SettingLabel(
                    title: "Unmatched visible activity is side tracked",
                    info: "When enabled, visible activity that does not match any tracking goal is treated as side tracked when Scout has reasonable confidence."
                )
            }
            Text("The scout reviews the focused screen plus relevant visible context from other displayed screens, then ignores unrelated screen content.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var samplingPage: some View {
        SettingsCard("Sampling") {
            Picker("Strategy", selection: Binding(
                get: { model.settings.samplingStrategy },
                set: { strategy in model.updateSamplingStrategy(strategy) }
            )) {
                ForEach(SamplingStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            Text(model.settings.samplingStrategy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.settings.samplingStrategy == .balanced {
                Stepper(
                    value: Binding(
                        get: { model.settings.sampleIntervalSeconds },
                        set: { interval in model.updateSampleInterval(interval) }
                    ),
                    in: 60...300,
                    step: 15
                ) {
                    Text("Balanced base interval: \(Int(model.settings.sampleIntervalSeconds)) seconds")
                }
            }
        }
    }

    private var notificationPage: some View {
        SettingsCard("Alerts") {
            Toggle(isOn: Binding(
                get: { model.settings.notificationPreferences.notifyOnSustainedDrift },
                set: { enabled in updateDriftAlert(enabled) }
            )) {
                SettingLabel(
                    title: "Alert on sustained drift",
                    info: "Sustained drift means recent check-ins show enough repeated off-goal time inside quest hours to pass the drift threshold and notification cooldown."
                )
            }
            Toggle(isOn: Binding(
                get: { model.settings.notificationPreferences.notifyOnRuntimeFailure },
                set: { enabled in updateRuntimeAlert(enabled) }
            )) {
                SettingLabel(
                    title: "Alert on model or runtime failures",
                    info: "Shows alerts when the local model, provider endpoint, or screen-capture runtime cannot produce a usable classification."
                )
            }
            if let lastError = model.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var installConfirmationTitle: String {
        model.settings.builtInModelStatus.installState == .ready
            ? "Reinstall built-in model?"
            : "Download built-in model?"
    }

    private var installConfirmationMessage: String {
        let descriptor = model.selectedBuiltInModelDescriptor
        return "Focula will download \(descriptor.displayName) from \(descriptor.repository). Estimated size: \(descriptor.estimatedDownloadSize). Classification stays local and raw screenshots are discarded after each request."
    }

    private var providerSettingsTitle: String {
        "\(model.settings.modelSelection.provider.displayName) connection"
    }

    private var providerHelpText: String {
        switch model.settings.modelSelection.provider {
        case .oMLX:
            return "oMLX is optional. Focula will not install it; point this at an existing oMLX/OpenAI-compatible vision server."
        case .lmStudio:
            return "In LM Studio, start the local server and load a vision-capable model. Then match the endpoint and model id here."
        case .openAICompatible:
            return "Use a local OpenAI-compatible vision server. Endpoint should usually end with /v1/chat/completions."
        case .cloudOptIn:
            return "Cloud provider settings."
        case .builtInGemma:
            return ""
        }
    }

    private var deleteConfirmationMessage: String {
        let names = model.builtInModelFolders
            .filter { selectedModelFolderPaths.contains($0.path) }
            .map(\.folderName)
            .joined(separator: ", ")
        return "This removes only the selected folder\(selectedModelFolderPaths.count == 1 ? "" : "s"): \(names). Other downloaded models stay on this Mac."
    }

    private func modelFolderSelectionBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selectedModelFolderPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedModelFolderPaths.insert(path)
                } else {
                    selectedModelFolderPaths.remove(path)
                }
            }
        )
    }

    private func updateAnyGoalRule(_ enabled: Bool) {
        var rules = model.settings.monitoringRules
        rules.anyTrackingGoalCountsAsFocused = enabled
        model.updateMonitoringRules(rules)
    }

    private func updateUnmatchedRule(_ enabled: Bool) {
        var rules = model.settings.monitoringRules
        rules.unmatchedActivityIsSideTracked = enabled
        model.updateMonitoringRules(rules)
    }

    private func updateDriftAlert(_ enabled: Bool) {
        var preferences = model.settings.notificationPreferences
        preferences.notifyOnSustainedDrift = enabled
        model.updateNotificationPreferences(preferences)
    }

    private func updateRuntimeAlert(_ enabled: Bool) {
        var preferences = model.settings.notificationPreferences
        preferences.notifyOnRuntimeFailure = enabled
        model.updateNotificationPreferences(preferences)
    }

    private func syncSelectedModelFoldersIfNeeded() {
        guard selectedModelFolderPaths.isEmpty else { return }
        let currentPath = model.settings.builtInModelStatus.storagePath
        if let current = model.builtInModelFolders.first(where: { $0.path == currentPath }) {
            selectedModelFolderPaths = [current.path]
        }
    }
}

private enum SettingsTab: Hashable {
    case model
    case privacy
    case monitoring
    case sampling
    case notifications
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BuiltInModelCard: View {
    let descriptor: BuiltInModelDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(descriptor.repository)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    ModelBadge(descriptor.precision)
                    ModelBadge(descriptor.estimatedDownloadSize)
                }

                Label(descriptor.expectedMemory, systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if descriptor.isRecommended {
                    Label("Recommended", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if !descriptor.isInstallable {
                    Label("Manual setup", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(descriptor.localOnlyNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.green.opacity(0.55) : Color.secondary.opacity(0.16), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModelBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

private struct SettingLabel: View {
    let title: String
    let info: String
    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button {
                showsInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(info)
            .popover(isPresented: $showsInfo, arrowEdge: .trailing) {
                Text(info)
                    .font(.callout)
                    .padding(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 320, alignment: .leading)
            }
        }
    }
}
