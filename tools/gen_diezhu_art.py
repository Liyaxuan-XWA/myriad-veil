#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""叠纸（boss_04_c）美术替代件（无生图配额时先落盘，之后同名覆盖）。

口径来自 docs/照影界第三位BOSS_叠纸_设计案.md §六：
  · 战场 = 淡赭宣纸 + 墨渍 + 纸纤维，**整张一样亮**（方向光交给 decal，不画进 tile，
    否则一平铺就出现多个假光源 —— 执烛上一版就是这么翻车的）；
    地面平均 60~90、近黑占比 < 8%，袍体月白 ≥ 170，反差必须拉开。
  · tile 必须**可无缝平铺**：噪声一律用 wrap 周期生成，墨渍跨边界时补画对称的一份。
  · 图标同模板：256² 哑光手绘、深色描边、中央主体、四角留白。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCENES = os.path.join(ROOT, "assets", "scenes")
FX = os.path.join(ROOT, "assets", "effects", "skills")
ICON = os.path.join(ROOT, "assets", "ui", "icon")

PAPER = (220, 217, 206)
PAPER_DARK = (176, 170, 156)
OCHRE = (196, 178, 148)
INK = (28, 30, 36)
BRONZE = (138, 106, 60)
MOON = (218, 226, 236)
GOLD = (232, 210, 150)


def periodic_noise(size: int, cell: int, seed: int) -> np.ndarray:
    """wrap 周期的平滑噪声：边缘对得上，平铺不露缝"""
    rng = np.random.default_rng(seed)
    n = max(2, size // cell)
    grid = rng.random((n, n)).astype(np.float64)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize(
        (size, size), Image.BICUBIC)
    # PIL 的 resize 不周期；用四象限平移拼回无缝（等价于循环卷积）
    a = np.asarray(img, dtype=np.float64) / 255.0
    h = size // 2
    # 四象限对调：外层必须沿 **行**(axis=0) 拼，沿 axis=1 拼会拼出 2048x512 的扁图 ——
    # 那张扁图当正方形 tile 用，实机就是满屏横向扫描纹（2026-11-02 踩过）。
    return np.concatenate((
        np.concatenate((a[h:, h:], a[h:, :h]), 1),
        np.concatenate((a[:h, h:], a[:h, :h]), 1)), 0)


def ground_tile(size: int = 1024) -> Image.Image:
    low = periodic_noise(size, 128, 7)
    mid = periodic_noise(size, 34, 11)
    fiber = periodic_noise(size, 6, 23)
    arr = 0.52 * low + 0.30 * mid + 0.18 * fiber
    arr = (arr - arr.min()) / max(float(np.ptp(arr)), 1e-6)
    # 目标亮度带：平均 ~76、中位 ~74，比执烛那档略暗一点点，仍远离近黑
    val = np.clip(52 + arr * 52, 0, 255)
    base = np.stack([val, val * 0.985, val * 0.94], -1)
    img = Image.fromarray(base.astype(np.uint8), "RGB").convert("RGBA")

    d = ImageDraw.Draw(img)
    # ⚠ 不许画等间距的横竖细线：实机上 7px 横线直接变成扫描纹，整张地读成"脏屏幕"。
    #   纸纤维改成各向同性的细碎噪点（下面 stain 之前先叠一层），只给质感不给方向。
    fa = np.random.default_rng(91).random((size, size, 1)).astype(np.float32)
    arr = np.asarray(img).astype(np.float32)
    arr[..., :3] = arr[..., :3] * (0.955 + 0.09 * fa)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    # 墨渍：少量、偏淡、跨边界的补一份镜像（tileable）
    rng = np.random.default_rng(31)
    stain = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stain)
    # ⚠ 墨渍半径 24~92 + alpha 26 在实机上是一堆能数清的深灰圆点（地面大特征，
    #   而且会被误读成"假光源/假折痕"）。压到 alpha 9、σ 22、只留 5 处淡晕。
    for _ in range(5):
        cx, cy = int(rng.integers(0, size)), int(rng.integers(0, size))
        r = int(rng.integers(60, 150))
        sd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(52, 54, 60, 9))
        for dx in (-size, 0, size):
            for dy in (-size, 0, size):
                if dx == 0 and dy == 0:
                    continue
                sd.ellipse((cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r),
                           fill=(52, 54, 60, 9))
    stain = stain.filter(ImageFilter.GaussianBlur(22))
    img.alpha_composite(stain)
    # 几道「折过的纸」的浅棱：一横一竖各两条，比墨渍亮、比纸面硬
    crease = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crease)
    # ⚠ 地面里绝不能有直线：那是这套机制自己的语言（折痕画在地上），
    #   画进 tile 就等于满场假折痕。四道浅棱全部去掉，只留撕口与纤维。
    for pos, horiz in []:
        a = (250, 248, 240, 34)
        b = (110, 104, 92, 26)
        if horiz:
            cd.line((0, pos, size, pos), fill=a, width=2)
            cd.line((0, pos + 3, size, pos + 3), fill=b, width=2)
        else:
            cd.line((pos, 0, pos, size), fill=a, width=2)
            cd.line((pos + 3, 0, pos + 3, size), fill=b, width=2)
    crease = crease.filter(ImageFilter.GaussianBlur(1.1))
    img.alpha_composite(crease)
    return img.convert("RGB")


def fold_seal(size: int = 512) -> Image.Image:
    """场心令印：一枚被折过三次的纸印 —— 八角硬折轮廓 + 中央一道折棱，不用圆环"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size * 0.5
    r = size * 0.40
    pts = []
    for i in range(8):
        ang = i * 0.25 * 3.14159265 + 0.196
        rr = r * (1.0 if i % 2 == 0 else 0.80)
        pts.append((c + rr * np.cos(ang), c + rr * np.sin(ang)))
    d.polygon(pts, fill=(24, 26, 32, 44), outline=(200, 206, 216, 96))
    d.line((pts[0], pts[4]), fill=(226, 230, 238, 110), width=4)
    d.line((pts[2], pts[6]), fill=(226, 230, 238, 78), width=3)
    for i in range(8):
        d.line((c, c, pts[i][0], pts[i][1]), fill=(150, 156, 168, 46), width=2)
    return img.filter(ImageFilter.GaussianBlur(0.8))


def icon_bg(size: int = 256):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def outline(d, pts, width=6):
    d.line(list(pts) + [pts[0]], fill=(24, 26, 32, 255), width=width, joint="curve")


def skill_press(img: Image.Image) -> None:
    """按纸：一只手掌压住一张对折的纸，折缝亮一道"""
    d = ImageDraw.Draw(img)
    d.polygon([(54, 176), (202, 168), (214, 92), (66, 104)], fill=PAPER + (255,))
    outline(d, [(54, 176), (202, 168), (214, 92), (66, 104)])
    d.line((60, 140, 208, 128), fill=(250, 250, 246, 255), width=5)
    d.line((60, 146, 208, 134), fill=(96, 92, 84, 200), width=3)
    d.ellipse((96, 62, 168, 134), fill=MOON + (255,))
    outline(d, [(110, 74), (154, 74), (164, 108), (100, 112)], 5)
    for a in range(4):
        x = 108 + a * 14
        d.line((x, 78, x - 4, 112), fill=(120, 130, 146, 220), width=4)


def skill_trace(img: Image.Image) -> None:
    """循痕：一条斜折棱贯穿，一把镇尺贴着棱滑出去"""
    d = ImageDraw.Draw(img)
    d.line((28, 208, 228, 58), fill=(250, 250, 246, 255), width=9)
    d.line((28, 216, 228, 66), fill=(70, 68, 64, 160), width=4)
    d.polygon([(78, 150), (178, 92), (188, 110), (88, 168)], fill=BRONZE + (255,))
    outline(d, [(78, 150), (178, 92), (188, 110), (88, 168)], 5)
    for i in range(4):
        t = 0.18 + i * 0.2
        x, y = 28 + 200 * t, 208 - 150 * t
        d.line((x - 10, y - 12, x + 10, y + 12), fill=(232, 236, 242, 170), width=3)


def skill_stride(img: Image.Image) -> None:
    """跨缝：两枚圆牌之间一条棱，一个纸人从右侧那枚立出来"""
    d = ImageDraw.Draw(img)
    d.ellipse((30, 112, 84, 166), fill=MOON + (230,), outline=(24, 26, 32, 255), width=5)
    d.ellipse((172, 112, 226, 166), fill=MOON + (230,), outline=(24, 26, 32, 255), width=5)
    d.line((57, 139, 199, 139), fill=(250, 250, 246, 230), width=6)
    d.polygon([(150, 60), (176, 66), (182, 112), (146, 110)], fill=PAPER + (255,))
    outline(d, [(150, 60), (176, 66), (182, 112), (146, 110)], 5)


def skill_seam(img: Image.Image) -> None:
    """裁痕：一把镇尺压在一道刚立起的折棱上，棱两侧错位"""
    d = ImageDraw.Draw(img)
    d.polygon([(40, 190), (126, 92), (216, 128), (128, 224)], fill=PAPER_DARK + (255,))
    d.polygon([(40, 190), (126, 92), (128, 60), (44, 150)], fill=PAPER + (255,))
    outline(d, [(44, 150), (126, 92), (216, 128), (128, 224)], 5)
    d.line((44, 150, 128, 60), fill=(250, 250, 246, 255), width=6)
    d.polygon([(96, 46), (196, 74), (192, 90), (92, 62)], fill=BRONZE + (255,))
    outline(d, [(96, 46), (196, 74), (192, 90), (92, 62)], 4)


def skill_shroud(img: Image.Image) -> None:
    """叠掩：三层错开的纸片盖住一团光"""
    d = ImageDraw.Draw(img)
    for i, (dx, dy, col) in enumerate([(0, 24, PAPER_DARK), (14, 8, PAPER), (-12, -8, MOON)]):
        pts = [(70 + dx, 96 + dy), (186 + dx, 84 + dy), (198 + dx, 168 + dy), (78 + dx, 180 + dy)]
        d.polygon(pts, fill=col + (255,))
        outline(d, pts, 5)
    d.ellipse((112, 116, 148, 152), fill=(250, 248, 238, 255))


def skill_tear(img: Image.Image) -> None:
    """碎痕：一条棱从中间断开，纸屑向两侧翻"""
    d = ImageDraw.Draw(img)
    d.line((26, 128, 108, 128), fill=(250, 250, 246, 255), width=10)
    d.line((148, 128, 230, 128), fill=(250, 250, 246, 255), width=10)
    d.line((26, 138, 108, 138), fill=(74, 70, 64, 170), width=4)
    rng = np.random.default_rng(5)
    for i in range(9):
        x = 96 + int(rng.integers(-6, 160))
        y = 128 + int(rng.integers(-56, 56))
        s = int(rng.integers(9, 22))
        d.polygon([(x, y), (x + s, y - s // 2), (x + s - 4, y + s // 2)],
                  fill=PAPER + (230,))


def skill_twin(img: Image.Image) -> None:
    """双屏：两枚圆牌各立一具纸影，两道线合向中间"""
    d = ImageDraw.Draw(img)
    for cx in (62, 194):
        d.ellipse((cx - 22, 150, cx + 22, 194), fill=MOON + (230,),
                  outline=(24, 26, 32, 255), width=5)
        d.polygon([(cx - 18, 62), (cx + 16, 68), (cx + 12, 150), (cx - 22, 146)],
                  fill=PAPER + (240,))
        outline(d, [(cx - 18, 62), (cx + 16, 68), (cx + 12, 150), (cx - 22, 146)], 4)
    d.line((62, 96, 128, 116), fill=(250, 250, 246, 235), width=6)
    d.line((194, 96, 128, 116), fill=(250, 250, 246, 235), width=6)


def skill_triple(img: Image.Image) -> None:
    """三重落纸：三片纸面错落成三角形，各带一条亮棱"""
    d = ImageDraw.Draw(img)
    for cx, cy in [(78, 96), (176, 108), (120, 182)]:
        pts = [(cx - 40, cy), (cx, cy - 28), (cx + 40, cy), (cx, cy + 28)]
        d.polygon(pts, fill=PAPER + (255,))
        outline(d, pts, 5)
        d.line((cx - 40, cy, cx + 40, cy), fill=(250, 250, 246, 240), width=5)


def skill_measure(img: Image.Image) -> None:
    """量折：一把镇尺量在折痕上，旁边一枚对位圆牌"""
    d = ImageDraw.Draw(img)
    d.line((34, 172, 222, 96), fill=(250, 250, 246, 255), width=8)
    d.polygon([(88, 118), (198, 76), (202, 94), (92, 136)], fill=BRONZE + (255,))
    outline(d, [(88, 118), (198, 76), (202, 94), (92, 136)], 4)
    d.ellipse((150, 146, 208, 204), fill=MOON + (235,), outline=(24, 26, 32, 255), width=5)
    d.ellipse((170, 166, 188, 184), fill=(24, 26, 32, 255))


def mat_zhihen(img: Image.Image) -> None:
    """照影纸痕：一条对折的纸，折缝发亮、两端起毛"""
    d = ImageDraw.Draw(img)
    d.polygon([(58, 196), (96, 58), (160, 44), (198, 178), (128, 210)],
              fill=PAPER + (255,))
    outline(d, [(58, 196), (96, 58), (160, 44), (198, 178), (128, 210)], 6)
    d.line((96, 58, 128, 210), fill=(252, 252, 248, 255), width=7)
    d.line((160, 44, 128, 210), fill=(122, 118, 108, 190), width=4)


def soul_diezhi(img: Image.Image) -> None:
    """叠纸元魂：凡界 boss-soul 画法 —— 一枚纸人形残魂在光团里，四周暗"""
    d = ImageDraw.Draw(img)
    d.ellipse((28, 28, 228, 228), fill=(18, 20, 26, 255))
    d.ellipse((62, 62, 194, 194), fill=(52, 58, 70, 255))
    d.polygon([(102, 74), (154, 82), (166, 140), (128, 166), (92, 142)],
              fill=(226, 232, 240, 210))
    d.line((128, 78, 128, 164), fill=(250, 250, 246, 240), width=5)
    d.ellipse((108, 158, 148, 198), fill=(176, 196, 226, 160))


def treasure_ling(img: Image.Image) -> None:
    """叠纸令：一枚对折的纸令牌，中间一道青铜镇尺压着"""
    d = ImageDraw.Draw(img)
    d.polygon([(64, 40), (192, 46), (196, 210), (60, 216)], fill=PAPER + (255,))
    outline(d, [(64, 40), (192, 46), (196, 210), (60, 216)], 7)
    d.line((128, 44, 128, 212), fill=(252, 252, 248, 255), width=6)
    d.polygon([(78, 112), (178, 104), (180, 126), (80, 136)], fill=BRONZE + (255,))
    outline(d, [(78, 112), (178, 104), (180, 126), (80, 136)], 5)
    d.rectangle((112, 170, 144, 202), fill=(122, 32, 30, 255))


def treasure_zhefu(img: Image.Image) -> None:
    """照影·迟照符：一符三折，符胆是三道平行棱（旧图标，机制已于 2026-11-07 重制）"""
    d = ImageDraw.Draw(img)
    d.polygon([(76, 30), (180, 34), (192, 214), (66, 220)], fill=(232, 226, 208, 255))
    outline(d, [(76, 30), (180, 34), (192, 214), (66, 220)], 7)
    for y in (86, 128, 170):
        d.line((86, y, 176, y - 10), fill=(252, 252, 248, 255), width=7)
        d.line((86, y + 5, 176, y - 5), fill=(92, 88, 80, 190), width=3)
    d.ellipse((104, 40, 156, 66), fill=MOON + (230,), outline=(24, 26, 32, 255), width=4)


def eq_zhicuo(img: Image.Image) -> None:
    """纸错剑：一柄薄成一页纸的剑，剑身中段有一道硬折"""
    d = ImageDraw.Draw(img)
    d.polygon([(60, 196), (150, 66), (176, 58), (168, 88), (78, 214)],
              fill=(224, 228, 236, 255))
    outline(d, [(60, 196), (150, 66), (176, 58), (168, 88), (78, 214)], 6)
    d.line((84, 186, 166, 74), fill=(252, 252, 250, 230), width=5)
    d.polygon([(150, 66), (176, 58), (168, 88)], fill=(150, 158, 172, 255))
    d.line((48, 178, 96, 226), fill=BRONZE + (255,), width=12)
    d.rectangle((54, 200, 82, 232), fill=(96, 74, 42, 255))


def eq_zhehen(img: Image.Image) -> None:
    """折痕佩：一枚压平的纸痕玉佩，三道平行棱 + 穿绳"""
    d = ImageDraw.Draw(img)
    d.polygon([(70, 62), (186, 54), (200, 158), (128, 208), (58, 156)],
              fill=(226, 222, 208, 255))
    outline(d, [(70, 62), (186, 54), (200, 158), (128, 208), (58, 156)], 7)
    for i in range(3):
        y = 96 + i * 26
        d.line((74, y, 184, y - 12), fill=(252, 252, 248, 245), width=6)
        d.line((74, y + 4, 184, y - 8), fill=(104, 100, 92, 170), width=3)
    d.line((128, 30, 128, 62), fill=(74, 62, 48, 255), width=7)


def weapon_zhicuo() -> Image.Image:
    """纸错剑局内贴图：与 changye_ren 同口径 —— 512² 画布、剑尖朝上、竖直摆放，
    ArtDB 里 sprite_rotation_deg = -90 会把它转到持握方向。剑身中段有一道硬折。"""
    w = 512
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    blade = [(238, 44), (276, 52), (284, 250), (230, 250)]
    d.polygon(blade, fill=(226, 230, 238, 255))
    d.line(blade + [blade[0]], fill=(26, 28, 32, 255), width=6, joint="curve")
    # 中段那道硬折：一侧压深一档，读得出这柄剑是「折出来的」不是「锻出来的」
    d.polygon([(284, 250), (276, 52), (292, 60), (296, 250)], fill=(150, 158, 172, 255))
    d.line((232, 150, 292, 142), fill=(250, 250, 248, 230), width=5)
    d.line((232, 156, 292, 148), fill=(92, 96, 106, 190), width=3)
    # 护手与柄：青铜，压纸尺的造型
    d.polygon([(196, 254), (316, 246), (318, 274), (198, 282)], fill=BRONZE + (255,))
    d.line([(196, 254), (316, 246), (318, 274), (198, 282), (196, 254)],
           fill=(26, 28, 32, 255), width=5)
    d.rectangle((240, 282, 272, 402), fill=(96, 74, 42, 255))
    d.line((240, 300, 272, 300), fill=(30, 26, 20, 200), width=4)
    d.line((240, 330, 272, 330), fill=(30, 26, 20, 200), width=4)
    d.line((240, 360, 272, 360), fill=(30, 26, 20, 200), width=4)
    d.ellipse((238, 398, 276, 430), fill=BRONZE + (255,), outline=(26, 28, 32, 255), width=5)
    return img


SKILL_ART = {
    "skill_fold_press": skill_press,
    "skill_fold_trace": skill_trace,
    "skill_fold_stride": skill_stride,
    "skill_fold_seam": skill_seam,
    "skill_fold_shroud": skill_shroud,
    "skill_fold_tear": skill_tear,
    "skill_fold_twin": skill_twin,
    "skill_fold_triple": skill_triple,
    "skill_fold_measure": skill_measure,
}


def save(img: Image.Image, folder: str, name: str) -> None:
    os.makedirs(folder, exist_ok=True)
    p = os.path.join(folder, name)
    img.save(p)
    print("wrote", p)


def main() -> None:
    g = ground_tile(1024)
    a = np.asarray(g, dtype=np.float64)
    print("地面：平均 %.1f 中位 %.1f 近黑 %.1f%%" % (
        a.mean(), np.median(a), (a.mean(-1) < 24).mean() * 100.0))
    save(g, SCENES, "zhaoying_fold_arena_ground.png")
    save(fold_seal(512), FX, "fold_seal.png")

    for key, fn in SKILL_ART.items():
        img, _ = icon_bg(256)
        fn(img)
        save(img, ICON, key + ".png")

    save(weapon_zhicuo(), os.path.join(ROOT, "assets", "effects", "weapons"),
         "zhicuo_jian.png")
    for name, fn in [("mat_zhaoying_zhihen", mat_zhihen), ("soul_diezhi", soul_diezhi),
                     ("tr_diezhi_ling", treasure_ling), ("tr_zhaoying_zhefu", treasure_zhefu),
                     ("equip_zhicuo_jian", eq_zhicuo), ("equip_zhehen_pei", eq_zhehen)]:
        img, _ = icon_bg(256)
        fn(img)
        save(img, ICON, name + ".png")


if __name__ == "__main__":
    main()
