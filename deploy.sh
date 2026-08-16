#!/bin/bash
set -euo pipefail

# ADultingHD - Local TestFlight Deploy
# Usage: ./deploy.sh [--skip-tests] [--macos] [--ios] [--all]
# Default (no platform flag): iOS only
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

verify_deploy_checkout

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
BUILD_IOS=false
BUILD_MACOS=false
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        --macos) BUILD_MACOS=true ;;
        --ios) BUILD_IOS=true ;;
        --all) BUILD_IOS=true; BUILD_MACOS=true ;;
    esac
done
# Default to iOS if no platform specified
if ! $BUILD_IOS && ! $BUILD_MACOS; then
    BUILD_IOS=true
fi

# Auto-increment build number
CURRENT_BUILD=$(grep CURRENT_PROJECT_VERSION project.yml | head -1 | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

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

# --- iOS Build & Upload ---
if $BUILD_IOS; then
    SCHEME_IOS="ADultingHD_iOS"
    ARCHIVE_IOS="$BUILD_DIR/ADultingHD_iOS.xcarchive"
    EXPORT_IOS="$BUILD_DIR/export_ios"

    echo "📦 Archiving iOS..."
    # CODE_SIGNING_ALLOWED=NO keeps the archive unsigned because the
    # App Store Connect API key used below for export only has Upload scope,
    # not Admin/Profile-Management scope. An upload-scope key cannot auto-
    # register new capabilities via `-allowProvisioningUpdates` during archive,
    # so any capability mismatch (App Groups, Push, iCloud) fails the archive
    # outright.
    #
    # The archive stays unsigned here; the next step seeds it with the real
    # production entitlements using whatever codesigning identity is present
    # on this machine (normally "Apple Development" — no Apple Distribution
    # private key required), and `-exportArchive` below then re-signs it with
    # the Distribution authority via the authenticated App Store Connect API
    # key. Skipping the seed step leaves the export with only a minimal
    # entitlements dict (team-id + application-identifier +
    # beta-reports-active + get-task-allow), which makes
    # CKContainer(identifier:) trap at runtime. See
    # docs/cloudkit-sharing.md#deploysh-re-sign-dance-ios for the full story
    # and prerequisites.
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME_IOS" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE_IOS" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        -quiet
    echo "✅ iOS archive complete"

    ARCHIVE_APP="$ARCHIVE_IOS/Products/Applications/ADultingHD.app"
    if [ ! -d "$ARCHIVE_APP" ]; then
        echo "❌ Archived app bundle not found at $ARCHIVE_APP"
        exit 1
    fi

    ARCHIVED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVE_APP/Info.plist")
    if [ "$ARCHIVED_BUILD" != "$NEW_BUILD" ]; then
        echo "❌ Archived iOS build number is $ARCHIVED_BUILD; expected $NEW_BUILD"
        exit 1
    fi
    echo "✅ iOS archive contains build $ARCHIVED_BUILD from source $SOURCE_SHA"

    # Seed the unsigned archive with the production entitlement set. This
    # must happen BEFORE -exportArchive — an archive that never had these
    # entitlements embedded gets exported with only the minimal dict
    # described above.
    #
    # Signing here uses whichever local codesigning identity is available
    # (set DEPLOY_SEED_SIGN_IDENTITY in .env to force a specific one). That
    # identity never reaches TestFlight — it only exists so the archive
    # carries concrete, non-wildcarded entitlement values for
    # `-exportArchive` to re-sign for distribution against. No local Apple
    # Distribution private key is required anywhere in this script; a
    # standard "Apple Development" cert (the one Xcode already uses for
    # local device builds) is sufficient.
    # Note: every `grep` below is deliberately followed by `|| true`. With
    # `set -euo pipefail`, a `grep` that finds no match exits 1 and — because
    # it sits inside a pipeline feeding a variable assignment — that would
    # otherwise abort the whole script right here instead of falling through
    # to the next identity type or the "none found" error below.
    SEED_IDENTITY="${DEPLOY_SEED_SIGN_IDENTITY:-}"
    if [ -z "$SEED_IDENTITY" ]; then
        CODESIGN_IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
        SEED_IDENTITY=$(echo "$CODESIGN_IDENTITIES" | grep "Apple Development" | head -1 | sed -E 's/^.*"(.*)"$/\1/' || true)
        if [ -z "$SEED_IDENTITY" ]; then
            SEED_IDENTITY=$(echo "$CODESIGN_IDENTITIES" | grep "Apple Distribution" | head -1 | sed -E 's/^.*"(.*)"$/\1/' || true)
        fi
    fi
    if [ -z "$SEED_IDENTITY" ]; then
        echo "❌ No local codesigning identity found in the login keychain."
        echo "   Install an 'Apple Development' certificate + private key (Xcode ->"
        echo "   Settings -> Accounts -> Manage Certificates, or download one from"
        echo "   developer.apple.com) and re-run. See"
        echo "   docs/cloudkit-sharing.md#deploysh-re-sign-dance-ios for details."
        exit 1
    fi
    echo "🔏 Seeding archive with production entitlements using local identity"

    # Production iOS entitlements. Must match what the App ID actually
    # grants, minus any wildcards/development-only keys that App Store
    # Connect validation rejects (`icloud-services = *`,
    # `ubiquity-kvstore-identifier = TEAMID.*`,
    # `icloud-container-development-container-identifiers`).
    SEED_ENTITLEMENTS="$BUILD_DIR/entitlements_ios_production.plist"
    cat > "$SEED_ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>$TEAM_ID.net.shadowpuppet.ADultingHD</string>
    <key>aps-environment</key>
    <string>production</string>
    <key>beta-reports-active</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.net.shadowpuppet.ADultingHD</string>
    </array>
    <key>com.apple.developer.icloud-container-environment</key>
    <string>Production</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.net.shadowpuppet.ADultingHD</string>
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
        <string>iCloud.net.shadowpuppet.ADultingHD</string>
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

    codesign --force --sign "$SEED_IDENTITY" \
        --entitlements "$SEED_ENTITLEMENTS" \
        --preserve-metadata=identifier,flags,runtime \
        "$ARCHIVE_APP"
    if ! codesign -d --entitlements :- "$ARCHIVE_APP" 2>/dev/null \
        | grep -q "com.apple.developer.icloud-container-identifiers"; then
        echo "❌ Archive seeding did not embed CloudKit entitlements — aborting"
        exit 1
    fi
    echo "✅ Archive seeded with production entitlements"

    cat > "$BUILD_DIR/exportOptions_ios.plist" <<EOF
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

    echo "📤 Exporting iOS IPA..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_IOS" \
        -exportOptionsPlist "$BUILD_DIR/exportOptions_ios.plist" \
        -exportPath "$EXPORT_IOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ iOS IPA exported"

    IPA_PATH="$EXPORT_IOS/ADultingHD.ipa"
    if [ ! -f "$IPA_PATH" ]; then
        echo "❌ iOS IPA not found at $IPA_PATH"
        ls -la "$EXPORT_IOS/"
        exit 1
    fi

    # Verify the exported IPA before upload: it must be signed by the Apple
    # Distribution authority for our team, and it must carry the full
    # production entitlement set. Abort rather than upload if either check
    # fails — a minimally-entitled or wrongly-signed binary sails through
    # TestFlight processing but traps at runtime on CKContainer(identifier:).
    echo "🔍 Verifying exported IPA signature and entitlements..."
    VERIFY_DIR="$BUILD_DIR/verify_ios"
    rm -rf "$VERIFY_DIR" && mkdir -p "$VERIFY_DIR"
    (cd "$VERIFY_DIR" && unzip -q "$IPA_PATH")
    APP_BUNDLE="$VERIFY_DIR/Payload/ADultingHD.app"

    CODESIGN_INFO=$(codesign -dvvv "$APP_BUNDLE" 2>&1)
    if ! echo "$CODESIGN_INFO" | grep -q "Authority=Apple Distribution: "; then
        echo "❌ Exported IPA is not signed by an Apple Distribution authority — aborting upload"
        exit 1
    fi
    if ! echo "$CODESIGN_INFO" | grep -q "TeamIdentifier=$TEAM_ID"; then
        echo "❌ Exported IPA TeamIdentifier does not match expected $TEAM_ID — aborting upload"
        exit 1
    fi

    APP_ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null)
    for key in \
        "com.apple.developer.icloud-container-identifiers" \
        "com.apple.developer.icloud-services" \
        "com.apple.developer.ubiquity-container-identifiers" \
        "aps-environment" \
        "keychain-access-groups" \
        "com.apple.security.application-groups"
    do
        if ! echo "$APP_ENTITLEMENTS" | grep -q "$key"; then
            echo "❌ Exported IPA missing required entitlement: $key — aborting upload"
            exit 1
        fi
    done
    if ! echo "$APP_ENTITLEMENTS" | grep -A1 "get-task-allow" | grep -q "<false/>"; then
        echo "❌ Exported IPA has get-task-allow != false (not a distribution build) — aborting upload"
        exit 1
    fi
    rm -rf "$VERIFY_DIR"
    echo "✅ IPA verified: Apple Distribution authority, team $TEAM_ID, full production entitlements"

    echo "🚀 Uploading iOS to TestFlight..."
    IOS_UPLOAD_LOG="$BUILD_DIR/ios_upload.log"
    set +e
    xcrun altool --upload-app \
        --file "$IPA_PATH" \
        --type ios \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1 | tee "$IOS_UPLOAD_LOG"
    IOS_UPLOAD_STATUS=${PIPESTATUS[0]}
    set -e
    # Definitive failure markers only — plain "ERROR: " false-positives on
    # altool's normal multipart retry events ("WILL RETRY PART N. Checksums
    # do not match." / "The network connection was lost."). The four patterns
    # below are Apple's terminal failure banners only.
    if [ "$IOS_UPLOAD_STATUS" -ne 0 ] || grep -qE "UPLOAD FAILED|Validation failed \(|ERROR ITMS-|product-errors" "$IOS_UPLOAD_LOG"; then
        echo "❌ iOS upload failed — see errors above"
        exit 1
    fi
    echo "✅ iOS upload complete!"

    if $BUILD_MACOS; then
        echo "⏳ Waiting 60s before macOS upload to avoid Apple CDN contention..."
        sleep 60
    fi
fi

# --- macOS Build & Upload ---
if $BUILD_MACOS; then
    SCHEME_MACOS="ADultingHD_macOS"
    ARCHIVE_MACOS="$BUILD_DIR/ADultingHD_macOS.xcarchive"
    EXPORT_MACOS="$BUILD_DIR/export_macos"

    echo "📦 Archiving macOS..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME_MACOS" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_MACOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ macOS archive complete"

    cat > "$BUILD_DIR/exportOptions_macos.plist" <<EOF
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

    echo "📤 Exporting macOS pkg..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_MACOS" \
        -exportOptionsPlist "$BUILD_DIR/exportOptions_macos.plist" \
        -exportPath "$EXPORT_MACOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ macOS pkg exported"

    PKG_PATH=$(find "$EXPORT_MACOS" -name "*.pkg" | head -1)
    if [ -z "$PKG_PATH" ]; then
        echo "❌ macOS package not found in $EXPORT_MACOS"
        ls -la "$EXPORT_MACOS/"
        exit 1
    fi

    echo "🚀 Uploading macOS to TestFlight..."
    MACOS_UPLOAD_LOG="$BUILD_DIR/macos_upload.log"
    set +e
    xcrun altool --upload-app \
        --file "$PKG_PATH" \
        --type macos \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1 | tee "$MACOS_UPLOAD_LOG"
    MACOS_UPLOAD_STATUS=${PIPESTATUS[0]}
    set -e
    # See iOS section above for why we don't grep plain "ERROR: ".
    if [ "$MACOS_UPLOAD_STATUS" -ne 0 ] || grep -qE "UPLOAD FAILED|Validation failed \(|ERROR ITMS-|product-errors" "$MACOS_UPLOAD_LOG"; then
        echo "❌ macOS upload failed — see errors above"
        exit 1
    fi
    echo "✅ macOS upload complete!"
fi

echo "✅ Build $NEW_BUILD submitted to TestFlight."

git add project.yml "$PROJECT/project.pbxproj"
git commit -m "build: bump to build $NEW_BUILD" -m "TestFlight source: $SOURCE_SHA"
echo "📝 Committed build number bump"

rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
