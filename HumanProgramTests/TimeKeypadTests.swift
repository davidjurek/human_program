import XCTest
@testable import HumanProgram

/// Pins the shared HHMM keypad rule used by the Schedule and Reminder editors.
final class TimeKeypadTests: XCTestCase {

    func test_appending_keepsDigitsAndCapsAtFour() {
        XCTAssertEqual(TimeKeypad.appending("8", to: ""), "8")
        XCTAssertEqual(TimeKeypad.appending("3", to: "08"), "083")
        XCTAssertEqual(TimeKeypad.appending("0", to: "083"), "0830")
        // Caps at the last 4 digits (HHMM).
        XCTAssertEqual(TimeKeypad.appending("5", to: "0830"), "8305")
        // Non-digits are dropped.
        XCTAssertEqual(TimeKeypad.appending("a", to: "12"), "12")
    }

    func test_minutes_parsesHHMM_andSnapsToFive() {
        XCTAssertNil(TimeKeypad.minutes(from: ""))                 // empty → nil
        XCTAssertEqual(TimeKeypad.minutes(from: "8"), 8 * 60)      // "8" → 08:00
        XCTAssertEqual(TimeKeypad.minutes(from: "08"), 8 * 60)     // 08:00
        XCTAssertEqual(TimeKeypad.minutes(from: "0830"), 8 * 60 + 30)
        XCTAssertEqual(TimeKeypad.minutes(from: "2045"), 20 * 60 + 45)
    }

    func test_minutes_clampsAndSnaps() {
        // Hours clamp to 23, minutes clamp to 55.
        XCTAssertEqual(TimeKeypad.minutes(from: "9999"), 23 * 60 + 55)
        // Minutes snap to the nearest 5: 32 → 30, 33 → 35.
        XCTAssertEqual(TimeKeypad.minutes(from: "0832"), 8 * 60 + 30)
        XCTAssertEqual(TimeKeypad.minutes(from: "0833"), 8 * 60 + 35)
    }
}
