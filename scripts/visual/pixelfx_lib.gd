@tool
class_name PixelFxLib
extends RefCounted
## pixelfx 素材的读取层（2026-11-04）。
##
## 只管三件事：读 catalog.json（244 个特效的 meta）、找已烘焙的变体、
## 把 Aseprite 格式的序列表拆成可以直接贴到 Sprite2D 上的 AtlasTexture 帧。
## 播放逻辑在 PixelFxFx，编辑器面板也走这里，保证口径一致。

const CATALOG_PATH := "res://assets/fx/pixelfx/catalog.json"
const ASSET_ROOT := "res://assets/fx/pixelfx"
## 像素绑定表：招式 id → 一组 pixelfx_* 参数。
## 面板直接改这个 JSON，不碰 art_db.gd 的源码（改坏一处会让整个数据表编译失败）。
const BINDINGS_PATH := "res://assets/fx/pixelfx/bindings.json"
## 项目内容树（BOSS → 招式 → 当前 motif / 五行），由 tools/dump_content_map.tscn 导出。
## 面板是编辑器脚本，不能直接调 SkillDB / MoveDB / ArtDB，所以走这张表。
const CONTENT_MAP_PATH := "res://assets/fx/pixelfx/content_map.json"
## 244 个特效的中文名与形态描述（人工按库里每条 desc 逐条写，不随 dump_meta 重新生成）
const CN_MAP_PATH := "res://assets/fx/pixelfx/effects_cn_map.json"
## 预览烘焙区：在 user:// 里，**不属于项目素材** —— 不会被 Godot 导入、
## 不会进 git、不会被打进导出包，面板却能照常播（用 Image 裸读文件）。
const PREVIEW_DIR := "user://pixelfx_preview"

static var _catalog: Dictionary = {}
static var _catalog_loaded := false
static var _content: Dictionary = {}
static var _content_loaded := false
static var _cn: Dictionary = {}
static var _cn_loaded := false
static var _bindings: Dictionary = {}
static var _bindings_loaded := false
static var _sheets: Dictionary = {}
static var _atlas_cache: Dictionary = {}


## 特效的中文名与中文形态描述；没登记返回空字典（调用方回退英文原名）
static func effect_cn(id: String) -> Dictionary:
	if not _cn_loaded:
		_cn_loaded = true
		if FileAccess.file_exists(CN_MAP_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(CN_MAP_PATH))
			if parsed is Dictionary:
				_cn = parsed
	var v = _cn.get(id, null)
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


static func has_cn_name(id: String) -> bool:
	return not effect_cn(id).is_empty()


## 内容树：[{boss_id, boss_name, group_name, skills:[{skill_id, skill_name, motif,
## damage_element, form_name, desc, passive}]}]；没导出过返回空数组
static func content_bosses() -> Array:
	if not _content_loaded:
		_content_loaded = true
		_content = {}
		if FileAccess.file_exists(CONTENT_MAP_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_MAP_PATH))
			if parsed is Dictionary:
				_content = parsed
	var arr = _content.get("bosses", [])
	return arr if arr is Array else []


## 某招法的像素绑定（没绑返回空字典）。键名与 SKILL_FX 条目一致，可直接当 cfg 用。
static func binding_for(skill_id: String) -> Dictionary:
	if skill_id == "" or not _bindings_loaded:
		_load_bindings()
	var v = _bindings.get(skill_id, null)
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


static func bindings() -> Dictionary:
	if not _bindings_loaded:
		_load_bindings()
	return _bindings


static func _load_bindings() -> void:
	_bindings_loaded = true
	_bindings = {}
	if not FileAccess.file_exists(BINDINGS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS_PATH))
	if parsed is Dictionary:
		_bindings = parsed


## 写绑定表（编辑器面板用）。空 opts = 解绑。
static func set_binding(skill_id: String, opts: Dictionary) -> bool:
	if skill_id == "":
		return false
	_load_bindings()
	if opts.is_empty():
		_bindings.erase(skill_id)
	else:
		_bindings[skill_id] = opts
	var f := FileAccess.open(BINDINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PixelFxLib: 绑定表写不进去 %s" % BINDINGS_PATH)
		return false
	var keys: Array = _bindings.keys()
	keys.sort()
	var ordered := "{"
	for i in keys.size():
		var k := String(keys[i])
		var v: Dictionary = _bindings[k]
		ordered += "\n\t\"%s\": %s" % [k, JSON.stringify(v)]
		if i < keys.size() - 1:
			ordered += ","
	ordered += "\n}\n"
	f.store_string(ordered)
	f.close()
	return true


## 目录表丢了/没跑 dump_meta 时返回空表，调用方要能安全退化
static func catalog() -> Dictionary:
	if _catalog_loaded:
		return _catalog
	_catalog_loaded = true
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("PixelFxLib: 缺 catalog.json，先跑 node tools/pixelfx/dump_meta.mjs")
		return _catalog
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary:
		_catalog = parsed
	return _catalog


static func effects() -> Array:
	var out = catalog().get("effects", [])
	return out if out is Array else []


static func categories() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for raw in effects():
		var e: Dictionary = raw
		var c := String(e.get("category", ""))
		if c != "" and not seen.has(c):
			seen[c] = true
			out.append(c)
	out.sort()
	return out


static func palettes() -> Dictionary:
	var p = catalog().get("palettes", {})
	return p if p is Dictionary else {}


static func effect_meta(id: String) -> Dictionary:
	for raw in effects():
		var e: Dictionary = raw
		if String(e.get("id", "")) == id:
			return e
	return {}


## 特效 id → 短名（文件名用），例：ice/frost-nova → frost-nova
static func short_name(id: String) -> String:
	var parts := id.split("/")
	return parts[parts.size() - 1] if parts.size() > 1 else id


static func category_of(id: String) -> String:
	var parts := id.split("/")
	return parts[0] if parts.size() > 1 else ""


static func json_path(id: String, variant: String = "default") -> String:
	return "%s/%s/%s__%s.json" % [ASSET_ROOT, category_of(id), short_name(id), variant]


static func png_path(id: String, variant: String = "default") -> String:
	return "%s/%s/%s__%s.png" % [ASSET_ROOT, category_of(id), short_name(id), variant]


static func is_baked(id: String, variant: String = "default") -> bool:
	return FileAccess.file_exists(json_path(id, variant))


## ---------- 预览烘焙（只给用户看，不进游戏素材） ----------
static func preview_json_path(id: String, variant: String) -> String:
	return "%s/%s/%s__%s.json" % [preview_dir(), category_of(id), short_name(id), variant]


static func is_preview_baked(id: String, variant: String = "default") -> bool:
	return FileAccess.file_exists(preview_json_path(id, variant))


## user:// 展开成绝对路径，好把 --out 直接交给 node 脚本
static func preview_dir() -> String:
	DirAccess.make_dir_recursive_absolute(PREVIEW_DIR)
	return ProjectSettings.globalize_path(PREVIEW_DIR)


## 面板取表用的优先级：先看这次选的变体是否已导入，再退到预览区
static func sheet_any_for(id: String, variant: String) -> Dictionary:
	if is_baked(id, variant):
		return sheet_for(id, variant)
	var pv := preview_json_path(id, variant)
	if FileAccess.file_exists(pv):
		return load_sheet(pv)
	return sheet_for(id, variant)


## 清空预览区（不碰 res:// 里的正式素材）
static func clear_preview() -> int:
	var abs_dir := ProjectSettings.globalize_path(PREVIEW_DIR)
	var d := DirAccess.open(abs_dir)
	if d == null:
		return 0
	var n := 0
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := abs_dir + "/" + name
		if d.current_is_dir():
			var sub := DirAccess.open(p)
			if sub != null:
				sub.list_dir_begin()
				var f := sub.get_next()
				while f != "":
					if not f.begins_with("."):
						sub.remove(f)
						n += 1
					f = sub.get_next()
				sub.list_dir_end()
			d.remove(name)
		elif not name.begins_with("."):
			d.remove(name)
			n += 1
		name = d.get_next()
	d.list_dir_end()
	invalidate()
	return n


## 扫某个特效已经烘出来的变体名（编辑器列表用；导出包里也能扫 PCK）
static func baked_variants(id: String) -> Array[String]:
	var out: Array[String] = []
	var dir := "%s/%s" % [ASSET_ROOT, category_of(id)]
	var prefix := short_name(id) + "__"
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var name := String(f)
		if not name.ends_with(".json"):
			continue
		var stem := name.trim_suffix(".json")
		if stem.begins_with(prefix):
			out.append(stem.trim_prefix(prefix))
	out.sort()
	return out


static func any_baked_variant(id: String) -> String:
	var list := baked_variants(id)
	if list.is_empty():
		return ""
	if list.has("default"):
		return "default"
	return String(list[0])


## 清缓存：编辑器刚烘焙完 / 刚改绑定必须调，否则拿到的还是旧表
static func invalidate() -> void:
	_sheets.clear()
	_atlas_cache.clear()
	_bindings_loaded = false
	_bindings = {}
	_content_loaded = false
	_content = {}
	_cn_loaded = false
	_cn = {}


## 读一张序列表 → {frames, durations, fps, loop, pivot, frame_size, columns, hits, texture, path}
static func load_sheet(sheet_json_path: String) -> Dictionary:
	if _sheets.has(sheet_json_path):
		return _sheets[sheet_json_path]
	var empty := {}
	if not FileAccess.file_exists(sheet_json_path):
		return empty
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sheet_json_path))
	if not (parsed is Dictionary):
		push_warning("PixelFxLib: 表头解析失败 %s" % sheet_json_path)
		return empty
	var doc: Dictionary = parsed
	var meta_all: Dictionary = doc.get("meta", {})
	var px: Dictionary = meta_all.get("pixelfx", {})
	var image_name := String(meta_all.get("image", ""))
	var dir_path := sheet_json_path.get_base_dir()
	var tex: Texture2D = null
	if image_name != "":
		var img_path := dir_path.path_join(image_name)
		if img_path.begins_with("res://") or img_path.begins_with("user://"):
			# 项目内素材：走导入后的资源（有压缩与缓存）
			if ResourceLoader.exists(img_path):
				tex = load(img_path) as Texture2D
			else:
				push_warning("PixelFxLib: 缺贴图 %s（跑一次 --import）" % img_path)
		elif FileAccess.file_exists(img_path):
			# 预览区：绝对路径裸读，不经导入流程，所以不会污染项目素材
			var img := Image.load_from_file(img_path)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		return empty
	# 过滤方式不在贴图上下手（CompressedTexture2D.filter 只读），
	# 由 PixelFxFx 的 Sprite2D.texture_filter = NEAREST 保证像素不糊
	var frames: Array = []
	var durations: Array = []
	for raw in doc.get("frames", []):
		var fr: Dictionary = raw
		var box: Dictionary = fr.get("frame", {})
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(float(box.get("x", 0.0)), float(box.get("y", 0.0)),
			float(box.get("w", 1.0)), float(box.get("h", 1.0)))
		frames.append(at)
		durations.append(maxf(1.0, float(fr.get("duration", 33.0))))
	var sheet := {
		"frames": frames,
		"durations": durations,
		"fps": float(px.get("fps", 30)),
		"loop": bool(px.get("loop", false)),
		"pivot": Vector2(float(px.get("pivot", [0, 0])[0]), float(px.get("pivot", [0, 0])[1])),
		"frame_size": Vector2(float(px.get("frameSize", [0, 0])[0]), float(px.get("frameSize", [0, 0])[1])),
		"columns": int(px.get("columns", 1)),
		"effect_id": String(px.get("id", "")),
		"variant": String(px.get("variant", "default")),
		"options": px.get("options", {}),
		"hits": _hits_of(px),
		"texture": tex,
		"path": sheet_json_path,
		"total_time": 0.0,
	}
	var total := 0.0
	for d in durations:
		total += float(d) / 1000.0
	sheet["total_time"] = total
	_sheets[sheet_json_path] = sheet
	return sheet


static func sheet_for(id: String, variant: String = "default") -> Dictionary:
	var v := variant
	if v == "" or not is_baked(id, v):
		v = any_baked_variant(id)
	if v == "":
		return {}
	return load_sheet(json_path(id, v))


## act.hits 的 t 是「特效自己的时间轴」，直接给运行时对齐出伤用
static func _hits_of(px: Dictionary) -> Array:
	var out: Array = []
	var act = px.get("act", {})
	if not (act is Dictionary):
		return out
	for raw in (act as Dictionary).get("hits", []):
		if not (raw is Dictionary):
			continue
		var h: Dictionary = raw
		out.append({
			"t": float(h.get("t", 0.0)),
			"stop": float(h.get("stop", h.get("freeze", 0.0))),
			"shake": float(h.get("shake", 0.0)),
			"amp": float(h.get("amp", 0.0)),
			"push": float(h.get("push", 0.0)),
			"skin": h.get("skin", null),
		})
	return out


## 面板/探针用：把 RGBA8 的 hex 色带列表转成 Godot Color 数组
static func palette_colors(list: Array) -> Array[Color]:
	var out: Array[Color] = []
	for raw in list:
		var s := String(raw)
		if s == "":
			continue
		var c := Color.from_string(s if s.begins_with("#") else "#" + s, Color.WHITE)
		out.append(c)
	return out
