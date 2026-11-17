"""离照 2D 骨骼分件（2026-10-29）。

定妆图：vibe_images/boss_lizhao_tpose_1793230585948_ad969c0d.png
- 只拆「日轮扇 + 扇柄 + 持扇的手」：绕手腕旋转，扇舞的幅度足够，且不会扯动宽袖。
- 身体保留祭袍 / 左臂 / 长绦；持扇手的位置用袖口暗红补洞，扇面在静止时完全盖住。
- 日轮扇是独立件，后续所有招式只转这一件 + 身体重心，避免宽袖与躯干粘连。
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _art_common as ac  # noqa: E402

SRC = "vibe_images/_lizhao_placed.png"
OUT = "assets/characters/boss/lizhao_rig"
CANVAS = (900, 720)
JOINT = (298.0, 232.0)  # 持扇手腕（画布坐标）


def fan_mask():
    m = Image.new("L", CANVAS, 0)
    d = ImageDraw.Draw(m)
    # 扇面
    d.ellipse([272, 82, 398, 208], fill=255)
    # 扇柄（斜向下）
    d.polygon([(292, 196), (318, 205), (308, 246), (276, 288), (260, 280), (286, 232)], fill=255)
    # 持扇的手
    d.ellipse([274, 210, 324, 258], fill=255)
    return m.filter(ImageFilter.GaussianBlur(1.0)).point(lambda v: 255 if v > 90 else 0)


def fill_wrist(base, hole):
    """只补「原本压在袖口上的洞」；扇面左侧是背景，补色会变成红饼。"""
    arr = np.array(base).astype(np.int16)
    hole_np = np.array(hole) > 128
    alpha = arr[:, :, 3]
    # 取袖口附近的暗红：略偏冷、比亮红低一档，和内侧阴影一致
    col = np.array([108.0, 34.0, 40.0])
    ys, xs = np.where(hole_np & (alpha > 180))
    for y, x in zip(ys, xs):
        vt = max(0.0, min(1.0, float(y - 200) / 90.0))
        k = 1.06 - 0.18 * vt
        arr[y, x] = [int(col[0] * k), int(col[1] * k), int(col[2] * k), 255]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    base = Image.open(SRC).convert("RGBA")
    mf = fan_mask()
    body = fill_wrist(base.copy(), mf)
    body.putalpha(Image.composite(Image.new("L", CANVAS, 0), base.getchannel("A"), mf))
    body.save(os.path.join(OUT, "body.png"))
    fan = base.copy()
    fan.putalpha(Image.composite(base.getchannel("A"), Image.new("L", CANVAS, 0), mf))
    fan.save(os.path.join(OUT, "fan.png"))
    base.save("assets/characters/boss/boss_lizhao.png")

    prev = Image.new("RGBA", CANVAS, (30, 26, 28, 255))
    for n in ("body", "fan"):
        prev.alpha_composite(Image.open(os.path.join(OUT, n + ".png")).convert("RGBA"))
    prev.convert("RGB").save("vibe_images/_lizhao_rig_composed.png")
    dbg = prev.copy()
    d = ImageDraw.Draw(dbg)
    d.ellipse([JOINT[0] - 6, JOINT[1] - 6, JOINT[0] + 6, JOINT[1] + 6],
              outline=(255, 255, 0, 255), width=2)
    dbg.convert("RGB").save("vibe_images/_lizhao_rig_joint.png")
    print("saved body/fan; joint", JOINT)


if __name__ == "__main__":
    main()
