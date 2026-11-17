"""从华彩母图（_bg + _art 1:1 合成）重出四张普通卡。

判据来自赫连霄 boss_03：他的普通卡与华彩合成是同一张插画，只差分级。
所以这里不换角色、不换构图，只做「同图不同处理」：
  1) 落地接触阴影 —— 母图是俯视地面 + 平视角色，脚底没有接触关系；
  2) 静帧分级 —— 华彩那层有 emission/aura/glow，普通卡要压回平光；
  3) 四角暗角，让视线回到角色。
产物先落 output/card_fix_stage，看过再覆盖 assets。
"""
from __future__ import annotations
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
STAGE = ROOT / "output" / "card_fix_stage"
STAGE.mkdir(parents=True, exist_ok=True)
W, H = 640, 960

TARGETS = {
    "boss_03_b": "card_boss_lizhao",
    "world_core_lianqi": "card_boss_core_ape",
    "world_core_zhuji": "card_boss_core_stag",
    "world_core_jiedan": "card_boss_core_qilin",
}


def alpha_rows(a: np.ndarray):
    return np.where((a[..., 3] > 24).any(axis=1))[0]


def contact_shadow(art: Image.Image) -> tuple[Image.Image, tuple]:
    """脚底那一条 alpha 的质心与宽度 → 一枚压扁的软黑椭圆。"""
    a = np.asarray(art, np.float32)
    al = a[..., 3] / 255.0
    rows = np.where((al > 0.35).any(axis=1))[0]
    if len(rows) == 0:
        return None, None
    foot = rows[-1]
    band = al[max(0, foot - 14):foot + 1]
    cols = np.where(band.max(axis=0) > 0.35)[0]
    if len(cols) == 0:
        return None, None
    cx = float((cols.min() + cols.max()) / 2)
    wide = max(90.0, (cols.max() - cols.min()) * 0.62)
    box = (cx - wide, min(H - 6, foot + 2), cx + wide, min(H - 2, foot + 2 + wide * 0.30))
    sh = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(sh)
    d.ellipse(box, fill=150)
    sh = sh.filter(ImageFilter.GaussianBlur(13))
    return sh, box


def vignette() -> Image.Image:
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.52) / (H * 0.62)) ** 2)
    v = np.clip(1.0 - (r - 0.62) * 0.72, 0.62, 1.0)
    return Image.fromarray((v * 255).astype(np.uint8), "L")


def depth_treat(bg: Image.Image, feet_y: int) -> Image.Image:
    """把俯视地面片读出纵深：远处压暗去饱和 + 轻微失焦 + 脚下光池。

    角色层一个字都不动，只处理背景 —— 标准里「背景层可以不同」就是留这个口的。
    """
    g = np.asarray(bg, np.float32)
    yy = np.arange(H, dtype=np.float32)[:, None]
    far = np.clip((feet_y - yy) / max(feet_y, 1), 0.0, 1.0) ** 1.35   # (H,1) 广播到全宽
    a = g.copy()
    a[..., 0] *= 1.0 - far * 0.42
    a[..., 1] *= 1.0 - far * 0.46
    a[..., 2] *= 1.0 - far * 0.40
    lum = a.mean(axis=2, keepdims=True)
    a = a + (lum - a) * (far[..., None] * 0.34)
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
    # 远景失焦：只糊上三分之二
    blur = out.filter(ImageFilter.GaussianBlur(3.4))
    m = Image.fromarray(np.repeat((np.clip(far[:, 0], 0, 1) * 210).astype(np.uint8), W, axis=0).reshape(H, W), "L")
    out = Image.composite(blur, out, m)
    # 脚下光池：把角色落点那一圈抬亮，人才是站在场景里而不是贴在地上
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(np.float32)
    pool = np.exp(-(((xx2 - W / 2) / 250.0) ** 2 + ((yy2 - feet_y + 40) / 150.0) ** 2))
    pool = np.clip(pool, 0, 1)[..., None] * np.array([1.0, 0.94, 0.78], np.float32)
    a2 = np.clip(np.asarray(out, np.float32) * (1.0 + pool * 0.26), 0, 255)
    return Image.fromarray(a2.astype(np.uint8), "RGB")


def build(name: str, out_key: str) -> None:
    art = Image.open(HOLO / f"{name}_art.png").convert("RGBA")
    bg = Image.open(HOLO / f"{name}_bg.png").convert("RGB")
    rows = np.where((np.asarray(art)[..., 3] > 0.35 * 255).any(axis=1))[0]
    bg = depth_treat(bg, int(rows[-1]) if len(rows) else 893)
    flat = bg.copy()
    sh, box = contact_shadow(art)
    if sh is not None:
        dark = Image.new("RGB", (W, H), (4, 4, 6))
        flat = Image.composite(dark, flat, sh.point(lambda v: int(v * 0.72)))
    flat.paste(art, (0, 0), art)
    # 静帧分级：轻微压亮部、抬对比、收一点饱和，去掉华彩层的浮光感
    flat = ImageEnhance.Contrast(flat).enhance(1.06)
    flat = ImageEnhance.Color(flat).enhance(0.94)
    flat = ImageEnhance.Brightness(flat).enhance(0.97)
    black = Image.new("RGB", (W, H), (6, 6, 9))
    flat = Image.composite(black, flat, vignette().point(lambda v: 255 - v))
    flat.save(STAGE / f"{out_key}.png")
    a = np.asarray(flat, np.float32)
    print(f"{out_key:26s} mean={a.mean():5.1f} median={np.median(a):5.1f} shadow={box}")


for n, k in TARGETS.items():
    build(n, k)
