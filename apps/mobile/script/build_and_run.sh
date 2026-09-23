#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

show_usage() {
  cat <<'USAGE'
Usage: ./script/build_and_run.sh [mode]
  start           Start Expo Go on the local network (default)
  --ios           Open iOS simulator with Expo Go
  --android       Open Android with Expo Go
  --web           Start the web preview
  --build-ios     Prepare native pairing and build the iOS development app
  --dev-client    Start a separately installed development build
  --tunnel        Start Expo Go via a tunnel
  --export-web    Export the web preview locally
  --help          Show this help
USAGE
}

if [[ "${1:-}" == "--help" ]]; then
  show_usage
  exit 0
fi

# Codex Desktop can supply Node even when the shell has no Node installation.
if ! command -v node >/dev/null 2>&1; then
  CODEX_NODE_DIR="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin"
  if [[ -x "$CODEX_NODE_DIR/node" ]]; then
    export PATH="$CODEX_NODE_DIR:$PATH"
  else
    echo 'Install Node.js LTS, then run npm ci in apps/mobile.' >&2
    exit 1
  fi
fi

if [[ -f node_modules/expo/bin/cli ]]; then
  EXPO_COMMAND=(node node_modules/expo/bin/cli)
elif command -v npx >/dev/null 2>&1; then
  EXPO_COMMAND=(npx --no-install expo)
else
  echo 'Dependencies missing. Run npm ci in apps/mobile first.' >&2
  exit 1
fi

case "${1:-start}" in
  start) exec "${EXPO_COMMAND[@]}" start --go ;;
  --ios) exec "${EXPO_COMMAND[@]}" start --go --ios ;;
  --android) exec "${EXPO_COMMAND[@]}" start --go --android ;;
  --web) exec "${EXPO_COMMAND[@]}" start --web ;;
  --build-ios)
    ./scripts/prepare-link-apple.sh
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    "${EXPO_COMMAND[@]}" prebuild --platform ios --no-install
    exec "${EXPO_COMMAND[@]}" run:ios ;;
  --dev-client) exec "${EXPO_COMMAND[@]}" start --dev-client ;;
  --tunnel) exec "${EXPO_COMMAND[@]}" start --go --tunnel ;;
  --export-web) exec "${EXPO_COMMAND[@]}" export --platform web ;;
  *) show_usage >&2; exit 2 ;;
esac
