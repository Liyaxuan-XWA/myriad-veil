"""虎妖水墨卡：把 1024×1536 图生图原片收成 640×960 卡面。

原片已按图鉴卡重绘（构图、姿态、岩台、雾林都不动），只做尺寸与轻微锐化。
"""
from pathlib import Path

from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "vibe_images" / "huyao_ink_card_raw_1793317163592_5af63264.png"
DST = ROOT / "assets" / "ui" / "codex" / "holo" / "boss_huyao_ink.png"


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    if im.size != (1024, 1536):
        raise SystemExit(f"unexpected source size: {im.size}")
    im = im.resize((640, 960), Image.Resampling.LANCZOS)
    im = ImageEnhance.Sharpness(im).enhance(1.12)
    DST.parent.mkdir(parents=True, exist_ok=True)
    im.save(DST, optimize=True)
    print(f"saved {DST.relative_to(ROOT)}  {im.size[0]}x{im.size[1]}")


if __name__ == "__main__":
    main()
