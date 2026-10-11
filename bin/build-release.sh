#!/bin/bash
set -e

# Builds a release: a universal app signed with Developer ID and the hardened runtime, in a signed,
# notarized, and stapled DMG, plus a signed Sparkle appcast pointing at it. With --upload it also
# publishes them: the DMG to Cloudflare R2, a GitHub release for the record, and the appcast last.
#
#   ./bin/build-release.sh [--upload]
#
# Needs a .env (cp .env.example .env), or with a 1Password-managed .env:
#   op run --env-file=.env -- ./bin/build-release.sh --upload

UPLOAD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --upload) UPLOAD=true; shift ;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [--upload]"; exit 1 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_NAME="HoverEnhance"
REPO="jstilwell/HoverEnhance"
PLIST_PATH="Resources/Info.plist"
RELEASE_DIR="build/release"
APP="$RELEASE_DIR/$APP_NAME.app"
APPCAST="$RELEASE_DIR/appcast.xml"
# The keychain account holding HoverEnhance's update signing key (see `generate_keys --account`).
SPARKLE_ACCOUNT="HoverEnhance"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"
ENV_FILE="$PROJECT_DIR/.env"

# Variables already in the environment (op run) win; otherwise a regular .env is sourced.
if [ -z "$R2_ACCOUNT_ID" ] && [ -e "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi
for var in R2_ACCOUNT_ID R2_BUCKET R2_APPCAST_PATH APPCAST_BASE_URL; do
    if [ -z "${!var}" ] || [ "${!var}" = "your_account_id_here" ]; then
        echo -e "${RED}Error: $var is not set.${NC}"
        echo "Either create a regular .env (cp .env.example .env) or, with a 1Password-managed .env, run:"
        echo "  op run --env-file=.env -- $0 $*"
        exit 1
    fi
done
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
APPCAST_PUBLIC_URL="${APPCAST_BASE_URL}/${R2_APPCAST_PATH}"

# Preflight: notarization credentials and Apple's agreements, before spending time building.
echo -e "${YELLOW}Checking notarization credentials...${NC}"
NOTARY_PREFLIGHT=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json 2>&1) || {
    echo -e "${RED}Notarization preflight failed.${NC}"
    if echo "$NOTARY_PREFLIGHT" | grep -qi "agreement"; then
        echo "An Apple Developer agreement needs accepting: https://developer.apple.com/account"
        echo "and https://appstoreconnect.apple.com/ → Business → Agreements, Tax, and Banking."
    elif echo "$NOTARY_PREFLIGHT" | grep -qi "keychain"; then
        echo "Keychain profile '$NOTARY_PROFILE' is missing. Create it with:"
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your-apple-id> --team-id <your-team-id>"
    fi
    echo "Raw error:"
    echo "$NOTARY_PREFLIGHT"
    exit 1
}
echo -e "${GREEN}Notarization credentials OK${NC}"

SIGN_UPDATE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -x "$SIGN_UPDATE" ]; then
    xcrun swift package resolve > /dev/null
fi
if [ ! -x "$SIGN_UPDATE" ]; then
    echo -e "${RED}Error: Sparkle's sign_update not found at $SIGN_UPDATE${NC}"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST_PATH")
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not read the version from $PLIST_PATH${NC}"
    exit 1
fi

# Release notes come from this version's section of CHANGELOG.md.
if [ ! -f CHANGELOG.md ]; then
    echo -e "${RED}Error: CHANGELOG.md not found${NC}"
    exit 1
fi
CHANGELOG_SECTION=$(sed -n "/^## ${VERSION} /,/^## /{/^## ${VERSION} /d;/^## /d;p;}" CHANGELOG.md)
CHANGELOG_SECTION=$(echo "$CHANGELOG_SECTION" | awk 'NF{found=1} found' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--)if(lines[i]~/[^ \t]/){last=i;break} for(i=1;i<=last;i++)print lines[i]}')
if [ -z "$CHANGELOG_SECTION" ]; then
    echo -e "${RED}Error: No CHANGELOG.md entry for version ${VERSION}${NC}"
    echo "Add one like this before building:"
    echo ""
    echo "  ## ${VERSION} - $(date +%m-%d-%Y)"
    echo ""
    echo "  ### Changed"
    echo "  - What changed"
    exit 1
fi
if grep -q "^## ${VERSION} - [Uu]nreleased" CHANGELOG.md; then
    echo -e "${RED}Error: CHANGELOG.md still calls ${VERSION} unreleased. Give it today's date ($(date +%m-%d-%Y)).${NC}"
    exit 1
fi
echo -e "${GREEN}Found the CHANGELOG.md entry for ${VERSION}${NC}"

GITHUB_NOTES="## What's New in Version ${VERSION}

${CHANGELOG_SECTION}"
APPCAST_FEATURES=""
while IFS= read -r line; do
    if [[ "$line" == -\ * ]]; then
        APPCAST_FEATURES="${APPCAST_FEATURES}          <li>${line#- }</li>
"
    fi
done <<< "$CHANGELOG_SECTION"
if [ -z "$APPCAST_FEATURES" ]; then
    APPCAST_FEATURES="          <li>Bug fixes and improvements</li>
"
fi

# Sparkle compares CFBundleVersion, so it follows the version.
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST_PATH")
if [ "$BUILD_VERSION" != "$VERSION" ]; then
    echo -e "${YELLOW}Syncing CFBundleVersion ($BUILD_VERSION) to $VERSION${NC}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST_PATH"
fi
CURRENT_FEED_URL=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" "$PLIST_PATH")
if [ "$CURRENT_FEED_URL" != "$APPCAST_PUBLIC_URL" ]; then
    echo -e "${YELLOW}Setting SUFeedURL to $APPCAST_PUBLIC_URL${NC}"
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $APPCAST_PUBLIC_URL" "$PLIST_PATH"
fi

# A release is cut from committed code, so the tag holds exactly what was built (including any
# Info.plist sync just made).
if [ "$UPLOAD" = true ] && [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}Error: the working tree has uncommitted changes.${NC}"
    git status --short
    echo "Commit them (including any Info.plist sync made just now) and run this again."
    exit 1
fi
if git rev-parse -q --verify "refs/tags/v${VERSION}" > /dev/null; then
    echo -e "${RED}Error: v${VERSION} is already tagged. Raise CFBundleShortVersionString in $PLIST_PATH.${NC}"
    exit 1
fi

echo -e "${GREEN}Building ${APP_NAME} ${VERSION}${NC}"
rm -rf "$RELEASE_DIR"
make release-app

# The appcast's minimum system must be what the binary needs, or Sparkle offers the update to Macs
# that can't run it.
MIN_SYSTEM_VERSION=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DOWNLOAD_URL="${APPCAST_BASE_URL}/releases/${DMG_NAME}"
echo -e "${YELLOW}Creating ${DMG_NAME}${NC}"
DMG_TEMP=$(mktemp -d)
trap 'rm -rf "$DMG_TEMP"' EXIT
cp -R "$APP" "$DMG_TEMP/"
# A leading space sorts the Applications link after the app.
ln -s /Applications "$DMG_TEMP/ Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"

SIGNING_IDENTITY=$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=Developer ID Application/{print $2; exit}')
if [ -z "$SIGNING_IDENTITY" ]; then
    echo -e "${RED}Error: the app isn't signed with a Developer ID Application identity${NC}"
    exit 1
fi
echo -e "${YELLOW}Signing the DMG as ${SIGNING_IDENTITY}${NC}"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"

# Anything but "Accepted" stops the release: Gatekeeper blocks an un-notarized download.
echo -e "${YELLOW}Notarizing the DMG (waiting up to 30 minutes)...${NC}"
NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" \
    --wait --timeout 30m --output-format json 2>&1) || true
SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
NOTARY_STATUS=$(echo "$NOTARY_OUTPUT" | grep -o '"status":"[^"]*"' | tail -1 | cut -d'"' -f4)
if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo -e "${RED}Notarization didn't succeed (status: ${NOTARY_STATUS:-none}). Release stopped.${NC}"
    echo "$NOTARY_OUTPUT"
    if [ -n "$SUBMISSION_ID" ]; then
        echo "Details: xcrun notarytool log \"$SUBMISSION_ID\" --keychain-profile \"$NOTARY_PROFILE\""
    fi
    exit 1
fi
xcrun stapler staple "$DMG_PATH"
if ! spctl -a -t open --context context:primary-signature -v "$DMG_PATH"; then
    echo -e "${RED}Error: Gatekeeper rejects the DMG. Release stopped.${NC}"
    exit 1
fi
echo -e "${GREEN}Notarized and stapled${NC}"

echo -e "${YELLOW}Signing the update...${NC}"
SIGNATURE=$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG_PATH")
ED_SIGNATURE=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
if [ -z "$ED_SIGNATURE" ]; then
    echo -e "${RED}Error: Failed to sign the update${NC}"
    exit 1
fi
FILE_SIZE=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$APPCAST" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.sparkleproject.org/xml/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME}</title>
    <link>${APPCAST_PUBLIC_URL}</link>
    <description>Most recent updates to ${APP_NAME}</description>
    <language>en</language>

    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>What's New in Version ${VERSION}</h2>
        <ul>
${APPCAST_FEATURES}        </ul>
      ]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}" />
      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

# The app requires a signed feed (SURequireSignedFeed). Nothing may change the appcast after this.
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$APPCAST"
if ! "$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$APPCAST"; then
    echo -e "${RED}Error: the appcast's signature didn't verify${NC}"
    exit 1
fi
echo -e "${GREEN}Built ${DMG_PATH} and a signed ${APPCAST}${NC}"

r2_upload() { # <file> <key> <content type>
    aws s3 cp "$1" "s3://${R2_BUCKET}/$2" --endpoint-url "$R2_ENDPOINT" --profile r2 --content-type "$3"
}

if [ "$UPLOAD" = true ]; then
    if ! command -v aws &> /dev/null || ! aws configure list --profile r2 &> /dev/null; then
        echo -e "${RED}Error: the AWS CLI with an 'r2' profile is needed (brew install awscli; aws configure --profile r2).${NC}"
        exit 1
    fi
    # Order matters: the appcast points at the DMG, so the DMG goes up first and the appcast last.
    echo -e "${YELLOW}Uploading the DMG to R2...${NC}"
    r2_upload "$DMG_PATH" "releases/${DMG_NAME}" "application/x-apple-diskimage"
    echo -e "${GREEN}DMG at ${DOWNLOAD_URL}${NC}"

    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        # Tags the commit that was built, even on a branch not yet merged.
        gh release create "v${VERSION}" "$DMG_PATH" --title "Version ${VERSION}" --notes "$GITHUB_NOTES" \
            --target "$(git rev-parse HEAD)" --repo "$REPO"
    else
        echo -e "${YELLOW}GitHub CLI not signed in; skipped the GitHub release. Tag v${VERSION} by hand.${NC}"
    fi

    echo -e "${YELLOW}Publishing the appcast...${NC}"
    r2_upload "$APPCAST" "$R2_APPCAST_PATH" "application/xml"
    echo -e "${GREEN}Appcast at ${APPCAST_PUBLIC_URL}${NC}"
else
    echo -e "${YELLOW}Next:${NC} ./bin/build-release.sh --upload publishes it, or by hand:"
    echo "  1. upload ${DMG_PATH} to ${DOWNLOAD_URL}"
    echo "  2. then publish the appcast with ./bin/copy-appcast.sh"
fi
echo -e "${GREEN}Done!${NC}"
