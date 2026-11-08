import Foundation

struct ProverbChapter: Codable, Identifiable, Equatable {
    struct Verse: Codable, Equatable {
        let number: Int
        let text: String
    }
    let day: Int
    let highlightVerse: Int
    let reflection: String
    let verses: [Verse]
    var id: Int { day }
    var reference: String { "Proverbs \(day):\(highlightVerse)" }
    var highlight: String { verses.first { $0.number == highlightVerse }?.text ?? "" }
}

struct ProverbLibrary: Codable {
    let translation: String
    let abbreviation: String
    let copyright: String
    let source: String
    let chapters: [ProverbChapter]

    static func load(from url: URL) throws -> ProverbLibrary {
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard library.chapters.map(\.day) == Array(1...31),
              library.chapters.allSatisfy({ !$0.highlight.isEmpty && !$0.reflection.isEmpty &&
                  $0.verses.map(\.number) == Array(1...$0.verses.count) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return library
    }

    static let bundled: ProverbLibrary? = {
        guard let url = Bundle.main.url(forResource: "Proverbs", withExtension: "json") else { return nil }
        return try? load(from: url)
    }()

    static func day(on date: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.day, from: date)
    }
}

struct ProverbReminderTime: Codable, Equatable {
    var hour = 8
    var minute = 0
    var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }

    func components(day: Int) -> DateComponents {
        // No fixed time zone: follow the device's local wall-clock time.
        var value = DateComponents()
        value.calendar = Calendar(identifier: .gregorian)
        value.day = day
        value.hour = hour
        value.minute = minute
        return value
    }
}

#if canImport(UserNotifications)
import UserNotifications

extension ProverbChapter {
    func notification(at time: ProverbReminderTime) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Today’s wisdom · Proverbs \(day)"
        content.body = "\(highlight) — \(reference) (WEB)"
        content.sound = .default
        content.userInfo = ["proverbDay": day]
        return UNNotificationRequest(identifier: "savedd.daily-proverb." + String(day), content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: time.components(day: day), repeats: true))
    }
}
#endif
