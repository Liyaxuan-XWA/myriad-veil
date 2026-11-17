extends Node
## 试炼模式「每张强化卡到底有没有真正生效」全量静态审计。
##
## 跑法：godot --headless --path . --quit-after 20000 res://tools/audit_rogue_cards.tscn -- --no-save
## 只读，不进游戏、不写存档。
##
## 为什么要这个：2026-11-12 加「绝笔」时发现一类错 —— **desc 写了效果、卡进了池子、
## 三选一照常弹、选了也不报错，但代码里没有任何人读它**。这种卡不会让任何断言变红，
## 玩家要打完那局才发现「这张卡白拿」。277 张卡靠人眼对必然漏，所以要机器过一遍。
##
## 生效通道共 7 条（声明式的一律在 rogue_run.rebuild() 里派生，见该函数）：
##   attr    → CharacterData.set_attribute_mod("rogue", …)  id 必须是真属性（或 <属性>_pct 词条）
##   cap     → RogueRun.cap(KEY) / cap_bonus.get(KEY)        KEY 必须有人读
##   stat    → RogueRun.stat(KEY)                            必须有人读
##   flag    → RogueRun.has_flag(KEY)                        必须有人读
##   form    → apply_form_mods(form_id, out)                 field 必须是结算结果里真有的键
##   recipe / variant → 在 add_buff 里直接改符匣             id 必须在 TalismanDB 里
##   都没有  → 只能靠代码按 buff id 特判                     必须有人按 id 读
##
## 第二段判据：光「有人读这个 key」不够，读它的那段代码本身得会被执行 —— 每个命中点
## 归到所属顶层函数，再查该函数有没有调用点 / 裸名引用（connect、Callable）/ 是引擎虚函数。
## 这能抓住「效果写在一个没人调的函数里」的死代码。
##
## ⚠ 口径保守：报出来的是「按字面量查不到消费者」，可能是动态拼 key
##   （`stat(prefix + k)`）。每条都带 file:line 供人工复核，不许直接当 bug 报出去。
##
## ⚠ 性能：v2 一上来每个 needle 全量逐行扫（277 卡 × 多通道 = 千万次 GDScript 字符串
##   比较，跑到天荒地老）。改成**先把整份代码里的引号字面量建成倒排索引**，之后
##   `stat("KEY")` 这类查的都是「先 O(1) 拿候选行、只对候选行做精确匹配」。

const SCAN_ROOT := "res://scripts"
## 卡池定义文件本身不算消费者
const SKIP_SCAN_FILES: Array[String] = ["rogue_db.gd"]
## 这些由引擎调，源码里看不到调用点。⚠ 别往里塞自己项目的 `_build` / `_refresh`
##   之类，那等于宣布它们永远可达，把审计自己骗过去。
const ENGINE_VIRTUAL: Array[String] = [
	"_init", "_ready", "_enter_tree", "_exit_tree", "_process", "_physics_process",
	"_process_delta", "_input", "_unhandled_input", "_gui_input", "_draw",
	"_notification", "_to_string", "_get", "_set", "_get_property_list",
	"_validate_property", "_input_event", "_shortcut_input", "_unhandled_key_input",
	"_key", "_mouse_enter", "_mouse_exit", "_focus_entered", "_focus_exited",
	"_has_custom_cursor", "_gui_input", "_make_input_icon",
]

var _lines := PackedStringArray()
var _funcs := PackedStringArray()
var _files := PackedStringArray()
var _quoted: Dictionary = {}          ## 字面量 -> Array[int] 候选行号
var _all_text := ""                   ## 整份代码拼一遍，供 identifier 计数（C++ 侧）
var _scene_text := ""                 ## .tscn 里 method = &"_on_x" 也算引用
var _decl_count: Dictionary = {}      ## func 名 -> 声明次数
var _alive_cache: Dictionary = {}
var _attr_vocab: Dictionary = {}

var _total := 0
var _dead: Array = []
var _suspect: Array = []
var _ok := 0


func _ready() -> void:
	print("\n########## 试炼强化卡生效面审计 ##########")
	_scan_sources()
	_all_text = "\n".join(_lines)
	_attr_vocab = _build_attr_vocab()
	print("索引 %d 行 / %d 个字面量 / 合法属性 id %d 个" % [
		_lines.size(), _quoted.size(), _attr_vocab.size()])
	_self_check()
	for raw_fam in RogueDB.POOLS.keys():
		var fam := String(raw_fam)
		var pool: Array = RogueDB.POOLS[raw_fam]
		var bad := 0
		for raw_card in pool:
			var card: Dictionary = raw_card
			_total += 1
			var notes := _audit_card(card)
			if notes.is_empty():
				_ok += 1
			else:
				bad += 1
				var is_dead := String(notes[0]).begins_with("DEAD")
				if is_dead:
					_dead.append([fam, card, notes])
				else:
					_suspect.append([fam, card, notes])
				for n in notes:
					print("  [%s] %-9s %-22s %s\n        %s" % [
						"死卡" if is_dead else "存疑", fam, String(card.get("id", "")),
						String(card.get("name", "")),
						String(n).replace("\n", "\n        ")])
		print("  —— %-10s %3d 张，有问题 %d" % [fam, pool.size(), bad])
	print("\n########## 合计 %d 张：查通过 %d / 死卡 %d / 存疑 %d ##########" % [
		_total, _ok, _dead.size(), _suspect.size()])
	for r in _dead:
		print("  死卡 %s · %s「%s」  %s" % [r[0], String(r[1].get("id", "")),
				String(r[1].get("name", "")), String(r[1].get("desc", ""))])
	print("")
	get_tree().quit(0)


## 工具自检：搜索层一旦漏匹配，整份审计会「全绿」骗人（v3 就把 `t_bag` 误判成死卡 ——
## 源码写的是 `cap_bonus.get("talisman_bag", 0)`，而我的 needle 带了右括号）。
## 所以先拿**已知接好线**的 key 证明查得到、再拿**必然不存在**的 key 证明不误报。
func _self_check() -> void:
	var pos: Array = [
		["has_flag(\"tal_no_cd\"", "绝笔：本轮刚验证过有读取点"],
		["has_flag(\"intent_as_mana\"", "以意御法：player.gd 里读"],
		["has_flag(\"sun_throw_refund\"", "日归：player.gd 里读"],
		["cap_bonus.get(\"talisman_bag\"", "符囊格数：走 cap_bonus 直读，不走 cap()"],
	]
	var neg: Array = [
		["has_flag(\"zz_not_a_real_flag\"", "不存在的 flag"],
		["stat(\"zz_not_a_real_stat\"", "不存在的 stat"],
	]
	var bad := 0
	for p in pos:
		var n := _sites(String(p[0])).size()
		if n == 0:
			bad += 1
			print("  [自检红] 查不到已知存在的关键字 %s（%s）→ 搜索层坏了" % [p[0], p[1]])
	for n_ in neg:
		var m := _sites(String(n_[0])).size()
		if m != 0:
			bad += 1
			print("  [自检红] 不存在的关键字命中 %d 处 %s → 匹配太松" % [m, n_[0]])
	if not _func_alive("_on_talisman_swap_closed"):
		bad += 1
		print("  [自检红] 连信号的处理函数被判成不可达 → 可达性判据坏了")
	if _func_alive("zz_definitely_not_a_function"):
		bad += 1
		print("  [自检红] 凭空的函数名被判成可达 → 可达性判据太松")
	if not _is_behavior("res://scripts/player/player.gd"):
		bad += 1
		print("  [自检红] player.gd 没被算成行为文件 → 分类表错了")
	if _is_behavior("res://scripts/ui/panels/rogue_pick_panel.gd"):
		bad += 1
		print("  [自检红] 面板被算成行为文件 → 「只有 UI 在读」这层判据失效")
	print("  自检 %s（%d 项）" % ["通过" if bad == 0 else "失败", pos.size() + neg.size() + 4])
	if bad != 0:
		print("########## 审计工具本身有问题，本次结果不可信 ##########")
		get_tree().quit(9)



func _audit_card(card: Dictionary) -> Array:
	var id := String(card.get("id", ""))
	var notes: Array = []
	var channels := 0

	var attr: Dictionary = card.get("attr", {})
	for raw_a in attr.keys():
		channels += 1
		notes.append_array(_check_attr(String(raw_a)))

	var cap: Dictionary = card.get("cap", {})
	for raw_c in cap.keys():
		channels += 1
		var c := String(raw_c)
		var sites: Array = _sites('cap("%s"' % c)
		sites.append_array(_sites('cap_bonus.get("%s"' % c))
		if sites.is_empty() and not RogueDB.CAP_BASE.has(c):
			notes.append("DEAD: cap key「%s」既不在 CAP_BASE 也没人读" % c)
		else:
			notes.append_array(_need_reader("cap", c, sites))

	var st: Dictionary = card.get("stat", {})
	for raw_s in st.keys():
		channels += 1
		var s := String(raw_s)
		notes.append_array(_need_reader("stat", s, _sites('stat("%s"' % s)))

	var flag := String(card.get("flag", ""))
	if flag != "":
		channels += 1
		notes.append_array(_need_reader("flag", flag, _sites('has_flag("%s"' % flag)))

	var forms: Array = card.get("form", [])
	for raw_fm in forms:
		channels += 1
		var fm: Dictionary = raw_fm
		var form_id := String(fm.get("form_id", ""))
		var field := String(fm.get("field", ""))
		if form_id != "" and not _quoted.has(form_id):
			notes.append("DEAD: form_id「%s」全项目没有同名字面量（乘不到任何招式）" % form_id)
		elif form_id != "":
			notes.append_array(_need_reader("form_id", form_id, _sites('"%s"' % form_id), false))
		if field != "" and not _quoted.has(field):
			notes.append("DEAD: form field「%s」在别处从未出现（out 里没这个键 = 乘了个寂寞）"
					% field)

	var recipe := String(card.get("recipe", ""))
	if recipe != "":
		channels += 1
		if TalismanDB.base_def(recipe).is_empty():
			notes.append("DEAD: recipe 指向的符「%s」不在 TalismanDB" % recipe)

	var variant := String(card.get("variant", ""))
	if variant != "":
		channels += 1
		if TalismanDB.get_def(variant).is_empty():
			notes.append("DEAD: 变体「%s」不在 TalismanDB" % variant)

	if channels == 0:
		var sites: Array = _sites('"%s"' % id)
		if sites.is_empty():
			notes.append(
				"DEAD: 无 attr/cap/stat/flag/form/recipe/variant，也没人按 id 特判 —— 查不出这张卡能改变任何东西")
		else:
			notes.append_array(_need_reader("buff id", id, sites))
	return notes


## 有 key 的通道：必须存在「可达」的读取点，而且**至少有一个读取点真的改变行为**。
## ⚠ 第三层判据：只在 UI / 文案里读到的 key = 界面上说得天花乱坠，一局下来什么数都没变。
##   （本项目的 desc 是「现算」的，面板会把 stat 拼进句子 —— 那不算生效。）
func _need_reader(kind: String, key: String, sites: Array,
		require_behavior: bool = true) -> Array:
	var out: Array = []
	if sites.is_empty():
		out.append("DEAD: %s「%s」没有任何读取点" % [kind, key])
		return out
	var alive := false
	var behavioral := false
	var where := ""
	for s in sites:
		where = "%s:%d %s()" % [String(s["path"]).replace("res://", ""), int(s["line"]),
				String(s["func"])]
		if _func_alive(String(s["func"])):
			alive = true
			if _is_behavior(String(s["path"])):
				behavioral = true
				break
	if not alive:
		out.append("%s「%s」的读取点全在没被调用的函数里 → %s" % [kind, key, where])
	elif require_behavior and not behavioral:
		out.append("%s「%s」只被界面/文案读到，战斗结算里没人用它 → %s" % [kind, key, where])
	return out


## 「改了它，玩家的这一局会不一样」的目录。UI、面板、指引、纯数据展示文件都不算。
func _is_behavior(path: String) -> bool:
	var p := path.replace("res://", "")
	if p.begins_with("scripts/ui/") or p.begins_with("scripts/tutorial/"):
		return false
	if p.contains("/panels/") or p.contains("/widgets/"):
		return false
	# 数据文件里的 desc 现算不算行为，但 rogue_run.gd 这类运行期文件算
	if p.ends_with("_db.gd") and not p.ends_with("rogue_run.gd"):
		return false
	return true


## attr 通道：id 要么是真属性，要么是 <真属性>_pct 词条；且该属性要真的有人算
func _check_attr(a: String) -> Array:
	var out: Array = []
	var base := a
	if not _attr_vocab.has(a):
		if a.ends_with("_pct") and _attr_vocab.has(a.substr(0, a.length() - 4)):
			base = a.substr(0, a.length() - 4)
		else:
			out.append(
				"DEAD: attr id「%s」不是 AttributeDB 里的属性，也不是 <属性>_pct 词条（set_attribute_mod 会收下，但没人算它）" % a)
			return out
	var sites: Array = _sites('attribute("%s"' % base)
	var read_any := not sites.is_empty()
	# 属性也可能经 AttributeDB.ATTR_XXX 常量、或按 id 拼出来读：只证明「存在读它的地方」
	if not read_any and not _all_text.contains("ATTR_" + base.to_upper()):
		out.append("attr「%s」：属性 id 合法，但全项目找不到读取点" % a)
	return out


func _sites(needle: String) -> Array:
	var out: Array = []
	var key := _quoted_key_of(needle)
	if key != "":
		if not _quoted.has(key):
			return out
		for raw_i in _quoted[key]:
			var i := int(raw_i)
			if _lines[i].contains(needle):
				out.append({"path": _files[i], "line": i + 1, "func": _funcs[i]})
		return out
	for i in _lines.size():
		if _lines[i].contains(needle):
			out.append({"path": _files[i], "line": i + 1, "func": _funcs[i]})
	return out


## 从 `stat("KEY")` 这种 needle 里抠出 KEY，好走倒排索引；没有引号就返回 ""
func _quoted_key_of(needle: String) -> String:
	var p := needle.find("\"")
	if p < 0:
		return ""
	var q := needle.find("\"", p + 1)
	return needle.substr(p + 1, q - p - 1) if q > p else ""


func _func_alive(fname: String) -> bool:
	if fname == "" or ENGINE_VIRTUAL.has(fname):
		return true
	if _alive_cache.has(fname):
		return bool(_alive_cache[fname])
	var refs := _all_text.count(fname) + _scene_text.count(fname)
	refs -= int(_decl_count.get(fname, 0))
	_alive_cache[fname] = refs > 0
	return bool(_alive_cache[fname])


func _scan_sources() -> void:
	var files: Array = []
	_walk(SCAN_ROOT, ".gd", files)
	for raw_p in files:
		var p := String(raw_p)
		if SKIP_SCAN_FILES.has(p.get_file()):
			continue
		var text := FileAccess.get_file_as_string(p)
		var lines := text.split("\n")
		var cur := ""
		for i in lines.size():
			var l := String(lines[i])
			if l.begins_with("func ") or l.begins_with("static func "):
				cur = _func_name_of(l)
				_decl_count[cur] = int(_decl_count.get(cur, 0)) + 1
			elif cur != "" and not l.begins_with("\t") and not l.begins_with(" ") \
					and l.strip_edges() != "" and not l.begins_with("#"):
				cur = ""
			_files.append(p)
			_funcs.append(cur)
			_lines.append(l)
			_index_line(_lines.size() - 1)
	var scenes: Array = []
	_walk("res://scenes", ".tscn", scenes)
	var chunks: PackedStringArray = []
	for raw_s in scenes:
		chunks.append(FileAccess.get_file_as_string(String(raw_s)))
	_scene_text = "\n".join(chunks)


## 把一行里所有 "..." 字面量登记进行号（长句/带空格的不存，索引只为查 id）
func _index_line(i: int) -> void:
	var l := _lines[i]
	var p := l.find("\"")
	while p >= 0:
		var q := l.find("\"", p + 1)
		if q < 0:
			break
		var lit := l.substr(p + 1, q - p - 1)
		if lit != "" and lit.length() <= 64 and not lit.contains(" "):
			if not _quoted.has(lit):
				_quoted[lit] = []
			_quoted[lit].append(i)
		p = l.find("\"", q + 1)


func _func_name_of(line: String) -> String:
	var s := line.replace("static func ", "").replace("func ", "")
	var paren := s.find("(")
	return s.substr(0, paren).strip_edges() if paren > 0 else s.strip_edges()


func _build_attr_vocab() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string("res://scripts/data/attribute_db.gd")
	for raw_line in text.split("\n"):
		var s := String(raw_line).strip_edges()
		if not s.begins_with("const ATTR_"):
			continue
		var q0 := s.find("\"")
		var q1 := s.find("\"", q0 + 1)
		if q0 >= 0 and q1 > q0:
			out[s.substr(q0 + 1, q1 - q0 - 1)] = true
	return out


func _walk(dir_path: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var p := dir_path.path_join(n)
			if d.current_is_dir():
				_walk(p, ext, out)
			elif n.ends_with(ext):
				out.append(p)
		n = d.get_next()
	d.list_dir_end()
