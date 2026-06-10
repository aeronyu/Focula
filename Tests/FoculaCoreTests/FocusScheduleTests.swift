import XCTest
@testable import FoculaCore

final class FocusScheduleTests: XCTestCase {
    func testScheduleIncludesWeekdayInsideWorkWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = FocusSchedule(
            weekdays: [2, 3, 4, 5, 6],
            startMinute: 9 * 60,
            endMinute: 17 * 60
        )
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 10)))

        XCTAssertTrue(schedule.contains(date, calendar: calendar))
    }

    func testScheduleExcludesWeekendAndAfterHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = FocusSchedule(
            weekdays: [2, 3, 4, 5, 6],
            startMinute: 9 * 60,
            endMinute: 17 * 60
        )
        let saturday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 10)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 18)))

        XCTAssertFalse(schedule.contains(saturday, calendar: calendar))
        XCTAssertFalse(schedule.contains(evening, calendar: calendar))
    }

    func testScheduleCanSpanMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = FocusSchedule(
            weekdays: [2, 3],
            startMinute: 22 * 60,
            endMinute: 2 * 60
        )
        let lateMonday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 23)))
        let earlyTuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 1)))
        let middayTuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 12)))

        XCTAssertTrue(schedule.contains(lateMonday, calendar: calendar))
        XCTAssertTrue(schedule.contains(earlyTuesday, calendar: calendar))
        XCTAssertFalse(schedule.contains(middayTuesday, calendar: calendar))
    }
}
