class_name MatchCombat
extends RefCounted
## 棋子的**抽象**战斗模型 —— 存在的唯一理由是让规则层能脱离场景跑千局模拟。
##
## 它不模拟走位、射程、前摇、元素克制、二阶段、任何机制。那些是第 4 步
## `PieceAdapter` 加载真 BOSS 场景之后的事，届时这个类整体被替换掉。
## 这里只回答一个问题：**状态机在棋子会死的情况下会不会卡住、会不会误判胜负**。
## 所以模拟结果只能用来验规则闭合，不能用来判断平衡 —— 别拿它的胜率表当结论。

## 伤害模型：每只活着的棋子把 dps 全压给**最近的**敌方棋子（集火），
## 位置就是它的出生格，不移动。
## 只把"场上现在的真实状态"镜像进 cards（改 hp / alive），**不产生任何伤害**。
## 抽象模型没有"真实棋盘"可镜像 → 空实现；真棋子模型 `MatchLiveCombat` 覆写它。
## 为什么要和 step() 分开：选牌窗口是时停的，那一支不结算伤害，
## 但真棋子是活的、照样在互相砍 —— 不镜像就会出现"棋盘上已经躺了一只、
## 规则层还以为两边都站着"，HUD 的存活数与画面直接对不上。
func sync(_cards: Array) -> void:
	pass


func step(cards: Array, delta: float) -> void:
	var alive: Array = []          # 装的是 cards 的下标，不是字典副本
	for i in cards.size():
		if bool(cards[i]["spawned"]) and bool(cards[i]["alive"]):
			alive.append(i)
	if alive.size() < 2:
		return
	# 先算好这一帧每人该掉多少血，再统一扣 —— 否则先处理的棋子会把后处理的
	# 直接打死，导致同一帧里「谁先结算」影响结果，模拟就不再可复现。
	var damage := {}
	for i in alive:
		var j := _nearest_enemy(cards, alive, i)
		if j < 0:
			continue
		damage[j] = float(damage.get(j, 0.0)) + float(cards[i]["dps"]) * delta
	for j in damage.keys():
		var c: Dictionary = cards[int(j)]
		c["hp"] = float(c["hp"]) - float(damage[j])
		if float(c["hp"]) <= 0.0:
			c["alive"] = false


func _nearest_enemy(cards: Array, pool: Array, from: int) -> int:
	var me := int(cards[from]["team"])
	var best := -1
	var best_d := INF
	for i in pool:
		if int(cards[i]["team"]) == me:
			continue
		var d := Vector2(cards[from]["pos"]).distance_squared_to(Vector2(cards[i]["pos"]))
		if d < best_d:
			best_d = d
			best = i
	return best


## 某队是否还有活着的棋子（场上无子 ≠ 判负 —— 12 张没翻完前还得继续放，
## 这条是用户定的「全部翻完再分胜负」，胜负只在 FINAL 阶段读这里）。
static func team_alive(cards: Array, team: int) -> bool:
	for c in cards:
		if int(c["team"]) == team and bool(c["spawned"]) and bool(c["alive"]):
			return true
	return false


## 剩余血量百分比之和 —— FINAL 超时的判据。
## 用百分比而不是绝对值：否则上限高的棋子天然多一条命（原始面板差 77 倍）。
static func hp_fraction_sum(cards: Array, team: int) -> float:
	var total := 0.0
	for c in cards:
		if int(c["team"]) != team or not bool(c["spawned"]) or not bool(c["alive"]):
			continue
		var m := float(c["hp_max"])
		if m > 0.0:
			total += clampf(float(c["hp"]) / m, 0.0, 1.0)
	return total
