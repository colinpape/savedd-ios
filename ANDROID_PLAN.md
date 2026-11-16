# Android implementation plan

Build a native Kotlin / Jetpack Compose browser matching the SwiftUI app. The website repository also contains a Phase 0 Capacitor APK that opens the live site; this native browser project adds the iOS-style controls and onboarding. The standalone Android Studio project lives in `android/` alongside iOS so parity changes are reviewable together. The website remains the search/auth/account backend.

## First test APK

- Dark purple/gold Savedd branding and serif headlines.
- Five onboarding steps: welcome, database partner picker with prefetch/filtering/skip, appearance/language/privacy, optional Daily Proverb with the fixed Proverbs 18:15 example, email sign-in or account skip.
- Persistent WebView tabs, visual tab manager, bottom new-tab/close controls, keyboard-aware address field with URL-friendly keyboard, voice entry, back/forward and history selection.
- Local bookmark list with favicons, Add bookmark from sharing, editable bookmark details, recent typed addresses/searches with individual/all deletion.
- Existing website settings bridge restricted to the two Savedd HTTPS origins. Database referrals use the same public API. Email PKCE returns through the existing fixed Savedd callback.
- Offline Proverbs/WEB readings and reflections shared with iOS, notification opt-in/time controls, local reminders, reboot/time-zone recovery, and notification-to-reading routing.
- Gradle build, focused unit tests, lint, CI APK artifact, and novice-friendly installation instructions.

## Device verification before public release

Check a real Android phone's keyboard/notches/back button, tab restoration, uploads/downloads, voice availability, passwords/magic-link return from Mail, notification permission and delivery under battery saving, offline behavior, large fonts, and light/dark mode. Build a signed AAB and configure Play Console internal testing only after the test APK is accepted. Google Play registration, release signing and store submission are separate release steps; no paid services or store submission are initiated here.

Android cannot promise iOS-identical system share sheets, speech dialogs, autofill, or exact notification delivery. Native controls should preserve the same actions and layout conventions while using Android platform behavior. Daily reminders use inexact alarms without requesting restricted exact-alarm access; Android battery settings may delay them.

This test build uses HTTPS-only networking. Automatic approval review rejected the initial app-wide cleartext exception; it was removed, and HTTP address input upgrades to HTTPS.
