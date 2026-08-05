# ADultingHD Design System — Cozy Domestic Adventure

Status: exploratory direction, not a locked visual specification.

ADultingHD should make ordinary maintenance feel like visible progress through a
home, not like operating a generic analytics dashboard. The visual metaphor is
a **cozy domestic adventure**: rooms become approachable quest zones, recurring
tasks form a path, and XP, streaks, and achievements feel earned without turning
the product into a children's game.

## Reference concepts

- [`design-system-board-v1.png`](./concepts/design-system-board-v1.png)
- [`onboarding-flow-v1.png`](./concepts/onboarding-flow-v1.png)
- [`core-screens-v1.png`](./concepts/core-screens-v1.png)
- [`onboarding-welcome-hero-v1.png`](./concepts/onboarding-welcome-hero-v1.png)
- [`onboarding-daily-loop-v1.png`](./concepts/onboarding-daily-loop-v1.png)

The screen mockups communicate hierarchy and mood. They are not pixel-accurate
implementation instructions, and their navigation should be reconciled with the
real feature set before coding.

## Product principles

1. **The home is the game board.** Lead with rooms, paths, and the next useful
   action. Charts and totals support the loop rather than becoming the product.
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
| `ink` | `#1F2A44` | Primary text, navigation, strong outlines |
| `cream` | `#FFF8ED` | Warm base surface and illustration transition |
| `coral` | `#F46F61` | Primary action and urgent emphasis |
| `questGold` | `#E9A23B` | XP, path, reward, and streak highlights |
| `sage` | `#59A985` | Complete/success and living spaces |
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
- Let one illustration or map become the visual anchor. Do not stack multiple
  white cards inside a large empty background.

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

Coral filled button, 50–56 pt tall, full width in onboarding. Loading preserves
the label width, progress is announced through accessibility, and disabled
states retain readable contrast.

## Screen direction

### Onboarding

- Replace the current empty upper third and text-heavy card with full-bleed art.
- Keep the flow to three conceptual beats: motivation, daily loop, tailored
  rooms. Collect names only when they are required for the household model.
- Keep Pro disclosure honest and skippable; it should not interrupt the core
  first-run value demonstration.
- Use the two generated illustrations as art-direction references. Crop variants
  should be exported per size class before adding them to the asset catalog.

### Home

- Make the house or room path the primary overview, with today's quests attached
  to locations.
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
- Recurring motif: one quest-gold path linking rooms, actions, and rewards.
- Environment first: the home and the work are the subject; mascots are optional
  supporting characters, not the only personality.
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
