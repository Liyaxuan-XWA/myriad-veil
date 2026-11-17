"""晏无咎 2D 骨骼分件（2026-10-29）。

定妆图：vibe_images/_wujiu_placed.png（900×720，脚底 y=700）

分件思路：
- body：整身（长袍 / 长发 / 垂手 / 前臂），宽袖全部留在躯干上，不做肩肘拆分 ——
  这张图的袖子又宽又碎，拆上臂必然把袖口扯开、关节处露白。
- hand_cast：只拆「举起的右手 + 手腕」这一小块，绕腕 (350,150) 转。前臂仍在
  body 上，所以手转开时下面永远有前臂垫着，不会出现白缝。幅度控制在 ±0.30 rad。
- wheel_outer / wheel_mid / wheel_inner：背后三段劫环，程序化生成，各自独立转。
  环本身是半透明符线，不参与受击判定，只做「三灾在头顶轮转」的视觉锚点。
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import math
import os
import numpy as np
from scipy import ndimage

SRC = "vibe_images/_wujiu_placed.png"
OUT = "assets/characters/boss/wujiu_rig"
CANVAS = (900, 720)
HAND_JOINT = (350.0, 150.0)
WHEEL_JOINT = (450.0, 330.0)

HAND_POLY = [
    (340, 60), (354, 58), (364, 66), (370, 78), (366, 88),
    (378, 92), (387, 102), (390, 112), (384, 121), (372, 122),
    (365, 117), (363, 126), (367, 136), (361, 145), (352, 150),
    (341, 147), (335, 139), (331, 128), (333, 116), (329, 108),
    (331, 98), (337, 90), (335, 82), (336, 72),
]


def make_wheel(size, rings, seed_shift=0.0):
    """三段劫环的其中一段：暗色描边 + 发光内芯 + 断口 + 刻痕。"""
    S = size * 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2.0
    for ring in rings:
        radius = ring["r"] * 2
        color = ring["color"]
        width = ring["w"] * 2
        base = math.radians(ring.get("start", 0.0) + seed_shift)
        spans = [(base + math.radians(a0), base + math.radians(a1))
                 for a0, a1 in ring["arcs"]]
        for a0, a1 in spans:
            # 外圈墨线：压住背景，保证在浅色地面上也能看清
            d.arc([c - radius, c - radius, c + radius, c + radius],
                  math.degrees(a0), math.degrees(a1), fill=(18, 16, 22, ring["ink"]),
                  width=width + 5)
            d.arc([c - radius, c - radius, c + radius, c + radius],
                  math.degrees(a0), math.degrees(a1), fill=color, width=width)
        # 断口两端的小三角 / 刻痕
        for a0, a1 in spans:
            for ang in (a0, a1):
                ca, sa = math.cos(ang), math.sin(ang)
                px, py = c + ca * radius, c + sa * radius
                nx, ny = -sa, ca
                d.line([(px - nx * 7 * 2, py - ny * 7 * 2),
                        (px + nx * 7 * 2, py + ny * 7 * 2)],
                       fill=color, width=4)
        # 环上刻度：每 18° 一根短切线
        for k in range(20):
            ang = base + k * math.tau / 20.0
            if ring.get("no_ticks", False):
                continue
            ca, sa = math.cos(ang), math.sin(ang)
            r0 = radius - width * 0.5 - 3
            r1 = r0 - ring["tick"]
            d.line([(c + ca * r0, c + sa * r0), (c + ca * r1, c + sa * r1)],
                   fill=(color[0], color[1], color[2], max(0, color[3] - 40)),
                   width=2)
    img = img.resize((size, size), Image.LANCZOS)
    glow = img.filter(ImageFilter.GaussianBlur(size * 0.012))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.55)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(glow)
    out.alpha_composite(img)
    return out


def wheel_outer():
    return make_wheel(760, [{
        "r": 350, "w": 11, "color": (132, 202, 196, 200), "ink": 150,
        "arcs": [(8, 104), (126, 214), (238, 330)], "tick": 16, "gap": 1,
    }])


def wheel_mid():
    return make_wheel(660, [{
        "r": 302, "w": 10, "color": (232, 142, 88, 190), "ink": 135,
        "arcs": [(20, 120), (150, 236), (258, 338)], "start": 12, "tick": 13,
    }])


def wheel_inner():
    img = make_wheel(560, [
        {"r": 254, "w": 10, "color": (176, 142, 232, 200), "ink": 135,
         "arcs": [(0, 96), (118, 208), (232, 322)], "start": 6, "tick": 12},
        {"r": 208, "w": 3, "color": (236, 232, 224, 140), "ink": 90,
         "arcs": [(10, 170), (190, 350)], "start": 0, "tick": 0, "no_ticks": True},
    ])
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    base = Image.open(SRC).convert("RGBA")

    mask = Image.new("L", CANVAS, 0)
    ImageDraw.Draw(mask).polygon(HAND_POLY, fill=255)
    # 先向外扩 2px：手指边缘的抗锯齿碎点若留在 body 上，手一转就会看见「飘着的肉色点」
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.8)).point(
        lambda v: 255 if v > 100 else 0)

    hand = base.copy()
    hand.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), mask))
    # 只留最大连通块：手腕边缘的碎发 / 键色残点不能被手带着转
    ha = np.array(hand.getchannel("A")) > 20
    lab, n = ndimage.label(ha)
    if n > 1:
        sizes = ndimage.sum(ha, lab, range(1, n + 1))
        keep = int(np.argmax(sizes)) + 1
        ha = lab == keep
        a = np.array(hand)
        a[:, :, 3] = np.where(ha, a[:, :, 3], 0)
        hand = Image.fromarray(a, "RGBA")
    hand.save(os.path.join(OUT, "hand_cast.png"))

    body = base.copy()
    body.putalpha(Image.composite(Image.new("L", CANVAS, 0), base.getchannel("A"), mask))
    # 手部原位置再清一遍肉色碎点（前臂 y>=142 保留）
    ba = np.array(body).astype(np.int16)
    r, g, b = ba[:, :, 0], ba[:, :, 1], ba[:, :, 2]
    skin = (r > 85) & (r > g + 8) & (g > b) & (r > b + 18)
    zone = np.zeros(ba.shape[:2], dtype=bool)
    zone[45:142, 325:402] = True
    ba[:, :, 3] = np.where(skin & zone, 0, ba[:, :, 3])
    ba_lab, ba_n = ndimage.label(ba[:, :, 3] > 20)
    for i in range(1, ba_n + 1):
        ys, xs = np.where(ba_lab == i)
        if ys.size == 0 or ys.size > 800:
            continue
        if xs.min() > 320 and xs.max() < 410 and ys.min() > 40 and ys.max() < 155:
            ba[ys, xs, 3] = 0
    body = Image.fromarray(ba.astype(np.uint8), "RGBA")
    body.save(os.path.join(OUT, "body.png"))

    base.save("assets/characters/boss/boss_wujiu.png")

    wheel_outer().save(os.path.join(OUT, "wheel_outer.png"))
    wheel_mid().save(os.path.join(OUT, "wheel_mid.png"))
    wheel_inner().save(os.path.join(OUT, "wheel_inner.png"))

    # 预览：暗底 + 青灰网格
    prev = Image.new("RGBA", CANVAS, (26, 24, 30, 255))
    for name, jp in (("wheel_outer", (450, 330)), ("wheel_mid", (450, 330)),
                     ("wheel_inner", (450, 330))):
        w = Image.open(os.path.join(OUT, name + ".png")).convert("RGBA")
        prev.alpha_composite(w, (int(jp[0] - w.width / 2), int(jp[1] - w.height / 2)))
    prev.alpha_composite(Image.open(os.path.join(OUT, "body.png")).convert("RGBA"))
    prev.alpha_composite(Image.open(os.path.join(OUT, "hand_cast.png")).convert("RGBA"))
    prev.convert("RGB").save("vibe_images/_wujiu_rig_composed.png")
    dbg = prev.copy()
    d = ImageDraw.Draw(dbg)
    for jp, col in ((HAND_JOINT, (255, 255, 0)), (WHEEL_JOINT, (0, 255, 255))):
        d.ellipse([jp[0] - 5, jp[1] - 5, jp[0] + 5, jp[1] + 5], outline=col + (255,), width=2)
    dbg.convert("RGB").save("vibe_images/_wujiu_rig_joint.png")
    print("saved body/hand/wheels; hand joint", HAND_JOINT, "wheel joint", WHEEL_JOINT)


if __name__ == "__main__":
    main()
