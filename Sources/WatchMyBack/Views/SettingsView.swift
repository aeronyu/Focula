import SwiftUI
import WatchMyBackCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

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
            }

            Section("Built-in local model") {
                LabeledContent("Default", value: BuiltInModelCatalog.gemma4E2B.displayName)
                LabeledContent("Size", value: BuiltInModelCatalog.gemma4E2B.estimatedDownloadSize)
                LabeledContent("Memory", value: BuiltInModelCatalog.gemma4E2B.expectedMemory)

                if let path = model.settings.builtInModelStatus.storagePath {
                    LabeledContent("Storage", value: path)
                }

                HStack {
                    Button {
                        Task { await model.installBuiltInModel() }
                    } label: {
                        Label(
                            model.settings.builtInModelStatus.installState == .ready ? "Reinstall" : "Install",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(model.isInstallingBuiltInModel)

                    Button {
                        model.deleteBuiltInModel()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(model.settings.builtInModelStatus.installState == .missing || model.isInstallingBuiltInModel)

                    Button {
                        Task { await model.testSelectedModel() }
                    } label: {
                        Label("Test", systemImage: "checkmark.circle")
                    }
                    .disabled(model.isTestingModel || model.isInstallingBuiltInModel)
                }

                Text(BuiltInModelCatalog.gemma4E2B.localOnlyNotice)
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

            if model.settings.modelSelection.provider != .builtInGemma {
                Section("Provider hookup") {
                    TextField(
                        "Endpoint",
                        text: Binding(
                            get: { model.endpointString },
                            set: { model.updateEndpoint($0) }
                        )
                    )

                    TextField(
                        "Model",
                        text: Binding(
                            get: { model.settings.modelSelection.modelID },
                            set: { model.updateModelName($0) }
                        )
                    )

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
                        Text("Optional providers are used only when already available. Built-in Gemma remains the default path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
    }
}
