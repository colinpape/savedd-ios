# First-run onboarding

Four native SwiftUI screens introduce SAVEDD, optionally select a referrer, set
preferences, and invite account creation. They use the website's Vespers dark
palette, serif wordmark, gold accent, and cross/magnifier mark. Setup stays dark;
the chosen light/dark appearance applies when browsing starts.

Settings are saved in UserDefaults as the user edits them. Completion is stored
separately, so completed setup does not reappear on launch. No account is required
to search. The browser's menu button opens Settings to change these preferences.

## Partner source

The directory uses the **existing website `feature/partner-program` branch**:
`src/lib/partners.ts`, `src/hooks/usePartners.ts`, `src/components/PartnerAdmin.tsx`,
and `src/lib/saveddProtocol.ts`. This feature is not present on website main at
the time of implementation; native reading does not require changing or merging
the website. Admin-approved partners are public kind 30078 records with d-tag
`savedd:partners`, containing `{ version: 1, partners: [{ slug, pubkey, name }] }`.

The bundled JavaScript reader queries the website's public relays, verifies Nostr
signatures, loads owner-signed canonical/legacy admin roles, and accepts the latest
directory only from the owner or currently approved admins. Empty directories and
admin removals are respected. No private key or login is required. Search/filtering
is local: typed names and codes are not sent to relays. Initials are intentional
avatar placeholders; the existing directory schema does not have image URLs.

Loading, empty, failed, no-match, and selected states are supported. A recognized
selection is passed on the initial Savedd URL as `?ref=<pubkey>` so the website's
existing referral capture enforces first-touch, program settings, and self-referral
rules. The app does not directly publish referral pings or overwrite attribution.
An unrecognized code is explicitly saved as unverified and does not attribute a
partner. Skip clears the draft selection. No 50% revenue-sharing copy is added.

To rebuild the bundled reader:

```sh
cd Tools/partner-directory
npm ci
npm test
npm run build
```

`nostr-tools` and its bundled noble/scure cryptography dependencies are MIT licensed;
their license notices ship as the `Savedd/ThirdPartyNotices.txt` app resource. Build tooling
is not needed to run the native app; the JavaScript resource is checked in.

## Website settings bridge

An origin-restricted, main-frame-only WKUserScript merges `theme`, `languageFilter`,
and `privacyMode` into `savedd:app-config` **before the website mounts**. A revision
marker avoids reapplying the same native choices on each navigation, preserving
subsequent changes made in the website. Other website settings and the existing
`savedd:referrer` are preserved. Changing native Settings recreates the web view
and applies the new choices. Native controls do not currently mirror later edits
made independently in the website's Settings screen.

Search language is a result preference, using the website's existing supported
language list; it does not translate app menus. Privacy Mode uses the website's
existing community-index-only provider behavior. It is not an incognito session,
VPN, or guarantee against AI/provider connections. The explanation states this.

## Handoff to Grok: email accounts

Email auth and cloud preference sync are intentionally not implemented in this
iOS change. Until signup is deployed, the account invitation says email signup is
coming soon, disables Create an account, and offers Continue without an account.
No credentials are collected and no account/sync success is claimed.

Once the website's email flow is deployed:

1. Set `SaveddSignupURL` in the app target's Info.plist to its actual HTTPS URL on
   `savedd.com`. The create-account button becomes enabled and opens that URL
   inside the existing browser (with the same cookie/data store).
2. On that origin, signup can read `localStorage['savedd:ios-onboarding']`:
   `{ version: 1, theme, languageFilter, privacyMode, referralCode, partnerPubkey,
   partnerName }`. This is untrusted client input; revalidate partner membership
   and code server-side, and enforce first-touch/account rules there.
3. After successful email authentication, save the preferences to the user's
   account using the website's new authenticated API. Do not infer authentication
   from opening a URL or closing a screen. Resolve pending codes through the same
   approved directory; never assign arbitrary typed codes as verified referrals.

## Validation

CI runs directory signature/trust tests, preference-bridge origin/persistence
checks, bundle reproducibility, and an unsigned iOS Simulator build on macOS.
This Linux workspace cannot run Xcode or an iOS Simulator.

Before release, run on an iPhone simulator/device:

- Fresh install: all four screens; back preserves choices; account skip works.
- Referral: empty input, exact code, name filtering, tap selection, clear, skip,
  long/invalid input, no matches, offline retry, and an empty approved directory.
- Choose light, another language, Privacy Mode on; confirm the first website
  search and native toolbar use the settings. Relaunch: no repeated onboarding.
- Change Settings later; confirm website values are merged without losing other
  config. Follow an external link and confirm no Savedd storage is injected there.
- Verify first-touch attribution remains unchanged when one already exists.
- Test SE-sized screens, landscape, iPad, keyboard, VoiceOver, accessibility text
  sizes, and Reduce Motion. Keep primary/skip buttons reachable while scrolling.
- After email integration: real signup, cancel/failure/retry, existing-user login,
  and actual server-side preference save/recovery across devices.
