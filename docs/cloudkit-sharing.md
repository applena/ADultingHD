# CloudKit Household Sharing

End-to-end notes for the CKShare-based household sharing feature — how
it works, how it was set up, and what to do when it breaks.

## What it does

A household owner in ADultingHD taps **Settings → Households → Invite
someone** (or the same step during onboarding). The app creates a
`CKShare` over a root record in the user's private CloudKit container,
then presents Apple's native `UICloudSharingController` sheet. The
owner picks one or more contacts by name/email/phone or sends via
Messages/Mail/AirDrop. The recipient taps the invite, iOS shows the
"Join [Household]?" sheet, and on accept the recipient's app joins
the shared `HouseholdZone` and starts seeing the same tasks,
completions, and member profiles.

All records in the shared zone (`HouseholdTask`, `TaskCompletion`,
`MemberProfile`, `HouseholdRoot`) sync cross-device via CloudKit zone
subscriptions plus our `userDidAcceptCloudKitShareWith` AppDelegate
hook.

## Code map

| File | Role |
|---|---|
| `ADultingHD/App/Features.swift` | `Features.cloudKitSharing` compile-time flag that gates every CloudKit code path. Never call `CKContainer(identifier:)` when this is off — the init traps if the container entitlement isn't in the signed profile |
| `ADultingHD/Storage/CloudKitSync.swift` | `CloudKitSync` singleton: zone setup, record push/pull, `createOrFetchShare()` that saves the root + CKShare atomically via `privateDB.modifyRecords(saving:deleting:savePolicy:atomically:)` |
| `ADultingHD/Storage/DataStore.swift` | `prepareHouseholdShare()` — the entry point the invite UI calls. Runs `setup()`, returns `(CKShare, CKContainer)` to the UI, and kicks off the one-shot data migration in a background Task so the share sheet opens instantly |
| `ADultingHD/Views/Household/CloudShareSheet.swift` | SwiftUI wrapper around `UICloudSharingController` (iOS) with a simple URL-and-copy fallback for macOS |
| `ADultingHD/Views/Household/HouseholdListView.swift` | Settings path: "Invite someone" button → presents `CloudShareSheet` |
| `ADultingHD/Views/Welcome/WelcomeView.swift` | Onboarding path: invite step → presents the same `CloudShareSheet` |
| `ADultingHD/App/AppDelegate.swift` | Implements `userDidAcceptCloudKitShareWith` on both iOS and macOS. Posts `.cloudKitShareAccepted` which `DataStore.registerJoinedHousehold(from:)` observes to complete the join |

## Invite flow (owner side)

```
User taps Invite
  ↓
DataStore.prepareHouseholdShare()
  ├── UserDefaults[householdSharingEnabled] = true
  ├── AppDelegate.registerForRemoteNotifications()
  ├── ckSync.setup()                    ← account status + zone create
  ├── ckSync.createOrFetchShare()       ← saves CKShare + HouseholdRoot
  │    atomically via modifyRecords
  │    savePolicy=.allKeys atomically=true
  ├── Task { migrateToCloudKitIfNeeded() }   ← background, non-blocking
  └── returns (CKShare, CKContainer)
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
  ├── App installed + routing registered → open app, call
  │    userDidAcceptCloudKitShareWith on our AppDelegate
  └── Otherwise → "Get the latest app from the App Store"
     (see App Store Connect Gate section below)
  ↓
AppDelegate posts .cloudKitShareAccepted notification
  ↓
DataStore.registerJoinedHousehold(from: metadata)
  ├── ckSync.acceptShare(from: metadata)
  ├── ckSync.setup() + pullFromCloudKit()
  └── shared zone records populate local state
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

## deploy.sh re-sign dance (iOS)

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

After `-exportArchive` produces the IPA, the deploy script:

1. Unzips the IPA
2. Writes a **hardcoded iOS-distribution entitlements plist** (see the
   heredoc in `deploy.sh` — it's deliberately literal because the
   profile's raw grants contain wildcards and dev-only keys that App
   Store Connect validation rejects: `icloud-services=*`,
   `ubiquity-kvstore-identifier=TEAMID.*`,
   `icloud-container-development-container-identifiers`)
3. Re-signs the .app bundle with `codesign --force --sign <Apple
   Distribution> --entitlements <that plist> --preserve-metadata=
   identifier,flags,runtime`
4. Grep-verifies the re-signed binary actually contains
   `com.apple.developer.icloud-container-identifiers` before uploading
5. Rebuilds the IPA for altool upload

**If you ever change the capabilities in `ADultingHD.entitlements`, also
update the hardcoded entitlements block in `deploy.sh`.** Otherwise the
new capability will be silently stripped from TestFlight builds.

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
