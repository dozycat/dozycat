#!/bin/bash
# Read-only checks for a new release Mac. Never create or print private keys.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
ok() { echo "✓ $*"; }
fail() { echo "✗ $*"; FAILED=1; }
for tool in cargo rustup xcodegen xcodebuild codesign hdiutil; do
  if command -v "$tool" >/dev/null; then ok "$tool"; else fail "缺少 $tool"; fi
done
if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then ok 'Xcode 初始化'; else fail '执行 xcodebuild -runFirstLaunch'; fi
if xcrun metal --version >/dev/null 2>&1; then ok 'Metal 编译器'; else fail '执行 xcodebuild -downloadComponent MetalToolchain'; fi
if xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then ok 'iOS SDK'; else fail '缺少 iOS SDK（共享内核需要）'; fi
if command -v rustup >/dev/null; then
  TARGETS="$(rustup target list --installed)"
  for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
    if echo "$TARGETS" | grep -qx "$target"; then ok "$target"; else fail "执行 rustup target add $target"; fi
  done
fi
if security find-identity -v -p codesigning | grep -q 'Developer ID Application:.*(PR5A8VMY8S)'; then
  ok 'Developer ID Application / PR5A8VMY8S'
else
  fail '未找到本项目的 Developer ID Application 证书及私钥'
fi
PROFILE="${DOZYCAT_NOTARY_PROFILE:-dozycat-notary}"
NOTARY_ARGS=(--keychain-profile "$PROFILE")
if [ -n "${DOZYCAT_NOTARY_KEYCHAIN:-}" ]; then NOTARY_ARGS+=(--keychain "$DOZYCAT_NOTARY_KEYCHAIN"); fi
if xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1; then
  ok "公证 profile: $PROFILE"
else
  fail "公证 profile 不可用: $PROFILE"
fi
KEY_TOOL=""
for cache in "$PROJECT_DIR/build/SourcePackages" "$HOME/Library/Developer/Xcode/DerivedData"; do
  [ -d "$cache" ] || continue
  KEY_TOOL="$(find "$cache" -type f -name generate_keys -print -quit)"
  [ -z "$KEY_TOOL" ] || break
done
if [ -n "$KEY_TOOL" ] && [ -x "$KEY_TOOL" ]; then
  EXPECTED="$(sed -n 's/.*SUPublicEDKey: //p' "$PROJECT_DIR/project.yml")"
  if PUBLIC_KEY="$("$KEY_TOOL" -p 2>/dev/null)" && [ "$PUBLIC_KEY" = "$EXPECTED" ]; then
    ok 'Sparkle 私钥对应项目公钥'
  else
    fail 'Sparkle 私钥缺失或与项目公钥不匹配；请迁移旧机器私钥'
  fi
else
  fail '尚无 Sparkle 工具；先执行 package-dmg.sh --adhoc'
fi
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  if [ "$(gh api repos/dozycat/dozycat --jq '.permissions.push' 2>/dev/null)" = "true" ]; then
    ok 'GitHub Release 写权限'
  else
    fail '当前 GitHub 账号没有 dozycat/dozycat 写权限'
  fi
else
  fail 'GitHub CLI 尚未安装或登录；执行 gh auth login'
fi
exit "$FAILED"
