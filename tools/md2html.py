# -*- coding: utf-8 -*-
"""把 stage1 的 Markdown 转成 doc-formatter 契约要求的单文件 HTML（封面 + 目录 + 正文）。

用法：
  python _md2html.py <md> <out.html> <文档标题> <副标题>
按 doc-formatter §2.5 的硬要求输出：宋体 / 12pt / 首行缩进 2em / h1~h3 标题 / 表格规范 /
页面级规则写在 <style> 里（封面命名页、正文页码从 1 起）。
"""
import html
import io
import re
import sys

ACCENT = "#1f4e79"
ACCENT_LIGHT = "#e8eef7"
BORDER = "#c8d2e0"

CSS = """
:root{
  --accent:__ACCENT__; --accent-light:__ACCENT_LIGHT__; --border:__BORDER__;
}
*{box-sizing:border-box;}
body{
  font-family:"SimSun","宋体",serif; font-size:12pt; line-height:1.65; color:#000;
  margin:0;
}
section.cover{padding:0;}
.cover-wrap{
  min-height:70vh; padding:3.2cm 2.4cm; display:flex; flex-direction:column; justify-content:center;
  border-top:6pt solid var(--accent);
}
.cover-kicker{font-family:"SimHei","黑体",sans-serif;font-size:11pt;letter-spacing:0.18em;color:var(--accent);margin-bottom:1.2em;}
.cover-title{font-family:"SimHei","黑体",sans-serif;font-size:30pt;font-weight:bold;line-height:1.35;color:#111;margin-bottom:0.6em;}
.cover-sub{font-size:14pt;color:#555;margin-bottom:2.2em;}
.cover-meta{font-size:10.5pt;color:#666;line-height:2;}
.cover-rule{height:2pt;width:120pt;background:var(--accent);margin:1.6em 0;}
.toc-title{font-family:"SimHei","黑体",sans-serif;font-size:18pt;font-weight:bold;color:var(--accent);margin:0 0 1em 0;}
.toc-list,.toc-list ol{list-style:none;padding-left:0;margin:0;}
.toc-list>li{margin:0.42em 0;font-size:12pt;}
.toc-list ol>li{margin:0.2em 0 0.2em 1.6em;font-size:11pt;color:#444;}
.toc-list a{color:#000;text-decoration:none;}
h1{
  font-family:"SimHei","黑体",sans-serif;font-size:17pt;font-weight:bold;color:#fff;
  background:var(--accent);padding:8pt 12pt;margin:1.6em 0 0.9em 0;
  page-break-after:avoid;
}
h2{
  font-family:"SimHei","黑体",sans-serif;font-size:13.5pt;font-weight:bold;color:var(--accent);
  border-left:4pt solid var(--accent);padding-left:8pt;margin:1.3em 0 0.6em 0;
  page-break-after:avoid;
}
h3{
  font-family:"SimHei","黑体",sans-serif;font-size:12pt;font-weight:bold;color:#222;margin:1em 0 0.5em 0;
  page-break-after:avoid;
}
p{margin:0 0 0.55em 0;text-indent:2em;text-align:justify;}
ul,ol{margin:0.4em 0 0.8em 0;padding-left:2.2em;}
li{margin:0.22em 0;font-size:12pt;line-height:1.6;}
table{border-collapse:collapse;width:100%;margin:0.7em 0 1em 0;font-size:10.5pt;}
th{background:var(--accent-light);font-family:"SimHei","黑体",sans-serif;font-weight:bold;
   border:0.75pt solid var(--border);padding:5pt 6pt;text-align:left;font-size:10.5pt;}
td{border:0.75pt solid var(--border);padding:4pt 6pt;vertical-align:top;font-size:10.5pt;line-height:1.5;}
.note{border-left:4pt solid var(--accent);background:var(--accent-light);
      padding:8pt 12pt;margin:0.8em 0 1em 0;font-size:10.5pt;color:#333;line-height:1.6;}
.note p{text-indent:0;margin:0;}
code{font-family:"Consolas","Courier New",monospace;font-size:10pt;background:#f2f4f7;padding:0 2pt;}
strong{font-weight:bold;}
"""


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return text


def parse(md: str):
    """返回 (title, blocks)。block = dict(type, ...)"""
    lines = md.split("\n")
    blocks = []
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line.strip():
            i += 1
            continue
        if line.startswith("# "):
            i += 1
            continue  # 标题由调用方传入，正文里跳过
        if line.startswith("## "):
            blocks.append({"type": "h1", "text": line[3:].strip()})
            i += 1
            continue
        if line.startswith("### "):
            blocks.append({"type": "h2", "text": line[4:].strip()})
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                raw = lines[i].strip().strip("|")
                cells = [c.strip() for c in raw.split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c.replace(" ", "")) for c in cells):
                    rows.append(cells)
                i += 1
            blocks.append({"type": "table", "rows": rows})
            continue
        if line.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            blocks.append({"type": "note", "text": " ".join(buf)})
            continue
        if re.match(r"^\s*[-*] ", line):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*] ", lines[i]):
                items.append(re.sub(r"^\s*[-*] ", "", lines[i]).strip())
                i += 1
            blocks.append({"type": "ul", "items": items})
            continue
        if re.match(r"^\s*\d+\. ", line):
            items = []
            while i < len(lines) and re.match(r"^\s*\d+\. ", lines[i]):
                items.append(re.sub(r"^\s*\d+\. ", "", lines[i]).strip())
                i += 1
            blocks.append({"type": "ol", "items": items})
            continue
        # 段落：合并连续非空、非结构行
        buf = [line]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if (not nxt or nxt.startswith("#") or nxt.startswith("|")
                    or nxt.startswith(">") or re.match(r"^\s*[-*] ", nxt)
                    or re.match(r"^\s*\d+\. ", nxt)):
                break
            buf.append(nxt)
            i += 1
        blocks.append({"type": "p", "text": " ".join(buf)})
    return blocks


def render(md: str, title: str, subtitle: str, date: str) -> str:
    blocks = parse(md)
    # 目录：h1 + 其后的 h2
    toc = []
    for b in blocks:
        if b["type"] == "h1":
            toc.append({"text": b["text"], "kids": []})
        elif b["type"] == "h2" and toc:
            toc[-1]["kids"].append(b["text"])

    body = []
    sec_no = 0
    first_section = True
    in_section = False
    for b in blocks:
        t = b["type"]
        if t == "h1":
            if in_section:
                body.append("</section>")
            sec_no += 1
            attr = ' data-page-restart="1"' if first_section else ""
            first_section = False
            in_section = True
            body.append('<section class="chapter"%s>' % attr)
            body.append('<h1 id="section-%d">%s</h1>' % (sec_no, inline(b["text"])))
            continue
        if t == "h2":
            body.append("<h2>%s</h2>" % inline(b["text"]))
            continue
        if t == "p":
            body.append("<p>%s</p>" % inline(b["text"]))
            continue
        if t == "note":
            body.append('<div class="note"><p>%s</p></div>' % inline(b["text"]))
            continue
        if t in ("ul", "ol"):
            body.append("<%s>" % t)
            for it in b["items"]:
                body.append("<li>%s</li>" % inline(it))
            body.append("</%s>" % t)
            continue
        if t == "table":
            rows = b["rows"]
            if not rows:
                continue
            body.append("<table>")
            body.append("<thead><tr>")
            for c in rows[0]:
                body.append("<th>%s</th>" % inline(c))
            body.append("</tr></thead><tbody>")
            for r in rows[1:]:
                body.append("<tr>")
                for c in r:
                    body.append("<td>%s</td>" % inline(c))
                body.append("</tr>")
            body.append("</tbody></table>")
    # 最后一个 section 未闭合（h1 开标签），统一闭合
    if in_section:
        body.append("</section>")

    toc_html = ['<p class="toc-title">目录</p>', '<ol class="toc-list">']
    for idx, item in enumerate(toc, start=1):
        toc_html.append('<li><a href="#section-%d">%s</a>' % (idx, inline(item["text"])))
        if item["kids"]:
            toc_html.append("<ol>")
            for kid in item["kids"]:
                toc_html.append("<li>%s</li>" % inline(kid))
            toc_html.append("</ol>")
        toc_html.append("</li>")
    toc_html.append("</ol>")

    css = (CSS.replace("__ACCENT__", ACCENT)
              .replace("__ACCENT_LIGHT__", ACCENT_LIGHT)
              .replace("__BORDER__", BORDER))
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="docx-page-size" content="A4">
<title>%s</title>
<style>
@page { @bottom-center { content: counter(page); } }
@page cover { @bottom-center { content: none; } }
section[role="cover"] { page: cover; }
%s
.toc-list, .toc-list ol, .toc-list ul { list-style: none; }
</style>
</head>
<body>
<section role="cover">
  <div class="cover-wrap">
    <div class="cover-kicker">万界秘境 · BOSS 资料</div>
    <div class="cover-title">%s</div>
    <div class="cover-rule"></div>
    <div class="cover-sub">%s</div>
    <div class="cover-meta">项目：万界秘境（Godot 4.7.2）<br>版本：阶段一开发版<br>整理日期：%s<br>数据口径：以当前代码与数据表为准</div>
  </div>
</section>
<section role="cover">
<nav class="doc-toc" aria-label="文档目录">
%s
</nav>
</section>
%s
</body>
</html>
""" % (html.escape(title), css,
       html.escape(title), html.escape(subtitle), html.escape(date),
       "\n".join(toc_html), "\n".join(body))


def main():
    md_path, out_path, title, subtitle = sys.argv[1:5]
    with io.open(md_path, "r", encoding="utf-8") as f:
        md = f.read()
    out = render(md, title, subtitle, "2026-10-18")
    with io.open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("written", out_path, len(out))


if __name__ == "__main__":
    main()
