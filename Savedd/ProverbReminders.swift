import SwiftUI
import UserNotifications
import UIKit

/// Local reminders need neither a server nor an account. Keep them separate from
/// search preferences so existing settings decode unchanged and stay off websites.
@MainActor
final class ProverbReminders: ObservableObject {
    static let shared = ProverbReminders()
    static let prefix = "savedd.daily-proverb."
    @Published private(set) var enabled: Bool
    @Published private(set) var time: ProverbReminderTime
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published var presentedChapter: ProverbChapter?
    @Published var searchURL: URL?
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var revision = 0
    private static let enabledKey = "savedd.proverbs.enabled.v1"
    private static let timeKey = "savedd.proverbs.time.v1"

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let saved = defaults.data(forKey: Self.timeKey).flatMap { try? JSONDecoder().decode(ProverbReminderTime.self, from: $0) }
        if let saved, saved.isValid { time = saved }
        else { time = ProverbReminderTime() }
    }

    var canNotify: Bool { permission == .authorized || permission == .provisional || permission == .ephemeral }
    var timeDescription: String { selectedDate.formatted(date: .omitted, time: .shortened) }
    var selectedDate: Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }

    func changeTime(_ date: Date) async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        time = ProverbReminderTime(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
        defaults.set(try? JSONEncoder().encode(time), forKey: Self.timeKey)
        if enabled { await refresh() }
    }

    /// Called only after the person explicitly taps Enable (never on appearance).
    func enable() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            permission = await center.notificationSettings().authorizationStatus
            if permission == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                permission = await center.notificationSettings().authorizationStatus
            }
            guard canNotify else {
                enabled = false
                defaults.set(false, forKey: Self.enabledKey)
                return
            }
            enabled = true
            defaults.set(true, forKey: Self.enabledKey)
            await schedule()
        } catch {
            error = "We couldn’t enable reminders. Please try again."
        }
    }

    func disable() {
        revision += 1
        enabled = false
        defaults.set(false, forKey: Self.enabledKey)
        center.removePendingNotificationRequests(withIdentifiers: (1...31).map { Self.prefix + String($0) })
        center.removeDeliveredNotifications(withIdentifiers: (1...31).map { Self.prefix + String($0) })
        error = nil
    }

    func refresh() async {
        permission = await center.notificationSettings().authorizationStatus
        if enabled && canNotify { await schedule() }
        else if enabled {
            // Preserve the user's subscription choice if iOS permission is revoked.
            center.removePendingNotificationRequests(withIdentifiers: (1...31).map { Self.prefix + String($0) })
        }
    }

    private func schedule() async {
        revision += 1
        let currentRevision = revision
        error = nil
        guard let library = ProverbLibrary.bundled else {
            error = "The Daily Proverb readings are unavailable. Please update Savedd."
            return
        }
        do {
            // 31 monthly repeating requests stay below iOS's 64-request limit and
            // continue without reopening the app. Nonexistent dates simply skip.
            for chapter in library.chapters {
                guard enabled, currentRevision == revision else { return }
                let request = chapter.notification(at: time)
                try await center.add(request)
                if !enabled {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
                guard currentRevision == revision else { return }
            }
        } catch {
            if currentRevision == revision {
                disable()
                error = "We couldn’t save your reminders. Please try enabling them again."
            }
        }
    }

    func open(day: Int) {
        presentedChapter = ProverbLibrary.bundled?.chapters.first { $0.day == day }
    }
}

/// Set at launch so tapping a reminder also works when the app was closed.
final class ProverbNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(ProverbReminders.prefix),
           let day = response.notification.request.content.userInfo["proverbDay"] as? Int {
            Task { @MainActor in ProverbReminders.shared.open(day: day) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
