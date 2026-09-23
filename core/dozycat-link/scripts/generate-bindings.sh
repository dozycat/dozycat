#!/bin/sh
set -eu
LINK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$LINK_ROOT"
cargo build --locked
cargo run --locked --bin uniffi-bindgen -- generate \
  --library target/debug/libdozycat_link.dylib --language swift --language kotlin \
  --out-dir target/generated
