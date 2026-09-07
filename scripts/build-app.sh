#!/bin/bash
# Build Memodics.app — a proper .app bundle so macOS grants a stable
# Accessibility identity, shows the menu-bar item, and supports launch-at-login.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Memodics.app"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Memodics"

echo "Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Memodics"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Generate the multi-size AppIcon.icns from the single 1024×1024 Icon.png.
# All required sizes are downscaled automatically — no need to hand-make them.
ICON_SRC="$ROOT/Icon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "Generating app icon from $ICON_SRC"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
              "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
              "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/icon_${name}.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
else
  echo "warning: $ICON_SRC not found — bundle will have no app icon"
fi

# Ad-hoc code signature so the Accessibility grant sticks across launches.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "warning: ad-hoc codesign failed (app still runnable)"

echo "Done. Launch with:  open \"$APP\""
