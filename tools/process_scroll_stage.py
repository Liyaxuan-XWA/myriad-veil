"""棋谱长卷的舞台底图处理（#59）。

只要一件事：把生成图按项目口径「舞台底图走图生图+调色」压暗降饱和。

不用平铺纸带：照片里的纸面是空白的，没有任何地标，
所以它动不动肉眼看不出来 —— 拓印在它上面滚、两端轴杆静止，
读起来就是"正在展开一卷空白旧绢，上面拓着一局局棋"。
少一层机制就少一处会算错的地方。
"""
from PIL import Image, ImageEnhance
import numpy as np
import os
import sys

SRC = "vibe_images/match_scroll_stage_tall_1793820572723_842f6200.png"
OUT_DIR = "assets/ui/match"
STAGE = f"{OUT_DIR}/stage_scroll.png"

DARKEN = 0.30          # 亮度：原图纸面是奶油色，必须压到"夜里烛光照着的旧绢"
SATURATE = 0.50        # 饱和度
PAPER_CAP = 104        # 纸面最亮处的绝对上限（0-255）；卡面要能从它上面跳出来

# 纸面在源图（1792x1024）里的实测范围，代码按同样的比例映射落点（落点同源）
PAPER_X0, PAPER_X1 = 0.030, 0.955
PAPER_Y0, PAPER_Y1 = 0.217, 0.772


def grade(im: Image.Image) -> Image.Image:
    im = ImageEnhance.Brightness(im).enhance(DARKEN)
    im = ImageEnhance.Color(im).enhance(SATURATE)
    a = np.asarray(im).astype(np.float32)
    lum = a.max(axis=2, keepdims=True)
    over = np.clip(lum - PAPER_CAP, 0, None)
    a = np.clip(a - over * 0.78, 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    stage = grade(Image.open(SRC).convert("RGB"))
    stage.save(STAGE)
    a = np.asarray(stage).astype(np.float32)
    h, w, _ = a.shape
    band = a[int(h * PAPER_Y0):int(h * PAPER_Y1), int(w * PAPER_X0):int(w * PAPER_X1)]
    print("stage: %dx%d  全图均值=%.1f 最亮=%d" % (w, h, a.max(axis=2).mean(), int(a.max())))
    print("纸带: 均值=%.1f 最亮=%d p99=%.0f" % (
        band.max(axis=2).mean(), int(band.max()), np.percentile(band.max(axis=2), 99)))
    print("PAPER 落点分数: x %.3f..%.3f  y %.3f..%.3f" % (
        PAPER_X0, PAPER_X1, PAPER_Y0, PAPER_Y1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
