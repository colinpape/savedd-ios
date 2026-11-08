import Foundation
import UserNotifications

@main
struct DailyProverbTests {
    @MainActor
    static func main() async throws {
        let library = try ProverbLibrary.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
        precondition(library.translation == "World English Bible" && library.copyright == "Public domain")
        precondition(library.chapters.count == 31)
        precondition(library.chapters.reduce(0) { $0 + $1.verses.count } == 915)
        let morning = ProverbReminderTime(hour: 8, minute: 15)
        let requests = ProverbNotificationPlan.requests(library: library, time: morning)
        precondition(Set(requests.map(\.identifier)).count == 58)
        precondition(requests.count < 64)
        for request in requests {
            let day = request.content.userInfo["proverbDay"] as! Int
            let chapter = library.chapters[day - 1]
            precondition(request.content.body.contains(chapter.highlight))
            precondition(request.content.body.contains(chapter.reference))
            precondition(request.content.userInfo["proverbDay"] as? Int == chapter.day)
            let trigger = request.trigger as! UNCalendarNotificationTrigger
            precondition(trigger.repeats == !request.identifier.hasSuffix(".leap"))
            let parts = trigger.dateComponents
            precondition(parts.day == chapter.day && parts.hour == 8 && parts.minute == 15)
            precondition(parts.timeZone == nil && parts.second == 0)
            if day <= 28 { precondition(parts.month == nil && parts.year == nil) }
            else { precondition(parts.month != nil) }
            let next = trigger.nextTriggerDate()!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            precondition(calendar.component(.day, from: next) == chapter.day, "Expected day \(chapter.day), received \(next) with \(parts)")
            precondition(calendar.component(.hour, from: next) == 8)
            if let month = parts.month { precondition(calendar.component(.month, from: next) == month) }
        }
        // The chapter follows the phone's day, rather than UTC or a non-Gregorian calendar.
        let date = ISO8601DateFormatter().date(from: "2026-11-09T02:00:00Z")!
        precondition(ProverbLibrary.day(on: date, timeZone: TimeZone(identifier: "America/Toronto")!) == 8)
        precondition(ProverbLibrary.day(on: date, timeZone: TimeZone(secondsFromGMT: 0)!) == 9)
        precondition(!ProverbReminderTime(hour: 24, minute: 0).isValid)
        precondition(!ProverbReminderTime(hour: 8, minute: 60).isValid)
        // Replacing time retains IDs so notifications are replaced, never duplicated.
        precondition(ProverbNotificationPlan.requests(library: library, time: .init(hour: 21, minute: 30)).map(\.identifier) == requests.map(\.identifier))
        let leapRequest = requests.first { $0.identifier.hasSuffix(".leap") }!
        let leapTrigger = leapRequest.trigger as! UNCalendarNotificationTrigger
        precondition(leapTrigger.dateComponents.month == 2 && leapTrigger.dateComponents.day == 29)
        precondition(ProverbNotificationPlan.identifiers.sorted() == requests.map(\.identifier).sorted())
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        for month in 1...12 {
            let anchor = gregorian.date(from: DateComponents(year: 2027, month: month, day: 1))!
            for request in requests where !request.identifier.hasSuffix(".leap") {
                let parts = (request.trigger as! UNCalendarNotificationTrigger).dateComponents
                let date = gregorian.nextDate(after: anchor, matching: parts, matchingPolicy: .nextTime)!
                precondition(gregorian.component(.day, from: date) == parts.day)
            }
        }
        let afterLeapDay = ISO8601DateFormatter().date(from: "2028-03-01T12:00:00Z")!
        let futureLeap = ProverbNotificationPlan.requests(library: library, time: morning, now: afterLeapDay)
            .first { $0.identifier.hasSuffix(".leap") }!
        precondition((futureLeap.trigger as! UNCalendarNotificationTrigger).dateComponents.year == 2032)
        let suite = "savedd.proverb-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FakeNotifications()
        let reminders = ProverbReminders(client: client, defaults: defaults, library: library)
        await reminders.refresh()
        precondition(client.promptCount == 0 && client.pending.isEmpty && !reminders.enabled)
        await reminders.enable()
        precondition(client.promptCount == 1 && reminders.enabled && client.pending.count == 58)
        let evening = Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: Date())!
        await reminders.changeTime(evening)
        precondition(client.pending.count == 58)
        precondition(client.pending.values.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour == 21 })
        let restored = ProverbReminders(client: client, defaults: defaults, library: library)
        precondition(restored.enabled && restored.time == ProverbReminderTime(hour: 21, minute: 30))
        client.status = .denied
        await reminders.refresh()
        precondition(reminders.enabled && client.pending.isEmpty && client.promptCount == 1)
        client.status = .authorized
        await reminders.refresh()
        precondition(client.pending.count == 58)
        reminders.disable()
        precondition(!reminders.enabled && client.pending.isEmpty)
        client.status = .denied
        await reminders.enable()
        precondition(!reminders.enabled && client.promptCount == 1 && client.pending.isEmpty)
        client.status = .authorized
        client.failAdd = true
        await reminders.enable()
        precondition(!reminders.enabled && reminders.error != nil && client.pending.isEmpty)
        client.failAdd = false
        await reminders.enable()
        reminders.open(day: 8)
        precondition(reminders.presentedChapter?.day == 8)
        reminders.open(day: 99)
        precondition(reminders.presentedChapter == nil)
        reminders.disable()
        client.onAdd = { reminders.disable() }
        await reminders.enable()
        precondition(!reminders.enabled && client.pending.isEmpty)
        client.onAdd = nil
        print("Permission, persistence, time edits, revoke/restore, cancellation, failure cleanup, and chapter routing passed")
        print("Daily Proverb: 31 chapters, 915 verses, correct local-day selection and 58 valid-date calendar reminders passed")
    }
}

@MainActor
final class FakeNotifications: ProverbNotificationClient {
    var status: UNAuthorizationStatus = .notDetermined
    var promptCount = 0
    var pending: [String: UNNotificationRequest] = [:]
    var failAdd = false
    var onAdd: (() -> Void)?
    func authorization() async -> UNAuthorizationStatus { status }
    func requestPermission() async throws { promptCount += 1; status = .authorized }
    func add(_ request: UNNotificationRequest) async throws {
        if failAdd { throw CocoaError(.fileWriteUnknown) }
        pending[request.identifier] = request
        onAdd?()
    }
    func removePending(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) {}
}
