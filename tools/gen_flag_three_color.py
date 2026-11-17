"""阵旗三色（2026-10-28）：由现有朱砂竖幡派生出「墨」「石青」两面，
并生成三件写实旗顶饰（青铜枪尖 / 铁锁环 / 石青玉璧）与三种地面环。

原则：只改布面颜色与杆顶，不动旗杆、金线、投影与轮廓，保证三面旗是同一批材料做的。
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

OUT = "assets/effects/skills"


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def recolor(src_name, dst_name, shadow, light):
    im = Image.open(os.path.join(OUT, src_name)).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            # 布面：红占绝对主导（金线 g/r≈0.8，布面≈0.3）
            if g > r * 0.55 or b > r * 0.60:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            t = max(0.0, min(1.0, lum / 110.0))
            nr, ng, nb = lerp(shadow, light, t)
            px[x, y] = (nr, ng, nb, a)
    im.save(os.path.join(OUT, dst_name))
    print("flag", dst_name)


def canvas(size=96):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def shadow_blob(d, cx, cy, r):
    d.ellipse([cx - r, cy - r + 6, cx + r, cy + r + 6], fill=(0, 0, 0, 70))


def ornament_spear():
    """攻：青铜枪尖（写实金属：暗底、亮脊、金箍、短杆）"""
    c = canvas()
    d = ImageDraw.Draw(c)
    shadow_blob(d, 48, 48, 22)
    # 枪尖本体
    blade = [(48, 4), (63, 34), (56, 62), (40, 62), (33, 34)]
    d.polygon(blade, fill=(118, 84, 44, 255), outline=(58, 40, 22, 255))
    d.polygon([(48, 8), (57, 34), (48, 58), (48, 8)], fill=(206, 168, 104, 255))
    d.polygon([(48, 8), (39, 34), (48, 58), (48, 8)], fill=(150, 108, 58, 255))
    d.line([(48, 10), (48, 58)], fill=(244, 216, 158, 230), width=2)
    # 金箍
    d.rounded_rectangle([36, 60, 60, 72], radius=4, fill=(196, 154, 70, 255),
                        outline=(110, 78, 34, 255))
    d.line([(38, 64), (58, 64)], fill=(244, 214, 146, 200), width=2)
    # 短杆
    d.rectangle([45, 72, 51, 92], fill=(96, 72, 48, 255))
    d.line([(46, 72), (46, 90)], fill=(150, 120, 84, 200), width=1)
    c.save(os.path.join(OUT, "flag_top_spear.png"))
    print("ornament spear")


def ornament_ring():
    """困：铁锁环（冷铁 + 铆钉 + 一小截链节）"""
    c = canvas()
    d = ImageDraw.Draw(c)
    shadow_blob(d, 48, 50, 24)
    # 环体
    d.ellipse([20, 22, 76, 78], outline=(46, 50, 58, 255), width=13)
    d.ellipse([23, 25, 73, 75], outline=(92, 98, 110, 255), width=4)
    d.arc([20, 22, 76, 78], 200, 300, fill=(168, 176, 190, 255), width=5)
    d.arc([20, 22, 76, 78], 30, 120, fill=(18, 20, 26, 220), width=4)
    # 铆钉
    for a in (20, 110, 200, 290):
        x = 48 + math.cos(math.radians(a)) * 28
        y = 50 + math.sin(math.radians(a)) * 28
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(150, 156, 168, 255),
                  outline=(20, 22, 28, 255))
    # 链节 + 红绳
    d.rounded_rectangle([42, 78, 54, 92], radius=5, outline=(70, 76, 88, 255), width=4)
    d.line([(48, 14), (48, 22)], fill=(150, 40, 34, 255), width=3)
    c.save(os.path.join(OUT, "flag_top_ring.png"))
    print("ornament ring")


def ornament_jade():
    """守：石青玉璧（玉面渐变 + 金边 + 金销）"""
    c = canvas()
    d = ImageDraw.Draw(c)
    shadow_blob(d, 48, 48, 24)
    d.ellipse([18, 16, 78, 76], fill=(16, 42, 48, 255), outline=(196, 154, 70, 255), width=4)
    d.ellipse([24, 22, 72, 70], fill=(38, 96, 106, 255))
    d.arc([24, 22, 72, 70], 200, 330, fill=(132, 206, 212, 230), width=5)
    d.arc([24, 22, 72, 70], 20, 120, fill=(14, 46, 54, 220), width=4)
    d.ellipse([40, 38, 56, 54], fill=(8, 16, 20, 255), outline=(196, 154, 70, 255), width=3)
    d.line([(48, 76), (48, 92)], fill=(196, 154, 70, 255), width=4)
    d.line([(30, 30), (36, 26)], fill=(240, 250, 250, 200), width=2)
    c.save(os.path.join(OUT, "flag_top_jade.png"))
    print("ornament jade")


def ground_ring(name, color, width=4, dashes=0, fill_alpha=0, ticks=None):
    size = 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    r = 116
    if fill_alpha > 0:
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(color[0], color[1], color[2], fill_alpha))
        img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(18)))
        d = ImageDraw.Draw(img)
    if dashes > 0:
        step = 360.0 / dashes
        for i in range(dashes):
            a0 = i * step
            d.arc([cx - r, cy - r, cx + r, cy + r], a0, a0 + step * 0.55,
                  fill=color, width=width)
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=width)
    if ticks:
        for a in ticks:
            rad = math.radians(a)
            x1, y1 = cx + math.cos(rad) * (r - 12), cy + math.sin(rad) * (r - 12)
            x2, y2 = cx + math.cos(rad) * (r + 12), cy + math.sin(rad) * (r + 12)
            d.line([(x1, y1), (x2, y2)], fill=(240, 210, 132, 220), width=4)
    img = ac.polish(img, grain=0.10, rim_alpha=0.10)
    img.save(os.path.join(OUT, name))
    print("ring", name)


if __name__ == "__main__":
    recolor("array_flag_red.png", "array_flag_ink.png", (8, 10, 14), (48, 52, 62))
    recolor("array_flag_red.png", "array_flag_blue.png", (10, 30, 38), (52, 122, 134))
    ornament_spear()
    ornament_ring()
    ornament_jade()
    ground_ring("flag_warn_ring.png", (226, 86, 66, 235), width=5, dashes=12, fill_alpha=46)
    ground_ring("flag_bind_ring.png", (92, 80, 72, 150), width=3, dashes=16, fill_alpha=26)
    ground_ring("flag_guard_ring.png", (120, 206, 214, 210), width=4, ticks=(0, 90, 180, 270))
