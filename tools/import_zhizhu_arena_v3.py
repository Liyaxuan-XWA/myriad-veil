"""执烛战场重做（2026-11-02 第三轮生图）

用户给两张：月白石坪地面（384²）+ 灯下光池（1024²黑底）。
两张都不能直接用，各自有硬伤，这里做本地修复（**不重画、不加滤镜换媒介**，
只是把平铺缺陷和亮度压到可用区间）：

地面三处硬伤
  1. 左右对比度不均：两侧砖密且深、中间发白 → 平铺出现**重复的竖向密砖条纹**；
     中央还有一圈低频圆形划痕。→ 压平整张图的低频亮度（减掉大尺度亮度场再补一小部分）。
  2. 平均亮度 202（我要的是 65–80）→ 归一到 74 并把极亮压到 150 以内，
     免得和影尖的冷焰、HUD 抢。
  3. 右下角「豆包AI生成」→ 平铺会重复 N 次，必须先擦。
  4. 对边差 9.4 / 11.3（>12 就算明显接缝）→ roll 到中心做十字羽化再 roll 回去。

光池一处硬伤：椭圆边缘有一圈 1–3px 的亮色锯齿线 —— 用户明确不要硬边圆环，
用中值滤波把细亮线吃掉，保留柔和衰减。
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter, median_filter

ROOT = r"D:\GodotProjects\myriad-veil"
VIBE = os.path.join(ROOT, "vibe_images")
SCENES = os.path.join(ROOT, "assets", "scenes")
SKILLS = os.path.join(ROOT, "assets", "effects", "skills")

TARGET_MEAN = 74.0
TARGET_MAX = 150.0
LUM_W = np.array([0.299, 0.587, 0.114], np.float32)


def scrub(im, box=(0.72, 0.88, 1.0, 1.0), radius=9):
    """水印框内高斯模糊抹掉字，再把这块「太平滑」的补丁补回周围的质感。

    只模糊会留下一块比四周光滑的浅色糊斑（石纹有颗粒、补丁没有），
    平铺时一眼就能看出「这里被动过」。所以补两步：
      1) 把补丁的均值对齐到它外围一圈环带的均值（水印字偏亮，模糊后整块抬白）；
      2) 从左上角干净区搬一份**高频细节**叠回去（只搬 detail，不搬低频图案）。
    """
    a = np.asarray(im.convert("RGB"), np.float32)
    h, w, _ = a.shape
    x0, y0 = int(w * box[0]), int(h * box[1])
    pw, ph = w - x0, h - y0
    # 环带：补丁外扩 14px 的一圈
    ex = min(14, x0, y0)
    ring = a[y0 - ex:h, x0 - ex:w]
    ring_mean = ring.reshape(-1, 3).mean(axis=0)
    # 干净参照区：左上角同尺寸
    clean = a[0:ph, 0:pw]
    blurred = np.asarray(im.filter(ImageFilter.GaussianBlur(radius)).convert("RGB"), np.float32)
    patch = blurred[y0:h, x0:w].copy()
    patch += (ring_mean - patch.reshape(-1, 3).mean(axis=0))[None, None, :]
    # 高频：干净区减去它自己的低频
    src = a[0:ph, 0:pw]
    detail = src - gaussian_filter(src, (3.0, 3.0, 0.0), mode="nearest")
    patch += detail * 0.85
    # 边缘羽化，别切出方框
    yy, xx = np.mgrid[0:ph, 0:pw]
    feather = np.minimum.reduce([
        np.clip(xx / 10.0, 0, 1), np.clip((pw - 1 - xx) / 3.0, 0, 1),
        np.clip(yy / 10.0, 0, 1), np.clip((ph - 1 - yy) / 3.0, 0, 1)])[..., None]
    a[y0:h, x0:w] = a[y0:h, x0:w] * (1 - feather) + patch * feather
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def flatten_low_freq(arr, sigma=26.0, keep=0.14):
    """减掉大尺度亮度场（竖条纹 / 中心划痕），只保留一小部分呼吸感。"""
    out = arr.copy()
    for c in range(3):
        base = gaussian_filter(arr[..., c], sigma, mode="wrap")   # wrap = 按平铺图处理，边缘不炸开
        detail = arr[..., c] - base
        mean = float(base.mean())
        out[..., c] = mean + detail + (base - mean) * keep
    return np.clip(out, 0.0, 255.0)


def normalize(arr):
    lum = arr @ LUM_W
    arr = arr * float(TARGET_MEAN / max(float(lum.mean()), 1.0))
    lum = arr @ LUM_W
    over = lum > TARGET_MAX
    if over.any():
        arr[over] *= (TARGET_MAX / lum[over])[..., None]
    return np.clip(arr, 0.0, 255.0)


def cool_tint(arr, sat=0.62):
    lum = (arr @ LUM_W)[..., None]
    mixed = lum + (arr - lum) * sat
    # 月白偏冷：蓝略抬、红略压
    mixed[..., 0] *= 0.965
    mixed[..., 2] *= 1.045
    return np.clip(mixed, 0.0, 255.0)


def seam_fix(img, band=26, strength=0.9):
    """把接缝滚到中心做十字羽化，再滚回去。"""
    a = np.asarray(img.convert("RGB"), np.float32)
    h, w, _ = a.shape
    a = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    blur = gaussian_filter(a, (band / 2.2, band / 2.2, 0.0), mode="wrap")
    cy, cx = h // 2, w // 2
    yy, xx = np.mgrid[0:h, 0:w]
    wy = np.clip(1.0 - np.abs(yy - cy) / float(band), 0.0, 1.0)
    wx = np.clip(1.0 - np.abs(xx - cx) / float(band), 0.0, 1.0)
    m = (np.maximum(wy, wx) * strength)[..., None]
    a = a * (1.0 - m) + blur * m
    a = np.roll(np.roll(a, h - cy, axis=0), w - cx, axis=1)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def edge_diff(img):
    g = np.asarray(img.convert("L"), np.float32)
    return (float(np.abs(g[:, :6] - g[:, -6:]).mean()),
            float(np.abs(g[:6, :] - g[-6:, :]).mean()))


def build_ground():
    im = scrub(Image.open(os.path.join(VIBE, "zhizhu_ground_v3.png")).convert("RGB"))
    arr = np.asarray(im, np.float32)
    arr = flatten_low_freq(arr)
    arr = normalize(arr)
    arr = cool_tint(arr)
    flat = Image.fromarray(arr.astype(np.uint8), "RGB")
    big = flat.resize((1024, 1024), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(1.1))
    big = big.filter(ImageFilter.UnsharpMask(radius=2.4, percent=52, threshold=2))
    big = seam_fix(big)
    out = os.path.join(SCENES, "zhaoying_lamp_arena_ground.png")
    big.save(out)
    a = np.asarray(big, np.float32)
    lum = a @ LUM_W
    print("地面 1024sq  平均 %.1f 中位 %.1f 近黑 %.1f%% >=150 %.1f%%  对边差 %.1f / %.1f" % (
        lum.mean(), np.median(lum), (lum < 25).mean() * 100, (lum >= 150).mean() * 100,
        *edge_diff(big)))
    t = Image.new("RGB", (2048, 2048))
    for y in range(2):
        for x in range(2):
            t.paste(big, (x * 1024, y * 1024))
    t.resize((760, 760), Image.LANCZOS).save(os.path.join(ROOT, "output", "z3_ground_tiled4.png"))


def build_pool():
    im = Image.open(os.path.join(VIBE, "zhizhu_lamppool_v3.png")).convert("RGB")
    a = np.asarray(im, np.float32)
    alpha = a.max(axis=2)
    # 吃掉椭圆边缘那圈 1–3px 亮锯齿（不要硬边圆环）
    alpha = median_filter(alpha, size=7, mode="nearest")
    alpha = gaussian_filter(alpha, 2.2, mode="nearest")
    alpha = np.clip((alpha / max(float(alpha.max()), 1.0)) ** 1.18 * 255.0, 0.0, 255.0)
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.sqrt(((xx - w / 2) / (w * 0.46)) ** 2 + ((yy - h / 2) / (h * 0.40)) ** 2)
    alpha = alpha * np.clip(1.25 - r, 0.0, 1.0)          # 再压一层径向柔边
    # 冷银为主，中心一点点暖（铜灯是唯一暖点）
    core = np.clip(1.0 - r * 1.6, 0.0, 1.0)
    col = np.zeros((h, w, 3), np.float32)
    col[..., 0] = 0.80 + core * 0.14
    col[..., 1] = 0.88 + core * 0.06
    col[..., 2] = 1.00 - core * 0.06
    out = np.dstack([np.clip(col * 255.0, 0, 255), alpha]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA").resize((512, 512), Image.LANCZOS)
    img.save(os.path.join(SKILLS, "lamp_pool.png"))
    print("光池 512sq  峰值 alpha %.0f  覆盖(a>20) %.1f%%" % (
        alpha.max(), float((np.asarray(img)[:, :, 3] > 20).mean() * 100)))
    bg = Image.new("RGB", (512, 512), (40, 44, 52))
    bg.paste(img, (0, 0), img)
    bg.save(os.path.join(ROOT, "output", "z3_pool_preview.png"))


build_ground()
build_pool()
