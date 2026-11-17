class_name MatchQuickSetup
extends RefCounted
## 快速模式开局布局的**唯一来源**（票 002 / ADR-0004）。
##
## 给定关卡号，算出对方 6 张牌各自坐在哪个格子、正面还是反面。
## 两个调用方：
##   · 长卷拓印 —— 快速模式开着时按它画"真实落位"；
##   · 对局开局 —— quick_prepare() 把同一批格子喂进 apply_command({"t":"deploy"})。
## 只准有一个实现：两处各算一次就一定会漂，而玩家是照着卷来针对的，
## 漂一次等于骗他。
##
## 不另写一套布阵规则：正反面走 `MatchPolicy.face_flags`（和普通模式 LOCK 同一个函数），
## 落格走 `MatchPolicy.random_free_cell`（和 `decide_deploy` 同一个函数）。
## 快速模式真正不同的只有**种子来源**（关卡号而非本局随机）和**日程**
## （对方 6 张一次摆完，不与玩家交替）。

const SEED_NS := "match_quick_%d"

static var _cache: Dictionary = {}


## 内容寻址种子：与 ADR-0002 同一约定（`hash("命名空间_编号")`），
## 所以同一关在任何存档、任何时间都得到同一副布局。
static func seed_for(level: int) -> int:
	return hash(SEED_NS % _clamp(level))


## 对方 6 张的落位。返回按**落子先后**排序的数组，每项
## `{boss_id: String, cell: Vector2i, face_up: bool}`。
static func layout_for(level: int) -> Array:
	var lv := _clamp(level)
	if _cache.has(lv):
		return _cache[lv]
	var deck: Array = MatchLevelDeck.deck_for(lv)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(lv)

	# ① 正反面：不指定 down/up ⇒ face_flags 自己按"最强锁正、最弱锁反"取，
	#    和 AI 在普通模式 LOCK 阶段的判据逐字相同。
	var dps: Array = []
	for id in deck:
		dps.append(float(MatchDB.piece_stats(String(id))["dps"]))
	var flags := MatchPolicy.face_flags(dps, rng)

	# ② 落格：先洗一个出子顺序，再逐张随机挑空格 —— 和 decide_deploy 的
	#    "随机卡 + 随机空格"同一套原语，只是这里不需要等玩家交替。
	var order: Array = range(deck.size())
	MatchPolicy.fisher_yates(order, rng)
	var out: Array = []
	var occupied: Array = []
	for pos in order:
		var cell := MatchPolicy.random_free_cell(occupied, rng)
		occupied.append(cell)
		out.append({"boss_id": String(deck[int(pos)]), "cell": cell,
				"face_up": bool(flags[int(pos)])})
	_cache[lv] = out
	return out


## 缓存清空（测试用；换卡池口径时也要清）。
static func reset_cache() -> void:
	_cache.clear()


static func _clamp(level: int) -> int:
	return maxi(level, 1)
