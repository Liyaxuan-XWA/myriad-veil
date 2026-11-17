"""锻造舞台「墨夜炉火」调色：把图像模型出的原片压回游戏里的夜炉亮度。

为什么需要这一步：模型交回来的图总是偏亮（实测平均亮度 27.0，而工程里现用的舞台是 20.1），
直接接进面板会让纸签、铜牌这些已经定稿的哑光控件被衬得发灰，整个界面从「夜里一炉火」
变成「白天一间屋」。所以调色不是美化，是把亮度拉回与 UI 同一档。

三步，缺一不可：
  1. gamma 压暗 + 冷灰偏移：整体沉下去，石头从暖灰变夜灰。
  2. 只回拉暖色像素：炉口和它洒在石面上的光是画面里唯一的饱和色，压暗时不能一起干掉，
     否则炉火变余烬、镜头就没有落点了。判据是 R 明显大于 B 且 G 不算低（橙黄族）。
  3. 暗角：把注意力钉在砧面，同时把顶部与右侧（会被顶栏和兵器架盖住）压成低信息量。

尺寸：模型只能给 1792x1024，而面板按「舞台像素 / 1.4 = 屏幕像素」摆交互落点，
1024 高会把这个比例破坏成 1.4222。上下各裁 8 像素回到 1008，规则重新成立。

用法：python tools/grade_forge_stage.py [源图路径]
"""

import os
import shutil
import sys

import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DEFAULT = os.path.join(
    REPO, "vibe_images", "forge_stage_pilot_b_1792933829447_273eb5ae.png")
DST = os.path.join(REPO, "assets", "ui", "forge", "stage_night.png")
BACKUP = DST + ".bak_pil"

TARGET_W, TARGET_H = 1792, 1008
GAMMA = 1.30
COOL_TINT = (0.90, 0.93, 1.03)
WARM_RESCUE = 0.42
VIGNETTE = 0.20
LUM_RANGE = (18.0, 22.0)  # 现用舞台实测 20.1


def luminance(arr):
    return float((arr @ np.array([0.299, 0.587, 0.114], np.float32)).mean()) * 100.0


def crop_to_ratio(arr):
    """上下各裁掉多余的像素，得到 1792x1008。"""
    h, w = arr.shape[:2]
    if (w, h) == (TARGET_W, TARGET_H):
        return arr
    if w != TARGET_W:
        raise SystemExit("宽度应为 %d，实际 %d：先确认生成尺寸是 1792x1024" % (TARGET_W, w))
    trim = (h - TARGET_H) // 2
    return arr[trim:trim + TARGET_H]


def grade(arr):
    warm_mask = ((arr[..., 0] > arr[..., 2] + 0.06)
                 & (arr[..., 1] > arr[..., 2] * 0.75))[..., None]
    out = arr ** GAMMA * np.array(COOL_TINT, np.float32)
    out = np.clip(out * (1.0 + warm_mask * WARM_RESCUE), 0.0, 1.0)

    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx / w - 0.5) * 2.0
    ny = (yy / h - 0.5) * 2.0
    fall = np.clip(np.hypot(nx * 0.85, ny) - 0.45, 0.0, 1.0) ** 1.6
    out = np.clip(out * (1.0 - VIGNETTE * fall)[..., None], 0.0, 1.0)
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC_DEFAULT
    arr = np.asarray(Image.open(src).convert("RGB"), np.float32) / 255.0
    arr = crop_to_ratio(arr)
    print("源图    %s" % os.path.relpath(src, REPO).replace(os.sep, "/"))
    print("        %dx%d  亮度 %.1f" % (arr.shape[1], arr.shape[0], luminance(arr)))

    out = grade(arr)
    lum = luminance(out)
    print("调色后  %dx%d  亮度 %.1f  （目标区间 %.1f~%.1f）"
          % (out.shape[1], out.shape[0], lum, LUM_RANGE[0], LUM_RANGE[1]))
    if not (LUM_RANGE[0] <= lum <= LUM_RANGE[1]):
        raise SystemExit("亮度落在目标区间外，先调 GAMMA / VIGNETTE，别直接写文件")

    # 旧图整份留着：assets/ui/forge 没进版本库，覆盖掉就找不回来了
    if os.path.exists(DST) and not os.path.exists(BACKUP):
        shutil.copyfile(DST, BACKUP)
        print("已备份旧图 -> %s" % os.path.relpath(BACKUP, REPO).replace(os.sep, "/"))

    Image.fromarray((out * 255).astype(np.uint8)).save(DST)
    print("写入      %s" % os.path.relpath(DST, REPO).replace(os.sep, "/"))
    print("记得跑：godot --headless --path . --import（否则 .ctex 不刷新，截图仍是旧图）")


if __name__ == "__main__":
    main()
