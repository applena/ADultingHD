# ImageGen briefs

These built-in ImageGen briefs produced the first design exploration. Preserve
them so future iterations can make one deliberate change at a time.

## Design-system board

```text
Use case: infographic-diagram
Asset type: holistic mobile app design-system concept board
Primary request: create a polished visual design-system board for ADultingHD, a native iOS app that turns household chores into an encouraging cozy adventure. Show a cohesive system, not random moodboard fragments.
Scene/backdrop: warm parchment-white canvas with softly rounded modular sections
Subject: color palette swatches, typography hierarchy samples, spacing rhythm, rounded card and button components, task-state chips, XP progress meter, room-category icons, achievement badges, and one small mascot-style domestic adventure illustration
Style/medium: shippable Apple-platform product design presentation; tactile 2D editorial illustration; clean SwiftUI-feasible components; subtle paper grain; modern, mature, playful without being childish
Composition/framing: landscape design board, orderly grid, generous whitespace, crisp alignment
Color palette: ink navy #1F2A44, warm cream #FFF8ED, coral #F46F61, quest gold #E9A23B, sage #59A985, sky #70A7E8, plum #765BC6
Text (verbatim): "ADultingHD", "Cozy Domestic Adventure", "Today’s Quests", "42 XP", "7 day streak", "Kitchen", "Bathroom", "Laundry", "Done"
Constraints: use the exact text only once where sensible; typography must be highly legible; interface elements must look implementable in SwiftUI; no device mockup; no logos other than the wordmark; no watermark
Avoid: generic fintech dashboard, candy gradients, neon, glassmorphism, childish preschool art, clutter, tiny unreadable annotations
```

## Onboarding flow

```text
Use case: ui-mockup
Asset type: high-fidelity iPhone onboarding flow concept
Primary request: design three portrait mobile screens for ADultingHD as a cohesive onboarding sequence that feels vivid and purposeful rather than card-heavy or boring
Scene/backdrop: three iPhone screen canvases side by side on a neutral presentation background
Subject: screen 1 welcome with a large original cozy-house adventure illustration where ordinary rooms feel like quest zones; screen 2 explains the daily loop with one connected illustrated path from choose task to complete to earn XP; screen 3 room-selection setup with expressive room tiles and a clear primary action
Style/medium: shippable native iOS product UI; 2D editorial illustration with simple shapes, subtle texture, confident ink outlines; mature playful tone
Composition/framing: full-bleed art in upper half, concise copy, strong bottom action area, clear hierarchy, safe areas respected
Color palette: ink navy #1F2A44, warm cream #FFF8ED, coral #F46F61, quest gold #E9A23B, sage #59A985, sky #70A7E8, plum #765BC6
Text (verbatim): "Make the house easier to run", "Set up my home", "A simple daily loop", "Next", "Choose your rooms", "Build my quest list"
Constraints: render each exact phrase once; legible typography; practical tap targets; no generic stock icons as the main visual; no watermark
Avoid: six nested cards, excessive explanatory text, childish cartoon style, sterile white screens, gradients, fake status bar text
```

## Core screens

```text
Use case: ui-mockup
Asset type: high-fidelity iPhone core app screen concepts
Primary request: design three portrait mobile screens for ADultingHD showing a cohesive evolved product system: Home, Tasks, and Profile
Scene/backdrop: three iPhone screen canvases side by side on a neutral presentation background
Subject: Home uses a compact due-task dashboard with room/category filter chips, visible XP and streak, and three useful next actions; Tasks uses a compact quest log grouped by room with overdue/due/completed states and fast completion controls; Profile uses a strong avatar hero, level journey, achievements, and household leaderboard
Style/medium: shippable native iOS product UI; editorial game-board influence translated into SwiftUI; tactile badge and stamp details; clean, mature, friendly
Composition/framing: prioritize one main action per screen; dense enough to be useful but calm; consistent navigation and component language
Color palette: ink navy #1F2A44, warm cream #FFF8ED, coral #F46F61, quest gold #E9A23B, sage #59A985, sky #70A7E8, plum #765BC6
Text (verbatim): "Home", "Today’s Quests", "Tasks", "Kitchen", "Laundry", "Profile", "Level 8", "14 day streak"
Constraints: use the exact text only; legible typography; UI must be feasible in SwiftUI; visually distinguish overdue, due, and completed without relying on color alone; no watermark
Avoid: generic analytics dashboard, oversized empty hero cards, glassmorphism, tiny text, cluttered mobile layouts, childish fantasy tropes
```

## Welcome hero

Historical exploration only. The current app-first direction does not render a
literal full-house cutaway or use a glowing line as core navigation; keep this
brief and its exports as provenance for the earlier visual exploration.

```text
Use case: illustration-story
Asset type: reusable full-bleed onboarding hero illustration for an iOS app, no UI and no text
Primary request: a warm cutaway view of a cozy modern house at twilight, where the kitchen, laundry, living room, bedroom, and bathroom each feel like a small approachable quest zone connected by one glowing path
Scene/backdrop: deep ink-navy twilight garden fading into warm cream at the lower edge so an iOS layout can transition naturally into content
Subject: the house and rooms only; tiny task symbols integrated as environmental details such as dishes, laundry basket, folded blanket, sparkle-clean sink, but no people and no mascots
Style/medium: original tactile 2D editorial illustration; confident ink outlines; subtle paper grain; mature playful storybook quality; clean enough for an Apple app
Composition/framing: wide 3:2 illustration, house centered, generous safe margins, strong silhouette, focal path sweeping upward through rooms
Lighting/mood: cozy amber windows, calm encouraging evening, gentle magical glow without fantasy clutter
Color palette: ink navy #1F2A44, warm cream #FFF8ED, coral #F46F61, quest gold #E9A23B, sage #59A985, sky #70A7E8, plum #765BC6
Constraints: no text, no letters, no logos, no interface chrome, no device mockup, no watermark
Avoid: childish cartoon characters, photorealism, generic stock vector art, excessive gradients, floating icons, clutter
```

## Daily loop illustration

```text
Use case: illustration-story
Asset type: reusable onboarding process illustration for an iOS app, no UI and no text
Primary request: a single connected visual story that explains the ADultingHD daily loop: choose a household task, complete the real chore, earn XP and advance
Scene/backdrop: warm cream paper-like field with open edges for flexible cropping
Subject: three compact illustrated moments linked by one sweeping quest-gold path: a hand choosing a task card, hands completing a simple household chore at a sink, and an achievement badge with rising XP spark
Style/medium: original tactile 2D editorial illustration; confident ink outlines; subtle paper grain; mature playful; consistent with a cozy domestic adventure product
Composition/framing: wide horizontal triptych without panel borders, clear left-to-right flow, generous whitespace around each moment
Color palette: ink navy #1F2A44, warm cream #FFF8ED, coral #F46F61, quest gold #E9A23B, sage #59A985, sky #70A7E8, plum #765BC6
Constraints: no text, no numbers, no letters, no logos, no interface chrome, no device mockup, no watermark
Avoid: people’s faces, childish mascots, photorealism, generic stock icons, disconnected clip art, clutter
```
