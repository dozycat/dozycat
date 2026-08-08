#!/bin/bash
# 从 iOS 的 1024px 主图重新生成 AppIcon asset catalog，桌面与手机保持同一张脸。
# logo 换了跑一次即可；产物进 git，打包脚本不依赖本脚本。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PROJECT_DIR/../../ios/Dozycat/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SET="$PROJECT_DIR/Assets/Assets.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "找不到 logo：$SRC" >&2; exit 1; }
mkdir -p "$SET"

for s in 16 32 128 256; do
  sips -z "$s" "$s" "$SRC" --out "$SET/icon_${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$SRC" --out "$SET/icon_${s}@2x.png" >/dev/null
done
# 512@1x 缩图，512@2x 保留 1024px 主图；避免 Asset Catalog 的尺寸警告。
sips -z 512 512 "$SRC" --out "$SET/icon_512.png" >/dev/null
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
