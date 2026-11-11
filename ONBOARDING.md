# First-run onboarding

Five native screens introduce Savedd, optionally choose a referrer, set search preferences, offer Daily Proverb reminders, and invite email sign-in. Setup uses the website's dark palette. Native appearance/language/privacy choices are saved locally and handed to the website before it mounts. An account remains optional.

## Database partner directory

The source is Savedd-com/Savedd's deployed Supabase `referrals` Edge Function:
`POST https://iofxuntxecxcqihuugcr.supabase.co/functions/v1/referrals`, JSON
`{"action":"public"}`, using the website's public publishable key in `apikey`.
No user bearer token, service-role key, direct table access, relay queries, WebKit
signature reader, or Nostr publishing is involved. The API returns active partners
and the program's enabled flag. `pubkey` remains the database's public partner
identifier for compatibility with existing accounts; it is not a relay lookup.

The directory starts loading on the welcome screen, deduplicates concurrent loads,
and caches successful results (including empty ones) for that onboarding session.
Failures retain retry/skip/code entry. Stopping onboarding cancels pending work.
Partner names/codes are filtered locally, with initials as avatar placeholders.
Paused programs and unavailable/invalid partners are not treated as approved.

The selected slug (or an unresolved typed code) is passed as a URL-encoded `ref`
parameter on the first website navigation. The website revalidates it against the
current public directory. Its existing ReferralCapture/ReferralEnrollment logic
handles first-touch, durable account claims, self-referral rejection and existing
account attribution. The native app does not write account referrals or override
an existing website referrer. Existing saved native settings decode unchanged.

## Email sign-in and the return from Mail

**Continue with email** opens the canonical URL
`https://www.savedd.com/auth/email?client=ios` in the existing persistent browser.
The website renders its existing email form: magic link by default, existing
password as a fallback, and optional code entry if the email template includes it.
The native app never stores passwords or copies web session tokens.

For requests started by that page, the website uses
`https://www.savedd.com/auth/ios-callback` as the email redirect. This HTTPS page
forwards only the PKCE `code` to the fixed `savedd://auth/callback?code=…` app URL.
It deliberately disables Supabase URL-session consumption on that intermediate
page so Safari cannot consume a callback intended for the app. It shows an
explicit Open Savedd button so browsers launch the app through a user gesture.

The app registers `savedd` in Info.plist, accepts only the exact auth callback
shape, and loads `https://www.savedd.com/?code=…` in its persistent WKWebView.
The website completes the PKCE exchange using the verifier saved on the same
canonical origin when the email was requested. Callbacks opened inside the browser
also use this path. It works with cold/warm app URL launches after onboarding.
Opening the account page completes *device onboarding*, not authentication: only
the website's verified session marks the user signed in. Expired/reused links use
the website's existing error/retry behavior.

Deploy the companion website routes before distributing this app update. The
existing documented Supabase allowlist `https://www.savedd.com/**` covers the HTTPS
return route; if the production project uses narrower redirects, add the exact
HTTPS callback URL in Supabase Auth URL configuration. No custom-scheme Supabase
redirect, Associated Domains entitlement, or Apple Team change is required.

The website's email account controls explicitly save/load supported search
preferences. Onboarding does not silently upload settings or claim that local
Daily Proverb reminders/bookmarks are account-synced.

## Verification

CI checks API request shape, data validation, cache/empty/retry/paused/cancellation
behavior, preservation of existing native preferences, and callback URL allowlisting.
It also runs the origin-limited website preference bridge tests, native history and
Daily Proverb tests, both simulator builds, and the unsigned Release archive.

On a phone: choose a partner, continue with email, request a real email, tap the link
in Mail/Safari, choose Open Savedd, and confirm sign-in in Savedd. Repeat with the
app closed, an expired link, password sign-in/recovery, and optional email code.
Confirm the account keeps its first referrer and that skipping accounts still works.
No real emails or test accounts are created by automated checks.
