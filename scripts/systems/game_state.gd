extends Node
## 全局游戏状态管理（阶段1：仅承载核心战斗状态与信号）
## 依据《万界秘境》任务书：境界、装备、功法等系统将在阶段2实现，
## 本阶段只提供最基础的全局容器与信号，供战斗原型使用。

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"

## 非游戏世界场景（标题 / 入口）—— 常驻 HUD 类 UI（任务面板、教学浮层等）
## 是 autoload 子节点、跨场景不销毁，必须靠这里判断「现在该不该露脸」。
## ⚠ 新增菜单类场景往这里加；新**游戏**场景别加（漏加菜单只是多露一次，
##   漏加游戏场景会让玩家看不到 UI，代价不对称）。
const NON_GAME_SCENES: Array = [
	"res://scenes/ui/title_screen.tscn",   # 开始界面
	"res://scenes/main/main.tscn",         # 别名入口（F6 直跑，会立刻转开始界面）
]


## 当前场景是不是游戏世界（标题 / 入口界面返回 false）
func in_game_world() -> bool:
	var cs: Node = get_tree().current_scene
	if cs == null:
		return false
	return not NON_GAME_SCENES.has(cs.scene_file_path)


## 顺序任务面板只露脸的那一个场景（原初位面 = 主城）
## ⚠ 这里用**白名单**而不是往 NON_GAME_SCENES 里塞黑名单：战斗 / 试炼 / 棋坛 /
##   大世界 / 以后新加的场景全都不用维护。漏一个的代价只是「任务面板不显示」，
##   而黑名单漏一个会让面板浮在玩家脸上挡视野，两者代价不对称。
const PRIMORDIAL_REALM_SCENE := "res://scenes/main/primordial_realm.tscn"


func in_primordial_realm() -> bool:
	var cs: Node = get_tree().current_scene
	if cs == null:
		return false
	return cs.scene_file_path == PRIMORDIAL_REALM_SCENE


# ===== 模态界面计数（顺序任务面板的遮挡判定）=====
## 系统面板(101) / 角色面板(100) / 确认框(110) 打开时 +1、关闭时 -1。
## 任务面板 layer=118 比它们都高，不判这个就会浮在面板上面
## （2026-11-11 用户报「不要在其它面板上层显示」）。
## ⚠ 必须是**计数**不是 bool：角色面板里点「丢弃」会再叠一个确认框，先关谁都不能把标记清掉。
## ⚠ 每个 push 的实现都必须在 _exit_tree 兜底 pop —— 面板随场景被 free 时不走 close()，
##   计数泄漏一次任务面板就永久消失，而且不报任何错。
var _modal_ui_depth: int = 0
## 同上的「谁开着」栈（后开的在后面）。指引靠它判断「当前这层界面是不是指引所属的那层」：
## 只有锚点落在最上层界面里才露脸，别的界面一开就藏。
var _modal_stack: Array = []


func push_modal_ui(node: Node = null) -> void:
	_modal_ui_depth += 1
	if node != null:
		_modal_stack.append(node)


func pop_modal_ui(node: Node = null) -> void:
	_modal_ui_depth = maxi(0, _modal_ui_depth - 1)
	if node != null:
		_modal_stack.erase(node)
	elif not _modal_stack.is_empty():
		_modal_stack.pop_back()


func modal_ui_open() -> bool:
	return _modal_ui_depth > 0


## 最上层的模态界面（已释放的会顺带清掉）；没有则 null
func top_modal() -> Node:
	for i in range(_modal_stack.size() - 1, -1, -1):
		var n = _modal_stack[i]
		if n is Node and is_instance_valid(n):
			return n as Node
		_modal_stack.remove_at(i)
	return null

# 当前境界（阶段1占位，阶段2正式实现境界系统）
var current_realm: String = "练气"

# 当前战斗的来源上下文（跨场景传递，供胜利结算使用）
# 形如：{"source": "arena"} / {"source": "domain", "domain_id": ..., "boss_id": ...} / {"source": "tower", "floor": n}
# 由入口（演武场 / 位面 / 万界塔）写入，战斗场景胜利时结算，返回主城时清空
# 详见 BattleResolver
var battle_context: Dictionary = {}

# 万界棋坛关卡上下文（跨场景传递，形如 {"level": 7}）
# 由棋谱长卷在「进入此关」时写入，对局读取它决定对手卡组与读数；
# 与 battle_context 分开：那条走 BattleResolver / combat_arena 的 BOSS 战结算，
# 棋局有自己的场景、胜负规则与结算，塞进去反而要在那边加分支。
var match_context: Dictionary = {}

## 跨场景的**一次性界面请求**：谁切回原初位面后要直接开哪个面板。
## 形如 {"panel": "domain", "tab": "world", "region": "lianqi"}（战败「去青岚野取剑」用）。
## 由发出方写、primordial_realm._ready 消费后立刻清空 —— 只活一次，不进存档。
var pending_panel: Dictionary = {}

# ===== 锻造台镜像（新手指引 c5 用，仅会话内状态，不进存档）=====
# 教学步骤表用 cond 轮询这两个值兜底：玩家不按推荐顺序操作（先拿锤 / 砧上直拖穿戴）
# 时，事件会发在「前一步还活着」的窗口里被步骤机丢掉；cond 读的是持久状态，
# 步一激活轮询就能立刻补完。forge_panel 负责维护（见 _pick_hammer / _refresh_content）。
var forge_hammer_held: bool = false   # 锤子是否被拿在手里
var forge_anvil_id: String = ""       # 砧上装备 id，空串 = 砧上没东西

# 信号：用于战斗关键事件广播
signal player_died
signal boss_died(boss_id: String)
signal boss_phase_changed(boss_id: String, phase: int)

# ===== 时间流速控制（顿帧 / 慢动作） =====
# 用真实时间戳驱动一个多阶段序列，避免 Engine.time_scale 影响计时
# 序列元素：{ scale: 时间流速, end_usec: 该阶段结束的真实时间戳 }
var _time_flow_sequence: Array = []
## 时间流的**恢复基准**。顿帧/慢动作结束后回到这个倍率，而不是写死的 1.0。
## 单人玩法恒为 1.0，行为与改动前完全一致；卡片自走棋的对局加速会把它推到 1.0→2.0，
## 那时 BOSS 转阶段的慢动作若仍恢复成 1.0，就会把加速值静默冲掉 —— 表现为「越打越慢回去」。
var time_flow_base: float = 1.0
const HIT_STOP_TIME_SCALE := 0.05
## 顿帧最小间隔（秒）—— ⚠ 必须节流！
## 万剑归宗一次放出十几把剑，每把命中都会调 trigger_hit_stop。
## 而 _push_time_flow 会把阶段**排队顺延**，12 把连中 = 累积 0.6 秒近乎静止，
## 表现就是「剑越多越卡」。节流后一轮连击只顿一次，单发重击的打击感不受影响。
const HIT_STOP_MIN_INTERVAL := 0.12
var _last_hit_stop_usec: int = 0


# ===== 调试面板数值持久化 =====
# boss_debug_overrides：用户在调试面板改过的 BOSS 数值（跨 R 重开保留）
# boss_debug_defaults：各字段的脚本默认值（首次从 BOSS 捕获，用于"恢复默认"）
var boss_debug_overrides: Dictionary = {}
var boss_debug_defaults: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 关窗 / 手机返回键不再由引擎直接结束进程，改走 ask_quit() 的确认框（2026-11-13 用户定）
	# ⚠ 两道闸门都要关：auto_accept_quit 管桌面 ×，quit_on_go_back 管安卓返回键。
	#   只关前者的话，手机端仍在弹确认框之前就先退出，确认框等于没机会出现。
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	_setup_sfx()
	_setup_debug_item_panel()


## 窗口 × 与安卓返回键。两个通知走两条路（2026-11-13 用户定）：
##   · WM_CLOSE（桌面点 ×）→ 一律弹「保存并退出」确认框
##   · WM_GO_BACK（安卓返回键）→ 先当「后退」用，退无可退才谈退出
## ⚠ 两个通知都要接：关掉 quit_on_go_back 之后，返回键就只剩这条通知，
##   不接等于返回键失灵。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ask_quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_go_back()


## 场景自己声明「返回键 = 后退」：主城 / 战斗 / 大世界进场置 true、离场置 false。
## true 时返回键合成一发 ESC，复用该场景已经调通的那条链；
## false（棋局、试炼、标题界面）没有后退语义，返回键退回退出确认。
var back_uses_esc := false


## 安卓返回键：面板/弹窗开着就关最上层，游戏场景里走该场景的 ESC 语义，
## 两者都没有才弹退出确认。
## ⚠ 实现方式是**合成一发 ESC**，不是另写一套关闭逻辑：项目里 ESC 的链条
##   （确认框取消 → 面板关闭 → 主城返回登录 → 战斗放弃本场 → 大世界指路传送门）
##   已经调通了，返回键复用同一条，PC 键盘路径一个字节都不用动。
func handle_go_back() -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		# 已经站在退出确认框上：返回键 = 取消，不再叠一层
		_inject_esc()
		return
	if _modal_ui_depth > 0 or back_uses_esc:
		_inject_esc()
		return
	ask_quit()


func _inject_esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	up.keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)


## 道具获取调试面板（2026-10-21 用户专用）
## ⚠ 只在**编辑器运行**时创建：导出包（debug / release 都一样）里
##   `OS.has_feature("editor")` 恒为 false，面板根本不会被实例化，
##   F2 也没有监听者 —— 不是靠隐藏或密码挡住的。
func _setup_debug_item_panel() -> void:
	if not OS.has_feature("editor"):
		return
	if get_node_or_null("DebugItemPanel") != null:
		return
	var panel := DebugItemPanel.new()
	panel.name = "DebugItemPanel"
	add_child(panel)


func _process(_delta: float) -> void:
	_tick_time_flow()


## 推进时间流速序列：到达阶段终点则切到下一阶段或恢复
func _tick_time_flow() -> void:
	if _time_flow_sequence.is_empty():
		return
	var now := Time.get_ticks_usec()
	# 弹出所有已到期的阶段
	while not _time_flow_sequence.is_empty() and now >= _time_flow_sequence[0].end_usec:
		_time_flow_sequence.pop_front()
	# 应用当前阶段的时间流速；序列空则恢复到基准
	if _time_flow_sequence.is_empty():
		Engine.time_scale = time_flow_base
	else:
		Engine.time_scale = _time_flow_sequence[0].scale


## 设定时间流的恢复基准（对局加速用）。立即生效，且之后每次顿帧/慢动作都回到这个值。
func set_time_flow_base(scale: float) -> void:
	time_flow_base = maxf(0.05, scale)
	if _time_flow_sequence.is_empty():
		Engine.time_scale = time_flow_base


## 触发顿帧：duration 为真实时间秒数（如 0.05 ≈ 3 帧 @60fps）
## ⚠ 带节流：多段命中（万剑归宗十几把剑连中）只顿一次，避免时间流队列越堆越长
## force = true 跳过节流：只给玩家终结段这种「必须顿」的重击用，禁止批量技能使用
func trigger_hit_stop(duration: float = 0.05, force: bool = false) -> void:
	var now := Time.get_ticks_usec()
	if not force and now - _last_hit_stop_usec < int(HIT_STOP_MIN_INTERVAL * 1_000_000):
		return
	_last_hit_stop_usec = now
	_push_time_flow(HIT_STOP_TIME_SCALE, duration)


## 慢动作：短暂放慢时间流速后恢复（可跟在顿帧之后形成"冻结→慢放"序列）
func trigger_slow_mo(duration: float, time_scale: float) -> void:
	_push_time_flow(time_scale, duration)


## 压入一个时间流速阶段：scale 持续 duration 秒（真实时间），之后自动恢复到 time_flow_base
func _push_time_flow(scale: float, duration: float) -> void:
	var now := Time.get_ticks_usec()
	# 若已有未结束的序列，从最后阶段结束时刻之后顺延，保证不重叠错乱
	var start_usec := now
	if not _time_flow_sequence.is_empty():
		start_usec = _time_flow_sequence[_time_flow_sequence.size() - 1].end_usec
	var end_usec := start_usec + int(duration * 1_000_000)
	# 阶段：指定 scale 持续到 end_usec
	_time_flow_sequence.append({"scale": scale, "end_usec": end_usec})
	# 恢复阶段：回到基准倍率，从 end_usec 开始（作为队首弹出后的恢复态）
	_time_flow_sequence.append({"scale": time_flow_base, "end_usec": end_usec})
	# 立即应用新的时间流速
	Engine.time_scale = scale


## 重置时间流速（重开场景前调用，避免残留顿帧/慢动作导致永久卡慢）
## 连基准一起清掉：上一局的对局加速不得带进新场景。
func reset_time_flow() -> void:
	_time_flow_sequence.clear()
	time_flow_base = 1.0
	Engine.time_scale = 1.0


func reset_run_state() -> void:
	"""重置一次战斗运行的状态（不含存档持久化）"""
	current_realm = "练气"
	reset_time_flow()


# ===== 退出确认（2026-11-13 用户定：关软件要先弹窗，点确认保存才关闭）=====
## 正在显示的退出确认框。连点窗口 × 不能叠两层，所以留引用。
var _quit_dialog: ConfirmDialog = null
## 从「决定要弹」到「真的进树」之间也算已弹过：探针与连点都靠它去重
var _quit_dialog_busy := false
## 探针 / 调试用：确认后是否真的请求了退出，以及退出前那一次存档的结果
var quit_requested := false
var quit_save_result: Dictionary = {}
## 「结束进程」单独封一层：探针把它换成记录器，才能验「点确认确实退出」而不自杀
var quit_handler: Callable = _quit_process


func _quit_process() -> void:
	get_tree().quit()


## 弹退出确认框。文案按「现在在哪、退出时存档会怎样」分五档，不许承诺做不到的事：
##   · 游戏内且有进度 → 按钮「保存并退出」，退出前写自动存档槽（1–4 轮转）
##   · 试炼之路（RogueRun.active）→ 明说本局不写存档
##   · 游戏内但还没进度 → auto_save 本来就会跳过空档，不能写成「会保存」
##   · 游戏内但存档闸门关着（--no-save 这类）→ 同样不能说「会保存」
##   · 标题界面 → 没有进度可写
## ⚠ 「是不是试炼」看 RogueRun.active，不看 SaveManager 的闸门：--no-save 也会
##   关 auto_save_enabled，那时玩家明明在主城里，却会看到试炼文案。
##   能写的那档只取 auto_save_enabled：write_enabled 是开发总开关，
##   不该泄漏成玩家看得见的一句话（探针因此能在 --no-save 下走到「保存并退出」那档，
##   而 auto_save 自己被 write_enabled 拦住，一个字节都不会落盘）。
## 文案本身封成 quit_plan() 纯函数：探针能逐档验文案而不用真的切场景。
func quit_plan(in_game: bool, in_trial: bool, writable: bool, has_progress: bool) -> Dictionary:
	var ok := "退出"
	var cancel := "取消"
	var msg := "当前不在游戏内，没有需要写入的进度。"
	var danger := false
	if in_trial:
		cancel = "继续挑战"
		msg = "试炼之路进行中 —— 本局不会写入存档，退出即放弃本局。\n角色进度以上一次存档为准。"
		danger = true
	elif has_progress:
		ok = "保存并退出"
		cancel = "继续游戏"
		msg = "退出前会把当前进度写进自动存档槽（1–4 轮转）。\n本场战斗与未拾取的掉落会一并结束。"
		danger = true
	elif writable:
		cancel = "继续游戏"
		msg = "本次还没有可保存的进度（新开局），退出不会写入存档。"
	elif in_game:
		cancel = "继续游戏"
		msg = "本次运行不写入存档，退出会丢掉未保存的进度。"
		danger = true
	return {"ok": ok, "cancel": cancel, "msg": msg, "danger": danger}


## 把四个真值现算一遍交给 quit_plan：状态读法只在这里，文案只在 quit_plan 里
## ⚠ 框必须延后一帧建：窗口 × 的通知是 root 往下 propagate 时送进来的，
##   那期间 root 正忙着挂子节点，直接 add_child 会被拒（"Parent node is busy
##   setting up children"），确认框根本弹不出来。
func ask_quit() -> void:
	if _quit_dialog_busy:
		return
	_quit_dialog_busy = true
	var in_game := in_game_world()
	var in_trial := in_game and RogueRun.active
	var writable := in_game and SaveManager.auto_save_enabled
	var has_progress := writable and not SaveManager.is_blank_run(SaveManager.capture())
	var p := quit_plan(in_game, in_trial, writable, has_progress)
	_spawn_quit_dialog.call_deferred(String(p["msg"]), String(p["ok"]),
		String(p["cancel"]), bool(p["danger"]))


func _spawn_quit_dialog(msg: String, ok: String, cancel: String, danger: bool) -> void:
	var d := ConfirmDialog.ask("退出游戏", msg, ok, cancel, _on_quit_confirmed, danger)
	# 没进树（父节点正忙之类）就放开闸门，否则下一次点 × 永远弹不出来
	if d == null or not is_instance_valid(d) or d.get_tree() == null:
		_quit_dialog_busy = false
		return
	_quit_dialog = d
	d.tree_exiting.connect(func() -> void:
		if _quit_dialog == d:
			_quit_dialog = null
		_quit_dialog_busy = false)


## 点「保存并退出」：先落盘，再结束进程（点「取消」不会走到这里）
func _on_quit_confirmed() -> void:
	quit_save_result = save_before_quit()
	quit_requested = true
	quit_handler.call()


## 退出前的存档：只有「游戏内 + 允许自动存档」才写。
## auto_save 自己还会拦空档 / 刚读档那一发，所以 slot 可能是 -1（没写但不算失败）。
func save_before_quit() -> Dictionary:
	if not in_game_world() or not SaveManager.auto_save_enabled:
		return {"attempted": false, "slot": -1}
	return {"attempted": true, "slot": SaveManager.auto_save()}


## 游戏内「退出游戏」统一走这里：自动存档 → 清理战斗/慢动作状态 → 返回登录（开始）界面。
## ⚠ 先恢复 paused 与时间流速，否则新场景可能一进去就暂停 / 慢动作。
func return_to_title() -> void:
	SaveManager.auto_save()
	reset_time_flow()
	BattleResolver.clear()
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


# ===== 全局音效管理器（程序生成占位音效，正式阶段替换为音频资源） =====
## 战斗音效声部数：挥击风声 / 命中 / 材质 / 空挥 必须能同时响，
## 单个播放器会把上一声直接掐断（2026-10-27 平A 手感第 2 步）
const SFX_VOICES := 4
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_voice := 0
var _sfx_cache: Dictionary = {}


func _setup_sfx() -> void:
	if not _sfx_players.is_empty():
		return
	for i in range(SFX_VOICES):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_sfx_players.append(p)
	_setup_ui_sfx()
	# 预生成所有战斗音效
	_sfx_cache = {
		"attack_hit": _gen_wav(_attack_hit_samples(), 22050),
		"player_hit": _gen_wav(_player_hit_samples(), 22050),
		"boss_attack": _gen_wav(_boss_attack_samples(), 22050),
		"phase_change": _gen_wav(_phase_change_samples(), 22050),
		"boss_death": _gen_wav(_boss_death_samples(), 22050),
		# 普攻命中材质（2026-10-27）：叠在 attack_hit 下面
		"attack_impact": _gen_wav(_impact_samples(), 22050),
		# BOSS 入场卡：墨迹扩散 / 金线扫过 / 印章落定 / 开战鼓
		"boss_intro_whoosh": _gen_wav(_intro_whoosh_samples(), 22050),
		"boss_intro_shimmer": _gen_wav(_intro_shimmer_samples(), 22050),
		"boss_intro_seal": _gen_wav(_intro_seal_samples(), 22050),
		"boss_intro_start": _gen_wav(_intro_start_samples(), 22050),
	}


## 播放指定音效（按名称）
## ⚠ 多声部轮流用：同名音效仍有最小间隔（万剑归宗十几把剑连中时不糊成一片），
##   不同音效可以叠着响（挥击风声 + 命中 + 材质）。
const SFX_MIN_INTERVAL := 0.06
var _last_sfx_usec: Dictionary = {}

func play_sfx(sfx_name: String) -> void:
	if _sfx_players.is_empty():
		_setup_sfx()
	if not _sfx_cache.has(sfx_name):
		return
	var now := Time.get_ticks_usec()
	if now - int(_last_sfx_usec.get(sfx_name, 0)) < int(SFX_MIN_INTERVAL * 1_000_000):
		return
	_last_sfx_usec[sfx_name] = now
	var p := _sfx_players[_sfx_voice]
	_sfx_voice = (_sfx_voice + 1) % _sfx_players.size()
	p.stream = _sfx_cache[sfx_name]
	p.play()


# ---- 各音效的采样数据生成 ----
func _gen_wav(samples: Array, sample_rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


## 攻击命中「唰」：短促中频噪声脉冲
func _attack_hit_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.12)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 40.0)
		out.append((rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 900.0 * t) * 0.4) * env)
	return out


## 命中材质：短促低频 + 噪声「实心」一击，和 attack_hit 的「唰」叠一起
func _impact_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.10)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 421
	for i in range(n):
		var t := float(i) / sr
		var u := t / 0.10
		var env := exp(-t * 26.0)
		var freq := 150.0 - 60.0 * u
		out.append((sin(TAU * freq * t) * 0.55
			+ rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.45) * env * 0.8)
	return out


## 玩家受击「咚」：低频重击
func _player_hit_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.2)
	var out: Array = []
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 20.0)
		out.append((sin(TAU * 180.0 * t) * 0.7 + sin(TAU * 90.0 * t) * 0.3) * env)
	return out


## BOSS 出招「呼」：中低频上滑
func _boss_attack_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.18)
	var out: Array = []
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 18.0)
		var freq := 200.0 + 500.0 * (t / 0.18)
		out.append(sin(TAU * freq * t) * 0.5 * env)
	return out


## 转阶段「嗡」：持续低频震颤
func _phase_change_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.6)
	var out: Array = []
	for i in range(n):
		var t := float(i) / sr
		var env := sin(TAU * 0.8 * t) * 0.5 + 0.5  # 缓慢包络起伏
		out.append(sin(TAU * 120.0 * t) * 0.5 * env + sin(TAU * 240.0 * t) * 0.3 * env)
	return out


## 击杀「轰」：低频爆炸感 + 快速衰减
func _boss_death_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.4)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 222
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 12.0)
		out.append((sin(TAU * 100.0 * t) * 0.6 + sin(TAU * 60.0 * t) * 0.4 + rng.randf_range(-0.2, 0.2)) * env)
	return out


# ===== BOSS 入场卡音效（2026-10-27）=====
## 墨迹扩散「呼——」：低通噪声扫过 + 低频下潜
func _intro_whoosh_samples() -> Array:
	var sr := 22050
	var dur := 0.55
	var n := int(sr * dur)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 331
	var lp := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		var env := sin(PI * clampf(u * 1.5, 0.0, 1.0)) * (1.0 - u * 0.55)
		var k := 0.02 + 0.13 * u
		lp += (rng.randf_range(-1.0, 1.0) - lp) * k
		var body := sin(TAU * (72.0 - 22.0 * u) * t) * 0.35
		out.append((lp * 1.7 + body) * env * 0.9)
	return out


## 金线扫过：高频金属细碎声（三音叠 + 快速衰减）
func _intro_shimmer_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.42)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 332
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 9.0)
		var trem := 0.72 + 0.28 * sin(TAU * 17.0 * t)
		var s := sin(TAU * 2093.0 * t) * 0.30
		s += sin(TAU * 2637.0 * t) * 0.22
		s += sin(TAU * 3136.0 * t) * 0.16
		s += rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.25
		out.append(s * env * trem)
	return out


## 印章落定「笃」：低频闷响 + 短促纸面噪声
func _intro_seal_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.26)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	for i in range(n):
		var t := float(i) / sr
		var env := exp(-t * 16.0)
		var thud := sin(TAU * 96.0 * t) * 0.72 + sin(TAU * 178.0 * t) * 0.28
		var paper := rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.35
		out.append((thud + paper) * env)
	return out


## 开战「鼓」：低频下潜 + 轻噪声，解除停时的起手信号
func _intro_start_samples() -> Array:
	var sr := 22050
	var n := int(sr * 0.5)
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 334
	for i in range(n):
		var t := float(i) / sr
		var u := t / 0.5
		var env := exp(-t * 7.0)
		var freq := 112.0 - 55.0 * u
		var s := sin(TAU * freq * t) * 0.75
		s += sin(TAU * freq * 2.0 * t) * 0.18
		s += rng.randf_range(-1.0, 1.0) * exp(-t * 45.0) * 0.30
		out.append(s * env)
	return out


# ===== UI 音效（2026-10-22 用户定：各种点击都要有声音，风格统一、音量一致、不突兀）=====
## 统一口径（改音效时务必守住这四条，否则会"突兀"）：
##   ① **同一个合成器**（`_ui_tone`）生成全部界面音效：正弦主体 + 少量谐波 +
##      3ms 软起音 + 指数衰减；界面音**一律不加噪声**（噪声是"嘶"的来源，在 UI 上最刺耳）
##   ② 每个音效都做**峰值归一化到 UI_PEAK** —— 各音效响度严格一致，不会某个抢耳
##   ③ 走独立的 4 声部池 + 统一音量 UI_VOLUME_DB（比战斗音效轻约 9dB，不盖战斗音）
##   ④ 音高都取自然音阶（A/C/D/E/G 系），避免出现不协和的电子"哔"
## 想加新音效：在 `_ui_cache` 里加一条，用 `_ui_tone` / `_ui_arp` 生成即可，音量自动一致。
const UI_VOLUME_DB := -16.0
## 所有界面音效的峰值（归一化目标）——"音量一致"就是靠这一条实现的
const UI_PEAK := 0.62
## 声部数：连点按钮/连敲锤子时轮流用，不会互相打断
const UI_VOICES := 4
## 同一音效的最小重复间隔（连敲锤子保留节奏感，又不至于糊成一片）
const UI_MIN_INTERVAL := 0.035

var _ui_players: Array[AudioStreamPlayer] = []
var _ui_cache: Dictionary = {}
var _ui_voice := 0
var _last_ui_usec: Dictionary = {}


func _setup_ui_sfx() -> void:
	if not _ui_players.is_empty():
		return
	for i in range(UI_VOICES):
		var p := AudioStreamPlayer.new()
		p.volume_db = UI_VOLUME_DB
		add_child(p)
		_ui_players.append(p)
	_ui_cache = {
		# 通用点击：A5，75ms，轻而圆
		"ui_click": _sfx_wav(_ui_tone(880.0, 0.075, 55.0, [[1.0, 1.0], [2.0, 0.18]], 0.40)),
		# 页签切换：高一个纯四度，更短更薄
		"ui_tab": _sfx_wav(_ui_tone(1174.0, 0.060, 70.0, [[1.0, 1.0], [2.0, 0.12]], 0.45)),
		# 打开面板 / 进入设施：E5→B5 上行（"展开"感）
		"ui_open": _sfx_wav(_ui_tone(659.0, 0.170, 20.0,
			[[1.0, 1.0], [2.0, 0.26], [3.0, 0.08]], 0.38, 0.0, 988.0)),
		# 关闭 / 返回：A4→D4 下行（"收起"感）
		"ui_close": _sfx_wav(_ui_tone(440.0, 0.140, 26.0,
			[[1.0, 1.0], [2.0, 0.15]], 0.32, 0.0, 294.0)),
		# 不可用 / 材料不足：低而短、闷（故意不刺耳）
		"ui_deny": _sfx_wav(_ui_tone(300.0, 0.120, 34.0, [[1.0, 1.0], [1.5, 0.18]], 0.26)),
		# 穿戴 / 卸下装备：极轻的"嗒"（比点击更短更薄，连穿几件也不吵）
		"ui_equip": _sfx_wav(_ui_tone(1046.0, 0.050, 90.0, [[1.0, 1.0]], 0.50)),
		# 确认类 / 领取：两音上行（C5→G5）
		"ui_confirm": _sfx_wav(_ui_arp([523.0, 784.0], 0.055, 0.18, 22.0,
			[[1.0, 1.0], [2.0, 0.28]], 0.36)),
		# 敲击铁器（2026-10-22 第二次改口径：从「柔和打铁」换成真的锤击铁砧声）
		"forge_hammer": _sfx_wav(_forge_hammer_samples()),
		# 拿起锤子：金属上滑（1250→1750Hz）+ 一点摩擦噪声，像把锤子提起来
		"forge_hammer_pick": _sfx_wav(_ui_tone(1250.0, 0.11, 26.0,
			[[1.0, 1.0], [2.1, 0.20]], 0.50, 0.08, 1750.0)),
		# 放下锤子：落在木台上的"嗒"（144Hz 闷响 + 760Hz 金属 + 轻摩擦）
		"forge_hammer_down": _sfx_wav(_ui_tone(760.0, 0.16, 30.0,
			[[0.19, 0.55], [1.0, 0.50], [2.2, 0.18]], 0.52, 0.10)),
		# 强化成功：三音上行
		"forge_success": _sfx_wav(_ui_arp([659.0, 784.0, 988.0], 0.045, 0.20, 20.0,
			[[1.0, 1.0], [2.0, 0.24]], 0.38)),
		# 大成功 / 进阶：四音上行、更亮
		"forge_great": _sfx_wav(_ui_arp([659.0, 880.0, 1046.0, 1318.0], 0.040, 0.18, 20.0,
			[[1.0, 1.0], [2.0, 0.34], [3.0, 0.12]], 0.40)),
		# 强化失败 / 破损：下行两音、闷
		"forge_fail": _sfx_wav(_ui_arp([392.0, 294.0], 0.070, 0.18, 26.0,
			[[1.0, 1.0], [2.0, 0.12]], 0.26)),
		# 挥锤风声：短促的低频噪声 + 极轻的低音，给 0.28s 自动弧线一个起手
		"forge_swing": _sfx_wav(_forge_swing_samples()),
		# 熔铸：炉膛低鸣 + 渐强噪声，约 1.1 秒，配合镜头推进与出炉
		"forge_melt": _sfx_wav(_forge_melt_samples()),
		# ---- 开始界面入场演出（2026-10-26）----
		# 悬停：极轻的一点，比点击再轻一档；只在鼠标移入漩涡时响
		"ui_hover": _sfx_wav(_normalize_peak(_ui_tone_raw(1318.0, 0.055, 95.0,
			[[1.0, 1.0], [2.0, 0.10]], 0.50), UI_PEAK * 0.46)),
		# 蓄力：55→132Hz 上滑 + 渐强摩擦，0.9s，接住"被气流托住"那一下
		"title_charge": _sfx_wav(_title_charge_samples()),
		# 牵引：带通噪声扫频的呼啸 + 气旋摆动，1.0s
		"title_pull": _sfx_wav(_title_pull_samples()),
		# 溶解：铃片 G6→C5 下滑 + 砂化颗粒，0.55s
		"title_dissolve": _sfx_wav(_title_dissolve_samples()),
		# 收束 + 白闪：140→34Hz 下潜 + 冲击瞬态 + 高频闪耀，0.85s（这一发最重）
		"title_collapse": _sfx_wav(_title_collapse_samples()),
	}


## 把采样数组包成可播放的 wav（统一 22050Hz 单声道，与战斗音效同一格式）
func _sfx_wav(samples: Array) -> AudioStreamWAV:
	return _gen_wav(samples, 22050)


## 播放 UI 音效（4 声部轮转，连续点击不会互相打断）
## 名称不存在时静默忽略 —— 调用方不必先判断
func play_ui(sfx_name: String) -> void:
	if _ui_cache.is_empty():
		_setup_ui_sfx()
	if not _ui_cache.has(sfx_name) or _ui_players.is_empty():
		return
	var now := Time.get_ticks_usec()
	if now - int(_last_ui_usec.get(sfx_name, 0)) < int(UI_MIN_INTERVAL * 1_000_000):
		return
	_last_ui_usec[sfx_name] = now
	var p := _ui_players[_ui_voice]
	_ui_voice = (_ui_voice + 1) % _ui_players.size()
	p.stream = _ui_cache[sfx_name]
	p.play()


## 延后播放：用于「敲击 + 结果」这类两层音效错开，避免叠成一团噪音
## ⚠ 计时器挂在 GameState（autoload，常驻）上，不用面板的 self ——
##   否则面板在这几十毫秒里被关掉时，await 恢复会撞上已释放的节点
func play_ui_delayed(sfx_name: String, delay: float) -> void:
	if delay <= 0.0:
		play_ui(sfx_name)
		return
	await get_tree().create_timer(delay).timeout
	play_ui(sfx_name)


# ---- UI 音效合成器（全部音效共用，保证同一音色族）----

## 通用音色：正弦主体 + 谐波，3ms 软起音，指数衰减，最后过一阶低通
## harmonics: [[倍频, 幅度], ...]；slide_to: 结束频率（0 = 不滑音）
## soft: 一阶低通系数（0 = 不滤；0.22 ≈ 1.2kHz、0.45 ≈ 3.5kHz，越小越柔）
func _ui_tone(base_hz: float, dur: float, decay: float, harmonics: Array,
		soft: float, noise_amt: float = 0.0, slide_to: float = 0.0) -> Array:
	return _normalize_peak(
		_ui_tone_raw(base_hz, dur, decay, harmonics, soft, noise_amt, slide_to), UI_PEAK)


func _ui_tone_raw(base_hz: float, dur: float, decay: float, harmonics: Array,
		soft: float, noise_amt: float = 0.0, slide_to: float = 0.0) -> Array:
	var sr := 22050
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var lp := 0.0
	var nlp := 0.0
	var phase := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		# 滑音用累积相位：直接写 sin(TAU*f*t) 在频率变化时会有相位跳变（"咔"）
		var f := base_hz if is_zero_approx(slide_to) else lerpf(base_hz, slide_to, u)
		phase += TAU * f / sr
		var s := 0.0
		for h in harmonics:
			s += sin(phase * float(h[0])) * float(h[1])
		if noise_amt > 0.0:
			nlp += 0.25 * (rng.randf_range(-1.0, 1.0) - nlp)
			s += nlp * noise_amt
		# 3ms 软起音：避免采样从 0 突跳产生爆音（界面音"突兀"的最大来源）
		s *= (1.0 - exp(-t * 320.0)) * exp(-t * decay)
		if soft > 0.0:
			lp += soft * (s - lp)
			s = lp
		out[i] = s
	return out


## 琶音：几个音依次接起来（相邻音留重叠尾巴，衔接自然）
func _ui_arp(freqs: Array, step: float, dur: float, decay: float,
		harmonics: Array, soft: float) -> Array:
	var sr := 22050
	var total := int(sr * (step * float(freqs.size() - 1) + dur))
	var buf: Array = []
	buf.resize(total)
	for i in range(total):
		buf[i] = 0.0
	for k in range(freqs.size()):
		var note := _ui_tone_raw(float(freqs[k]), dur, decay, harmonics, soft)
		var off := int(sr * step * float(k))
		for i in range(note.size()):
			if off + i < total:
				buf[off + i] = float(buf[off + i]) + float(note[i])
	return _normalize_peak(buf, UI_PEAK)


## 锤击铁器（2026-10-22 用户改口径：原来的「柔和打铁」太闷，要真的像锤子砸铁砧）
## 三层叠加：
##   ① **击打瞬态**：极短高频噪声（decay 130 → 只有头 20ms 有），给"啪"的冲击
##   ② **金属共鸣**：非谐波分音（780Hz × 1.0 / 2.4 / 3.9 / 5.6，频率越高衰减越快）→ 铁的亮泽
##   ③ **铁砧低频**：150Hz 慢衰减 → 给"沉"的支撑，不至于只有脆响
## 起音用 1ms（比界面点击的 3ms 更利落）——锤击必须"打下去"才有力度。
## 柔和度全靠最后 0.60 的一阶低通（≈4.5kHz）：保住金属感，又不出现刺耳的"叮——"。
## ⚠ 想更脆 → soft 调到 0.70；想更闷 → 0.45。改这一个数就能换风格。
func _forge_hammer_samples() -> Array:
	var sr := 22050
	var dur := 0.20
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var base := 780.0
	# [倍频（相对 780Hz）, 幅度, 衰减速率]
	var partials := [
		[150.0 / base, 0.50, 13.0],   # 铁砧本体（低频支撑）
		[1.00, 0.34, 26.0],           # 金属基音
		[2.40, 0.22, 33.0],
		[3.90, 0.13, 42.0],
		[5.60, 0.07, 52.0],
	]
	var phases: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var lp := 0.0
	var nlp := 0.0
	for i in range(n):
		var t := float(i) / sr
		var s := 0.0
		for k in range(partials.size()):
			var mult: float = partials[k][0]
			var amp: float = partials[k][1]
			var dec: float = partials[k][2]
			phases[k] = float(phases[k]) + TAU * base * mult / sr
			s += sin(float(phases[k])) * amp * exp(-t * dec)
		# 击打瞬态：噪声本身少过一道低通（0.55，保留"啪"的高频），再按 130 快速衰减
		nlp += 0.55 * (rng.randf_range(-1.0, 1.0) - nlp)
		s += nlp * 0.30 * exp(-t * 130.0)
		s *= 1.0 - exp(-t * 900.0)
		lp += 0.60 * (s - lp)
		out[i] = lp
	return _normalize_peak(out, UI_PEAK)


## 挥锤风声：低通过噪声从弱到强再收，带一点点 120Hz 的低频支撑
func _forge_swing_samples() -> Array:
	var sr := 22050
	var dur := 0.18
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		var env := sin(PI * clampf(u, 0.0, 1.0)) ** 1.4
		lp += 0.16 * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += 0.08 * (lp - lp2)
		phase += TAU * 120.0 / sr
		var s := lp2 * 0.85 * env + sin(phase) * 0.12 * env
		out[i] = s
	return _normalize_peak(out, UI_PEAK)


## 熔铸：低频炉鸣 + 缓慢渐强的砂噪，尾部收束
func _forge_melt_samples() -> Array:
	var sr := 22050
	var dur := 1.1
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8882
	var lp := 0.0
	var phase1 := 0.0
	var phase2 := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		var env := sin(PI * clampf(u, 0.0, 1.0)) ** 0.7
		lp += 0.055 * (rng.randf_range(-1.0, 1.0) - lp)
		phase1 += TAU * lerpf(64.0, 92.0, u) / sr
		phase2 += TAU * lerpf(131.0, 196.0, u) / sr
		var s := (sin(phase1) * 0.36 + sin(phase2) * 0.16) * env
		s += lp * 0.5 * env * (0.4 + u)
		out[i] = s
	return _normalize_peak(out, UI_PEAK)


## 蓄力：低频上滑 55→132Hz + 随音高抬升的空气摩擦，0.9 秒渐强
## 对应 title_screen 的 `_begin_cinematic()`（镜头推近 + 主角 charge shader 抬起）
## ⚠ 界面音「一律不加噪声」那条口径是给点击音定的；这里是过场演出音，噪声必须留，
##   否则蓄力会变成干巴巴的电子"呜"。摩擦声走一阶低通、只占 10~40% 幅度，不刺耳。
func _title_charge_samples() -> Array:
	var sr := 22050
	var dur := 0.90
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var phase := 0.0
	var lp := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		# 音高按 u² 抬升：前段几乎不动、后段明显上冲，听觉上才是"蓄"不是"滑音"
		var f := lerpf(55.0, 132.0, u * u)
		phase += TAU * f / sr
		# ⚠ 三次实测校准：基音独大时 98% 能量在 500Hz 以下，手机/笔记本根本发不出来。
		#   现在基音让位给 2~4 次谐波与摩擦层，谱重心 135→约 300Hz，仍是"低频蓄力"但听得见
		var body := sin(phase) * 0.42 + sin(phase * 2.0) * 0.30 \
			+ sin(phase * 3.0) * 0.26 + sin(phase * 4.0) * 0.20 + sin(phase * 6.0) * 0.12
		lp += lerpf(0.050, 0.220, u) * (rng.randf_range(-1.0, 1.0) - lp)
		# 尾 0.12s 收干净，交棒给 title_pull 的起音
		var tail := clampf((dur - t) / 0.12, 0.0, 1.0)
		var s := body * (0.30 + 0.70 * u * u) + lp * lerpf(0.18, 0.60, u)
		s *= (1.0 - exp(-t * 6.0)) * tail * tail
		out[i] = s
	return _normalize_peak(out, 0.52)


## 牵引呼啸：噪声过低通（截止随进度抬高）再减去慢速低通 → 带通错觉的「呼」
## 0.9 秒内摆 3 次气旋起伏；再叠一点点上滑的极轻音高给方向感
func _title_pull_samples() -> Array:
	var sr := 22050
	var dur := 1.00
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	var lp := 0.0
	var slow := 0.0
	var phase := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		lp += lerpf(0.035, 0.300, u) * (rng.randf_range(-1.0, 1.0) - lp)
		slow += 0.004 * (lp - slow)
		var air := lp - slow
		# 气旋摆动：一条直线的高频噪声听起来像漏气，必须让它自己起伏
		var swirl := 0.72 + 0.28 * sin(TAU * 3.2 * t + 0.8)
		phase += TAU * lerpf(220.0, 330.0, u) / sr
		var tone := sin(phase) * 0.06 + sin(phase * 2.02) * 0.02
		var s := air * 0.85 * swirl + tone
		var fade_in := clampf(t / 0.16, 0.0, 1.0)
		var fade_out := clampf((dur - t) / 0.18, 0.0, 1.0)
		s *= fade_in * fade_out * (0.55 + 0.45 * u)
		out[i] = s
	return _normalize_peak(out, 0.46)


## 溶解：四枚非谐波铃片整体从 G6 滑到 C5 + 高频颗粒簇（砂化感）
## 与 title_absorb_fx 的 `begin_dissolve()`（冲击波 + 光丝开始散）同一时刻
func _title_dissolve_samples() -> Array:
	var sr := 22050
	var dur := 0.55
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	# [倍频, 幅度, 衰减速率] —— 非整数倍频才有金属/琉璃的"片"感
	# ⚠ 基音别定太高：第一版 1568→523 Hz 时 >4kHz 占到 15.7%（比锤击音还刺），
	#   整体降一个八度并把颗粒压到 0.20，谱重心才落回"碎光"该在的位置
	var partials := [[1.00, 0.34, 9.0], [2.37, 0.20, 12.0], [3.91, 0.13, 16.0], [5.40, 0.08, 22.0]]
	var phases: Array = [0.0, 0.0, 0.0, 0.0]
	var hp := 0.0
	for i in range(n):
		var t := float(i) / sr
		var u := t / dur
		var base := lerpf(1046.0, 349.0, u * u)
		var s := 0.0
		for k in range(partials.size()):
			phases[k] = float(phases[k]) + TAU * base * float(partials[k][0]) / sr
			s += sin(float(phases[k])) * float(partials[k][1]) * exp(-t * float(partials[k][2]))
		# 颗粒：噪声被 sin^6 削成一簇一簇（26Hz 的稀疏率），越到后面越稀
		# 低通系数 0.35 ≈ 1.2kHz，颗粒是"砂"不是"嘶"
		hp += 0.35 * (rng.randf_range(-1.0, 1.0) - hp)
		var grain := hp * pow(maxf(0.0, sin(TAU * 26.0 * t + 0.4)), 6.0)
		s += grain * 0.20 * (1.0 - u * 0.6)
		s *= (1.0 - exp(-t * 320.0)) * exp(-t * 4.2)
		out[i] = s
	return _normalize_peak(out, 0.42)


## 收束 + 白闪：140→34Hz 下潜（前 0.35s 完成）+ 30ms 宽带瞬态 + 三枚高频闪耀
## 这一发是整段演出的重心，归一化给到 UI_PEAK 满值（其余入场音都压在 0.42~0.52）
func _title_collapse_samples() -> Array:
	var sr := 22050
	var dur := 0.85
	var n := int(sr * dur)
	var out: Array = []
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6161
	var sub_phase := 0.0
	# 中频"闷拳"：低频下潜在小喇叭上几乎发不出来的，必须补一层 1kHz 上下的冲击
	var mid := 0.0
	var spark := [[2093.0, 0.26, 6.0], [3136.0, 0.18, 8.0], [4186.0, 0.12, 11.0]]
	var spark_phase: Array = [0.0, 0.0, 0.0]
	for i in range(n):
		var t := float(i) / sr
		# 下潜曲线用 u²：前半段"砸下来"最快，后半段几乎贴在 34Hz 上震
		var u := clampf(t / 0.35, 0.0, 1.0)
		var f := lerpf(140.0, 34.0, u * u)
		sub_phase += TAU * f / sr
		var sub := sin(sub_phase) * 0.42 + sin(sub_phase * 2.0) * 0.22
		var hit := rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.50
		mid += 0.30 * (rng.randf_range(-1.0, 1.0) - mid)
		var punch := mid * exp(-t * 26.0) * 0.95
		var sk := 0.0
		for k in range(spark.size()):
			spark_phase[k] = float(spark_phase[k]) + TAU * float(spark[k][0]) / sr
			sk += sin(float(spark_phase[k])) * float(spark[k][1]) * exp(-t * float(spark[k][2]))
		# 4ms 起音（比界面点击的 3ms 稍缓，低频不能一上来就硬切）
		var s := (sub * exp(-t * 3.4) + hit + punch + sk) * (1.0 - exp(-t * 250.0))
		out[i] = s
	return _normalize_peak(out, UI_PEAK)


## 峰值归一化：这是"所有界面音效一样响"的落地手段，别绕开它直接返回采样
func _normalize_peak(samples: Array, peak: float) -> Array:
	var mx := 0.0
	for v in samples:
		mx = maxf(mx, absf(float(v)))
	if mx <= 0.0001:
		return samples
	var k := peak / mx
	for i in range(samples.size()):
		samples[i] = float(samples[i]) * k
	return samples


# ===== 调试面板数值管理 =====
func set_boss_override(prop_name: String, value: float) -> void:
	boss_debug_overrides[prop_name] = value


func get_boss_override(prop_name: String):
	return boss_debug_overrides.get(prop_name)


func has_boss_override(prop_name: String) -> bool:
	return boss_debug_overrides.has(prop_name)


func capture_boss_default(prop_name: String, value: float) -> void:
	"""仅当尚未记录默认值时，捕获该字段的脚本默认值"""
	if not boss_debug_defaults.has(prop_name):
		boss_debug_defaults[prop_name] = value


func get_boss_default(prop_name: String):
	return boss_debug_defaults.get(prop_name)


func clear_boss_overrides() -> void:
	boss_debug_overrides.clear()
