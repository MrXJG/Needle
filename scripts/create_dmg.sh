#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg"
APP_NAME="Needle"
APP_PATH="$BUILD_DIR/app/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"
SIGN_IDENTITY="${NEEDLE_SIGN_IDENTITY:-}"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/package_app.sh" "$CONFIGURATION"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH" >/dev/null
fi

echo "$DMG_PATH"
