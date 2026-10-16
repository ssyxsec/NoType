import XCTest
@testable import NoTypeCore

final class HistoryTests: XCTestCase {
    func testRoundTripAndDeletePreserveMultilingualText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        XCTAssertEqual(try store.load(), [])
        let record = DictationRecord(rawText: "嗯，明天 review 一下。", text: "明天 review 一下。", mode: "自然表达", engine: "whisper", duration: 3.5, appName: "Notes")
        try store.save([record])
        XCTAssertEqual(try store.load(), [record])
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("history.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try store.save([])
        XCTAssertEqual(try store.load(), [])
    }
    func testCorruptHistoryIsNeverOverwrittenDuringLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.json")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try HistoryStore(directory: dir).load())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
