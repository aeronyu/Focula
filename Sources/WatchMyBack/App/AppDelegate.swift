import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showMainWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindowIfNeeded()
        }
        return true
    }

    private func showMainWindowIfNeeded(attemptsRemaining: Int = 4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let existingWindow = NSApp.windows.first(where: { $0.title == "Focula" && $0.canBecomeMain }) {
                self.placeDashboardWindowOnMainScreenIfNeeded(existingWindow)
                existingWindow.makeKeyAndOrderFront(nil)
            } else {
                NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)

            let hasVisibleDashboard = NSApp.windows.contains {
                $0.title == "Focula" && $0.isVisible
            }
            if !hasVisibleDashboard && attemptsRemaining > 0 {
                self.showMainWindowIfNeeded(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    private func placeDashboardWindowOnMainScreenIfNeeded(_ window: NSWindow) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        guard !visibleFrame.intersects(window.frame) else { return }

        var frame = window.frame
        frame.size.width = min(max(frame.size.width, 980), visibleFrame.width)
        frame.size.height = min(max(frame.size.height, 680), visibleFrame.height)
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }
}
