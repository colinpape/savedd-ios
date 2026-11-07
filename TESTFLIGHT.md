# Install Savedd through TestFlight

A paid Apple Developer Program membership is required. No phone cable or Developer Mode is needed for a TestFlight installation.

## Create the app record (once)

1. Open https://developer.apple.com/account/resources/identifiers/list and sign in with your paid developer account.
2. Select the correct team. Look for an explicit App ID with Bundle ID **com.savedd.browser**. If it does not exist, press **+**, choose **App IDs → App**, enter description **Savedd**, and register the explicit Bundle ID **com.savedd.browser**. Leave optional capabilities off unless needed.
3. Open https://appstoreconnect.apple.com/apps with the same team.
4. If Savedd already exists, open it and verify its Bundle ID. Otherwise click **+ → New App**.
5. Choose platform **iOS**, name **Savedd** (if available), primary language **English (U.S.)**, Bundle ID **com.savedd.browser**, and SKU **savedd-ios-001**. SKU is your own internal label.
6. Click **Create**. The account holder may need to accept Apple's latest agreements first.

## Archive and upload from the Mac

1. Pull the latest main branch before opening **Savedd.xcodeproj**. Preserve any local signing or icon edits if Git reports a conflict.
2. In Xcode select the blue Savedd project, then **TARGETS → Savedd → Signing & Capabilities**. Enable **Automatically manage signing** and choose your paid developer team for all configurations. Do not select a free Personal Team.
3. Under **General**, verify Bundle Identifier **com.savedd.browser**, Version **1.0**, Build **1**. If that build was already uploaded, increase Build to **2**, then **3**, etc. for each later upload.
4. Stop any device operation. In the top destination selector, choose **Any iOS Device (arm64)** or the equivalent generic iOS device destination, rather than your phone or a simulator.
5. Choose **Product → Archive**. This creates a Release archive on your Mac without talking to the phone.
6. When Organizer opens, select the new archive and click **Distribute App**. Choose **App Store Connect** (or the TestFlight upload option offered by your Xcode version), then **Upload**. Use automatic signing and follow validation/upload prompts.
7. If Apple reports an unsupported SDK, update Xcode to a version Apple currently accepts for uploads. The repository's unsigned CI archive checks compilation; it is not an uploadable TestFlight build.

## Install on your iPhone

1. After Apple finishes processing, open **App Store Connect → Savedd → TestFlight**.
2. Resolve any **Missing Compliance** questions accurately. This app includes HTTPS and bundled cryptographic signature verification; do not guess the export-compliance answers. The privacy manifest declares native UserDefaults use; it does not answer the website's data-collection questions.
3. Under **Internal Testing**, create a group such as **Savedd testing**, add yourself as a tester, and assign the processed build. Your Apple account must be an eligible App Store Connect user. External testers use a separate beta-review flow.
4. Install Apple's **TestFlight** app from the App Store on your iPhone. Open your invitation and tap **Accept → Install**.
5. Savedd now launches from your Home Screen independently of the Mac. TestFlight builds expire after 90 days.

## Suggested testing notes

Test first-run welcome, optional referral selection, appearance/language/privacy preferences, guest continuation, search, tabs, and bookmarks. Verify dark mode on both savedd.com and www.savedd.com. Reinstalling over an existing app may preserve onboarding completion: use the browser's Settings entry to inspect preferences.

Account creation currently requires a configured signup URL and is otherwise shown as coming soon. An empty published partner directory can leave no partners to choose. Check these states honestly when completing beta information.

Privacy practices and Apple review acceptance must reflect the actual app and loaded website. No App Store publication happens merely by uploading a build for internal TestFlight testing.
