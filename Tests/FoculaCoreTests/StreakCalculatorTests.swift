import XCTest
@testable import FoculaCore

final class StreakCalculatorTests: XCTestCase {
    func testDayCountsWhenFocusRatioAndTargetMinutesMet() {
        let stats = DailyStats(
            date: Date(timeIntervalSince1970: 0),
            focusSeconds: 7_200,
            offGoalSeconds: 1_200,
            unknownSeconds: 0,
            recoveryCount: 1,
            xp: 125
        )

        XCTAssertTrue(StreakCalculator.dayCounts(stats: stats, targetMinutes: 90))
        XCTAssertFalse(StreakCalculator.dayCounts(stats: stats, targetMinutes: 150))
    }
}
