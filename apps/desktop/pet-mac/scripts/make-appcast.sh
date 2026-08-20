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
DL_PREFIX="${DOZYCAT_DL_PREFIX:-https://github.com/dozycat/dozycat/releases/download/__VERSION__/}"

[ -d "$DIST" ] || { echo "no dist/, run scripts/package-dmg.sh first" >&2; exit 1; }
case "$DL_PREFIX" in
  *__VERSION__*) ;;
  *)
    echo "DOZYCAT_DL_PREFIX must contain __VERSION__ so historical releases stay pinned to their tag" >&2
    exit 1
    ;;
esac

GA="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Sparkle*/bin/generate_appcast' 2>/dev/null | head -1)"
[ -x "$GA" ] || { echo "generate_appcast not found (build once to fetch Sparkle)" >&2; exit 1; }

echo "==> sign appcast (download prefix: $DL_PREFIX)"
"$GA" --download-url-prefix "$DL_PREFIX" -o "$SITE/appcast.xml" "$DIST"

# generate_appcast 只接受一个公共下载前缀。先用占位符签名生成，再按每个
# item 的 shortVersionString 固定到对应 GitHub tag；否则 releases/latest 会在
# 下一版发布后让全部历史 URL 指向错误的 release。
APPCAST_TMP="$(mktemp "$SITE/appcast.xml.XXXXXX")"
trap 'rm -f "$APPCAST_TMP"' EXIT
awk -v template="$DL_PREFIX" '
  /<sparkle:shortVersionString>/ {
    version = $0
    sub(/^.*<sparkle:shortVersionString>/, "", version)
    sub(/<\/sparkle:shortVersionString>.*$/, "", version)
  }
  /<enclosure url=/ {
    if (version == "") {
      print "appcast enclosure appears before its version" > "/dev/stderr"
      exit 1
    }
    resolved_prefix = template
    gsub(/__VERSION__/, version, resolved_prefix)
    asset = $0
    sub(/^.*url="/, "", asset)
    sub(/".*$/, "", asset)
    sub(/^.*\//, "", asset)
    before_url = $0
    sub(/url=".*/, "url=\"", before_url)
    after_url = $0
    sub(/^.*url="[^"]*"/, "", after_url)
    $0 = before_url resolved_prefix asset "\"" after_url
  }
  { print }
' "$SITE/appcast.xml" > "$APPCAST_TMP"
mv "$APPCAST_TMP" "$SITE/appcast.xml"
trap - EXIT

# 每个 item（包括 delta）必须留在自己的 tag，主包文件名也必须匹配版本。
if ! awk -v template="$DL_PREFIX" '
  /<sparkle:shortVersionString>/ {
    version = $0
    sub(/^.*<sparkle:shortVersionString>/, "", version)
    sub(/<\/sparkle:shortVersionString>.*$/, "", version)
  }
  /<enclosure url=/ {
    expected_prefix = template
    gsub(/__VERSION__/, version, expected_prefix)
    if (index($0, expected_prefix) == 0) {
      print "appcast mismatch: version " version " is not pinned to " expected_prefix > "/dev/stderr"
      exit 1
    }
    if ($0 !~ /sparkle:deltaFrom=/) {
      expected_file = "dozycat-" version "-arm64.dmg"
      if (index($0, expected_file) == 0) {
        print "appcast mismatch: version " version " does not point to " expected_file > "/dev/stderr"
        exit 1
      }
    }
  }
' "$SITE/appcast.xml"; then
  echo "错误：appcast tag、版本或文件名不一致。" >&2
  exit 1
fi

# 官网按钮使用 releases/latest，但文件名仍带版本号；漏改会在新 release 成为
# Latest 的瞬间全部 404。发布前把 HTML 与博客模板里的旧版本一并拦住。
LATEST_VERSION="$(awk '
  /<sparkle:shortVersionString>/ {
    version = $0
    sub(/^.*<sparkle:shortVersionString>/, "", version)
    sub(/<\/sparkle:shortVersionString>.*$/, "", version)
    print version
    exit
  }
' "$SITE/appcast.xml")"
[ -n "$LATEST_VERSION" ] || { echo "错误：appcast 没有版本号。" >&2; exit 1; }
STALE_DOWNLOADS="$({
  find "$SITE" -type f \( -name '*.html' -o -name '*.py' \) \
    -exec grep -nHE 'releases/latest/download/dozycat-[0-9]+\.[0-9]+\.[0-9]+-arm64\.dmg' {} +
} | grep -v "dozycat-${LATEST_VERSION}-arm64.dmg" || true)"
if [ -n "$STALE_DOWNLOADS" ]; then
  echo "错误：官网仍有旧版本下载链接（当前 appcast 是 $LATEST_VERSION）：" >&2
  echo "$STALE_DOWNLOADS" >&2
  exit 1
fi

echo "==> appcast -> $SITE/appcast.xml"
