# ADultingHD

Gamified household task management for iOS and macOS. Turns adulting
chores into an XP-based game — streaks, levels, achievements, supply
tracking, and cross-device household sharing via iCloud.

**Bundle ID**: `net.shadowpuppet.ADultingHD`
**Platforms**: iOS 17.0+, macOS 14.0+
**Language**: Swift 6.0 / SwiftUI / Swift Charts

## Features

- Freeform household tasks that require only a name; room, personal or
  household scope, assignee, schedule, supplies, checklist, and difficulty
  are optional configuration
- 50+ editable task templates spanning kitchen, laundry, bathroom,
  bedroom, living room, yard, garage, and seasonal maintenance
- Per-task XP with difficulty multipliers, streak bonuses, and
  period-consistency bonuses (daily / weekly / monthly)
- Level-up and achievement celebrations
- Supply tracking (toilet paper, paper towels, etc.) with low-stock
  reminders
- Customizable avatar shop — earn coins, unlock gear
- **Pro unlock** (`$9.99` one-time IAP) — multi-household support,
  invite collaborators, advanced stats, full avatar shop, unlimited
  custom tasks
- **iCloud Documents sync** — tasks/completions/profile mirror to your
  iCloud so your data follows you across devices you own
- **CloudKit household sharing** (Pro) — invite roommates or family
  members via Apple's native share sheet; everyone sees the same
  tasks and competes on the household leaderboard

## Build

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen).
`project.yml` is source of truth; don't hand-edit the `.xcodeproj`.

```bash
# Regenerate Xcode project from project.yml
xcodegen generate

# Build & verify (iOS simulator, unsigned)
xcodebuild build -project ADultingHD.xcodeproj -scheme ADultingHD_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Build & verify (macOS, unsigned)
xcodebuild build -project ADultingHD.xcodeproj -scheme ADultingHD_macOS \
  -destination 'platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
```

## Deploy to TestFlight

```bash
./deploy.sh              # iOS only (default)
./deploy.sh --macos      # macOS only
./deploy.sh --all        # both
./deploy.sh --skip-tests # skip unit tests before archive
```

`deploy.sh` auto-increments the build number in `project.yml`, runs the iOS
unit-test target, and archives. UI tests remain available through the
`ADultingHD_iOS` scheme for explicit UI validation. The script then re-signs
with a hardcoded iOS distribution entitlements dict (necessary
because the API key is Upload-scope only — see
[`docs/cloudkit-sharing.md`](docs/cloudkit-sharing.md)), uploads via
altool, and commits the build bump.

Requires a `.env` file at the repo root with:

```bash
APPSTORE_API_KEY_ID=...
APPSTORE_ISSUER_ID=...
APPSTORE_API_PRIVATE_KEY_PATH=/abs/path/to/AuthKey_XXXX.p8
TEAM_ID=TYQ32QCF6K
```

## Architecture

- **Models** (`ADultingHD/Models/`): Data types — `HouseholdTask`,
  `TaskCompletion`, `UserProfile`, `Achievement`, `Household`
- **Data** (`ADultingHD/Data/`): Built-in template library with suggested
  rooms, supplies, schedules, and difficulty
- **Storage** (`ADultingHD/Storage/`): JSON file persistence with
  iCloud Documents sync (`ICloudMonitor` + `TaskStore` dual-writes,
  `newerOf(cloud:local:)` merge). `CloudKitSync` handles cross-user
  sharing via CKShare
- **Views** (`ADultingHD/Views/`): Platform-adaptive UI — `NavigationSplitView`
  on macOS, `TabView` on iOS
- **Theme** (`ADultingHD/Theme/`): Adaptive colors for light/dark

Engine/model functions are pure — no state mutation, no I/O. Platform-specific
code is guarded with `#if os(macOS)` / `#if os(iOS)`.

## Documentation

- [`docs/cloudkit-sharing.md`](docs/cloudkit-sharing.md) — CloudKit setup,
  CKShare invite flow (`UICloudSharingController`), deploy.sh re-sign
  dance, App Store Connect submission gate for share-URL routing, and
  reusable skills that capture the debugging journey
- [`docs/design/ASSET_LICENSES.md`](docs/design/ASSET_LICENSES.md) — runtime
  artwork provenance and licensing
- [`CLAUDE.md`](CLAUDE.md) — codebase guide for AI coding assistants
- [`GOALS.md`](GOALS.md) — project goals and milestones
- [`PLAN.md`](PLAN.md) — current roadmap

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Adam Eivy / ShadowPuppet, LLC.
