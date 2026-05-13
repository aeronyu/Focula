import SwiftUI
import WatchMyBackCore

@main
struct WatchMyBackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Watch My Back", id: "dashboard") {
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
            }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Label("Watch My Back", systemImage: model.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 520)
        }
    }
}
