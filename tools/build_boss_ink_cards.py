"""全套纸本水墨卡：把 1024×1536 的图生图原片收成 640×960。

原片已按图鉴原画重绘（身份、姿态、构图不动），这里只做统一收片：
尺寸、纸白点、轻微锐化。虎妖那张是模板，不再重跑。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "vibe_images"
DST = ROOT / "assets" / "ui" / "codex" / "holo"

PAPER_TARGET = np.array([247.0, 244.0, 236.0], np.float32)

CARDS = {
    "boss_01": "boss_01_ink_wash_sample_1793374571916_cf586c3a.png",
    "boss_01_c": "boss_01_c_ink_wash_v2_1793374701115_1e24eec6.png",
    "boss_02": "boss_02_ink_wash_v2_1793374731510_2a16e5de.png",
    "boss_02_b": "boss_02_b_ink_wash_v2_1793374765442_1f09071b.png",
    "boss_02_c": "qijun_ink_v2_1793374889296_9491ab07.png",
    "boss_03": "heiliao_ink_v2_1793374916141_b1ce056b.png",
    "boss_03_b": "lizhao_ink_v2_1793374947175_00f88d21.png",
    "boss_03_c": "wujiu_ink_v2_1793375001990_c35af460.png",
    "world_core_lianqi": "world_core_lianqi_ink_wash_sample_1793374620368_9febe9a1.png",
    "world_core_zhuji": "cangjiao_ink_v2_1793375030429_84190648.png",
    "world_core_jiedan": "qilin_ink_v2_1793375061182_dd2e4f38.png",
    "world_core_shihou": "shihou_ink_card_v2_1793462892473_26d15954.png",
    # 照影界两位：观澜上次是临时收的片、没进表，这里补上保证可复现
    "boss_04": "guanying_ink_1793491387780_21df3d95.png",
    "boss_04_b": "zhizhu_ink_v2.png",
    "boss_04_c": "diezhi_v2_ink_wash_1793798534822_e826acd8.png",
}

## 图生图原片右下角带「Qoder AI生成」水印：只对带水印的源裁掉底部。
TRIM_BOTTOM = {
    "world_core_shihou": 60,
}


def grade(im: Image.Image) -> Image.Image:
    a = np.asarray(im, np.float32)
    hi = np.percentile(a.reshape(-1, 3), 95.0, axis=0)
    gain = np.clip(PAPER_TARGET / np.maximum(hi, 1.0), 0.88, 1.22)
    a = np.clip(a * gain[None, None, :], 0.0, 255.0)
    return Image.fromarray(a.astype(np.uint8), "RGB")


def main() -> None:
    only = set(sys.argv[1:])
    for key, raw_name in CARDS.items():
        if only and key not in only:
            continue
        src = RAW / raw_name
        if not src.exists():
            raise SystemExit(f"missing raw: {src}")
        im = Image.open(src).convert("RGB")
        # 校验比例而不是像素尺寸：生图工具给到多大不由我们定（执烛这批只有 256×384），
        # 但 2:3 必须守住 —— 比例错了收进 640×960 会把人和影子一起拉扁。
        ratio = im.width / im.height
        if abs(ratio - 2 / 3) > 0.02:
            raise SystemExit(f"source not 2:3 for {key}: {im.size} (ratio {ratio:.3f})")
        if im.height < 960:
            print(f"  ! {key}: 原片只有 {im.size[0]}x{im.size[1]}，收片会偏糊")
        im = im.resize((640, 960), Image.Resampling.LANCZOS)
        trim = TRIM_BOTTOM.get(key, 0)
        if trim > 0:
            im = im.crop((0, 0, im.width, im.height - trim))
        im = grade(im)
        im = ImageEnhance.Sharpness(im).enhance(1.10)
        out = DST / f"{key}_ink.png"
        im.save(out, optimize=True)
        print(f"saved {out.relative_to(ROOT)}  {im.size[0]}x{im.size[1]}")


if __name__ == "__main__":
    main()
