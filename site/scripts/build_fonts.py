#!/usr/bin/env python3
"""Subset Noto Sans SC and Noto Serif SC to the characters the site uses.

    python3 site/scripts/build_fonts.py <directory with NotoSansSC.ttf and NotoSerifSC.ttf>

The sources are the variable fonts from github.com/google/fonts (ofl/notosanssc,
ofl/notoserifsc; SIL Open Font License). Needs `pip install fonttools brotli`.
Writes site/assets/fonts/*.woff2 and charset.txt. Run it again when build_blog.py
reports characters that the fonts do not cover.
"""

from __future__ import annotations

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SITE_DIR = Path(__file__).resolve().parents[1]
FONT_DIR = SITE_DIR / "assets" / "fonts"
CHARSET_PATH = FONT_DIR / "charset.txt"
# Always kept, whatever the pages contain: ASCII, Latin-1, and common CJK punctuation.
BASE = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "".join(chr(c) for c in range(0xA0, 0x100))
    + "–—‘’“”…·•×÷→←↑↓≈≤≥°′″±−✓"
    + "、。〈〉《》「」『』【】〔〕！（），：；？～￥％"
)
# family file, source file, weight range kept
FAMILIES = (
    ("noto-sans-sc", "NotoSansSC.ttf", (300, 700)),
    ("noto-serif-sc", "NotoSerifSC.ttf", (400, 600)),
)


def site_characters() -> str:
    """Every character that appears in the site's pages, posts, diagrams and styles."""
    chars = set(BASE)
    for pattern in ("*.html", "*.md", "*.css", "*.json"):
        for path in SITE_DIR.rglob(pattern):
            chars.update(path.read_text(encoding="utf-8"))
    return "".join(sorted(c for c in chars if c.isprintable() and c != " ")) + " "


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source_dir = Path(sys.argv[1])
    chars = site_characters()
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    for name, source, (low, high) in FAMILIES:
        font = TTFont(source_dir / source)
        options = subset.Options()
        options.flavor = "woff2"
        options.layout_features = ["*"]
        options.drop_tables += ["DSIG"]
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=chars)
        subsetter.subset(font)
        font = instancer.instantiateVariableFont(font, {"wght": (low, high)})
        target = FONT_DIR / f"{name}.woff2"
        font.flavor = "woff2"
        font.save(target)
        print(f"{target.relative_to(SITE_DIR)}  {target.stat().st_size / 1024:.0f} KB")
    CHARSET_PATH.write_text(chars, encoding="utf-8")
    print(f"{len(chars)} characters")


if __name__ == "__main__":
    main()
