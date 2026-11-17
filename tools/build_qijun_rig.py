"""太虚气君 2D 骨骼分件（2026-10-28，T-pose 版 v2）。

A-pose 版的手臂贴着袍子，切下来后身体会留下整条袖子的洞，抬手就露出补丁；
改用**双臂抬平的 T-pose**：袖子内侧与躯干之间有背景空隙，身体只需要补一个
肩窝小圆，手臂整块绕肩关节转，不会拖着一条「补丁袖」。

三件：body / arm_l / arm_r（+ 程序化 halo）。
关节 = 肩点；贴图用整张 900×720 画布，offset = -joint（与定阵 rig 同口径）。
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

PLACED = "vibe_images/qijun_tpose_placed.png"
OUT = "assets/characters/boss/qijun_rig"
CANVAS = (900, 720)
JL = (405, 248)
JR = (495, 248)


def poly_left():
    return [(404, 228), (372, 238), (330, 254), (290, 272), (258, 288),
            (242, 302), (252, 316), (286, 316), (322, 304), (334, 330),
            (334, 390), (330, 442), (338, 474), (300, 480), (284, 442),
            (284, 386), (296, 330), (338, 296), (378, 268), (402, 248)]


def poly_right():
    return [(496, 228), (528, 238), (570, 254), (610, 272), (642, 288),
            (658, 302), (648, 316), (614, 316), (578, 304), (566, 330),
            (566, 390), (570, 442), (562, 474), (600, 480), (616, 442),
            (616, 386), (604, 330), (562, 296), (522, 268), (498, 248)]


def mask_from(points, disc, r=34):
    m = Image.new("L", CANVAS, 0)
    d = ImageDraw.Draw(m)
    d.polygon(points, fill=255)
    d.ellipse([disc[0] - r, disc[1] - r, disc[0] + r, disc[1] + r], fill=255)
    return m.filter(ImageFilter.GaussianBlur(1.0)).point(lambda v: 255 if v > 90 else 0)


def cloth_patch(base, hole):
    """把肩窝小圆补成袍色：取外袍平均色 + 竖向渐变。"""
    arr = np.array(base).astype(np.int16)
    hole_np = np.array(hole) > 128
    samples = []
    for (sx, sy) in ((420, 300), (480, 300), (410, 380), (490, 380), (430, 460), (470, 460)):
        if not hole_np[sy, sx] and base.getpixel((sx, sy))[3] > 200:
            samples.append(arr[sy, sx][:3].astype(float))
    col = np.mean(np.array(samples), axis=0) if samples else np.array([226.0, 232.0, 232.0])
    ys, xs = np.where(hole_np)
    for y, x in zip(ys, xs):
        vt = max(0.0, min(1.0, float(y - 230) / 220.0))
        k = 1.02 - 0.16 * vt
        arr[y, x] = [int(col[0] * k), int(col[1] * k), int(col[2] * k), 255]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def halo():
    img = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 450, 300
    for r, a, w in ((232, 70, 3), (206, 46, 2), (180, 30, 2)):
        d.arc([cx - r, cy - r, cx + r, cy + r], 0, 360,
              fill=(120, 206, 222, a), width=w)
    for k in range(3):
        a0 = 24 + k * 120
        d.arc([cx - 218, cy - 218, cx + 218, cy + 218], a0, a0 + 44,
              fill=(176, 234, 246, 130), width=5)
    img = ac.polish(img, grain=0.06, rim_alpha=0.05)
    img.save(os.path.join(OUT, "halo.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    base = Image.open(PLACED).convert("RGBA")
    ml = mask_from(poly_left(), JL)
    mr = mask_from(poly_right(), JR)
    both = Image.composite(Image.new("L", CANVAS, 255), ml, mr)  # 并集
    # 身体：袖子洞先补袍色，再把「手臂按站姿角度转好」的副本**只贴回洞内**当内衬垂袖。
    # 关键：内衬必须限制在洞内，否则静止时会出现双层袖重影（上一版踩过）。
    body = cloth_patch(base.copy(), both)
    import math
    for mask, joint, idle in ((ml, JL, -0.50), (mr, JR, 0.50)):
        arm = base.copy()
        arm.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), mask))
        arm = arm.rotate(-math.degrees(idle), resample=Image.BICUBIC, center=joint)
        under = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        under.alpha_composite(arm)
        under.putalpha(Image.composite(under.getchannel("A"), Image.new("L", CANVAS, 0), both))
        body.alpha_composite(under)
    body.save(os.path.join(OUT, "body.png"))
    # 两臂
    for name, mask in (("arm_l", ml), ("arm_r", mr)):
        part = base.copy()
        part.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), mask))
        part.save(os.path.join(OUT, name + ".png"))
    halo()
    prev = Image.new("RGBA", CANVAS, (36, 40, 44, 255))
    for n in ("halo", "body", "arm_l", "arm_r"):
        prev.alpha_composite(Image.open(os.path.join(OUT, n + ".png")).convert("RGBA"))
    prev.convert("RGB").save("vibe_images/_qijun_rig_composed.png")
    bodybg = Image.new("RGBA", CANVAS, (36, 40, 44, 255))
    bodybg.alpha_composite(body)
    bodybg.convert("RGB").save("vibe_images/_qijun_rig_body.png")
    print("rig parts saved; joints", JL, JR)


if __name__ == "__main__":
    main()
