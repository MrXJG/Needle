#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
INSTALL_MODE="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_IDENTITY="${NEEDLE_SIGN_IDENTITY:--}"
VERSION_FROM_ENV="${NEEDLE_APP_VERSION:-}"

cd "$ROOT_DIR"

sign_app() {
  local app_path="$1"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$app_path" >/dev/null
  else
    codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$app_path" >/dev/null
  fi
}

resolve_app_version() {
  if [[ -n "$VERSION_FROM_ENV" ]]; then
    printf '%s' "${VERSION_FROM_ENV#v}"
    return
  fi

  if command -v git >/dev/null 2>&1; then
    local latest_tag
    latest_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [[ -n "$latest_tag" ]]; then
      printf '%s' "${latest_tag#v}"
      return
    fi
  fi

  printf '%s' "0.0.0"
}

swift build -c "$CONFIGURATION" --product Needle

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/Needle"
APP_DIR="$ROOT_DIR/.build/app/Needle.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing executable: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/Needle"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

APP_VERSION="$(resolve_app_version)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

chmod +x "$MACOS_DIR/Needle"

if command -v codesign >/dev/null 2>&1; then
  sign_app "$APP_DIR"
fi

if [[ "$INSTALL_MODE" == "--install" ]]; then
  rm -rf "/Applications/Needle.app"
  cp -R "$APP_DIR" "/Applications/Needle.app"
  if command -v codesign >/dev/null 2>&1; then
    sign_app "/Applications/Needle.app"
  fi
  echo "/Applications/Needle.app"
  exit 0
fi

echo "$APP_DIR"
