# Development Firebase policy — approved and implemented

The owner approved disabling inherited Firebase initialization and symbol upload
in Debug builds. `AppDelegate` uses `#if !DEBUG`; the Crashlytics build phase exits
before invoking the uploader when `CONFIGURATION` is Debug.

The actual checkout builds successfully and reports "Skipping Firebase symbol upload
in Debug". The verification helper now builds this checkout directly. Historical
baseline builds used disposable copies while authorization was pending.

Release behavior remains inherited and requires review before distribution. No
credentials were rotated and no upstream Firebase project settings were changed.
