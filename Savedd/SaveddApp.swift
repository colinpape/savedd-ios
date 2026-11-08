import SwiftUI

@main
struct SaveddApp: App {
    @UIApplicationDelegateAdaptor(ProverbNotificationDelegate.self) private var notificationDelegate
    var body: some Scene {
        WindowGroup {
            SaveddRootView()
        }
    }
}
