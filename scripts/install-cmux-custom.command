#!/bin/zsh
#
# install-cmux-custom.command
#
# Double-click this file to install the latest custom-built Cmux from the
# 'custom-latest' release of vichi7/cmux into /Applications/Cmux.app.
#
# Steps performed:
#   1. Download the latest custom-latest release zip from GitHub.
#   2. Verify sha256.
#   3. Unzip into a temp directory.
#   4. Strip quarantine and re-sign ad-hoc (survives curl/ditto round-trip).
#   5. Quit any running Cmux.
#   6. Replace /Applications/Cmux.app atomically.
#   7. Launch the new build.

set -euo pipefail

REPO="vichi7/cmux"
TAG="custom-latest"
ZIP_NAME="cmux-custom.zip"
SHA_NAME="cmux-custom.zip.sha256"
DEST="/Applications/Cmux.app"
TMP="$(mktemp -d -t cmux-custom-install)"

red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue()   { printf '\033[34m%s\033[0m\n' "$*"; }

trap 'rm -rf "$TMP"' EXIT

blue "==> Installing Cmux (custom build) from $REPO @ $TAG"
blue "==> Workspace: $TMP"

# 1. Prefer gh if authenticated; fall back to curl via public release download URL.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  blue "==> Downloading via gh"
  gh release download "$TAG" --repo "$REPO" --dir "$TMP" --pattern "$ZIP_NAME" --pattern "$SHA_NAME"
else
  blue "==> Downloading via curl (public release)"
  BASE="https://github.com/$REPO/releases/download/$TAG"
  curl -fsSL -o "$TMP/$ZIP_NAME" "$BASE/$ZIP_NAME"
  curl -fsSL -o "$TMP/$SHA_NAME" "$BASE/$SHA_NAME"
fi

# 2. Verify sha256. The sha file contains "<hash>  <filename>" as produced by
#    `shasum -a 256`, so shasum -c handles it directly.
blue "==> Verifying sha256"
(cd "$TMP" && shasum -a 256 -c "$SHA_NAME") || { red "sha256 mismatch — aborting"; exit 1; }
green "    sha256 OK"

# 3. Unzip into temp.
blue "==> Unzipping"
ditto -xk "$TMP/$ZIP_NAME" "$TMP/unpack"
NEW_APP="$(find "$TMP/unpack" -maxdepth 2 -name '*.app' -type d | head -n 1)"
if [ -z "${NEW_APP:-}" ]; then
  red "Could not find .app in downloaded zip"; exit 1
fi
green "    extracted: $NEW_APP"

# 4. Strip quarantine and re-sign ad-hoc.
blue "==> Stripping quarantine + re-signing"
xattr -cr "$NEW_APP"
codesign --force --deep --sign - "$NEW_APP" >/dev/null 2>&1 || true
codesign --verify --deep --strict "$NEW_APP"
green "    signature valid"

# 5. Quit any running Cmux. Use bundle ID so we catch both the Dock app and
#    any background-only instance.
blue "==> Quitting running Cmux (if any)"
osascript -e 'tell application id "com.cmuxterm.app" to quit' 2>/dev/null || true
# Give it a moment to exit cleanly; SIGTERM anything still alive after.
for i in 1 2 3 4 5; do
  if ! pgrep -f "Cmux.app/Contents/MacOS/cmux" >/dev/null; then break; fi
  sleep 0.5
done
pkill -f "Cmux.app/Contents/MacOS/cmux" 2>/dev/null || true
sleep 0.5

# 6. Replace /Applications/Cmux.app atomically via backup + move.
#    /Applications is group-writable by admin users, so no sudo needed here.
blue "==> Installing to $DEST"
if [ -e "$DEST" ]; then
  BACKUP="$DEST.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$DEST" "$BACKUP"
  yellow "    previous Cmux moved to $BACKUP"
fi
ditto "$NEW_APP" "$DEST"
xattr -cr "$DEST"
green "    installed"

# 7. Strip com.apple.provenance so Gatekeeper doesn't block launch of the
#    ad-hoc-signed bundle. Provenance is kernel-protected and requires root
#    to remove. This is the one prompt you'll see per install; everything
#    above runs as $USER.
blue "==> Stripping com.apple.provenance (requires sudo password)"
if sudo xattr -rd com.apple.provenance "$DEST" 2>/dev/null; then
  green "    provenance stripped"
else
  yellow "    sudo failed — Gatekeeper may block launch."
  yellow "    Workaround: right-click $DEST in Finder and click Open."
fi

# 8. Launch.
blue "==> Launching"
open "$DEST"
green "==> Done. Custom Cmux is now your /Applications/Cmux.app."

echo ""
echo "Tip: old backups accumulate in /Applications as Cmux.app.backup-<ts>."
echo "     Remove them when you trust the new build:"
echo "       sudo rm -rf /Applications/Cmux.app.backup-*"
