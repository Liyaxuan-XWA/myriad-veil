extends Node
## 练气区美术接入自检（2026-10-28）：
##   三张立绘 / 投射物 / 首领卡 → ArtDB 配置 → 世界实体体型与 HUD → 招式 FX → 图鉴数据
## 用法：godot --headless --path . res://tools/probe_lianqi_art.tscn

var _fails: Array = []
var _passes := 0

func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _fx_nodes(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Node2D", true, false):
		if n is SkillFx:
			out.append(n)
	return out


func _clear_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()


func _ready() -> void:
	print("\n########## 练气区美术探针 ##########")
	await get_tree().process_frame

	# ---------- 1. 资源与 ArtDB ----------
	for p in ["res://assets/characters/world/beast_fengya.png",
			"res://assets/characters/world/beast_jianjia.png",
			"res://assets/characters/world/ape_qinglan.png",
			"res://assets/effects/skills/ape_boulder.png",
			"res://assets/effects/skills/ape_orb.png",
			"res://assets/effects/skills/ape_crack.png",
			"res://assets/ui/codex/card_boss_core_ape.png"]:
		_check(ResourceLoader.exists(p), "资源存在 " + p.get_file())
	var card := load("res://assets/ui/codex/card_boss_core_ape.png") as Texture2D
	_check(card != null and card.get_width() == 640 and card.get_height() == 960,
		"首领卡 640×960", "%dx%d" % [card.get_width(), card.get_height()] if card != null else "null")

	for pair in [["world_beast_fengya", 54.0], ["world_beast_jianjia", 58.0],
			["world_core_lianqi", 126.0]]:
		var vid := String(pair[0])
		var cfg := ArtDB.get_visual(vid)
		var tex := String(cfg.get("texture", ""))
		_check(tex != "" and ResourceLoader.exists(tex), "ArtDB 贴图 " + vid, tex)
		_check(is_equal_approx(float(cfg.get("target_length", 0.0)), float(pair[1])),
			"ArtDB 显示高度 " + vid, str(cfg.get("target_length", 0.0)))
		_check(bool(cfg.get("anchor_bottom", false)) and bool(cfg.get("flip_driven", false)),
			"ArtDB 底面锚定/翻转 " + vid)

	for entry in [["skill_beast_bite", "claw"], ["skill_beast_charge", "slash"],
			["skill_ape_swipe", "slash"], ["skill_ape_slam", "stomp"],
			["skill_ape_boulder", "volley"], ["skill_ape_volley", "volley"],
			["skill_ape_quake", "stomp"], ["skill_ape_orb", "orb"]]:
		var fx := ArtDB.get_skill_fx(String(entry[0]))
		_check(not fx.is_empty() and String(fx.get("motif", "")) == String(entry[1]),
			"SKILL_FX " + String(entry[0]), String(fx.get("motif", "")))
	for pair in [["skill_ape_boulder", "ape_boulder"], ["skill_ape_volley", "ape_boulder"],
			["skill_ape_orb", "ape_orb"]]:
		var fx2 := ArtDB.get_skill_fx(String(pair[0]))
		_check(String(fx2.get("projectile_visual", "")) == String(pair[1]),
			"投掷物外观 " + String(pair[0]), String(fx2.get("projectile_visual", "")))
	for sid in ["skill_ape_slam", "skill_ape_quake"]:
		var fx3 := ArtDB.get_skill_fx(sid)
		_check(String(fx3.get("crack_texture", "")) == "ape_crack",
			"裂纹贴图 " + sid, String(fx3.get("crack_texture", "")))

	# ---------- 2. 图鉴数据 ----------
	_check(WorldDB.get_boss_name("world_core_lianqi") == "青岚古猿", "图鉴名 = 青岚古猿")
	var entries := CodexDB.boss_entries()
	var has_core := false
	for e in entries:
		if String((e as Dictionary).get("id", "")) == "world_core_lianqi":
			has_core = true
	_check(has_core, "BOSS 图鉴收录青岚古猿", "n=%d" % entries.size())
	var card_entry := CodexDB.boss_entry("world_core_lianqi")
	_check(String(card_entry.get("portrait", "")) ==
		"res://assets/ui/codex/card_boss_core_ape.png", "图鉴卡面路径")
	_check(bool(card_entry.get("world_boss", false)), "标记为大世界首领")
	_check(String(card_entry.get("subtitle", "")).contains("青岚野"), "副标题含青岚野",
		String(card_entry.get("subtitle", "")))

	var st := CodexDB.boss_stats("world_core_lianqi")
	_check(int(st.get("hp", 0)) == 2200, "图鉴气血 2200", str(st.get("hp", 0)))
	_check(int(st.get("speed_p1", 0)) == 96 and int(st.get("speed_p2", 0)) == 125,
		"图鉴移速 96/125", "%s/%s" % [st.get("speed_p1"), st.get("speed_p2")])
	_check(is_equal_approx(float(st.get("windup", 0.0)), 0.85), "图鉴前摇 0.85",
		str(st.get("windup")))
	_check(String(st.get("attack_text", "")) == "攻击力 50", "图鉴攻击力文案",
		String(st.get("attack_text", "")))
	_check(int(st.get("radius", 0)) == 44, "图鉴受击半径 44", str(st.get("radius")))

	var moves := CodexDB.boss_moves_info("world_core_lianqi")
	_check(moves.size() == 5, "图鉴招式 5 个", "n=%d" % moves.size())
	var names: Array = []
	for m in moves:
		names.append(String((m as Dictionary).get("name", "")))
	_check("裂地重锤" in names and "青岚灵爆" in names, "招式名齐全", str(names))

	var drops := CodexDB.boss_drops_info("world_core_lianqi")
	_check(drops.size() == 2, "图鉴掉落 2 条", "n=%d" % drops.size())
	var all_guaranteed := true
	for d in drops:
		if not is_equal_approx(float((d as Dictionary).get("chance", 0.0)), 1.0):
			all_guaranteed = false
	_check(all_guaranteed, "图鉴掉落均为 100%")
	_check(CodexDB.boss_learn_info("world_core_lianqi").is_empty(), "大世界首领无塔层功法")

	var old_kills = CharacterData.secret_world.get("core_kills", {}).duplicate()
	CharacterData.secret_world["core_kills"] = {}
	_check(not CodexDB.is_boss_unlocked("world_core_lianqi"), "未击杀时图鉴未解锁")
	CharacterData.secret_world["core_kills"]["world_lianqi"] = true
	_check(CodexDB.is_boss_unlocked("world_core_lianqi"), "击杀后图鉴解锁")
	CharacterData.secret_world["core_kills"] = old_kills

	# ---------- 3. 世界实体 ----------
	SecretWorldDB.pending_spawn_region = ""
	var w = (load("res://scenes/world/secret_world.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame

	var core: WorldEnemy = w._enemies.get("lianqi_core_boss")
	if core == null:
		core = w._core
	_check(core != null, "青岚古猿已生成")
	if core != null:
		_check(core.skin.using_texture and core.skin.visual_id == "world_core_lianqi",
			"古猿走真实立绘", core.skin.visual_id)
		var vh := core.skin.visual_rect.size.y
		_check(vh > 120.0 and vh < 135.0, "古猿显示高度 ≈126", "%.1f" % vh)
		_check(core.head_top_y() < -110.0, "古猿头顶基准正确", "%.1f" % core.head_top_y())
		var spheres: Array = core.hit_spheres()
		_check(spheres.size() == 1 and is_equal_approx(float((spheres[0] as Vector3).z), 44.0),
			"古猿受击半径 44", str(spheres))
		_check(core._melee_fx == "skill_ape_swipe", "古猿近战专属 FX", core._melee_fx)
		var bg := core.get_node_or_null("HPBarBG") as Control
		_check(bg != null and is_equal_approx(bg.size.x, 96.0), "古猿血条加宽到 96",
			str(bg.size) if bg != null else "null")
		_check(core._name_label != null and is_equal_approx(core._name_label.size.x, 220.0),
			"古猿名牌加宽到 220")
		_check(core._name_label != null and core._name_label.position.y < -130.0,
			"古猿名牌在头顶", str(core._name_label.position) if core._name_label != null else "null")

	var beast: WorldEnemy = w._enemies.get("lq_beast_feng_1")
	var tank: WorldEnemy = w._enemies.get("lq_beast_jian_1")
	_check(beast != null and beast.skin.using_texture, "锋牙兽走真实立绘")
	_check(tank != null and tank.skin.using_texture, "坚甲兽走真实立绘")
	if beast != null:
		_check(beast._melee_fx == "skill_beast_bite", "锋牙兽扑咬 FX", beast._melee_fx)
		_check(is_equal_approx(float(beast.hit_spheres()[0].z), 28.0), "锋牙兽受击半径 28")
		_check(beast._name_label != null and beast._name_label.position.y < -60.0,
			"灵兽名牌在头顶", str(beast._name_label.position) if beast._name_label != null else "null")
	if tank != null:
		_check(tank._melee_fx == "skill_beast_charge", "坚甲兽撞击 FX", tank._melee_fx)
		_check(is_equal_approx(float(tank.hit_spheres()[0].z), 32.0), "坚甲兽受击半径 32")

	# ---------- 4. 招式 FX：近战 / 砸地 / 投射物 ----------
	# 把玩家挪远，避免自检时把玩家打死
	w.player.global_position = (core.global_position if core != null else Vector2.ZERO) + Vector2(2400.0, 0.0)
	await get_tree().process_frame

	if beast != null:
		var before := _fx_nodes(w).size()
		beast._do_melee()
		await get_tree().process_frame
		var made := _fx_nodes(w).size() - before
		_check(made >= 1, "锋牙兽扑咬真的出 FX", "n=%d" % made)
		_clear_nodes(_fx_nodes(w))
		await get_tree().process_frame

	if core != null:
		for raw in SecretWorldDB.CORE_SKILLS:
			var def: Dictionary = raw
			var form := MoveDB.resolve_boss(String(def.get("form_id", "")))
			var before2 := _fx_nodes(w).size()
			core._play_form(form, 1.0, String(def.get("attack_kind", "")),
				String(def.get("damage_element", "")),
				float(def.get("range", -1.0)), float(def.get("angle", -1.0)),
				String(def.get("fx_id", "")))
			await get_tree().process_frame
			var made2 := _fx_nodes(w).size() - before2
			_check(made2 >= 1, "古猿出招 FX " + String(def.get("name", "")), "n=%d" % made2)
			_clear_nodes(_fx_nodes(w))
			await get_tree().process_frame
			var projs: Array = []
			for n in w.find_children("*", "Area2D", true, false):
				if n.has_method("set_visual_override"):
					projs.append(n)
			# 投射物招式顺带核对外观覆盖
			if String(def.get("fx_id", "")) != "" and String(form.get("hit_shape", "")) == \
					MoveDB.SHAPE_PROJECTILE:
				var fid := String(ArtDB.get_skill_fx(String(def.get("fx_id", ""))).get("projectile_visual", ""))
				var ok_vis := not projs.is_empty()
				for p in projs:
					var v: SkinVisual = p.get_node_or_null("Visual/Skin") as SkinVisual
					if v == null or v.visual_id != fid:
						ok_vis = false
				_check(ok_vis, "古猿投掷物外观 " + fid, "n=%d" % projs.size())
			_clear_nodes(projs)

	w.queue_free()
	await get_tree().process_frame

	print("\n########## 结果：%d 项通过，%d 项失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  x ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
