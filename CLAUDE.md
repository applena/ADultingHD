# ADultingHD

Gamified household task management app for iOS and macOS. Turns adulting chores into an XP-based game with streaks, levels, achievements, and supply tracking.

## Tech Stack

- Swift 6.0, SwiftUI, Swift Charts
- iOS 17.0+ / macOS 14.0+
- XcodeGen (`project.yml` is source of truth, not `.xcodeproj`)
- JSON file-based storage in Documents, mirrored to iCloud Documents for cross-device sync
- Bundle ID: `net.shadowpuppet.ADultingHD`

## Build Commands

```bash
xcodegen generate
xcodebuild build -project ADultingHD.xcodeproj -scheme ADultingHD_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build -project ADultingHD.xcodeproj -scheme ADultingHD_macOS \
  -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
./deploy.sh          # TestFlight deployment
./deploy.sh --skip-tests
```

## Architecture

- **Models** (`ADultingHD/Models/`): All data types — HouseholdTask, TaskCompletion, UserProfile, Achievement
- **Data** (`ADultingHD/Data/`): Built-in task library with 50+ household tasks, categories, supplies, frequencies
- **Storage** (`ADultingHD/Storage/`): JSON file persistence with iCloud Documents sync (`ICloudMonitor` + `TaskStore` dual-writes)
- **Views** (`ADultingHD/Views/`): Platform-adaptive — `NavigationSplitView` on macOS, `TabView` on iOS
- **Theme** (`ADultingHD/Theme/`): Adaptive colors for light/dark mode

## Key Conventions

- Engine/model functions are pure — no state mutation, no I/O
- Platform-specific code guarded with `#if os(macOS)` / `#if os(iOS)`
- Gamification: XP per task (difficulty-based), levels, streaks, achievements
- Tasks have categories, frequencies, difficulty ratings, and supply lists

## iCloud Sync Pattern

All files in `TaskStore` are dual-written: once to the local Documents directory (`~/Documents/ADultingHD/`), once to the iCloud ubiquity container (`iCloud.net.shadowpuppet.ADultingHD/Documents/ADultingHD/`). Loads use a `newerOf(cloud:local:)` comparison of modification dates to prefer the most-recently-updated copy.

`ICloudMonitor` (Storage/ICloudMonitor.swift) watches the iCloud container via `NSMetadataQuery` for `*.json` changes from other devices. On detection it debounces 2s, checks a 5s write-suppression window (to ignore our own iCloud writes), then posts `.dataDidSync` which `DataStore.startSyncObserver()` handles by calling `load()`.

This is the same pattern used in MortalLoom and EscapeMint-Swift.

## Workflow

**Always run `/simplify` before building.** Any time changed code is about to be built (`xcodebuild`, `./deploy.sh`, or a test run), first invoke `/simplify` to review the diff for reuse, quality, and efficiency. Fix anything it flags, then build. This catches redundancy, dead state, and perf regressions while they're cheap to address — not after they've shipped.

After completing a significant feature or enhancement:
1. Run `/simplify` (again if code has changed since the pre-build run) and fix any remaining issues
2. Commit and push to the default branch
