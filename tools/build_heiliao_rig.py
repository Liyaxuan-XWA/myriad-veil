"""赫连霄 2D 骨骼分件（2026-10-29）。

定妆图：vibe_images/heiliao_tpose_v2_1793209042485_2cf8008c.png
- 右臂（含圆肩甲 + 铁笔）整块切下，绕肩关节旋转；
- 左臂 / 披风 / 雷鼓留在身体上（避免宽袖与披风的补丁洞）；
- 身体被切走的肩窝用「胸甲暗红」整块平涂补洞，圆肩甲随臂转动、始终盖住关节；
- 雷环程序化另出（不依赖 AI）。
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import numpy as np
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

SRC = "vibe_images/_heiliao_placed.png"
OUT = "assets/characters/boss/heiliao_rig"
CANVAS = (900, 720)
JOINT = (393.0, 205.0)   # 画布坐标里的肩关节（右肩圆甲中心）


def arm_poly():
    # 肩甲以下的手臂 + 铁笔；肩窝用一个 38px 的球顶住，肩甲（单独一件）盖在上面
    return [
        (420, 198), (470, 200), (540, 205), (610, 210), (660, 215),
        (735, 218), (815, 224), (815, 252), (735, 255), (660, 265),
        (610, 272), (540, 275), (470, 280), (420, 282), (395, 275),
        (380, 250), (385, 220),
    ]


def fill_shoulder(base, hole):
    """把肩窝补成胸甲的暗红 / 黑，带一点竖向渐变；圆肩甲会盖住大半。"""
    arr = np.array(base).astype(np.int16)
    hole_np = np.array(hole) > 128
    samples = []
    for (sx, sy) in ((380, 300), (420, 310), (360, 340), (440, 280), (330, 320)):
        if not hole_np[sy, sx] and base.getpixel((sx, sy))[3] > 200:
            samples.append(arr[sy, sx][:3].astype(float))
    col = np.mean(np.array(samples), axis=0) if samples else np.array([92.0, 34.0, 34.0])
    ys, xs = np.where(hole_np)
    for y, x in zip(ys, xs):
        vt = max(0.0, min(1.0, float(y - 150) / 150.0))
        k = 1.04 - 0.20 * vt
        arr[y, x] = [int(col[0] * k), int(col[1] * k), int(col[2] * k), 255]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def arm_mask():
    m = Image.new("L", CANVAS, 0)
    d = ImageDraw.Draw(m)
    d.polygon(arm_poly(), fill=255)
    d.ellipse([400 - 38, 235 - 38, 400 + 38, 235 + 38], fill=255)
    return m.filter(ImageFilter.GaussianBlur(1.0)).point(lambda v: 255 if v > 90 else 0)


def pauldron_mask():
    m = Image.new("L", CANVAS, 0)
    d = ImageDraw.Draw(m)
    d.ellipse([JOINT[0] - 62, JOINT[1] - 62, JOINT[0] + 62, JOINT[1] + 62], fill=255)
    return m.filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 100 else 0)


def halo():
    img = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 450.0, 286.0
    # 三层软环（半径 320：必须大过甲胄轮廓，否则整圈都被身体挡住）
    for r, a, w in ((320, 92, 4), (296, 64, 3), (272, 42, 2)):
        d.arc([cx - r, cy - r, cx + r, cy + r], 0, 360,
              fill=(150, 108, 232, a), width=w)
    # 内圈赤金细环：让雷环在深色背景上也有轮廓
    d.arc([cx - 284, cy - 284, cx + 284, cy + 284], 0, 360,
          fill=(212, 168, 88, 110), width=2)
    # 四段雷弧（只画在环上，像雷纹在转）
    for k in range(4):
        a0 = 20 + k * 90
        d.arc([cx - 304, cy - 304, cx + 304, cy + 304], a0, a0 + 38,
              fill=(226, 202, 255, 225), width=7)
    # 几道竖直小雷枝
    for k in range(6):
        ang = 2 * math.pi * (float(k) / 6.0) + 0.25
        x0 = cx + math.cos(ang) * 310.0
        y0 = cy + math.sin(ang) * 310.0
        x1 = cx + math.cos(ang) * 352.0
        y1 = cy + math.sin(ang) * 352.0
        mx = (x0 + x1) * 0.5 + random_offset(k)
        my = (y0 + y1) * 0.5 - 10.0
        d.line([(x0, y0), (mx, my), (x1, y1)], fill=(196, 150, 255, 130), width=3)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    glow = img.filter(ImageFilter.GaussianBlur(7))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.75)))
    img = Image.alpha_composite(glow, img)
    img = ac.polish(img, grain=0.06, rim_alpha=0.05)
    img.save(os.path.join(OUT, "halo.png"))


def random_offset(k):
    return (8.0 if k % 2 == 0 else -9.0)


def main():
    os.makedirs(OUT, exist_ok=True)
    base = Image.open(SRC).convert("RGBA")
    ma = arm_mask()
    mp = pauldron_mask()
    hole = ImageChops.lighter(ma, mp)
    body = fill_shoulder(base.copy(), hole)
    body.putalpha(Image.composite(Image.new("L", CANVAS, 0), base.getchannel("A"), hole))
    body.save(os.path.join(OUT, "body.png"))
    arm = base.copy()
    arm.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), ma))
    arm.save(os.path.join(OUT, "arm_pen.png"))
    pauldron = base.copy()
    pauldron.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), mp))
    pauldron.save(os.path.join(OUT, "pauldron.png"))
    halo()
    base.save("assets/characters/boss/boss_heiliao.png")

    prev = Image.new("RGBA", CANVAS, (34, 38, 42, 255))
    for n in ("halo", "body", "arm_pen", "pauldron"):
        prev.alpha_composite(Image.open(os.path.join(OUT, n + ".png")).convert("RGBA"))
    prev.convert("RGB").save("vibe_images/_heiliao_rig_composed.png")
    # 关节与蒙版预览
    dbg = prev.copy()
    d = ImageDraw.Draw(dbg)
    d.ellipse([JOINT[0] - 6, JOINT[1] - 6, JOINT[0] + 6, JOINT[1] + 6], outline=(255, 255, 0, 255), width=2)
    dbg.convert("RGB").save("vibe_images/_heiliao_rig_joint.png")
    print("saved body/arm/halo; joint", JOINT)


if __name__ == "__main__":
    main()
