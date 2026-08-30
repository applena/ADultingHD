#!/bin/bash
# Two-simulator CloudKit household sharing smoke test.
#
# Boots two simulators signed into different iCloud accounts, installs the app
# on both, waits for you to create a household share on Simulator A, then fires
# the share URL at Simulator B via xcrun simctl openurl — which triggers iOS's
# native "Join Household?" system sheet and calls userDidAcceptCloudKitShareWith.
#
# Prerequisites: see docs/test-accounts.md
#
# Usage:
#   ./scripts/test-sharing.sh
#
# Override simulator names:
#   SIM_A_NAME="iPhone 15 Pro" SIM_B_NAME="iPhone 17 Pro" ./scripts/test-sharing.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---------------------------------------------------------------------------
# Configuration — override with env vars
# ---------------------------------------------------------------------------

SIM_A_NAME="${SIM_A_NAME:-iPhone 15 Pro}"     # Owner's device — Account 1
SIM_B_NAME="${SIM_B_NAME:-iPhone 17 Pro}"     # Recipient's device — Account 2
BUNDLE_ID="net.shadowpuppet.ADultingHD"
SCHEME="ADultingHD_iOS"
BUILD_DIR="$SCRIPT_DIR/../build/test-sharing"
URL_WAIT_SECS="${URL_WAIT_SECS:-90}"          # How long to wait for the share URL

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '\n→ %s\n' "$*"; }
step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
pause(){ printf '\n\033[2m%s\033[0m' "$1"; read -r _; }

sim_udid() {
    # Return the UDID of the first simulator matching the given name
    xcrun simctl list devices available -j \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
name = sys.argv[1]
for devs in data['devices'].values():
    for d in devs:
        if d['name'] == name:
            print(d['udid']); sys.exit(0)
sys.exit(1)
" "$1" 2>/dev/null
}

sim_state() {
    xcrun simctl list devices available -j \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
udid = sys.argv[1]
for devs in data['devices'].values():
    for d in devs:
        if d['udid'] == udid:
            print(d['state']); sys.exit(0)
print('Unknown')
" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Find simulators
# ---------------------------------------------------------------------------

step "Finding simulators"

UDID_A=$(sim_udid "$SIM_A_NAME") \
    || die "Simulator '$SIM_A_NAME' not found. Run: xcrun simctl list devices available"
UDID_B=$(sim_udid "$SIM_B_NAME") \
    || die "Simulator '$SIM_B_NAME' not found. Run: xcrun simctl list devices available"

[ "$UDID_A" != "$UDID_B" ] \
    || die "SIM_A_NAME and SIM_B_NAME resolved to the same simulator ($UDID_A)"

ok "Simulator A: $SIM_A_NAME ($UDID_A)"
ok "Simulator B: $SIM_B_NAME ($UDID_B)"

# ---------------------------------------------------------------------------
# 2. Build (must be signed — CloudKit entitlements required)
# ---------------------------------------------------------------------------

step "Building $SCHEME (development-signed, Debug)"
mkdir -p "$BUILD_DIR"

xcodebuild build \
    -project ADultingHD.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "platform=iOS Simulator,name=$SIM_A_NAME" \
    DEVELOPMENT_TEAM=TYQ32QCF6K \
    -quiet

APP_PATH=$(find "$BUILD_DIR/DerivedData" \
    -name "ADultingHD.app" -path "*Debug-iphonesimulator*" 2>/dev/null | head -1)
[ -n "$APP_PATH" ] || die "Could not find built .app in $BUILD_DIR/DerivedData"
ok "App: $APP_PATH"

# ---------------------------------------------------------------------------
# 3. Boot simulators
# ---------------------------------------------------------------------------

step "Booting simulators"

if [ "$(sim_state "$UDID_A")" != "Booted" ]; then
    xcrun simctl boot "$UDID_A"
    ok "Booted $SIM_A_NAME"
else
    ok "$SIM_A_NAME already booted"
fi

if [ "$(sim_state "$UDID_B")" != "Booted" ]; then
    xcrun simctl boot "$UDID_B"
    ok "Booted $SIM_B_NAME"
else
    ok "$SIM_B_NAME already booted"
fi

open -a Simulator

# ---------------------------------------------------------------------------
# 4. Install app on both simulators
# ---------------------------------------------------------------------------

step "Installing app"
xcrun simctl install "$UDID_A" "$APP_PATH"
ok "Installed on $SIM_A_NAME"
xcrun simctl install "$UDID_B" "$APP_PATH"
ok "Installed on $SIM_B_NAME"

# ---------------------------------------------------------------------------
# 5. Prompt for iCloud sign-in (one-time setup)
# ---------------------------------------------------------------------------

cat <<SETUP

┌──────────────────────────────────────────────────────────────┐
│  One-time setup: sign into iCloud on both simulators         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Simulator A  ($SIM_A_NAME)                                 │
│    Settings → [your name] → iCloud → sign in                │
│    Use: Account 1 (see docs/test-accounts.md)               │
│                                                              │
│  Simulator B  ($SIM_B_NAME)                                 │
│    Settings → [your name] → iCloud → sign in                │
│    Use: Account 2 (see docs/test-accounts.md)               │
│                                                              │
│  Skip if already signed in.                                  │
└──────────────────────────────────────────────────────────────┘
SETUP

pause "Press enter when both simulators are signed into iCloud... "

# ---------------------------------------------------------------------------
# 6. Launch the app on both simulators
# ---------------------------------------------------------------------------

step "Launching app"
xcrun simctl launch "$UDID_A" "$BUNDLE_ID" > /dev/null
xcrun simctl launch "$UDID_B" "$BUNDLE_ID" > /dev/null
ok "App launched on both simulators"

# ---------------------------------------------------------------------------
# 7. Monitor Simulator A logs for the share URL
# ---------------------------------------------------------------------------

step "Monitoring Simulator A logs for household share URL"

LOGFILE=$(mktemp)
# Stream CloudKit category logs from Simulator A to a temp file in background
xcrun simctl spawn "$UDID_A" log stream \
    --predicate 'subsystem == "net.shadowpuppet.ADultingHD" AND category == "CloudKitSync"' \
    --level info > "$LOGFILE" 2>/dev/null &
LOG_PID=$!
trap 'kill "$LOG_PID" 2>/dev/null; rm -f "$LOGFILE"' EXIT

cat <<INSTRUCTIONS

On Simulator A ($SIM_A_NAME):
  1. Complete onboarding (or go to Settings if already set up)
  2. Tap "Household" → "Invite Someone" (or the invite button in onboarding)
  3. The share URL will be captured automatically from logs

Waiting up to ${URL_WAIT_SECS}s for the share URL…
INSTRUCTIONS

SHARE_URL=""
for (( i=0; i<URL_WAIT_SECS; i++ )); do
    if grep -qo 'https://www\.icloud\.com/share/[^ ]*' "$LOGFILE" 2>/dev/null; then
        SHARE_URL=$(grep -o 'https://www\.icloud\.com/share/[^ ]*' "$LOGFILE" | tail -1)
        break
    fi
    printf '\r  Waiting… %ds elapsed' "$i"
    sleep 1
done
printf '\n'

if [ -z "$SHARE_URL" ]; then
    warn "Share URL not detected in logs after ${URL_WAIT_SECS}s."
    warn "Check Xcode → Window → Devices and Simulators → Simulator A logs for a line like:"
    warn "  ☁️ Created household share: https://www.icloud.com/share/..."
    printf '\n'
    read -rp "Paste the share URL manually: " SHARE_URL
fi

[ -n "$SHARE_URL" ] || die "No share URL provided — cannot continue"
ok "Share URL: $SHARE_URL"

# ---------------------------------------------------------------------------
# 8. Trigger acceptance on Simulator B
# ---------------------------------------------------------------------------

step "Opening share URL on Simulator B ($SIM_B_NAME)"
xcrun simctl openurl "$UDID_B" "$SHARE_URL"

cat <<VERIFY

✅ Share URL sent to Simulator B.

Expected behaviour on Simulator B:
  • iOS shows the native "Join Household?" system sheet
  • Tap "Join" — the app opens and registers the shared household
  • Both simulators should now show the same tasks and member profiles

If Simulator B shows "Get the latest app from the App Store" instead:
  • The Development CloudKit schema is missing the cloudkit.share type
  • Run: CLOUDKIT_INTEGRATION_TESTS=1 xcodebuild test … -only-testing .../CloudKitIntegrationTests
  • See docs/cloudkit-sharing.md → "App Store Connect submission gate"

If Safari opens instead of the sharing sheet:
  • iOS may need a moment to recognise the installed app — retry in 10s
  • Or try pasting the URL directly in the Simulator B's Safari address bar

VERIFY
