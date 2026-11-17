"""按**原图**重出四位 BOSS 的华彩三层：角色层 / 背景层 / 线条层。

根因：这四位的 _art 当初是从战斗透明立绘 + 游戏内空场截图做的，
和图鉴原图不是同一张画 —— 所以卡1/卡3 与卡2/卡4 分裂。
标准（赫连霄）是三层全部从原图图生图派生，这里统一到那个口径。

先落 output/yuantu_stage，合成对得上原图再覆盖 assets。
"""
from __future__ import annotations
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_plain_holo_cards import W, H, make_lines  # noqa: E402
from key_magenta_robust import key_magenta_robust  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
VIBE = ROOT / "vibe_images"
STAGE = ROOT / "output" / "yuantu_stage"
STAGE.mkdir(parents=True, exist_ok=True)

SET = {
    "boss_03_b": {
        "yuantu": "card_lizhao_src_1793230792511_1ed55e4e.png",
        "art": "lizhao_holo_art_from_yuantu_1793619170652_9661bbee.png",
        "bg": "lizhao_holo_bg_from_yuantu_1793619150688_d3dfda1e.png",
        "label": "离照",
    },
    "world_core_lianqi": {
        "yuantu": "card_boss_core_ape_1793196812674_f8534f45.png",
        "art": "lianqi_holo_art_from_yuantu_1793619206602_da242720.png",
        "bg": "lianqi_holo_bg_from_yuantu_1793619190116_b4ef32d2.png",
        "label": "青岚·古猿",
    },
    "world_core_zhuji": {
        "yuantu": "zhuji_boss_concept_v2_style_1793212671935_bd0373f6.png",
        "art": "zhuji_holo_art_from_yuantu_1793619269874_8ee3d62e.png",
        "bg": "zhuji_holo_bg_from_yuantu_1793619249014_082bb9d6.png",
        "label": "云隐·苍角",
    },
    "world_core_jiedan": {
        "yuantu": "qilin_codex_card_1793283189183_79580483.png",
        "art": "jiedan_holo_art_from_yuantu_1793619308990_db7e9668.png",
        "bg": "jiedan_holo_bg_from_yuantu_1793619287598_eaf2db90.png",
        "label": "赤金·火麟",
    },
}


def fit(im: Image.Image) -> Image.Image:
    return im.resize((W, H), Image.Resampling.LANCZOS)


def build(key: str, cfg: dict) -> dict:
    yt = fit(Image.open(VIBE / cfg["yuantu"]).convert("RGB"))
    art = fit(key_magenta_robust(VIBE / cfg["art"]))
    bg = fit(Image.open(VIBE / cfg["bg"]).convert("RGB"))
    lines = make_lines(art, 21.0)
    comp = bg.copy()
    comp.paste(art, (0, 0), art)
    art.save(STAGE / f"{key}_art.png")
    bg.save(STAGE / f"{key}_bg.png")
    lines.save(STAGE / f"{key}_lines.png")
    comp.save(STAGE / f"{key}_composite.png")
    yt.save(STAGE / f"{key}_yuantu.png")
    d = np.asarray(comp, np.float32) - np.asarray(yt, np.float32)
    cov = float((np.asarray(art)[..., 3] > 24).mean() * 100)
    return {"comp": comp, "art": art, "bg": bg, "yt": yt,
            "mad": float(np.abs(d).mean()), "cov": cov, "label": cfg["label"]}


def sheet(rows: dict) -> None:
    tw, th = 300, 450
    s = Image.new("RGB", (tw * 4 + 50, (th + 30) * len(rows) + 16), (14, 14, 18))
    d = ImageDraw.Draw(s)
    for i, (k, r) in enumerate(rows.items()):
        y = 8 + i * (th + 30)
        for c, (lab, im) in enumerate([("原图", r["yt"]), ("角色层", None), ("背景层", r["bg"]), ("合成", r["comp"])]):
            x = 10 + c * (tw + 10)
            if lab == "角色层":
                a = Image.new("RGB", (W, H), (26, 26, 30))
                a.paste(r["art"], (0, 0), r["art"])
                im = a
            s.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
            s2 = d
            s2.text((x + 2, y + th + 4), lab, fill=(205, 205, 205))
        d.text((12, y - 0), "", fill=(0, 0, 0))
        d.text((10, y + th + 16), f"{r['label']}  合成vs原图 MAD={r['mad']:.1f}  角色alpha={r['cov']:.1f}%",
               fill=(255, 210, 120))
    s.save(ROOT / "output" / "yuantu_layers_check.png")


rows = {k: build(k, v) for k, v in SET.items()}
for k, r in rows.items():
    print(f"{r['label']:10s} {k:20s} MAD={r['mad']:5.1f}  alpha={r['cov']:4.1f}%")
sheet(rows)
print("sheet -> output/yuantu_layers_check.png")
