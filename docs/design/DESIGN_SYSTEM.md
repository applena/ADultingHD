# ADultingHD Design System — Cozy Domestic Adventure

Status: active v1 direction, intentionally open to iteration.

ADultingHD should make ordinary maintenance feel like visible progress through a
home, not like operating a generic analytics dashboard. The visual metaphor is
a **cozy domestic adventure**: rooms become approachable quest zones, recurring
tasks form a manageable weekly rhythm, and XP, streaks, and achievements feel
earned without turning the product into a children's game. The product stays an
app first: room language organizes work, but the UI never assumes a particular
floor plan.

## Reference concepts

- [`design-system-board-v1.png`](./concepts/design-system-board-v1.png)
- [`onboarding-flow-v1.png`](./concepts/onboarding-flow-v1.png)
- [`core-screens-v1.png`](./concepts/core-screens-v1.png)
- [`onboarding-welcome-hero-v1.png`](./concepts/onboarding-welcome-hero-v1.png)
- [`onboarding-daily-loop-v1.png`](./concepts/onboarding-daily-loop-v1.png)

The screen mockups communicate hierarchy and mood. They are not pixel-accurate
implementation instructions, and their navigation should be reconciled with the
real feature set before coding. Earlier concepts include a connected-house
motif; the current app-first direction below supersedes that as core navigation.

## Product principles

1. **The home is the game board.** Lead with due tasks, compact room filters, and
   the next useful action. Rooms organize the work without becoming a literal
   map, while charts and totals support the loop rather than becoming the
   product.
2. **Progress is tangible.** Use trails, stamps, badges, filled markers, and
   compact XP feedback so work visibly changes the experience.
3. **Warm, not juvenile.** Editorial illustration, textured color, and confident
   typography can be playful without fantasy costumes or preschool styling.
4. **One dominant action per screen.** Secondary tools stay available but do not
   compete with the next quest, completion control, or setup action.
5. **Native first.** Keep controls, navigation, Dynamic Type, VoiceOver, reduced
   motion, and platform conventions genuinely native even when surfaces are
   visually distinctive.

## Foundations

### Color

| Token | Value | Use |
| --- | --- | --- |
| `adventureBlue` | `#143359` | Primary actions and strong outlines |
| `cream` | `#FFF8ED` | Warm base surface and illustration transition |
| `coral` | `#FA7373` | Urgent emphasis and warm highlights |
| `hearthGold` | `#F09329` | XP, path, reward, and streak highlights |
| `leafGreen` | `#3D6E4A` | Complete/success and living spaces |
| `sky` | `#70A7E8` | Information and bathroom/clean-water cues |
| `plum` | `#765BC6` | Level progression and rare achievements |

All semantic colors need light and dark variants with WCAG-compliant text
contrast. Status must also use shape, icon, and label; color alone is never the
only signal.

### Typography

- Display: a warm editorial serif for high-impact titles only, with a SwiftUI
  system-rounded fallback when custom-font licensing or Dynamic Type makes it
  impractical.
- Interface: San Francisco/system text for controls, task content, metrics, and
  accessibility-critical labels.
- Default sizes: 28 pt display, 20 pt section title, 17 pt body, 15 pt supporting
  text, and 13 pt metadata. Use text styles rather than fixed sizes in code.
- Prefer sentence case. Reserve all caps for short eyebrow labels.

### Layout

- Use an 8-point spacing grid with 4-point optical adjustments.
- Standard content inset: 16 pt on compact iPhone, 20–24 pt on regular width.
- Standard control height: at least 44 pt.
- Default surface radius: 16 pt. Use smaller 10–12 pt radii for chips and
  task-state controls; avoid applying the same card treatment to every block.
- Let one illustration or compact app preview become the visual anchor. Do not
  stack multiple white cards inside a large empty background, and do not use a
  floor plan or glowing line as core navigation.

## Core components

### Quest row

Contains room icon, task name, compact time/XP metadata, state marker, and a
44-point completion target. A leading rail and icon distinguish `overdue`,
`due`, and `complete` even in grayscale. Navigation and completion must be
separate accessible actions.

### Room tile

Uses a small editorial room scene, room name, selection state, and optional task
count. Selection adds a check mark and strong border; deselection reduces
contrast without making the label unreadable.

### Progress trail

A path or sequence of markers connects the current task, the next room, and a
reward. Motion should be subtle and disabled when Reduce Motion is enabled.

### Reward badge

Achievements use a consistent medal silhouette, semantic symbol, and rarity
treatment. Locked badges keep the silhouette visible and add a lock label so
the system still feels discoverable.

### Primary action

Deep-navy filled button, 50–56 pt tall, full width in onboarding. Loading
preserves the label width, progress is announced through accessibility, and
disabled states retain readable contrast. Coral and gold remain accents rather
than competing calls to action.

## Screen direction

### Onboarding

- Keep the welcome step focused on one small, achievable household action with
  a large, text-free illustration. Use artwork only when it clarifies a
  product behavior.
- Keep the flow to three conceptual beats: motivation, daily loop, and a
  tailored starter list. Supporting setup screens may collect the household
  name, companion, room scope, and explicit quest choices, but every screen
  should move the user toward a useful first list.
- Keep the daily-loop illustration supportive and onboarding-only; it should not
  define how a person's real home is laid out.
- Keep Pro disclosure honest and skippable; it should not interrupt the core
  first-run value demonstration.
- Use the two generated illustrations as art-direction references. Crop variants
  should be exported per size class before adding them to the asset catalog.

### Home

- Make today's due quests the primary overview, with compact room/category chips
  for filtering and direct navigation to the task list. Never imply that those
  categories describe a user's physical floor plan.
- Keep XP and streak visible but compact.
- Surface the next three useful actions before tips, historical metrics, or
  promotions.

### Tasks

- Use a quest-log hierarchy: room section, status, task, time, XP, completion.
- Keep filtering compact and make horizontal overflow intentional and obvious.
- Do not equate “active” with “complete”; those concepts need distinct controls.

### Profile

- Treat the avatar and level as one hero, followed by achievements and the
  household leaderboard.
- Avoid a grid of disconnected metric cards when one progress narrative can
  communicate the same information.

## Illustration system

- Medium: tactile 2D editorial illustration with ink outlines and subtle paper
  grain.
- Recurring motif: quest-gold highlights can connect actions and rewards in
  onboarding, but a line must not act as core navigation between rooms.
- Environment first: the home and the work are the subject; mascots are optional
  supporting characters, not the only personality.
- Prefer focused chore moments or code-native product previews over full-house
  cutaways that prescribe a particular home layout.
- Keep UI text outside raster artwork. Generated art should contain no labels,
  numbers, buttons, or status indicators.
- Prepare light/dark crops and verify meaningful content survives compact iPhone,
  Max iPhone, iPad, and macOS aspect ratios.

## Accessibility and validation

- Test at accessibility text sizes without clipping or covering primary actions.
- Provide concise VoiceOver descriptions for every illustration; mark decorative
  flourishes hidden from accessibility.
- Preserve state meaning under grayscale, increased contrast, and color-blind
  simulation.
- Respect Reduce Motion and Reduce Transparency.
- Add screenshot coverage for onboarding plus Home, Tasks, Schedule, Supplies,
  Stats, and Profile at compact and regular widths.

## Production asset mapping

The untouched ImageGen masters and exact prompts live in `docs/design/`. App
exports are versioned separately under
`ADultingHD/App/Assets.xcassets/`:

- `Onboarding/WelcomeFocusV1` is the current welcome illustration: one small
  task leading to visible progress. `Onboarding/WelcomeHeroV1` remains an
  additive design reference and is not part of the first-run flow.
- `Onboarding/DailyLoopV1` selects compact iPhone, full iPad, and wide macOS
  crops of the task-to-reward illustration.
- `Avatars/raccoon`, `Avatars/turtle`, `Avatars/otter`, and `Avatars/capybara`
  are free starter companions; the avatar name and selection state remain
  SwiftUI copy and accessibility state rather than raster text.

The artwork contains no UI copy. SwiftUI supplies localizable text, adaptive
layout, semantic progress, and concise VoiceOver descriptions around it.
