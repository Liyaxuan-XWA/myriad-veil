"""两仪真人美术的公共润色工具（2026-10-28）。

目的：在**不改变任何轮廓**的前提下，把平涂分件做出材质感 ——
垂直明暗、边缘内阴影、外缘环境光、细颗粒。因为只改明暗与边缘，
rig.tres 的分件锚点（整画布 900×720 / offset = -joint）完全不受影响。

⚠ 生图配额仍是 HTTP 403 code 112，本轮全部走程序化；正式美术同名覆盖即可。
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math

GOLD = (196, 154, 70, 255)
GOLD_L = (240, 210, 132, 255)
CYAN_L = (150, 228, 236, 255)
WHITE2 = (244, 240, 228, 255)


def clip_layer(layer: Image.Image, alpha: Image.Image) -> Image.Image:
    """把一层颜色裁到 alpha 形状里（用于渐变 / 纹理只作用于分件本身）"""
    out = layer.copy()
    out.putalpha(ImageChops.multiply(layer.getchannel("A"), alpha))
    return out


def polish(img: Image.Image, grain: float = 0.16, rim_alpha: float = 0.18,
           rim_color=(150, 228, 236)) -> Image.Image:
    """平涂 → 有材质：竖向明暗 + 边缘内阴影 + 外缘环境光 + 细颗粒。
    只在最终分辨率上跑（别在 3× 超采样上跑，滤镜太贵）。"""
    w, h = img.size
    alpha = img.getchannel("A")

    # 1) 竖向明暗：上 45% 提亮、下 55% 压暗（低透明，柔和过渡）
    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / max(1, h - 1)
        if t < 0.45:
            a = int(30 * (1.0 - t / 0.45))
            gd.line([(0, y), (w, y)], fill=(255, 250, 236, a))
        else:
            a = int(58 * ((t - 0.45) / 0.55))
            gd.line([(0, y), (w, y)], fill=(6, 8, 12, a))
    img = Image.alpha_composite(img, clip_layer(grad, alpha))

    # 2) 边缘内阴影：alpha 内缩再模糊，差集就是内侧的一圈暗边
    inner = alpha.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.GaussianBlur(4))
    edge = ImageChops.subtract(alpha, inner)
    shadow = Image.new("RGBA", (w, h), (6, 8, 12, 0))
    shadow.putalpha(edge.point(lambda v: int(v * 0.60)))
    img = Image.alpha_composite(img, shadow)

    # 3) 外缘环境光：淡淡一圈（阴侧青、阳侧金由调用方自己再叠）
    outer = alpha.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(7))
    halo = Image.new("RGBA", (w, h), (rim_color[0], rim_color[1], rim_color[2], 0))
    halo.putalpha(ImageChops.subtract(outer, alpha).point(lambda v: int(v * rim_alpha)))
    img = Image.alpha_composite(halo, img)

    # 4) 细颗粒：纸面 / 布料颗粒，只落在分件里
    noise = Image.effect_noise((w, h), 16).convert("L")
    grain_layer = Image.new("RGBA", (w, h), (255, 252, 244, 0))
    grain_layer.putalpha(ImageChops.multiply(
        noise.point(lambda v: max(0, v - 120)),
        alpha.point(lambda v: int(v * grain))))
    img = Image.alpha_composite(img, grain_layer)
    return img


def radial_glow(size, color, radius, alpha=110):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    d.ellipse([w / 2 - radius, h / 2 - radius, w / 2 + radius, h / 2 + radius],
              fill=(color[0], color[1], color[2], alpha))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def vignette(size, strength=0.55, color=(4, 5, 7)):
    w, h = size
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([-w * 0.25, -h * 0.30, w * 1.25, h * 1.30], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    inv = ImageChops.invert(mask).point(lambda v: int(v * strength))
    layer = Image.new("RGBA", (w, h), (color[0], color[1], color[2], 0))
    layer.putalpha(inv)
    return layer


def draw_bagua_ring(d: ImageDraw.ImageDraw, cx, cy, radius, color, width=3,
                    bar_len=26.0, bar_gap=13.0):
    """八组卦象（乾兑离震巽坎艮坤），沿切向摆开 —— 与特效贴图同一套语言"""
    trigrams = [(1, 1, 1), (1, 1, 0), (1, 0, 1), (1, 0, 0),
                (0, 1, 1), (0, 1, 0), (0, 0, 1), (0, 0, 0)]
    for i, tri in enumerate(trigrams):
        ang = -math.pi / 2 + i * math.tau / 8.0
        tx, ty = -math.sin(ang), math.cos(ang)
        for k, solid in enumerate(tri):
            rr = radius + k * bar_gap
            px = cx + math.cos(ang) * rr
            py = cy + math.sin(ang) * rr
            if solid:
                _tangent_bar(d, px, py, tx, ty, bar_len, width, color)
            else:
                seg = bar_len * 0.38
                for sign in (-1.0, 1.0):
                    off = sign * (bar_len * 0.5 - seg * 0.5)
                    _tangent_bar(d, px + tx * off, py + ty * off, tx, ty, seg, width, color)


def _tangent_bar(d, px, py, tx, ty, length, width, color):
    hx, hy = tx * length * 0.5, ty * length * 0.5
    nx, ny = -ty * width * 0.5, tx * width * 0.5
    d.polygon([(px - hx + nx, py - hy + ny), (px + hx + nx, py + hy + ny),
               (px + hx - nx, py + hy - ny), (px - hx - nx, py - hy - ny)], fill=color)
