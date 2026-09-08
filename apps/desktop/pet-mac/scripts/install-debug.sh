#!/bin/bash
# 开发版始终安装到同一个位置；中间产物不进入 Spotlight。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
"$SCRIPT_DIR/prepare-build-dir.sh"
cargo build --manifest-path "$PROJECT_DIR/../Cargo.toml" --locked -p dozycat-sense
cd "$PROJECT_DIR"
xcodegen generate
xcodebuild -project DozycatPet.xcodeproj -scheme DozycatPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PROJECT_DIR/build.noindex/DerivedData" \
  -clonedSourcePackagesDirPath "$PROJECT_DIR/build.noindex/SourcePackages" \
  -skipPackagePluginValidation -quiet build
APP="$PROJECT_DIR/build.noindex/DerivedData/Build/Products/Debug/dozycat-debug.app"
install -m 755 "$PROJECT_DIR/../target/debug/dozycat-sense" "$APP/Contents/Resources/dozycat-sense"
codesign --force --sign 'Developer ID Application' "$APP/Contents/Resources/dozycat-sense"
codesign --force --sign 'Developer ID Application' "$APP"
codesign --verify --deep --strict "$APP"
ditto "$APP" /Applications/dozycat-debug.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/dozycat-debug.app
mdimport /Applications/dozycat-debug.app
echo '已更新 /Applications/dozycat-debug.app'
