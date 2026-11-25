import XCTest

@testable import MenuBarHider

final class ClockDateTooltipTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func calendar(_ locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    func testShortDateWithWeekdayAndWeekNumber() {
        XCTAssertEqual(ClockDateTooltip.text(for: date(2026, 11, 25), calendar: calendar("en_GB")), "Wed 25 Nov · W48")
    }

    func testFollowsLocaleOrder() {
        XCTAssertEqual(ClockDateTooltip.text(for: date(2026, 11, 25), calendar: calendar("en_US")), "Wed, Nov 25 · W48")
    }

    func testWeekNumberFollowsRegionRules() {
        // 1 January 2027 is a Friday: still ISO week 53 of 2026 in Poland, week 1 in the US.
        XCTAssertTrue(ClockDateTooltip.text(for: date(2027, 1, 1), calendar: calendar("pl_PL")).hasSuffix("W53"))
        XCTAssertTrue(ClockDateTooltip.text(for: date(2027, 1, 1), calendar: calendar("en_US")).hasSuffix("W1"))
    }

    func testShowsDateOnClockHoverByDefault() {
        let suite = "ClockDateTooltipTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: UserDefaults(suiteName: suite)!)

        XCTAssertTrue(settings.showsClockDate)
        settings.showsClockDate = false
        XCTAssertFalse(settings.showsClockDate)
    }
}
