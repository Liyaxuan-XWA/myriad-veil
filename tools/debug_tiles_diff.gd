extends Node2D
## 临时排查：assets/scenes/tiles 下所有被导入的贴图是否与磁盘 PNG 一致。
## 用法：godot --headless --path . tools/debug_tiles_diff.tscn

func _ready() -> void:
	var dir := DirAccess.open("res://assets/scenes/tiles")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".png"):
			names.append(f)
	names.sort()
	for f in names:
		var path := "res://assets/scenes/tiles/" + String(f)
		var tex := load(path) as Texture2D
		if tex == null:
			print("MISSING import ", f)
			continue
		var img := tex.get_image()
		var raw := Image.load_from_file(path)
		if img.get_size() != raw.get_size():
			print("SIZE DIFF ", f, " tex=", img.get_size(), " raw=", raw.get_size())
			continue
		var w := img.get_width()
		var h := img.get_height()
		var diff := 0
		var maxd := 0.0
		for y in range(0, h, maxi(1, h / 40)):
			for x in range(0, w, maxi(1, w / 40)):
				var a := img.get_pixel(x, y)
				var b := raw.get_pixel(x, y)
				var d: float = maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
				if d > 0.1:
					diff += 1
					maxd = maxf(maxd, d)
		if diff > 0:
			print("STALE  ", f, "  diff_samples=", diff, " max=", maxd)
		else:
			print("ok     ", f)
	get_tree().quit(0)
