import XCTest
@testable import NoTypeCore

final class UsageAndShortcutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func record(_ text: String, seconds: Double, date: Date, source: String? = nil) -> DictationRecord {
        DictationRecord(createdAt: date, rawText: text, text: "润色结果不计数", mode: "自然表达", engine: "whisper", duration: seconds, appName: "Test", source: source)
    }
    func testWeightedSpeedLocalDayAndDeduplication() {
        let first = ISO8601DateFormatter().date(from: "2026-01-01T15:59:00Z")!
        let second = first.addingTimeInterval(120)
        let a = record("你好，世界！", seconds: 30, date: first)
        let b = record("一二三四五六", seconds: 90, date: second)
        let stats = UsageStatistics(records: [a, b, a], calendar: calendar)
        XCTAssertEqual(stats.characters, 10)
        XCTAssertEqual(stats.seconds, 120)
        XCTAssertEqual(stats.charactersPerMinute, 5)
        XCTAssertEqual(stats.sessions, 2)
        XCTAssertEqual(stats.activeDays, 2)
        XCTAssertEqual(stats.days.map { calendar.component(.day, from: $0.date) }, [1, 2])
    }
    func testSourceFilteringIntervalsAndStableOriginalCount() {
        let start = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var spoken = record("后来编辑的更长文字", seconds: 20, date: start, source: "recording")
        spoken.dictationCharacters = 3
        let values = [spoken, record("导入", seconds: 100, date: start, source: "imported"),
                      record("手动", seconds: 0, date: start, source: "typed"),
                      record("边界", seconds: 5, date: end, source: "recording"),
                      record("非法", seconds: .infinity, date: start, source: "recording")]
        let stats = UsageStatistics(records: values, calendar: calendar, interval: DateInterval(start: start, end: end))
        XCTAssertEqual(stats.characters, 3)
        XCTAssertEqual(stats.sessions, 1)
        XCTAssertEqual(stats.activeDays, 1)
        XCTAssertEqual(UsageStatistics.characterCount("你好， hello 123! 👋"), 10)
        XCTAssertEqual(UsageStatistics(records: [], calendar: calendar).charactersPerMinute, 0)
    }
    func testHistoryWithoutNewFieldsStillDecodes() throws {
        let record = record("旧记录", seconds: 2, date: Date())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "source"); object.removeValue(forKey: "dictationCharacters")
        let decoded = try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(UsageStatistics(records: [decoded]).sessions, 1)
    }
    func testShortcutValidationAndPersistence() throws {
        XCTAssertNil(RecordingShortcut.standard.validationError)
        XCTAssertNotNil(RecordingShortcut(keyCode: 0, modifiers: 0).validationError)
        XCTAssertNotNil(RecordingShortcut(keyCode: 0, modifiers: RecordingShortcut.shift).validationError)
        XCTAssertNotNil(RecordingShortcut(keyCode: 12, modifiers: RecordingShortcut.command).validationError)
        XCTAssertNotNil(RecordingShortcut(keyCode: 999, modifiers: RecordingShortcut.control).validationError)
        let custom = RecordingShortcut(keyCode: 40, modifiers: RecordingShortcut.control | RecordingShortcut.option)
        XCTAssertNil(custom.validationError)
        XCTAssertEqual(custom.displayName, "⌃⌥ K")
        XCTAssertEqual(try JSONDecoder().decode(RecordingShortcut.self, from: JSONEncoder().encode(custom)), custom)
    }
}
