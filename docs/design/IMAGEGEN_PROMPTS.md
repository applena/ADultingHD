# Runtime ImageGen prompt log

All raster artwork shipped in `ADultingHD/App/Assets.xcassets/` was regenerated
on 2026-08-30 with Codex's built-in ImageGen tool. The generations used text-only
prompts and no repository image as a reference or edit target. The production
files are the reviewed outputs (with app-icon and avatar size normalization).

## Shared avatar direction

Each avatar prompt below was combined with this direction:

```text
original full-body character asset for a cozy domestic-adventure iOS/macOS app;
square 1:1 composition; warm cream-white background; soft peach ground shadow;
confident dark ink outline; tactile 2D editorial illustration; mature playful
Apple-platform product art; simple flat shading; centered with generous safe
margins; clean readable silhouette at small avatar sizes; no text, no letters,
no numbers, no logo, no watermark, no UI, no frame; avoid photorealism, 3D
render, generic stock art, clutter, cropped character, extra limbs, extra
fingers
```

## App icon

```text
Use case: logo-brand
Asset type: square 1024x1024 iOS and macOS app icon artwork
Primary request: an original, instantly readable icon for ADultingHD, a cozy household-task adventure app; show a simple friendly checklist sheet with three check marks, a small warm house roof behind it, and one quest-gold sparkle
Scene/backdrop: solid warm cream background, full square composition designed to survive Apple's rounded icon mask
Style/medium: polished tactile 2D editorial illustration, bold deep ink-navy outline, simple flat shapes, subtle paper grain, mature playful Apple-platform app icon
Composition/framing: centered, strong silhouette, generous margin, no tiny details
Lighting/mood: bright, encouraging, clean
Color palette: deep ink navy #143359, warm cream #FFF8ED, coral #FA7373, quest gold #F09329, leaf green #3D6E4A
Constraints: no readable text, no letters, no numbers, no logos, no watermark, no gradients, no UI screenshot, no device frame
Avoid: photorealism, 3D render, clutter, thin lines, generic stock icon, trademarked imagery
```

## Onboarding artwork

The three `WelcomeHeroV1` files use the same welcoming-home request with
orientation-specific framing: compact 4:3, iPad 3:2, and wide 2:1. The iPad
variant shows a small inviting home with kitchen, laundry nook, living area,
and bedroom details; the compact and wide variants use the same subject with
their protected crop margins.

`SharedHouseholdV1` shows three simplified household members cooperating on
dishes, laundry, and recycling in a warm home, connected by a gentle gold path.
`ManageableSuggestionsV1` shows a kitchen counter with dishes, a folded towel,
and a houseplant as three approachable chores. `XPStreaksV1` shows a clean sink,
folded towel, physical progress markers, and a gold star reward. All four scenes
use the following constraints:

```text
tactile 2D editorial illustration; confident deep ink outlines; subtle paper
grain; mature playful Apple-platform product art; warm cream, ink navy, coral,
quest gold, leaf green, sky blue, and plum palette; no text, no letters, no
numbers, no logos, no buttons, no interface chrome, no device frame, no
watermark; avoid photorealism, childish mascots, generic stock vector art, and
excessive tiny details
```

The art intentionally leaves all onboarding copy, controls, and accessibility
descriptions to SwiftUI.

## Avatar subjects

The asset-specific prompt records are:

- `raccoon`: coral utility apron and folded cleaning cloth.
- `turtle`: stack of folded towels on its shell.
- `otter`: sparkling dish brush.
- `capybara`: soft-yellow bandana and small houseplant.
- `cat`: coral apron and feather duster.
- `dog`: rubber cleaning gloves and spray bottle.
- `bunny`: coral bandana and tiny mop.
- `bear`: warm-yellow hard hat and toolbox.
- `fox`: blue sunglasses, coral cape, and broom.
- `panda`: tidy laundry basket and folded clothes.
- `unicorn`: softly sparkling horn, gold crown, wand, and soap bubbles.
- `dragon`: tiny warm breath drying dishes on a rack.
- `cat_chef`: chef hat, apron, golden spatula, and frying pan.
- `cat_ninja`: charcoal ninja outfit, coral headband, and star-shaped discs.
- `dog_firefighter`: red helmet, coat, and hose with a clean arc of water.
- `dog_astronaut`: white space suit and clear helmet among simple stars.
- `bunny_gardener`: overalls, straw hat, watering can, and blooming flowers.
- `bunny_wizard`: deep-blue star hat, plum robe, and crystal staff.
- `bear_lumberjack`: red plaid shirt, green suspenders, knit cap, axe, and firewood.
- `bear_knight`: silver armor, plumed helmet, rounded shield, and star sword.
- `fox_detective`: navy coat, brown deerstalker, magnifying glass, and blank clue card.
- `fox_pirate`: navy tricorn, coral sash, brass compass, cutlass, and tiny chest.
- `panda_sensei`: sage martial-arts robe, plum sash, and blank scroll.
- `panda_emperor`: plum-and-gold robe, ornate crown, and rounded scepter.
- `unicorn_fairy`: pastel wings, flower crown, gold wand, leaves, and sparkles.
- `unicorn_rockstar`: plum jacket, star glasses, and coral electric guitar.
- `dragon_king`: gold crown, plum cape, friendly armor, and rounded scepter.
- `dragon_mecha`: original orange-and-navy mecha armor with cyan accents and a harmless energy tool.

The catalog's `person` starter remains an emoji rendered by SwiftUI and has no
raster asset.
