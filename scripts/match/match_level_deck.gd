class_name MatchLevelDeck
extends RefCounted
## 棋坛关卡 · 对手卡组生成器（纯函数，不碰节点、不读存档）
##
## 口径见 docs/adr/0002-关卡卡组由关卡号确定性生成.md 与 CONTEXT.md：
## 关卡号是唯一的难度输入，同一关在任何存档重打都得到同一副，
## 不同关之间严格不重副，且关卡号不参与任何数值计算。
##
## 难度只来自"谁上场"：按**原始面板 HP×攻击**的名次加权（天然跨 490 倍），
## 不用棋盘折算 power —— 那只跨 0.92~1.14，是设计案 §2 第 5 条刻意压平的，
## 拿它当权重等于没加权。

## 单关最多重摇几次。
## ⚠ 别以为上限是 C(16,6)=8008：加权饱和（第 50 关起 bias=1）后强半区几乎垄断抽样，
##   实测**可达**组合只有 ~3400 副、第 416 关起就会撞车（探针 ⑦ 量出来的）。
##   玩家能打到几百关已经是极限，所以这里取 12 就够——
##   在真实区间（占用率 <5%）连续 12 次撞车的概率约 10^-16，去重照样成立；
##   而空间真用尽时，重摇再多也只是白烧时间（64 次实测把 1..8100 拉到 64 秒）。
const MAX_REROLLS := 12
## 重摇偏移用的质数，要保证不同 attempt 的 seed 不互相覆盖
const REROLL_PRIME := 0x5A17
## 满偏时最强那只相对最弱那只的权重倍数。40 倍能把平均名次从 8.5 抬到 ~12.6。
const WEIGHT_RATIO := 40.0
## 第几关把偏置走满。定在 50 是因为玩家真会玩的区间就是前几十关，
## 曲线必须在那段里看得见，而不是铺到 400 关才慢慢抬头。
const BIAS_FULL_LEVEL := 50.0
## 抬升形状：0.75 让前期就有变化、后期不再无限陡（1.0 是线性，0.5 是 sqrt）。
const BIAS_CURVE_EXP := 0.75

## 递推缓存与已用组合表。生成第 N 关必须先把 1..N-1 都算出来，
## 所以这里按序补齐；调用顺序（先问 300 还是先问 7）不影响结果。
static var _cache: Dictionary = {}
static var _used: Dictionary = {}
## boss_id → 原始面板名次（1 最弱）。首次用到时按 PANEL_SNAPSHOT 现算一次。
static var _ranks: Dictionary = {}


## 公共接缝：所有测试与调用方都只走这一个函数。
## 关卡号从 1 起；0 / 负数一律按第 1 关处理，不另开一副"幽灵牌"
## （调用方传的是 `match_level_cleared + 1`，默认 0 的旧档会直接撞下界）。
static func deck_for(level: int) -> Array:
	var lv := _clamp_level(level)
	if _cache.has(lv):
		return _cache[lv]
	for pre in range(1, lv + 1):
		if not _cache.has(pre):
			_cache[pre] = _generate(pre)
	return _cache[lv]


static func _clamp_level(level: int) -> int:
	return maxi(level, 1)


## 卡组 → 稳定指纹（排序后拼接），用于「同一副」的判等。
static func combo_key(deck: Array) -> String:
	var ids: Array[String] = []
	for id in deck:
		ids.append(String(id))
	ids.sort()
	return "|".join(ids)


## 某只卡在本关卡池里的原始面板名次（1 最弱 → 16 最强），给界面标"强度档"用。
static func raw_rank(boss_id: String) -> int:
	_ensure_ranks()
	return int(_ranks.get(boss_id, 0))


## 清空缓存。只给探针/以后改权重时用；正式运行期不需要。
static func reset_cache() -> void:
	_cache.clear()
	_used.clear()
	_ranks.clear()


static func _generate(level: int) -> Array:
	for attempt in MAX_REROLLS:
		var deck := _draw(level, attempt)
		var k := combo_key(deck)
		if not _used.has(k):
			_used[k] = level
			return deck
	# 可达组合用尽（实测约第 416 关起）：宁可重复也不能崩或死循环
	var fallback := _draw(level, 0)
	push_warning("MatchLevelDeck: 第 %d 关重摇 %d 次仍与已有关卡重复，组合已用尽" % [level, MAX_REROLLS])
	_used[combo_key(fallback)] = level
	return fallback


## 加权不放回抽 6 张。权重只随名次与关卡号变，不随任何棋子面板变。
static func _draw(level: int, attempt: int) -> Array:
	_ensure_ranks()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(level, attempt)
	var bias := _bias(level)
	var bag: Array = MatchDB.CARD_POOL.duplicate()
	var deck: Array = []
	while deck.size() < MatchDB.DECK_SIZE and not bag.is_empty():
		var total := 0.0
		for id in bag:
			total += _weight(String(id), bias)
		var roll := rng.randf() * total
		var pick := bag.size() - 1
		var acc := 0.0
		for i in bag.size():
			acc += _weight(String(bag[i]), bias)
			if roll <= acc:
				pick = i
				break
		deck.append(bag[pick])
		bag.remove_at(pick)
	return deck


static func _weight(boss_id: String, bias: float) -> float:
	var n := maxi(_ranks.size(), 1)
	var pos := float(maxi(int(_ranks.get(boss_id, 1)) - 1, 0)) / float(n - 1)
	return pow(WEIGHT_RATIO, bias * pos)


## 0 → 1 的偏置：前期就有变化，第 50 关走满后不再变陡。
static func _bias(level: int) -> float:
	var t := clampf(float(maxi(level, 1)) / BIAS_FULL_LEVEL, 0.0, 1.0)
	return pow(t, BIAS_CURVE_EXP)


static func _seed_for(level: int, attempt: int) -> int:
	return hash("match_level_%d" % level) + attempt * REROLL_PRIME


static func _ensure_ranks() -> void:
	if not _ranks.is_empty():
		return
	var scored: Array = []
	for id in MatchDB.CARD_POOL:
		var p: Dictionary = MatchDB.PANEL_SNAPSHOT[String(id)]
		scored.append([String(id), float(p.hp) * float(p.atk)])
	# 同分按 id 字典序破平，免得不同平台排序不稳定导致名次翻转、卡组跟着变
	scored.sort_custom(func(a, b):
		if float(a[1]) == float(b[1]):
			return String(a[0]) < String(b[0])
		return float(a[1]) < float(b[1])
	)
	for i in scored.size():
		_ranks[String(scored[i][0])] = i + 1
