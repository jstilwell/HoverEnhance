#!/bin/bash
set -e

# Publishes the appcast bin/build-release.sh made, once its DMG is uploaded. Refuses an appcast that
# isn't signed, or was changed after signing: the app accepts only a signed feed.
#
#   ./bin/copy-appcast.sh     (or: op run --env-file=.env -- ./bin/copy-appcast.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"
if [ -z "$R2_ACCOUNT_ID" ] && [ -e .env ]; then
    # shellcheck source=/dev/null
    source .env
fi
for var in R2_ACCOUNT_ID R2_BUCKET R2_APPCAST_PATH APPCAST_BASE_URL; do
    if [ -z "${!var}" ] || [ "${!var}" = "your_account_id_here" ]; then
        echo "Error: $var is not set. Create a regular .env (cp .env.example .env) or run:"
        echo "  op run --env-file=.env -- $0"
        exit 1
    fi
done

APPCAST="build/release/appcast.xml"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if ! "$SIGN_UPDATE" --account HoverEnhance --verify "$APPCAST"; then
    echo "Error: $APPCAST isn't signed, or was changed after signing. Run ./bin/build-release.sh again."
    exit 1
fi

aws s3 cp "$APPCAST" "s3://${R2_BUCKET}/${R2_APPCAST_PATH}" \
    --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" --profile r2 --content-type "application/xml"
echo "Published ${APPCAST_BASE_URL}/${R2_APPCAST_PATH}"
