#!/bin/bash
# 桌宠打包：Release 构建 → 捆 dozycat-sense → 签名 → （可选）公证 → dmg
#
# 有 Developer ID Application 证书时自动真签 + 加固运行时；配了 notarytool
# keychain profile（环境变量 DOZYCAT_NOTARY_PROFILE）时顺手公证 + 钉票。
# 什么都没有时退化为 ad-hoc 签名——本机可跑，分发会被 Gatekeeper 拦。
#
# 用法：scripts/package-dmg.sh [输出目录，默认 dist/]
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist}"
DERIVED="$(mktemp -d /tmp/dozycat-pkg.XXXXXX)"
mkdir -p "$OUT"

echo "==> dozycat-sense (release)"
(cd .. && cargo build --release -p dozycat-sense)
SENSE="../target/release/dozycat-sense"

echo "==> xcodegen + xcodebuild (Release)"
xcodegen generate >/dev/null
xcodebuild -project DozycatPet.xcodeproj -scheme DozycatPet -configuration Release \
  -derivedDataPath "$DERIVED" build 2>&1 | grep -E "error|warning: Code|BUILD" || true
APP="$DERIVED/Build/Products/Release/DozycatPet.app"
[ -d "$APP" ] || { echo "构建失败：$APP 不存在"; exit 1; }

echo "==> 捆入 dozycat-sense"
cp "$SENSE" "$APP/Contents/Resources/dozycat-sense"
chmod +x "$APP/Contents/Resources/dozycat-sense"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"

if [ -n "$IDENTITY" ]; then
  echo "==> 签名：$IDENTITY（hardened runtime）"
  codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" "$APP/Contents/Resources/dozycat-sense"
  codesign --force --deep --timestamp --options runtime \
    --sign "$IDENTITY" "$APP"
else
  echo "==> 没找到 Developer ID Application 证书，ad-hoc 签名（仅本机可跑）"
  echo "    补证书：Xcode → Settings → Accounts → Manage Certificates →"
  echo "    + → Developer ID Application（需要账号 Holder），然后重跑本脚本"
  codesign --force --sign - "$APP/Contents/Resources/dozycat-sense"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "    签名校验通过"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
DMG="$OUT/dozycat-$VERSION.dmg"

echo "==> 打 dmg：$DMG"
STAGE="$(mktemp -d /tmp/dozycat-dmg.XXXXXX)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "dozycat 懒猫" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [ -n "${DOZYCAT_NOTARY_PROFILE:-}" ]; then
    echo "==> 公证（profile: $DOZYCAT_NOTARY_PROFILE）"
    xcrun notarytool submit "$DMG" --keychain-profile "$DOZYCAT_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "    公证完成，票已钉进 dmg"
  else
    echo "==> 跳过公证（设 DOZYCAT_NOTARY_PROFILE 后自动公证：）"
    echo "    xcrun notarytool store-credentials <名字> --apple-id 你的AppleID --team-id 团队ID --password app专用密码"
  fi
fi

rm -rf "$DERIVED"
echo "==> 完成：$DMG"
du -h "$DMG"
