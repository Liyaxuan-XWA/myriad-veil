"""把「当前存档」里全部卡包的解锁条件补齐（2026-11-02）

目的：让你在**游戏里**直接翻收藏册检查 60 张卡面，而不是只看截图。

⚠ 只动卡片系统真正读的四个字段，别的一律不碰：
    tower_progress[f].clear_count   → 抬到 12（华彩卡要 ≥ 11 次）
    tower_no_hit_double[f]          → true（双倍血场次无伤）
    tower_best_time[f]              → 只有 > 10 秒才改成 6 秒（纸本水墨要 10 秒内纪录）
    core_replay[region]             → 大陆核心首领同口径
  **不动** first_kill / unlocked / domain_progress / tower_no_hit_reward /
  card_reward_claimed —— 所以首杀奖励、位面万界本源、无伤 50 晶石都还在，
  新解锁的非普通卡也仍然可以领晶石（15 位 × 3 张 ≈ 2250 颗，这是副作用，别当白嫖忘了来路）。

跑之前自动整份备份到 save_backups/<时间戳>/。脚本幂等，重复跑结果一样。
⚠ 游戏开着的话，退出时的自动存档会覆盖本脚本的改动 —— 先关游戏再跑。
"""

import json
import os
import shutil
import sys
import time

SAVE_DIR = os.path.join(os.environ.get("APPDATA", ""), "Godot",
                        "app_userdata", "万界秘境")
SLOTS = (1, 2, 3, 4, 5)
CORE_CLEARS = 12
BEST_TIME_LIMIT = 10.0
BEST_TIME_FAKE = 6.0
REGIONS = ["world_lianqi", "world_zhuji", "world_jiedan", "world_yuanying"]


def backup_dir():
    d = os.path.join(SAVE_DIR, "save_backups", time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(d, exist_ok=True)
    return d


def patch_slot(path, log):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    tp = data.setdefault("tower_progress", {})
    nd = data.setdefault("tower_no_hit_double", {})
    bt = data.setdefault("tower_best_time", {})

    floors = [str(i) for i in range(1, 12)]
    for fl in floors:
        e = tp.get(fl)
        if not isinstance(e, dict):
            # 没打过的层：只塞 clear_count，不写 first_kill / unlocked，
            # 这样真打通时首杀奖励照发。
            # ⚠ 不能 continue —— 后面两步（无伤标记、最佳纪录）是新层也需要的，
            #   第一版在这里提前返回，结果塔 11 层只解到「华彩」档，水墨卡仍是灰的。
            tp[fl] = {"clear_count": CORE_CLEARS}
            log.append("  塔 %2s 层：新建条目 clear_count=%d（未标记首杀）" % (fl, CORE_CLEARS))
        else:
            cur = int(e.get("clear_count", 0) or 0)
            if cur < CORE_CLEARS:
                e["clear_count"] = float(CORE_CLEARS)
                log.append("  塔 %2s 层：通关次数 %d → %d" % (fl, cur, CORE_CLEARS))
        if not bool(nd.get(fl, False)):
            nd[fl] = True
            log.append("  塔 %2s 层：补「双倍血无伤」标记" % fl)
        raw = bt.get(fl, -1.0)
        try:
            t = float(raw)
        except (TypeError, ValueError):
            t = -1.0
        if not (0.0 <= t <= BEST_TIME_LIMIT):
            bt[fl] = BEST_TIME_FAKE
            log.append("  塔 %2s 层：最佳纪录 %s → %.1f 秒（纸本水墨要 10 秒内）"
                       % (fl, ("无" if t < 0 else "%.2f" % t), BEST_TIME_FAKE))

    sw = data.setdefault("secret_world", {})
    kills = sw.setdefault("core_kills", {})
    cr = data.setdefault("core_replay", {})
    for region in REGIONS:
        if not bool(kills.get(region, False)):
            kills[region] = True
            log.append("  核心 %s：补「已击杀」" % region)
        e = cr.get(region)
        if not isinstance(e, dict):
            cr[region] = {"clear_count": float(CORE_CLEARS), "best_time": BEST_TIME_FAKE,
                          "no_hit_double": True}
            log.append("  核心 %s：新建重战记录" % region)
            continue
        if int(e.get("clear_count", 0) or 0) < CORE_CLEARS:
            e["clear_count"] = float(CORE_CLEARS)
            log.append("  核心 %s：通关次数抬到 %d" % (region, CORE_CLEARS))
        if not bool(e.get("no_hit_double", False)):
            e["no_hit_double"] = True
            log.append("  核心 %s：补「双倍血无伤」" % region)
        t = float(e.get("best_time", -1.0) or -1.0)
        if not (0.0 <= t <= BEST_TIME_LIMIT):
            e["best_time"] = BEST_TIME_FAKE
            log.append("  核心 %s：最佳纪录 %s → %.1f 秒"
                       % (region, ("无" if t < 0 else "%.2f" % t), BEST_TIME_FAKE))
    return data


def main():
    if not os.path.isdir(SAVE_DIR):
        raise SystemExit("找不到存档目录：%s" % SAVE_DIR)
    paths = [os.path.join(SAVE_DIR, "save_slot_%d.json" % s) for s in SLOTS]
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        raise SystemExit("存档目录里没有 save_slot_*.json")

    bak = backup_dir()
    for p in paths:
        shutil.copy2(p, os.path.join(bak, os.path.basename(p)))
    print("已备份 %d 份到 %s" % (len(paths), bak))

    for p in paths:
        log = []
        data = patch_slot(p, log)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        print("\n%s：改动 %d 处" % (os.path.basename(p), len(log)))
        for line in log[:60]:
            print(line)
        if len(log) > 60:
            print("  …另有 %d 处同类" % (len(log) - 60))
    print("\n完成。进游戏开万界图鉴·成就卡包即可翻全部 60 张。")
    print("要回滚：把 %s 里的文件复制回上层同名文件。" % bak)


if __name__ == "__main__":
    sys.exit(main())
