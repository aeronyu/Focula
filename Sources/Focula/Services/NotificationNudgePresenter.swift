import Foundation
import UserNotifications
import FoculaCore

@MainActor
final class NotificationNudgePresenter {
    static let shared = NotificationNudgePresenter()

    private init() {}

    func requestAuthorization() {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(goal: Goal, appName: String) {
        guard isRunningFromAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Back to \(goal.title)"
        content.body = "\(appName) looks off mission. Take one small step toward the goal."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "focula-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
