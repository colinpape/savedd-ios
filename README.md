# Savedd iOS

Savedd is an iOS browser built with SwiftUI and WKWebView, using Savedd as its default search engine.

Open **Savedd.xcodeproj** in Xcode. The project targets iOS 17 or later. For a simulator, select an iPhone simulator and press Run. For a physical device or distribution, select your Apple developer team under **Savedd target → Signing & Capabilities**.

The app includes first-run onboarding, optional partner referrals, local appearance/language/privacy preferences, tabs, and bookmarks. The 1024px PNG app icon is already installed in Assets.xcassets; no decoding step is required.

- [Onboarding behavior and website integration](ONBOARDING.md)
- [TestFlight setup, upload, and installation](TESTFLIGHT.md)

CI checks the database partner directory, email callback routing, and website preference handoff, builds the simulator app, captures onboarding screens, and checks an unsigned Release archive for a generic iOS device. CI does not sign or upload to Apple.
