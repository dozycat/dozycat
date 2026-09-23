#!/bin/sh
set -eu
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export IPHONEOS_DEPLOYMENT_TARGET=16.4 MACOSX_DEPLOYMENT_TARGET=14.0
LINK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$LINK_ROOT"
LINK_PROFILE="${DOZYCAT_LINK_PROFILE:-dev}"
case "$LINK_PROFILE" in
  dev) LINK_OUTPUT=debug ;;
  release) LINK_OUTPUT=release ;;
  *) echo "Use DOZYCAT_LINK_PROFILE=dev or release" >&2; exit 2 ;;
esac
./scripts/generate-bindings.sh
for triple in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  cargo build --locked --lib --profile "$LINK_PROFILE" --target "$triple"
done
APPLE_OUT="$LINK_ROOT/target/apple"
# Framework slices isolate their headers; two raw static-library XCFrameworks both
# copy module.modulemap into Xcode's shared include directory and collide.
for triple in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  SLICE="$APPLE_OUT/$triple/dozycat_linkFFI.framework"
  mkdir -p "$SLICE/Headers" "$SLICE/Modules"
  cp "target/$triple/$LINK_OUTPUT/libdozycat_link.a" "$SLICE/dozycat_linkFFI"
  cp target/generated/dozycat_linkFFI.h "$SLICE/Headers/"
  cat > "$SLICE/Modules/module.modulemap" <<'MAP'
framework module dozycat_linkFFI {
  umbrella header "dozycat_linkFFI.h"
  export *
  module * { export * }
}
MAP
  case "$triple" in
    *darwin) PLATFORM=MacOSX; MINIMUM=14.0 ;;
    *sim) PLATFORM=iPhoneSimulator; MINIMUM=16.4 ;;
    *) PLATFORM=iPhoneOS; MINIMUM=16.4 ;;
  esac
  cat > "$SLICE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.paperboytm.dozycat.link.ffi</string>
<key>CFBundleName</key><string>dozycat_linkFFI</string>
<key>CFBundleExecutable</key><string>dozycat_linkFFI</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>MinimumOSVersion</key><string>$MINIMUM</string>
<key>CFBundleSupportedPlatforms</key><array><string>$PLATFORM</string></array>
</dict></plist>
PLIST
done
# Only generated build products are replaced.
rm -rf "$APPLE_OUT/dozycat_linkFFI.xcframework"
xcodebuild -create-xcframework \
  -framework "$APPLE_OUT/aarch64-apple-darwin/dozycat_linkFFI.framework" \
  -framework "$APPLE_OUT/aarch64-apple-ios/dozycat_linkFFI.framework" \
  -framework "$APPLE_OUT/aarch64-apple-ios-sim/dozycat_linkFFI.framework" \
  -output "$APPLE_OUT/dozycat_linkFFI.xcframework"
