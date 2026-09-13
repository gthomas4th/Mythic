# Startup timer crash repair

The first Debug launch repeatedly terminated with `EXC_BREAKPOINT` in
`SparkleUpdateController.manageBackgroundTask(_:)`. All eight inspected crash
reports showed the same main-actor queue assertion in the scheduled callback.

The update timer now schedules on `DispatchQueue.main`, matching the callback’s
actor isolation. The six-hour interval and existing update behavior are retained.
No actor checks are disabled.

Verification: Debug build succeeds; the application opens the Mythic Setup
welcome screen through native UI automation. The core suite passes all 24 tests.
The core suite does not exercise Sparkle; startup verification is a separate
runtime check.
