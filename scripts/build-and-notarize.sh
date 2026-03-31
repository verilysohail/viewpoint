#!/bin/bash
set -euo pipefail

# Build, sign, and notarize Indigo for Developer ID distribution.
#
# Prerequisites:
#   - "Developer ID Application: Verily Life Sciences, LLC (LDF8KBK2SH)" certificate
#     must be in the dev-secrets keychain
#   - Apple ID (smamdani@verily.com) must be signed in to Xcode with the
#     Verily Life Sciences team (LDF8KBK2SH)
#
# Usage:
#   ./scripts/build-and-notarize.sh

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/Viewpoint.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"

SCHEME="Viewpoint"
PROJECT="${PROJECT_DIR}/Viewpoint.xcodeproj"
CONFIGURATION="Release"

TEAM_ID="LDF8KBK2SH"
SIGN_IDENTITY="Developer ID Application: Verily Life Sciences, LLC (${TEAM_ID})"
KEYCHAIN_PATH="${HOME}/Library/Keychains/dev-secrets.keychain-db"

echo "==> Cleaning build directory"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Ensuring dev-secrets keychain is in search list"
security list-keychains -d user -s "${KEYCHAIN_PATH}" $(security list-keychains -d user | tr -d '"' | tr '\n' ' ')

echo "==> Archiving ${SCHEME}"
xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    archive \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--keychain ${KEYCHAIN_PATH}" \
    | tail -5

echo ""
echo "==> Archive succeeded"

# Generate ExportOptions.plist matching the Xcode Organizer "Distribute > Developer ID > Upload" flow.
# destination=upload submits to Apple's notary service using Xcode's stored credentials.
cat > "${EXPORT_OPTIONS}" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadSymbols</key>
    <false/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> Exporting and uploading to Apple notary service"
xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    | tail -5

echo ""
echo "==> Export and notarization upload succeeded"

# With destination=upload, the app is uploaded directly to Apple and placed in
# the archive's Submissions/ folder rather than EXPORT_PATH. Find it there.
SUBMISSION_APP=$(find "${ARCHIVE_PATH}/Submissions" -name "Indigo.app" -type d -maxdepth 2 2>/dev/null | head -1)

if [ -z "${SUBMISSION_APP}" ]; then
    echo "ERROR: Could not find submitted app in archive Submissions folder"
    exit 1
fi

# Wait for Apple to finish processing before stapling
echo "==> Waiting for notarization to complete..."
for i in $(seq 1 12); do
    if xcrun stapler staple "${SUBMISSION_APP}" 2>/dev/null; then
        break
    fi
    if [ "$i" -eq 12 ]; then
        echo "ERROR: Notarization did not complete within 2 minutes"
        exit 1
    fi
    echo "    Notarization still processing, retrying in 10s... (attempt $i/12)"
    sleep 10
done

# Verify
echo "==> Verifying signature and notarization"
spctl -a -vvv "${SUBMISSION_APP}" 2>&1

# Copy stapled app out for easy access
mkdir -p "${EXPORT_PATH}"
cp -R "${SUBMISSION_APP}" "${EXPORT_PATH}/Indigo.app"

echo ""
echo "==> Done! Notarized app is at: ${EXPORT_PATH}/Indigo.app"
