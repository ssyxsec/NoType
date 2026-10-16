import Foundation

public struct DailyUsage: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var characters = 0
    public var seconds: Double = 0
    public var sessions = 0
    public var charactersPerMinute: Double { seconds > 0 ? Double(characters) * 60 / seconds : 0 }
}

public struct UsageStatistics: Sendable {
    public let days: [DailyUsage]
    public let characters: Int
    public let seconds: Double
    public let sessions: Int
    public var activeDays: Int { days.count }
    public var charactersPerMinute: Double { seconds > 0 ? Double(characters) * 60 / seconds : 0 }

    public static func characterCount(_ text: String) -> Int {
        text.filter { character in character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }.count
    }
    public init(records: [DictationRecord], calendar: Calendar = .current, interval: DateInterval? = nil) {
        var grouped: [Date: DailyUsage] = [:]
        var seen = Set<UUID>()
        for record in records {
            guard seen.insert(record.id).inserted,
                  record.source == "recording" || (record.source == nil && record.duration > 0),
                  record.duration.isFinite, record.duration > 0,
                  interval.map({ record.createdAt >= $0.start && record.createdAt < $0.end }) ?? true else { continue }
            let count = record.dictationCharacters ?? Self.characterCount(record.rawText)
            guard count > 0 else { continue }
            let date = calendar.startOfDay(for: record.createdAt)
            var usage = grouped[date] ?? DailyUsage(date: date)
            usage.characters += max(0, count); usage.seconds += record.duration; usage.sessions += 1
            grouped[date] = usage
        }
        days = grouped.values.sorted { $0.date < $1.date }
        characters = days.reduce(0) { $0 + $1.characters }
        seconds = days.reduce(0) { $0 + $1.seconds }
        sessions = days.reduce(0) { $0 + $1.sessions }
    }
}
