import SwiftUI
import WatchMyBackCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showInstallConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var selectedModelFolderPaths: Set<String> = []

    var body: some View {
        Form {
            Section("Model") {
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
                Section(providerSettingsTitle) {
                    LabeledContent("Provider", value: model.settings.modelSelection.provider.displayName)

                    TextField(
                        "Endpoint",
                        text: Binding(
                            get: { model.endpointString },
                            set: { model.updateEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Model",
                        text: Binding(
                            get: { model.settings.modelSelection.modelID },
                            set: { model.updateModelName($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button {
                            model.resetSelectedProviderDefaults()
                        } label: {
                            Label("Use Defaults", systemImage: "arrow.counterclockwise")
                        }

                        Button {
                            Task { await model.testSelectedModel() }
                        } label: {
                            Label("Test Connection", systemImage: "checkmark.circle")
                        }
                        .disabled(model.isTestingModel)
                    }

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

            Section("Built-in local model") {
                Picker(
                    "Variant",
                    selection: Binding(
                        get: { model.selectedBuiltInModelDescriptor.id },
                        set: { model.selectBuiltInModel(id: $0) }
                    )
                ) {
                    ForEach(BuiltInModelCatalog.all) { descriptor in
                        Text(descriptor.isRecommended ? "\(descriptor.displayName) - recommended" : descriptor.displayName)
                            .tag(descriptor.id)
                    }
                }

                LabeledContent("Repository", value: model.selectedBuiltInModelDescriptor.repository)
                LabeledContent("Precision", value: model.selectedBuiltInModelDescriptor.precision)
                LabeledContent("Size", value: model.selectedBuiltInModelDescriptor.estimatedDownloadSize)
                LabeledContent("Memory", value: model.selectedBuiltInModelDescriptor.expectedMemory)

                if let path = model.settings.builtInModelStatus.storagePath {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Storage")
                            .font(.subheadline)
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

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
                            Toggle(
                                isOn: Binding(
                                    get: { selectedModelFolderPaths.contains(folder.path) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedModelFolderPaths.insert(folder.path)
                                        } else {
                                            selectedModelFolderPaths.remove(folder.path)
                                        }
                                    }
                                )
                            ) {
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

                HStack {
                    Button {
                        showInstallConfirmation = true
                    } label: {
                        Label(
                            model.settings.builtInModelStatus.installState == .ready ? "Reinstall" : "Install",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(model.isInstallingBuiltInModel)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(model.isInstallingBuiltInModel || selectedModelFolderPaths.isEmpty)

                    Button {
                        Task { await model.testSelectedModel() }
                    } label: {
                        Label("Test", systemImage: "checkmark.circle")
                    }
                    .disabled(model.isTestingModel || model.isInstallingBuiltInModel)

                    Button {
                        model.openBuiltInModelsFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                }

                Text(model.selectedBuiltInModelDescriptor.localOnlyNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Screen Recording", value: model.screenRecordingPermissionLabel)

                HStack {
                    Button {
                        model.openScreenRecordingGuide()
                    } label: {
                        Label("Open Permission Guide", systemImage: "camera.viewfinder")
                    }
                    .disabled(model.screenRecordingPermission.isGranted)

                    Button {
                        model.refreshScreenRecordingPermission()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                Text("The guide opens System Settings and shows a draggable Watch My Back tile for Screen & System Audio Recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle(
                    "Save safe activity summaries",
                    isOn: Binding(
                        get: { model.settings.persistActivitySummaries },
                        set: { model.updatePersistActivitySummaries($0) }
                    )
                )

                Text("When enabled, Watch My Back stores a short redacted activity summary for the dashboard feed. Raw screenshots, OCR, visible text, prompts, and image data are still not stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sampling") {
                Stepper(
                    value: Binding(
                        get: { model.settings.sampleIntervalSeconds },
                        set: { model.updateSampleInterval($0) }
                    ),
                    in: 15...300,
                    step: 15
                ) {
                    Text("Every \(Int(model.settings.sampleIntervalSeconds)) seconds")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

    private var installConfirmationTitle: String {
        model.settings.builtInModelStatus.installState == .ready
            ? "Reinstall built-in model?"
            : "Download built-in model?"
    }

    private var installConfirmationMessage: String {
        let descriptor = model.selectedBuiltInModelDescriptor
        return "Watch My Back will download \(descriptor.displayName) from \(descriptor.repository). Estimated size: \(descriptor.estimatedDownloadSize). Classification stays local and raw screenshots are discarded after each request."
    }

    private var providerSettingsTitle: String {
        "\(model.settings.modelSelection.provider.displayName) connection"
    }

    private var providerHelpText: String {
        switch model.settings.modelSelection.provider {
        case .oMLX:
            return "oMLX is optional. Watch My Back will not install it; point this at an existing oMLX/OpenAI-compatible vision server."
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

    private func syncSelectedModelFoldersIfNeeded() {
        guard selectedModelFolderPaths.isEmpty else { return }
        let currentPath = model.settings.builtInModelStatus.storagePath
        if let current = model.builtInModelFolders.first(where: { $0.path == currentPath }) {
            selectedModelFolderPaths = [current.path]
        }
    }
}
