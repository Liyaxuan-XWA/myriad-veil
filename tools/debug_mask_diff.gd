extends Node2D
## 临时排查：比较「导入后的 lianqi_mask」与「磁盘原始 PNG」的像素是否一致。
## 用法：godot --headless --path . tools/debug_mask_diff.tscn

func _ready() -> void:
	var tex := load("res://assets/scenes/tiles/lianqi_mask.png") as Texture2D
	var img := tex.get_image()
	var raw := Image.load_from_file("res://assets/scenes/tiles/lianqi_mask.png")
	print("tex=", tex.get_class(), " size=", img.get_size(), " fmt=", img.get_format())
	print("raw size=", raw.get_size(), " fmt=", raw.get_format())
	if img.is_compressed():
		print("tex image is compressed")
	for p in [Vector2i(2, 2), Vector2i(375, 250), Vector2i(637, 200), Vector2i(200, 300), Vector2i(740, 490)]:
		print(p, " tex=", img.get_pixelv(p), " raw=", raw.get_pixelv(p))
	# 统计整幅差异
	var w := img.get_width()
	var h := img.get_height()
	var diff := 0
	var maxd := 0.0
	for y in range(0, h, 7):
		for x in range(0, w, 7):
			var a := img.get_pixel(x, y)
			var b := raw.get_pixel(x, y)
			var d: float = maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			if d > 0.05:
				diff += 1
				maxd = maxf(maxd, d)
	print("diff samples=", diff, " maxdiff=", maxd)
	get_tree().quit(0)
