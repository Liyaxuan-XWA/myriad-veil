"""叠纸四张卡导入（2026-11-03）

母本 = 用户外部生成的卡面原画 `diezhi_card_v2`（1024×1536，2:3）。
四张卡全部从这一张派生，保证「同一个人、同一机位、同一道折棱」：

  卡1 图鉴原画  card_boss_diezhi.png        ← 原画直接收片
  卡2 华彩·场景 boss_04_c_{art,bg,lines}    ← 原画的图生图两张分件（洋红底人物 / 无人物空景）
  卡3 华彩·线条 boss_04_c_lines.png         ← 由 art 层现算，不另画
  卡4 纸本水墨  boss_04_c_ink.png            ← 水墨重绘原片收片（另跑 bake_boss_ink_maps）

口径抄 tools/rebuild_holo_from_yuantu.py（赫连霄母本），不另立标准。
产物先落 output/diezhi_card_stage，量过 MAD / alpha_min / 线层通道三条守卫再覆盖 assets。
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
VIBE = ROOT / "vibe_images"
STAGE = ROOT / "output" / "diezhi_card_stage"
HOLO = ROOT / "assets" / "ui" / "codex" / "holo"
CODEX = ROOT / "assets" / "ui" / "codex"
BACKUP = ROOT / "assets" / "_backup" / "diezhi_cards_20261103"
W, H = 640, 960

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_plain_holo_cards import make_lines  # noqa: E402
from key_magenta_robust import key_magenta_robust  # noqa: E402

SRC = {
    # 2026-11-04 画风返工：三张全部从**新卡面**派生（图生图只换底 / 只删人），
    # 旧源图是暖黄折纸那一档，留着会把卡2/3/4 拉回旧风格。
    "yuantu": "card_boss_diezhi_v2_1793797790226_5398f8d9.png",
    "art": "diezhi_v2_card_art_magenta_1793798415137_4eec7f95.png",
    "bg": "diezhi_v2_card_bg_plate_1793798432843_a620bacc.png",
}
# 卡面原画要求 2:3，比例错了收进 640×960 会把人和纸脊一起拉扁
RATIO_TOL = 0.02
# 合成 vs 原画的容忍度：低于这个值说明人物层根本没抠出来（两层几乎重合）
MAD_MIN = 6.0
MAD_MAX = 40.0


def fit(im: Image.Image) -> Image.Image:
    if im.width == W and im.height == H:
        return im
    return im.resize((W, H), Image.Resampling.LANCZOS)


def check_ratio(name: str, im: Image.Image) -> None:
    r = im.width / im.height
    if abs(r - 2.0 / 3.0) > RATIO_TOL:
        raise SystemExit(f"{name} 不是 2:3：{im.size}（比例 {r:.3f}）")


def main() -> None:
    STAGE.mkdir(parents=True, exist_ok=True)
    paths = {k: VIBE / v for k, v in SRC.items()}
    for k, p in paths.items():
        if not p.exists():
            raise SystemExit(f"缺源图 {k}: {p}")

    yt = fit(Image.open(paths["yuantu"]).convert("RGB"))
    art = fit(key_magenta_robust(paths["art"]))
    bg = fit(Image.open(paths["bg"]).convert("RGB"))
    for k, im in [("原画", yt), ("人物层", art), ("背景层", bg)]:
        check_ratio(k, im)

    lines = make_lines(art, 21.0)
    comp = bg.copy()
    comp.paste(art, (0, 0), art)

    a = np.asarray(art)
    alpha_min = float(a[..., 3].min())
    cov = float((a[..., 3] > 24).mean() * 100.0)
    mad = float(np.abs(np.asarray(comp, np.float32) - np.asarray(yt, np.float32)).mean())
    lmask = np.asarray(lines, np.float32)
    lmean = float(lmask.mean())

    print(f"合成 vs 原画 MAD = {mad:5.1f}   容忍 {MAD_MIN}~{MAD_MAX}")
    print(f"人物层 alpha_min = {alpha_min:5.1f}（必须 0，否则背景层永不显示）")
    print(f"人物层不透明覆盖 = {cov:.1f}%")
    print(f"线条层均值 = {lmean:.1f}/255（虎妖标准 21）  线层模式 {lines.mode}")

    bad = []
    if alpha_min > 0.0:
        bad.append("人物层没有真正透明像素 → 卡1 会退化成卡3")
    if not (MAD_MIN <= mad <= MAD_MAX):
        bad.append(f"MAD {mad:.1f} 出容忍带 → 两层与母本对不上")
    if not (12.0 <= lmean <= 32.0):
        bad.append(f"线层均值 {lmean:.1f} 出档 → 蚀刻线过强/过弱")
    if bad:
        for m in bad:
            print("  !", m)
        print("守卫未过，只落 staging，不覆盖 assets。")
    else:
        print("守卫通过。")

    # ---------- staging 对照表 ----------
    art_on_dark = Image.new("RGB", (W, H), (26, 26, 30))
    art_on_dark.paste(art, (0, 0), art)
    line_view = Image.merge("RGB", [lines, lines, lines])
    tw, th = 320, 480
    row = Image.new("RGB", (tw * 4 + 50, th + 26), (14, 14, 18))
    d = ImageDraw.Draw(row)
    for i, (lab, im) in enumerate([("yuantu", yt), ("art", art_on_dark),
                                   ("bg", bg), ("composite", comp)]):
        x = 10 + i * (tw + 10)
        row.paste(im.convert("RGB").resize((tw, th), Image.LANCZOS), (x, 0))
        d.text((x + 2, th + 6), lab, fill=(205, 205, 205))
    d.text((10, th + 14), f"MAD={mad:.1f} alpha_min={alpha_min:.0f} cov={cov:.1f}% lines_mean={lmean:.1f}",
           fill=(255, 210, 120))
    row.save(STAGE / "layers_check.png")
    line_view.convert("RGB").resize((W // 2, H // 2)).save(STAGE / "lines_view.png")
    for n, im in [("yuantu", yt), ("art", art), ("bg", bg),
                  ("lines", line_view), ("composite", comp)]:
        im.convert("RGB" if n not in ("art",) else "RGBA").save(STAGE / f"{n}.png")
    art.save(STAGE / "art_rgba.png")

    if bad:
        print(f"staging -> {STAGE}")
        return

    # ---------- 备份 + 覆盖 ----------
    targets = [CODEX / "card_boss_diezhi.png",
               HOLO / "boss_04_c_art.png", HOLO / "boss_04_c_bg.png",
               HOLO / "boss_04_c_lines.png"]
    BACKUP.mkdir(parents=True, exist_ok=True)
    for t in targets:
        if t.exists():
            shutil.copy2(t, BACKUP / t.name)
            print("备份", t.relative_to(ROOT))
    yt.save(CODEX / "card_boss_diezhi.png", optimize=True)
    art.save(HOLO / "boss_04_c_art.png", optimize=True)
    bg.save(HOLO / "boss_04_c_bg.png", optimize=True)
    lines.save(HOLO / "boss_04_c_lines.png", optimize=True)
    for t in targets:
        print("写入", t.relative_to(ROOT), Image.open(t).size, Image.open(t).mode)
    print("staging -> output/diezhi_card_stage")


if __name__ == "__main__":
    main()
