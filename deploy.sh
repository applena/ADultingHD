#!/bin/bash
set -euo pipefail

# ADultingHD - Local TestFlight Deploy
# Usage: ./deploy.sh [--skip-tests] [--no-bump] [--export-only] [--macos] [--ios] [--all]
# Default (no platform flag): iOS only
# --no-bump: use the next App Store Connect build number without changing Git
# --export-only: archive, sign, and verify, but do not upload (implies --no-bump)
# --macos: macOS only
# --all: both iOS and macOS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

DEPLOY_REMOTE="${DEPLOY_REMOTE:-origin}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"

verify_deploy_checkout() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "❌ Deploy must run from a Git worktree."
        exit 1
    fi

    REPO_ROOT=$(git rev-parse --show-toplevel)
    if [ "$REPO_ROOT" != "$SCRIPT_DIR" ]; then
        echo "❌ Deploy script is not running from the repository root."
        echo "   Script: $SCRIPT_DIR"
        echo "   Git root: $REPO_ROOT"
        exit 1
    fi

    CURRENT_BRANCH=$(git symbolic-ref --quiet --short HEAD || true)
    # Only DEPLOY_BRANCH may upload; an export-only run uploads nothing, so it
    # may validate signing from any branch.
    if $EXPORT_ONLY && [ -n "$CURRENT_BRANCH" ]; then
        DEPLOY_BRANCH="$CURRENT_BRANCH"
    fi
    if [ "$CURRENT_BRANCH" != "$DEPLOY_BRANCH" ]; then
        echo "❌ TestFlight deploys must run from '$DEPLOY_BRANCH' (current: '${CURRENT_BRANCH:-detached HEAD}')."
        exit 1
    fi

    if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
        echo "❌ Refusing to deploy a dirty worktree. Commit, stash, or remove local changes first:"
        git status --short
        exit 1
    fi

    echo "🔄 Checking $DEPLOY_REMOTE/$DEPLOY_BRANCH for newer commits..."
    git fetch --quiet "$DEPLOY_REMOTE" "$DEPLOY_BRANCH"

    SOURCE_SHA=$(git rev-parse HEAD)
    REMOTE_SHA=$(git rev-parse "$DEPLOY_REMOTE/$DEPLOY_BRANCH")
    if [ "$SOURCE_SHA" != "$REMOTE_SHA" ]; then
        COUNTS=$(git rev-list --left-right --count "$SOURCE_SHA...$REMOTE_SHA")
        AHEAD=$(echo "$COUNTS" | awk '{print $1}')
        BEHIND=$(echo "$COUNTS" | awk '{print $2}')
        echo "❌ Refusing to deploy because local $DEPLOY_BRANCH does not exactly match $DEPLOY_REMOTE/$DEPLOY_BRANCH."
        echo "   Local:  $SOURCE_SHA"
        echo "   Remote: $REMOTE_SHA"
        echo "   Ahead: $AHEAD, behind: $BEHIND"
        exit 1
    fi

    echo "✅ Deploy source: $SOURCE_SHA ($DEPLOY_REMOTE/$DEPLOY_BRANCH)"
}

verify_delivery_processing() {
    local platform="$1"
    local delivery_id="$2"
    local status_log="$BUILD_DIR/${platform}_processing_status.json"

    echo "⏳ Waiting for Apple to finish processing $platform delivery $delivery_id..."
    if ! xcrun altool --build-status \
        --delivery-id "$delivery_id" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" \
        --output-format json 2>&1 | tee "$status_log"; then
        echo "❌ Apple build processing check failed"
        exit 1
    fi

    if ! grep -Eq '"build-status"[[:space:]]*:[[:space:]]*"VALID"' "$status_log"; then
        echo "❌ Apple did not report a valid App Store Connect build"
        exit 1
    fi

    # Xcode 26.3's altool output contains only delivery-uuid + build-status;
    # other versions also include is-on-app-store-connect. Treat an omitted
    # optional field as compatible, but fail closed if Apple explicitly reports
    # that the valid delivery is not on App Store Connect.
    if grep -q '"is-on-app-store-connect"' "$status_log" \
        && ! grep -Eq '"is-on-app-store-connect"[[:space:]]*:[[:space:]]*true' "$status_log"; then
        echo "❌ Apple processed the delivery but did not place it on App Store Connect"
        exit 1
    fi

    echo "✅ Apple processed $platform delivery $delivery_id successfully"
}

if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "❌ .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

KEY_PATH="$APPSTORE_API_PRIVATE_KEY_PATH"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ API key not found at: $KEY_PATH"
    exit 1
fi

mkdir -p ~/.private_keys
KEY_FILENAME="AuthKey_${APPSTORE_API_KEY_ID}.p8"
if [ ! -f ~/.private_keys/"$KEY_FILENAME" ]; then
    ln -sf "$KEY_PATH" ~/.private_keys/"$KEY_FILENAME"
    echo "🔑 Symlinked API key to ~/.private_keys/"
fi

PROJECT="ADultingHD.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build"
TEST_DERIVED_DATA="$BUILD_DIR/test"

# Parse flags
SKIP_TESTS=false
NO_BUMP=false
EXPORT_ONLY=false
BUILD_IOS=false
BUILD_MACOS=false
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        --no-bump) NO_BUMP=true ;;
        --export-only) EXPORT_ONLY=true; NO_BUMP=true ;;
        --macos) BUILD_MACOS=true ;;
        --ios) BUILD_IOS=true ;;
        --all) BUILD_IOS=true; BUILD_MACOS=true ;;
        *)
            echo "❌ Unknown argument: $arg"
            exit 1
            ;;
    esac
done
# Default to iOS if no platform specified
if ! $BUILD_IOS && ! $BUILD_MACOS; then
    BUILD_IOS=true
fi

verify_deploy_checkout

# Query App Store Connect for the highest uploaded build number. CI uses this
# as the source of truth so serialized main-branch deploys never reuse a build
# number, even though CI intentionally does not write build-bump commits back to
# the repository. ES256 signing uses only openssl + Python's standard library.
fetch_remote_build() {
    BUNDLE_ID="$1" KEY_ID="$APPSTORE_API_KEY_ID" \
    ISSUER="$APPSTORE_ISSUER_ID" KEY_PATH_ENV="$KEY_PATH" \
    python3 - <<'PYEOF'
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


try:
    now = int(time.time())
    header = b64url(json.dumps({
        'alg': 'ES256',
        'kid': os.environ['KEY_ID'],
        'typ': 'JWT',
    }, separators=(',', ':')).encode())
    claims = b64url(json.dumps({
        'iss': os.environ['ISSUER'],
        'iat': now,
        'exp': now + 1200,
        'aud': 'appstoreconnect-v1',
    }, separators=(',', ':')).encode())
    signing_input = header + b'.' + claims

    der = subprocess.run(
        ['openssl', 'dgst', '-sha256', '-sign', os.environ['KEY_PATH_ENV']],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout

    # Convert the DER ECDSA signature to the JOSE r||s representation.
    if not der or der[0] != 0x30:
        raise ValueError('unexpected ECDSA signature')
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    r_length = der[index + 1]
    r = der[index + 2:index + 2 + r_length]
    index += 2 + r_length
    s_length = der[index + 1]
    s = der[index + 2:index + 2 + s_length]
    raw_signature = r.lstrip(b'\x00').rjust(32, b'\x00') + s.lstrip(b'\x00').rjust(32, b'\x00')
    token = (signing_input + b'.' + b64url(raw_signature)).decode()

    def get(path, query):
        url = 'https://api.appstoreconnect.apple.com' + path + '?' + urllib.parse.urlencode(query, safe=',')
        request = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)

    apps = get('/v1/apps', {'filter[bundleId]': os.environ['BUNDLE_ID']}).get('data', [])
    if not apps:
        raise RuntimeError('bundle ID is not registered in App Store Connect')

    builds = get('/v1/builds', {
        'filter[app]': apps[0]['id'],
        'sort': '-uploadedDate',
        'limit': '200',
    }).get('data', [])
    versions = [
        int(build['attributes']['version'])
        for build in builds
        if build.get('attributes', {}).get('version', '').isdigit()
    ]
    print(max(versions) if versions else 0)
except Exception as error:
    print(f'❌ App Store Connect build lookup failed: {error}', file=sys.stderr)
    sys.exit(1)
PYEOF
}

LOCAL_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
if ! [[ "$LOCAL_BUILD" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid CURRENT_PROJECT_VERSION in project.yml: $LOCAL_BUILD"
    exit 1
fi

echo "🔍 Checking TestFlight for the highest existing build..."
REMOTE_BUILD=$(fetch_remote_build "net.shadowpuppet.ADultingHD")
if ! [[ "$REMOTE_BUILD" =~ ^[0-9]+$ ]]; then
    echo "❌ App Store Connect returned an invalid build number: $REMOTE_BUILD"
    exit 1
fi

CURRENT_BUILD=$LOCAL_BUILD
if [ "$REMOTE_BUILD" -gt "$CURRENT_BUILD" ]; then
    CURRENT_BUILD=$REMOTE_BUILD
    echo "ℹ️  TestFlight is ahead of project.yml ($REMOTE_BUILD vs. $LOCAL_BUILD)."
fi
NEW_BUILD=$((CURRENT_BUILD + 1))

if $NO_BUMP; then
    echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD (--no-bump; repository remains unchanged)"
else
    ORIG_PROJECT_YML=$(mktemp)
    ORIG_PBXPROJ=$(mktemp)
    cp project.yml "$ORIG_PROJECT_YML"
    cp "$PROJECT/project.pbxproj" "$ORIG_PBXPROJ"

    echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
    /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${LOCAL_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

    DEPLOY_SUCCESS=false
    rollback_build_bump() {
        if [ "$DEPLOY_SUCCESS" = "false" ]; then
            echo "↩️  Rolling back build number bump (deploy did not complete)..."
            cp "$ORIG_PROJECT_YML" project.yml 2>/dev/null || true
            cp "$ORIG_PBXPROJ" "$PROJECT/project.pbxproj" 2>/dev/null || true
        fi
        rm -f "$ORIG_PROJECT_YML" "$ORIG_PBXPROJ"
    }
    trap rollback_build_bump EXIT
fi

echo "⚙️  Regenerating Xcode project..."
xcodegen generate

if ! $SKIP_TESTS; then
    echo "🧪 Running unit tests..."
    DESTINATION=$(
        if xcrun simctl list devices available | grep -q "iPhone 17 Pro"; then
            echo "platform=iOS Simulator,name=iPhone 17 Pro"
        elif xcrun simctl list devices available | grep -q "iPhone 17"; then
            echo "platform=iOS Simulator,name=iPhone 17"
        elif xcrun simctl list devices available | grep -q "iPhone 16"; then
            echo "platform=iOS Simulator,name=iPhone 16"
        else
            echo "platform=iOS Simulator,name=iPhone 15"
        fi
    )
    # Keep the deploy gate focused on deterministic unit coverage. UI tests
    # remain available through the scheme, but Xcode 26 emits a repeated
    # IDELaunchParametersSnapshot/LLDB diagnostic for every UI app launch even
    # when the tests pass. Use a checkout-local derived-data path so deploys do
    # not contend with another xcodebuild invocation's test database.
    xcodebuild test \
        -project "$PROJECT" \
        -scheme ADultingHD_iOS \
        -destination "$DESTINATION" \
        -configuration Debug \
        -derivedDataPath "$TEST_DERIVED_DATA" \
        -only-testing:ADultingHDTests_iOS \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
    echo "✅ Tests passed"
fi

rm -rf "$BUILD_DIR"

mkdir -p "$BUILD_DIR"

# --- Shared signing pipeline ---
#
# Both platforms follow the same path, because the App Store Connect API key
# only has Upload scope, not Admin/Profile-Management scope, and CI runners
# have no signing certificates:
#
#   1. Archive unsigned (CODE_SIGNING_ALLOWED=NO). An upload-scope key cannot
#      auto-register capabilities via `-allowProvisioningUpdates` during
#      archive, so any capability mismatch (App Groups, Push, iCloud) would
#      fail a signed archive outright.
#   2. Seed the archived app with the concrete production entitlements, using
#      a local identity when available or an ad-hoc signature otherwise. The
#      seed signature never reaches TestFlight. Skipping it leaves the export
#      with only a minimal entitlements dict, which makes
#      CKContainer(identifier:) trap at runtime.
#   3. `-exportArchive` re-signs with the Apple Distribution authority via
#      cloud-managed signing and the authenticated API key.
#   4. Verify the exported app's authority, team, and seeded entitlements.
#
# Every platform is built and verified before anything is uploaded, so a
# signing failure on one platform never leaves a half-shipped build.
#
# See docs/cloudkit-sharing.md#deploysh-re-sign-dance-ios for the full story.

BUNDLE_ID="net.shadowpuppet.ADultingHD"
CLOUD_CONTAINER="iCloud.$BUNDLE_ID"
APP_GROUP="group.$BUNDLE_ID"

# Note: every `grep` below is deliberately followed by `|| true`. With
# `set -euo pipefail`, a `grep` that finds no match exits 1 and, inside a
# pipeline feeding a variable assignment, would abort the script instead of
# falling through to the next identity type or the ad-hoc fallback.
SEED_IDENTITY="${DEPLOY_SEED_SIGN_IDENTITY:-}"
if [ -z "$SEED_IDENTITY" ]; then
    CODESIGN_IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
    SEED_IDENTITY=$(echo "$CODESIGN_IDENTITIES" | grep "Apple Development" | head -1 | sed -E 's/^.*"(.*)"$/\1/' || true)
    if [ -z "$SEED_IDENTITY" ]; then
        SEED_IDENTITY=$(echo "$CODESIGN_IDENTITIES" | grep "Apple Distribution" | head -1 | sed -E 's/^.*"(.*)"$/\1/' || true)
    fi
fi
if [ -z "$SEED_IDENTITY" ]; then
    SEED_IDENTITY="-"
    echo "🔏 No local codesigning identity found; using an ad-hoc seed signature"
else
    echo "🔏 Using local seed identity: $SEED_IDENTITY"
fi

cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

# build_platform <label> <scheme> <sdk-platform> <entitlements-plist>
#
# Archives, seeds, exports, and verifies one platform. Sets EXPORTED_FILE to
# the .ipa/.pkg that upload_build should send.
build_platform() {
    local label="$1" scheme="$2" sdk="$3" entitlements="$4"
    local archive="$BUILD_DIR/$scheme.xcarchive"
    local export_dir="$BUILD_DIR/export_$sdk"
    local verify_dir="$BUILD_DIR/verify_$sdk"

    echo "📦 Archiving $label..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -configuration Release \
        -destination "generic/platform=$label" \
        -archivePath "$archive" \
        CURRENT_PROJECT_VERSION="$NEW_BUILD" \
        CODE_SIGNING_ALLOWED=NO \
        CLOUDKIT_SIGNING_EXPECTED=YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        -quiet
    echo "✅ $label archive complete"

    local app
    app=$(find_app "$archive/Products/Applications")
    local archived_build
    archived_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(app_info_plist "$app")")
    if [ "$archived_build" != "$NEW_BUILD" ]; then
        echo "❌ Archived $label build number is $archived_build; expected $NEW_BUILD"
        exit 1
    fi
    echo "✅ $label archive contains build $archived_build from source $SOURCE_SHA"

    # This must happen BEFORE -exportArchive: an archive that never had these
    # entitlements embedded gets exported with only the minimal dict.
    echo "🔏 Seeding $label archive with production entitlements"
    codesign --force --sign "$SEED_IDENTITY" \
        --entitlements "$entitlements" \
        --preserve-metadata=identifier,flags,runtime \
        "$app"

    echo "📤 Exporting $label..."
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
        -exportPath "$export_dir" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet

    EXPORTED_FILE=$(find "$export_dir" -maxdepth 1 \( -name "*.ipa" -o -name "*.pkg" \) | head -1)
    if [ -z "$EXPORTED_FILE" ]; then
        echo "❌ $label export produced no .ipa or .pkg"
        ls -la "$export_dir/"
        exit 1
    fi
    echo "✅ $label exported: $(basename "$EXPORTED_FILE")"

    rm -rf "$verify_dir"
    case "$EXPORTED_FILE" in
        *.ipa) mkdir -p "$verify_dir" && (cd "$verify_dir" && unzip -q "$EXPORTED_FILE") ;;
        *.pkg) pkgutil --expand-full "$EXPORTED_FILE" "$verify_dir" ;;
    esac
    local exported_app
    exported_app=$(find_app "$verify_dir")
    verify_signed_app "$label" "$exported_app" "$entitlements"
    rm -rf "$verify_dir"
}

find_app() {
    local app
    app=$(find "$1" -type d -name "*.app" -prune | head -1)
    if [ -z "$app" ]; then
        echo "❌ No app bundle found in $1" >&2
        exit 1
    fi
    echo "$app"
}

app_info_plist() {
    if [ -f "$1/Contents/Info.plist" ]; then
        echo "$1/Contents/Info.plist"
    else
        echo "$1/Info.plist"
    fi
}

# verify_signed_app <label> <app-bundle> <seed-entitlements-plist>
#
# The exported app must be signed by the Apple Distribution authority for our
# team and carry every seeded production entitlement. A minimally-entitled or
# wrongly-signed binary sails through TestFlight processing but traps at
# runtime on CKContainer(identifier:).
verify_signed_app() {
    local label="$1" app="$2" seed="$3"
    echo "🔍 Verifying exported $label signature and entitlements..."

    local codesign_info
    codesign_info=$(codesign -dvvv "$app" 2>&1)
    if ! echo "$codesign_info" | grep -q "Authority=Apple Distribution: "; then
        echo "❌ Exported $label app is not signed by an Apple Distribution authority — aborting"
        exit 1
    fi
    if ! echo "$codesign_info" | grep -q "TeamIdentifier=$TEAM_ID"; then
        echo "❌ Exported $label app TeamIdentifier does not match expected $TEAM_ID — aborting"
        exit 1
    fi
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :CloudKitSigningExpected' "$(app_info_plist "$app")")" != "YES" ]; then
        echo "❌ Exported $label app disables CloudKit at runtime — aborting"
        exit 1
    fi

    # Every seeded key must survive export with its seeded value. The keychain
    # access group wildcard is the one key export legitimately rewrites, so it
    # only has to be present.
    if ! codesign -d --entitlements :- "$app" 2>/dev/null | SEED="$seed" /usr/bin/python3 -c '
import os, plistlib, sys
exported = plistlib.loads(sys.stdin.buffer.read())
with open(os.environ["SEED"], "rb") as f:
    seeded = plistlib.load(f)
problems = []
for key, value in seeded.items():
    if key not in exported:
        problems.append(f"missing {key}")
    elif key != "keychain-access-groups" and exported[key] != value:
        problems.append(f"{key} is {exported[key]!r}, expected {value!r}")
for problem in problems:
    print("   " + problem)
sys.exit(1 if problems else 0)
'; then
        echo "❌ Exported $label app does not carry the seeded production entitlements — aborting"
        exit 1
    fi
    echo "✅ $label verified: Apple Distribution authority, team $TEAM_ID, full production entitlements"
}

# upload_build <label> <altool-type> <file>
upload_build() {
    local label="$1" type="$2" file="$3"
    if $EXPORT_ONLY; then
        echo "⏭️  --export-only: skipping $label upload"
        return
    fi

    local log="$BUILD_DIR/${type}_upload.log"
    echo "🚀 Uploading $label to TestFlight..."
    set +e
    xcrun altool --upload-app \
        --file "$file" \
        --type "$type" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1 | tee "$log"
    local status=${PIPESTATUS[0]}
    set -e
    # Definitive failure markers only — plain "ERROR: " false-positives on
    # altool's normal multipart retry events ("WILL RETRY PART N. Checksums
    # do not match." / "The network connection was lost."). The four patterns
    # below are Apple's terminal failure banners only.
    if [ "$status" -ne 0 ] || grep -qE "UPLOAD FAILED|Validation failed \(|ERROR ITMS-|product-errors" "$log"; then
        echo "❌ $label upload failed — see errors above"
        exit 1
    fi
    echo "✅ $label upload complete!"

    local delivery_id
    delivery_id=$(sed -nE 's/.*Delivery UUID:[[:space:]]*([[:alnum:]-]+).*/\1/p' "$log" | tail -1)
    if [ -z "$delivery_id" ]; then
        echo "❌ $label upload succeeded but no delivery UUID was returned"
        exit 1
    fi
    # Waiting for Apple to process this delivery also spaces it from the next
    # platform's upload, avoiding Apple CDN contention.
    verify_delivery_processing "$label" "$delivery_id"
}

# Production iOS entitlements. Must match what the App ID actually grants,
# minus any wildcards/development-only keys that App Store Connect validation
# rejects (`icloud-services = *`, `ubiquity-kvstore-identifier = TEAMID.*`,
# `icloud-container-development-container-identifiers`).
IOS_ENTITLEMENTS="$BUILD_DIR/entitlements_ios_production.plist"
cat > "$IOS_ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>$TEAM_ID.$BUNDLE_ID</string>
    <key>aps-environment</key>
    <string>production</string>
    <key>beta-reports-active</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>$APP_GROUP</string>
    </array>
    <key>com.apple.developer.icloud-container-environment</key>
    <string>Production</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>$CLOUD_CONTAINER</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudDocuments</string>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.team-identifier</key>
    <string>$TEAM_ID</string>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>$CLOUD_CONTAINER</string>
    </array>
    <key>get-task-allow</key>
    <false/>
    <key>keychain-access-groups</key>
    <array>
        <string>$TEAM_ID.*</string>
        <string>com.apple.token</string>
    </array>
</dict>
</plist>
EOF

# Production macOS entitlements start from the target's checked-in
# entitlements (sandbox, file access, App Group, iCloud services), so a
# capability added there reaches release builds. macOS then needs the
# platform spellings of the push and app-identifier keys and the concrete
# production values that the development file leaves out.
MACOS_ENTITLEMENTS="$BUILD_DIR/entitlements_macos_production.plist"
cp ADultingHD/App/ADultingHD.entitlements "$MACOS_ENTITLEMENTS"
# PlistBuddy, not plutil: plutil treats the dots in these key names as nested
# key paths.
/usr/libexec/PlistBuddy \
    -c "Delete :aps-environment" \
    -c "Add :com.apple.developer.aps-environment string production" \
    -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    -c "Add :com.apple.developer.icloud-container-environment string Production" \
    -c "Add :com.apple.developer.ubiquity-container-identifiers array" \
    -c "Add :com.apple.developer.ubiquity-container-identifiers:0 string $CLOUD_CONTAINER" \
    "$MACOS_ENTITLEMENTS"

if $BUILD_IOS; then
    build_platform "iOS" "ADultingHD_iOS" "ios" "$IOS_ENTITLEMENTS"
    IOS_FILE="$EXPORTED_FILE"
fi
if $BUILD_MACOS; then
    build_platform "macOS" "ADultingHD_macOS" "macos" "$MACOS_ENTITLEMENTS"
    MACOS_FILE="$EXPORTED_FILE"
fi

if $BUILD_IOS; then
    upload_build "iOS" "ios" "$IOS_FILE"
fi
if $BUILD_MACOS; then
    upload_build "macOS" "macos" "$MACOS_FILE"
fi

if $EXPORT_ONLY; then
    echo "✅ Build $NEW_BUILD exported and verified (not uploaded)."
else
    echo "✅ Build $NEW_BUILD submitted to TestFlight."
fi

if ! $NO_BUMP; then
    git add project.yml "$PROJECT/project.pbxproj"
    git commit -m "build: bump to build $NEW_BUILD" -m "TestFlight source: $SOURCE_SHA"
    DEPLOY_SUCCESS=true
    echo "📝 Committed build number bump"

    echo "⬆️  Pushing build record to $DEPLOY_REMOTE/$DEPLOY_BRANCH..."
    git push "$DEPLOY_REMOTE" "$DEPLOY_BRANCH"
    echo "✅ Build record pushed"
else
    echo "📝 Skipped build-number commit (--no-bump)"
fi

rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
