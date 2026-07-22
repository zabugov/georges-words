#!/bin/bash
# Publish one built-and-stapled DMG: EdDSA-sign it, create the GitHub
# release (with the stable-named GeorgesWords.dmg asset the download
# page links), regenerate appcast.xml, roll the changelog, push the
# feed commit, and mirror the appcast into the public releases repo
# when configured (ADR 0009).
#
# Shared by release.yml (the normal path) and staple.yml (notarization
# verdicts that took longer than the in-run wait) so a slow verdict
# still ends in a real, customer-visible release — previously the
# staple workflow only re-uploaded an Actions artifact and no release
# ever appeared (review P1, 2026-07-22).
#
# Required env:
#   VERSION                 marketing version (CFBundleShortVersionString)
#   BUILD_NUMBER            CFBundleVersion — the ORIGINAL release run's
#                           run number, not the calling workflow's
#   DMG_PATH                path to the stapled DMG
#   GH_TOKEN                token for the code repo
#   SPARKLE_ED_PRIVATE_KEY  the Sparkle EdDSA private key. REQUIRED: the
#                           app embeds SUPublicEDKey, so an unsigned feed
#                           entry would be rejected by every installed
#                           copy (review P1 / backlog 7.10).
# Optional env (two-repo split, ADR 0009):
#   RELEASES_REPO           owner/name of the public releases repo
#   RELEASES_REPO_TOKEN     token that can push to RELEASES_REPO
set -euo pipefail

TAG="v${VERSION}-b${BUILD_NUMBER}"
DMG_NAME="$(basename "$DMG_PATH")"
DMG_DIR="$(dirname "$DMG_PATH")"

# --- Where does this release live, and does the feed point there? -----
FEED_URL=$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' app/Info.plist)
if [ -n "${RELEASES_REPO:-}" ]; then
  if [ -z "${RELEASES_REPO_TOKEN:-}" ]; then
    echo "::error::RELEASES_REPO is set but RELEASES_REPO_TOKEN is missing (ADR 0009 step 2)."
    exit 1
  fi
  TARGET_REPO="$RELEASES_REPO"
  RELEASE_TOKEN="$RELEASES_REPO_TOKEN"
  case "$FEED_URL" in
    *"$RELEASES_REPO"*) echo "Feed points at the releases repo." ;;
    *) echo "::warning::SUFeedURL still points at the code repo — correct only for the migration release itself (ADR 0009 step 4)." ;;
  esac
else
  TARGET_REPO="$GITHUB_REPOSITORY"
  RELEASE_TOKEN="$GH_TOKEN"
  case "$FEED_URL" in
    *"$GITHUB_REPOSITORY"*) ;;
    *)
      echo "::error::SUFeedURL ($FEED_URL) points away from this repo but RELEASES_REPO is not configured — installed apps would follow a feed this run never updates."
      exit 1
      ;;
  esac
fi

# --- EdDSA signature FIRST: never create a release we can't feed ------
if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  echo "::error::SPARKLE_ED_PRIVATE_KEY is missing — the app embeds a Sparkle public key, so an unsigned appcast entry would be rejected by every installed copy (7.10)."
  exit 1
fi
SIGN_TOOL=$(find app/.build -name sign_update -type f -perm +111 2>/dev/null | head -1)
if [ -z "$SIGN_TOOL" ]; then
  echo "::error::Sparkle's sign_update tool not found under app/.build — run 'swift build' or 'swift package resolve' first."
  exit 1
fi
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > ed_key.txt
ED_SIG=$("$SIGN_TOOL" -f ed_key.txt "$DMG_PATH" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
rm -f ed_key.txt
if [ -z "$ED_SIG" ]; then
  echo "::error::sign_update produced no signature — check SPARKLE_ED_PRIVATE_KEY."
  exit 1
fi

# --- Release notes from CHANGELOG.md's Unreleased section (9.9) -------
python3 - <<'NOTESEOF'
import re
notes = "Notarized, stapled, auto-updating build."
try:
    text = open("CHANGELOG.md").read()
    match = re.search(r"## Unreleased\n(.*?)(?=\n## |\Z)", text, re.S)
    body = match.group(1).strip() if match else ""
    if body:
        notes = body
except OSError:
    pass
open("/tmp/release-notes.md", "w").write(notes + "\n")
NOTESEOF

# --- The GitHub release, with the stable-named asset (9.2) ------------
cp "$DMG_PATH" "$DMG_DIR/GeorgesWords.dmg"
GH_TOKEN="$RELEASE_TOKEN" gh release create "$TAG" "$DMG_PATH" "$DMG_DIR/GeorgesWords.dmg" \
  --repo "$TARGET_REPO" \
  --title "George's Words ${VERSION} (build ${BUILD_NUMBER})" \
  --notes-file /tmp/release-notes.md

# --- appcast.xml -------------------------------------------------------
LENGTH=$(stat -f%z "$DMG_PATH")
URL="https://github.com/${TARGET_REPO}/releases/download/${TAG}/${DMG_NAME}"
python3 - "$VERSION" "$BUILD_NUMBER" "$URL" "$LENGTH" "$ED_SIG" <<'PYEOF'
import html, sys, email.utils, time
version, build, url, length = sys.argv[1:5]
ed_sig = sys.argv[5] if len(sys.argv) > 5 else ""
sig_attr = f' sparkle:edSignature="{ed_sig}"' if ed_sig else ""
# Sparkle shows the item description as the update notes (9.9) —
# same text the GitHub release gets, minimally HTML-ified.
description = ""
try:
    notes = open("/tmp/release-notes.md").read().strip()
    if notes:
        rendered = "<br>".join(
            html.escape(line.strip()).replace("- ", "&bull; ", 1) if line.strip().startswith("- ")
            else html.escape(line.strip())
            for line in notes.splitlines() if line.strip()
        ).replace("**", "")
        description = f"<description><![CDATA[{rendered}]]></description>"
except OSError:
    pass
appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>George's Words</title>
    <item>
      <title>Version {version} (build {build})</title>
      <pubDate>{email.utils.formatdate(time.time())}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      {description}
      <enclosure url="{url}" length="{length}"{sig_attr} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
open("appcast.xml", "w").write(appcast)
PYEOF

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# --- Roll the changelog (9.9); defensive — never blocks the feed ------
python3 - "$VERSION" "$BUILD_NUMBER" <<'ROLLEOF'
import sys, datetime, re
try:
    version, build = sys.argv[1], sys.argv[2]
    text = open("CHANGELOG.md").read()
    if re.search(r"## Unreleased\n+(?=[^\n#])", text):
        stamp = datetime.date.today().isoformat()
        text = text.replace(
            "## Unreleased",
            f"## Unreleased\n\n## {version} (build {build}) — {stamp}",
            1,
        )
        open("CHANGELOG.md", "w").write(text)
except Exception as error:
    print(f"::warning::changelog roll skipped: {error}")
ROLLEOF

# swift build/resolve may have refreshed Package.resolved — commit it
# too so local checkouts stay clean, and autostash any other noise.
git add appcast.xml app/Package.resolved CHANGELOG.md
git commit -m "Appcast: ${VERSION} build ${BUILD_NUMBER}"
git pull --rebase --autostash origin main
# HEAD:main, not main: on a tag trigger the checkout is a detached
# HEAD and no local main ref exists (review P1, 2026-07-22).
git push origin HEAD:main

# --- Two-repo split (ADR 0009): mirror the appcast ---------------------
# The commit above keeps the OLD feed current too, so installs that
# haven't migrated yet still see this release — both feeds stay live
# until the code repo goes private.
if [ "$TARGET_REPO" != "$GITHUB_REPOSITORY" ]; then
  rm -rf /tmp/releases-repo
  git clone --depth 1 "https://x-access-token:${RELEASES_REPO_TOKEN}@github.com/${TARGET_REPO}.git" /tmp/releases-repo
  cp appcast.xml /tmp/releases-repo/appcast.xml
  # If the releases repo serves its site (and maybe the feed, on a
  # custom domain) from site/, keep that copy fresh too.
  if [ -d /tmp/releases-repo/site ]; then
    cp appcast.xml /tmp/releases-repo/site/appcast.xml
  fi
  cd /tmp/releases-repo
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add -A
  git commit -m "Appcast: ${VERSION} build ${BUILD_NUMBER}"
  git push
  cd "$GITHUB_WORKSPACE"
fi
