#!/usr/bin/env python3
"""Turn the Markdown posts declared in site/blog/posts.json into static pages."""

from __future__ import annotations

import html
import json
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


SITE_DIR = Path(__file__).resolve().parents[1]
BLOG_DIR = SITE_DIR / "blog"
MANIFEST_PATH = BLOG_DIR / "posts.json"


@dataclass(frozen=True)
class Post:
    slug: str
    source: Path
    category: str
    date: str
    description: str
    title: str
    markdown: str
    reading_minutes: int

    @property
    def display_date(self) -> str:
        return datetime.strptime(self.date, "%Y-%m-%d").strftime("%Y.%m.%d")


def inline_markdown(value: str) -> str:
    """Render the small inline Markdown subset used by the project's posts."""
    tokens: list[str] = []

    def hold(rendered: str) -> str:
        tokens.append(rendered)
        return f"\x00{len(tokens) - 1}\x00"

    value = re.sub(
        r"`([^`]+)`",
        lambda match: hold(f"<code>{html.escape(match.group(1))}</code>"),
        value,
    )
    value = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda match: hold(
            f'<a href="{html.escape(match.group(2), quote=True)}">'
            f"{inline_markdown(match.group(1))}</a>"
        ),
        value,
    )
    value = html.escape(value)
    value = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", value)
    value = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", value)
    value = value.replace("  \n", "<br>\n")

    for index, rendered in enumerate(tokens):
        value = value.replace(f"\x00{index}\x00", rendered)
    return value


def join_wrapped_lines(lines: list[str]) -> str:
    result = ""
    for raw_line in lines:
        line = raw_line.strip()
        if not result:
            result = line
            continue
        if result.endswith("  "):
            result += "\n" + line
            continue
        previous = result[-1]
        following = line[0] if line else ""
        if re.match(r"[A-Za-z0-9)]", previous) and re.match(r"[A-Za-z0-9(]", following):
            result += " " + line
        else:
            result += line
    return result


def markdown_to_html(markdown: str) -> tuple[str, str]:
    lines = markdown.splitlines()
    title = ""
    blocks: list[str] = []
    paragraph: list[str] = []
    code_lines: list[str] = []
    code_language = ""
    in_code = False
    list_type: str | None = None
    list_items: list[str] = []
    section_index = 0

    def flush_paragraph() -> None:
        if paragraph:
            value = join_wrapped_lines(paragraph)
            blocks.append(f"<p>{inline_markdown(value)}</p>")
            paragraph.clear()

    def flush_list() -> None:
        nonlocal list_type
        if list_type and list_items:
            items = "".join(f"<li>{inline_markdown(item)}</li>" for item in list_items)
            blocks.append(f"<{list_type}>{items}</{list_type}>")
        list_type = None
        list_items.clear()

    for line in lines + [""]:
        fence = re.match(r"^```\s*([\w+-]*)\s*$", line)
        if fence:
            if in_code:
                language_class = (
                    f' class="language-{html.escape(code_language, quote=True)}"'
                    if code_language
                    else ""
                )
                blocks.append(
                    f"<pre><code{language_class}>{html.escape(chr(10).join(code_lines))}</code></pre>"
                )
                code_lines.clear()
                code_language = ""
                in_code = False
            else:
                flush_paragraph()
                flush_list()
                code_language = fence.group(1)
                in_code = True
            continue

        if in_code:
            code_lines.append(line)
            continue

        heading = re.match(r"^(#{1,3})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            flush_list()
            level = len(heading.group(1))
            heading_text = heading.group(2).strip()
            if level == 1 and not title:
                title = re.sub(r"[*_`]", "", heading_text)
                continue
            section_index += 1
            blocks.append(
                f'<h{level} id="section-{section_index}">{inline_markdown(heading_text)}</h{level}>'
            )
            continue

        unordered = re.match(r"^\s*[-*+]\s+(.+)$", line)
        ordered = re.match(r"^\s*\d+[.)]\s+(.+)$", line)
        if unordered or ordered:
            flush_paragraph()
            incoming_type = "ul" if unordered else "ol"
            if list_type and list_type != incoming_type:
                flush_list()
            list_type = incoming_type
            list_items.append((unordered or ordered).group(1))
            continue

        if re.match(r"^\s*(?:---+|\*\*\*+)\s*$", line):
            flush_paragraph()
            flush_list()
            blocks.append("<hr>")
            continue

        if not line.strip():
            flush_paragraph()
            flush_list()
            continue

        paragraph.append(line)

    if not title:
        raise ValueError("Every blog post needs a level-one Markdown heading")
    return title, "\n".join(blocks)


def word_count(markdown: str) -> int:
    without_code = re.sub(r"```.*?```", "", markdown, flags=re.DOTALL)
    cjk = len(re.findall(r"[\u3400-\u9fff]", without_code))
    latin_words = len(re.findall(r"\b[A-Za-z0-9][A-Za-z0-9_-]*\b", without_code))
    return cjk + latin_words


def page_head(title: str, description: str, stylesheet: str) -> str:
    escaped_title = html.escape(title)
    escaped_description = html.escape(description, quote=True)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escaped_title}</title>
<meta name="description" content="{escaped_description}">
<meta property="og:title" content="{escaped_title}">
<meta property="og:description" content="{escaped_description}">
<link rel="icon" type="image/png" href="{stylesheet}assets/icon.png">
<link rel="apple-touch-icon" href="{stylesheet}assets/icon.png">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@300;400;500;700&family=Noto+Serif+SC:wght@400;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{stylesheet}style.css">
</head>"""


def cat_logo(home_href: str) -> str:
    return f"""<a class="logo logo-cn" href="{home_href}" aria-label="回到懒猫君首页">
    <span class="cat cat-mini" aria-hidden="true">
      <span class="ear ear-l"></span>
      <span class="ear ear-r"></span>
      <span class="head">
        <span class="eye eye-l"></span>
        <span class="eye eye-r"></span>
      </span>
    </span>
    懒猫君<span class="dot">。</span>
  </a>"""


def blog_nav(home_href: str, blog_href: str) -> str:
    return f"""<nav class="nav blog-site-nav">
  {cat_logo(home_href)}
  <div class="nav-links">
    <a href="{home_href}">小传</a>
    <a class="nav-blog active" href="{blog_href}">手记</a>
    <a class="btn btn-ink" href="https://github.com/dozycat/dozycat/releases/latest/download/dozycat-0.1.1-arm64.dmg">领养一只懒猫</a>
  </div>
</nav>"""


def blog_footer(home_href: str, blog_href: str) -> str:
    return f"""<footer class="footer">
  <div class="footer-inner">
    <span>懒猫君 · dozycat © 2026</span>
    <span class="footer-links">
      <a href="{home_href}">小传</a>
      <a href="{blog_href}">手记</a>
      <a href="https://github.com/dozycat/dozycat">GitHub</a>
    </span>
  </div>
</footer>"""


def render_index(posts: list[Post]) -> str:
    cards: list[str] = []
    for post in posts:
        cards.append(
            f"""<article class="blog-card">
      <a class="blog-card-link" href="{html.escape(post.slug)}/">
        <span class="blog-card-visual" aria-hidden="true">
          <span class="signal signal-mind"><i style="width:72%"></i></span>
          <span class="signal signal-body"><i style="width:45%"></i></span>
          <span class="signal-caption">72&nbsp;&nbsp;·&nbsp;&nbsp;45</span>
        </span>
        <span class="blog-card-copy">
          <span class="article-meta">{html.escape(post.category)} · {post.display_date} · {post.reading_minutes} 分钟</span>
          <span class="blog-card-title">{html.escape(post.title)}</span>
          <span class="blog-card-description">{html.escape(post.description)}</span>
        </span>
        <span class="blog-card-arrow" aria-hidden="true">↗</span>
      </a>
    </article>"""
        )

    return f"""{page_head('懒猫手记 — 懒猫君', '懒猫君的产品、设计与生活观察。', '../')}
<body class="blog-page">
{blog_nav('../', './')}
<main class="blog-index">
  <header class="blog-index-hero">
    <div class="kicker">懒猫手记 · 偶尔更新</div>
    <h1>把猫是怎么想的，<br>慢慢写下来。</h1>
    <p>关于感知、记忆和陪伴，也关于我们为什么这样做。这里不赶连载，想明白一件，就写一件。</p>
  </header>
  <section class="blog-list" aria-label="全部手记">
    {''.join(cards)}
  </section>
</main>
{blog_footer('../', './')}
</body>
</html>
"""


def render_post(post: Post, body_html: str) -> str:
    return f"""{page_head(f'{post.title} — 懒猫手记', post.description, '../../')}
<body class="blog-page article-page">
{blog_nav('../../', '../')}
<main>
  <article class="blog-article">
    <header class="article-hero">
      <a class="article-back" href="../">← 返回全部手记</a>
      <div class="article-meta">{html.escape(post.category)} · {post.display_date} · {post.reading_minutes} 分钟</div>
      <h1>{html.escape(post.title)}</h1>
      <p class="article-dek">{html.escape(post.description)}</p>
      <div class="article-energy" aria-hidden="true">
        <span><i class="article-energy-mind" style="width:72%"></i></span>
        <span><i class="article-energy-body" style="width:45%"></i></span>
      </div>
    </header>
    <div class="markdown-body">
{body_html}
    </div>
    <footer class="article-end">
      <span class="article-end-mark">完</span>
      <p>累了就先到这里。站起来接杯水，猫替你守着这一页。</p>
      <a href="../">再读一篇手记 →</a>
    </footer>
  </article>
</main>
{blog_footer('../../', '../')}
</body>
</html>
"""


def load_posts() -> list[tuple[Post, str]]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    posts: list[tuple[Post, str]] = []
    for item in manifest:
        source = (BLOG_DIR / item["source"]).resolve()
        markdown = source.read_text(encoding="utf-8")
        title, body_html = markdown_to_html(markdown)
        post = Post(
            slug=item["slug"],
            source=source,
            category=item["category"],
            date=item["date"],
            description=item["description"],
            title=title,
            markdown=markdown,
            reading_minutes=max(1, round(word_count(markdown) / 400)),
        )
        posts.append((post, body_html))
    return sorted(posts, key=lambda item: item[0].date, reverse=True)


def main() -> None:
    rendered_posts = load_posts()
    BLOG_DIR.mkdir(parents=True, exist_ok=True)
    (BLOG_DIR / "index.html").write_text(
        render_index([post for post, _ in rendered_posts]), encoding="utf-8"
    )
    for post, body_html in rendered_posts:
        output_dir = BLOG_DIR / post.slug
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "index.html").write_text(
            render_post(post, body_html), encoding="utf-8"
        )
    print(f"Built {len(rendered_posts)} blog post(s) in {BLOG_DIR}")


if __name__ == "__main__":
    main()
