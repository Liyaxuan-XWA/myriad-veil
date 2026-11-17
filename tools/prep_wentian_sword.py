"""问天剑三件套导入：白底/灰石底 → 透明 PNG。

跑法：python tools/prep_wentian_sword.py
输入：豆包生成的两张不透明原片（刃尖朝上的剑 + 石台插剑设施）
输出：
  assets/ui/icon/equip_wentianjian.png        256² 透明图标，斜 45°（对齐现有 equip_* 图标）
  assets/effects/weapons/wentian_jian.png     竖直、**刃尖朝下**的局内武器贴图
  assets/scenes/world/lianqi_sword_shrine.png 石台剑设施（底边压落点用 anchor_bottom）

⚠ 为什么不用现成的 key_magenta_robust.py：那套判据是「R、B 同时明显高于 G」的洋红，
  而这两张原片是**纯白底 / 暖灰石地底**，色度判据完全不命中。
  这里改成「边界泛洪 + 白底反解（unmix）」：只删**和边框连成一片**的底色，
  被主体围住的内部高光（剑脊反光、石台亮面）不会被误删。
  ⚠ 泛洪判据用「离底色多近」而不是「离纯白多近」：石台地面是暖灰 (146,142,138)，
  四角颜色并不一致，所以底色取**边框中位色**而不是常量。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import binary_dilation, gaussian_filter, label

## key_magenta_robust 就在同一个 tools/ 目录下，脚本直接跑时要把本目录加进路径
sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parents[1]
SRC_SWORD = Path(
    r"C:/Users/q2334/.qoder-cn/tmp/D--GodotProjects-myriad-veil/images/"
    "ee70879a-5c62-4ca3-a744-3a0935076a0d/"
    "48e3c2e8-7b46-406b-9b72-4891b92b678c.png")
SRC_SHRINE = Path(
    r"C:/Users/q2334/.qoder-cn/tmp/D--GodotProjects-myriad-veil/images/"
    "ee70879a-5c62-4ca3-a744-3a0935076a0d/"
    "5d25e83d-2b80-45dd-b996-6211b5e1f0d1.png")
## 石台的**洋红底版**（图生图换底产物）：原片地面与石台同色系，色度泛洪分不开
SRC_SHRINE_MAGENTA = ROOT / "vibe_images/wentian_shrine_magenta_1794438618065_262004d9.png"

ICON_OUT = ROOT / "assets/ui/icon/equip_wentianjian.png"
WEAPON_OUT = ROOT / "assets/effects/weapons/wentian_jian.png"
SHRINE_OUT = ROOT / "assets/scenes/world/lianqi_sword_shrine.png"
DEBUG_DIR = ROOT / "output"


def border_color(rgb: np.ndarray) -> np.ndarray:
    """底色 = 四边一圈的中位色（不是常量：石台地面四角就差了 36 个亮度）。"""
    t = np.concatenate([
        rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]], axis=0)
    return np.median(t, axis=0)


def flood_key(path, tol: float = 46.0, feather: float = 0.7,
              spill: float = 0.9) -> Image.Image:
    """边界泛洪键底：只删与边框连通的近底色区域，并反解边缘的底色叠加。"""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    bg = border_color(rgb)
    dist = np.sqrt(((rgb - bg[None, None, :]) ** 2).sum(axis=2))
    near = dist < tol
    # 只保留**碰到边框**的那一片近底色：主体内部围住的亮面/反光保住了
    lab, n = label(near)
    border_labels = set(int(v) for v in np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])))
    border_labels.discard(0)
    bg_mask = np.isin(lab, list(border_labels))
    # 内侧一圈按「有多少近底邻居」给半透明，避免硬锯齿
    near_ring = binary_dilation(bg_mask, iterations=2) & ~bg_mask
    alpha = (~bg_mask).astype(np.float32)
    strength = np.clip(dist / max(1.0, tol), 0.0, 1.0)
    alpha[near_ring] = 1.0 - strength[near_ring] * 0.92
    alpha = gaussian_filter(alpha, feather)
    # 白/灰底反解：C_obs = a*C + (1-a)*bg → C = (C_obs - (1-a)*bg)/a
    a3 = np.clip(alpha, 1e-3, 1.0)[..., None]
    spill_amt = np.clip(strength * spill, 0.0, 1.0)[..., None] * (1.0 - a3)
    color = (rgb - spill_amt * bg[None, None, :]) / np.maximum(1.0 - spill_amt, 1e-3)
    color = np.clip(color, 0.0, 255.0)
    return Image.fromarray((np.dstack([color, alpha * 255.0]) + 0.5).astype(np.uint8), "RGBA")


def bbox_crop(im: Image.Image, pad: int = 6) -> Image.Image:
    """按 alpha 包围盒裁掉空边，留 pad 像素（Godot 的 used_rect 与 anchor_bottom 都要干净包围盒）。"""
    a = np.asarray(im)[..., 3]
    ys, xs = (a > 24).nonzero()
    if ys.size == 0:
        return im
    box = (max(0, xs.min() - pad), max(0, ys.min() - pad),
           min(im.width, xs.max() + 1 + pad), min(im.height, ys.max() + 1 + pad))
    return im.crop(box)


def fit_square(im: Image.Image, size: int) -> Image.Image:
    """等比放进 size² 画布，居中留边（图标模板口径：256² 透明底）。"""
    scale = min(size / im.width, size / im.height)
    w, h = max(1, int(round(im.width * scale))), max(1, int(round(im.height * scale)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return out


def report(name: str, im: Image.Image) -> None:
    a = np.asarray(im)
    ys, xs = (a[..., 3] > 24).nonzero()
    cov = (a[..., 3] > 24).mean() * 100
    soft = ((a[..., 3] > 8) & (a[..., 3] < 247)).mean() * 100
    bw = xs.max() - xs.min() + 1 if xs.size else 0
    bh = ys.max() - ys.min() + 1 if ys.size else 0
    print("%-22s 画布%s 内容%dx%d 宽高比%.2f 覆盖%.1f%% 半透明边%.1f%%" % (
        name, str(a.shape[:2][::-1]), bw, bh, (bw / bh if bh else 0), cov, soft))


def save_debug(im: Image.Image, tag: str) -> None:
    """合成到**游戏地面色**上看：白底预览永远看不出毛边。"""
    bg = Image.new("RGB", im.size, (33, 48, 38))
    bg.paste(im, (0, 0), im)
    DEBUG_DIR.mkdir(exist_ok=True)
    bg.save(DEBUG_DIR / ("prep_%s.png" % tag))


def keep_largest(im: Image.Image) -> Image.Image:
    """只留最大连通域。
    ⚠ 必须做：原片右下角有「豆包AI生成」水印，键底后它变成一小片不透明碎点，
      跟着主体一起进包围盒 —— 贴图缩到 70px 时它就是一道脏斑。
    """
    a = np.asarray(im)
    lab, n = label(a[..., 3] > 24)
    if n <= 1:
        return im
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    biggest = int(sizes.argmax())
    out = a.copy()
    out[lab != biggest, 3] = 0
    return Image.fromarray(out, "RGBA")


def erode_alpha(im: Image.Image, iterations: int = 1) -> Image.Image:
    """alpha 收边：吃掉键底留下的一圈底色毛边（洋红版就是紫溢）。"""
    a = np.asarray(im).copy()
    solid = binary_dilation(a[..., 3] <= 24, iterations=iterations)
    a[..., 3][solid] = 0
    return Image.fromarray(a, "RGBA")


def main() -> None:
    # ---- ① 剑：白底泛洪键出 → 去水印碎点 → 收边 → 裁包围盒 ----
    sword = flood_key(SRC_SWORD, tol=42.0)
    sword = erode_alpha(keep_largest(sword), 1)
    sword = bbox_crop(sword)
    report("sword keyed", sword)
    save_debug(sword, "sword_keyed")

    # 局内贴图：现有约定是**竖直、刃尖朝下**（sprite_rotation_deg 都是 -90）。
    # 原片刃尖朝上 → 转 180°。
    weapon = sword.rotate(180, expand=True)
    weapon.save(WEAPON_OUT)
    report("weapon out", weapon)
    save_debug(weapon, "weapon")

    # 图标：现有 equip_* 长条武器图标都是斜 45° 摆放（内容 bbox 宽高比 0.9~1.2）。
    icon = fit_square(sword.rotate(45, expand=True), 256)
    icon.save(ICON_OUT)
    report("icon out", icon)
    save_debug(icon, "icon")

    # ---- ② 石台：地面与石台同色系，色度泛洪分不开 ----
    #      走项目标准流程：图生图**换洋红底** → key_magenta_robust 色键 → 收边去紫溢。
    #      （见 tools/prep_new_weapon_visuals.py 与 docs/任务书交接包.md 的同一套路）
    from key_magenta_robust import key_magenta_robust
    shrine = key_magenta_robust(SRC_SHRINE_MAGENTA)
    shrine = erode_alpha(keep_largest(shrine), 2)
    shrine = bbox_crop(shrine)
    report("shrine keyed", shrine)
    save_debug(shrine, "shrine_keyed")
    # 显示口径：target_length 走 SkinVisual 的 used_rect 自动缩放，这里只保证包围盒干净
    shrine.save(SHRINE_OUT)
    save_debug(shrine, "shrine")

    print("\n输出：\n  %s\n  %s\n  %s" % (ICON_OUT, WEAPON_OUT, SHRINE_OUT))
    print("调试图（合成到游戏地面色）：%s/prep_*.png" % DEBUG_DIR)


main()
