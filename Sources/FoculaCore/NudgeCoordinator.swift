import Foundation

public final class NudgeCoordinator {
    private let cooldown: TimeInterval
    private let calendar: Calendar
    private var lastNudgeAt: Date?

    public init(cooldown: TimeInterval = 600, calendar: Calendar = .current) {
        self.cooldown = cooldown
        self.calendar = calendar
    }

    public func shouldNudge(
        focusState: FocusState,
        schedule: FocusSchedule,
        paused: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !paused else { return false }
        guard focusState == .offGoal else { return false }
        guard schedule.contains(now, calendar: calendar) else { return false }

        if let lastNudgeAt, now.timeIntervalSince(lastNudgeAt) < cooldown {
            return false
        }

        return true
    }

    public func recordNudge(at date: Date = Date()) {
        lastNudgeAt = date
    }
}
