#!/bin/zsh
# 构建 dozycat-core → DozycatCore.xcframework + Swift 绑定。
# 产物：apps/ios/Vendor/DozycatCore.xcframework、apps/ios/Dozycat/Core/dozycat_core.swift
# 之后跑 `xcodegen generate` 即可。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CORE="$ROOT/core/dozycat-core"
IOS="$ROOT/apps/ios"
OUT="$CORE/target"
GEN="$OUT/uniffi-generated"

echo "▸ building rust (host cdylib for bindgen)"
cargo build --release --manifest-path "$CORE/Cargo.toml"

echo "▸ building rust (iOS device + simulator + macOS staticlibs)"
cargo build --release --manifest-path "$CORE/Cargo.toml" --target aarch64-apple-ios
cargo build --release --manifest-path "$CORE/Cargo.toml" --target aarch64-apple-ios-sim
cargo build --release --manifest-path "$CORE/Cargo.toml" --target aarch64-apple-darwin

echo "▸ generating swift bindings"
rm -rf "$GEN"
# 注意：uniffi-bindgen 的 library 模式会从「当前目录」跑 cargo metadata，
# 必须 cd 进 crate 所在 workspace，否则从任意目录调用本脚本会失败。
(cd "$CORE" && cargo run --release --bin uniffi-bindgen -- \
  generate --library "$OUT/release/libdozycat_core.dylib" \
  --language swift --out-dir "$GEN")

# xcframework 的每个 slice 要一个 headers 目录，modulemap 必须叫 module.modulemap
for slice in device sim mac; do
  mkdir -p "$GEN/include-$slice"
  cp "$GEN/dozycat_coreFFI.h" "$GEN/include-$slice/"
  cp "$GEN/dozycat_coreFFI.modulemap" "$GEN/include-$slice/module.modulemap"
done

echo "▸ packaging xcframework (ios + sim + macos)"
rm -rf "$IOS/Vendor/DozycatCore.xcframework"
mkdir -p "$IOS/Vendor"
xcodebuild -create-xcframework \
  -library "$OUT/aarch64-apple-ios/release/libdozycat_core.a" -headers "$GEN/include-device" \
  -library "$OUT/aarch64-apple-ios-sim/release/libdozycat_core.a" -headers "$GEN/include-sim" \
  -library "$OUT/aarch64-apple-darwin/release/libdozycat_core.a" -headers "$GEN/include-mac" \
  -output "$IOS/Vendor/DozycatCore.xcframework"

mkdir -p "$IOS/Dozycat/Core"
cp "$GEN/dozycat_core.swift" "$IOS/Dozycat/Core/dozycat_core.swift"

echo "✓ done: Vendor/DozycatCore.xcframework + Dozycat/Core/dozycat_core.swift"
