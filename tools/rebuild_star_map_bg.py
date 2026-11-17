"""位面星图底图重建：把生成图里残留的银色镜盘抠掉、把曝光和星点补回原画口径。

输入  : vibe_images/realm_select_bg_nebula_only_v2_*.png   （图生图产物，仍带镜盘）
参照  : .scratch/位面星图/realm_select_bg_backup_with_gates.png（原画，四扇镜门画在里面）
输出  : .scratch/位面星图/realm_select_bg_clean.png（2730x1536，交给实机过目后再覆盖 assets/）

三步都对「原画扣除四扇门圈之后的星云」负责，指标打印在末尾，任何一项不达标就别覆盖底图。
"""
from PIL import Image, ImageFilter
import numpy as np
from scipy import ndimage
import glob, json, os

SRC_SIZE = (2730, 1536)
GATES = [(1365, 818, 258), (654, 801, 220), (2074, 780, 215), (1365, 270, 150)]
REF = ".scratch/位面星图/realm_select_bg_backup_with_gates.png"
OUT = ".scratch/位面星图/realm_select_bg_clean.png"

LUM_W = np.array([.299, .587, .114], np.float32)
STAT_CLEAR = 1.25   # 统计星云口径：只扣掉门本体，保住样本量
PASTE_CLEAR = 1.90  # 搬运星点口径：连门圈辉光一起扣掉，宁可少贴几颗星也别贴出白痕


def load_ref():
    im = Image.open(REF).convert("RGB")
    a = np.asarray(im, np.float32) / 255.0
    return a, _gate_clear(a.shape[:2], STAT_CLEAR)


def to_lab(a):
    return a @ LUM_W


def find_medallion(a):
    """银色镜盘 = 三通道几乎相等（中性）且够亮。

    星云紫蓝是 B≫R、环带暖棕是 R>B，都不中性，所以「|R-B| 很小」这一条就能把它们排除掉；
    上一版只用「低饱和+亮」，结果把左侧暖棕云丝当成了最大连通块，抠错了地方。
    再用位置先验（上半部中央）兜底，避免再被别处的高光骗到。
    """
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(2)
    mn = a.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 1.0)
    grey = (sat < 0.22) & (mx > 0.40) & (np.abs(r - b) < 0.075) & (np.abs(r - g) < 0.075)
    h, w = a.shape[:2]
    prior = np.zeros((h, w), np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    prior[((xx / w - 0.487) * 1.0) ** 2 + ((yy / h - 0.185) * 1.6) ** 2 < 0.055] = 1.0
    grey_prior = grey & (prior > 0)
    grey = grey_prior if grey_prior.sum() > 400 else grey
    grey = ndimage.binary_closing(grey, np.ones((3, 3), bool), iterations=2)
    grey = ndimage.binary_opening(grey, np.ones((3, 3), bool), iterations=1)
    lab, n = ndimage.label(grey)
    if n == 0:
        print("  无中性亮块")
        return None, 0
    sizes = ndimage.sum(grey, lab, np.arange(1, n + 1))
    best = int(np.argmax(sizes)) + 1
    blob = lab == best
    ys, xs = np.nonzero(blob)
    cy, cx = float(ys.mean()), float(xs.mean())
    rx = float(xs.max() - xs.min()) / 2.0
    ry = float(ys.max() - ys.min()) / 2.0
    rad = max(rx, ry)
    area = int(blob.sum())
    print("  最大中性亮块：面积 %d px，中心 (%.1f, %.1f) = frac (%.3f, %.3f)，半轴 %.1f/%.1f"
          % (area, cx, cy, cx / w, cy / h, rx, ry))
    # 镜盘是实心圆盘：面积要够大、长宽比接近 1、填充率接近圆。
    # 达不到就当作「本图已无物体」，绝不能拿云丝高光去抠——抠错地方比留着更糟。
    fill = area / max(1.0, (2 * rx) * (2 * ry))
    if area < 1200 or rad < 18 or max(rx, ry) < 1.8 * min(rx, ry) or fill < 0.55:
        print("  判定：不是镜盘（面积/圆度/填充率不达标），跳过抠除")
        return None, area
    return (cx, cy, rad), area


def inpaint_disc(a, cx, cy, rad):
    """用同一环带、关于图水平镜像的邻居补丁填掉镜盘，再羽化边缘。

    星云是绕中心的椭圆环带，镜像后正好还是同一条环带：色调、云丝走向、景深都对得上。
    """
    h, w = a.shape[:2]
    pad = int(rad * 1.55) + 8
    x0, x1 = int(max(0, cx - pad)), int(min(w, cx + pad))
    y0, y1 = int(max(0, cy - pad)), int(min(h, cy + pad))
    # 镜像源：把同一 y 区间、x 关于图心对称的补丁搬过来
    mx0, mx1 = w - x1, w - x0
    src = a[y0:y1, mx0:mx1].copy()
    if src.shape[1] != (x1 - x0):
        src = np.asarray(Image.fromarray((src * 255).astype(np.uint8)).resize((x1 - x0, y1 - y0)), np.float32) / 255.0
    # 镜像补丁里若也带星点无所谓；但它不能覆盖到别的物体——本图除镜盘外无物体
    d = np.hypot(np.mgrid[y0:y1, x0:x1][1] - cx, np.mgrid[y0:y1, x0:x1][0] - cy)
    core = np.clip((d - rad * 0.82) / (rad * 0.72), 0, 1)  # 0=全换 1=保留
    core = ndimage.gaussian_filter(core.astype(np.float32), rad * 0.10)
    core = np.clip(core, 0, 1)
    out = a.copy()
    reg = out[y0:y1, x0:x1]
    out[y0:y1, x0:x1] = reg * core[..., None] + src * (1 - core[..., None])
    return out, (x0, x1, y0, y1)


def tone_lift(a, ref, ref_neb):
    """按通道把「均值+标准差」一起拉回原画扣除门圈的口径，只调增益不调色相。输入全为 0..1。

    只用均值会留下对比度偏差（上一版 std 高了 36%），所以走线性直方图匹配。
    四角暗角用暗部权重保护，避免线性拉伸把纯黑抬成灰。
    """
    tgt_m = ref[ref_neb].mean(0)
    tgt_s = ref[ref_neb].std(0)
    cur_m = a.reshape(-1, 3).mean(0)
    cur_s = a.reshape(-1, 3).std(0)
    slope = tgt_s / np.maximum(cur_s, 1e-6)
    print("  通道均值 %s -> %s   std %s -> %s   斜率 %s"
          % (np.round(cur_m, 4), np.round(tgt_m, 4), np.round(cur_s, 4), np.round(tgt_s, 4), np.round(slope, 4)))
    lifted = np.clip((a - cur_m) * slope + tgt_m, 0, 1)
    lum = to_lab(a)
    keep_dark = np.clip((0.075 - lum) / 0.075, 0, 1)
    out = a * keep_dark[..., None] + lifted * (1 - keep_dark[..., None])
    print("  抬升后均值 %s std %s" % (np.round(out.reshape(-1, 3).mean(0), 4), np.round(out.reshape(-1, 3).std(0), 4)))
    return out


def sparkle_layer(ref, size):
    """从原画里抽两层星点信息，都对齐到 size：

    hi    = 高通层（减去大尺度星云后的尖峰）——负责补回「中等亮」的星雾与小星点；
    core  = 原画自身亮度 >0.88 的星核（门圈以外）连同其像素值——负责补回最尖的那批星核。
    只用 hi 补不到 >0.92 那一档：星核在原画里是被画成近白的实心点，
    叠加 delta 到暗天上最多到 0.5，必须把原画的像素值本身搬过来才够尖。

    ⚠ 搬运用的排除半径必须比统计用的宽得多。门圈的辉光铺到 1.25r 之外，
      实测按 1.25r 排除时，辉光边缘那几段「成片但不圆」的亮弧会被当成星点整片贴到底图上，
      留下斜白痕（v2 原图 0 道，全是我们自己贴上去的）。
      所以：统计口径用 1.25r（保住星云样本量），搬运口径用 1.9r（宁可少贴几颗星）。
      再加一道形状筛兜底：星点是紧实小圆斑（填充率 ≥0.4），光弧不是。
    """
    h, w = size
    rgb_s = np.asarray(Image.fromarray((np.clip(ref, 0, 1) * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float32) / 255.0
    lr_s = to_lab(rgb_s)
    neb_s = _gate_clear((h, w), PASTE_CLEAR)
    bg = ndimage.gaussian_filter(lr_s, max(2.0, w / 260.0))
    hi = np.where(neb_s, np.clip(lr_s - bg, 0, 1), 0.0).astype(np.float32)
    soft = np.clip((lr_s - 0.88) / (0.95 - 0.88), 0, 1)
    core = np.where(neb_s, ndimage.gaussian_filter(soft, 0.6), 0.0).astype(np.float32)
    return hi, _star_only(core), rgb_s


def _gate_clear(shape, radius_mult):
    """门圈（含辉光）以外的区域；shape 为 (h, w)，可缩放到任意分辨率。"""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    keep = np.ones((h, w), bool)
    sx = w / float(SRC_SIZE[0])
    sy = h / float(SRC_SIZE[1])
    for cx, cy, r in GATES:
        keep &= (xx - cx * sx) ** 2 + (yy - cy * sy) ** 2 > (r * radius_mult * min(sx, sy)) ** 2
    return keep


def _star_only(core):
    """把 core 掩膜里「不是星点」的块整块置零。"""
    m = core > 0.5
    lab, n = ndimage.label(m)
    keep = np.zeros_like(core, np.float32)
    dropped = 0
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        area = int((lab[sl] == i).sum())
        ry = sl[0].stop - sl[0].start
        rx = sl[1].stop - sl[1].start
        fill = area / float(max(1, rx * ry))
        if area >= 60 or (area >= 25 and fill < 0.40 and max(rx, ry) >= 14):
            dropped += 1
            continue
        keep[lab == i] = 1.0
    print("  星点形状筛：丢弃 %d 个成片光弧块，保留 %d 个星点" % (dropped, n - dropped))
    # keep 只覆盖 core>0.5 的实心部分，而 core 是高斯羽化过的；不外扩就会把星点的辉光切掉，
    # 星点会变成生硬的方点。外扩 3px 刚好盖住羽化边。
    return ndimage.binary_dilation(keep > 0, np.ones((7, 7), bool)).astype(np.float32)


def sparkle_transfer(a, ref, tgt_bright, tgt_core):
    """先搬原画的星核像素值，再用高通层补中低星点，增益二分收敛到「>0.80 占比 == 原画星云口径」。

    固定乘 0.85 会过冲（实测 0.43% vs 目标 0.054%，星点糊成一片噪声），所以按目标反解增益。
    """
    h, w = a.shape[:2]
    hi, core, rgb_s = sparkle_layer(ref, (h, w))
    out = np.maximum(a, rgb_s * core[..., None])
    after_core = (to_lab(out) > 0.80).mean()
    print("  星核搬运：%.3f%% 像素被点亮，>0.80 占比 %.3f%% -> %.3f%%"
          % (100 * (core > 0.5).mean(), 100 * (to_lab(a) > 0.80).mean(), 100 * after_core))
    lo, hi_g = 0.0, 6.0
    gain = 0.0
    for _ in range(18):
        mid = (lo + hi_g) / 2.0
        trial = np.clip(out + hi[..., None] * np.array([0.95, 0.92, 1.0], np.float32) * mid, 0, 1)
        if (to_lab(trial) > 0.80).mean() < tgt_bright:
            lo = mid
        else:
            hi_g = mid
        gain = mid
    out = np.clip(out + hi[..., None] * np.array([0.95, 0.92, 1.0], np.float32) * gain, 0, 1)
    b80 = (to_lab(out) > 0.80).mean()
    b92 = (to_lab(out) > 0.92).mean()
    print("  高通补星：增益 %.3f，>0.80 %.3f%%（目标 %.3f%%）  >0.92 %.3f%%（目标 %.3f%%）"
          % (gain, 100 * b80, 100 * tgt_bright, 100 * b92, 100 * tgt_core))
    return out


def report(a, ref, ref_neb):
    lr = to_lab(ref)
    tgt = lr[ref_neb]
    rgb = ref[ref_neb]
    cur = to_lab(a)
    print("\n== 指标（目标 = 原画扣除四扇门圈）==")
    print("%-22s %10s %10s %8s" % ("", "现在", "目标", "差"))
    rows = [("R 均值", a[..., 0].mean(), rgb[..., 0].mean()),
            ("G 均值", a[..., 1].mean(), rgb[..., 1].mean()),
            ("B 均值", a[..., 2].mean(), rgb[..., 2].mean()),
            ("亮度均值", cur.mean(), tgt.mean()),
            ("亮度std", cur.std(), tgt.std()),
            ("亮>0.80 %", 100 * (cur > .80).mean(), 100 * (tgt > .80).mean()),
            ("亮>0.92 %", 100 * (cur > .92).mean(), 100 * (tgt > .92).mean())]
    worst = 0.0
    for name, got, want in rows:
        d = (got - want) / max(abs(want), 1e-6)
        worst = max(worst, abs(d))
        print("%-22s %10.4f %10.4f %7.1f%%" % (name, got, want, 100 * d))
    print("最大相对偏差 %.1f%%" % (100 * worst))
    return float(worst)


def main():
    cand = sorted(glob.glob("vibe_images/realm_select_bg_nebula_only_v2_*.png"))
    if not cand:
        print("找不到 v2 生成图"); return 1
    print("输入", cand[-1])
    ref, ref_neb = load_ref()
    a = np.asarray(Image.open(cand[-1]).convert("RGB"), np.float32) / 255.0
    print("尺寸", a.shape[1], a.shape[0])

    print("\n[1] 定位并抠除残留镜盘")
    pos, _ = find_medallion(a)
    if pos is not None:
        cx, cy, rad = pos
        print("\n[2] 镜像补丁抠除")
        a, box = inpaint_disc(a, cx, cy, rad)
        print("  替换区域 x %d..%d  y %d..%d" % (box[0], box[1], box[2], box[3]))
        chk, left = find_medallion(a)
        print("  复检：残留 %s" % ("无" if chk is None else (chk, left)))

    print("\n[3] 曝光对齐")
    a = tone_lift(a, ref, ref_neb)

    print("\n[4] 放大到 %dx%d（星点必须在同分辨率上对账，降采样会把星点压暗）" % SRC_SIZE)
    a = np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize(SRC_SIZE, Image.LANCZOS), np.float32) / 255.0

    print("\n[5] 星点补回")
    lr_neb = to_lab(ref)[ref_neb]
    tgt_bright = float((lr_neb > 0.80).mean())
    tgt_core = float((lr_neb > 0.92).mean())
    a = sparkle_transfer(a, ref, tgt_bright, tgt_core)

    worst = report(a, ref, ref_neb)

    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(OUT)
    print("\n输出", OUT)
    json.dump({"max_rel_dev": worst}, open(".scratch/位面星图/realm_bg_metrics.json", "w"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
