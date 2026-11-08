import Foundation
import UserNotifications

@main
struct DailyProverbTests {
    static func main() throws {
        let library = try ProverbLibrary.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
        precondition(library.translation == "World English Bible" && library.copyright == "Public domain")
        precondition(library.chapters.count == 31)
        precondition(library.chapters.reduce(0) { $0 + $1.verses.count } == 915)
        let morning = ProverbReminderTime(hour: 8, minute: 15)
        let requests = library.chapters.map { $0.notification(at: morning) }
        precondition(Set(requests.map(\.identifier)).count == 31)
        precondition(requests.count < 64)
        for (chapter, request) in zip(library.chapters, requests) {
            precondition(request.content.body.contains(chapter.highlight))
            precondition(request.content.body.contains(chapter.reference))
            precondition(request.content.userInfo["proverbDay"] as? Int == chapter.day)
            let trigger = request.trigger as! UNCalendarNotificationTrigger
            precondition(trigger.repeats)
            let parts = trigger.dateComponents
            precondition(parts.day == chapter.day && parts.hour == 8 && parts.minute == 15)
            precondition(parts.month == nil && parts.year == nil && parts.timeZone == nil)
            let next = trigger.nextTriggerDate()!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            precondition(calendar.component(.day, from: next) == chapter.day)
            precondition(calendar.component(.hour, from: next) == 8)
        }
        // The chapter follows the phone's day, rather than UTC or a non-Gregorian calendar.
        let date = ISO8601DateFormatter().date(from: "2026-11-09T02:00:00Z")!
        precondition(ProverbLibrary.day(on: date, timeZone: TimeZone(identifier: "America/Toronto")!) == 8)
        precondition(ProverbLibrary.day(on: date, timeZone: TimeZone(secondsFromGMT: 0)!) == 9)
        precondition(!ProverbReminderTime(hour: 24, minute: 0).isValid)
        precondition(!ProverbReminderTime(hour: 8, minute: 60).isValid)
        // Replacing time retains IDs so notifications are replaced, never duplicated.
        precondition(library.chapters.map { $0.notification(at: .init(hour: 21, minute: 30)).identifier } == requests.map(\.identifier))
        print("Daily Proverb: 31 chapters, 915 verses, correct local-day selection and 31 repeating calendar reminders passed")
    }
}
