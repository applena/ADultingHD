# Household sharing audit — 2026-09-04

The review covered app lifecycle, models, storage, services, SwiftUI screens,
platform configuration, deployment and tests. Implementation is concentrated on
recipient invitations and the correctness of multiple household workspaces.

## Repaired

- Capture invitation metadata at scene creation and during warm activation.
- Route validated URL and activity fallbacks through a deduplicated inbox.
- Require an explicit add/merge decision for existing users.
- Fetch the destination before switching; preserve the source and pending
  invitation on acceptance, fetch, upload or disk failures.
- Merge only missing shared chores, preserving destination edits and original
  home backups. Do not transfer memberships, private chores or completion XP.
- Resume existing sharing sessions; use a supported shared-database subscription.
- Scope completion uploads by household provenance and keep ambiguous legacy
  history local. Exclude other members from personal streak/XP and Undo actions.
- Accept equal/lower-XP snapshots for other members so name/avatar changes update.
- Use native participant management on macOS and protect invitation diagnostics.
- Recover valid older storage copies and isolate unit tests from app/iCloud files.
- Fix iOS backup export, weekday schedule validation, household-switcher layout,
  leave/delete wording, checklist accessibility and level-up celebration timing.

## Remaining independent work

- Persist shared task deletion and completion-undo tombstones. Existing CloudKit
  union reconciliation can resurrect a locally deleted record. A durable remote
  deletion contract and backward-compatible schema deployment are required.
- Preserve consistency-bonus metadata in the CloudKit completion contract so
  undo on a second device can reverse the exact original bonus.
- Embed the existing widget extension in the iOS app and extend the archive/export
  signing workflow for that extension. Merely linking the target would not ship
  a correctly signed extension.
- Supply-stock state is currently local/iCloud Documents only. Sharing stock
  between Apple IDs requires its own CloudKit contract and schema deployment.
- Celebration particles still need a Reduce Motion variant.

## Verification boundaries

Local validation passed on Xcode 26.6: 216 unit tests on iOS and 216 on macOS
(four signed CloudKit integration tests skipped on each platform), plus five
iPhone UI tests covering add, merge, decline, retry, large accessibility text
in dark mode, and invalid twice-weekly scheduling. This adds 39 unit tests and
five UI tests. Invitation overview, merge and retry screenshots were inspected.

Deterministic tests exercise the real invitation transaction and file store,
with injected CloudKit responses for failures and retries. iOS UI tests exercise
an isolated DEBUG-only invitation fixture. Neither proves Apple's live Messages
routing or Production participation across two Apple IDs; those require the
signed two-account device acceptance pass documented in cloudkit-sharing.md.
