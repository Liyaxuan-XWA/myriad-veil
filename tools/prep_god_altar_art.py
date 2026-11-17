"""铸神晶 / 补天石 / 铸神祭坛 —— 用户提供图处理（2026-11-13）

⚠ 祭坛那一步（_altar：椭圆羽化）已于 2026-11-13 被 tools/prep_god_altar_v2.py 取代：
  实机看是一圈白灰雾边 + 底部没抠净的地面。别在这里重跑 _altar 覆盖新图。

源图（对话附件）：
  1) 金粉水晶 + 金色符环（白底）→ 铸神晶图标
  2) 石台祭坛 + 粉色晶体 + 金链（庭院场景）→ 大世界祭坛立绘
  3) 裂金蛋白石（白底）→ 补天石图标

处理口径：
  · 两张图标：从边框做「近白连通区」泛洪，只剥掉外部背景，石头内部的白色高光保留；
    再收 1px + 羽化 1px，去水印，按 alpha 包围盒裁切、8% 留白、缩到 256×256。
  · 祭坛：裁掉庭院远景与右下角水印，只留石台与晶体；椭圆羽化遮罩让底座周围的地砖
    渐隐进世界地表；无背景板。
用法：
  python tools/prep_god_altar_art.py --src-dir <附件目录>
"""
import argparse
import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

CRYSTAL_SRC = "b8d012d3-724c-447d-b513-f4f8bf63840a.png"
ALTAR_SRC = "5762a365-c7b8-4c12-8911-cd2aba62420a.png"
STONE_SRC = "25926d44-8f09-4780-8501-80888209e901.png"
YUNXIAN_SRC = "361c2bf6-a1c6-4176-8bc4-dad914a05dfa.png"


def _flood_alpha(im: Image.Image, erase_corner: bool = True) -> Image.Image:
    """近白外部背景 → alpha 0；被物体包住的白色高光保留。"""
    w, h = im.size
    arr = np.asarray(im.convert("RGB")).astype(np.uint8)
    bg_like = (arr.min(axis=2) >= 242).astype(np.uint8) * 255
    m = Image.fromarray(bg_like, "L").copy()
    seeds = [(x, y) for x in range(w) for y in (0, h - 1)]
    seeds += [(x, y) for y in range(h) for x in (0, w - 1)]
    for xy in seeds:
        if m.getpixel(xy) == 255:
            ImageDraw.floodfill(m, xy, 128)
    alpha = np.where(np.asarray(m) == 128, 0, 255).astype(np.uint8)
    a = Image.fromarray(alpha, "L").copy()
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    if erase_corner:
        ImageDraw.Draw(a).rectangle(
            [int(w * 0.68), int(h * 0.88), w, h], fill=0)
    return Image.fromarray(np.dstack([arr, np.asarray(a)]).astype(np.uint8), "RGBA")


def _icon(src_path: str, out_path: str, flood: bool = True) -> None:
    src = Image.open(src_path)
    if flood:
        im = _flood_alpha(src)
    else:
        # 金粉水晶的白底是「柔光」连成的一片，泛洪会在符环内留下白盘；
        # 改用离白距离做软 alpha，光环的透明度反而更像魔法光。
        rgb = np.asarray(src.convert("RGB")).astype(np.float32)
        d = 255.0 - rgb.min(axis=2)
        a = np.clip((d - 8.0) * 8.0, 0, 255).astype(np.uint8)
        w, h = src.size
        ad = Image.fromarray(a, "L").copy()
        ImageDraw.Draw(ad).rectangle([int(w * 0.68), int(h * 0.88), w, h], fill=0)
        im = Image.fromarray(np.dstack([rgb, np.asarray(ad)]).astype(np.uint8), "RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(bbox)
    side = max(im.size)
    pad = int(side * 0.08)
    canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    canvas.paste(im, ((canvas.width - im.width) // 2,
                      (canvas.height - im.height) // 2), im)
    canvas.resize((256, 256), Image.LANCZOS).save(out_path)
    print("icon", out_path)


def _altar(src_path: str, out_path: str) -> None:
    im = Image.open(src_path).convert("RGB").crop((18, 88, 272, 348))
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * 0.5, h * 0.55
    rx, ry = w * 0.52, h * 0.55
    r = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    alpha = (np.clip((1.0 - r) / 0.18, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(np.dstack([np.asarray(im), alpha]).astype(np.uint8),
                    "RGBA").save(out_path)
    print("altar", out_path, im.size)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src-dir", required=True)
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon_dir = os.path.join(root, "assets/ui/icon")
    world_dir = os.path.join(root, "assets/scenes/world")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(world_dir, exist_ok=True)
    _icon(os.path.join(args.src_dir, CRYSTAL_SRC),
          os.path.join(icon_dir, "mat_zhushenjing.png"), flood=False)
    _icon(os.path.join(args.src_dir, STONE_SRC),
          os.path.join(icon_dir, "mat_butianshi.png"))
    _icon(os.path.join(args.src_dir, YUNXIAN_SRC),
          os.path.join(icon_dir, "mat_yunxiansui.png"))
    _altar(os.path.join(args.src_dir, ALTAR_SRC),
           os.path.join(world_dir, "god_altar.png"))


if __name__ == "__main__":
    main()
