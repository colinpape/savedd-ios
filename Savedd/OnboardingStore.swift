import SwiftUI

enum SaveddAppearance: String, Codable, CaseIterable {
    case dark, light
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var title: String { self == .dark ? "Dark" : "Light" }
}

struct SaveddPreferences: Codable, Equatable {
    var appearance: SaveddAppearance = .dark
    var language: String = {
        let code = (Locale.preferredLanguages.first ?? "en").components(separatedBy: "-")[0].lowercased()
        return code.range(of: "^[a-z]{2}$", options: .regularExpression) != nil ? code : "en"
    }()
    var privacyMode = false
    var referralCode = ""
    var partner: SaveddPartner?
}

@MainActor
final class OnboardingStore: ObservableObject {
    @Published var preferences: SaveddPreferences { didSet { save() } }
    @Published private(set) var isComplete: Bool
    private let defaults: UserDefaults
    private static let preferencesKey = "savedd.onboarding.preferences.v1"
    private static let completedKey = "savedd.onboarding.completed.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey),
           let saved = try? JSONDecoder().decode(SaveddPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = SaveddPreferences()
        }
        isComplete = defaults.bool(forKey: Self.completedKey)
    }

    func complete() {
        save()
        defaults.set(true, forKey: Self.completedKey)
        isComplete = true
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

}

enum SaveddAccountConfiguration {
    /// Set this Info.plist value when the website's email signup is deployed.
    /// Do not send people to the current Nostr login or invent a working signup route.
    static var signupURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SaveddSignupURL") as? String,
              let url = URL(string: raw), url.scheme == "https",
              url.host == "savedd.com", url.port == nil || url.port == 443 else { return nil }
        return url
    }
}

extension SaveddPreferences {
    var webPayload: String {
        let payload: [String: Any] = [
            "version": 1,
            "theme": appearance.rawValue,
            "languageFilter": language.isEmpty ? [] : [language],
            "privacyMode": privacyMode,
            "referralCode": referralCode,
            "partnerPubkey": partner?.pubkey ?? "",
            "partnerName": partner?.name ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Runs before the website mounts. Never expose preferences to other origins or frames.
    var bootstrapScript: String {
        """
        (() => {
          const trustedOrigins = ['https://savedd.com', 'https://www.savedd.com'];
          if (window !== window.top || !trustedOrigins.includes(location.origin)) return;
          try {
            const settings = \(webPayload);
            const revision = JSON.stringify(settings);
            if (localStorage.getItem('savedd:ios-applied-preferences') === revision) return;
            const current = JSON.parse(localStorage.getItem('savedd:app-config') || '{}');
            localStorage.setItem('savedd:app-config', JSON.stringify({
              ...current, theme: settings.theme, languageFilter: settings.languageFilter,
              privacyMode: settings.privacyMode
            }));
            // Handoff for email signup and unresolved short codes; never overwrite
            // the website's first-touch attribution or publish referral events here.
            localStorage.setItem('savedd:ios-onboarding', JSON.stringify(settings));
            localStorage.setItem('savedd:ios-applied-preferences', revision);
          } catch (_) { /* unavailable storage must not prevent browsing */ }
        })();
        """
    }
}
