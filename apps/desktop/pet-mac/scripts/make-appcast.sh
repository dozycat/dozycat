#!/bin/bash
# Generate + EdDSA-sign appcast.xml from the dmg in dist/, write to site/appcast.xml.
# Update packages are signed with the private key in the keychain (from generate_keys);
# download URLs point at GitHub Releases. Run after package-dmg.sh; commit site/appcast.xml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/../../.." && pwd)"
DIST="$PROJECT_DIR/dist"
SITE="$REPO_ROOT/site"
DL_PREFIX="${DOZYCAT_DL_PREFIX:-https://github.com/dozycat/dozycat/releases/latest/download/}"

[ -d "$DIST" ] || { echo "no dist/, run scripts/package-dmg.sh first" >&2; exit 1; }

GA="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Sparkle*/bin/generate_appcast' 2>/dev/null | head -1)"
[ -x "$GA" ] || { echo "generate_appcast not found (build once to fetch Sparkle)" >&2; exit 1; }

echo "==> sign appcast (download prefix: $DL_PREFIX)"
"$GA" --download-url-prefix "$DL_PREFIX" -o "$SITE/appcast.xml" "$DIST"
echo "==> appcast -> $SITE/appcast.xml"
