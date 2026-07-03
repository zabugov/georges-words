#!/usr/bin/env bash
# Build George's Words into a runnable .app bundle and launch it.
# Usage: ./app/build.sh   (from the repo root, on your Mac)
set -euo pipefail
cd "$(dirname "$0")"

if [ "${GW_PARAKEET:-}" = "0" ]; then
    echo "==> Parakeet engine DISABLED (GW_PARAKEET=0) — Whisper-only build"
fi

echo "==> Building (first run downloads Swift dependencies — may take a few minutes)"
if ! swift build -c release; then
    # "could not build module '_DarwinFoundation…'" and similar module errors
    # are a stale compiler module cache (often leftover from a previous Xcode
    # / SDK), not a code problem. Clear the caches and try once more from clean.
    echo ""
    echo "==> Build failed. Clearing compiler/module caches and retrying from clean…"
    rm -rf .build
    rm -rf "$HOME/Library/Caches/org.swift.swiftpm"
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
    CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
    if [ -n "$CACHE_DIR" ]; then
        rm -rf "${CACHE_DIR}org.llvm.clang" "${CACHE_DIR}clang"
    fi
    swift build -c release
fi

APP_DIR="build/GeorgesWords.app"

# Assemble and SIGN in a private temp dir. The project may live in an
# iCloud-synced folder, and iCloud stamps extended attributes onto files
# faster than we can strip them — codesign then fails with "resource fork,
# Finder information, or similar detritus not allowed". Signing outside
# iCloud's reach avoids the race entirely; the finished app is moved into
# place afterwards.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/georgeswords.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE_APP="$STAGE_DIR/GeorgesWords.app"

echo "==> Assembling ${APP_DIR}"
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp ".build/release/GeorgesWords" "$STAGE_APP/Contents/MacOS/GeorgesWords"
cp "Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "icon/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGE_APP" 2>/dev/null || true
find "$STAGE_APP" -name "._*" -delete 2>/dev/null || true

IDENTITY="GeorgesWords Dev"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> No stable signing identity yet — creating one now (one-time)."
    echo "    macOS may ask for your login password; that's expected."
    ./setup-signing.sh || true
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> Signing with '$IDENTITY' (stable identity — permissions survive rebuilds)"
    codesign --force --deep --sign "$IDENTITY" "$STAGE_APP"
else
    echo "!! Signing ad-hoc — macOS WILL reset Microphone/Accessibility permissions"
    echo "!! on every rebuild. Run ./app/setup-signing.sh manually to fix this."
    codesign --force --deep --sign - "$STAGE_APP"
fi

echo "==> Signature check:"
codesign -dv "$STAGE_APP" 2>&1 | grep -E "Signature|Authority" || true

echo "==> Installing ${APP_DIR}"
mkdir -p build
rm -rf "$APP_DIR"
mv "$STAGE_APP" "$APP_DIR"

if [ -z "${GW_SKIP_OPEN:-}" ]; then
    echo "==> Launching"
    open "$APP_DIR"
fi

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
EOF
