#!/bin/zsh
# Generate ALL avatar item images via SD API (Flux model)
# Visual complexity scales with item cost/rarity

API="http://100.120.88.104:7860/sdapi/v1/txt2img"
OUTDIR="$(dirname "$0")/generated-avatars"
NEGATIVE="realistic, photographic, 3d render, text, watermark, signature, blurry, deformed, extra limbs, extra fingers, ugly, horror, dark, gritty, nsfw, human"

generate() {
    local subdir="$1"
    local name="$2"
    local prompt="$3"
    local outfile="${OUTDIR}/${subdir}/${name}.png"

    if [[ -f "$outfile" ]]; then
        echo "    SKIP (exists): ${subdir}/${name}"
        return
    fi

    echo ">>> Generating: ${subdir}/${name}"

    response=$(curl -s -X POST "${API}" \
        -H "Content-Type: application/json" \
        -d "{
            \"prompt\": \"${prompt}\",
            \"negative_prompt\": \"${NEGATIVE}\",
            \"steps\": 20,
            \"cfg_scale\": 1.0,
            \"distilled_cfg_scale\": 3.5,
            \"width\": 512,
            \"height\": 512,
            \"sampler_name\": \"Euler\",
            \"scheduler\": \"Beta\",
            \"seed\": -1,
            \"batch_size\": 1,
            \"n_iter\": 1
        }")

    echo "${response}" | python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
if 'images' in data and len(data['images']) > 0:
    img_data = base64.b64decode(data['images'][0])
    with open('${outfile}', 'wb') as f:
        f.write(img_data)
    print('    OK: ${subdir}/${name}')
else:
    print('    ERROR: No image in response')
    if 'error' in data:
        print('    ' + str(data.get('error','')))
"
}

echo "============================================="
echo "  ADultingHD Avatar Generation - Full Set"
echo "  Cost -> Visual Complexity Scaling"
echo "============================================="
echo ""

# ─── STYLE TIERS ─────────────────────────────────────────────────────
# Cheap/free items: minimal, clean, simple shapes
TIER_FREE="chibi cartoon character, simple clean design, minimal details, soft colors, white background, centered, cute kawaii style, game avatar icon, clean digital illustration, flat shading, bold outlines"
# Low cost items: some personality, slight detail
TIER_LOW="chibi cartoon character, charming design, some detail, warm colors, white background, centered, cute kawaii style, game avatar icon, clean digital illustration, simple shading, bold outlines"
# Mid cost items: more detail, props, personality
TIER_MID="chibi cartoon character, detailed design, vibrant colors, subtle sparkle effects, white background, centered, cute kawaii style, game avatar icon, clean digital illustration, soft shading, bold outlines"
# High cost items: premium look, rich detail, glow effects
TIER_HIGH="chibi cartoon character, highly detailed premium design, rich vibrant colors, sparkle and glow effects, white background, centered, cute kawaii style, game avatar icon, polished digital illustration, dynamic shading, bold outlines"
# Legendary items: epic, fully equipped, maximum visual richness
TIER_EPIC="chibi cartoon character, epic legendary design, stunning rich colors, magical glow aura and particle effects, dramatic lighting, white background, centered, cute kawaii style, game avatar icon, masterful digital illustration, dynamic dramatic shading, bold outlines"

# ─── ITEM STYLE TIERS (for accessories/hats/etc) ────────────────────
ITEM_CHEAP="clean simple icon illustration, minimal design, flat colors, white background, centered, bold outlines, game item icon"
ITEM_MID="detailed icon illustration, warm vibrant colors, subtle shading, white background, centered, bold outlines, game item icon, slight sparkle"
ITEM_PRICEY="premium icon illustration, rich colors, glow effect, polished shading, white background, centered, bold outlines, game item icon, sparkle details"
ITEM_LEGENDARY="epic legendary icon illustration, rich saturated colors, golden glow aura, dramatic lighting, white background, centered, bold outlines, premium game item icon, particle effects"

# ═══════════════════════════════════════════════════════════════════════
echo "▸ BASE CHARACTERS (8)"
echo "  Free->simple ... Legendary->epic"
echo ""
# ═══════════════════════════════════════════════════════════════════════

# Cat - FREE (0 coins) - Default avatar. Simple, clean, welcoming.
generate "base" "cat" \
    "an adorable simple chibi cartoon cat, sitting upright, soft orange tabby, big round eyes, gentle smile, minimal details, no accessories, no props, ${TIER_FREE}"

# Dog - 200 coins - Friendly, slightly more personality
generate "base" "dog" \
    "an adorable chibi cartoon golden retriever puppy, sitting happily, tongue out, wagging tail, friendly warm expression, one small collar, ${TIER_LOW}"

# Bunny - 200 coins - Cute, bit of character
generate "base" "bunny" \
    "an adorable chibi cartoon bunny rabbit, soft white and pink, long floppy ears, holding a small carrot, sweet curious expression, ${TIER_LOW}"

# Bear - 300 coins - Sturdy, a prop or two
generate "base" "bear" \
    "an adorable chibi cartoon brown bear, round and sturdy, wearing a small vest, holding a honey pot, warm confident smile, ${TIER_MID}"

# Fox - 300 coins - Cool, stylish
generate "base" "fox" \
    "an adorable chibi cartoon fox, sleek orange and white fur, wearing a tiny bandana, clever smirk, bushy tail swishing, stylish pose, ${TIER_MID}"

# Panda - 400 coins, L5 - More detailed, bamboo theme
generate "base" "panda" \
    "an adorable chibi cartoon panda, black and white, wearing a bamboo leaf hat, holding bamboo stalk, sitting cross-legged, serene happy expression, cherry blossoms floating around, ${TIER_HIGH}"

# Unicorn - 500 coins, L10 - Magical, sparkly, premium
generate "base" "unicorn" \
    "an adorable chibi cartoon unicorn, white body with pastel rainbow mane, glowing golden horn, wearing a small tiara, surrounded by floating stars and sparkles, magical aura, majestic cute expression, ${TIER_HIGH}"

# Dragon - 1000 coins, L20 - EPIC, fully equipped, maximum detail
generate "base" "dragon" \
    "an adorable chibi cartoon baby dragon, deep red scales with golden belly, wearing tiny golden armor and a royal cape, breathing rainbow fire, holding a legendary sword, surrounded by floating treasure coins and gems, glowing magical aura, epic legendary heroic pose, ${TIER_EPIC}"

# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "▸ HATS (10)"
echo ""
# ═══════════════════════════════════════════════════════════════════════

generate "hat" "party_hat" \
    "a cute colorful cone party hat with polka dots and a pom-pom on top, festive streamers, ${ITEM_CHEAP}"

generate "hat" "baseball_cap" \
    "a sporty baseball cap, blue and white, slightly tilted, casual cool style, ${ITEM_CHEAP}"

generate "hat" "cowboy" \
    "a classic brown leather cowboy hat with a small star badge on the band, western style, ${ITEM_MID}"

generate "hat" "helmet" \
    "a bright yellow hard hat safety helmet, construction worker style, shiny surface, ${ITEM_MID}"

generate "hat" "ribbon" \
    "a cute pink satin hair ribbon bow, delicate and feminine, simple elegant design, ${ITEM_CHEAP}"

generate "hat" "flower_crown" \
    "a beautiful flower crown wreath made of colorful daisies and small roses, spring vibes, ${ITEM_MID}"

generate "hat" "top_hat" \
    "a fancy black top hat with a satin band and small buckle, elegant gentleman style, slight shine, ${ITEM_MID}"

generate "hat" "grad_cap" \
    "a dark blue graduation cap mortarboard with gold tassel hanging to the side, academic achievement, ${ITEM_MID}"

generate "hat" "wizard_hat" \
    "a tall purple wizard hat with golden stars and crescent moons embroidered on it, mystical glow, magical aura, ${ITEM_PRICEY}"

generate "hat" "crown" \
    "a magnificent golden royal crown studded with rubies emeralds and sapphires, velvet interior, radiant golden glow, regal and precious, ${ITEM_LEGENDARY}"

# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "▸ GLASSES (5)"
echo ""
# ═══════════════════════════════════════════════════════════════════════

generate "glasses" "nerd_glasses" \
    "a pair of round thick-rimmed nerdy glasses, black frames, slightly oversized, intellectual cute style, ${ITEM_CHEAP}"

generate "glasses" "sunglasses" \
    "a pair of cool dark aviator sunglasses, reflective lenses with a slight blue tint, sleek modern style, ${ITEM_CHEAP}"

generate "glasses" "heart_eyes" \
    "a pair of fun heart-shaped glasses with pink lenses, cute valentine style, sparkle on lenses, ${ITEM_MID}"

generate "glasses" "monocle" \
    "a distinguished golden monocle with a thin chain, elegant vintage style, slight gleam on lens, ${ITEM_MID}"

generate "glasses" "star_eyes" \
    "a pair of star-shaped glasses with golden glittery frames and rainbow holographic lenses, dazzling sparkle effects, ${ITEM_PRICEY}"

# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "▸ ACCESSORIES (9)"
echo ""
# ═══════════════════════════════════════════════════════════════════════

generate "accessory" "scarf" \
    "a cozy knitted red and white striped scarf, soft woolen texture, casual warm feel, ${ITEM_CHEAP}"

generate "accessory" "rubber_gloves" \
    "a pair of bright yellow rubber cleaning gloves, shiny surface, household cleaning theme, ${ITEM_CHEAP}"

generate "accessory" "spray_bottle" \
    "a blue and white spray bottle cleaner, squirt of mist coming out, household cleaning supply, ${ITEM_CHEAP}"

generate "accessory" "soap_bubbles" \
    "a cluster of iridescent floating soap bubbles, rainbow reflections on each bubble, dreamy and clean, ${ITEM_MID}"

generate "accessory" "broom" \
    "a classic wooden broom with straw bristles, household cleaning tool, slight magical sparkle around it, ${ITEM_MID}"

generate "accessory" "sparkle_wand" \
    "a magical sparkle wand with a glowing star tip, trailing sparkle dust and tiny stars, enchanted cleaning tool, ${ITEM_MID}"

generate "accessory" "medal" \
    "a shiny golden medal on a red white and blue ribbon, achievement award, gleaming surface, ${ITEM_MID}"

generate "accessory" "cape" \
    "a flowing superhero cape, deep red with golden trim, dramatic billowing fabric, heroic epic feel, ${ITEM_PRICEY}"

generate "accessory" "trophy" \
    "a magnificent golden trophy cup on a marble base, engraved details, radiant golden glow, champion award, confetti particles, ${ITEM_LEGENDARY}"

# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "▸ BACKGROUNDS (6)"
echo ""
# ═══════════════════════════════════════════════════════════════════════

generate "background" "bg_stars" \
    "a circular badge background filled with cute yellow stars on a soft blue gradient, simple pattern, game UI element, clean icon design, bold outlines"

generate "background" "bg_clean" \
    "a circular badge background with floating iridescent soap bubbles on a soft cyan gradient, clean fresh feeling, game UI element, clean icon design"

generate "background" "bg_hearts" \
    "a circular badge background filled with pink and red hearts of various sizes on a soft pink gradient, romantic cute pattern, game UI element, clean icon design"

generate "background" "bg_sparkle" \
    "a circular badge background with golden sparkles and shooting stars on a deep purple gradient, magical shimmer, game UI element, polished icon design"

generate "background" "bg_rainbow" \
    "a circular badge background with a vibrant rainbow arc and fluffy clouds on a sky blue gradient, colorful cheerful, game UI element, rich detailed icon design"

generate "background" "bg_fire" \
    "a circular badge background with dramatic flames and embers on a dark gradient, intense orange and red fire, epic energy aura, game UI element, premium icon design, dramatic lighting"

echo ""
echo "============================================="
total=$(find "${OUTDIR}" -name "*.png" -not -path "*/.*" | wc -l | tr -d ' ')
echo "  COMPLETE: ${total} images generated"
echo "  Output: ${OUTDIR}/"
echo "============================================="
