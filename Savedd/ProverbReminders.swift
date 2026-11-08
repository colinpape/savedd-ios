import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
protocol ProverbNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestPermission() async throws
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

@MainActor
struct SystemProverbNotifications: ProverbNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestPermission() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
}

/// Local reminders need neither a server nor an account. Keep them separate from
/// search preferences so existing settings decode unchanged and stay off websites.
@MainActor
final class ProverbReminders: ObservableObject {
    static let shared = ProverbReminders()
    nonisolated static let prefix = ProverbNotificationPlan.prefix
    @Published private(set) var enabled: Bool
    @Published private(set) var time: ProverbReminderTime
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published var presentedChapter: ProverbChapter?
    @Published var searchURL: URL?
    private let client: any ProverbNotificationClient
    private let library: ProverbLibrary?
    private let defaults: UserDefaults
    private var revision = 0
    private static let enabledKey = "savedd.proverbs.enabled.v1"
    private static let timeKey = "savedd.proverbs.time.v1"

    init(client: (any ProverbNotificationClient)? = nil, defaults: UserDefaults = .standard, library: ProverbLibrary? = ProverbLibrary.bundled) {
        self.client = client ?? SystemProverbNotifications()
        self.library = library
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let saved = defaults.data(forKey: Self.timeKey).flatMap { try? JSONDecoder().decode(ProverbReminderTime.self, from: $0) }
        if let saved, saved.isValid { time = saved }
        else { time = ProverbReminderTime() }
    }

    var canNotify: Bool {
        #if os(iOS)
        return permission == .authorized || permission == .provisional || permission == .ephemeral
        #else
        return permission == .authorized || permission == .provisional
        #endif
    }
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
            permission = await client.authorization()
            if permission == .notDetermined {
                try await client.requestPermission()
                permission = await client.authorization()
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
            self.error = "We couldn’t enable reminders. Please try again."
        }
    }

    func disable() {
        revision += 1
        enabled = false
        defaults.set(false, forKey: Self.enabledKey)
        client.removePending(ProverbNotificationPlan.identifiers)
        client.removeDelivered(ProverbNotificationPlan.identifiers)
        error = nil
    }

    func refresh() async {
        permission = await client.authorization()
        if enabled && canNotify { await schedule() }
        else if enabled {
            // Preserve the user's subscription choice if iOS permission is revoked.
            client.removePending(ProverbNotificationPlan.identifiers)
        }
    }

    private func schedule() async {
        revision += 1
        let currentRevision = revision
        error = nil
        guard let library else {
            disable()
            error = "The Daily Proverb readings are unavailable. Please update Savedd."
            return
        }
        do {
            for request in ProverbNotificationPlan.requests(library: library, time: time) {
                guard enabled, currentRevision == revision else { return }
                try await client.add(request)
                if !enabled {
                    client.removePending([request.identifier])
                    return
                }
                guard currentRevision == revision else { return }
            }
        } catch {
            if currentRevision == revision {
                disable()
                self.error = "We couldn’t save your reminders. Please try enabling them again."
            }
        }
    }

    func open(day: Int) {
        presentedChapter = library?.chapters.first { $0.day == day }
    }
}

#if canImport(UIKit)
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

#endif
