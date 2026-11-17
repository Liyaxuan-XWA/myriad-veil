"""两仪真人的技能特效贴图（2026-10-28）。

目的：让八式「光看特效就能认出来」，并给整只 BOSS 一套统一的阴阳八卦语言。
全部程序化绘制、加法混合友好（透明底 + 高亮芯 + 柔光），可被正式美术同名覆盖。

输出：
  assets/effects/skills/liangyi_bagua.png       先天八卦环（金，一圈八组卦象）
  assets/effects/skills/liangyi_taiji.png       太极印（阴阳鱼 + 金边）
  assets/effects/skills/liangyi_palm_seal.png   掌印（掌心太极 + 三道掌纹 + 指印）
  assets/effects/skills/liangyi_bar.png         一根发光卦爻（阳关三叠的踏痕用）
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

OUT = "assets/effects/skills"

GOLD = (236, 198, 116, 255)
GOLD_SOFT = (236, 198, 116, 170)
WHITE = (255, 250, 232, 255)
CYAN = (128, 226, 238, 255)
INK = (14, 18, 24, 255)


def glow(size, color, r, alpha=120):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(r * 0.45))


def save(img, name, size=512):
    img = img.resize((size, size), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("fx", name)


def bagua_ring():
    """八组卦象绕一圈：乾☰ 兑☱ 离☲ 震☳ 巽☴ 坎☵ 艮☶ 坤☷。
    每组三爻，爻线沿切向摆，断爻在中间留缝 —— 远看是「一圈刻度」，近看认得出卦。"""
    S = 512
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = Image.alpha_composite(c, glow((S, S), GOLD, 210, 70))
    d = ImageDraw.Draw(c)
    cx = cy = S / 2
    # 外圈细描边 + 内圈
    d.ellipse([cx - 236, cy - 236, cx + 236, cy + 236], outline=GOLD_SOFT, width=3)
    d.ellipse([cx - 176, cy - 176, cx + 176, cy + 176], outline=(GOLD[0], GOLD[1], GOLD[2], 90), width=2)
    # 三爻位：1 = 阳爻（整根），0 = 阴爻（中断）
    trigrams = [
        (1, 1, 1),  # 乾
        (1, 1, 0),  # 兑
        (1, 0, 1),  # 离
        (1, 0, 0),  # 震
        (0, 1, 1),  # 巽
        (0, 1, 0),  # 坎
        (0, 0, 1),  # 艮
        (0, 0, 0),  # 坤
    ]
    bar_len = 54.0
    bar_w = 7.0
    gap = 13.0
    for i, tri in enumerate(trigrams):
        ang = -math.pi / 2 + i * math.tau / 8.0
        for k, solid in enumerate(tri):
            # 每爻往外排：第一爻最靠内
            rr = 190.0 + k * gap
            px = cx + math.cos(ang) * rr
            py = cy + math.sin(ang) * rr
            # 切向单位向量
            tx, ty = -math.sin(ang), math.cos(ang)
            if solid:
                _bar(d, px, py, tx, ty, bar_len, bar_w, GOLD)
            else:
                # 断爻：中间空出 1/3
                half = bar_len * 0.5
                seg = bar_len * 0.34
                for sign in (-1.0, 1.0):
                    off = sign * (half - seg * 0.5)
                    _bar(d, px + tx * off, py + ty * off, tx, ty, seg, bar_w, GOLD)
    # 中心小太极环（占位，真正的太极印由 liangyi_taiji 提供）
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], outline=(WHITE[0], WHITE[1], WHITE[2], 190), width=3)
    save(c, "liangyi_bagua.png")


def _bar(d, px, py, tx, ty, length, width, color):
    hx, hy = tx * length * 0.5, ty * length * 0.5
    nx, ny = -ty * width * 0.5, tx * width * 0.5
    d.polygon([
        (px - hx + nx, py - hy + ny), (px + hx + nx, py + hy + ny),
        (px + hx - nx, py + hy - ny), (px - hx - nx, py - hy - ny),
    ], fill=color)


def taiji():
    S = 512
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = Image.alpha_composite(c, glow((S, S), GOLD, 190, 90))
    d = ImageDraw.Draw(c)
    cx = cy = S / 2
    R = 190
    # 阳面（宣白）与阴面（墨）
    d.pieslice([cx - R, cy - R, cx + R, cy + R], -90, 90, fill=WHITE)
    d.pieslice([cx - R, cy - R, cx + R, cy + R], 90, 270, fill=INK)
    h = R // 2
    d.ellipse([cx - h, cy - R, cx + h, cy], fill=WHITE)
    d.ellipse([cx - h, cy, cx + h, cy + R], fill=INK)
    # 鱼眼
    d.ellipse([cx - 30, cy - h - 30, cx + 30, cy - h + 30], fill=INK)
    d.ellipse([cx - 30, cy + h - 30, cx + 30, cy + h + 30], fill=WHITE)
    # 金边
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GOLD, width=6)
    save(c, "liangyi_taiji.png")


def palm_seal():
    """掌印：掌心一枚太极、上三道掌纹、五指指印 —— 焚脉掌命中时盖在扇形中段。"""
    S = 512
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = Image.alpha_composite(c, glow((S, S), GOLD, 170, 80))
    d = ImageDraw.Draw(c)
    cx, cy = S / 2, S / 2 + 30
    # 掌身
    d.ellipse([cx - 118, cy - 96, cx + 118, cy + 130], fill=(GOLD[0], GOLD[1], GOLD[2], 150))
    # 五指（从掌身向上放射）
    for i in range(5):
        ang = math.radians(-104.0 + i * 19.0)
        r1 = 92.0
        r2 = 210.0 - abs(i - 2) * 16.0
        x1, y1 = cx + math.cos(ang) * r1, cy - 20 + math.sin(ang) * r1
        x2, y2 = cx + math.cos(ang) * r2, cy - 20 + math.sin(ang) * r2
        _bar(d, (x1 + x2) * 0.5, (y1 + y2) * 0.5,
             math.cos(ang), math.sin(ang), r2 - r1, 30.0, (GOLD[0], GOLD[1], GOLD[2], 170))
    # 掌纹：三道弧
    for i, (rr, aa) in enumerate([(86, 210), (64, 180), (44, 150)]):
        d.arc([cx - rr, cy - rr * 0.8, cx + rr, cy + rr * 0.9],
              start=200 + i * 4, end=340 - i * 4, fill=(255, 244, 214, aa), width=5)
    # 掌心太极（简化：半明半暗的小圆 + 金边）
    pr = 34
    d.pieslice([cx - pr, cy - pr, cx + pr, cy + pr], -90, 90, fill=WHITE)
    d.pieslice([cx - pr, cy - pr, cx + pr, cy + pr], 90, 270, fill=INK)
    d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], outline=GOLD, width=4)
    save(c, "liangyi_palm_seal.png")


def bar():
    """一根发光卦爻：阳关三叠每踏一下盖一条，三条叠起来就是乾卦。"""
    W, H = 256, 64
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(core)
    # 中间厚、两端收尖
    d.polygon([(8, H / 2), (W / 2, 6), (W - 8, H / 2), (W / 2, H - 6)], fill=GOLD)
    d.polygon([(26, H / 2), (W / 2, 20), (W - 26, H / 2), (W / 2, H - 20)],
              fill=(255, 250, 232, 235))
    c = Image.alpha_composite(c, core.filter(ImageFilter.GaussianBlur(10)))
    c = Image.alpha_composite(c, core)
    c.save(os.path.join(OUT, "liangyi_bar.png"))
    print("fx liangyi_bar.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bagua_ring()
    taiji()
    palm_seal()
    bar()
