# BOSS 仇恨值机制（2026-10-21 用户定）

> 一句话：敌方 BOSS 对「玩家 + 每个友军召唤物」各记一份仇恨，**最高者成为它的 target**。
> AI 追击、面向、单体招式全都读 `target`，所以换 target 就等于换仇恨目标。

## 1. 仇恨怎么算

```
仇恨(单位) = 近 5 秒对它造成的伤害 × THREAT_PER_DAMAGE
           + 距离仇恨（越近越高，贴脸给满 THREAT_DIST_MAX）
           + 嘲讽 / 外部写入（add_threat）
```

| 组成 | 常量 | 默认 | 说明 |
|---|---|---|---|
| 伤害窗口 | `THREAT_DAMAGE_WINDOW` | 5.0 秒 | 只记最近 5 秒打出来的伤害，超时那笔自动失效（**用实际扣掉的血**，不是原始伤害） |
| 伤害权重 | `THREAT_PER_DAMAGE` | 1.0 | 1 点伤害 = 1 点仇恨；调大 = 输出更容易拉住仇恨 |
| 距离上限 | `THREAT_DIST_MAX` | 40.0 | 距离 0 时的距离仇恨；约等于「白打 40 点伤害」 |
| 距离范围 | `THREAT_DIST_RANGE` | 600.0 | 超过这个距离距离仇恨归零 |
| 重选间隔 | `THREAT_RECHECK` | 0.4 秒 | 定时重新评估目标 |
| 切换迟滞 | `THREAT_SWITCH_MARGIN` | 1.1 | 新目标要 ≥ 当前目标 ×1.1 才换，防止两个目标仇恨接近时来回抖 |

**距离公式**：`THREAT_DIST_MAX × clamp(1 − 距离 / THREAT_DIST_RANGE, 0, 1)` —— 贴脸 40、300px 处 20、600px 外 0。

**伤害归属**：伤害来源会被映射成「仇恨单位」
- 玩家 / 友军召唤物本体 → 它自己
- 投射物 → 先读它身上的 `source`（BOSS 投射物有）；玩家投射物目前不带发射者字段 → **兜底算成玩家的**
- 兜底仍为空 → 归给玩家

## 2. 什么时候换目标（用户拍板的三条）

1. **只在待机（IDLE）/ 追击（CHASE）时换**：前摇、出招、收招、僵直期间锁定当前目标，
   不会出现「招式打到一半突然转身」。
2. **目标消失 → 立刻强制重选**：召唤物消散或被打死，仇恨立刻清除，BOSS 马上回玩家。
   ⚠ 这条同时是**防崩措施**——`target` 若留在已释放的召唤物上，下一帧读 `global_position` 就会
   报 "previously freed instance"（2026-10-21 修过的同类坑）。
3. **迟滞 1.1 倍**：新目标仇恨必须高出当前目标 10% 才换。

范围攻击（`attack_units()`）不受影响——本来就打一片；仇恨只决定「追谁、朝谁出招、单体招式打谁」。

## 3. 代码位置（`scripts/boss/boss_base.gd`）

| 函数 | 作用 |
|---|---|
| `_tick_threat(delta)` | 每帧：清失效单位 → 窗口衰减 → 目标失效强制重选 → 定时重选 |
| `_update_threat_target(force)` | 挑仇恨最高的单位；`force=true` 无视「出招中不换」 |
| `_set_threat_target(unit)` | 真正切换（写 `target` 与 `threat_target`） |
| `_threat_of(unit)` | 该单位当前仇恨；**-1 = 已失效 / 已消散**，不该再当目标 |
| `threat_of_unit(unit)` | 对外读取（调试 / 以后做仇恨条） |
| `_register_damage_threat(src, amount)` | 受伤时记账，由 `take_damage` 调用 |
| `add_threat(unit, amount, duration)` | **嘲讽接口**：外部写入仇恨，`duration<=0` 为常驻 |
| `_threat_unit_of(src)` | 伤害来源 → 仇恨单位 |

友军召唤物（`is_ally = true`）**不维护仇恨表**，它的 target 恒为敌方 BOSS。

## 4. 以后的嘲讽机制怎么接

```gdscript
# 例：玩家开嘲讽技能，让 BOSS 5 秒内死盯自己
for b in get_tree().get_nodes_in_group("boss"):
    (b as BossBase).add_threat(player, 2000.0, 5.0)   # 5 秒后自动失效

# 例：某个召唤物自带「常驻嘲讽光环」（只要它还活着就一直拉仇恨）
boss.add_threat(summon, 800.0, 0.0)                   # duration<=0 = 常驻，单位消失才清
```

想做「嘲讽倍率」而不是「固定数值」，就在调用处按自己的倍率换算成 amount 传进来即可，
仇恨表本身不需要改。

## 5. 调参建议

- 召唤物太容易抢仇恨 → 调小 `THREAT_DIST_MAX`，或给召唤物的伤害走一个折扣
  （在 `_register_damage_threat` 里按 `unit is BossBase` 乘系数）。
- 想让输出更能拉住 → 调大 `THREAT_PER_DAMAGE`。
- 觉得目标切得太频繁 → 调大 `THREAT_SWITCH_MARGIN`（1.2~1.3）。
