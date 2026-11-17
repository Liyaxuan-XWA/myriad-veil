@tool
class_name PixelFxFx
extends Node2D
## pixelfx 序列表的运行时播放器（2026-11-04）。
##
## 一张烘焙表 = 一个 Sprite2D 换 AtlasTexture 帧，按表里的 duration 走。
## pivot 来自 meta.pixelfx.pivot（就是特效自己的原点/脚底），所以本节点的
## global_position 直接摆「命中点/施法者脚下」即可，不用再手调偏移。
##
## 表里没有的东西一律不改：帧序、时长、循环都由烘焙产物决定，
## 换色/换 seed 属于重新烘焙的范畴（见 tools/pixelfx/README.md）。

signal hit_fired(info: Dictionary)
signal finished

static var _add_material: CanvasItemMaterial

var effect_id := ""
var variant := "default"
var speed_scale := 1.0
var additive := false
## 一次性特效放完自动 queue_free；循环特效（如营火）默认不自动清
var auto_free := true
## 朝左施放时自动翻面（近战刀光、投射物这类才需要）
var flip_by_dir := false

var _sheet: Dictionary = {}
var _frames: Array = []
var _durations: Array = []
var _times: Array = []
var _total := 0.0
var _elapsed := 0.0
var _index := 0
var _sprite: Sprite2D
var _hits: Array = []
var _hit_cursor := 0
var _playing := true


static func _ensure_material() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = SkillFx.additive_material()
	return _add_material


## 在 host 下生成一个像素特效。表没烘出来时返回 null，调用方要能安全退化。
## opts: variant / scale / flip / speed / additive / back / dir(Vector2) /
##       auto_free / flip_by_dir / z(float)
static func spawn(host: Node, at: Vector2, id: String, opts: Dictionary = {}) -> PixelFxFx:
	var sheet := PixelFxLib.sheet_for(id, String(opts.get("variant", "default")))
	if sheet.is_empty():
		return null
	var fx := PixelFxFx.new()
	fx.effect_id = id
	fx.variant = String(sheet.get("variant", "default"))
	fx._sheet = sheet
	fx.additive = bool(opts.get("additive", false))
	# 循环特效（营火、传送门这类）默认不自动清，一次性特效放完就回收
	fx.auto_free = bool(opts.get("auto_free", not bool(sheet.get("loop", false))))
	fx.flip_by_dir = bool(opts.get("flip_by_dir", false))
	fx.speed_scale = maxf(0.05, float(opts.get("speed", 1.0)))
	host.add_child(fx)
	fx.global_position = at
	var s := float(opts.get("scale", 1.0))
	fx.scale = Vector2(s, s) if s > 0.0 else Vector2.ONE
	var dir: Variant = opts.get("dir", null)
	var flip := bool(opts.get("flip", false))
	if dir is Vector2 and fx.flip_by_dir:
		flip = (dir as Vector2).x < 0.0
	fx._sprite.flip_h = flip
	fx.z_index = int(opts.get("z", -1.0 if bool(opts.get("back", false)) else 4.0))
	return fx


func _ready() -> void:
	if _sprite == null:
		# 场景里直接挂节点（没走 spawn）：自己建画布并按 effect_id 找表
		_sprite = Sprite2D.new()
		_sprite.name = "Sheet"
		# 像素表必须最近邻采样，否则一放大就是糊的一片
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	if _sheet.is_empty() and effect_id != "":
		_sheet = PixelFxLib.sheet_for(effect_id, variant)
	if not _sheet.is_empty() and _frames.is_empty():
		_setup()


func _setup() -> void:
	if _sheet.is_empty() or _sprite == null:
		return
	_frames = _sheet.get("frames", [])
	_durations = _sheet.get("durations", [])
	if _frames.is_empty():
		return
	_times.clear()
	_total = 0.0
	for raw in _durations:
		_times.append(_total)
		_total += float(raw) / 1000.0
	_total = maxf(0.001, _total)
	var pivot: Vector2 = _sheet.get("pivot", Vector2.ZERO)
	# offset 是「纹理左上角」的位移，所以要取负的 pivot 才能让原点落在节点上
	_sprite.offset = -pivot
	_sprite.texture = _frames[0] as Texture2D
	_hits = _sheet.get("hits", [])
	_hit_cursor = 0
	_elapsed = 0.0
	_index = 0
	_apply_material()


func _apply_material() -> void:
	if _sprite == null:
		return
	_sprite.material = _ensure_material() if additive else null
	_sprite.self_modulate = Color.WHITE


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_elapsed += delta * speed_scale
	for i in range(_hit_cursor, _hits.size()):
		var h: Dictionary = _hits[i]
		if float(h.get("t", 0.0)) <= _elapsed:
			_hit_cursor = i + 1
			hit_fired.emit(h)
		else:
			break
	if _elapsed >= _total:
		if bool(_sheet.get("loop", false)):
			_elapsed = fposmod(_elapsed, _total)
			_hit_cursor = 0
		else:
			_elapsed = _total - 0.0001
			_show_index(_frames.size() - 1)
			finished.emit()
			if auto_free:
				queue_free()
			return
	_show_index(_frame_index_at(_elapsed))


func _frame_index_at(t: float) -> int:
	var lo := 0
	var hi := _frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(_times[mid]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _show_index(i: int) -> void:
	if i == _index:
		return
	_index = i
	if _sprite != null and i < _frames.size():
		_sprite.texture = _frames[i] as Texture2D


# ===================== 外部控制 =====================

func set_frame(i: int) -> void:
	## 编辑器时间轴用：定格到某一帧
	_playing = false
	_elapsed = float(_times[clampi(i, 0, _frames.size() - 1)]) if not _times.is_empty() else 0.0
	_show_index(clampi(i, 0, maxi(0, _frames.size() - 1)))


func set_time(t: float) -> void:
	_elapsed = clampf(t, 0.0, _total)
	_hit_cursor = 0
	for i in _hits.size():
		if float(_hits[i].get("t", 0.0)) <= _elapsed:
			_hit_cursor = i + 1
	_show_index(_frame_index_at(_elapsed))


func set_playing(v: bool) -> void:
	_playing = v


func is_playing() -> bool:
	return _playing


func set_additive(v: bool) -> void:
	additive = v
	_apply_material()


func set_flip(v: bool) -> void:
	if _sprite != null:
		_sprite.flip_h = v


func set_scale_mult(v: float) -> void:
	scale = Vector2(v, v)


## 让特效半径贴合判定半径：frame_size 的半宽当作「视觉半径」
func fit_to_radius(radius: float) -> void:
	var fs: Vector2 = _sheet.get("frame_size", Vector2.ZERO)
	if fs.x <= 0.0:
		return
	var v := radius / (fs.x * 0.5)
	scale = Vector2(v, v)


func frame_count() -> int:
	return _frames.size()


func frame_time() -> float:
	return _total / maxf(1.0, float(_frames.size()))


func total_time() -> float:
	return _total


func current_index() -> int:
	return _index


func is_loop() -> bool:
	return bool(_sheet.get("loop", false))


## 第一下命中的时刻（秒，特效自己的时间轴）；没有命中帧返回 -1
func first_hit_time() -> float:
	if _hits.is_empty():
		return -1.0
	return float(_hits[0].get("t", 0.0))


func hits() -> Array:
	return _hits.duplicate(true)


func sheet() -> Dictionary:
	return _sheet
