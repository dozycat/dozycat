#!/bin/bash
# macOS 桌宠发布包：Release → 嵌入 helper → 签名 → DMG → 公证/钉票。
#
# 正式模式不会静默退化为 ad-hoc；缺少 Developer ID 或公证 profile 会直接失败。
# 仅验证构建链路时显式传 --adhoc，产物不能对外分发。
#
# 用法：
#   DOZYCAT_NOTARY_PROFILE=dozycat-notary \
#     DOZYCAT_NOTARY_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" \
#     scripts/package-dmg.sh
#   scripts/package-dmg.sh --adhoc
#   scripts/package-dmg.sh --skip-notarize --output dist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/../../.." && pwd)"
OUT="$PROJECT_DIR/dist"
MODE="release"
NOTARIZE=1
MIN_MACOS="14.0"
ARCH="arm64"
NOTARY_ARGS=()

usage() {
  sed -n '2,10p' "$0" | sed 's/^# *//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --adhoc)
      MODE="adhoc"
      NOTARIZE=0
      ;;
    --skip-notarize)
      NOTARIZE=0
      ;;
    --output)
      shift
      [ "$#" -gt 0 ] || { echo "错误：--output 需要目录" >&2; exit 2; }
      OUT="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$OUT" in
  /*) ;;
  *) OUT="$PROJECT_DIR/$OUT" ;;
esac

for tool in cargo xcodegen xcodebuild codesign hdiutil ditto shasum; do
  command -v "$tool" >/dev/null || { echo "错误：缺少命令 $tool" >&2; exit 2; }
done

IDENTITY="${DOZYCAT_CODESIGN_IDENTITY:-}"
if [ "$MODE" = "release" ]; then
  if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
  fi
  if [ -z "$IDENTITY" ]; then
    echo "错误：未找到 Developer ID Application 证书。" >&2
    echo "请先在 Xcode → Settings → Apple Accounts 登录并创建证书。" >&2
    echo "只验证本机构建可运行：scripts/package-dmg.sh --adhoc" >&2
    exit 2
  fi
  if [ "$NOTARIZE" -eq 1 ] && [ -z "${DOZYCAT_NOTARY_PROFILE:-}" ]; then
    echo "错误：正式发布需要 DOZYCAT_NOTARY_PROFILE。" >&2
    echo "只生成已签名、未公证的包可传 --skip-notarize（不建议对外分发）。" >&2
    exit 2
  fi
  if [ "$NOTARIZE" -eq 1 ]; then
    NOTARY_ARGS=(--keychain-profile "$DOZYCAT_NOTARY_PROFILE")
    if [ -n "${DOZYCAT_NOTARY_KEYCHAIN:-}" ]; then
      NOTARY_ARGS+=(--keychain "$DOZYCAT_NOTARY_KEYCHAIN")
    fi
  fi
else
  IDENTITY="-"
fi

DERIVED="$(mktemp -d /tmp/dozycat-pkg.XXXXXX)"
STAGE=""
cleanup() {
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
    rm -rf -- "$STAGE"
  fi
  if [ -d "$DERIVED" ]; then
    rm -rf -- "$DERIVED"
  fi
}
trap cleanup EXIT

mkdir -p "$OUT"
echo "==> 配置：$MODE / $ARCH / macOS $MIN_MACOS+"

echo "==> dozycat-sense (release)"
MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
  cargo build --manifest-path "$REPO_ROOT/apps/desktop/Cargo.toml" \
  --release -p dozycat-sense
SENSE="$REPO_ROOT/apps/desktop/target/release/dozycat-sense"

echo "==> dozycat-core (macOS $MIN_MACOS+)"
DOZYCAT_MACOS_DEPLOYMENT_TARGET="$MIN_MACOS" \
  "$REPO_ROOT/apps/ios/scripts/build-core.sh"

echo "==> xcodegen + xcodebuild (Release)"
cd "$PROJECT_DIR"
xcodegen generate >/dev/null
xcodebuild -project DozycatPet.xcodeproj -scheme DozycatPet -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -quiet build
APP="$DERIVED/Build/Products/Release/DozycatPet.app"
[ -d "$APP" ] || { echo "构建失败：$APP 不存在"; exit 1; }

echo "==> 捆入 dozycat-sense"
install -m 755 "$SENSE" "$APP/Contents/Resources/dozycat-sense"

if [ "$MODE" = "release" ]; then
  echo "==> 签名：${IDENTITY}（hardened runtime）"
  codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" "$APP/Contents/Resources/dozycat-sense"
  codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" "$APP"
else
  echo "==> ad-hoc 签名（仅用于本机验证）"
  codesign --force --sign - "$APP/Contents/Resources/dozycat-sense"
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
echo "    app 签名结构校验通过"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/dozycat-$VERSION-$ARCH.dmg"

echo "==> 打 dmg：$DMG"
STAGE="$(mktemp -d /tmp/dozycat-dmg.XXXXXX)"
ditto "$APP" "$STAGE/DozycatPet.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "dozycat 懒猫" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

if [ "$MODE" = "release" ]; then
  echo "==> 签名 dmg"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
  if [ "$NOTARIZE" -eq 1 ]; then
    echo "==> 公证（profile: ${DOZYCAT_NOTARY_PROFILE}）"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
    echo "    公证、钉票与 Gatekeeper 校验通过"
  else
    echo "警告：已按要求跳过公证；该包不适合对外分发。"
  fi
fi

echo "==> 完成：$DMG"
du -h "$DMG"
shasum -a 256 "$DMG"
