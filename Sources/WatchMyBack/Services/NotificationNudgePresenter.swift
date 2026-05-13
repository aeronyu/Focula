import Foundation
import UserNotifications
import WatchMyBackCore

@MainActor
final class NotificationNudgePresenter {
    static let shared = NotificationNudgePresenter()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(goal: Goal, appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Back to \(goal.title)"
        content.body = "\(appName) looks off mission. Take one small step toward the goal."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "watch-my-back-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
