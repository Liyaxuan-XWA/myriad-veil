#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把叠纸（boss_04_c · 塔 12 层）的四张卡解锁出来，好进游戏直接翻卡包与收藏封面。

只动三个键，其它一律不碰：
  tower_progress["12"]      → {clear_count, first_kill, unlocked}   （普通卡 + 华彩·有背景）
  tower_no_hit_double["12"] → true                                  （纯华彩·无背景）
  tower_best_time["12"]     → ≤ INK_CLEAR_TIME_LIMIT 的一个值        （水墨异画）

规矩：先确认游戏已关；每个被改的槽先备份（已存在就不覆盖）；打印被覆盖/新增的真实纪录；
重复跑是幂等的（已经满足就跳过）。
"""
import io
import json
import os
import shutil
import sys

SAVE_DIR = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "万界秘境")
FLOOR = "12"                 # 塔 12 层 = 叠纸（WorldDB.get_floors 按位面顺序生成，domain_04 第三位）
CLEAR_COUNT = 12.0           # 与其它层同档（那些层是 12~25），过 HOLO_CLEAR_REQUIRED = 11
BEST_TIME = 6.0              # 与 10/11 层一致，且 ≤ 10.0 才解水墨
BACKUP_SUFFIX = ".preunlock.json"


def card_state(d):
    """按 CodexDB.card_entry 的读法，算出四张卡现在解没解。"""
    tp = d.get("tower_progress", {}).get(FLOOR, {})
    count = float(tp.get("clear_count", 0) or 0)
    first = bool(tp.get("first_kill", False))
    best = d.get("tower_best_time", {}).get(FLOOR)
    dbl = bool(d.get("tower_no_hit_double", {}).get(FLOOR, False))
    boss_cleared = count >= 1 or first
    double_cleared = count >= 11
    ink = boss_cleared and double_cleared and best is not None and 0.0 <= float(best) <= 10.0
    return {
        "普通卡·原画": boss_cleared,
        "华彩·有背景": double_cleared,
        "纯华彩·无背景": double_cleared and dbl,
        "水墨异画": ink,
    }


def main():
    if not os.path.isdir(SAVE_DIR):
        sys.exit("找不到存档目录：%s" % SAVE_DIR)
    live = [p for p in os.listdir(SAVE_DIR) if p.startswith("save_slot_")
            and p.endswith(".json") and not p.endswith(BACKUP_SUFFIX)
            and ".bak." not in p and "clobbered" not in p]
    if not live:
        sys.exit("没有存档槽")
    print("存档目录：%s" % SAVE_DIR)
    for name in sorted(live):
        path = os.path.join(SAVE_DIR, name)
        d = json.load(io.open(path, encoding="utf-8"))
        before = card_state(d)
        if all(before.values()):
            print("\n[%s] 四张已全解锁，跳过（幂等）" % name)
            continue
        tp = d.setdefault("tower_progress", {})
        old_tp = tp.get(FLOOR)
        old_dbl = d.get("tower_no_hit_double", {}).get(FLOOR)
        old_best = d.get("tower_best_time", {}).get(FLOOR)
        print("\n[%s] 被覆盖的真实纪录：" % name)
        print("   tower_progress[%s]      = %r" % (FLOOR, old_tp))
        print("   tower_no_hit_double[%s] = %r" % (FLOOR, old_dbl))
        print("   tower_best_time[%s]     = %r" % (FLOOR, old_best))
        # 备份：只在第一次看到时留，重跑不会把母本冲掉
        bak = path.replace(".json", BACKUP_SUFFIX)
        if os.path.exists(bak):
            print("   备份已存在，不覆盖：%s" % os.path.basename(bak))
        else:
            shutil.copy2(path, bak)
            print("   备份 → %s" % os.path.basename(bak))
        # 只补这三个键；层号在 JSON 里是字符串（save_manager 的 _keys_to_str 口径）
        entry = tp.setdefault(FLOOR, {})
        entry["clear_count"] = max(float(entry.get("clear_count", 0) or 0), CLEAR_COUNT)
        entry["first_kill"] = True
        entry["unlocked"] = True
        d.setdefault("tower_no_hit_double", {})[FLOOR] = True
        prev_best = d.setdefault("tower_best_time", {}).get(FLOOR)
        d["tower_best_time"][FLOOR] = BEST_TIME if prev_best is None \
            else min(float(prev_best), BEST_TIME)
        after = card_state(d)
        print("   写入后：tower_progress[%s] = %s / no_hit_double=True / best=%s"
              % (FLOOR, entry, d["tower_best_time"][FLOOR]))
        print("   四张卡：", "  ".join("%s=%s" % (k, "已解锁" if v else "锁着")
                                       for k, v in after.items()))
        io.open(path, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
        print("   已写回 %s" % name)
    print("\n完成。要还原就把 %s 覆盖回同名槽即可。" % BACKUP_SUFFIX)


if __name__ == "__main__":
    main()
