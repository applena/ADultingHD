#!/bin/zsh
# Generate avatar thumbnails via SD API (Flux model)
# Each image: 512x512, chibi cartoon animal characters with cleaning/household theme

API="http://100.120.88.104:7860/sdapi/v1/txt2img"
OUTDIR="$(dirname "$0")/generated-avatars"

STYLE="chibi cartoon character, bold black outlines, vibrant colors, white background, centered composition, cute kawaii style, game avatar icon, clean digital illustration, simple flat shading"
NEGATIVE="realistic, photographic, 3d render, text, watermark, signature, blurry, deformed, extra limbs, extra fingers, ugly, horror, dark, gritty, nsfw, human"

generate() {
    local name="$1"
    local prompt="$2"
    local outfile="${OUTDIR}/${name}.png"

    echo ">>> Generating: ${name}"

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
    print('    Saved: ${outfile}')
else:
    print('    ERROR: No image in response')
    if 'error' in data:
        print('    ' + data['error'])
"
}

echo "Generating 12 avatar images with Flux model..."
echo "Output: ${OUTDIR}"
echo ""

# 8 base animal characters
generate "01_cat" "an adorable chibi cartoon cat character wearing a tiny apron and holding a feather duster, smiling cheerfully, big expressive eyes, ${STYLE}"
generate "02_dog" "an adorable chibi cartoon golden retriever puppy character wearing rubber gloves and holding a spray bottle, happy eager expression, tongue out, ${STYLE}"
generate "03_bunny" "an adorable chibi cartoon bunny rabbit character wearing a bandana and pushing a tiny mop, determined cute expression, floppy ears, ${STYLE}"
generate "04_bear" "an adorable chibi cartoon bear character wearing a hard hat and carrying a toolbox, confident smile, round body, ${STYLE}"
generate "05_fox" "an adorable chibi cartoon fox character wearing sunglasses and a cape, holding a broom like a superhero staff, smirking cool expression, ${STYLE}"
generate "06_panda" "an adorable chibi cartoon panda character sitting in a laundry basket surrounded by fresh clean clothes, content happy expression, ${STYLE}"
generate "07_unicorn" "an adorable chibi cartoon unicorn character with a sparkly horn, wearing a crown and holding a magic wand that shoots soap bubbles, magical expression, ${STYLE}"
generate "08_dragon" "an adorable chibi cartoon baby dragon character breathing tiny flames to dry dishes on a dish rack, proud expression, small wings, ${STYLE}"

# 4 bonus themed variants
generate "09_cat_chef" "an adorable chibi cartoon cat character wearing a chef hat and apron, holding a spatula and standing next to a frying pan, kitchen setting, ${STYLE}"
generate "10_dog_garden" "an adorable chibi cartoon corgi puppy character wearing a sun hat and gardening gloves, watering flowers with a tiny watering can, ${STYLE}"
generate "11_bunny_sparkle" "an adorable chibi cartoon bunny rabbit character surrounded by sparkles and stars, wearing a wizard hat, holding a magic cleaning wand, enchanted expression, ${STYLE}"
generate "12_fox_trophy" "an adorable chibi cartoon fox character standing on a winner podium holding a golden trophy, wearing a medal, celebratory confetti, victorious expression, ${STYLE}"

echo ""
echo "Done! Generated $(ls -1 ${OUTDIR}/*.png 2>/dev/null | wc -l | tr -d ' ') images in ${OUTDIR}"
