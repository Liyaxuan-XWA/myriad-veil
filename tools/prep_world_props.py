#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""大世界实体（灵气团 / 传送门）的出图整形：抹水印 → 抠底 → 裁到内容 → 落 assets。

两张图走两条不同的底：
  灵气团  纯黑底 + 加色混合。发光的东西没有「边缘」，抠出来一定带锯；
          加色混合下黑底自己就消失了，连 alpha 都不需要。所以这里**不抠图**，
          只把水印涂黑 + 按亮度裁方。
  传送门  品红底 + 常规 alpha。石头是不发光的实体，必须真抠。复用 BOSS 序列帧
          那套 key_out（背景色从四角实测、带溢色抑制），不另写一份判据。

用法：
    python tools/prep_world_props.py            # 出图到 assets/scenes/world/
    python tools/prep_world_props.py --check    # 只报指标，不写文件
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_boss_sprite_frames import key_out  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "vibe_images")
OUT_DIR = os.path.join(ROOT, "assets", "scenes", "world")

## 水印搜索窗（占画幅的比例，右下那块）。出图工具把「Qoder AI生成」压在右下角，
## 但**具体位置随内容变** —— 实测灵气团那张在 y 963~1012，传送门那张在 y 998~1015，
## 而门那次的石板底座一直画到 y 971 / x 937，正好压在 prep_region_tiles 的固定盒
## (852,948) 里。所以这里不整块涂死，改成「找出窗内的字、只涂字的包围盒」。
WM_WIN = (0.70, 0.86)
## 一条笔画算「字」的上限：面积 / 高 / 宽。超过就当它是美术（底座、笔触团）。
WM_MAX_AREA = 600
WM_MAX_H = 30
WM_MAX_W = 60
## 涂字时向外扩的余量：字是抗锯齿的淡灰边，贴着笔画涂会留一圈 halo。
WM_PAD = 6
## 离实测背景多远算「有东西」。
WM_MIN_DIFF = 40


def _newest(pattern: str) -> str:
    hits = sorted(glob.glob(os.path.join(SRC_DIR, pattern)), key=os.path.getmtime)
    if not hits:
        raise SystemExit(f"no source matches {pattern} in vibe_images/")
    return hits[-1]


def _corner_bg(rgb: np.ndarray) -> np.ndarray:
    cs = [rgb[:24, :24], rgb[:24, -24:], rgb[-24:, :24], rgb[-24:, -24:]]
    return np.median(np.concatenate([c.reshape(-1, 3) for c in cs], axis=0), axis=0)


def erase_watermark(rgb: np.ndarray, label: str) -> None:
    """把右下角的水印涂成背景色（原地改）。

    ⚠ 只涂「字的包围盒」，不涂固定大盒：固定盒会连美术一起啃掉，而且啃完是静默的。
      涂之前先确认包围盒没和大块成分挨上，挨上了直接停下来报错，不猜。
    """
    h, w, _ = rgb.shape
    bg = _corner_bg(rgb)
    diff = np.abs(rgb.astype(np.int16) - bg[None, None, :]).max(axis=2)
    win = np.zeros(diff.shape, bool)
    win[int(h * WM_WIN[1]):, int(w * WM_WIN[0]):] = True
    lab, n = ndimage.label((diff > WM_MIN_DIFF) & win)
    if n == 0:
        print(f"{label:9s} 窗内没找到水印，跳过")
        return

    small: list[tuple[np.ndarray, np.ndarray]] = []
    big: list[tuple[int, int, int, int]] = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        hh = int(ys.max() - ys.min() + 1)
        ww = int(xs.max() - xs.min() + 1)
        if len(ys) <= WM_MAX_AREA and hh <= WM_MAX_H and ww <= WM_MAX_W:
            small.append((ys, xs))
        else:
            big.append((int(ys.min()), int(ys.max()) + 1, int(xs.min()), int(xs.max()) + 1))
    if not small:
        raise SystemExit(f"{label}: 窗内只有大块成分，判不出水印 —— 需要人工看这张图")

    y0 = min(int(ys.min()) for ys, _ in small) - WM_PAD
    y1 = max(int(ys.max()) for ys, _ in small) + WM_PAD + 1
    x0 = min(int(xs.min()) for _, xs in small) - WM_PAD
    x1 = max(int(xs.max()) for _, xs in small) + WM_PAD + 1
    y0, y1 = max(y0, 0), min(y1, h)
    x0, x1 = max(x0, 0), min(x1, w)
    for by0, by1, bx0, bx1 in big:
        if by0 < y1 and y0 < by1 and bx0 < x1 and x0 < bx1:
            raise SystemExit(
                f"{label}: 水印包围盒 (x {x0}-{x1}, y {y0}-{y1}) 和大块美术 "
                f"(x {bx0}-{bx1 - 1}, y {by0}-{by1 - 1}) 重叠，涂掉会啃图 —— 重出图或手动处理。"
            )
    rgb[y0:y1, x0:x1] = bg.astype(np.uint8)[None, None, :]
    print(f"{label:9s} 涂水印 {len(small)} 笔 → 包围盒 x {x0}-{x1} y {y0}-{y1}  "
          f"bg={bg.astype(int).tolist()}")


def _crop_box(mask: np.ndarray, thr: int, min_count: int = 3, pad: int = 2) -> tuple[slice, slice]:
    """按「这一行/列有多少个达标像素」定包围盒。

    ⚠ 不能只看「有没有」：模型出的底不是数学上的 0，四边会漏几个 alpha≈10 的孤点，
      一个点就能把 1024 宽的画布全算成内容，裁出来等于没裁（实测传送门那张 963 列
      「有」像素，其中 3 列只有 1 个点）。min_count 把这些孤点当地面噪点滤掉。
    """
    hit = mask > thr
    counts = hit.sum(axis=1)
    ys = np.where(counts >= min_count)[0]
    counts = hit.sum(axis=0)
    xs = np.where(counts >= min_count)[0]
    if len(ys) == 0 or len(xs) == 0:
        raise SystemExit(f"裁切失败：达标(>{thr})且成行成列(≥{min_count})的像素为空")
    return (
        slice(max(int(ys.min()) - pad, 0), min(int(ys.max()) + pad + 1, mask.shape[0])),
        slice(max(int(xs.min()) - pad, 0), min(int(xs.max()) + pad + 1, mask.shape[1])),
    )


def prep_orb(write: bool) -> int:
    src = _newest("world_qi_orb_*.png")
    rgb = np.asarray(Image.open(src).convert("RGB")).copy()
    erase_watermark(rgb, "qi_orb")
    # 亮度包围盒：加色图没有 alpha，用「最大通道」当有光区域。阈值取 12 —— 再低就把
    # 压缩噪声当辉光，外圈会胖一圈，转起来能看到一个不存在的方边。
    sl, sr = _crop_box(rgb.max(axis=2), 12)
    sub = rgb[sl, sr]
    h, w = sub.shape[:2]
    side = max(h, w)
    # 补成正方形并居中 —— 着色器绕画布中心转，偏心就会看出是在「转」而不是在「涌」
    out = Image.new("RGB", (side, side), (0, 0, 0))
    out.paste(Image.fromarray(sub), ((side - w) // 2, (side - h) // 2))
    print(f"            内容 {w}x{h} → 画布 {side}x{side}  峰值 {sub.max() / 255.0:.3f}  "
          f"均值 {sub.mean() / 255.0:.3f}")
    if write:
        os.makedirs(OUT_DIR, exist_ok=True)
        out.save(os.path.join(OUT_DIR, "qi_orb.png"))
    return side


def _restore_holes(rgba: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    """把「被实心轮廓围住、但颜色并不是背景」的封闭洞恢复成不透明的原画。

    为什么必须有这一步：品红键的判据是 min(R,B) - G，而**紫罗兰正好也满足这条**
    （门的虚空按 #35184d~#b9a2e0 画，R 和 B 都高于 G）。于是整片虚空被判成
    alpha≈0.78 的「半透明背景边」，还顺带吃了 key_out 的溢色抑制 —— 出来就是
    一层发灰的蓝，而且地面会透过去。单看颜色分不开，得看**拓扑**：
    背景一定从画布四边连进来，虚空是被石圈封死的岛。
    从四边洪泛「不够实」的区域，泛不到的就是岛。
    ⚠ 岛不一定是画上去的东西：门圈和底座之间那块品红缝隙也是岛。所以再加一条
      「离实测背景足够远」才恢复，否则会在门脚中间糊出一块紫红石头。
    """
    diff = np.abs(rgb.astype(np.int16) - _corner_bg(rgb)[None, None, :]).max(axis=2)
    loose = rgba[..., 3] < 250
    lab, n = ndimage.label(loose)
    border = np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]
    ]))
    border = border[border > 0]
    outside = np.isin(lab, border)
    fill = loose & ~outside & (diff > 45)
    out = rgba.copy()
    out[fill] = np.concatenate([rgb[fill], np.full((int(fill.sum()), 1), 255, np.uint8)], axis=1)
    print(f"            封闭岛恢复 {fill.sum()} px（虚空），其中判为背景留在透明 {(loose & ~outside & (diff <= 45)).sum()} px")
    return out


def prep_portal(write: bool) -> int:
    src = _newest("world_portal_*.png")
    rgb = np.asarray(Image.open(src).convert("RGB")).copy()
    erase_watermark(rgb, "portal")
    rgba = np.asarray(key_out(Image.fromarray(rgb)))
    rgba = _restore_holes(rgba, rgb)
    sl, sr = _crop_box(rgba[..., 3], 60)
    out = Image.fromarray(rgba[sl, sr])
    h, w = out.size[1], out.size[0]
    # 底行不透明度：裁完最底一行应该几乎全实，否则 anchor_bottom 会让门浮空
    bottom = float(rgba[sl, :][:, sr][..., 3].mean()) / 255.0
    holes = float((rgba[..., 3] < 8).mean())
    print(f"            内容 {w}x{h}  底行不透明度 {bottom:.3f}  全图透明占比 {holes:.3f}")
    if write:
        os.makedirs(OUT_DIR, exist_ok=True)
        out.save(os.path.join(OUT_DIR, "portal_arch.png"))
    return h


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只报指标，不写文件")
    args = ap.parse_args()
    write = not args.check
    side = prep_orb(write)
    h = prep_portal(write)
    if write:
        print("wrote:", os.path.relpath(OUT_DIR, ROOT))
    # 回显 ArtDB 要用的换算数（画布高 / 内容高 → 想要多少显示像素就乘这个 scale）
    print(f"\nArtDB 参考  qi_orb 画布 {side}px → 显示 46px 需 scale {46.0 / side:.4f}")
    print(f"ArtDB 参考  portal 内容 {h}px → 显示 132px 需 scale {132.0 / h:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
