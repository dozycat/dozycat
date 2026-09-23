#!/bin/sh
set -eu
MOBILE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$MOBILE_ROOT/../.." && pwd)
LINK_ROOT="$REPO_ROOT/core/dozycat-link"
"$LINK_ROOT/scripts/build-apple.sh"
MODULE_OUT="$MOBILE_ROOT/modules/dozycat-link/ios"
mkdir -p "$MODULE_OUT/Generated" "$MODULE_OUT/Shared"
cp "$LINK_ROOT/target/generated/dozycat_link.swift" "$MODULE_OUT/Generated/"
cp "$LINK_ROOT/native/apple/LinkVault.swift" "$LINK_ROOT/native/apple/LinkCoordinator.swift" "$MODULE_OUT/Shared/"
rm -rf "$MODULE_OUT/dozycat_linkFFI.xcframework"
cp -R "$LINK_ROOT/target/apple/dozycat_linkFFI.xcframework" "$MODULE_OUT/"
