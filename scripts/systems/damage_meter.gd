class_name DamageMeter
extends RefCounted
## BOSS 伤害统计台账（2026-11-12 用户定：打完 BOSS 在左侧出一块逐技能的伤害面板）
##
## 只记**减免之后实际掉的血**（和伤害飘字同一个数），每行一个来源。
## 记账点只有一个：`BossBase.take_damage`（所有扣血都要过这里）。
## 来源标签由打人方在出手前 `push()` 一次，`record()` 消费掉 —— 没 push 的算「其他」。
##
## ⚠ 只统计真实位面战 / 万界塔：由 CombatArena 开局 `begin()`、击杀 `finish()`。
##   演武场 / 试炼 / 核心分支不记账（它们的「BOSS」是木桩或无尽模式，没有可比性）。
## ⚠ 别在这里判血量或死亡：台账只认「这一下掉了多少」，结算链路一处都不改。

static var active := false
## 来源标签 → 累计伤害
static var rows: Dictionary = {}
static var total := 0.0
## 当前这一下的来源标签（push 后由 record 消费；不跨帧残留）
static var _tag := ""


static func begin() -> void:
	active = true
	rows = {}
	total = 0.0
	_tag = ""


static func finish() -> void:
	active = false
	_tag = ""


## 打人方在 take_damage 之前调一次，声明「这一下是谁打的」
static func push(tag: String) -> void:
	if active:
		_tag = tag


## 由 BossBase.take_damage 调用：amount = 减免后实际掉的血
static func record(amount: float) -> void:
	if not active:
		_tag = ""
		return
	var tag := _tag if _tag != "" else "其他"
	_tag = ""
	if amount <= 0.0:
		return
	rows[tag] = float(rows.get(tag, 0.0)) + amount
	total += amount


## 排行：按伤害降序；超过 limit 行时只留前 limit-1 名 + 一行「其他」（不出现两行同名）
static func ranked(limit: int = 8) -> Array:
	var list: Array = []
	for k in rows.keys():
		list.append({"tag": String(k), "amount": float(rows[k])})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["amount"]) > float(b["amount"]))
	if list.size() <= limit:
		return list
	# 「最多 limit 行」= 前 limit-1 名 + 一行「其他」
	var show_n := maxi(1, limit - 1)
	var head: Array = list.slice(0, show_n)
	var rest := 0.0
	for i in range(show_n, list.size()):
		rest += float(list[i]["amount"])
	for r in head:
		if String(r["tag"]) == "其他":
			r["amount"] = float(r["amount"]) + rest
			return head
	head.append({"tag": "其他", "amount": rest})
	return head
