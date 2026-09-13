# Epic concurrency repair — approved and implemented

The owner approved a contained repair after the pinned upstream failed Swift 6
actor-isolation checks on Xcode 26.6. Five diagnostics affected install metadata,
uninstall, launch and move entry points.

Mutable game and UI state remains on MainActor. `ActorBoundWork` prepares fresh
immutable inputs when queued work starts, performs background work, and applies
successful results on MainActor. Cancellation and failures prevent state application.
The existing queue, persistence and Legendary command behavior are retained.
Move and uninstall apply state only after successful process exit. The uninstall
fallback never deletes files when the caller requested preservation.

Metadata parsing uses a locked value type instead of unstructured tasks mutating
captured variables. Fractional MiB values retain precision. No new unchecked
Sendable conformance or reduced concurrency checking was introduced.

Validation: full Debug build passes; seven synthetic operation/metadata tests cover
execution boundaries, cancellation, errors, late input preparation and parser values.
No real game was moved or uninstalled. This is a bounded repair, not a verification
of every inherited operation-queue race or live Epic account workflow.
