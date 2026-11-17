extends Node
## 全部卡包卡面一览（2026-11-02）
##
## 目的：把**每一位守关者的每一张卡**都解锁并单独截一张，供用户逐张检查卡面效果。
## 解锁口径照 `CodexDB.card_entry()`：塔层要「通关 ≥ 11 次 + 双倍血场次无伤 +
## 纪录 ≤ 10 秒」三档齐，大陆核心首领走 `core_replay` 同一套。
## 只截当前显示的那张大卡（取最大可见 CardFace 的全局矩形裁切），
## 所以每张都是原生尺寸，能直接看清算线与细节。
##
## 用法：godot --path . --resolution 1280x720 res://tools/shot_all_cards.tscn -- --no-save

const OUT_DIR := "output/cards"


func _unlock_all() -> void:
	for raw in WorldDB.get_floors():
		var f := raw as Dictionary
		var fl := int(f.get("floor", 0))
		if fl <= 0:
			continue
		CharacterData.tower_progress[fl] = {
			"unlocked": true, "first_kill": true, "clear_count": 12,
		}
		CharacterData.tower_best_time[fl] = 6.0
		CharacterData.tower_no_hit_double[fl] = true
	for raw in SecretWorldDB.REGIONS:
		var r := raw as Dictionary
		## ⚠ 区域表用的键是 `region_id`，不是 `id` —— 读错字段会让四位大陆核心
		##   首领一张卡都解锁不了（`ordered_variants` 只返回已解锁的）。
		var region := String(r.get("region_id", ""))
		if region == "" or String(r.get("core_boss_id", "")) == "":
			continue
		CharacterData.secret_world["core_kills"][region] = true
		CharacterData.core_replay[region] = {
			"clear_count": 12, "best_time": 6.0,
			"no_hit_double": true, "no_hit_rewarded": true,
		}
	# 位面 BOSS 的「已击败」口径还看位面进度，一并填满
	for d in WorldDB.DOMAINS:
		var dom := d as Dictionary
		var did := String(dom.get("id", ""))
		var cleared: Array = []
		for b in dom.get("boss_ids", []):
			cleared.append(String(b))
		CharacterData.domain_progress[did] = {"unlocked": true, "cleared_bosses": cleared}


func _freeze(view: AchievementView) -> void:
	for n in view.find_children("*", "HoloCardView", true, false):
		(n as HoloCardView).set_view_speed_immediate(Vector2.ZERO)
	for n in view.find_children("*", "CardFace", true, false):
		var face := n as CardFace
		if face != null and face.is_paper():
			face.set_paper_reveal_immediate(1.0)


## 当前显示的大卡。
## ⚠ 单张模式下大卡有**两种**节点：华彩卡直挂 `HoloCardView`（名叫 HoloSingle），
##   普通卡 / 水墨卡才是 `CardFace`（CardSingle）。只找 CardFace 的话，
##   11 位守关者的 scene / plain 两张会全部截空 —— 实测就是这样。
func _big_face(view: AchievementView) -> Control:
	for n in view.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null:
			continue
		var nm := String(c.name)
		if (nm == "CardSingle" or nm == "HoloSingle") and c.visible:
			return c
	var best: Control = null
	var best_area := 0.0
	for n in view.find_children("*", "CardFace", true, false):
		var c := n as Control
		if c == null or not c.visible:
			continue
		var area := c.size.x * c.size.y
		if area > best_area:
			best_area = area
			best = c
	return best


func _grab(view: AchievementView, path: String) -> bool:
	var face := _big_face(view)
	if face == null:
		return false
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	var gr := Rect2(Vector2.ZERO, Vector2.ZERO)
	var xform := vp.get_canvas_transform()
	var r := face.get_global_rect()
	var p0 := xform * r.position
	var p1 := xform * (r.position + r.size)
	var sc := Vector2(img.get_width(), img.get_height()) \
			/ Vector2(vp.get_visible_rect().size.x, vp.get_visible_rect().size.y)
	gr = Rect2(p0 * sc, (p1 - p0) * sc)
	var sub := img.get_region(Rect2i(int(gr.position.x), int(gr.position.y),
			maxi(1, int(gr.size.x)), maxi(1, int(gr.size.y))))
	var err := sub.save_png(path)
	print("CARD %s  %.0fx%.0f err=%d" % [path, gr.size.x, gr.size.y, err])
	return err == OK


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://" + OUT_DIR)
	_unlock_all()
	var panel := AchievementPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array = []
	for key in CodexDB.HOLO_CARDS.keys():
		ids.append(String(key))
	ids.sort()
	var missing := 0
	for bid in ids:
		panel._view.open_boss(bid)
		await get_tree().create_timer(0.55).timeout
		var entry := CodexDB.card_entry(bid)
		var variants: Array = CodexDB.ordered_variants(entry)
		for i in variants.size():
			## ⚠ 每次都要重新取 view：换卡时面板会重建视图，缓存下来的引用
			##   会变成「previously freed」，直接传进 _freeze 就报 Invalid type。
			var view: AchievementView = panel._view
			if view == null or not is_instance_valid(view):
				await get_tree().process_frame
				view = panel._view
			if view == null or not is_instance_valid(view):
				missing += 1
				break
			view.open_card(i)
			await get_tree().create_timer(0.7).timeout
			_freeze(view)
			await get_tree().create_timer(0.15).timeout
			var label := String((variants[i] as Dictionary).get("id", "c%d" % i))
			var ok := await _grab(view, "res://%s/%s_%02d_%s.png" % [OUT_DIR, bid, i, label])
			if not ok:
				missing += 1
				print("  ! 没截到 %s 第 %d 张（%s）" % [bid, i, label])
	print("完成：%d 位守关者，缺图 %d 张" % [ids.size(), missing])
	get_tree().quit(0)
