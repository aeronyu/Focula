import XCTest
@testable import FoculaCore

final class NudgeCoordinatorTests: XCTestCase {
    func testNudgeOnlyInsideFocusHoursAndAfterCooldown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = FocusSchedule(weekdays: [4], startMinute: 9 * 60, endMinute: 17 * 60)
        let coordinator = NudgeCoordinator(cooldown: 300, calendar: calendar)
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 10, minute: 0)))
        let soon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 10, minute: 2)))
        let afterCooldown = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 10, minute: 6)))
        let afterHours = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 18, minute: 0)))

        XCTAssertTrue(coordinator.shouldNudge(focusState: .offGoal, schedule: schedule, paused: false, now: first))
        coordinator.recordNudge(at: first)
        XCTAssertFalse(coordinator.shouldNudge(focusState: .offGoal, schedule: schedule, paused: false, now: soon))
        XCTAssertTrue(coordinator.shouldNudge(focusState: .offGoal, schedule: schedule, paused: false, now: afterCooldown))
        XCTAssertFalse(coordinator.shouldNudge(focusState: .offGoal, schedule: schedule, paused: false, now: afterHours))
    }
}
