class_name BossRigLiangyi
extends BossRigHuman

## 两仪真人的骨骼动画集（2026-10-27）。
##
## 与刀客 / 剑客共用 `BossRigHuman` 的关节与「慢蓄力 → 爆发 → 定格」生成器；
## 只写差异：不持长兵，表演主力是**躯干旋转 + 双臂开合 + 背后太极环**。
##
## 关节：
## ```
## body（躯干 + 头 + 长袍）
##   ├── halo    身后光环的**外环 + 八卦**（整圈自转）
##   ├── taiji   身后光环的**太极盘**（不转 —— 对称图形必须始终直立）
##   ├── leg_back / leg_front
##   ├── staff   长杖（父 = arm，轴在**手握处**）
##   └── arm     广袖 + 手
## ```
## ⚠ 2026-10-28：杖必须**独立成件**，不能并进 arm。arm 是绕肩转的，而杖跟人差不多
##   高（约 555px），并进去之后任何手臂动作都会把整根杖从左上甩到右上，像抡棍子 ——
##   两仪是法系，招式是掌 / 指 / 印，抬手施法时杖应该立在身侧。staff 的旋转轴放在
##   手握处，只做很轻的滞后摆动（见 `_extra_loops`）。
## 分件由 tools/gen_liangyi_art.py 生成：每张都是整画布 900×720，
## rig.tres 的 offset = -joint，所以换正式美术时覆盖同名 PNG 即可。

const LY_SKILLS := {
	"palm": {"length": 0.75, "windup": 0.75},
	"finger": {"length": 0.70, "windup": 0.70},
	"flip": {"length": 0.60, "windup": 0.60},
	"collapse": {"length": 1.20, "windup": 1.20},
	"triple": {"length": 0.60, "windup": 0.60},
	"wind": {"length": 0.80, "windup": 0.80},
	"fish": {"length": 0.70, "windup": 0.70},
	"counter": {"length": 1.80, "windup": 0.80},
}


func _skill_table() -> Dictionary:
	return LY_SKILLS


func _make_skill(anim: String) -> Animation:
	match anim:
		"palm":
			return _make_palm()
		"finger":
			return _make_finger()
		"flip":
			return _make_flip()
		"collapse":
			return _make_collapse()
		"triple":
			return _make_triple()
		"wind":
			return _make_wind()
		"fish":
			return _make_fish()
		"counter":
			return _make_counter()
	return _make_palm()


## 待机 / 走路额外轨道：太极环缓慢自转 + 飘带滞后 + 长杖极轻的呼吸摆动
## ⚠ 杖的摆幅必须很小（0.02 级）：它是一根立地的长杖，摆大了就成了抡棍子。
func _extra_loops(a: Animation) -> void:
	_add_sine(a, "staff", "rotation", 0.022, 0.5, 0)
	# 外环**整圈自转**（环状 + 八卦，转动才像法阵）。太极盘是独立件 `taiji`，
	# 不参与旋转 —— 对称图形必须始终直立（2026-10-28 拆件的原因）。
	_add_halo_spin(a, 1.0)


## 光环两层：外环**正转**、太极盘**反向慢转**（用户 2026-10-28 定：
## 「背后的太极图也要旋转，和外层反向旋转，不要太快」）。
##
## ⚠ 太极盘只能转**整数圈**：它黑白各半、不是旋转对称的，如果停在 0.42 圈这种
##   半圈位置，动画循环回 0 时会「啪」地跳一下（黑白对调），非常显眼。
##   所以这里对 turns 取整后再反向（`maxi(1, round(turns))`）。
func _add_halo_spin(a: Animation, turns: float) -> void:
	_add_spin_track(a, "halo", turns)
	_add_spin_track(a, "taiji", -float(maxi(1, int(round(turns)))))


## 给某个部件挂一条线性整圈旋转轨道（0 → TAU·turns）
func _add_spin_track(a: Animation, part: String, turns: float) -> void:
	if not _nodes.has(part):
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath("%s:rotation" % _node_path_of(part)))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	a.track_insert_key(idx, 0.0, 0.0)
	a.track_insert_key(idx, maxf(a.length, 0.1), TAU * turns)


func _add_sash(a: Animation, anim: String, back: float, hit: float) -> void:
	var windup := float(_skill_table()[anim]["windup"])
	var t_pull := _real_to_anim(anim, windup * 0.50)
	var t_swing := _real_to_anim(anim, windup * 0.85)
	_add_keys(a, "sash", "rotation", [
		[0.0, 0.0], [t_pull, back], [t_swing, hit], [a.length, 0.0],
	])


func _make_palm() -> Animation:
	var a := _skill_anim("palm")
	_strike(a, "palm", Vector2(-6.0, 2.0), Vector2(14.0, -2.0),
		-0.25, 0.30, -0.04, 0.05, Vector2(1.02, 0.97))
	_legs(a, "palm", 0.04, -0.05, -0.04, 0.06)
	_add_sash(a, "palm", 0.06, -0.04)
	_add_halo_spin(a, 0.5)
	return a


func _make_finger() -> Animation:
	var a := _skill_anim("finger")
	_strike(a, "finger", Vector2(-4.0, 3.0), Vector2(18.0, -3.0),
		-0.19, 0.41, -0.03, 0.04, Vector2(1.01, 0.98))
	_legs(a, "finger", 0.03, -0.06, -0.03, 0.05)
	_add_sash(a, "finger", 0.05, -0.03)
	_add_halo_spin(a, 0.4)
	return a


## 两仪转：躯干拧转半圈、广袖外展、太极环加速一圈
func _make_flip() -> Animation:
	var a := _skill_anim("flip")
	var b := _body_rest()
	var windup := float(_skill_table()["flip"]["windup"])
	var t_pull := _real_to_anim("flip", windup * 0.45)
	var t_swing := _real_to_anim("flip", windup * 0.80)
	var t_hold := _hit_time("flip") + _real_to_anim("flip", 0.06)
	_add_keys(a, "body", "rotation", [
		[0.0, 0.0], [t_pull, 0.42], [t_swing, -0.38], [t_hold, -0.38], [a.length, 0.0],
	])
	_add_keys(a, "body", "position", [
		[0.0, b], [t_pull, b + Vector2(-4.0, 2.0)], [t_swing, b + Vector2(6.0, -2.0)],
		[t_hold, b + Vector2(6.0, -2.0)], [a.length, b],
	])
	_add_keys(a, "arm", "rotation", [
		[0.0, 0.0], [t_pull, -0.50], [t_swing, 0.39], [t_hold, 0.39], [a.length, 0.0],
	])
	_add_keys(a, "leg_front", "rotation", [[0.0, 0.0], [t_swing, -0.08], [a.length, 0.0]])
	_add_keys(a, "leg_back", "rotation", [[0.0, 0.0], [t_swing, 0.08], [a.length, 0.0]])
	_add_sash(a, "flip", 0.16, -0.12)
	_add_halo_spin(a, 1.0)
	return a


## 太极崩：双手下压，躯干从拔高到砸落
func _make_collapse() -> Animation:
	var a := _skill_anim("collapse")
	_strike(a, "collapse", Vector2(-10.0, -14.0), Vector2(10.0, 16.0),
		-0.61, 0.39, -0.08, 0.10, Vector2(0.95, 1.06))
	_legs(a, "collapse", 0.06, -0.08, -0.06, 0.10)
	_add_sash(a, "collapse", 0.14, -0.10)
	_add_halo_spin(a, 1.5)
	return a


## 阳关三叠：前送 + 三次肩臂脉冲（游戏里三段突进各命中一次）
func _make_triple() -> Animation:
	var a := _skill_anim("triple")
	_strike(a, "triple", Vector2(-6.0, 2.0), Vector2(20.0, -2.0),
		-0.28, 0.33, -0.04, 0.05, Vector2(1.03, 0.96))
	_legs(a, "triple", 0.05, -0.07, -0.04, 0.08)
	_add_sash(a, "triple", 0.12, -0.08)
	_add_halo_spin(a, 0.6)
	return a


## 阴风蚀骨：广袖横扫，太极环反向转
func _make_wind() -> Animation:
	var a := _skill_anim("wind")
	_strike(a, "wind", Vector2(-8.0, 4.0), Vector2(10.0, -6.0),
		-0.50, 0.28, -0.06, 0.06, Vector2(1.02, 0.98))
	_legs(a, "wind", 0.04, -0.05, -0.04, 0.06)
	_add_sash(a, "wind", 0.10, -0.08)
	_add_halo_spin(a, -1.0)
	return a


## 阴阳双鱼：向前递掌，双鱼由游戏逻辑发射
func _make_fish() -> Animation:
	var a := _skill_anim("fish")
	_strike(a, "fish", Vector2(-4.0, 2.0), Vector2(12.0, -2.0),
		-0.22, 0.39, -0.03, 0.04, Vector2(1.01, 0.99))
	_legs(a, "fish", 0.03, -0.05, -0.03, 0.05)
	_add_sash(a, "fish", 0.08, -0.06)
	_add_halo_spin(a, 0.5)
	return a


## 两仪倒悬：架招（长定格）→ 末端爆发
func _make_counter() -> Animation:
	var a := _skill_anim("counter")
	_strike(a, "counter", Vector2(-10.0, 6.0), Vector2(8.0, -4.0),
		-0.55, 0.44, -0.07, 0.08, Vector2(0.98, 1.03), 0.25)
	_legs(a, "counter", 0.05, -0.06, -0.05, 0.08)
	_add_sash(a, "counter", 0.12, -0.08)
	_add_halo_spin(a, 0.3)
	return a
