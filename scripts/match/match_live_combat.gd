class_name MatchLiveCombat
extends MatchCombat
## 真棋子的战斗读数 —— 把 `cards` 的血量/存活**反向同步**自场上的真 BOSS 实例。
##
## 为什么必须换掉父类：`MatchCombat.step()` 自己按 dps×dt 扣血，
## 而真棋子身上有一套完整的伤害管线（招式系数、抗性、无敌帧、弹反、护体）。
## 两套同时写 `hp` 就是两个真相来源 —— 表现是"血条明明还有却判死了"
## 或者"模型站着但规则层认为它已经没了"。
## 这里只读不写：伤害结算完全交给真 BOSS，规则层只负责在合适时机读结果。

## card_index → 棋子实例。由 MatchArena 在 spawn 事件里填。
var pieces: Dictionary = {}


## 真棋子没有"自己算伤害"这一步，所以 step 与 sync 是同一件事；
## 但选牌窗口（时停、不结算伤害）也要镜像，故 MatchState 两处分别调用。
func step(cards: Array, _delta: float) -> void:
	sync(cards)


func sync(cards: Array) -> void:
	for idx in pieces.keys():
		var i := int(idx)
		if i < 0 or i >= cards.size():
			continue
		# ⚠ 必须先取成 Variant 再判存活：真 BOSS 死亡后会自行释放，
		#   而 `var piece: Node = 已释放实例` 这一步**本身就是错误**
		#   （"Trying to assign invalid previously freed instance"），
		#   is_instance_valid 根本来不及执行。冒烟测试里每帧刷一条就是这个。
		var raw = pieces[idx]
		var card: Dictionary = cards[i]
		if raw == null or not is_instance_valid(raw):
			card["alive"] = false
			_dead.append(idx)
			continue
		var piece := raw as Node2D
		card["hp"] = float(piece.get("current_hp"))
		if BossBase.is_unit_dead(piece):
			card["alive"] = false
			_dead.append(idx)
	# 死透的从表里摘掉：留着既不报错也白跑，摘了才能确定"这帧之后不再碰它"
	for k in _dead:
		pieces.erase(k)
	_dead.clear()


var _dead: Array = []
	# 已经没棋子对应的卡（比如从未 spawn）不动它，交给 spawn 事件负责置 alive


## 真棋子已经不需要抽象集火逻辑，但父类的静态判读（team_alive / hp_fraction_sum）
## 读的正是上面同步回来的 hp / alive，所以胜负判定不用另写一套。
