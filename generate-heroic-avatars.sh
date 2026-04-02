#!/bin/zsh
# Generate HEROIC avatar variants - fully decked out, pre-composed, highest tier unlocks
# These are complete character illustrations with themed equipment - no emoji overlay needed

API="http://100.120.88.104:7860/sdapi/v1/txt2img"
OUTDIR="$(dirname "$0")/generated-avatars/heroic"
mkdir -p "$OUTDIR"
NEGATIVE="realistic, photographic, 3d render, text, watermark, signature, blurry, deformed, extra limbs, extra fingers, ugly, horror, dark, gritty, nsfw, human"

generate() {
    local name="$1"
    local prompt="$2"
    local outfile="${OUTDIR}/${name}.png"

    if [[ -f "$outfile" ]]; then
        echo "    SKIP (exists): heroic/${name}"
        return
    fi

    echo ">>> Generating: heroic/${name}"

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
    print('    OK: heroic/${name}')
else:
    print('    ERROR: No image')
"
}

HEROIC="chibi cartoon character, epic heroic design, rich vibrant colors, magical glow aura and sparkle effects, dynamic pose, white background, centered, cute kawaii style, masterful digital illustration, bold outlines, game avatar icon, premium legendary quality"

echo "============================================="
echo "  HEROIC AVATAR VARIANTS"
echo "  Fully composed, ultimate tier unlocks"
echo "============================================="
echo ""

# ─── Each animal gets a themed heroic version ────────────────────────

# Cat heroics
generate "cat_ninja" \
    "an adorable chibi cartoon cat ninja warrior, wearing a black ninja outfit with a red headband, holding shurikens shaped like stars, stealthy action pose, smoke wisps around feet, ${HEROIC}"

generate "cat_chef" \
    "an adorable chibi cartoon cat master chef, wearing a tall white chef hat and double-breasted chef coat, holding a golden spatula and flaming frying pan, kitchen sparkles, ${HEROIC}"

# Dog heroics
generate "dog_firefighter" \
    "an adorable chibi cartoon golden retriever firefighter hero, wearing a red firefighter helmet and coat with reflective stripes, holding a fire hose spraying water, brave heroic stance, ${HEROIC}"

generate "dog_astronaut" \
    "an adorable chibi cartoon golden retriever astronaut, wearing a white space suit with a glass helmet, floating among stars and planets, cosmic sparkle trail, ${HEROIC}"

# Bunny heroics
generate "bunny_wizard" \
    "an adorable chibi cartoon bunny rabbit wizard, wearing a tall blue wizard hat with golden stars and a flowing magical robe, casting a sparkle cleaning spell from a crystal staff, magical runes floating around, ${HEROIC}"

generate "bunny_gardener" \
    "an adorable chibi cartoon bunny rabbit master gardener, wearing overalls and a straw hat, surrounded by blooming magical flowers and butterflies, holding an enchanted golden watering can that pours sparkles, ${HEROIC}"

# Bear heroics
generate "bear_knight" \
    "an adorable chibi cartoon bear knight in shining silver armor, wearing a plumed helmet, holding a shield with a star emblem and a gleaming sword, heroic champion pose, ${HEROIC}"

generate "bear_lumberjack" \
    "an adorable chibi cartoon bear lumberjack, wearing a red plaid flannel shirt and suspenders, holding a massive golden axe over shoulder, stack of perfectly chopped wood behind, rugged heroic pose, ${HEROIC}"

# Fox heroics
generate "fox_pirate" \
    "an adorable chibi cartoon fox pirate captain, wearing a fancy tricorn hat with a golden feather, eye patch, holding a treasure map and standing on a pile of gold coins, confident swashbuckler pose, ${HEROIC}"

generate "fox_detective" \
    "an adorable chibi cartoon fox detective, wearing a deerstalker hat and trench coat, holding a magnifying glass with a gleaming lens, mysterious fog and clue sparkles, clever investigator pose, ${HEROIC}"

# Panda heroics
generate "panda_sensei" \
    "an adorable chibi cartoon panda kung fu master sensei, wearing a traditional gi with a black belt, striking a martial arts pose, zen aura with floating cherry blossoms and bamboo, wise powerful expression, ${HEROIC}"

generate "panda_emperor" \
    "an adorable chibi cartoon panda emperor, wearing magnificent golden imperial robes and a jade crown, holding a royal scepter, sitting on a throne made of bamboo and gold, imperial majesty, ${HEROIC}"

# Unicorn heroics
generate "unicorn_fairy" \
    "an adorable chibi cartoon unicorn fairy princess, with crystalline butterfly wings, wearing a flowing rainbow gown and diamond tiara, surrounded by floating crystals and rainbow aurora, casting prismatic light spells, ${HEROIC}"

generate "unicorn_rockstar" \
    "an adorable chibi cartoon unicorn rockstar, wearing studded leather jacket and star sunglasses, playing a rainbow electric guitar with lightning sparks flying, concert stage lights and speakers, ${HEROIC}"

# Dragon heroics
generate "dragon_king" \
    "an adorable chibi cartoon dragon king supreme ruler, wearing magnificent golden crown with enormous gems, sitting on a throne of treasure and crystals, wings spread wide, breathing rainbow fire, surrounded by floating gold coins and magical orbs, ultimate legendary majesty, ${HEROIC}"

generate "dragon_mecha" \
    "an adorable chibi cartoon dragon in a mecha robot suit, high-tech golden armor with glowing blue energy lines, jet boosters on back, laser cannon arm, holographic display visor, futuristic particles and sparks, ultimate sci-fi legendary warrior, ${HEROIC}"

echo ""
echo "============================================="
total=$(ls -1 ${OUTDIR}/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "  COMPLETE: ${total} heroic variants generated"
echo "============================================="
