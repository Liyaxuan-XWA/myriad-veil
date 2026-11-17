extends Node
## pixelfx 链路探针（2026-11-04）
## 用法：godot --headless --path . tools/probe_pixelfx.tscn -- --no-save
## 覆盖：目录表 → 烘焙产物加载 → 播放器帧推进/命中信号 → SkillFx 像素通道 → 未烘焙退化

var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _ready() -> void:
	_check(PixelFxLib.catalog().get("count", 0) == 244,
		"目录表 244 个特效", str(PixelFxLib.catalog().get("count", 0)))
	_check(PixelFxLib.effects().size() == 244, "effects 数组长度一致", str(PixelFxLib.effects().size()))
	_check(PixelFxLib.categories().size() == 21, "21 个分类", str(PixelFxLib.categories()))
	_check(PixelFxLib.palettes().size() == 27, "27 条内置色带", str(PixelFxLib.palettes().size()))
	var meta := PixelFxLib.effect_meta("ice/frost-nova")
	_check(not meta.is_empty() and String(meta.get("name", "")) == "Frost nova",
		"按 id 取 meta", str(meta.get("name", "")))
	_check(int(meta.get("options", {}).get("reach", -1)) == 104, "meta.options 里的数值旋钮带出来",
		str(meta.get("options", {}).get("reach", -1)))

	# ---------- 烘焙产物 ----------
	_check(PixelFxLib.is_baked("ice/frost-nova"), "frost-nova 已烘焙")
	_check(PixelFxLib.baked_variants("ice/frost-nova") == ["default"],
		"变体扫描", str(PixelFxLib.baked_variants("ice/frost-nova")))
	_check(not PixelFxLib.is_baked("ice/no-such-effect"), "未烘焙的 id 返回 false")
	var sheet := PixelFxLib.load_sheet(PixelFxLib.json_path("ice/frost-nova"))
	_check(not sheet.is_empty(), "表加载成功", String(sheet.get("path", "")))
	_check((sheet.get("frames", []) as Array).size() == 103, "103 帧",
		str((sheet.get("frames", []) as Array).size()))
	_check(absf(float(sheet.get("total_time", 0.0)) - 3.4) < 0.12, "总时长≈3.4s",
		str(sheet.get("total_time", 0.0)))
	_check(sheet.get("pivot", Vector2.ONE * -1) == Vector2(144, 150), "pivot 对齐",
		str(sheet.get("pivot", Vector2.ZERO)))
	_check(not bool(sheet.get("loop", true)), "一次性标记")
	_check((sheet.get("hits", []) as Array).size() == 3, "act.hits 命中时序带出来",
		str((sheet.get("hits", []) as Array).size()))
	var first: Texture2D = (sheet.get("frames", []) as Array)[0]
	_check(first is AtlasTexture and (first as AtlasTexture).region.size == Vector2(288, 192),
		"单帧尺寸", str((first as AtlasTexture).region.size))

	# ---------- 播放器 ----------
	var fx := PixelFxFx.spawn(self, Vector2(300, 300), "ice/frost-nova")
	_check(fx != null, "spawn 成功")
	var sprite := fx.get_node_or_null("Sheet") as Sprite2D
	_check(sprite != null and sprite.texture != null, "画布已挂上第一帧")
	_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "采样 = NEAREST（像素不糊）",
		str(sprite.texture_filter))
	_check(sprite.offset == Vector2(-144, -150), "offset = -pivot（节点原点即脚底）", str(sprite.offset))
	var tex0: Texture2D = sprite.texture
	var hits: Array = []
	fx.hit_fired.connect(func(h: Dictionary) -> void: hits.append(h))
	for i in 30:
		await get_tree().process_frame
	if sprite.texture != null and sprite.texture != tex0:
		_check(true, "帧在推进", "index=%d t=%.2fs" % [fx.current_index(), fx._elapsed])
	else:
		_check(false, "帧在推进", "纹理没变")
	# 特效自己是 30fps，引擎跑了 30 帧（约 0.6s）→ 应该到第 18 帧上下
	_check(fx.current_index() >= int(fx._elapsed * 30.0) - 1, "帧号跟时间一致",
		"index=%d t=%.2fs 期望≈%d" % [fx.current_index(), fx._elapsed, int(fx._elapsed * 30.0)])
	_check(hits.size() >= 1 and absf(float(hits[0].get("t", 0.0)) - 0.42) < 0.01,
		"0.42s 命中信号已发（可对齐出伤）", str(hits))
	_check(absf(fx.first_hit_time() - 0.42) < 0.001, "first_hit_time", str(fx.first_hit_time()))
	fx.fit_to_radius(144.0)
	_check(absf(fx.scale.x - 1.0) < 0.01, "fit_to_radius(半宽=半径)", str(fx.scale.x))
	fx.set_frame(7)
	_check(fx.current_index() == 7 and not fx.is_playing(), "时间轴定格")
	fx.queue_free()

	# 循环特效不该自动回收
	var loop_fx := PixelFxFx.spawn(self, Vector2(200, 200), "fire/campfire")
	_check(loop_fx != null and not loop_fx.auto_free, "循环特效默认不自动清")
	if loop_fx != null:
		loop_fx.queue_free()
	# 未烘焙 → spawn 返回 null（调用方退回原演出）
	_check(PixelFxFx.spawn(self, Vector2.ZERO, "ice/no-such-effect") == null, "未烘焙 spawn 返回 null")

	# ---------- SkillFx 像素通道 ----------
	var sfx := SkillFx.new()
	add_child(sfx)
	sfx._cfg = {"motif": "pixel", "pixelfx": "melee/sword-slash", "pixelfx_flip_by_dir": true}
	sfx._dir = Vector2.LEFT
	sfx.global_position = Vector2(400, 400)
	_check(sfx._try_pixelfx(), "通道：配了表就播像素")
	var spawned := _count_pixel_children()
	_check(spawned >= 1, "像素节点落在战场父节点上", str(spawned))
	var no_cfg := SkillFx.new()
	add_child(no_cfg)
	no_cfg._cfg = {"motif": "pixel"}
	_check(not no_cfg._try_pixelfx(), "通道：没写 pixelfx 键 → 不接管")
	var missing := SkillFx.new()
	add_child(missing)
	missing._cfg = {"motif": "pixel", "pixelfx": "ice/no-such-effect"}
	_check(not missing._try_pixelfx(), "通道：表没烘 → 退回默认演出（不出现空招）")
	sfx.queue_free()
	no_cfg.queue_free()
	missing.queue_free()

	# ---------- 项目内容树（BOSS → 招式） ----------
	var bosses := PixelFxLib.content_bosses()
	_check(bosses.size() >= 10, "内容树有 10+ 只 BOSS", str(bosses.size()))
	var skill_total := 0
	var named := 0
	var with_motif := 0
	for b in bosses:
		var bd: Dictionary = b
		if String(bd.get("boss_name", "")) != "":
			named += 1
		for sraw in (bd.get("skills", []) as Array):
			var sd: Dictionary = sraw
			skill_total += 1
			if String(sd.get("skill_id", "")) != "" and String(sd.get("skill_name", "")) != "":
				with_motif += 1
	_check(named == bosses.size(), "每只 BOSS 都有中文名", str(named))
	_check(skill_total >= 80 and with_motif == skill_total,
		"招式都有 id + 中文名", "%d 门 / 齐 %d" % [skill_total, with_motif])

	# ---------- 绑定表往返 ----------
	var bindings_path := PixelFxLib.BINDINGS_PATH
	var backup := ""
	if FileAccess.file_exists(bindings_path):
		backup = FileAccess.get_file_as_string(bindings_path)
	var probe_sid := "skill_probe_pixelfx"
	var slash := String((PixelFxLib.effect_meta("melee/sword-slash")).get("id", ""))
	_check(PixelFxLib.set_binding(probe_sid, {"pixelfx": slash, "pixelfx_variant": "default",
		"pixelfx_scale": 1.5}), "绑定表写入成功")
	PixelFxLib.invalidate()
	var back := PixelFxLib.binding_for(probe_sid)
	_check(String(back.get("pixelfx", "")) == slash and float(back.get("pixelfx_scale", 0.0)) == 1.5,
		"绑定表读回一致", str(back))
	# 关键：cfg 里完全没有 pixelfx 键，只靠绑定表也要接管
	var tfx := SkillFx.new()
	add_child(tfx)
	tfx._cfg = {"motif": "slash"}
	tfx._skill_id = probe_sid
	tfx.global_position = Vector2(100, 100)
	_check(tfx._try_pixelfx(), "绑定表优先于 cfg（cfg 没写也能接管）")
	# 解绑后必须退回原演出
	PixelFxLib.set_binding(probe_sid, {})
	PixelFxLib.invalidate()
	var ufx := SkillFx.new()
	add_child(ufx)
	ufx._cfg = {"motif": "slash"}
	ufx._skill_id = probe_sid
	ufx.global_position = Vector2(120, 120)
	_check(not ufx._try_pixelfx(), "解绑后退回默认演出")
	tfx.queue_free()
	ufx.queue_free()
	# 还原探针自己的绑定文件（不能把测试数据留在项目里）
	var bf := FileAccess.open(bindings_path, FileAccess.WRITE)
	bf.store_string(backup if backup != "" else "{}\n")
	bf.close()
	PixelFxLib.invalidate()
	_check(PixelFxLib.binding_for(probe_sid).is_empty(), "探针绑定已清理")

	# ---------- 中文名表（244 条全覆盖） ----------
	var cn_missing: Array[String] = []
	var cn_desc_missing: Array[String] = []
	var latin_names: Array[String] = []
	for raw in PixelFxLib.effects():
		var e: Dictionary = raw
		var id := String(e.get("id", ""))
		var cn := PixelFxLib.effect_cn(id)
		var nm := String(cn.get("name", ""))
		if nm == "":
			cn_missing.append(id)
			continue
		if String(cn.get("desc", "")) == "":
			cn_desc_missing.append(id)
		for ch in nm:
			if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
				latin_names.append("%s=%s" % [id, nm])
				break
	_check(cn_missing.is_empty(), "244 个特效全部有中文名", str(cn_missing.slice(0, 8)))
	_check(cn_desc_missing.is_empty(), "每条都配了中文形态描述", str(cn_desc_missing.slice(0, 8)))
	_check(latin_names.is_empty(), "中文名里没有残留英文单词", str(latin_names.slice(0, 8)))
	var nova_cn := PixelFxLib.effect_cn("ice/frost-nova")
	_check(String(nova_cn.get("name", "")) == "冰晶环爆", "冰环叫「冰晶环爆」", str(nova_cn.get("name", "")))
	_check(PixelFxLib.effect_cn("no/such-effect").is_empty(), "没登记的 id 返回空（面板回退原名）")

	# ---------- 预览烘焙：能在引擎里看，但不进项目素材 ----------
	var pv_id := "water/fountain"
	var pdir := PixelFxLib.preview_dir()
	_check(not pdir.contains("assets/fx/pixelfx") and pdir != "",
		"预览区在项目 assets 之外", pdir)
	_check(not PixelFxLib.is_baked(pv_id), "预览用的特效本来没导入")
	var job_file := "user://pixelfx/probe_preview_job.json"
	DirAccess.make_dir_recursive_absolute("user://pixelfx")
	var jf := FileAccess.open(job_file, FileAccess.WRITE)
	jf.store_string(JSON.stringify([{"id": pv_id, "variant": "default"}]))
	jf.close()
	var plines: Array[String] = []
	var pcode := OS.execute("node", PackedStringArray([
		ProjectSettings.globalize_path("res://tools/pixelfx/bake.mjs"),
		"--jobs", ProjectSettings.globalize_path(job_file),
		"--lib", "E:/skill/game/pixelfx",
		"--out", pdir,
	]), plines, 90000.0)
	var pok := ""
	for l in plines:
		if String(l).begins_with("BAKE_OK"):
			pok = String(l)
	_check(pcode == 0 and pok != "", "预览烘焙成功", pok)
	var pok_path := pok.split(" ")[3] if pok.split(" ").size() > 3 else ""
	_check(not pok_path.begins_with("res://"), "回执报的是绝对路径而不是 res://", pok_path)
	_check(PixelFxLib.is_preview_baked(pv_id), "预览表已落在 user:// 区")
	_check(not PixelFxLib.is_baked(pv_id), "预览烘焙没有污染 assets/（仍未导入）")
	PixelFxLib.invalidate()
	var psheet := PixelFxLib.sheet_any_for(pv_id, "default")
	_check(not psheet.is_empty() and (psheet.get("frames", []) as Array).size() > 0,
		"预览表能被裸读加载（不经导入流程）",
		"%d 帧" % (psheet.get("frames", []) as Array).size())
	_check(psheet.get("texture", null) is Texture2D, "预览贴图有效")
	_check(float(psheet.get("total_time", 0.0)) > 0.0, "预览时长算得出来",
		str(psheet.get("total_time", 0.0)))
	# 关键：游戏侧（PixelFxFx / 绑定 / 挂场景）读不到预览版 —— 这是设计，不是 bug
	_check(PixelFxFx.spawn(self, Vector2(60, 60), pv_id) == null,
		"只有预览版时游戏内 spawn 返回 null（必须导入才能用）")
	var cleared := PixelFxLib.clear_preview()
	_check(cleared >= 2 and not PixelFxLib.is_preview_baked(pv_id),
		"清空预览缓存生效，正式素材不受影响", "删了 %d 个文件" % cleared)
	_check(PixelFxLib.is_baked("ice/frost-nova"), "清空预览后已导入的特效仍在")

	print("RESULT passes=", _passes, " fails=", _fails.size())
	for f in _fails:
		print("  FAILED -> ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _count_pixel_children() -> int:
	var n := 0
	for c in get_children():
		if c is PixelFxFx and not c.is_queued_for_deletion():
			n += 1
	return n
