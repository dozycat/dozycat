#!/bin/bash
# 从 site/assets/icon.png（懒猫 logo，512px）重新生成 AppIcon asset catalog。
# logo 换了跑一次即可；产物进 git，打包脚本不依赖本脚本。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PROJECT_DIR/../../../site/assets/icon.png"
SET="$PROJECT_DIR/Assets/Assets.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "找不到 logo：$SRC" >&2; exit 1; }
mkdir -p "$SET"

for s in 16 32 128 256; do
  sips -z "$s" "$s" "$SRC" --out "$SET/icon_${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$SRC" --out "$SET/icon_${s}@2x.png" >/dev/null
done
# 源图 512px：512/512@2x 直接用原图，不上采样糊图
cp "$SRC" "$SET/icon_512.png"
cp "$SRC" "$SET/icon_512@2x.png"

cat > "$SET/Contents.json" <<'EOF'
{
  "images": [
    { "size": "16x16", "idiom": "mac", "scale": "1x", "filename": "icon_16.png" },
    { "size": "16x16", "idiom": "mac", "scale": "2x", "filename": "icon_16@2x.png" },
    { "size": "32x32", "idiom": "mac", "scale": "1x", "filename": "icon_32.png" },
    { "size": "32x32", "idiom": "mac", "scale": "2x", "filename": "icon_32@2x.png" },
    { "size": "128x128", "idiom": "mac", "scale": "1x", "filename": "icon_128.png" },
    { "size": "128x128", "idiom": "mac", "scale": "2x", "filename": "icon_128@2x.png" },
    { "size": "256x256", "idiom": "mac", "scale": "1x", "filename": "icon_256.png" },
    { "size": "256x256", "idiom": "mac", "scale": "2x", "filename": "icon_256@2x.png" },
    { "size": "512x512", "idiom": "mac", "scale": "1x", "filename": "icon_512.png" },
    { "size": "512x512", "idiom": "mac", "scale": "2x", "filename": "icon_512@2x.png" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
EOF
echo "已生成 $SET"
