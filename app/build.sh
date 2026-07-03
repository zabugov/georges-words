#!/usr/bin/env bash
# Build George's Words into a runnable .app bundle and launch it.
# Usage: ./app/build.sh   (from the repo root, on your Mac)
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Building (first run downloads Swift dependencies — may take a few minutes)"
swift build -c release

APP_DIR="build/GeorgesWords.app"
echo "==> Assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/GeorgesWords" "$APP_DIR/Contents/MacOS/GeorgesWords"
cp "Info.plist" "$APP_DIR/Contents/Info.plist"

IDENTITY="GeorgesWords Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> Signing with '$IDENTITY' (stable identity — permissions survive rebuilds)"
    codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
else
    echo "==> Signing (ad-hoc)."
    echo "    Tip: run ./app/setup-signing.sh once, and macOS will stop asking you"
    echo "    to re-grant Accessibility after every rebuild."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Launching"
open "$APP_DIR"

cat <<'EOF'

George's Words is starting (look for the mic icon in the menu bar).

First-run checklist:
  1. Allow Microphone access when prompted.
  2. Allow Accessibility access when prompted
     (System Settings -> Privacy & Security -> Accessibility -> enable GeorgesWords).
  3. Set the Fn key free: System Settings -> Keyboard -> "Press globe key" -> Do Nothing.
  4. First launch downloads the speech model (one-time, ~500 MB). The menu bar
     icon shows an hourglass until it's ready, then a mic.

Then: click into any text field, HOLD Fn, speak, release.

Note: after a rebuild, macOS may require re-toggling the Accessibility
permission (off and on again) because the app's ad-hoc signature changed.
EOF
