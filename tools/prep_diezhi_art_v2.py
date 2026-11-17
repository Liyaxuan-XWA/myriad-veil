#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""叠纸（boss_04_c）美术重做收片 —— 2026-11-04。

问题：这一只整批漂到了「暖黄折纸模型」那一档，和照影界另外两位（观澜、执烛）以及
前面所有 BOSS 的手绘暗调插画不是一个 tier。量出来的偏差（旧 → 新，目标见括号）：
  卡面    亮度 173 →  53（同类 20~97）    暖偏 R-B +75.9 → -20.3（同类 -23~-8）
  地面    亮度  79 →  71（目标 65~80）    暖偏 +15.3 → -23.9（观澜 -44.4 / 执烛 -8.2）
  立绘    低多边形纸偶、无脸黑缝 → 手绘、纸面墨眉、撕纸下摆，配色转冷

四件一次收：
  body / rule  → assets/characters/boss/diezhi_rig/   （画布与内容位置沿用旧件，锚点才不用从零重测）
  card         → assets/ui/codex/card_boss_diezhi.png （640×960）
  ground       → assets/scenes/zhaoying_fold_arena_ground.png（1024²，对边差 0.61/0.77 可平铺）

键色用 `key_auto`（从画面四边**量**出键色再抠）：生图模型已经把「平涂洋红」画歪过三次
（(236,91,206) 淡粉 / (217,32,128) 暗红 / (161,49,97) 暗玫瑰），写死 #FF00FE 会解不干净。

用法：
  python tools/prep_diezhi_art_v2.py            # 只出对照表和指标，不落盘
  python tools/prep_diezhi_art_v2.py --write    # 落盘（原件先备份到 assets/_backup/）
"""
import argparse
import glob
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from mat_icon_plate import key_auto, detect_key  # noqa: E402

VIBE = os.path.join(ROOT, "vibe_images")
RIG = os.path.join(ROOT, "assets", "characters", "boss", "diezhi_rig")
BK = os.path.join(ROOT, "assets", "_backup", "diezhi_art_v2_20261104")

# 旧件的口径：把这些数字改成新立绘实测出来的位置，锚点才会跟着走
BODY_CANVAS = (640, 692)
BODY_TOP = 2
BODY_H = 681
BODY_CX = 331          # 旧内容水平中心，新件也按它居中
RULE_CANVAS = (220, 64)
RULE_LEN = 185
CARD_SIZE = (640, 960)
GROUND_SIZE = (1024, 1024)
L = np.array([0.2126, 0.7152, 0.0722])

# rig 坐标换算（boss_rig_data.gd：part_offset = 贴图中心相对关节的偏移）
#   body 关节 (0,0)、offset (0,54) → body 贴图中心落在 rig (0,54)
#   所以画布点 (cx,cy) → rig (cx - 320, cy - 692/2 + 54) = (cx - 320, cy - 292)
BODY_JOINT = (0.0, 0.0)
BODY_OFFSET = (0.0, 54.0)
OLD_RULE_JOINT = (92, 37)


def canvas_to_rig(cx, cy):
    return (int(round(cx - BODY_CANVAS[0] / 2 + BODY_JOINT[0] + BODY_OFFSET[0])),
            int(round(cy - BODY_CANVAS[1] / 2 + BODY_JOINT[1] + BODY_OFFSET[1])))


def newest(prefix):
    ps = sorted(glob.glob(os.path.join(VIBE, prefix + "*.png")), key=os.path.getmtime)
    if not ps:
        raise SystemExit("找不到候选：vibe_images/%s*.png" % prefix)
    return ps[-1]


def keyed(prefix):
    im = Image.open(newest(prefix)).convert("RGB")
    return key_auto(im), detect_key(im), os.path.basename(newest(prefix))


def fit_part(img, canvas, target_h=None, target_len=None, cx=None, top=None):
    """按内容包围盒等比缩放放进画布；target_len 用于横长件（镇尺）。"""
    a = np.asarray(img)
    ys, xs = np.where(a[..., 3] > 24)
    if len(xs) == 0:
        raise SystemExit("整张都是键色")
    crop = img.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    if target_len:
        s = target_len / max(crop.size)          # 横长件按最长边定尺
    else:
        s = target_h / crop.size[1]
    w, h = max(1, int(round(crop.size[0] * s))), max(1, int(round(crop.size[1] * s)))
    crop = crop.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    px = int((cx if cx is not None else canvas[0] / 2) - w / 2)
    py = int(top if top is not None else (canvas[1] - h) / 2)
    out.alpha_composite(crop, (max(0, px), max(0, py)))
    return out


def metrics(img):
    a = np.asarray(img).astype(float)
    v = a[..., 3] > 200
    if not v.any():
        return None
    rgb = a[v][:, :3]
    lum = rgb @ L
    return {"median": np.median(rgb, 0), "bright": lum.mean(),
            "warm": (rgb[:, 0] - rgb[:, 2]).mean(), "solid": 100 * v.mean()}


def report(tag, old, new):
    o, n = metrics(old), metrics(new)
    if not o or not n:
        print("%-8s 旧件没有可见像素" % tag)
        return
    print("%-8s 亮度 %3.0f→%3.0f   暖偏 %+6.1f→%+6.1f   中位 %s→%s   实心 %.0f%%→%.0f%%" % (
        tag, o["bright"], n["bright"], o["warm"], n["warm"],
        np.round(o["median"]).astype(int), np.round(n["median"]).astype(int),
        o["solid"], n["solid"]))


def grip_at(body, lo, hi):
    """在内容高度 lo~hi 这段里取最靠右的 8% 像素当手，返回 rig 空间坐标。"""
    a = np.asarray(body)
    ys, xs = np.where(a[..., 3] > 200)
    if len(xs) < 200:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    band = (ys > y0 + (y1 - y0) * lo) & (ys < y0 + (y1 - y0) * hi)
    bx, by = xs[band], ys[band]
    if bx.size < 50:
        return None
    sel = bx >= np.quantile(bx, 0.92)
    return canvas_to_rig(int(np.median(bx[sel])), int(np.median(by[sel])))


def calibrate_band(old_body, want=OLD_RULE_JOINT):
    """在**旧件**上扫高度带，找出能复现 rig.tres 里那个握点的带。

    不这么办就会错：固定用 0.52~0.70 量旧件得到 (97,88)，而实际写的是 (92,37) —— x 对、y 差 51。
    手在身体上的相对高度是画师习惯，猜不得，只能拿已知答案反标定。
    """
    best = None
    for li in range(30, 72, 2):
        g = grip_at(old_body, li / 100.0, (li + 10) / 100.0)
        if g is None:
            continue
        err = abs(g[0] - want[0]) + abs(g[1] - want[1])
        if best is None or err < best[0]:
            best = (err, li / 100.0, g)
    return best


ICONS = {
    "skill_fold_press": "icon_fold_press_v2",
    "skill_fold_trace": "icon_fold_trace_v2",
    "skill_fold_stride": "icon_fold_stride_v4",
    "skill_fold_seam": "icon_fold_seam_v2",
    "skill_fold_shroud": "icon_fold_shroud_v2",
    "skill_fold_tear": "icon_fold_tear_v2",
    "skill_fold_twin": "icon_fold_twin_v2",
    "skill_fold_triple": "icon_fold_triple_v2",
    "skill_fold_measure": "icon_fold_measure_v2",
    "soul_diezhi": "icon_soul_diezhi_v2",
    "tr_diezhi_ling": "icon_tr_diezhi_ling_v2",
    # 11-04 第二轮：这两张不在上面 11 张清单里，漏了 —— 一张整幅糊着半透明灰紫底
    # （可见填充比 1.00 / 半透明占比 68.8%），一张暖偏 +72 还是黄纸色。
    "equip_zhicuo_jian": "icon_equip_zhicuo_jian_v2",
    "mat_zhaoying_zhihen": "icon_mat_zhaoying_zhihen_v2",
}
ICON_DIR = os.path.join(ROOT, "assets", "ui", "icon")


def run_icons(write):
    """11 张图标收片：自动量键色 → 256² → 掉碎点。旧件全是暖黄纸色 + 带圆角牌。"""
    from mat_icon_plate import key_to_icon
    rows = []
    for stem, prefix in ICONS.items():
        cands = sorted(glob.glob(os.path.join(VIBE, prefix + "*.png")), key=os.path.getmtime)
        if not cands:
            print("%-22s 没有新原片，跳过" % stem)
            continue
        icon, cov = key_to_icon(cands[-1], 256, 14, 48, auto=True)
        if icon is None:
            print("%-22s 判不出内容" % stem)
            continue
        a = np.asarray(icon).astype(float)
        al = a[..., 3]
        vis = al > 16                       # 可见（含半透明）：底板常常是半透明糊上去的
        ys, xs = np.where(vis)
        bw = xs.max() - xs.min() + 1
        bh = ys.max() - ys.min() + 1
        fill = vis.sum() / float(bw * bh)   # 外接矩形填充比：底板≈1.0，真物件 0.15~0.8
        semi = 100 * ((al > 16) & (al <= 200)).mean()
        v = al > 120
        rgb = a[v][:, :3] if v.any() else np.zeros((1, 3))
        warm = (rgb[:, 0] - rgb[:, 2]).mean()
        lum = rgb @ L
        # 底板残留判据：填充比 ≥0.95 或 半透明占比 ≥35% —— equip_zhicuo_jian 是 1.00 / 68.8%
        bad = "  ⚠ 底板没抠掉" if (fill >= 0.95 or semi >= 35.0) else ""
        print("%-22s 实心 %5.1f%%  亮度 %3.0f  暖偏 %+6.1f  填充比 %.2f  半透 %5.1f%%%s  <- %s" % (
            stem, cov, lum.mean(), warm, fill, semi, bad, os.path.basename(cands[-1])))
        rows.append((stem, icon, warm, fill, semi))
        if write and os.path.exists(os.path.join(ICON_DIR, stem + ".png")):
            os.makedirs(BK, exist_ok=True)
            bk = os.path.join(BK, "icon_" + stem + ".png")
            if not os.path.exists(bk):
                shutil.copy2(os.path.join(ICON_DIR, stem + ".png"), bk)
            icon.save(os.path.join(ICON_DIR, stem + ".png"))
    if write:
        print("图标已落盘 %d 张，备份在 %s" % (len(rows), BK))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="落盘（原件先备份）")
    ap.add_argument("--icons", action="store_true", help="只收 11 张图标")
    args = ap.parse_args()

    if args.icons:
        run_icons(args.write)
        return

    body_img, bkey, bsrc = keyed("boss_diezhi_v2_body")
    rule_img, rkey, rsrc = keyed("boss_diezhi_v2_rule")
    card_raw = Image.open(newest("card_boss_diezhi_v2")).convert("RGB")
    ground_raw = Image.open(newest("zhaoying_fold_arena_ground_v2")).convert("RGB")

    body = fit_part(body_img, BODY_CANVAS, target_h=BODY_H, cx=BODY_CX, top=BODY_TOP)
    rule = fit_part(rule_img, RULE_CANVAS, target_len=RULE_LEN)
    card = card_raw.resize(CARD_SIZE, Image.LANCZOS)
    ground = ground_raw.resize(GROUND_SIZE, Image.LANCZOS)

    olds = {
        "body": Image.open(os.path.join(RIG, "body.png")).convert("RGBA"),
        "rule": Image.open(os.path.join(RIG, "rule.png")).convert("RGBA"),
        "card": Image.open(os.path.join(ROOT, "assets/ui/codex/card_boss_diezhi.png")).convert("RGBA"),
        "ground": Image.open(os.path.join(ROOT, "assets/scenes/zhaoying_fold_arena_ground.png")).convert("RGBA"),
    }
    news = {"body": body, "rule": rule, "card": card.convert("RGBA"), "ground": ground.convert("RGBA")}

    print("body  候选 %s  量出键色 %s" % (bsrc, bkey.astype(int)))
    print("rule  候选 %s  量出键色 %s" % (rsrc, rkey.astype(int)))
    ba = np.asarray(body)
    ys, xs = np.where(ba[..., 3] > 200)
    print("body  放进 %s 画布：内容 x %d..%d  y %d..%d（旧件 x 214..449  y 2..682）" % (
        BODY_CANVAS, xs.min(), xs.max(), ys.min(), ys.max()))
    cal = calibrate_band(olds["body"])
    if cal is None:
        print("握点标定失败：旧件上扫不到任何带，要手标")
    else:
        err, lo, onew = cal
        gnew = grip_at(body, lo, lo + 0.10)
        print("握点带标定：内容高度 %.2f~%.2f 处（旧件复现 rig %d,%d，tres 写 %d,%d，误差 %d）" % (
            lo, lo + 0.10, onew[0], onew[1], OLD_RULE_JOINT[0], OLD_RULE_JOINT[1], int(err)))
        if gnew:
            print("  → 新件同带量得 rig %d,%d（旧 %d,%d）" % (gnew[0], gnew[1], onew[0], onew[1]))
        else:
            print("  → 新件该带内找不到手部像素，要手标")

    # 指标对照
    print("\n--- 旧 → 新（目标：亮度 20~97 / 暖偏为负）---")
    for k in ("body", "rule", "card", "ground"):
        report(k, olds[k], news[k])

    # 地面平铺判据
    ga = np.asarray(ground.convert("RGB")).astype(float) @ L
    lr = abs(ga[:, :6].mean() - ga[:, -6:].mean())
    tb = abs(ga[:6].mean() - ga[-6:, :].mean())
    print("地面 对边差 左右 %.2f 上下 %.2f（>3 就会露缝）  近黑 %.1f%%" % (
        lr, tb, 100 * (ga < 25).mean()))

    # 对照表
    S = 300
    sheet = Image.new("RGB", (S * 4, S * 2), (46, 48, 54))
    pairs = [("旧 body", olds["body"], 0, 0), ("新 body", body, 1, 0),
             ("旧 rule", olds["rule"], 2, 0), ("新 rule", rule, 3, 0),
             ("旧 地面", olds["ground"], 0, 1), ("新 地面", ground.convert("RGBA"), 1, 1),
             ("旧 卡面", olds["card"], 2, 1), ("新 卡面", news["card"], 3, 1)]
    for name, im, c, r in pairs:
        bb = im.getchannel("A").getbbox() or (0, 0, *im.size)
        t = im.crop(bb) if im.mode == "RGBA" else im
        t.thumbnail((S - 10, S - 10), Image.LANCZOS)
        cell = Image.new("RGBA", (S, S), (52, 54, 62, 255))
        cell.alpha_composite(t.convert("RGBA"), ((S - t.size[0]) // 2, (S - t.size[1]) // 2))
        sheet.paste(cell.convert("RGB"), (c * S, r * S))
    out = os.path.join(ROOT, "output", "diezhi_v2_sheet.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("对照表：", out)

    if args.write:
        os.makedirs(BK, exist_ok=True)
        targets = {
            os.path.join(RIG, "body.png"): body,
            os.path.join(RIG, "rule.png"): rule,
            os.path.join(ROOT, "assets/characters/boss/boss_diezhi.png"):
                body.resize((640, 692), Image.LANCZOS),
            os.path.join(ROOT, "assets/ui/codex/card_boss_diezhi.png"): card.convert("RGBA"),
            os.path.join(ROOT, "assets/scenes/zhaoying_fold_arena_ground.png"): ground,
        }
        for path, im in targets.items():
            if os.path.exists(path):
                bk = os.path.join(BK, os.path.basename(os.path.dirname(path)) + "_" + os.path.basename(path))
                if not os.path.exists(bk):
                    shutil.copy2(path, bk)
            im.save(path)
            print("已落盘", os.path.relpath(path, ROOT))
        print("原件备份在", BK)


if __name__ == "__main__":
    main()
