extends Node2D
## 临时排查：把导入后的 lianqi_mask 存成 PNG，并统计差异像素的 alpha 分布。
## 用法：godot --headless --path . tools/debug_mask_dump.tscn

func _ready() -> void:
	var path := "res://assets/scenes/tiles/lianqi_mask.png"
	var tex := load(path) as Texture2D
	var img := tex.get_image()
	img.save_png("res://output/dump_mask_imported.png")
	var raw := Image.load_from_file(path)
	var w := img.get_width()
	var h := img.get_height()
	var by_alpha := {}
	var samples := 0
	for y in range(h):
		for x in range(w):
			var a := img.get_pixel(x, y)
			var b := raw.get_pixel(x, y)
			var d: float = maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			if d > 0.05:
				var key := "alpha=0" if b.a < 0.01 else "alpha>0"
				by_alpha[key] = int(by_alpha.get(key, 0)) + 1
				samples += 1
				if samples <= 8:
					print("diff ", Vector2i(x, y), " imp=", a, " raw=", b)
	print("total diff px=", samples, " ", by_alpha)
	get_tree().quit(0)
