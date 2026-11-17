extends Node
## UI 视觉秩序验收探针（2026-11-04 用户给的五条规则 → 五条可机检的验收项）
## 用法：godot --headless --path . tools/probe_ui_polish.tscn -- --no-save
##
## 验收对照：光影统一 / 色彩克制 / 文字分层 / 布局留白 / 无多余特效

const UI_DIR := "res://scripts/ui"
## 允许保留 ≥2px 描边的文件（UIKit 自己的实现除外）
const OUTLINE_ALLOWED_FILES := []


var _passes := 0
var _fails: Array = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label, "  ", detail)
	else:
		_fails.append(label + "  " + detail)
		print("FAIL  ", label, "  ", detail)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## 递归列出 .gd 文件
func _list_scripts(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir + "/" + name
		if d.current_is_dir() and not name.begins_with("."):
			_list_scripts(p, out)
		elif name.ends_with(".gd"):
			out.append(p)
		name = d.get_next()
	d.list_dir_end()


func _ready() -> void:
	# ============ ① 光影统一：一个光源方向，柔和投影 + 细亮边 ============
	var off := UIKit.elevation_offset(UIKit.ELEV_CARD)
	_check(off.x > 0.0 and off.y > 0.0, "① 光源在左上：投影一律落向右下", str(off))
	_check(UIKit.elevation_offset(UIKit.ELEV_DRAG).x > off.x,
		"① 层次越高投影越远", "%s → %s" % [off, UIKit.elevation_offset(UIKit.ELEV_DRAG)])
	var panel := UIKit.panel_style()
	_check(panel.shadow_size > 0 and panel.shadow_offset == UIKit.elevation_offset(UIKit.ELEV_FLOAT),
		"① 面板底带柔和投影", "size=%d offset=%s" % [panel.shadow_size, str(panel.shadow_offset)])
	_check(panel.border_width_left == 1, "① 面板外框收到 1px（不再靠粗框分层）",
		str(panel.border_width_left))
	var card := UIKit.accent_card_style(UIKit.C_ACCENT)
	_check(card.shadow_size > 0, "① 卡片/信息条同一套光影", str(card.shadow_size))
	var slot := UIKit.slot_style(true)
	_check(slot.shadow_size == 0, "① 面板内的槽位是平面元素：不投影", str(slot.shadow_size))
	# 亮边覆盖层：重复调用不叠第二层，且真的挂在底之上内容之前
	var host := PanelContainer.new()
	add_child(host)
	host.add_theme_stylebox_override("panel", UIKit.panel_style())
	UIKit.edge_light(host, 6.0)
	UIKit.edge_light(host, 6.0)
	var edges := 0
	for c in host.get_children():
		if c is UIKit.EdgeOverlay:
			edges += 1
	_check(edges == 1, "① 受光边只叠一层（重复调用幂等）", str(edges))
	_check(host.get_child(0) is UIKit.EdgeOverlay, "① 亮边画在底色之上、内容之下",
		String(host.get_child(0).name))
	var overlay := host.get_child(0) as UIKit.EdgeOverlay
	_check(overlay.light.a < overlay.shade.a or overlay.light.a < 0.2,
		"① 亮边是「细」亮边不是白框", "alpha=%.2f" % overlay.light.a)
	host.queue_free()

	# ============ ② 色彩克制：强调色只留给主按钮 ============
	_check(UIKit.C_EMPHASIS != UIKit.C_ACCENT, "② 强调色与通用金分开",
		"%s vs %s" % [UIKit.C_EMPHASIS.to_html(), UIKit.C_ACCENT.to_html()])
	_check(UIKit.title("x").get_theme_color("font_color") != UIKit.C_EMPHASIS,
		"② 标题不占用最高亮度色",
		UIKit.title("x").get_theme_color("font_color").to_html())
	_check(UIKit.subtitle("x").get_theme_color("font_color").s < UIKit.C_ACCENT.s,
		"② 副标题已降饱和", "%.2f < %.2f" % [
			UIKit.subtitle("x").get_theme_color("font_color").s, UIKit.C_ACCENT.s])
	var raw: Color = UIKit.FACILITY_STYLES["talisman"]["accent"]
	var got: Color = UIKit.facility_style("talisman")["accent"]
	_check(got.s < raw.s, "② 设施主题色统一降饱和（读出来就是收过的）",
		"%.2f → %.2f" % [raw.s, got.s])
	_check(absf(UIKit.muted(raw, 0.0).s - raw.s) < 0.001, "② muted(0) 不动原色",
		str(UIKit.muted(raw, 0.0).s))
	_check(UIKit.note("x").get_theme_color("font_color") == UIKit.C_TEXT_FAINT,
		"② 三级注释退到最暗一档", str(UIKit.C_TEXT_FAINT.to_html()))
	var chip := UIKit.chip("可挑战", UIKit.C_OK)
	var chip_sb := chip.get_theme_stylebox("panel") as StyleBoxFlat
	_check(chip_sb.border_color.a < 0.4, "② 状态签边框收透明度", str(chip_sb.border_color.a))
	chip.queue_free()

	# ============ ③ 文字三级：标题 / 正文 / 数字 ============
	_check(UIKit.F_TITLE > UIKit.F_SECTION and UIKit.F_SECTION > UIKit.F_BODY
			and UIKit.F_BODY > UIKit.F_SMALL, "③ 四级字号阶梯成立",
		"%d/%d/%d/%d" % [UIKit.F_TITLE, UIKit.F_SECTION, UIKit.F_BODY, UIKit.F_SMALL])
	var num := UIKit.num_label("128")
	_check(num.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "③ 数字右对齐成列",
		str(num.horizontal_alignment))
	_check(num.get_theme_font("font") == UIKit.readable_font(), "③ 数字用阅读字体（不靠艺术字）")
	_check(num.get_theme_constant("outline_size") == 0, "③ 数字不加描边")
	_check(not num.has_theme_font_override("font_bold"), "③ 数字不加粗")
	var row := UIKit.stat_row("气血上限", "657")
	var row_kids := row.get_children()
	var value_label := row_kids[row_kids.size() - 1] as Label
	_check(value_label != null and value_label.get_theme_color("font_color") == UIKit.C_NUM,
		"③ 属性行数值走数字级", str(value_label.get_theme_color("font_color").to_html()))
	_check(UIKit.title("T").get_theme_font_size("font_size") == UIKit.F_TITLE,
		"③ 标题级字号来源单一", str(UIKit.title("T").get_theme_font_size("font_size")))

	# ============ ④ 布局留白 ============
	_check(UIKit.GAP_SECTION > UIKit.GAP_BLOCK and UIKit.GAP_BLOCK > 0.0,
		"④ 留白常量成阶梯", "%s / %s / %s" % [
			UIKit.GAP_SECTION, UIKit.GAP_BLOCK, UIKit.GAP_PRIMARY_ROW])
	_check(UIKit.GAP_PRIMARY_ROW >= 16.0, "④ 主按钮行上方留够空", str(UIKit.GAP_PRIMARY_ROW))

	# ============ ⑤ 无多余特效：源码级扫描 ============
	var scripts: Array = []
	_list_scripts(UI_DIR, scripts)
	_list_scripts("res://scripts/main", scripts)
	_check(scripts.size() > 20, "⑤ 扫到了 UI 源码", "%d 个文件" % scripts.size())
	var heavy: Array[String] = []
	var outline_total := 0
	for spath in scripts:
		var src := _read(String(spath))
		if src == "":
			continue
		for line in src.split("\n"):
			var t := String(line).strip_edges()
			if t.contains("add_theme_constant_override(\"outline_size\""):
				var size := 0
				var at := t.find("outline_size\",")
				if at >= 0:
					var digits := ""
					for ch in t.substr(at + 14):
						if ch >= "0" and ch <= "9":
							digits += ch
						else:
							break
					size = int(digits) if digits != "" else 0
				if size >= 2 and not String(spath).ends_with("ui_kit.gd"):
					heavy.append("%s:%s" % [spath.get_file(), t])
				outline_total += 1
				if t.contains("add_theme_font_override(\"font_bold\""):
					heavy.append("%s: 加粗" % spath.get_file())
	_check(heavy.is_empty(), "⑤ 全 UI 里没有 ≥2px 的粗描边和加粗滥用",
		str(heavy.slice(0, 6)))
	_check(outline_total <= 6, "⑤ 描边调用总数已收敛（只留给压插画的字）", "%d 处" % outline_total)

	# 按钮：所有 tone 都不该再有描边，光晕只给主按钮
	var tones := ["default", "primary", "paper", "danger", "quiet", "tab"]
	var bad_outline: Array[String] = []
	var glow_src := _read("res://scripts/ui/ink_button.gd")
	for tone in tones:
		var b := UIKit.button("T", Vector2(80, 28), tone)
		if b == null:
			bad_outline.append("建不出来:" + tone)
			continue
		if int(b.get_theme_constant("outline_size")) != 0:
			bad_outline.append(tone)
		add_child(b)
		b.queue_free()
	_check(bad_outline.is_empty(), "⑤ 六种按钮全部去掉了文字描边", str(bad_outline))
	_check(glow_src.contains("tone == TONE_PRIMARY ? 0.16") or glow_src.contains("0.16 if tone == TONE_PRIMARY"),
		"⑤ 高亮光晕只给主按钮", "")
	_check(not glow_src.contains("tween_property(_brush, \"scale\", Vector2.ONE, 0.20)"),
		"⑤ hover 不再让笔刷线抽长（一次划过只留一个回执）", "")
	_check(UIKit.soft_text_shadow(Label.new(), 4) != null, "⑤ soft_text_shadow 仍可用")
	var dl := UIKit.soft_text_shadow(Label.new(), 1) as Label
	_check(int(dl.get_theme_constant("outline_size")) == 1
			and int(dl.get_theme_constant("shadow_offset_y")) == 2,
		"⑤ 压插画的字＝1px 细边 + 右下柔影",
		"outline=%s shadow_y=%s" % [dl.get_theme_constant("outline_size"),
			dl.get_theme_constant("shadow_offset_y")])
	dl.queue_free()

	print("RESULT passes=", _passes, " fails=", _fails.size())
	for f in _fails:
		print("  FAILED -> ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
