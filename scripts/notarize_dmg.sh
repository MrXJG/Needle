#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/dist/Needle.dmg}"

: "${NEEDLE_NOTARY_APPLE_ID:?Set NEEDLE_NOTARY_APPLE_ID}"
: "${NEEDLE_NOTARY_TEAM_ID:?Set NEEDLE_NOTARY_TEAM_ID}"
: "${NEEDLE_NOTARY_PASSWORD:?Set NEEDLE_NOTARY_PASSWORD to an app-specific password}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH" >&2
  exit 1
fi

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$NEEDLE_NOTARY_APPLE_ID" \
  --team-id "$NEEDLE_NOTARY_TEAM_ID" \
  --password "$NEEDLE_NOTARY_PASSWORD" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "$DMG_PATH"
