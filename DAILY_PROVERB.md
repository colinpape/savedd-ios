# Daily Proverb

Onboarding now offers an optional reminder between preferences and account creation. Nothing asks iOS for permission until the person taps **Enable daily reminder**. Default: 8 a.m. local time. **Maybe later** continues setup. Settings includes reminder controls and today's reading for existing users.

The World English Bible (WEB) is public domain and uses modern English. All 31 chapters (915 verses) are bundled from https://bible-api.com/ using its `translation=web` Proverbs endpoints. Each chapter has one selected verse and a separately labeled Savedd reflection. These passages and reflections repeat monthly. Scripture is kept verbatim apart from whitespace normalization. No content is generated at notification delivery time. No account, server, or push entitlement is required.

There are 58 local notification requests: monthly repeats for days 1–28, yearly repeats for valid months on days 29–31, and the next February 29 as a one-time request refreshed on app activation. This avoids iOS rolling nonexistent dates into the next month while staying below the 64-request limit. Dates and chosen local hour/minute use the Gregorian calendar. Tapping a notification opens its chapter, including older notifications from a different day. Full readings work offline; Explore uses Savedd search. iOS Focus, notification settings, and scheduled summaries can affect when alerts appear. Reminder settings stay on the device and are separate from website preferences.

## Phone checks

- Fresh setup: verify step count, preview, time choice, Maybe later, permission grant and denial, and Continue without an account.
- Settings: enable, change the time, disable, revoke iOS permission and return, re-enable permission and return. No prompt on opening the page.
- Tap a delivered reminder with Savedd closed, foregrounded, and in the background. Confirm the chapter matches the notification, full reading works in airplane mode, and Explore searches within Savedd.
- Verify local delivery after a time-zone change, at month boundaries (including February), and through daylight-saving changes. iOS controls final delivery timing.

## Denomination

Do not infer denomination from a referral partner, Bible translation, or browsing. I recommend introducing an optional **Your faith tradition** step only when it controls a visible benefit (such as relevant resources or optional reflections). Include **Prefer not to say**, **Exploring / unsure**, and **Other**, alongside user-reviewed traditions. The common Proverbs reading can remain the default for everyone. Explain the benefit before asking, let users change or clear it, and keep the choice on-device unless they explicitly choose account sync. No denomination field is collected in this version.
