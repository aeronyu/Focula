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
