extends Control
## 铸神祭坛设施图 · 实机尺寸对照（2026-11-13 抠图重做）
## 用法：godot --path . --windowed --resolution 900x460 res://tools/shot_god_altar.tscn -- --no-save
## 左：新版 中：化神坛（画风锚点）。都按 target_length≈170 的高度显示。

const ROW_H := 170.0
const SLOTS := [
	["res://assets/scenes/world/god_altar.png", 190.0],
	["res://assets/scenes/world/huashen_altar.png", 520.0],
]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.115, 0.11, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var ground := ColorRect.new()
	ground.color = Color(0.14, 0.16, 0.12)
	ground.position = Vector2(0, 330)
	ground.size = Vector2(900, 130)
	bg.add_child(ground)
	for spec in SLOTS:
		var path := String(spec[0])
		var tex := load(path) as Texture2D
		if tex == null:
			print("TEX NULL ", path)
			continue
		print("TEX ", path, " -> ", tex.get_size(), " ", tex.get_class())
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var h := ROW_H
		var w := tex.get_width() * (h / tex.get_height())
		tr.size = Vector2(w, h)
		tr.position = Vector2(float(spec[1]) - w * 0.5, 330.0 - h)
		add_child(tr)
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("output/god_altar_facility.png")
	print("SHOT output/god_altar_facility.png  viewport=", get_viewport().get_visible_rect().size)
	get_tree().quit(0)
