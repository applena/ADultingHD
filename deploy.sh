#!/bin/bash
set -euo pipefail

# ADultingHD - Local TestFlight Deploy
# Usage: ./deploy.sh [--skip-tests] [--macos] [--ios] [--all]
# Default (no platform flag): iOS only
# --macos: macOS only
# --all: both iOS and macOS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

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
    echo "🧪 Running tests..."
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
    xcodebuild test \
        -project "$PROJECT" \
        -scheme ADultingHD_iOS \
        -destination "$DESTINATION" \
        -configuration Debug \
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
    # outright. Unsigned archive + signed export sidesteps that, but see the
    # post-export re-sign below that reinjects the real entitlements — the
    # export step alone produces a binary with only a minimal entitlements
    # dict (team-id + application-identifier + beta-reports-active +
    # get-task-allow) which makes CKContainer(identifier:) trap at runtime.
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

    # Re-sign the app with entitlements that include CloudKit. The
    # -exportArchive step above embeds the correct distribution profile (which
    # grants iCloud via the App ID) but signs the binary with a minimal
    # entitlements dict — just application-identifier, beta-reports-active,
    # team-identifier, get-task-allow. CKContainer(identifier:) traps at
    # runtime on a binary with no icloud entitlements claimed.
    #
    # Using the profile's granted Entitlements dict directly doesn't work
    # either: Apple's App Store validator rejects wildcarded values
    # (`icloud-services = *`, `ubiquity-kvstore-identifier = TEAMID.*`) and
    # development-only keys (`icloud-container-development-container-identifiers`).
    # Xcode normally rewrites these to specific values when signing during
    # archive — we emulate that rewrite here.
    echo "🔏 Re-signing with iOS distribution entitlements (CloudKit included)..."
    RESIGN_DIR="$BUILD_DIR/resign_ios"
    rm -rf "$RESIGN_DIR" && mkdir -p "$RESIGN_DIR"
    (cd "$RESIGN_DIR" && unzip -q "$IPA_PATH")
    APP_BUNDLE="$RESIGN_DIR/Payload/ADultingHD.app"

    # Build the production iOS entitlements dict. Must match what the
    # embedded profile grants, minus any wildcards/development-only keys
    # that App Store Connect validation rejects.
    cat > "$RESIGN_DIR/signing.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>TYQ32QCF6K.net.shadowpuppet.ADultingHD</string>
    <key>aps-environment</key>
    <string>production</string>
    <key>beta-reports-active</key>
    <true/>
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
    <string>TYQ32QCF6K</string>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>iCloud.net.shadowpuppet.ADultingHD</string>
    </array>
    <key>get-task-allow</key>
    <false/>
    <key>keychain-access-groups</key>
    <array>
        <string>TYQ32QCF6K.*</string>
        <string>com.apple.token</string>
    </array>
</dict>
</plist>
EOF

    SIGN_IDENTITY="Apple Distribution: ShadowPuppet, LLC (TYQ32QCF6K)"
    codesign --force --sign "$SIGN_IDENTITY" \
        --entitlements "$RESIGN_DIR/signing.entitlements" \
        --preserve-metadata=identifier,flags,runtime \
        "$APP_BUNDLE"
    # Rebuild the IPA
    rm -f "$IPA_PATH"
    (cd "$RESIGN_DIR" && zip -qr "$IPA_PATH" Payload)
    # Verify CloudKit entitlements now present in the binary
    if ! codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null \
        | grep -q "com.apple.developer.icloud-container-identifiers"; then
        echo "❌ Re-sign did not include CloudKit entitlements — aborting"
        codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 | head -20
        exit 1
    fi
    echo "✅ Re-signed with full entitlements"

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
git commit -m "build: bump to build $NEW_BUILD"
echo "📝 Committed build number bump"

rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
