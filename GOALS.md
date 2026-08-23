# GOALS.md

Make adulting suck less by turning household chores into a game worth playing.

---

## Mission

ADultingHD exists because household maintenance is necessary, repetitive, and deeply unmotivating. The app has three selling points, and every feature traces back to one of them:

1. **Tell you exactly what to do, today** — Not just a task name, but a description, and room for step-by-step instructions and the supplies it needs, so a chore doesn't have to start with "wait, how do I even do this."
2. **Divide the labor** — Invite the people you live with into your household (via a native iCloud share — no ADultingHD account to create) so chores can be assigned to whoever's doing them, and everyone can see who did what, and when.
3. **Make it a game** — RPG-style progression — XP, levels, streaks, achievements — turns "I have to clean the bathroom" into "I'm 200 XP from leveling up."

The goal is a native iOS/macOS app that makes household management genuinely engaging for individuals and families, without requiring a custom account system, a server, or a subscription.

---

## Core Tenets

1. **Gamification is the product, not a gimmick** — Every feature decision filters through "does this make chores feel more rewarding?" XP calculations, streak mechanics, and achievement unlocks are first-class concerns, not afterthoughts bolted onto a task list.

2. **Offline-first, private by default** — All data lives on-device as JSON files first. No custom server, no ADultingHD account, no telemetry. Cross-device sync and household invites ride on the user's existing iCloud account (JSON mirrored to iCloud Documents; household sharing via `CKShare`) rather than a backend we operate — so multi-person households work without anyone signing up for anything new. Users own their data completely.

3. **Cross-platform with native feel** — iOS and macOS from a single codebase, but each platform gets its own navigation paradigm (TabView vs. NavigationSplitView) and layout tuning. No lowest-common-denominator UI.

4. **Start with the task, configure when useful** — A task name is enough to begin. Ship 50+ editable templates with sensible room, schedule, supply, and difficulty suggestions, but never make a room or recurring schedule a creation gate. Users should feel the game loop within 30 seconds of launching, not after 20 minutes of configuration.

5. **Pure architecture** — Model and engine functions stay pure (no side effects, no I/O). Storage is isolated behind actors. This keeps the codebase testable and the mental model simple.

---

## Milestones

### v1.0 — The Complete Game Loop

The app delivers a full gamification cycle: discover tasks, complete them with quality ratings, earn XP, level up, maintain streaks, unlock achievements, and celebrate progress. Households can add multiple members who compete on a shared leaderboard. Widgets surface key stats without opening the app. Statistics charts visualize progress over time. Supply tracking connects tasks to real-world inventory. The experience feels rewarding on day one and sustaining on day thirty.

- **Core loop** — Completing any task feels immediately rewarding through XP gains, streak maintenance, and progress toward the next level
- **Depth** — Achievements, seasonal suggestions, quality ratings, and optional room insights give long-term players new goals to chase
- **Task clarity** — Every task starts with a user-defined name. Optional descriptions, supplies, rooms, schedules, and ordered step-by-step instructions (`ChecklistItem.instructions`) add context when "what" is not enough and a chore needs a "how"
- **Household play** — Shipped via CloudKit `CKShare`: a household owner invites others (even across Apple IDs) through the native share sheet; accepted invites sync the same task list, completions, and leaderboard. Tasks can carry a `defaultAssigneeId` so a household can divide chores by member, and the activity feed/leaderboard shows who did what and when
- **Passive engagement** — Widgets and notifications keep the game present without requiring the app to be open
- **Supply awareness** — Task-linked inventory tracking bridges the gap between "what needs doing" and "what do I need to buy"

### v2.0 — Smarter Scheduling *(shipped)*

The app moves beyond tracking what's due to actively helping users plan their time. `ScheduleView` estimates daily effort, can optionally batch configured tasks by room, and `PowerHourView` guides users through a focused, timed, sequential completion flow. Unscheduled tasks remain trackable without being treated as recurring due work. The experience is proactive ("here's your optimal block") rather than purely reactive.

- **Time intelligence** — Shipped. The schedule header and optional room batch rows show per-task and per-day minute totals so users can see effort before committing.
- **Spatial batching** — Shipped. Today's scheduled tasks default to a task-first list and can switch into collapsible room sections when spatial batching is useful.
- **Guided sessions** — Shipped. "Start Power Hour" launches a coached, timed, one-task-at-a-time flow with pacing and completion tracking.
- **Flexible rescheduling** — Shipped (issue #25). Dragging a task to a different day in `ScheduleView`'s week view sets a one-off `scheduledOverrideDate` that moves that occurrence without touching the recurring schedule; completing the task resumes the normal cadence.

---

## Long-Term Vision

ADultingHD becomes the default way a household thinks about maintenance — not a chore list you dread opening, but a game you check because you want to. The progression system is deep enough that long-term users still find new achievements to chase. Families coordinate naturally through shared visibility. The app respects that adulting is hard by making the meta-game of tracking it genuinely fun, while staying lightweight, private, and free of engagement-dark-patterns.

---

## Non-Goals

- **Not a general-purpose to-do app** — ADultingHD is specifically for household maintenance tasks, whether recurring, one-time, or not scheduled yet. Work projects and generic grocery lists belong elsewhere.

- **No custom backend or ADultingHD account** — Cross-device sync and household invites are shipped, but they ride entirely on the user's existing iCloud account (iCloud Documents mirroring + CloudKit `CKShare`). There is no server we operate and no separate account to create just to use the app.

- **No social features beyond the household** — The leaderboard is for your family, not the internet. No sharing, no public profiles, no social pressure mechanics.

- **No monetization through engagement manipulation** — No artificial cooldowns, energy systems, or pay-to-skip mechanics. The gamification serves motivation, not retention metrics.

- **Not open source** *(inferred)* — Developed under Shadow Puppet LLC as a proprietary product distributed through the App Store.

---

For the tactical backlog and current work items, see [PLAN.md](./PLAN.md).
