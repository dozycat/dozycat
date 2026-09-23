#!/bin/sh
set -eu
LINK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$LINK_ROOT"
./scripts/generate-bindings.sh
swiftc -I target/generated -L target/debug -ldozycat_link \
  -Xcc -fmodule-map-file=target/generated/dozycat_linkFFI.modulemap \
  -Xlinker -rpath -Xlinker "$LINK_ROOT/target/debug" \
  target/generated/dozycat_link.swift native/apple/LinkVault.swift native/apple/LinkCoordinator.swift tests/native/main.swift \
  -o target/native-smoke
target/native-smoke

swiftc -parse-as-library -I target/generated -L target/debug -ldozycat_link \
  -Xcc -fmodule-map-file=target/generated/dozycat_linkFFI.modulemap \
  -Xlinker -rpath -Xlinker "$LINK_ROOT/target/debug" \
  target/generated/dozycat_link.swift native/apple/LinkVault.swift native/apple/LinkCoordinator.swift \
  tests/native/CoordinatorSmoke.swift -o target/coordinator-smoke
target/coordinator-smoke
