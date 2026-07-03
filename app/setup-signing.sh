#!/usr/bin/env bash
# One-time setup: create a self-signed code-signing certificate named
# "GeorgesWords Dev" in your login keychain. Once it exists, build.sh signs
# every build with it, so macOS sees each rebuild as the SAME app and your
# Accessibility/Microphone grants survive rebuilds.
#
# Usage: ./app/setup-signing.sh   (on your Mac; run once)
set -euo pipefail

IDENTITY="GeorgesWords Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' already exists — nothing to do."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Generating a self-signed code-signing certificate (valid 10 years)"
openssl req -x509 -newkey rsa:2048 \
  -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
  -days 3650 -nodes -subj "/CN=$IDENTITY" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

echo "==> Importing into your login keychain"
# Import key and cert as separate PEMs — PKCS12 bundles from modern OpenSSL
# use algorithms macOS's keychain importer rejects ("MAC verification failed").
security import "$TMP_DIR/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$TMP_DIR/cert.pem" -k "$KEYCHAIN"

echo "==> Marking it trusted for code signing (macOS will ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"

cat <<EOF

Done. From now on, ./app/build.sh signs with '$IDENTITY'.

Two one-time things to know:
  1. The FIRST build after this needs one last Accessibility re-grant
     (the signature changed from ad-hoc to this certificate). After that,
     rebuilds keep the permission.
  2. On the first signed build, macOS may show a dialog that codesign
     "wants to sign using key ... in your keychain" — click Always Allow.

If anything above failed, the GUI route does the same thing:
  Keychain Access → Certificate Assistant → Create a Certificate…
  Name: $IDENTITY | Identity Type: Self-Signed Root | Certificate Type: Code Signing
EOF
