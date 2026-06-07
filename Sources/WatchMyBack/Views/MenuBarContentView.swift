import SwiftUI
import WatchMyBackCore

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.lastFocusState.symbolName)
                    .foregroundStyle(model.lastFocusState.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedGoal?.title ?? "Focula")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.lastFocusState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label(model.selectedModelLabel, systemImage: "cpu")
                    .font(.subheadline.weight(.medium))
                Text(model.selectedModelStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Menu {
                ForEach(ModelProvider.allCases) { provider in
                    Button {
                        model.switchModelProvider(provider)
                    } label: {
                        Label(provider.displayName, systemImage: provider == model.settings.modelSelection.provider ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label("Switch Model", systemImage: "arrow.triangle.2.circlepath")
            }

            Menu {
                ForEach(BuiltInModelCatalog.all) { descriptor in
                    Button {
                        model.selectBuiltInModel(id: descriptor.id)
                    } label: {
                        Label(
                            descriptor.displayName,
                            systemImage: descriptor.id == model.selectedBuiltInModelDescriptor.id
                                ? "checkmark"
                                : descriptor.isInstallable ? "cpu" : "exclamationmark.triangle"
                        )
                    }
                }
            } label: {
                Label("Gemma Variant", systemImage: "slider.horizontal.3")
            }

            Button {
                Task { await model.testSelectedModel() }
            } label: {
                Label("Test Model", systemImage: "checkmark.circle")
            }
            .disabled(model.isTestingModel || model.isInstallingBuiltInModel || !model.selectedBuiltInModelDescriptor.isInstallable)

            if model.settings.modelSelection.provider == .builtInGemma {
                Button {
                    Task { await model.installBuiltInModel() }
                } label: {
                    Label("Install Built-in Model", systemImage: "arrow.down.circle")
                }
                .disabled(model.settings.builtInModelStatus.installState == .ready || model.isInstallingBuiltInModel || !model.selectedBuiltInModelDescriptor.isInstallable)

                Button {
                    model.pauseModelRuntime()
                } label: {
                    Label("Pause Model", systemImage: "stop.circle")
                }

                Button {
                    model.openBuiltInModelsFolder()
                } label: {
                    Label("Open Models Folder", systemImage: "folder")
                }
            }

            Divider()

            Button {
                model.togglePaused()
            } label: {
                Label(model.settings.paused ? "Resume Tracking" : "Pause Tracking", systemImage: model.settings.paused ? "play.fill" : "pause.fill")
            }

            Button {
                Task { await model.sampleNow(manual: true) }
            } label: {
                Label("Sample Now", systemImage: "camera.metering.matrix")
            }
            .disabled(model.isSampling)

            if !model.screenRecordingPermission.isGranted {
                Button {
                    model.openScreenRecordingGuide()
                } label: {
                    Label("Open Permission Guide", systemImage: "camera.viewfinder")
                }
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 330, alignment: .leading)
    }
}
