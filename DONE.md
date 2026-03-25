# DONE

Completed improvement ideas for ADultingHD.

## 1. Push Notification Reminders

Tasks show as "due" or "overdue" in the UI, but there's no way to get reminded without opening the app. Add local notifications using `UNUserNotificationCenter` — schedule a daily summary of due tasks each morning, and optionally per-task reminders at user-chosen times. This is the single biggest engagement lever missing.

## 2. Statistics Charts (Swift Charts)

Swift Charts is already in the tech stack but unused. Add a Stats tab or section to the Profile view with:
- XP earned per day/week (bar chart)
- Task completions over time (line chart)
- Category breakdown (pie/donut chart)
- Streak calendar heat map (GitHub-style contribution grid)

This gives users visual proof of progress beyond a single XP number.

## 3. Household Multi-User Support

Currently single-user only. Add the ability to create household profiles so family members or roommates can share the same task list. Each person has their own XP, streaks, and achievements. Show a household leaderboard on the dashboard. Storage could stay local with a shared JSON file, or use CloudKit for sync.

## 4. Widgets (WidgetKit)

iOS home screen and Lock Screen widgets showing:
- Today's due task count and next task up
- Current streak and XP progress toward next level
- A "quick complete" widget for the most common daily tasks

Widgets keep the app visible without requiring a launch and reinforce the habit loop.

## 5. Achievement Progress & Detail View

Locked achievements currently show no progress toward unlocking. Add a detail view for each achievement showing:
- Progress bar (e.g., "47/50 tasks completed" for Half Century)
- Flavor text / lore for each achievement
- Unlock date for earned achievements
- Rarity indicator (what percentage of theoretical progress)

This turns achievements from a binary checklist into a motivating goal system.

## 6. Task Notes & Completion Quality

The `TaskCompletion` model has an optional `notes` field but there's no UI to write or view notes. Add:
- A notes text field in the completion confirmation dialog
- A "how well did you do?" quality rating (quick/normal/deep clean)
- Bonus XP for deep clean completions
- Ability to browse past notes in the task detail history

This adds texture to the completion history beyond just timestamps.

## 8. Seasonal & Contextual Tasks

The built-in task library is static. Add seasonal task suggestions that appear based on time of year:
- Spring: deep clean windows, organize garage, service AC
- Fall: clean gutters, winterize outdoor faucets, check weather stripping
- Monthly: tasks that rotate (e.g., clean a different appliance each month)

Surface these as "suggested tasks" on the dashboard rather than cluttering the main list.

## 9. Supply Shopping List

The Supplies view shows what supplies exist and which tasks use them, but there's no way to track inventory or generate a shopping list. Add:
- Low/out-of-stock toggle per supply
- "Generate shopping list" that collects all low/out items
- Share sheet to export the list or send to a reminders/notes app
- Optional: link supplies to product URLs for quick reorder

## 10. Haptics, Sounds & Celebration Animations

Task completion currently just updates the data. Add sensory feedback:
- Haptic feedback on task completion (success pattern)
- Optional sound effects (XP ding, level-up fanfare, streak milestone)
- Confetti or particle animation on level-ups and achievement unlocks
- Streak fire animation that grows with streak length

These small dopamine hits are what make gamification actually feel like a game.
