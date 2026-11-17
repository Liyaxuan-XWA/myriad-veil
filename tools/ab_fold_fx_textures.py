"""折棱 / 圆牌：程序化贴图 vs 外部生图 的实机尺度 A/B（2026-11-03）

结论要能算出来，不能靠看图感觉。两边都按**游戏里真实显示的像素尺寸**画到
照影界·叠纸战场的真实地面上，再量三条读数：
  · 纵向羽化宽度（alpha 落到峰值 5% 的总厚度）—— 决定读不读得出「纸吃光的棱」
  · 亮芯宽度（>=90% 峰值）—— 太宽糊、太窄就是激光线
  · 中心是否透亮（圆牌牌心 alpha）—— 牌心要能压住代码画的编号点

贴图公式逐行照抄 scripts/visual/skill_fx.gd 的 fold_ridge_texture() /
fold_disc_texture()，不另写一套近似的。
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "assets" / "effects" / "skills"
GROUND = ROOT / "assets" / "scenes" / "zhaoying_fold_arena_ground.png"
OUT = ROOT / "output" / "fold_ab.png"

RIDGE_W, RIDGE_H = 512, 64
DISC_S = 256
SEAM_R = 62.0
DISC_ON_SCREEN = SEAM_R * 2.0 * 1.35      # fold_seam.gd 的真实显示直径


def smoothstep(a: float, b: float, x):
    t = np.clip((x - a) / max(b - a, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def ridge_proc() -> np.ndarray:
    img = np.zeros((RIDGE_H, RIDGE_W, 4), np.float32)
    mid = (RIDGE_H - 1) * 0.5
    ys = np.arange(RIDGE_H, dtype=np.float32)
    dy = np.abs(ys - mid)
    core = np.exp(-np.power(dy / 1.5, 2.0))
    halo = np.exp(-np.power(dy / 17.0, 2.0)) * 0.20
    a_row = np.clip(core + halo, 0.0, 1.0)
    xs = np.arange(RIDGE_W, dtype=np.float32)
    jitter = 1.0 + 0.14 * np.sin(xs * 0.121) + 0.09 * np.sin(xs * 0.031 + 1.7)
    u = xs / float(RIDGE_W - 1)
    taper = smoothstep(0.0, 0.12, u) * smoothstep(0.0, 0.12, 1.0 - u)
    a = np.clip(a_row[:, None] * jitter[None, :] * taper[None, :], 0.0, 1.0)
    img[..., :3] = 255.0
    img[..., 3] = a * 255.0
    return img


def disc_proc() -> np.ndarray:
    img = np.zeros((DISC_S, DISC_S, 4), np.float32)
    c = (DISC_S - 1) * 0.5
    yy, xx = np.mgrid[0:DISC_S, 0:DISC_S].astype(np.float32)
    r = np.hypot(xx - c, yy - c) / c
    body = np.clip(1.0 - smoothstep(0.44, 0.98, r), 0.0, 1.0)
    inner = np.clip(1.0 - smoothstep(0.0, 0.52, r), 0.0, 1.0) * 0.55
    rim = np.exp(-np.power((r - 0.70) / 0.085, 2.0)) * 0.55
    lum = np.clip(body * 0.62 + inner * body, 0.0, 1.0) * (1.0 - rim * 0.8)
    img[..., :3] = 255.0
    img[..., 3] = np.maximum(lum, rim * body * 0.42) * 255.0
    return img


def load_png(name: str) -> np.ndarray:
    return np.asarray(Image.open(SKILLS / name).convert("RGBA"), np.float32)


def metrics(a: np.ndarray, label: str) -> list[str]:
    al = a[..., 3] / 255.0
    out = [label]
    if a.shape[0] == RIDGE_H and a.shape[1] == RIDGE_W:
        prof = al.max(axis=1)
        pk = max(prof.max(), 1e-6)
        ys = np.arange(len(prof))
        feather = int((prof >= 0.05 * pk).sum())
        core = int((prof >= 0.90 * pk).sum())
        rgb = a[..., :3][al > 0.5].mean(axis=0) if (al > 0.5).any() else np.zeros(3)
        out.append(f"  亮芯 {core:2d}px   羽化总厚 {feather:2d}px / {a.shape[0]}   RGB均值 {rgb.round(0)}")
    else:
        s = a.shape[0]
        c = (s - 1) / 2
        yy, xx = np.mgrid[0:s, 0:s]
        r = np.hypot(xx - c, yy - c) / c
        pk = max(al.max(), 1e-6)
        band = r[al >= 0.5 * pk]
        centre = al[(yy - c) ** 2 + (xx - c) ** 2 <= (0.12 * c) ** 2]
        out.append(f"  >=50% 峰值半径 {band.min() if band.size else 0:.2f}~{band.max() if band.size else 0:.2f}"
                   f"   牌心 alpha {centre.mean():.2f}（编号点压得住需 >=0.25）")
    return out


def paste_over(ground: Image.Image, a: np.ndarray, box, additive: bool, tone,
               alpha_scale: float = 1.0) -> None:
    """按真实显示尺寸贴到地面上：box=(x, y, w, h) 目标屏幕矩形。"""
    im = Image.fromarray(a.astype(np.uint8), "RGBA").resize((box[2], box[3]), Image.LANCZOS)
    arr = np.asarray(im, np.float32)
    arr[..., :3] *= np.array(tone, np.float32)
    al = (arr[..., 3:4] / 255.0) * alpha_scale
    x, y, w, h = box
    region = np.asarray(ground.crop((x, y, x + w, y + h)), np.float32)
    if additive:
        blended = region + arr[..., :3] * al
    else:
        blended = region * (1.0 - al) + arr[..., :3] * al
    out = Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8), "RGB")
    ground.paste(out, (x, y))


def draw_crease(g: Image.Image, ridge: np.ndarray, x0: int, ycen: int, length: int) -> None:
    """照抄 FoldVisual._apply() 的三层叠法：墨影(lip) → 加色宽羽化(glow) → 月白芯(core)。"""
    h = ridge.shape[0]
    tone = (0.86, 0.92, 0.98)
    core_tone = tuple(np.array(tone) * 0.45 + 0.55)
    # _lip: 普通混合、近黑、scale(0.94, 0.62)、沿法向 +15px
    paste_over(g, ridge, (x0 + int(length * 0.03), ycen + 15 - int(h * 0.62 / 2),
                          int(length * 0.94), int(h * 0.62)), False, (0.06, 0.07, 0.09), 0.40)
    # _glow: 加色、scale y ×1.55
    paste_over(g, ridge, (x0, ycen - int(h * 1.55 / 2), length, int(h * 1.55)),
               True, tone, 0.20)
    # _core: 普通混合、月白偏白、alpha 0.72
    paste_over(g, ridge, (x0, ycen - h // 2, length, h), False, core_tone, 0.72)


def readability(g: Image.Image, x0: int, ycen: int, length: int) -> tuple:
    """折痕是这套机制唯一的读数 —— 量它在地面上到底跳出来多少。"""
    a = np.asarray(g.crop((x0, ycen - 26, x0 + length, ycen + 26)), np.float32)
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    rows = np.abs(np.arange(lum.shape[0]) - 26.0)
    core = lum[rows <= 3.0].mean()
    ground = lum[rows >= 20.0].mean()
    dark = lum[rows <= 3.0].min()
    return core, ground, dark


def main() -> None:
    ridge_p, ridge_g = ridge_proc(), load_png("fold_ridge.png")
    disc_p, disc_g = disc_proc(), load_png("fold_seam_disc.png")

    print("=== 折棱（真实显示：长 900px × 高 64px）===")
    for line in metrics(ridge_p, "程序化") + metrics(ridge_g, "生  图"):
        print(line)
    print("=== 对位圆牌（真实显示直径 %.0fpx）===" % DISC_ON_SCREEN)
    for line in metrics(disc_p, "程序化") + metrics(disc_g, "生  图"):
        print(line)

    TONE = (0.86, 0.92, 0.98)
    W, LENGTH, X0 = 1000, 880, 60
    rows = [("折棱 · 程序化", ridge_p, "ridge"), ("折棱 · 生图", ridge_g, "ridge"),
            ("圆牌 · 程序化", disc_p, "disc"), ("圆牌 · 生图", disc_g, "disc")]
    sheet = Image.new("RGB", (W, 320 * len(rows)), (12, 12, 16))
    d = ImageDraw.Draw(sheet)
    for i, (label, tex, kind) in enumerate(rows):
        g = Image.open(GROUND).convert("RGB").resize((W, 320), Image.LANCZOS)
        if kind == "ridge":
            yc = 160
            draw_crease(g, tex, X0, yc, LENGTH)
            core, ground, dark = readability(g, X0 + 80, yc, LENGTH - 160)
            d.text((8, yc - 46), f"{label}   芯亮度 {core:.0f} / 地面 {ground:.0f} "
                                 f"→ 反差 +{core - ground:.0f}   暗部最低 {dark:.0f}",
                   fill=(255, 230, 150))
        else:
            s = int(DISC_ON_SCREEN)
            dd = ImageDraw.Draw(g)
            for j, cx in enumerate((W * 0.32, W * 0.62)):
                paste_over(g, tex, (int(cx - s / 2), int(160 - s / 2), s, s), False, TONE, 0.68)
                for k in range(1 + j):
                    px = cx + (k - 0.5 * j) * SEAM_R * 0.44
                    dd.ellipse((px - 6, 160 - 6, px + 6, 160 + 6), fill=(26, 28, 36))
            a = np.asarray(g, np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)
            c0 = int(W * 0.32)
            centre = a[156:164, c0 - 4:c0 + 4].mean()
            ring = a[160 - int(s * 0.31):160 + int(s * 0.31),
                     c0 + int(s * 0.28):c0 + int(s * 0.36)].mean()
            d.text((8, 8), f"{label}   牌心 {centre:.0f}   环带 {ring:.0f}   "
                           f"编号点(26) 对牌心反差 {abs(centre - 26):.0f}",
                   fill=(255, 230, 150))
        sheet.paste(g, (0, i * 320))
    sheet.save(OUT)
    print("A/B ->", OUT)


if __name__ == "__main__":
    main()
