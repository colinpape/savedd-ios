# Savedd for Android

A native Kotlin/Jetpack Compose browser with the same core flow as the SwiftUI app. Minimum Android 8 (API 26); target/compile API 36. Open this `android` folder in Android Studio, keeping the neighboring `Savedd/Proverbs.json` file from the repository: Gradle bundles that shared content automatically.

## Install a test APK on a phone

1. Download the provided **Savedd-Android-test.apk** onto the Android phone. You can also copy it from your computer over USB or a file-transfer service you already use.
2. Open the APK in Downloads. If Android asks, allow **Install unknown apps** for the browser or Files app you used. Return and tap **Install**.
3. Open **Savedd**. Complete onboarding or skip the optional referral, reminder, and account steps.
4. To test reminders, choose a time a few minutes ahead and enable notifications. Android battery saving can delay the alert. Tap the alert and verify its chapter and offline reading.
5. To test email sign-in, request a link inside Savedd, open the email, then tap **Open Savedd** on the return page. Existing passwords and optional email codes are also supported.

The website repository also contains an earlier Capacitor Phase 0 APK, using package `com.savedd.app`. This native app uses `com.savedd.browser`; they can coexist. Use this native APK for the iOS-style browser/onboarding test.

Debug APKs use a development signing key. Updates must be signed by the same key to install over an existing copy. The local key is kept in `.local/debug.keystore` and is not committed; independent CI builds may use a different key. Uninstalling clears app data. Set up a private persistent release key before ongoing external testing or Google Play distribution. No production key or paid Play account is required for the first APK test.

## Build in Android Studio

1. Install current Android Studio, choose **Open**, and select this `android` folder.
2. Allow its SDK/Gradle setup to finish. Use JDK 17 (or a compatible Android Studio bundled JDK) and install Android SDK Platform 36 / Build Tools 35.0.0 when prompted.
3. Select an Android emulator or connect your phone with USB debugging enabled, then press **Run**.
4. **Build → Build App Bundle(s) / APK(s) → Build APK(s)** produces `app/build/outputs/apk/debug/app-debug.apk`.

Terminal equivalent, from this folder:

```sh
./gradlew testDebugUnitTest lintDebug assembleDebug
```

A Windows Gradle wrapper (`gradlew.bat`) is included. No website checkout, npm installation, service-role key, or database migration is required. The public referral API configuration is the same as iOS. The website's mobile email entry route must recognize `client=android`.

## What is implemented

- Five onboarding screens, static Proverbs 18:15 illustration, dark brand palette, local appearance/language/privacy settings and account skip.
- Prefetched database partner directory with filtering/initials/skip/retry. Referral codes pass to the website for current validation, first-touch and account attribution.
- Persistent tab URLs and live WebViews while running, visual thumbnails, bottom new-tab/done controls, keyboard-aware address entry, period-friendly URL keyboard, voice entry through an installed Android speech app, history menus and recent-entry deletion/clear.
- Native local bookmarks with favicon caching, edit/delete, and Add bookmark in the share menu. Sharing uses Android's system chooser.
- Restricted settings bootstrap for Savedd HTTPS main frames only; no JavascriptInterface exposed to external sites. Persistent website sessions and constrained PKCE app return.
- File picker, confirmed downloads to Downloads, and fullscreen HTML video.
- Offline WEB chapters/reflections shared with iOS. Optional local reminders with time selection, notification permission handling, reboot/time-zone recovery, and chapter routing on tap.

## Platform differences / phone checks

- This test build uses HTTPS-only networking. Typed HTTP addresses are upgraded to HTTPS; sites or downloads that require unencrypted HTTP are not supported.

- Inexact alarms deliberately avoid the restricted exact-alarm permission. Doze/battery settings and notification channel settings control delivery; a force-stopped app cannot resume alarms until reopened.
- Voice recognition depends on an installed provider; if unavailable, Savedd explains that the keyboard microphone can be used instead. The app doesn't request microphone access merely on launch.
- Webpage camera/microphone capture permissions are denied in this first test build. Native voice input uses Android's separate recognition activity.
- Android controls autofill/password-manager availability, system sharing and notification presentation. No account login or password is copied into native preferences.
- Process restarts restore tab URLs, not the prior WebView back/forward stack. Live tabs retain their own navigation and scroll while the app runs.
- Check real Mail-to-app return, keyboards/notches, tab/history behavior, uploads/downloads/video, offline reading, notification permission/delivery, screen rotation, large text, and light/dark mode before release.

Google Play internal testing, store assets/privacy declarations, a release signing key, and signed AAB submission come after this APK acceptance pass. They are not performed by this build.
