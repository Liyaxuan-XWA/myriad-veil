#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""叠纸（照影界第 3 位 · boss_04_c）正式美术导入 —— 2026-11-03

把 ImageGen 生成的 18 张源图（洋红底 / 纯黑底）导入成工程素材，**同名覆盖** PIL 占位件，
所以代码与表一个字段都不用改。

复用执烛那一套（`import_zhizhu_art.py`）而不是重写：
  洋红键色 + 反解去溢色 / 右下角 AI 水印补块 / 内容包围盒 / 收片 / 切格图标。
执烛踩过的坑这里全部照守：
  · 半透明边必须按 k 反解颜色，否则合成时一圈品红毛边（2026-11-02 实测）。
  · rig 部件画布只留必要空白：画布上半的空会被 `head_top_y()` 当成身体最高点，
    血条直接顶到头顶上方几十像素。所以**新件按占位件的同一包围盒落位**，
    所有下游锚点（头顶、受击球、muzzle）自动沿用。
  · 地面绝不能有方向纹 / 直线 / 大特征（折痕机制会在地上画自己的发光棱）。

产物与验收口径都打印出来，方便和占位件对账。
"""

import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_zhizhu_art import (ROOT, crop_content, fit_into, is_magenta,   # noqa: E402
                              paste_bottom_center, scrub_watermark, square_icon, src)

VIBE = os.path.join(ROOT, "vibe_images")
BOSS = os.path.join(ROOT, "assets", "characters", "boss")
RIG = os.path.join(BOSS, "diezhi_rig")
FX = os.path.join(ROOT, "assets", "effects", "skills")
WPN = os.path.join(ROOT, "assets", "effects", "weapons")
SCENES = os.path.join(ROOT, "assets", "scenes")
ICON = os.path.join(ROOT, "assets", "ui", "icon")
BACKUP = os.path.join(ROOT, "assets", "_backup", "diezhi_pil_20261103")

# 占位件实测的落位包围盒：新件按同一盒走，锚点才不会漂
BODY_CANVAS = (640, 692)
BODY_BOX = (182, 0, 483, 685)          # 内容左上/右下
RULE_CANVAS = (220, 64)
RULE_BOX = (24, 11, 209, 52)

GROUND_TARGET_MEDIAN = 78.0            # 同位面：执烛 73.4 / 观澜 59.4
GROUND_TARGET_AVG = 79.0


def pick(prefix):
    """vibe_images 里按前缀取最新一张（文件名带时间戳）。"""
    cands = sorted([f for f in os.listdir(VIBE)
                    if f.startswith(prefix) and f.endswith(".png")],
                   key=lambda f: os.path.getmtime(os.path.join(VIBE, f)))
    if not cands:
        raise FileNotFoundError("没有 " + prefix + " 源图")
    return Image.open(os.path.join(VIBE, cands[-1])).convert("RGB")


def key_magenta_sampled(im):
    """同执烛的算法，但**键色按这张图自己采样**。
    ⚠ 这批生图给的"洋红"每张都不一样（实测角点 (186,26,94) ~ (213,39,99)），
      而 `import_zhizhu_art.key_magenta` 里减掉的是写死的 #E6007E ——
      拿它去反解这批图会把红蓝减过头，边缘发青。公式照抄，键色换成采样值。"""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    pts = [px[8, 8], px[8, h - 9], px[w - 9, 8], px[w - 9, h - 9]]
    kr = sum(p[0] for p in pts) / 4.0
    kg = sum(p[1] for p in pts) / 4.0
    kb = sum(p[2] for p in pts) / 4.0
    out = rgb.convert("RGBA")
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = op[x, y]
            k = max(0.0, min(1.0, (((r + b) * 0.5 - g) - 30.0) / 70.0))
            if k <= 0.0:
                continue
            if k >= 0.98:
                op[x, y] = (0, 0, 0, 0)
                continue
            inv = 1.0 / (1.0 - k)
            op[x, y] = (int(max(0.0, min(255.0, (r - kr * k) * inv))),
                        int(max(0.0, min(255.0, (g - kg * k) * inv))),
                        int(max(0.0, min(255.0, (b - kb * k) * inv))),
                        int(a * (1.0 - k)))
    return out


def lum_alpha(rgb):
    """纯黑底 → 加色特效：亮度当 alpha，颜色保留（加色混合下黑就是透明）。"""
    im = rgb.convert("RGBA")
    a = np.asarray(im)
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2])
    out = a.copy()
    out[..., 3] = np.clip(lum * 1.35, 0, 255).astype(np.uint8)
    out[..., 0:3] = np.clip(a[..., 0:3].astype(np.float32) *
                             np.where(lum[..., None] > 1.0, 1.0, 0.0), 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def place_into(im, canvas_size, box):
    """把内容精确放进指定包围盒（保持盒中心与盒高），画布尺寸照旧。"""
    bw, bh = box[2] - box[0], box[3] - box[1]
    fit = fit_into(im, bw, bh, 0)
    cv = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    cx = (box[0] + box[2]) / 2.0
    cv.alpha_composite(fit, (int(round(cx - fit.width / 2.0)),
                             int(box[3] - fit.height)))
    return cv


def center_in(im, w, h):
    """按 alpha 包围盒把内容挪到画布正中：加色贴图偏心 = 棱线/圆牌画歪。"""
    bb = im.getbbox()
    if bb is None:
        return im
    crop = im.crop(bb)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(crop, ((w - crop.width) // 2, (h - crop.height) // 2))
    return out


def metrics(path):
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)
    alpha = a[..., 3]
    ys, xs = np.nonzero(alpha > 8)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    vis = alpha > 8
    box = "无内容" if len(xs) == 0 else "(%d,%d)-(%d,%d)" % (xs.min(), ys.min(),
                                                             xs.max() + 1, ys.max() + 1)
    print("  %-52s %4dx%-4d 覆盖%5.1f%% bbox%s 亮度%5.1f" % (
        os.path.relpath(path, ROOT).replace("\\", "/"), im.size[0], im.size[1],
        100.0 * vis.mean(), box, float(lum[vis].mean()) if vis.any() else 0.0))


def heal_seam(arr, band=96):
    """上下对敲接缝：把缝挪到中间，用带外的两行做线性插值 heal，再挪回去。"""
    h, w = arr.shape[:2]
    rolled = np.roll(arr, h // 2, axis=0)
    c = h // 2
    half = band // 2
    top = rolled[c - half - 1].astype(np.float32)
    bot = rolled[c + half].astype(np.float32)
    for i in range(band):
        k = i / float(band - 1)
        rolled[c - half + i] = top * (1.0 - k) + bot * k
    return np.roll(rolled, -(h // 2), axis=0)


def dc_align_seam(rgb, edge=16, scale=90.0):
    """对敲缝压平：只把「跨过接缝的那一层低频亮度台阶」抹掉，**不动任何纹理**。

    ⚠ 别再用「把缝挪到中间然后 96px 线性插值」那套 heal_seam：它等于把中间那条带
      的所有细节擦成一道渐变。战场地面是 2×2 镜像块铺的（combat_arena._make_mirror_tile_texture），
      这条带会被镜像成左右对称的「暗斑」，实机截图里就是一块明显的水泥补丁（2026-11-03 抓到）。
      叠纸原片上下缝 22.92 里约 20.3 是纯亮度台阶，所以只对齐 DC 就压到 10.72（内部 8.67）。
    """
    lum = rgb.mean(axis=2)
    h, w = lum.shape[:2]
    out = rgb.astype(np.float32)
    dv = (lum[:edge].mean() - lum[-edge:].mean()) * 0.5
    dh = (lum[:, :edge].mean() - lum[:, -edge:].mean()) * 0.5
    vy = 2.0 / (1.0 + np.exp(-(np.arange(h) - h * 0.5) / scale)) - 1.0
    vx = 2.0 / (1.0 + np.exp(-(np.arange(w) - w * 0.5) / scale)) - 1.0
    out += (dv * vy)[:, None, None]
    out += (dh * vx)[None, :, None]
    return np.clip(out, 0.0, 255.0)


def seam_report(rgb):
    lum = rgb.mean(axis=2) if rgb.ndim == 3 else rgb
    inner_v = float(np.abs(lum[:, 1:] - lum[:, :-1]).mean())
    inner_h = float(np.abs(lum[1:, :] - lum[:-1, :]).mean())
    s_h = float(np.abs(lum[:, 0:1] - lum[:, -1:]).mean())
    s_v = float(np.abs(lum[0:1, :] - lum[-1:, :]).mean())
    return inner_v, inner_h, s_h, s_v


def backup(targets):
    os.makedirs(BACKUP, exist_ok=True)
    n = 0
    for p in targets:
        if not os.path.exists(p):
            continue
        dst = os.path.join(BACKUP, os.path.relpath(p, ROOT).replace("\\", "_"))
        if os.path.exists(dst):
            continue          # 只备份**第一次**看到的占位件：重跑导入不许把母本冲掉
        shutil.copy2(p, dst)
        n += 1
    print("备份 %d 个占位件 → %s" % (n, os.path.relpath(BACKUP, ROOT)))


def main():
    for d in (BOSS, RIG, FX, WPN, SCENES, ICON):
        os.makedirs(d, exist_ok=True)
    outs = [os.path.join(BOSS, "boss_diezhi.png"), os.path.join(RIG, "body.png"),
            os.path.join(RIG, "rule.png"), os.path.join(FX, "fold_seal.png"),
            os.path.join(WPN, "zhicuo_jian.png"),
            os.path.join(SCENES, "zhaoying_fold_arena_ground.png")]
    outs += [os.path.join(ICON, n + ".png") for n in
             ["soul_diezhi", "tr_diezhi_ling", "tr_zhaoying_zhefu", "mat_zhaoying_zhihen",
              "equip_zhicuo_jian", "equip_zhehen_pei"] +
             ["skill_fold_" + s for s in ["press", "trace", "stride", "seam", "shroud",
                                          "tear", "twin", "triple", "measure"]]]
    backup(outs)

    print("\n[1] 定妆图与 rig 分件（镜像成 3/4 朝右）")
    concept = scrub_watermark(pick("diezhi_concept_v2"))
    fig = key_magenta_sampled(crop_content(concept.transpose(Image.FLIP_LEFT_RIGHT)))
    place_into(fig, BODY_CANVAS, BODY_BOX).save(os.path.join(BOSS, "boss_diezhi.png"))
    body = scrub_watermark(pick("diezhi_body_v2"))
    bk = key_magenta_sampled(crop_content(body.transpose(Image.FLIP_LEFT_RIGHT)))
    place_into(bk, BODY_CANVAS, BODY_BOX).save(os.path.join(RIG, "body.png"))
    # ⚠ v3 那张画成了拐尺（左端一个凸起台阶），定妆图和卡面里的镇尺都是
    #   「一根直条 + 两端各一颗铆钉」。部件形状和母本对不上，玩家会认为卡片上
    #   和场上是两个道具 —— 所以换 v4 重画，不做裁角糊弄。
    rule = key_magenta_sampled(crop_content(scrub_watermark(pick("diezhi_rule_v4"))))
    place_into(rule, RULE_CANVAS, RULE_BOX).save(os.path.join(RIG, "rule.png"))
    for p in ["boss_diezhi.png", "body.png", "rule.png"]:
        metrics(os.path.join(RIG if p != "boss_diezhi.png" else BOSS, p))

    print("\n[2] 战场地面（亮度归带 + 对敲缝只压 DC，不抹细节）")
    g = pick("diezhi_ground_v1").resize((1024, 1024), Image.LANCZOS)
    raw = np.asarray(g.convert("RGB")).astype(np.float32)
    raw_iv, raw_ih, raw_sh, raw_sv = seam_report(raw)
    arr = np.asarray(g.convert("L")).astype(np.float32)
    before = (float(arr.mean()), float(np.median(arr)))
    rgb = dc_align_seam(raw)
    gain = GROUND_TARGET_MEDIAN / max(float(np.median(rgb.mean(axis=2))), 1.0)
    out = np.clip(rgb * gain, 0, 255).astype(np.uint8)
    gp = os.path.join(SCENES, "zhaoying_fold_arena_ground.png")
    Image.fromarray(out, "RGB").filter(ImageFilter.SMOOTH).save(gp)
    a2 = np.asarray(Image.open(gp).convert("L")).astype(np.float32)
    lr = np.abs(a2[:, 0] - a2[:, -1]).mean()
    tb = np.abs(a2[0, :] - a2[-1, :]).mean()
    inner = max(np.abs(a2[:, :-1] - a2[:, 1:]).mean(), np.abs(a2[:-1] - a2[1:]).mean())
    print("  平均 %.1f→%.1f  中位 %.1f→%.1f  近黑 %.2f%%" %
          (before[0], a2.mean(), before[1], np.median(a2), 100.0 * (a2 < 12).mean()))
    print("  对敲差 左右 %.2f→%.2f  上下 %.2f→%.2f  内部 %.2f（缝/内部 必须 <=1.5，且不许抹细节）"
          % (raw_sh, lr, raw_sv, tb, inner))

    print("\n[3] 令印 decal 与局内武器")
    seal = key_magenta_sampled(crop_content(scrub_watermark(pick("diezhi_seal_v1"),
                                                    (0.70, 0.86, 1.0, 1.0))))
    seal = fit_into(seal, 504, 504, 0)
    sc = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    sc.alpha_composite(seal, ((512 - seal.width) // 2, (512 - seal.height) // 2))
    sc.save(os.path.join(FX, "fold_seal.png"))
    wp = key_magenta_sampled(crop_content(scrub_watermark(pick("diezhi_weapon_v1"))))
    wp = fit_into(wp, 470, 470, 0)
    wc = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    wc.alpha_composite(wp, ((512 - wp.width) // 2, (512 - wp.height) // 2))
    wc.save(os.path.join(WPN, "zhicuo_jian.png"))
    metrics(os.path.join(FX, "fold_seal.png"))
    metrics(os.path.join(WPN, "zhicuo_jian.png"))

    print("\n[4] 折棱 / 圆牌 / 翻面纸（黑底转亮度 alpha，按代码原生尺寸）")
    ridge = lum_alpha(pick("diezhi_ridge_v1").resize((512, 64), Image.LANCZOS))
    center_in(ridge, 512, 64).save(os.path.join(FX, "fold_ridge.png"))
    disc = lum_alpha(pick("diezhi_disc_v1").resize((256, 256), Image.LANCZOS))
    center_in(disc, 256, 256).save(os.path.join(FX, "fold_seam_disc.png"))
    sheet = key_magenta_sampled(crop_content(scrub_watermark(pick("diezhi_sheet_v1"))))
    sheet = fit_into(sheet, 500, 500, 0)
    sh = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    sh.alpha_composite(sheet, ((512 - sheet.width) // 2, (512 - sheet.height) // 2))
    sh.save(os.path.join(FX, "fold_sheet.png"))
    for n in ["fold_ridge.png", "fold_seam_disc.png", "fold_sheet.png"]:
        metrics(os.path.join(FX, n))

    print("\n[5] 图标表切格（2×2 四格 → 256x256）")
    plan = [("diezhi_icons_sheetA", ["soul_diezhi", "tr_diezhi_ling",
                                     "tr_zhaoying_zhefu", "mat_zhaoying_zhihen"]),
            ("diezhi_icons_sheetB", ["equip_zhicuo_jian", "equip_zhehen_pei",
                                     "skill_fold_press", "skill_fold_trace"]),
            ("diezhi_icons_sheetC", ["skill_fold_stride", "skill_fold_seam",
                                     "skill_fold_shroud", "skill_fold_tear"]),
            ("diezhi_icons_sheetD", ["skill_fold_twin", "skill_fold_triple",
                                     "skill_fold_measure", None])]
    for sheet_name, names in plan:
        im = scrub_watermark(pick(sheet_name), (0.72, 0.88, 1.0, 1.0))
        cw, ch = im.width // 2, im.height // 2
        for i, nm in enumerate(names):
            if nm is None:
                continue
            r, c = i // 2, i % 2
            cell = im.crop((c * cw + 8, r * ch + 8, (c + 1) * cw - 8, (r + 1) * ch - 8))
            square_icon(key_magenta_sampled(cell), 256, 10).save(os.path.join(ICON, nm + ".png"))
            print("  icon", nm)

    print("\n[6] 元魂图标重出：图标表里那张的头是一个**空白圆盘**")
    # 叠纸的身份全在「对折的纸头 + 一道墨缝」上，元魂图标给一个无脸白圆，
    # 玩家从背包点进去认不出这是谁 —— 单独重出一张，只换头，构图/配色/烟/环全保留。
    soul = os.path.join(ICON, "soul_diezhi.png")
    if os.path.exists(soul):
        template = Image.open(soul).convert("RGBA")
        fresh = pick("diezhi_soul_icon").resize((256, 256), Image.LANCZOS).convert("RGBA")
        fresh.putalpha(template.split()[3])          # 沿用工程图标模板的圆角遮罩
        fresh.save(soul)
        fa = np.asarray(fresh)
        print("  soul_diezhi.png 换头重出  不透明 %.1f%%  遮罩沿用旧模板"
              % ((fa[..., 3] > 24).mean() * 100))

    print("\n[7] 落盘验收")
    for nm in ["soul_diezhi", "tr_diezhi_ling", "tr_zhaoying_zhefu", "mat_zhaoying_zhihen",
               "equip_zhicuo_jian", "equip_zhehen_pei"] + \
              ["skill_fold_" + s for s in ["press", "trace", "stride", "seam", "shroud",
                                           "tear", "twin", "triple", "measure"]]:
        metrics(os.path.join(ICON, nm + ".png"))
    print("\ndone")


if __name__ == "__main__":
    main()
