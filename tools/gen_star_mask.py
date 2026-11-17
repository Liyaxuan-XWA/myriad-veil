"""从原初位面地面图里分离「星点」权重图（2026-10-22）。

为什么需要它：
  星点和灵脉都是亮像素，靠 shader 邻域采样无法可靠区分（弯曲的细线会从所有采样方向漏掉）。
  这里用连通块分析把「线/光团」整片找出来排除掉，剩下的孤立亮点才是星。
  **完全由美术图派生，不含任何手绘内容**；换图后重跑本脚本即可。

做法：
  ① 亮度 > LUMA_TH 视为亮像素
  ② 对亮像素做膨胀（把虚线状的灵脉亮芯连成整条），再连通块标记
  ③ 外接框超过 LINE_BOX 的块 = 灵脉 / 大光团 → 整片排除
  ④ 剩下的亮像素 = 星点；高斯羽化后存成灰度权重图

用法：
  python tools/gen_star_mask.py
输出：
  assets/scenes/primordial_star_mask.png（与原图同尺寸的灰度图，0=不是星，1=星）
"""
from PIL import Image
import numpy as np
from scipy import ndimage

SRC = "assets/scenes/primordial_realm_ground.png"
DST = "assets/scenes/primordial_star_mask.png"

# 亮度门槛：低于它的一律不算星（地面本体）
LUMA_TH = 0.45
# 膨胀次数：把灵脉断续的亮芯连成整条，避免被当成一颗颗星
DILATE_ITER = 3
# 外接框（像素）超过这个值的连通块视为「线 / 光团」，整片排除
LINE_BOX = 24
# 羽化：星点移动时边缘柔和，不出现硬切
FEATHER_SIGMA = 0.9
FEATHER_GAIN = 1.35


def main() -> None:
    im = np.asarray(Image.open(SRC).convert("RGB"), dtype=np.float32) / 255.0
    lum = im @ np.array([0.299, 0.587, 0.114], dtype=np.float32)

    bright = lum > LUMA_TH
    # ② 膨胀 + 连通块：让虚线状的灵脉连成一条
    grown = ndimage.binary_dilation(
        bright, ndimage.generate_binary_structure(2, 2), iterations=DILATE_ITER)
    lab, n = ndimage.label(grown, structure=np.ones((3, 3), dtype=int))
    objs = ndimage.find_objects(lab)

    # ③ 大块 = 灵脉/光团，整片划进「不许动」区域
    line_ids = []
    for i, sl in enumerate(objs):
        if sl is None:
            continue
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if max(h, w) > LINE_BOX:
            line_ids.append(i + 1)
    line_zone = np.isin(lab, line_ids)

    # ④ 星点 = 亮像素里不属于线区的那些
    star = bright & ~line_zone
    weight = ndimage.gaussian_filter(star.astype(np.float32), FEATHER_SIGMA)
    weight = np.clip(weight * FEATHER_GAIN, 0.0, 1.0)

    out = (weight * 255.0).astype(np.uint8)
    Image.fromarray(out, mode="L").save(DST, "PNG", optimize=True)
    print("亮连通块 %d（排除线/光团 %d），星点像素 %d，权重>0.05 的像素 %d" % (
        n, len(line_ids), int(star.sum()), int((weight > 0.05).sum())))


if __name__ == "__main__":
    main()
