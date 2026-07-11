import XCTest
@testable import LimitBar

/// ResetClock — абсолютное время сброса в строке меню (фидбэк владельца 11.07:
/// «во сколько сбросится» полезнее, чем «через сколько», и должно быть видно всегда).
final class ResetClockTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testNilDateGivesNil() {
        XCTAssertNil(ResetClock.label(nil))
    }

    func testPastDateSaysNow() {
        let now = date(2026, 7, 11, 18, 0)
        XCTAssertEqual(ResetClock.label(now.addingTimeInterval(-60), now: now, calendar: calendar), "now")
    }

    func testSameDayShowsTimeOnly() {
        let now = date(2026, 7, 11, 15, 0)
        let label = ResetClock.label(date(2026, 7, 11, 19, 4), now: now, calendar: calendar)!
        // Формат локале-зависимый (19:04 или 7:04 PM) — проверяем состав, не строку.
        XCTAssertTrue(label.contains("04"), "time must be present: \(label)")
        XCTAssertFalse(label.lowercased().contains("mon"), "no weekday for today: \(label)")
    }

    func testOtherDayIncludesWeekday() {
        let now = date(2026, 7, 11, 15, 0)   // суббота
        let label = ResetClock.label(date(2026, 7, 14, 9, 0), now: now, calendar: calendar)!
        // 14.07.2026 — вторник; en-локаль даст "Tue", другие — своё сокращение.
        XCTAssertTrue(label.rangeOfCharacter(from: .letters) != nil, "weekday expected: \(label)")
        XCTAssertTrue(label.contains("9") || label.contains("09"), "time expected: \(label)")
    }
}
