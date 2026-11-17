"""把独立生成的「照影界·镜门」加性合成进位面星图底图。

原三扇画死的光门一个像素都不动，只在顶部空星云里落第 4 扇，
落点与 scripts/ui/facility/domain_star_map.gd 的 GATE_LAYOUT[3] 严格同源。
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import sys

SRC = "assets/ui/realm_select_bg.png"
GATE = "vibe_images/gate_mirror_zhaoying_1793796868058_28b94a72.png"
OUT = "output/realm_select_bg_4gates.png"

# 与 GATE_LAYOUT[3] 同源（源图 2730x1536 像素坐标）
CENTER = (1365, 270)
RING_R = 150
INNER_DIM = 0.55
WATER = (16, 24, 42)
WATER_STRENGTH = 0.50
# 镜门悬在凡界正上方：下探的烟尾不能爬进凡界的云里，否则两扇门糊成一坨
BOTTOM_FADE = 0.20


def ring_center(lum):
    """用最亮的一圈像素反解圆心：候选中心里，半径标准差最小者。"""
    thr = np.percentile(lum, 99.0)
    ys, xs = np.nonzero(lum >= thr)
    best = None
    for cy in np.arange(ys.mean() - 60, ys.mean() + 60, 4.0):
        for cx in np.arange(xs.mean() - 60, xs.mean() + 60, 4.0):
            r = np.hypot(xs - cx, ys - cy)
            s = r.std()
            if best is None or s < best[0]:
                best = (s, cx, cy, r)
    _, cx, cy, r = best
    return cx, cy, np.percentile(r, 50), np.percentile(r, 97)


def kill_watermark(a):
    """右下角「AI生成」水印：整块涂黑（那里本来就是纯黑底）。"""
    h, w, _ = a.shape
    a[int(h * 0.915):, int(w * 0.86):] = 0
    return a


def main():
    bg = Image.open(SRC).convert("RGB")
    g = Image.open(GATE).convert("RGB")
    a = np.asarray(g).astype(np.float32)
    a = kill_watermark(a)
    lum = a.max(axis=2)
    cx, cy, r50, r97 = ring_center(lum)
    print("gate center=(%.1f,%.1f) r50=%.1f r97=%.1f" % (cx, cy, r50, r97))

    # 裁出「环 + 外围烟」的方框，烟要留到环外 32%
    half = r97 * 1.34
    x0, y0 = max(0, int(cx - half)), max(0, int(cy - half))
    x1, y1 = min(a.shape[1], int(cx + half)), min(a.shape[0], int(cy + half))
    crop = Image.fromarray(a[y0:y1, x0:x1].astype(np.uint8))
    ccx, ccy = cx - x0, cy - y0

    # 缩放到目标环半径
    scale = RING_R / r50
    size = max(2, int(round(crop.width * scale)))
    gate = crop.resize((size, size), Image.LANCZOS)
    ccx *= scale
    ccy *= scale
    print("scaled to %d px, center in crop=(%.1f,%.1f)" % (size, ccx, ccy))

    # 镜面内部压暗：横贯的水线太硬，且名字要写在镜心
    ga = np.asarray(gate).astype(np.float32)
    yy, xx = np.mgrid[0:ga.shape[0], 0:ga.shape[1]]
    d = np.hypot(xx - ccx, yy - ccy) / RING_R
    # r<0.80 内部整体压到 0.30，0.80~0.92 平滑过渡回 1.0
    dim = np.where(d < 0.80, INNER_DIM, np.where(d > 0.92, 1.0,
        INNER_DIM + (1.0 - INNER_DIM) * (d - 0.80) / 0.12))
    ga *= dim[:, :, None]

    # 下探的烟尾按纵向渐变收掉，镜门和凡界之间留出一条干净的缝
    fade_top = ccy + RING_R * (1.0 - BOTTOM_FADE)
    ramp = np.clip((yy - fade_top) / (RING_R * BOTTOM_FADE * 1.6), 0.0, 1.0)
    ga *= (1.0 - ramp)[:, :, None] ** 1.6
    gate = Image.fromarray(np.clip(ga, 0, 255).astype(np.uint8))

    # 镜门内部先把底色拉成「静水」深色，避免透出背后的星云旋臂
    base = bg.copy()
    mask = Image.new("L", base.size, 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([CENTER[0] - RING_R * 0.97, CENTER[1] - RING_R * 0.97,
                CENTER[0] + RING_R * 0.97, CENTER[1] + RING_R * 0.97], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(RING_R * 0.10))
    water = Image.new("RGB", base.size, (10, 17, 30))
    base = Image.composite(water, base, mask.point(lambda v: int(v * 0.62)))

    # 加性合成（发光素材在纯黑底上，screen 等价于 additive）
    px = int(round(CENTER[0] - ccx))
    py = int(round(CENTER[1] - ccy))
    canvas = Image.new("RGB", base.size, (0, 0, 0))
    canvas.paste(gate, (px, py))
    out = Image.blend(base, ImageChops_add(base, canvas), 1.0)
    out.save(OUT)
    print("SAVED", OUT, "gate box x %d..%d y %d..%d" % (px, px + size, py, py + size))
    return 0


def ImageChops_add(a, b):
    from PIL import ImageChops
    return ImageChops.add(a, b, scale=1.0, offset=0)


if __name__ == "__main__":
    sys.exit(main())
