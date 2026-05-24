# Needle

A native macOS file search prototype.

The first version focuses on a polished macOS search surface backed by an
independent filename index. It does not use Spotlight as its primary search
engine.

## Build

```sh
swift build
swift test
swift run NeedleCoreCheck
swift run Needle
```

## Package a runnable app

```sh
scripts/package_app.sh debug
open .build/app/Needle.app
```

For permission testing, install the app into `/Applications` first. macOS System
Settings is more reliable with apps from the Applications folder than with apps
inside hidden build directories.

```sh
scripts/package_app.sh debug --install
open /Applications/Needle.app
```

The packaging script builds the SwiftPM executable, assembles a standard macOS
`.app` bundle, writes `Info.plist`, and applies ad-hoc signing for local runs.

## Create a DMG

```sh
scripts/create_dmg.sh release
open dist/Needle.dmg
```

For Developer ID builds, provide a signing identity before packaging:

```sh
export NEEDLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
scripts/create_dmg.sh release
```

To notarize the signed DMG, set Apple notarization credentials and run:

```sh
export NEEDLE_NOTARY_APPLE_ID="you@example.com"
export NEEDLE_NOTARY_TEAM_ID="TEAMID"
export NEEDLE_NOTARY_PASSWORD="app-specific-password"
scripts/notarize_dmg.sh dist/Needle.dmg
```

## First run

The app uses Chinese as the default UI language. It starts with no indexed roots
so it does not unexpectedly scan the whole home folder. Open Settings, add a
small folder first, then rebuild the index. Add the home folder only after
granting Full Disk Access in System Settings.

The first launch guide links to:

- Full Disk Access, required for protected folders such as Desktop, Documents,
  Downloads, and Photos Library. Use System Settings' `+` button to add
  `/Applications/Needle.app`; dragging the app into the list is not used as the
  primary flow because macOS TCC panels handle custom drag sources
  inconsistently.
- Accessibility, required by macOS for the global shortcut listener.

Settings currently include:

- Indexed folders.
- Include hidden files.
- Match paths by default.
- Launch at login.
- Global shortcut toggle. The default shortcut is `Command-Shift-F`.

`NeedleCoreCheck` is a fast no-framework smoke check for query parsing, ranking,
exclusion rules, and SQLite persistence. `swift test` runs the standard XCTest
suite now that full Xcode is available.

Project progress and the active polishing backlog are tracked in
[`PROGRESS.md`](PROGRESS.md).

Manual release QA is tracked in [`docs/QA_CHECKLIST.md`](docs/QA_CHECKLIST.md).
