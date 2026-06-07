import SwiftUI
import WatchMyBackCore

@main
struct WatchMyBackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Focula", id: "dashboard") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandMenu("Focus") {
                Button(model.settings.paused ? "Resume Tracking" : "Pause Tracking") {
                    model.togglePaused()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Sample Now") {
                    Task { await model.sampleNow(manual: true) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Open Screen Recording Guide") {
                    model.openScreenRecordingGuide()
                }
            }

            CommandMenu("Model") {
                Button("Test Selected Model") {
                    Task { await model.testSelectedModel() }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!model.selectedBuiltInModelDescriptor.isInstallable)

                Button("Pause Built-in Sidecar") {
                    model.pauseModelRuntime()
                }

                Menu("Built-in Gemma Variant") {
                    ForEach(BuiltInModelCatalog.all) { descriptor in
                        Button(descriptor.displayName) {
                            model.selectBuiltInModel(id: descriptor.id)
                        }
                        .disabled(descriptor.id == model.selectedBuiltInModelDescriptor.id)
                    }
                }

                Button("Open Models Folder") {
                    model.openBuiltInModelsFolder()
                }

                Divider()

                ForEach(ModelProvider.allCases) { provider in
                    Button(provider.displayName) {
                        model.switchModelProvider(provider)
                    }
                    .disabled(provider == model.settings.modelSelection.provider)
                }
            }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Label("Focula", systemImage: model.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 760, height: 820)
        }
    }
}
