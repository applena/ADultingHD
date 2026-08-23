# CloudKit Household Sharing

End-to-end notes for the CKShare-based household sharing feature — how
it works, how it was set up, and what to do when it breaks.

## What it does

A household owner in ADultingHD taps **Settings → Households → Invite
someone**. The app creates a
`CKShare` over a root record in the user's private CloudKit container,
then presents Apple's native `UICloudSharingController` sheet. The
owner picks one or more contacts by name/email/phone or sends via
Messages/Mail/AirDrop. The recipient taps the invite and the app either
joins immediately (for an existing user) or stages the metadata for its
first onboarding page. A first-time recipient sees the household and
inviter, enters a display name, and can either accept or create a separate
household without accepting the CloudKit share.

Every `Household` row maps to a single custom CKRecordZone. Owned
households live in `privateCloudDatabase`; joined households live in
`sharedCloudDatabase` and carry `ownerUserRecordName` so the zone
ID resolves correctly across app restarts. Records in the zone
(`HouseholdTask`, `PersonalTaskTombstone`, `TaskCompletion`, `MemberProfile`, `HouseholdRoot`)
sync cross-device via CloudKit zone subscriptions plus our
`userDidAcceptCloudKitShareWith` AppDelegate hook and the
`onContinueUserActivity` SwiftUI modifier.

Tasks marked **Personal** remain in the owner's local workspace and are never
shared with household members. When an existing shared task changes scope, the
owner publishes a UUID-only `PersonalTaskTombstone` so other devices remove
their stale copy; associated completion records are purged as part of the same
sync.

`HouseholdTask.createdAt` and `scheduledOverrideDate` remain local model fields
and are not uploaded as custom CloudKit fields because the production schema
predates them. Existing local values are preserved when a matching cloud task
is merged; a newly joined device falls back to CloudKit's stable system
`creationDate` for records without local recurrence metadata. Checklist data
keeps its original array wire format for older clients.

Task planning fields migrate additively. New clients prefer the optional
freeform `room` field and `scheduleFrequency` (which includes `No Schedule`),
while continuing to dual-write the legacy `category` and `frequency` fields.
Known legacy categories map to room names, legacy `General` maps to no room,
and unknown legacy category strings remain readable as custom rooms. An
unscheduled task writes `Weekly` only as its legacy frequency fallback; new
clients use `scheduleFrequency` and therefore keep it out of recurring due
calculations. Deploy the `room` and `scheduleFrequency` fields from Development
to Production before shipping a build that writes them. Also deploy
`planningSchemaVersion`, `legacyCategorySnapshot`, and
`legacyFrequencySnapshot`; the snapshots identify later legacy-client edits so
the additive fields cannot shadow a room or schedule change made by an older
build.

## Code map

| File | Role |
|---|---|
| `ADultingHD/App/Features.swift` | `Features.cloudKitSharing` compile-time flag that gates every CloudKit code path. Never call `CKContainer(identifier:)` when this is off — the init traps if the container entitlement isn't in the signed profile |
| `ADultingHD/Storage/CloudKitSync.swift` | `CloudKitSync` singleton: per-household zone+database routing, record push/pull, privacy-preserving `PersonalTaskTombstone` markers, `createOrFetchShare(for:)` that saves the root + CKShare atomically, and `removeHouseholdCloudData(for:)` for owner revocation or participant leave. `uploadInitialShareSnapshot(...)` validates every required record before invite presentation. `acceptShare(from:)` returns `HouseholdShareInfo` including owner and inviter identity |
| `ADultingHD/Storage/DataStore.swift` | `prepareHouseholdShare()` creates the share and awaits a fail-closed initial snapshot upload before returning `PreparedHouseholdShare`. `stagePendingOnboardingShare(...)` previews first-launch metadata without accepting it; `acceptPendingOnboardingShare(...)` commits the chosen invite and display name |
| `ADultingHD/Models/Household.swift` | `Household` value type with explicit `.owned` / `.joined(ownerUserRecordName:inviterName:)` ownership. `HouseholdIndex.currentSchemaVersion = 4` |
| `ADultingHD/Views/Household/CloudShareSheet.swift` | SwiftUI wrapper around `UICloudSharingController` (iOS) with a simple URL-and-copy fallback for macOS |
| `ADultingHD/Views/Household/HouseholdListView.swift` | Settings path: "Invite someone" button → presents `CloudShareSheet` |
| `ADultingHD/Views/Welcome/WelcomeView.swift` | Coordinates action-first create and join onboarding. Invite recipients enter their name on page one and can decline into the default house-creation route |
| `ADultingHD/App/AppDelegate.swift` | Implements `userDidAcceptCloudKitShareWith` on iOS and macOS. Enqueues into `IncomingShareInbox` so cold-launch invites aren't lost before SwiftUI's `.task` runs. Also defines `ShareAcceptance.activityType` for the warm-launch `onContinueUserActivity` path |
| `ADultingHD/App/ADultingHDApp.swift` | Drains `IncomingShareInbox`, handles warm-launch user activities, and chooses staged onboarding versus immediate existing-user registration |

## Reset and deletion lifecycle

CloudKit zone identity is the sharing boundary. New households use a unique
`Household-<UUID>` zone; `HouseholdZone` is retained only when migrating an
existing pre-multi-household account. The owner must delete the private zone
before the local household row is removed. CloudKit then removes the records,
share, and every participant together. A participant deleting a joined row
leaves the share by deleting its share record in the shared database.

`DataStore.resetAll()` applies that cleanup to every known household before
removing local files. If CloudKit is unavailable while a *confirmed* share
needs revoking, the reset is cancelled so an invited person cannot remain
attached to server data that the owner can no longer manage locally (see
below for what counts as confirmed vs. best-effort). Accounts that reset on
an older build are detected during onboarding invite preparation; their
legacy zone is revoked before a new share is created.

`Household.shareRecordName` wasn't persisted by builds before this cleanup
existed, and `isHouseholdSharingEnabled` is local `UserDefaults` — not synced
via iCloud — so neither reliably proves an owned household was never shared:
the field can be `nil` for a real legacy share, and the flag can be unset on
a second device or after a reinstall even though the household is shared
from elsewhere. `DataStore.householdCloudKitCleanupTargets(from:)` therefore
splits households into two groups instead of guessing from either signal:
- `confirmed` — `shareRecordName` is set, or the household is joined (a
  joined household only exists because it was shared; the participant-leave
  path re-derives the share directly from the zone, not this field). A
  failure to reach CloudKit for a confirmed household blocks the deletion.
- `ambiguous` — every other owned household. Resolved with a best-effort,
  read-only `CloudKitSync.hasExistingShare` check: attempted whenever
  CloudKit is reachable (so a legacy or cross-device share isn't silently
  left stranded when it's possible to check), but skipped rather than
  blocking when it isn't — most owned households were never shared at all,
  so an ordinary offline local deletion must not be held hostage by one that
  almost certainly has nothing to clean up.

A confirmed share still guarantees revocation before local deletion, exactly
as before; only the ambiguous, likely-never-shared case is best-effort.

## Invite flow (owner side)

```
User taps Invite
  ↓
DataStore.prepareHouseholdShare()
  ├── AppDelegate.registerForRemoteNotifications()
  ├── ckSync.setup()                              ← account status check
  ├── isolateLegacyOnboardingHouseholdWhileSerialized() ← revoke stale reset share
  ├── ckSync.createOrFetchShare(for: target)
  │    ├── ensureOwnedZoneExists(for:)            ← idempotent zone create
  │    └── modifyRecords(saving: [root, share],   ← atomic both-or-nothing
  │                      savePolicy=.allKeys, atomically=true)
  ├── recordShareWhileSerialized(share, target.id)
  ├── UserDefaults[householdSharingEnabled] = true
  ├── ckSync.setupSubscriptions(for: target)
  ├── ckSync.uploadInitialShareSnapshot(...)       ← awaited, every record checked
  └── returns PreparedHouseholdShare
  ↓
CloudShareSheet wraps UICloudSharingController
  ↓
User picks recipient → OS sends invite via Messages/Mail/AirDrop
```

## Accept flow (recipient side)

```
Recipient taps icloud.com/share/... link
  ↓
iOS cloud-share service decodes metadata
  ↓
Looks up container → App ID mapping in Apple's routing DB
  ├── App installed + routing registered → open app, deliver via
  │   either AppDelegate.userDidAcceptCloudKitShareWith (cold-launch)
  │   or NSUserActivity activityType=com.apple.CloudKit.ShareMetadata
  │   (warm-launch)
  └── Otherwise → "Get the latest app from the App Store"
     (see App Store Connect Gate section below)
  ↓
IncomingShareInbox.enqueue(metadata)             ← cold-launch buffer
  └── ADultingHDApp.task drains after DataStore.load()
OR
onContinueUserActivity(ShareAcceptance.activityType)
  ↓
ADultingHDApp.handleIncomingHouseholdShare(metadata)
  ├── Existing user → DataStore.registerJoinedHousehold(from:)
  └── First launch → DataStore.stagePendingOnboardingShare(metadata)
       ├── Welcome shows household + inviter and asks for display name
       ├── "Create my own household instead" clears the staged metadata
       │    and starts the default house-name onboarding
       └── Join → acceptPendingOnboardingShare(id:displayName:)
            ├── ckSync.acceptShare(from:) → HouseholdShareInfo
            ├── replace only a revalidated pristine bootstrap, otherwise preserve it
            ├── activate the stable joined-zone row
            ├── setup subscriptions and pull that exact household
            └── save the entered profile name and clear the matching staged invite
```

## Setup prerequisites

These are one-time configuration steps. Flipping `Features.cloudKitSharing`
to `true` without completing them will crash the app.

### 1. Apple Developer portal

- Navigate to **Identifiers → App IDs → ADultingHD (net.shadowpuppet.ADultingHD)**
  under team **TYQ32QCF6K (ShadowPuppet, LLC)**
- iCloud capability enabled with **Include CloudKit support** checked
- Container `iCloud.net.shadowpuppet.ADultingHD` assigned
- Push Notifications capability (required for CloudKit silent pushes)

### 2. CloudKit Console

- Schema deployed to Development (auto-creates on first debug-build
  record push, or imported via CKML — see `/tmp/adulting-schema.ckdb`
  backup or re-export from the Console)
- Schema deployed to **Production** — TestFlight + App Store both use
  Production. Every time the schema changes in Dev (new record type,
  new field, new index) you must **Deploy Schema Changes…** to push
  to Production before shipping a TestFlight build that relies on it
- `cloudkit.share` system type must exist in both environments — it
  auto-creates when the first CKShare is saved in Development. Always
  re-deploy Dev → Production after first local share creation
- Team selector gotcha: the CloudKit Console defaults to team
  `H67CLQW4PB` (personal team) but the container lives under
  `TYQ32QCF6K`. Switch via the Account Menu

### 3. Entitlements

In `ADultingHD/App/ADultingHD.entitlements` (and mirrored in `project.yml`
so xcodegen writes them consistently):

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.net.shadowpuppet.ADultingHD</string></array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
    <string>CloudKit</string>
</array>
<key>aps-environment</key>
<string>development</string>   <!-- flipped to production by deploy.sh re-sign -->
```

## deploy.sh re-sign dance (iOS) {#deploysh-re-sign-dance-ios}

### Why it exists

Our App Store Connect API key has Upload-only scope. That means
`xcodebuild archive -allowProvisioningUpdates` fails with "Authentication
failed" when it tries to register new capabilities (documented in the
sister skill `xcodebuild-appgroup-provisioning-auth-failure`). The
workaround is to archive **unsigned** with `CODE_SIGNING_ALLOWED=NO`
and sign during `xcodebuild -exportArchive`.

But that workaround has its own gotcha: `-exportArchive` rebuilds the
entitlements dict from scratch using only the profile's team identifier,
dropping every capability entitlement from `ADultingHD.entitlements`.
The resulting binary has the CloudKit profile embedded but claims no
CloudKit entitlements, so `CKContainer(identifier:)` traps at runtime
as if the entitlement wasn't granted.

### The fix in `deploy.sh`

Earlier revisions of this script re-signed the *exported IPA* after the
fact, using a hardcoded local `Apple Distribution: ShadowPuppet, LLC
(TYQ32QCF6K)` identity. That broke the day a release machine had
authenticated-export access (via the App Store Connect API key) but not
the Distribution private key itself — export succeeded, the post-export
`codesign` step failed with "no identity found", and there was no safe
fallback (uploading the un-re-signed IPA ships a binary with only
minimal entitlements). See issue #28.

The script now seeds entitlements into the **archive**, before export,
instead of re-signing the exported IPA after:

1. `xcodebuild archive` produces the unsigned `.xcarchive` as before.
2. `deploy.sh` locates a local codesigning identity — preferring "Apple
   Development" (the same cert Xcode already uses for local device
   builds), falling back to "Apple Distribution" if present, or
   `DEPLOY_SEED_SIGN_IDENTITY` from `.env` if set. **No Apple
   Distribution private key is required for this step.**
3. It writes a **production iOS entitlements plist** (built from
   `$TEAM_ID` in `.env`, not hardcoded — see the heredoc in `deploy.sh`)
   and `codesign`s the archive's `.app` bundle in place with it. The
   values are deliberately literal/non-wildcarded because the profile's
   raw grants contain wildcards and dev-only keys that App Store Connect
   validation rejects: `icloud-services=*`,
   `ubiquity-kvstore-identifier=TEAMID.*`,
   `icloud-container-development-container-identifiers`.
4. `xcodebuild -exportArchive` runs as before, authenticated via the
   App Store Connect API key. Because the archive now carries concrete
   entitlement values instead of nothing, the Distribution-signed export
   carries them through too.
5. `deploy.sh` unzips the **exported IPA** and verifies, before upload:
   - `codesign -dvvv` shows `Authority=Apple Distribution: …` and
     `TeamIdentifier=$TEAM_ID` (the export step, not the seed step,
     determines the final signing authority)
   - `codesign -d --entitlements :-` includes the CloudKit container,
     CloudKit/CloudDocuments services, ubiquity container, `aps-
     environment`, `keychain-access-groups`, and
     `com.apple.security.application-groups` (the widget's shared
     container) keys, and `get-task-allow` is `false`
   - Any failed check `exit 1`s before the upload step runs

**If you ever change the capabilities in `ADultingHD.entitlements`, also
update the production entitlements heredoc AND the verification key list in
`deploy.sh`.** Otherwise the new capability will be silently stripped from
TestFlight builds, or a stale check will pass without actually covering it.
This hand-maintained duplication (the same keys live in
`ADultingHD/App/ADultingHD.entitlements`, `project.yml`, and now two spots
in `deploy.sh`) is a known tradeoff, not an oversight: App Store Connect
validation rejects the wildcard/dev-only values Apple's own provisioning
profile grants (see the cheat sheet below), so the script can't just read
the checked-in `.entitlements` file verbatim — it has to override specific
keys with production-safe literal values. A follow-up that derives the
verification key list (not the seed values, which must stay overridden)
from `ADultingHD/App/ADultingHD.entitlements` via `PlistBuddy`/`plutil`
would close that gap; deferred out of this change to keep the signing-path
fix isolated and reviewable on its own.

### Prerequisites

- An **Apple Development** certificate + private key in the release
  machine's login keychain (`security find-identity -v -p codesigning`
  should list it). This is the same cert used for everyday local
  `xcodebuild build`/`test` runs — nothing extra to provision.
- The App Store Connect API key in `.env`
  (`APPSTORE_API_PRIVATE_KEY_PATH` / `APPSTORE_API_KEY_ID` /
  `APPSTORE_ISSUER_ID`) still needs Upload scope, same as before.
- An Apple Distribution certificate/key is **not** required on the
  machine running `deploy.sh` — Distribution signing happens on Apple's
  side during the authenticated `-exportArchive` call.
- Nothing in the seed/verify steps prints private key material or API
  key contents; only the resolved identity's *name* (a certificate
  common name, not a secret) and codesign/entitlements metadata are
  logged.

### What's been verified by execution vs. inspection only

Build 38 validated steps 1-5 above end-to-end on a real release machine:
unsigned archive → Apple Development seed → authenticated export →
Apple Distribution-signed IPA with full production entitlements →
passed upload. The current `deploy.sh` code implementing that flow has
been syntax-checked (`bash -n`) and reviewed by inspection, but has
**not** been re-run through a live `xcodebuild archive`/`-exportArchive`
cycle since this refactor (no Xcode/codesigning environment available
where the change was made). Run a real `./deploy.sh --skip-tests`
dry run on a machine with Xcode and the API key configured before
trusting it for a release.

### The validation error cheat sheet

| Error from App Store Connect upload | Fix |
|---|---|
| `icloud-container-environment` not supported (empty value) | Add `<key>com.apple.developer.icloud-container-environment</key><string>Production</string>` to re-sign entitlements |
| `icloud-services` value `*` not supported | Replace with specific array `[CloudDocuments, CloudKit]` |
| `ubiquity-kvstore-identifier` wildcard `TEAMID.*` not supported | Remove or set specific value |
| `icloud-container-development-container-identifiers` not supported | Remove — it's development-only |
| `application-groups` not granted | Either enable App Groups capability on the App ID, or remove from re-sign entitlements (widget's shared UserDefaults will silently break) |

## App Store Connect submission gate

`icloud.com/share/...` URLs route to installed apps based on a
**container → App ID → App Store app** mapping maintained by Apple's
routing service. Until the app is at least submitted for App Store
review (state: "Waiting for Review", "In Review", or "Ready for Sale"),
recipients tapping a share URL see "Get the latest app from the App
Store" even when they have the TestFlight build installed.

This is not a bug in our code — it's how Apple's share-link routing
works for unreleased apps. To unblock cross-device testing with real
recipients, submit the app for review. It doesn't need to be approved;
just submitted.

TestFlight-internal testers on the owner's device will still be able
to create shares and see the UICloudSharingController sheet correctly.
The block is only on the recipient's "accept" step.

## Testing the sharing flow locally

### Automated tests (one simulator, Development CloudKit)

`ADultingHDTests/CloudKitIntegrationTests.swift` covers the owner side:
zone setup, share creation, idempotency, and recipient-side metadata fetch.
Enable with an env var so CI skips them:

```bash
CLOUDKIT_INTEGRATION_TESTS=1 xcodebuild test \
    -scheme ADultingHD_iOS \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
    -only-testing ADultingHDTests_iOS/CloudKitIntegrationTests
```

`testShareURL_metadataFetchable` is the key regression test — it calls
`CKFetchShareMetadataOperation` with the live share URL, which is exactly
what iOS does when a recipient taps the link. If this test passes in
Development, the schema is correct and the recipient-side routing will work
in Production once the App Store submission gate is cleared.

### Two-simulator cross-account test

The full accept flow — two different Apple IDs, one inviting the other —
cannot be automated in a single process because `CKShare.Metadata` has no
public initializer and `userDidAcceptCloudKitShareWith` is triggered by
Apple's OS-level URL router, not by app code.

The semi-automated script at `scripts/test-sharing.sh` handles the
mechanical parts: it builds a signed app, installs it on two simulators,
monitors Simulator A's logs for the share URL, and fires it at Simulator B
via `xcrun simctl openurl` — which triggers iOS's native "Join Household?"
sheet and then calls `userDidAcceptCloudKitShareWith` in the app.

```bash
./scripts/test-sharing.sh

# Override simulator names if needed:
SIM_A_NAME="iPhone 16 Pro" SIM_B_NAME="iPhone 16" ./scripts/test-sharing.sh
```

See [`docs/test-accounts.md`](test-accounts.md) for one-time setup:
creating two test Apple IDs and signing them into the simulators.

Run this test before any release that touches the sharing flow.

## Related skills (Claudeception library)

Problems that have bitten this codebase and are now captured as reusable
skills in `~/.claude/skills/`:

- `cloudkit-sharing-first-time-implementation-gotchas` — initial portal
  setup, reserved record-type prefixes, CKShare atomic save
- `cloudkit-stale-distribution-profile-trap` — how a cached
  provisioning profile that predates a capability addition produces
  runtime `CKContainer(identifier:)` traps even when the portal looks
  correct
- `xcodebuild-unsigned-archive-strips-entitlements` — the deploy.sh
  re-sign dance above, in full detail, for other projects that hit
  the same pattern
- `xcodebuild-appgroup-provisioning-auth-failure` — why we can't use
  `-allowProvisioningUpdates` during archive
- `ckcontainer-test-launch-crash` — the unsigned-simulator variant of
  the CKContainer trap

## Cross-references

- [`CLAUDE.md`](../CLAUDE.md) — top-level project guide; links here
  from the "CloudKit Sharing" section
- [`README.md`](../README.md) — user-facing project overview
- [`deploy.sh`](../deploy.sh) — the re-sign logic this doc describes
- [`scripts/test-sharing.sh`](../scripts/test-sharing.sh) — two-simulator cross-account test runner
- [`docs/test-accounts.md`](test-accounts.md) — setting up test Apple IDs for the two-simulator test
- `ADultingHDTests/CloudKitIntegrationTests.swift` — automated one-simulator tests
