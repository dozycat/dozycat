#!/bin/bash
# 保留 build/ 路径兼容性，实际产物放在 Spotlight 不索引的目录。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -L "$PROJECT_DIR/build" ]; then
  [ "$(readlink "$PROJECT_DIR/build")" = build.noindex ] || {
    echo '错误：build 指向其他目录，请先检查。' >&2; exit 1;
  }
elif [ -e "$PROJECT_DIR/build" ]; then
  [ ! -e "$PROJECT_DIR/build.noindex" ] || {
    echo '错误：build 和 build.noindex 同时存在，请先合并。' >&2; exit 1;
  }
  mv "$PROJECT_DIR/build" "$PROJECT_DIR/build.noindex"
fi
mkdir -p "$PROJECT_DIR/build.noindex"
[ -L "$PROJECT_DIR/build" ] || ln -s build.noindex "$PROJECT_DIR/build"
