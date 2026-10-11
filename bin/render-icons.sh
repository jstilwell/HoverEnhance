#!/bin/bash
set -e

# Renders the vector icons in design/icons/ into what the app ships: Resources/AppIcon.icns and the
# menu bar template image (MenuBarIcon.png at 1x and 2x). Uses headless Chrome, which draws the SVGs'
# gradients, masks, and filters faithfully where ImageMagick doesn't.
#
#   ./bin/render-icons.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR/design/icons"
OUT="$PROJECT_DIR/Resources"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
    echo "Error: Google Chrome is required at $CHROME"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# render <svg> <out.png> <px>
render() {
    printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="%s" height="%s" style="display:block"></body></html>' \
        "$1" "$3" "$3" > "$WORK/render.html"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$WORK/chrome" \
        --default-background-color=00000000 --force-device-scale-factor=1 \
        --window-size="$3,$3" --screenshot="$2" "file://$WORK/render.html" > /dev/null 2>&1
}

# App icon: every size an .icns holds, each rendered from the vector rather than scaled down.
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    render "$SRC/appicon.svg" "$ICONSET/icon_${size}x${size}.png" "$size"
    render "$SRC/appicon.svg" "$ICONSET/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"

# Menu bar template image, 18 pt.
render "$SRC/menubar.svg" "$OUT/MenuBarIcon.png" 18
render "$SRC/menubar.svg" "$OUT/MenuBarIcon@2x.png" 36

echo "Rendered AppIcon.icns and MenuBarIcon.png into $OUT"
