#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WatchMyBack"
APP_DISPLAY_NAME="Focula"
BUNDLE_ID="dev.aeronyu.Focula"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/watch-my-back.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP_BUNDLE="$STAGING_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$STAGED_APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_NAME="WatchMyBack"
APP_ICON_SOURCE="$ROOT_DIR/Sources/WatchMyBack/Resources/AppIcon/$APP_ICON_NAME.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE" "$STAGED_APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/$APP_ICON_NAME.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Focula classifies ephemeral screenshots locally to determine whether current activity matches your goals.</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${WMB_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F\" '/Apple Development/ {print $2; exit}')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi
find "$STAGED_APP_BUNDLE" -depth -exec xattr -c {} \; >/dev/null 2>&1 || true
xattr -cr "$STAGED_APP_BUNDLE" >/dev/null 2>&1 || true
xattr -c "$STAGED_APP_BUNDLE" >/dev/null 2>&1 || true
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGED_APP_BUNDLE" >/dev/null
mkdir -p "$DIST_DIR"
/usr/bin/ditto --noextattr --norsrc "$STAGED_APP_BUNDLE" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
