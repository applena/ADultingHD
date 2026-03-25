# GOALS.md

Make adulting suck less by turning household chores into a game worth playing.

---

## Mission

ADultingHD exists because household maintenance is necessary, repetitive, and deeply unmotivating. By layering RPG-style progression mechanics — XP, levels, streaks, achievements — on top of real chores, the app transforms "I have to clean the bathroom" into "I'm 200 XP from leveling up." The goal is a native iOS/macOS app that makes household management genuinely engaging for individuals and families, without requiring accounts, cloud services, or subscriptions.

---

## Core Tenets

1. **Gamification is the product, not a gimmick** — Every feature decision filters through "does this make chores feel more rewarding?" XP calculations, streak mechanics, and achievement unlocks are first-class concerns, not afterthoughts bolted onto a task list.

2. **Offline-first, private by default** — All data lives on-device as JSON files. No server, no account creation, no telemetry. Users own their data completely.

3. **Cross-platform with native feel** — iOS and macOS from a single codebase, but each platform gets its own navigation paradigm (TabView vs. NavigationSplitView) and layout tuning. No lowest-common-denominator UI.

4. **Opinionated defaults, zero setup friction** — Ship with 50+ pre-built tasks, sensible frequencies, and difficulty ratings. Users should feel the game loop within 30 seconds of launching, not after 20 minutes of configuration.

5. **Pure architecture** — Model and engine functions stay pure (no side effects, no I/O). Storage is isolated behind actors. This keeps the codebase testable and the mental model simple.

---

## Milestones

### v1.0 — The Complete Game Loop

The app delivers a full gamification cycle: discover tasks, complete them with quality ratings, earn XP, level up, maintain streaks, unlock achievements, and celebrate progress. Households can add multiple members who compete on a shared leaderboard. Widgets surface key stats without opening the app. Statistics charts visualize progress over time. Supply tracking connects tasks to real-world inventory. The experience feels rewarding on day one and sustaining on day thirty.

- **Core loop** — Completing any task feels immediately rewarding through XP gains, streak maintenance, and progress toward the next level
- **Depth** — Achievements, seasonal suggestions, quality ratings, and category mastery give long-term players new goals to chase
- **Household play** — Multiple profiles with independent progression and a shared leaderboard make chores a friendly competition
- **Passive engagement** — Widgets and notifications keep the game present without requiring the app to be open
- **Supply awareness** — Task-linked inventory tracking bridges the gap between "what needs doing" and "what do I need to buy"

### v2.0 — Smarter Scheduling *(inferred)*

The app moves beyond tracking what's due to actively helping users plan their time. Scheduling becomes intelligent — estimating daily effort, batching tasks by location, and guiding users through focused "power hour" sessions with timers. The experience shifts from reactive ("what's overdue?") to proactive ("here's your optimal 45-minute block").

- **Time intelligence** — Users see effort estimates and can make informed decisions about what to tackle today
- **Spatial batching** — Tasks grouped by room/category reduce context-switching and make cleaning sessions efficient
- **Guided sessions** — Power hour mode turns a task list into a coached workflow with pacing and completion tracking

---

## Long-Term Vision

ADultingHD becomes the default way a household thinks about maintenance — not a chore list you dread opening, but a game you check because you want to. The progression system is deep enough that long-term users still find new achievements to chase. Families coordinate naturally through shared visibility. The app respects that adulting is hard by making the meta-game of tracking it genuinely fun, while staying lightweight, private, and free of engagement-dark-patterns.

---

## Non-Goals

- **Not a general-purpose to-do app** — ADultingHD is specifically for recurring household tasks. One-off reminders, work projects, and grocery lists belong elsewhere.

- **No cloud sync or accounts** — Simplicity and privacy outweigh cross-device sync. If sync becomes necessary, it should use platform-native mechanisms (iCloud), not a custom backend.

- **No social features beyond the household** — The leaderboard is for your family, not the internet. No sharing, no public profiles, no social pressure mechanics.

- **No monetization through engagement manipulation** — No artificial cooldowns, energy systems, or pay-to-skip mechanics. The gamification serves motivation, not retention metrics.

- **Not open source** *(inferred)* — Developed under Shadow Puppet LLC as a proprietary product distributed through the App Store.

---

For the tactical backlog and current work items, see [PLAN.md](./PLAN.md).
