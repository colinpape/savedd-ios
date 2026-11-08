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
        value.second = 0
        return value
    }
}

#if canImport(UserNotifications)
import UserNotifications

enum ProverbNotificationPlan {
    static let prefix = "savedd.daily-proverb."
    static let lateMonthDays: [Int: [Int]] = [
        29: [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        30: [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        31: [1, 3, 5, 7, 8, 10, 12]
    ]
    static var identifiers: [String] {
        (1...28).map { prefix + String($0) } +
        [29, 30, 31].flatMap { day in lateMonthDays[day]!.map { prefix + "\(day).month.\($0)" } } +
        [prefix + "29.leap"]
    }

    static func requests(library: ProverbLibrary, time: ProverbReminderTime, now: Date = Date()) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for chapter in library.chapters {
            let content = UNMutableNotificationContent()
            content.title = "Savedd Daily Proverb"
            content.body = "\(chapter.highlight) — \(chapter.reference) (WEB)"
            content.sound = .default
            content.userInfo = ["proverbDay": chapter.day]
            func append(_ components: DateComponents, suffix: String = "", repeats: Bool = true) {
                requests.append(UNNotificationRequest(identifier: prefix + String(chapter.day) + suffix, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)))
            }
            if chapter.day <= 28 {
                append(time.components(day: chapter.day))
            } else {
                // UNCalendarNotificationTrigger uses nextTime matching: a bare
                // day 31 can roll to the 1st! Only schedule dates valid in each month.
                for month in lateMonthDays[chapter.day] ?? [] {
                    var parts = time.components(day: chapter.day)
                    parts.month = month
                    append(parts, suffix: ".month.\(month)")
                }
                if chapter.day == 29 {
                    var parts = time.components(day: 29)
                    parts.month = 2
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = .current
                    if let leapDay = calendar.nextDate(after: now, matching: parts, matchingPolicy: .strict) {
                        parts.year = calendar.component(.year, from: leapDay)
                        append(parts, suffix: ".leap", repeats: false)
                    }
                }
            }
        }
        // 58 requests, below iOS's limit of 64. Refresh the leap-day request on app activation.
        return requests
    }
}
#endif
