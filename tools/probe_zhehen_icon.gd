extends Node
## 折痕佩图标：去粉底 / 留透明边 / 锻造挂签可用（2026-11-13）
## 用法：godot --headless --path . --quit-after 30000 res://tools/probe_zhehen_icon.tscn -- --no-save

const ICON := "res://assets/ui/icon/equip_zhehen_pei.png"
const EID := "eq_zhehen_pei"

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
	print("\n########## 折痕佩图标 ##########")
	await _run()
	print("\n########## 结果 %d 通过 / %d 失败 ##########" % [_passes, _fails.size()])
	for f in _fails:
		print("  ✗ ", f)
	get_tree().quit(_fails.size())


func _run() -> void:
	var def := ItemDB.get_equipment_template(EID)
	_check(not def.is_empty() and String(def.get("icon", "")) == ICON,
		"折痕佩模板指向该图标", String(def.get("icon", "")))
	var tex := load(ICON) as Texture2D
	_check(tex != null, "图标可加载")
	if tex == null:
		return
	var img := tex.get_image()
	_check(img != null and img.get_width() == 256 and img.get_height() == 256,
		"仍是 256²", str(img.get_size()) if img != null else "null")
	if img == null:
		return
	# 四角必须是全透明（旧版是半透明粉块）
	for p in [Vector2i(4, 4), Vector2i(251, 4), Vector2i(4, 251), Vector2i(251, 251)]:
		var c := img.get_pixelv(p)
		_check(c.a <= 0.02, "四角透明 %s" % str(p), "a=%.2f" % c.a)
	# 可见像素里不许残留粉/洋红（r、b 同时明显高于 g）
	var pink := 0
	var visible := 0
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.03:
				visible += 1
				if c.r - c.g > 0.14 and c.b - c.g > 0.05:
					pink += 1
			if c.a > 0.98:
				opaque += 1
	_check(pink == 0, "可见像素没有粉底残留", "pink=%d / visible=%d" % [pink, visible])
	_check(opaque > 12000 and visible > 15000, "实体覆盖足够", "opaque=%d visible=%d" % [opaque, visible])
	# 叠纸图标底板守卫：旧件整幅是半透明粉块（alpha≈80），按「可见面积」算而不是实心面积
	var used := img.get_used_rect()
	var fill := float(visible) / float(maxi(1, used.size.x * used.size.y))
	var semi := float(visible - opaque) / float(img.get_width() * img.get_height()) * 100.0
	_check(fill < 0.90, "外接框填充比 < 0.90（不是整幅底板）", "%.2f" % fill)
	_check(semi < 30.0, "半透明只占整幅 < 30%", "%.1f%%" % semi)
	# 透明边界的 RGB 已搬成物件色，避免缩小时粉边渗出
	var edge_rgb := img.get_pixel(8, 8)
	_check(edge_rgb.a <= 0.02 and edge_rgb.r - edge_rgb.g < 0.14,
		"透明区的底色不再发粉", str(edge_rgb))
	# 原图物件包围盒（透明边不应把画面裁没）
	_check(used.size.x > 100 and used.size.y > 100, "物件包围盒仍完整",
		"%s" % str(used.size))
	# 锻造挂签走 alpha 裁剪后应拿到物件大小的 region
	var trimmed := ForgeTagSlot._trimmed_texture(ICON)
	_check(trimmed is AtlasTexture and (trimmed as AtlasTexture).region.size.x > 100
			and (trimmed as AtlasTexture).region.size.y > 100,
		"锻造挂签裁边后仍有完整物件",
		str((trimmed as AtlasTexture).region) if trimmed is AtlasTexture else "not-atlas")
