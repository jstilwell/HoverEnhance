#!/bin/bash
set -e

usage() {
    cat <<'USAGE'
Builds this copy of HoverEnhance and runs it, quitting any copy that's already running.

  ./bin/run.sh          build and run
  ./bin/run.sh --log    then stream what it does (Ctrl-C stops the log, not the app)
USAGE
}

LOG=false
for arg in "$@"; do
    case $arg in
        --log) LOG=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg"; usage; exit 1 ;;
    esac
done

cd "$(dirname "$0")/.."

if ! xcrun --find swift > /dev/null 2>&1; then
    echo "Building HoverEnhance needs Xcode. Install it from the App Store, then run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi

# The Makefile signs with the first Apple Development or Developer ID certificate it finds.
if ! security find-identity -v -p codesigning | grep -qE "Apple Development|Developer ID Application"; then
    echo "Note: no signing certificate found, so the build is signed ad hoc and macOS will ask for"
    echo "Accessibility access again after every build. An Apple Development certificate avoids that."
fi

make run
echo "HoverEnhance is running from build/HoverEnhance.app. Look for its icon in the menu bar."

if [ "$LOG" = true ]; then
    make log
fi
