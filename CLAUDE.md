# ADultingHD

Gamified household task management app for iOS and macOS. Turns adulting chores into an XP-based game with streaks, levels, achievements, and supply tracking.

## Tech Stack

- Swift 6.0, SwiftUI, Swift Charts
- iOS 17.0+ / macOS 14.0+
- XcodeGen (`project.yml` is source of truth, not `.xcodeproj`)
- JSON file-based storage in Documents directory
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
- **Storage** (`ADultingHD/Storage/`): JSON file persistence and @Observable in-memory state
- **Views** (`ADultingHD/Views/`): Platform-adaptive — `NavigationSplitView` on macOS, `TabView` on iOS
- **Theme** (`ADultingHD/Theme/`): Adaptive colors for light/dark mode

## Key Conventions

- Engine/model functions are pure — no state mutation, no I/O
- Platform-specific code guarded with `#if os(macOS)` / `#if os(iOS)`
- Gamification: XP per task (difficulty-based), levels, streaks, achievements
- Tasks have categories, frequencies, difficulty ratings, and supply lists

## Git Workflow

After completing a significant feature or enhancement:
1. Run `/simplify` to review changed code for reuse, quality, and efficiency — fix any issues found
2. Commit and push to the default branch
