extends Node2D
## 战斗箱庭（阶段1原型）：组合玩家与原型BOSS，验证核心战斗循环
## 无UI预警、无红圈、无范围标记

const ITEM_PICKUP_SCENE := "res://scenes/items/item_pickup.tscn"
## 演武场训练木桩（SOURCE_ARENA 专用，不参与位面 / 塔战斗）
const TRAINING_DUMMY_SCENE := "res://scenes/combat/training_dummy.tscn"
## 大世界区域核心首领重战（SOURCE_WORLD_CORE）：用世界敌人脚本配置 CORE_BOSS
const WORLD_ENEMY_SCENE := "res://scenes/world/world_enemy.tscn"

# ===== 战斗 BGM（2026-10-24 用户定：三种风格都要，且按战斗随机）=====
## 三首曲子不再绑定 BOSS；每次开战从洗好的牌堆抽一首，抽完三首再重新洗牌。
## 合成器源文件见 tools/gen_battle_music.py，改曲后重跑即可。
const BGM_WUXIA := "res://assets/audio/bgm/battle_wuxia.wav"
const BGM_TENSE := "res://assets/audio/bgm/battle_tense.wav"
const BGM_EPIC := "res://assets/audio/bgm/battle_epic.wav"
const BGM_TRACKS: Array[String] = [BGM_WUXIA, BGM_TENSE, BGM_EPIC]

## 战场整体灯光调色（2026-10-27）：全屏分级，只作用于世界，不碰 HUD
const ARENA_GRADE_SHADER := "res://assets/shaders/arena_grade.gdshader"
static var _bgm_bag: Array[String] = []
var _music_player: BgmPlayer = null

var player: Node2D
var boss: Node2D
## 训练模式（演武场）：木桩 + 训练 HUD；位面 / 塔战斗为 false
var training_mode := false
## 试炼之路的局内调度器（只在 SOURCE_ROGUE 时创建）
var _rogue: RogueArena = null
var training_dummy: Node2D = null
## BOSS 入场卡开着：此时树是暂停的，ESC / C 等战斗快捷键一律让给卡片
var _intro_open := false
var _training_panel: PanelContainer = null
var _training_values: Dictionary = {}
var _training_status: Label = null
var _training_status_token := 0
## 训练面板默认整块隐藏，按 H 呼出 / 收起（2026-10-25 用户定）
var _training_hud_visible := false
## 面板收起时左上角的常驻按键提示（触屏不创建，触屏默认展开面板）
var _training_hint: Label = null
var _training_skill_panel: SkillPanel = null

# ESC 确认框是否已弹出（框内再按 ESC = 取消，不要再叠一层）
var _confirm_open := false

# 通关计时（秒）：击杀瞬间定格，用于记录本关最快通关时间
var _elapsed: float = 0.0
var _timing: bool = true

# 当前场上未拾取的掉落物（按 F 拾取离玩家最近的一个；走进范围也会自动捡）
var _drops_on_ground: Array = []
## 自动拾取节拍（2026-11-12 用户定：掉落物靠近就捡，不用按 F）
const AUTO_PICKUP_INTERVAL := 0.12
var _auto_pick_left := 0.0
## 本场实际使用的战场美术 id（_setup_ground_bg 写入，探针验模式隔离用）
var ground_visual_id: String = ""

# 本次战斗待感悟的功法 id（塔首杀才有；为空 = 无感悟环节）
var _pending_insight: Array = []

# 通关后左上角出现的「返回原初位面」按钮
var _return_button: Button = null

# ===== 连败提醒（2026-10-27 用户定）=====
## 同一只 BOSS 连续死到这个次数，就在战败界面中央弹出「怎么变强」提示
const BOSS_FAIL_HINT_AT := 2
## 提示横幅整条可点，右侧「看指引」令签做呼吸（与突破提醒同一套手感）
var _grow_banner: Control = null
var _grow_button: Button = null
## 它打开的指引书面板：开着时 ESC 让给面板，战斗场景不要再弹「放弃战斗」确认框
var _guide_panel: GuidePanel = null

# ===== 虎妖战败 · 「封印松动」取剑提示（2026-11-12 用户定）=====
## 虎妖死够两次、且玩家还没拿到石台剑时，**每次**战败都弹一张可点的卡；
## 点卡 = 回原初位面并直接停在「万界秘境 · 苍澜大陆 · 青岚野」那一页。
const SWORD_HINT_DEATHS := 2
const SWORD_HINT_BOSS := "boss_huyao"
const SWORD_HINT_ITEM := "eq_wentian_jian"
var _sword_hint: Control = null

# ===== 通关后的收尾状态（2026-10-23）=====
## BOSS 已被击杀 = 战斗结束。ESC 从此不再问「要不要放弃战斗」。
var _cleared: bool = false
## 功法感悟面板是否正开着（面板自己处理 ESC，这里只用来防重复弹 / 防提前出返回按钮）
var _insight_open: bool = false
## 结算大字幕的节点与补间：ESC 提前跳过时要能把它们掐掉
var _clear_banner_label: Label = null
var _clear_banner_tween: Tween = null

@onready var boss_spawn: Marker2D = $BossSpawn
@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var time_label: Label = $HUD/TimeLabel
@onready var momentum_bar: ProgressBar = $HUD/MomentumBar
@onready var momentum_label: Label = $HUD/MomentumLabel
## 左上角「基础操作」竖排块（2026-11-12 用户定：从底部整行挪到左上角竖排，
## 战斗中常驻、不跟其它按钮抢位置）。节点由 _build_key_hint() 现建。
var _key_hint: Control = null
## 垫在提示文字下方的半透明黑背景条（与文字**一起**渐隐，否则会剩一条黑带）

## 按键提示的停留时长（秒）与渐隐时长（秒）

# ===== 战斗内功法快捷栏 =====
## 4 个主动功法槽横排屏幕底部居中；进场时按当前装配构建，每帧刷新冷却。
## ⚠ 按键顺序必须与 player.gd 的 SKILL_KEYS / skill_panel.gd 的 SLOT_KEYS 一致，
##   改一处就要改另外两处。
const SKILL_BAR_KEYS: Array[String] = ["Q", "E", "R", "T"]
const SKILL_SLOT_SIZE := Vector2(48.0, 48.0)     ## 单格尺寸
const SKILL_SLOT_GAP := 6.0                       ## 格间距
const SKILL_ICON_SIZE := Vector2(36.0, 36.0)     ## 格内图标
## 资源不足时的图标灰化（灵力 / 精力不够 → 去色压暗，见 _update_slot_disabled）
const SKILL_GRAY_SHADER := "res://assets/shaders/ui_gray.gdshader"
## 灰化强度：1.0 全灰 + 压暗三成，既看得出「按不出来」，又还认得出是哪个技能
const SKILL_GRAY_MIX := 1.0
const SKILL_GRAY_DIM := 0.30
## 视口尺寸（与 project.godot 的窗口分辨率一致）
## ⚠ 不要用 get_viewport().get_visible_rect().size 算 HUD 位置：
##   实测该接口在此环境会返回 1280×1280，快捷栏会被推到屏幕外。
const VIEW_W := 1280.0
const VIEW_H := 720.0

## ===== 万界塔：反复挑战的血量成长 =====
## 规则与数值都在 CharacterData.tower_hp_multiplier()（塔面板也用它显示，避免两处各写一份）：
## 同一层每通关一次 +基础血量 10%，最多 +100%（2 倍封顶）；次数取 clear_count，失败重打不涨。

## 万界秘境 BOSS 掉的锻造晶石数（2026-11-10 用户定：首杀 9）。
## 重复挑战是允许的（结算只停发万界本源），重复档与塔的「之后」档对齐取 3；
## 要改成每次都 9，把 REPEAT 改成 9 即可。
const DOMAIN_FIRST_KILL_CRYSTALS := 9
const DOMAIN_REPEAT_CRYSTALS := 3

## ===== 战场边界（2026-10-22 地图放大到 2 倍后补上）=====
## 地图变大以后，玩家能一路走到地面之外、看到空白（旧版 1800×1013 也有这问题）。
## 做法与主城屏障同源：Camera2D.limit 管镜头 + 四面隐形墙管人。
## ⚠ 墙放在**第 6 层（值 32）**：玩家 mask 已含 2/8（BOSS、天剑），
##   墙若放第 1 层会被 BOSS 投射物（mask 1）当成命中目标吃掉，所以专门开一层。
const WALL_LAYER := 32
## 墙相对地图边缘内缩的距离：让镜头贴边时还能看到一圈地面，不会「一脚踩到虚空」
const WALL_INSET := 40.0
## 墙的厚度（往地图外侧长，不占可视区域）
const WALL_THICKNESS := 80.0
## ===== 边缘视野（2026-10-30 用户定：贴墙时玩家也必须在视野中心）=====
## 相机不再硬夹在地图矩形上，允许越过地图半屏；场外由边界雾遮住。
## 雾从隐形墙外沿开始，向场内严格为 0，不压暗可走区域。
const EDGE_FOG_SHADER := "res://assets/shaders/arena_edge_fog.gdshader"
const EDGE_FOG_BAND := 280.0
## 地面向外多铺的距离：只需覆盖雾的淡入段，浓雾之外看不见地面
const EDGE_FOG_GROUND_PAD := 520.0
## 雾面本身向外多铺的距离：要盖住相机极限外扩 + 天剑拉远后的可见范围
const EDGE_FOG_RECT_PAD := 2000.0
## 地图半宽高（= 世界原点为中心的地图矩形的一半）；Vector2.ZERO = 还没算出来
## ⚠ 边界墙只拦玩家：BOSS 的 collision_mask 是 1，**碰不到第 6 层的墙**。
##   所以 BOSS 侧要靠 BossBase.arena_half_extents 做逻辑钳制（虎妖后闪曾被推出地图外）。
var arena_half_extents: Vector2 = Vector2.ZERO
## 快捷栏节点池：每项 { box, icon, key, cover, mask, cd, sid, aura }
##   aura = 剑意就绪光环（SkillReadyAura，挂在 row 下的 sibling，位置每帧对齐格子中心）
var _skill_slots: Array = []

# ===== 负面状态显示（2026-10-23 用户定）=====
## 挂在**第一个功法格正上方**，从下往上堆：新获得的 debuff 出现在最上面（旧的被顶下去），
## 这样多个 debuff 同时存在也不会互相盖住。
var _debuff_box: VBoxContainer = null
## id -> { panel, label }
var _debuff_rows: Dictionary = {}
## 增益状态列：挂在**第一个法宝格上方、左端对齐法宝栏**（2026-10-23 用户定）
var _buff_box: VBoxContainer = null
var _buff_rows: Dictionary = {}
## 标签宽度
const DEBUFF_ROW_WIDTH := 140.0
## 标签底边与技能栏顶部的间距
const DEBUFF_BOX_GAP := 6.0
## 列表区上边界留白
## ⚠ **不要写死列表高度**（第一版固定 190px）：底对齐容器在内容超出高度时会从顶部往上溢出，
##   同时中三四个 debuff 就会飘到技能栏外面。这里让容器一直顶到屏幕上沿，
##   内容永远从底部往上堆 —— 中多少个都完整显示、且都在容器内。
const DEBUFF_BOX_TOP_MARGIN := 8.0

# ===== 法宝展示栏（2026-10-21 用户定：放在技能栏左边）=====
## 3 格对应法宝槽 1/2/3，显示图标 + 按键数字 + 召唤冷却剩余秒数
const TREASURE_SLOT_SIZE := Vector2(46.0, 46.0)
const TREASURE_SLOT_GAP := 6.0
## 法宝栏与技能栏之间的间距
const TREASURE_BAR_MARGIN := 14.0
var _treasure_slots: Array = []     # 每项 { box, icon_wrap, cd, last_id }


func _ready() -> void:
	# 安卓返回键在本场景 = 后退（ESC 语义：放弃本场 / 退出试炼 / 通关收尾），
	# 见 GameState.handle_go_back()
	GameState.back_uses_esc = true
	# 演武场 = 训练木桩模式；位面 / 万界塔 = 原战斗流程
	training_mode = BattleResolver.current_source() == BattleResolver.SOURCE_ARENA
	# BOSS 入场卡：位面 / 塔每次进战都亮卡（C 重开那一次跳过）；
	# 没有图鉴卡面的塔层不亮，走原来的开场标题字
	var skip_intro := BattleResolver.consume_intro_skip()
	var intro_entry: Dictionary = {}
	var rogue_mode := BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE
	# 伤害统计（2026-11-12）：只给真实位面战 / 万界塔记账（试炼/演武场不记）
	if not rogue_mode and BattleResolver.current_source() in [
			BattleResolver.SOURCE_DOMAIN, BattleResolver.SOURCE_TOWER]:
		DamageMeter.begin()
	if not training_mode and not skip_intro and not rogue_mode:
		intro_entry = CodexDB.boss_entry(String(GameState.battle_context.get("boss_id", "")))
	# 触屏：切到战斗布局（摇杆 + 攻/闪/弹 + 功法 1~4 + 法宝 1~3 + 拾取/重开/返回）
	VirtualPad.set_context("combat")
	# 必须先替换 BOSS：后续所有绑定与血条同步都以最终 BOSS 为准
	_spawn_boss_by_context()
	_setup_ground_bg()
	player = $Player
	boss = $Boss
	player.player_died.connect(_on_player_died)

	if training_mode:
		# 训练场：木桩不攻击，不接 BOSS 血条 / 阶段 / 调试面板绑定
		_setup_training_mode()
	else:
		_bind_boss(boss)

		# 显示本次战斗的来源（位面 BOSS / 万界塔投影）
		$HUD/BattleTitleLabel.text = BattleResolver.battle_title()
		if intro_entry.is_empty():
			_show_opening_announce()

	_build_skill_bar()
	_build_treasure_bar()
	_style_hud()
	_build_key_hint(rogue_mode)
	_start_battle_music()
	if rogue_mode:
		_setup_rogue()
	if not intro_entry.is_empty():
		_start_boss_intro(intro_entry)
	_setup_tutorial()


# ===================== 新手指引（2026-11-10）=====================
## 战斗章节在第 2 章：首次进 BOSS 战就开；弹刀教学只在
## 「首次打凡界第一位面 BOSS 且 c2_parry 没做完」时喂招。
## ⚠ 暂停期间玩家 _input 不生效，右键由 TutorialOverlay（ALWAYS）接住后回调到这里，
##   这里代按一次 _start_parry 再解除暂停。
## ⚠⚠ 光「代按」不够（2026-11-10 端到端自检抓到）：暂停冻住的是**整个前摇**，
##   解除后 BOSS 还要挥 0.4~0.8 秒才落招，而弹反窗口只有 0.22 秒 ——
##   玩家按了右键照样挨打，等于教了个寂寞。所以代按时把余下前摇压到
##   TUT_PARRY_LEAD，落招一定在窗口内。**只动教学场次的前摇，不动弹反窗口与伤害。**
const TUT_PARRY_TIMES := 3
## 解除暂停后到落招的间隔（必须明显小于 player.PARRY_WINDOW = 0.22）
const TUT_PARRY_LEAD := 0.09

var _tut_parry_left := 0
var _tut_parry_hooked := false
## 当前这次暂停是不是「等玩家按右键弹刀」
var _tut_waiting_parry := false


## 离场交还返回键：新场景没声明时，返回键回到「退出确认」而不是把战斗语义带过去
func _exit_tree() -> void:
	GameState.back_uses_esc = false


func _setup_tutorial() -> void:
	if training_mode:
		return
	var src := String(GameState.battle_context.get("source", ""))
	Tutorial.note("battle_started:" + src)
	Tutorial.maybe_start("battle")
	if src != BattleResolver.SOURCE_DOMAIN:
		return
	if Tutorial.is_done("c2_parry"):
		return
	_tut_parry_left = TUT_PARRY_TIMES
	_tut_parry_hooked = true
	(boss as BossBase).attack_windup.connect(_on_tut_windup)
	Tutorial.pause_parry.connect(_on_tut_parry_pressed)
	Tutorial.pause_skip.connect(_on_tut_parry_skipped)


func _on_tut_windup(kind: String, _windup: float) -> void:
	if not _tut_parry_hooked or _tut_parry_left <= 0:
		return
	# 只在这一步还没学会时喂招；玩家跳过之后不再暂停
	if not Tutorial.is_active_step("c2_parry"):
		return
	# ⚠ 只教「物理近战」：法术 / 元素招弹不了；
	#   物理投掷（刀气）虽然能弹，但**飞行时间远大于 0.22 秒窗口**，
	#   暂停里按完右键，刀气还在天上飞，窗口早就关了 → 教一次挨一次（自检实测掉血）。
	if kind != "physical_melee":
		return
	_tut_parry_left -= 1
	_tut_waiting_parry = true
	Tutorial.pause_prompt(_tut_parry_prompt())


## 喂招提示的按键名：手游按不到「右键」，这里必须说手上那颗键
## （2026-11-13 用户报：指引喊「按右键弹开」，手游点「弹」没反应，卡死在这一步）
func _tut_parry_prompt() -> String:
	if VirtualPad.is_touch_enabled():
		return "它抬手了 —— 点右下的「弹」键弹开"
	return "它抬手了 —— 按右键弹开"


func _on_tut_parry_pressed() -> void:
	if not Tutorial.is_pause_prompt():
		return
	if _tut_waiting_parry:
		_tut_waiting_parry = false
		_clamp_windup_for_teaching()
	player.call("_start_parry")
	Tutorial.resume()


func _on_tut_parry_skipped() -> void:
	if not Tutorial.is_pause_prompt():
		return
	# 跳过 = 放弃这一次，攻击照常落下（会掉血）。不给无敌，这是玩家自己选的代价。
	_tut_waiting_parry = false
	Tutorial.resume()


## 把 BOSS 余下的前摇压到 TUT_PARRY_LEAD（只在教学场次、且确实处于前摇时）
func _clamp_windup_for_teaching() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var b := boss as BossBase
	if b == null or b.state != BossBase.BossState.WINDUP:
		return
	if b.state_timer > TUT_PARRY_LEAD:
		b.state_timer = TUT_PARRY_LEAD


# ===================== 战斗 BGM =====================
## 三首战斗曲随机轮换：每次开战抽一首，三首抽完自动重新洗牌；
## 不按 BOSS / 关卡固定，所以同一关重复挑战也会换曲。
func _battle_music_path() -> String:
	if _bgm_bag.is_empty():
		for path in BGM_TRACKS:
			_bgm_bag.append(path)
		_bgm_bag.shuffle()
	return _bgm_bag.pop_back()


func _start_battle_music() -> void:
	if _music_player != null:
		return
	_music_player = BgmPlayer.new()
	_music_player.name = "BattleMusic"
	add_child(_music_player)
	_music_player.play_loop(_battle_music_path(),
		BgmPlayer.BATTLE_VOLUME_DB, BgmPlayer.DEFAULT_FADE_IN)


func _fade_out_battle_music(duration: float = BgmPlayer.DEFAULT_FADE_OUT) -> void:
	if _music_player != null:
		_music_player.fade_out(duration)


## 战场地面（2026-10-22 第二轮：**单张 TextureRect + texture repeat**）
## 做法：把原图先按 `tile_width` 缩放成一块「2×2 镜像块」，再让一个 TextureRect 以
##   `texture_repeat = ENABLED` + `stretch_mode = TILE` 铺满整个战场 ——
##   **TextureRect 拉多大，纹理就自动铺多大**，改地图大小只改 ArtDB 的 `map_tiles`。
## 为什么先烘一张 2×2 镜像块：原图四边并不严丝合缝（实测左右差 8~16、上下差 7~16），
##   直接 repeat 会出现淡色接缝；镜像块内部接缝取的是同一像素列/行，天然无缝，
##   再往外 repeat 时只重复「镜像块」的边界，同样是无缝的。
## 代价：战场只画 1 个节点 / 1 次绘制调用（旧版 9 个 Sprite2D），地图放大不增加开销。
## 美术全在 ArtDB.VISUALS 的 bg_* 条目里；改图/改格子大小只改那张表。
func _setup_ground_bg() -> void:
	var ground := get_node_or_null("Ground")
	if ground == null:
		return
	for c in ground.get_children():
		ground.remove_child(c)
		c.queue_free()

	var boss_id := String(GameState.battle_context.get("boss_id", ""))
	var visual_id := "bg_primordial_realm"
	match boss_id:
		"boss_huyao":
			visual_id = "bg_huyao_arena"
		"boss_01":
			visual_id = "bg_daoke_arena"
		"boss_01_c":
			visual_id = "bg_jianke_arena"
		"boss_02":
			visual_id = "bg_liangyi_arena"
		"boss_02_b":
			visual_id = "bg_dingzhen_arena"
		"boss_02_c":
			visual_id = "bg_qijun_arena"
		"boss_03":
			visual_id = "bg_chixiao_arena"
		"boss_03_b":
			visual_id = "bg_lizhao_arena"
		"boss_03_c":
			visual_id = "bg_calamity_arena"
		"boss_04":
			visual_id = "bg_zhaoying_arena"
		"boss_04_b":
			visual_id = "bg_zhaoying_lamp_arena"
		"boss_04_c":
			visual_id = "bg_zhaoying_fold_arena"
		"world_core_lianqi":
			# 青岚野核心首领重战：沿用虎妖的夜林战场（同属练气区林地氛围）
			visual_id = "bg_huyao_arena"
		"world_core_zhuji":
			# 云隐谷核心重战：冷杉林下 + 谷心苔石圈
			visual_id = "bg_cangjiao_arena"
		"world_core_shihou":
			# 幽冥灵墟核心重战：冷紫石道与青裂地缝
			visual_id = "bg_youming_arena"

	# 试炼之路：整局固定「无尽试炼台」，不跟着本层抽到的 BOSS 换战场。
	# ⚠ 放在 match 之后覆盖（而不是把 match 整段包进 else），这样主模式的
	#   BOSS→战场映射一行都不用动，模式隔离只在这一处。
	if RogueRun.active:
		visual_id = "bg_rogue_trial"

	# 暴露给探针 / 调试：本场实际用的是哪套战场美术
	ground_visual_id = visual_id
	var cfg := ArtDB.get_visual(visual_id)
	_setup_arena_grade(cfg)
	_setup_center_decal(cfg)
	var tex_path := String(cfg.get("texture", ""))
	var tile_w := float(cfg.get("tile_width", 0.0))
	# `map_tiles` = 战场横向由几个 tile_width 宽的格子组成；旧的 tile_grid 作兼容兜底
	var map_tiles := int(cfg.get("map_tiles", cfg.get("tile_grid", 0)))
	if map_tiles < 1 or tile_w <= 0.0 or tex_path == "" or not ResourceLoader.exists(tex_path):
		# 没配平铺（或贴图缺失）→ 退回单张 SkinVisual，保证永远有画面
		var skin := SkinVisual.new()
		skin.name = "Skin"
		skin.visual_id = visual_id
		ground.add_child(skin)
		skin.refresh()
		skin.modulate = cfg.get("tint", Color.WHITE)
		_apply_arena_bounds(skin.visual_rect.size)
		_setup_edge_fog(skin.visual_rect.size, cfg)
		return

	var tiled := _make_mirror_tile_texture(tex_path, tile_w)
	if tiled == null:
		var fallback := SkinVisual.new()
		fallback.name = "Skin"
		fallback.visual_id = visual_id
		ground.add_child(fallback)
		fallback.refresh()
		fallback.modulate = cfg.get("tint", Color.WHITE)
		_apply_arena_bounds(fallback.visual_rect.size)
		_setup_edge_fog(fallback.visual_rect.size, cfg)
		return

	# 镜像块 = 2×2 个格子，所以单格高度取贴图高度的一半
	var tile_h := float(tiled.get_height()) * 0.5
	var map_size := Vector2(tile_w * float(map_tiles), tile_h * float(map_tiles))
	var half := map_size * 0.5

	var rect := TextureRect.new()
	rect.name = "TiledBG"
	rect.texture = tiled
	# 这两行就是「repeat」的全部：贴图循环 + 平铺拉伸
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rect.stretch_mode = TextureRect.STRETCH_TILE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 整体明暗/偏色：只改 ArtDB 的 tint，**不动原图**（冰砖那张原图近白，太亮）
	rect.modulate = cfg.get("tint", Color.WHITE)
	# Control 挂在 Node2D 下没有 Control 父级，锚点固定左上、用 offset 定位置与尺寸，
	# 否则窗口尺寸变化时会被当成「相对视口」重新布局
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 0.0
	rect.anchor_bottom = 0.0
	rect.offset_left = -half.x - EDGE_FOG_GROUND_PAD
	rect.offset_top = -half.y - EDGE_FOG_GROUND_PAD
	rect.offset_right = half.x + EDGE_FOG_GROUND_PAD
	rect.offset_bottom = half.y + EDGE_FOG_GROUND_PAD
	ground.add_child(rect)

	_apply_arena_bounds(map_size)
	_setup_edge_fog(map_size, cfg)


## 场外边界雾：镜头越界时看到的那一圈地面由它收边。
## 雾色直接取当前战场的暗角色，跟整体分级同源；mist 只是同色提亮，不另加冷蓝。
func _setup_edge_fog(map_size: Vector2, cfg: Dictionary) -> void:
	var ground := get_node_or_null("Ground")
	if ground == null or map_size.x <= 1.0 or map_size.y <= 1.0:
		return
	var old := ground.get_node_or_null("EdgeFog")
	if old != null:
		ground.remove_child(old)
		old.queue_free()
	var half := map_size * 0.5
	var pad := Vector2(EDGE_FOG_RECT_PAD, EDGE_FOG_RECT_PAD)
	var fog := ColorRect.new()
	fog.name = "EdgeFog"
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.anchor_left = 0.0
	fog.anchor_top = 0.0
	fog.anchor_right = 0.0
	fog.anchor_bottom = 0.0
	fog.offset_left = -half.x - pad.x
	fog.offset_top = -half.y - pad.y
	fog.offset_right = half.x + pad.x
	fog.offset_bottom = half.y + pad.y
	var mat := ShaderMaterial.new()
	var fog_shader := load(EDGE_FOG_SHADER) as Shader
	if fog_shader == null:
		return
	mat.shader = fog_shader
	var grade: Dictionary = cfg.get("grade", {})
	var fog_base: Color = grade.get("vignette_color", Color(0.02, 0.03, 0.045, 1.0))
	fog_base.a = 1.0
	# 远雾压向暗角同色但略抬一点，近墙的淡雾同色提亮；两边都不离战场调色
	var fog_col := fog_base.lerp(Color(0.16, 0.18, 0.21, 1.0), 0.58)
	var mist_col := fog_base.lerp(Color(0.82, 0.86, 0.90, 1.0), 0.62)
	mat.set_shader_parameter("rect_px", (half + pad) * 2.0)
	# 雾边落在隐形墙外沿（不是地图矩形边），人贴墙时脚下仍是干净地面
	mat.set_shader_parameter("arena_half", half - Vector2(WALL_INSET, WALL_INSET))
	mat.set_shader_parameter("band_px", EDGE_FOG_BAND)
	mat.set_shader_parameter("fog_color", fog_col)
	mat.set_shader_parameter("mist_color", mist_col)
	fog.material = mat
	ground.add_child(fog)


## 场地中央贴花（2026-10-28）：**只画一次，不拉伸、不平铺**。
## 太极盘是「场地中心」而不是地面材质 —— 铺在平贴图里会跟着重复 N 次，
## 那样一眼就假。所以单独挂一个 Sprite2D 在 Ground 下、z_index 高于平铺层。
## 全部配置在 ArtDB 的 bg_*_arena 条目：`decal`（贴图）/ `decal_size`（世界直径）
## / `decal_opacity`。没配 decal 的战场（其他 BOSS）不会多出任何节点。
func _setup_center_decal(cfg: Dictionary) -> void:
	var ground := get_node_or_null("Ground")
	if ground == null:
		return
	var path := String(cfg.get("decal", ""))
	var size := float(cfg.get("decal_size", 0.0))
	if path == "" or size <= 0.0 or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "CenterDecal"
	spr.texture = tex
	spr.centered = true
	spr.position = Vector2.ZERO
	# 等比缩到目标直径（贴花是正圆，只按宽度算比例即可）
	var s := size / maxf(1.0, float(tex.get_width()))
	spr.scale = Vector2(s, s)
	# 只降 alpha 是不够的：太极盘的白石半边本身就比地面亮一大截，压不下去就会
	# 和人物抢焦点。所以再乘一个 `decal_tint` 把它压暗并统一到地面的冷灰调。
	var tint: Color = cfg.get("decal_tint", Color.WHITE)
	spr.modulate = Color(tint.r, tint.g, tint.b, float(cfg.get("decal_opacity", 1.0)))
	spr.z_index = 1          # 盖在平铺地面之上，但仍在人物之下（Ground 整体在下）
	ground.add_child(spr)


## 整体灯光调色：把分级层挂在 HUD 层最底下（z_index -100），
## 它读屏幕纹理时 HUD 还没画，所以只调「地面 + 人物 + 特效」，UI 保持原色。
## 参数全部来自 ArtDB 的 bg_*_arena.grade；没有配 grade 的战场（演武场）不生效。
func _setup_arena_grade(cfg: Dictionary) -> void:
	var grade: Dictionary = cfg.get("grade", {})
	if grade.is_empty():
		return
	var hud := $HUD
	var old := hud.get_node_or_null("ArenaGrade")
	if old != null:
		old.queue_free()
	var rect := ColorRect.new()
	rect.name = "ArenaGrade"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -100
	var mat := ShaderMaterial.new()
	mat.shader = load(ARENA_GRADE_SHADER)
	mat.set_shader_parameter("exposure", float(grade.get("exposure", 1.0)))
	mat.set_shader_parameter("contrast", float(grade.get("contrast", 1.0)))
	mat.set_shader_parameter("saturation", float(grade.get("saturation", 1.0)))
	mat.set_shader_parameter("lift", float(grade.get("lift", 0.0)))
	mat.set_shader_parameter("gamma", float(grade.get("gamma", 1.0)))
	mat.set_shader_parameter("shadow_tint", grade.get("shadow_tint", Color.WHITE))
	mat.set_shader_parameter("highlight_tint", grade.get("highlight_tint", Color.WHITE))
	mat.set_shader_parameter("vignette", float(grade.get("vignette", 0.0)))
	mat.set_shader_parameter("vignette_color", grade.get("vignette_color", Color.BLACK))
	mat.set_shader_parameter("light_dir", grade.get("light_dir", Vector2(0.0, -1.0)))
	mat.set_shader_parameter("light_strength", float(grade.get("light_strength", 0.0)))
	rect.material = mat
	hud.add_child(rect)
	hud.move_child(rect, 0)


## 烘一块 2×2 镜像贴图（左右翻 / 上下翻 / 双翻），尺寸 = 2 个 tile_width 宽
## 缓存只留**当前这一张**：后台应用多、内存紧张时，同时攒 3~4 张（各 3 MB）纯属浪费
static var _mirror_tile_cache: Dictionary = {}

func _make_mirror_tile_texture(tex_path: String, tile_w: float) -> Texture2D:
	var key := "%s@%d" % [tex_path, int(round(tile_w))]
	if _mirror_tile_cache.has(key):
		return _mirror_tile_cache[key]
	# 换图了：旧的那张没有用，先释放
	_mirror_tile_cache.clear()
	# ⚠ 必须用 CACHE_MODE_IGNORE：原图 2730×1536（≈16 MB）只在烘焙时用一次，
	#   走普通 load() 会被 ResourceLoader 缓存住，白白占内存（后台开一堆应用时最要命）
	var src := ResourceLoader.load(tex_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return null
	var tw := int(round(tile_w))
	var th := int(round(float(img.get_height()) * float(tw) / float(maxf(1.0, float(img.get_width())))))
	img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	# 四个象限：左上原样、右上左右翻、左下上下翻、右下双翻
	var q_tr: Image = img.duplicate()
	q_tr.flip_x()
	var q_bl: Image = img.duplicate()
	q_bl.flip_y()
	var q_br: Image = img.duplicate()
	q_br.flip_x()
	q_br.flip_y()
	var out := Image.create_empty(tw * 2, th * 2, false, img.get_format())
	var cell := Rect2i(0, 0, tw, th)
	out.blit_rect(img, cell, Vector2i(0, 0))
	out.blit_rect(q_tr, cell, Vector2i(tw, 0))
	out.blit_rect(q_bl, cell, Vector2i(0, th))
	out.blit_rect(q_br, cell, Vector2i(tw, th))
	var tex := ImageTexture.create_from_image(out)
	_mirror_tile_cache[key] = tex
	return tex


## 战场边界：镜头限制在地图矩形内 + 四面隐形墙拦住玩家
## ⚠ 只在**有地图尺寸**时调用；地图放大后不加这层，玩家会走出地面看到空白
func _apply_arena_bounds(map_size: Vector2) -> void:
	if map_size.x <= 1.0 or map_size.y <= 1.0:
		return
	var half := map_size * 0.5
	arena_half_extents = half
	# 登记到 group：后加入的节点（法宝召唤出来的友军 BOSS）要能自己找回边界，
	# 见 BossBase._sync_arena_bounds()
	if not is_in_group("combat_arena"):
		add_to_group("combat_arena")

	# ① 镜头：限制放宽到地图外一屏，玩家贴墙时相机仍能跟到人身上（人始终居中）；
	#    越界看到的一圈地面由 EdgeFog 收边。见 EDGE_FOG_* 常量。
	var p := get_node_or_null("Player")
	if p != null:
		var cam := p.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			var view_half := get_viewport().get_visible_rect().size * 0.5
			if view_half.x < 1.0 or view_half.y < 1.0:
				view_half = Vector2(1280.0, 720.0) * 0.5
			var pad := view_half + Vector2(64.0, 64.0)
			cam.limit_left = int(-half.x - pad.x)
			cam.limit_top = int(-half.y - pad.y)
			cam.limit_right = int(half.x + pad.x)
			cam.limit_bottom = int(half.y + pad.y)

	# ② 四面墙：内缩 WALL_INSET，厚度往地图外侧长，不占可视区域
	var body := StaticBody2D.new()
	body.name = "ArenaWalls"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	var inner_x := half.x - WALL_INSET
	var inner_y := half.y - WALL_INSET
	var t := WALL_THICKNESS
	_add_arena_wall(body, Vector2(0.0, -inner_y - t * 0.5), Vector2(half.x * 2.0, t))
	_add_arena_wall(body, Vector2(0.0, inner_y + t * 0.5), Vector2(half.x * 2.0, t))
	_add_arena_wall(body, Vector2(-inner_x - t * 0.5, 0.0), Vector2(t, half.y * 2.0))
	_add_arena_wall(body, Vector2(inner_x + t * 0.5, 0.0), Vector2(t, half.y * 2.0))

	# ③ BOSS 侧同步注入：墙拦不住 BOSS（mask=1 不含 WALL_LAYER），
	#    它自己按这个矩形钳制「后闪 / 突进 / 瞬移」的落点
	var b := get_node_or_null("Boss")
	if b != null and b.has_method("set_arena_bounds"):
		b.call("set_arena_bounds", half)


func _add_arena_wall(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


# ===================== 法宝展示栏（技能栏左边） =====================

## 3 个格子对应法宝槽 1/2/3：图标 + 左上角按键数字 + 召唤冷却秒数
## ⚠ 与技能栏同一套绝对定位（HUD 是 CanvasLayer，不能用 anchor 预设）
func _build_treasure_bar() -> void:
	for e in _treasure_slots:
		if is_instance_valid(e.get("box")):
			e["box"].queue_free()
	_treasure_slots.clear()

	var n := 3
	var bar_w := float(n) * TREASURE_SLOT_SIZE.x + float(n - 1) * TREASURE_SLOT_GAP
	var skill_n := SKILL_BAR_KEYS.size()
	var skill_w := float(skill_n) * SKILL_SLOT_SIZE.x + float(skill_n - 1) * SKILL_SLOT_GAP
	var skill_left := (VIEW_W - skill_w) * 0.5
	var left := skill_left - TREASURE_BAR_MARGIN - bar_w

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TREASURE_SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = left
	row.offset_right = left + bar_w
	row.offset_top = VIEW_H - TREASURE_SLOT_SIZE.y - 4.0
	row.offset_bottom = VIEW_H - 4.0
	$HUD.add_child(row)

	# buff 列要靠法宝栏的位置来定位 —— 等 row 建好再挂
	_build_buff_box(left, row.offset_top)

	for i in n:
		var box := PanelContainer.new()
		box.custom_minimum_size = TREASURE_SLOT_SIZE
		box.clip_contents = true
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tsb := UIKit.slot_style(false)
		UIKit.apply_elevation(tsb, UIKit.ELEV_CARD)
		box.add_theme_stylebox_override("panel", tsb)
		UIKit.edge_light(box, 3.0)
		box.tooltip_text = "法宝槽 %d：战斗中按 %d 使用" % [i + 1, i + 1]
		row.add_child(box)

		var layer := Control.new()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(layer)

		var icon_wrap := CenterContainer.new()
		icon_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(icon_wrap)

		# 快捷键角标是次要信息：降饱和 + 柔投影，不占用最高亮度的强调色
		var key := UIKit.label(str(i + 1), UIKit.F_BADGE, UIKit.muted(UIKit.C_ACCENT, 0.34))
		UIKit.soft_text_shadow(key, 0)
		key.position = Vector2(3.0, 0.0)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(key)

		var cd := UIKit.label("", UIKit.F_BADGE, Color(1.0, 1.0, 1.0, 1.0))
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(cd)

		# ⚠ 初值不能写 ""：空槽的 id 也是 ""，会被「内容没变」判断跳过 → 永远不出「空」字
		_treasure_slots.append({"box": box, "icon_wrap": icon_wrap, "cd": cd, "last_id": "__init__"})


## 每帧刷新：槽位内容变了才重建图标，冷却只改文字与透明度
func _update_treasure_bar() -> void:
	if _treasure_slots.is_empty():
		return
	for i in _treasure_slots.size():
		var e: Dictionary = _treasure_slots[i]
		var item: Dictionary = CharacterData.get_equipped("treasure_%d" % (i + 1))
		var tid := String(item.get("id", ""))
		var wrap: Control = e.get("icon_wrap")

		if String(e.get("last_id", "")) != tid:
			e["last_id"] = tid
			UIKit.clear_children(wrap)
			if item.is_empty():
				wrap.add_child(UIKit.label("空", UIKit.F_SMALL, UIKit.C_DISABLE))
			else:
				wrap.add_child(UIKit.equip_icon(item, Vector2(26, 26)))

		var left_cd := 0.0
		if tid != "" and player != null and player.has_method("treasure_status_left"):
			left_cd = float(player.call("treasure_status_left", tid))
		var cd_label: Label = e.get("cd")
		cd_label.visible = left_cd > 0.05
		if left_cd > 0.05:
			cd_label.text = "%d" % int(ceilf(left_cd))
		wrap.modulate = Color(1.0, 1.0, 1.0, 0.35) if left_cd > 0.05 else Color.WHITE
		var box: PanelContainer = e.get("box")
		box.add_theme_stylebox_override("panel", UIKit.slot_style(not item.is_empty()))


# ===================== 功法快捷栏 =====================

## 构建战斗内功法快捷栏：按当前装配生成 4 个格子，横排屏幕底部居中
## 全部代码构建（不进 tscn）—— 装配是运行期数据，进场景时才确定
func _build_skill_bar() -> void:
	# 先清掉旧的（重开战斗 / 调试改装配后重建）
	for e in _skill_slots:
		if is_instance_valid(e.get("box")):
			e["box"].queue_free()
		# 光环是 row 的 sibling（见下方构建处），不会随 box 释放，必须显式销毁
		if is_instance_valid(e.get("aura")):
			e["aura"].queue_free()
	_skill_slots.clear()
	# ⚠ 11-12：试炼换符后会重新调用本函数（槽值缓存必须刷新），旧的 row 容器不会随
	#   box 一起消失 —— 不摘掉它，每换一次符就在 HUD 下多挂一个空 HBoxContainer。
	#   必须先 remove_child 再 queue_free：只 queue_free 的话旧节点**本帧还挂在 HUD 下**，
	#   同名新 node 会被顶成自动改名（@Control@…），按名字就再也找不回来。
	#   所以认 **meta 不认 name**：meta 不受改名影响，name 只是给人看的。
	for c in $HUD.get_children():
		if c.has_meta("skill_bar_row"):
			$HUD.remove_child(c)
			c.queue_free()

	# ⚠ HUD 是 CanvasLayer，它的 Control 子节点**不能用 anchor 预设**（基准尺寸不是视口，
	#   会算出 1280×1280 这种诡异值）。这里与其它 HUD 元素一致，用绝对 offset 定位。
	# ⚠ 视口尺寸取常量而不是 get_viewport().get_visible_rect()（那个接口在此环境不准）。
	var n := SKILL_BAR_KEYS.size()
	var bar_w := float(n) * SKILL_SLOT_SIZE.x + float(n - 1) * SKILL_SLOT_GAP

	var row := HBoxContainer.new()
	row.name = "SkillBarRow"
	row.set_meta("skill_bar_row", true)
	row.add_theme_constant_override("separation", int(SKILL_SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = (VIEW_W - bar_w) * 0.5
	row.offset_right = row.offset_left + bar_w
	row.offset_top = VIEW_H - SKILL_SLOT_SIZE.y - 4.0
	row.offset_bottom = VIEW_H - 4.0
	$HUD.add_child(row)

	for i in n:
		var sid := ""
		if i < CharacterData.active_skill_loadout.size():
			sid = String(CharacterData.active_skill_loadout[i])
		var box := _make_skill_slot(i, sid)
		row.add_child(box)
		# 剑意就绪光环（一剑开天 / 万剑归宗满层时绕格旋转）。
		# ⚠ 必须挂 row 下当 sibling，不能挂格子里：格子 clip_contents=true
		#   （给冷却遮罩兜底），超出 48px 的环会被裁掉。
		#   位置由 _update_skill_bar 每帧对齐格子中心；不可见时脚本自己停转。
		var aura := SkillReadyAura.new()
		# ⚠ 必须默认隐藏：空槽（sid=""）会被 _update_skill_bar 的 continue 跳过，
		#   它的 aura 永远等不到显隐判定 —— Node2D 默认 visible=true，会一直挂在
		#   row 原点（第一格左上角）显示剑气环（历史 bug：装配不满 4 格就复现）。
		aura.visible = false
		row.add_child(aura)
		_skill_slots[i]["aura"] = aura

	# 技能栏建好之后再挂 debuff 列：它要靠第一格的位置来定位
	_build_debuff_box()


# ===================== 负面状态（debuff）显示 =====================

## 在第一个功法格正上方建一个「底对齐」的竖列：
## 底对齐 = 内容贴着技能栏往上长，新标签插到 index 0 就出现在最上面。
## ⚠ 不能每帧重建标签：会闪、也会丢顺序。这里只建一次，之后只改文字。
func _build_debuff_box() -> void:
	if _debuff_box != null and is_instance_valid(_debuff_box):
		_debuff_box.queue_free()
	_debuff_rows.clear()

	var n := SKILL_BAR_KEYS.size()
	var bar_w := float(n) * SKILL_SLOT_SIZE.x + float(n - 1) * SKILL_SLOT_GAP
	var bar_left := (VIEW_W - bar_w) * 0.5
	var bar_top := VIEW_H - SKILL_SLOT_SIZE.y - 4.0

	var box := VBoxContainer.new()
	box.name = "DebuffBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 底对齐：内容从下往上堆，底部固定
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 4)
	# 水平上尽量居中于第一个功法格，但**左边界不许越过整排功法栏的最左端**
	# （2026-10-23 用户要求）：140 宽的标签居中的话会往左探出 46px，看着像飘在功法栏外面。
	# 越界时改成跟功法栏左端对齐，读起来是「贴着功法栏长出来的一列」。
	var first_center := bar_left + SKILL_SLOT_SIZE.x * 0.5
	var box_left := maxf(bar_left, first_center - DEBUFF_ROW_WIDTH * 0.5)
	box.offset_left = box_left
	box.offset_right = box_left + DEBUFF_ROW_WIDTH
	box.offset_bottom = bar_top - DEBUFF_BOX_GAP
	box.offset_top = DEBUFF_BOX_TOP_MARGIN
	$HUD.add_child(box)
	_debuff_box = box


## 增益状态列：**第一个法宝格上方、左端对齐法宝栏**（与 debuff 列同构，只是换了位置和配色）
func _build_buff_box(bar_left: float, bar_top: float) -> void:
	if _buff_box != null and is_instance_valid(_buff_box):
		_buff_box.queue_free()
	_buff_rows.clear()

	var box := VBoxContainer.new()
	box.name = "BuffBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 4)
	# 用户要求「最左边」→ 左端直接对齐法宝栏左边界，不做居中
	box.offset_left = bar_left
	box.offset_right = bar_left + DEBUFF_ROW_WIDTH
	box.offset_bottom = bar_top - DEBUFF_BOX_GAP
	box.offset_top = DEBUFF_BOX_TOP_MARGIN
	$HUD.add_child(box)
	_buff_box = box


## 每帧同步 debuff 标签（新增 / 刷新剩余秒 / 移除过期）
func _update_debuff_bar() -> void:
	if _debuff_box == null or not is_instance_valid(_debuff_box):
		return
	if player == null or not is_instance_valid(player):
		return
	var list: Dictionary = player.get("debuffs")
	var entries: Dictionary = {}
	for raw_id in list.keys():
		var id := String(raw_id)
		# 力竭不再占一行标签：剩余时间改画在玩家脚前灵环的精力点阵上（2026-11-11 用户定
		# 「状态收进简内，屏幕上只留低血暗角这一条二级通道」）。判定逻辑一字未动，
		# 只是显示归属搬走 —— 别在这里再补一份倒计时，那会又变成两处说同一件事。
		if id == "exhausted":
			continue
		entries[id] = {
			"text": "%s　%.1fs" % [DebuffDB.display_name(id), maxf(float(list[raw_id]), 0.0)],
			"color": DebuffDB.color(id),
		}
	_sync_status_list(_debuff_box, _debuff_rows, entries)


# ===================== 增益状态（buff）显示 =====================
## 位置：**第一个法宝格上方、左端对齐法宝栏**（用户 2026-10-23 定）。
## 显示逻辑与 debuff 完全一致（新的在上、不限数量、不裁切），只是配色走 BuffDB 的绿。

func _update_buff_bar() -> void:
	if _buff_box == null or not is_instance_valid(_buff_box):
		return
	if player == null or not is_instance_valid(player):
		return
	var list: Dictionary = player.get("buffs")
	var entries: Dictionary = {}
	for raw_id in list.keys():
		var id := String(raw_id)
		var e: Dictionary = list[raw_id]
		var text := ""
		if BuffDB.is_count_based(id):
			# 次数型：名称 + 次数（用户要求「如果是次数就在图标后面显示数字」）
			text = "%s　×%d" % [BuffDB.display_name(id), int(e.get("count", 0))]
		else:
			text = "%s　%.1fs" % [BuffDB.display_name(id), maxf(float(e.get("left", 0.0)), 0.0)]
		entries[id] = {"text": text, "color": BuffDB.color(id)}
	# 迟照符不是 buff，单独一条读数：待结伤害 + 剩余窗口（血条不掉账时必须可见）
	var rk_left := float(player.get("_reckoning_left"))
	if rk_left > 0.0:
		entries["delayed_reckoning"] = {
			"text": "迟照　待结 %d / %.1fs" % [
				int(round(float(player.get("_reckoning_pool")))), rk_left],
			"color": UIKit.C_FLOAT_WARN,
		}
	# 换锋符：窗口剩余（不是 buff，单独一条读数）
	var bf_left := float(player.get("_blade_form_left"))
	if bf_left > 0.0:
		entries["blade_form"] = {
			"text": "换锋　%.1fs" % bf_left,
			"color": UIKit.C_HUD_MANA,
		}
	_sync_status_list(_buff_box, _buff_rows, entries)


## 通用状态列同步：debuff 与 buff 共用
## entries: id -> { text, color }
## 规则（用户 2026-10-23 定）：新出现的放**最上面**，已有的原地刷新文字，消失的移除。
## ⚠ 只改文字不重建节点：重建会闪、也会丢顺序。
func _sync_status_list(box: VBoxContainer, rows: Dictionary, entries: Dictionary) -> void:
	if box == null or not is_instance_valid(box):
		return
	# ① 已经不存在的
	for id in rows.keys():
		if not entries.has(id):
			var panel := ((rows[id] as Dictionary).get("panel")) as Control
			if panel != null and is_instance_valid(panel):
				panel.queue_free()
			rows.erase(id)
	# ② 新增 / 刷新（entries 的 key 是 Variant，统一转 String 当字典键）
	for raw_id in entries.keys():
		var id := String(raw_id)
		var e: Dictionary = entries[raw_id]
		var color := Color(e.get("color", UIKit.C_TEXT))
		if not rows.has(id):
			var built := _make_status_row(String(e.get("text", "")), color)
			box.add_child(built.get("panel"))
			box.move_child(built.get("panel"), 0)
			rows[id] = built
		else:
			var label := ((rows[id] as Dictionary).get("label")) as Label
			if label != null and is_instance_valid(label):
				label.text = String(e.get("text", ""))
				label.add_theme_color_override("font_color", color)


## 单行状态标签：暗底 + 状态色描边 + 文字
## 美术替换口：底框走 UIKit.slot_style，颜色由调用方传（DebuffDB / BuffDB）
func _make_status_row(text: String, color: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.slot_style(true)
	sb.bg_color = Color(0.09, 0.06, 0.07, 0.90)
	sb.border_color = color
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)

	var label := UIKit.label(text, UIKit.F_SMALL, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return {"panel": panel, "label": label}


## 单个功法格：底框 + 图标 + 左上角按键 + 冷却遮罩 + 秒数
## 空槽 = 暗框 + 半透明按键字母（让玩家知道有 4 个位可装）
func _make_skill_slot(index: int, sid: String) -> Control:
	var filled := sid != ""

	var box := PanelContainer.new()
	box.custom_minimum_size = SKILL_SLOT_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UIKit.slot_style(filled)
	# HUD 的格子是浮在战场上的一层：给柔和投影 + 左上受光边（面板内的格子不投影）
	UIKit.apply_elevation(sb, UIKit.ELEV_CARD)
	box.add_theme_stylebox_override("panel", sb)
	UIKit.edge_light(box, 3.0)
	# ⚠ 硬保险：PanelContainer 会按 stylebox 的 content_margin 把子节点排进内容区，
	#   但**不会裁剪溢出的子节点** —— 冷却遮罩一旦算高就会画到边框外面去。
	box.clip_contents = true
	box.tooltip_text = _skill_slot_tooltip(sid)
	# 新手指引锚点：Q/E/R/T 四格（「hud.skill.q」是教学里引用的键，指 Q 这一格）
	if index == 0:
		box.set_meta("tut", "hud.skill.q")
	else:
		box.set_meta("tut", "hud.skill.%d" % (index + 1))

	# 图标（技能取 SkillDB，符箓取 ItemDB；空槽给暗底）
	var icon := UIKit.icon_node(
		CharacterData.active_slot_display_icon(sid) if filled else "",
		CharacterData.active_slot_display_name(sid) if filled else "",
		"skill", SKILL_ICON_SIZE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 空槽整体压暗：占位色块和有技能的格子同色，不压暗会看不出「这个位是空的」
	if not filled:
		icon.modulate = Color(1.0, 1.0, 1.0, 0.22)
	box.add_child(icon)

	# 资源不足时把图标压成灰色（参数每帧由 _update_slot_disabled 改）
	# ⚠ 材质必须挂到真正绘制贴图的 TextureRect：CanvasItem 的 material 不向子节点继承，
	#   给 CenterContainer 挂等于没挂（这是本改动最容易踩空的一步）。
	var icon_mat: ShaderMaterial = null
	if filled:
		var paint_target := _icon_paint_target(icon)
		if paint_target != null:
			icon_mat = ShaderMaterial.new()
			icon_mat.shader = load(SKILL_GRAY_SHADER)
			icon_mat.set_shader_parameter("gray_mix", 0.0)
			icon_mat.set_shader_parameter("dim", 0.0)
			paint_target.material = icon_mat

	# 冷却遮罩：从底部往上填（剩余比例越高遮罩越高），转好时完全消失
	# ⚠⚠ 不能把遮罩**直接**当 PanelContainer 的子节点用 anchor 定位：
	#   PanelContainer 每次排序都会把子节点重新 fit 成**内容区**（48×48 减去 stylebox 的
	#   3px content_margin = 42×42），这个过程会把 anchor 改掉 —— 于是 offset_top 从
	#   「相对底边」变成「相对顶边」，遮罩高度直接窜出格子（表现为灰色块盖住上边框）。
	#   正确做法：套一层普通 Control 当「内容区」，遮罩在它内部按**像素**定位。
	var cover := Control.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cover)          # 由 PanelContainer 自动 fit 成内容区，尺寸随时可读

	var mask := ColorRect.new()
	mask.color = UIKit.C_CD_MASK
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.visible = false
	cover.add_child(mask)         # 初始 size 为 0，由 _update_skill_bar 每帧重算

	# 冷却秒数（遮罩之上，居中小字）
	var cd := UIKit.label("", UIKit.F_BADGE, Color(1.0, 1.0, 1.0, 1.0))
	cd.set_anchors_preset(Control.PRESET_CENTER)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.visible = false
	box.add_child(cd)

	# 左上角按键字母（Q/E/R/T）—— **最后加入**，这样它在最上层，
	# 冷却遮罩盖得住图标却盖不住按键，玩家永远看得见该按哪个键
	var key := UIKit.label(SKILL_BAR_KEYS[index], UIKit.F_BADGE,
		UIKit.muted(UIKit.C_ACCENT, 0.34) if filled else UIKit.C_DISABLE)
	key.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key.offset_left = 3.0
	key.offset_top = 1.0
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key)

	var count_label := UIKit.label("", UIKit.F_BADGE, Color.WHITE)
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.offset_left = -24.0
	count_label.offset_top = -16.0
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.visible = CharacterData.is_talisman_slot(sid)
	box.add_child(count_label)

	_skill_slots.append({
		"box": box, "icon": icon, "key": key, "cover": cover, "mask": mask, "cd": cd,
		"count": count_label, "is_talisman": CharacterData.is_talisman_slot(sid), "sid": sid,
		"icon_mat": icon_mat, "gray_on": false, "gray_reason": "",
	})
	return box


## 每帧刷新冷却遮罩与秒数
func _update_skill_bar() -> void:
	if _skill_slots.is_empty() or not is_instance_valid(player):
		return
	for e in _skill_slots:
		var sid := String(e.get("sid", ""))
		var cover: Control = e.get("cover")
		var mask: ColorRect = e.get("mask")
		var cd: Label = e.get("cd")
		if sid == "" or cover == null or mask == null or cd == null:
			continue
		_update_slot_disabled(e, sid)
		var count_label: Label = e.get("count")
		if bool(e.get("is_talisman", false)):
			var base_id := CharacterData.talisman_slot_item_id(sid)
			var run_tal := RogueRun.active and not TalismanDB.base_def(base_id).is_empty()
			var tal_left: float = float(player.run_talisman_cd_left(base_id)) if run_tal else 0.0
			if count_label != null:
				if run_tal:
					# 试炼：右下角显示品阶（练 / 筑 / 结 / 元），不显示张数（局内没有库存）。
					# ⚠ 冷却中把这个角让给秒数：48px 的格子里「品阶 + 剩余秒」会叠在一起。
					var tier := clampi(RogueRun.talisman_tier(base_id), 0,
						TalismanDB.QUALITY_NAME.size() - 1)
					count_label.text = String(TalismanDB.QUALITY_NAME[tier]).substr(0, 1)
					count_label.visible = tal_left <= 0.0
				else:
					# 演武场符箓无限：不显示背包张数，避免误以为会被消耗
					count_label.visible = true
					count_label.text = "∞" if training_mode \
						else "×%d" % CharacterData.active_slot_talisman_count(sid)
			if tal_left <= 0.0:
				mask.visible = false
				cd.visible = false
			else:
				var tal_total: float = TalismanDB.cooldown(base_id) \
					* maxf(0.25, 1.0 + RogueRun.stat("tal_cd_pct") / 100.0)
				var tal_ratio: float = clampf(tal_left / maxf(tal_total, 0.01), 0.0, 1.0)
				var tal_area := cover.size
				var tal_h := tal_area.y * tal_ratio
				mask.position = Vector2(0.0, tal_area.y - tal_h)
				mask.size = Vector2(tal_area.x, tal_h)
				mask.visible = true
				cd.visible = true
				cd.text = "%.1f" % tal_left
			_update_ready_aura(e, tal_left)
			continue
		var left: float = player.skill_cooldown_left(sid)
		if left <= 0.0:
			# 已转好：遮罩与秒数都收起
			mask.visible = false
			cd.visible = false
		else:
			# 遮罩高度 = 剩余比例 × **内容区**高度，底边贴着内容区底边。
			# cover 就是内容区（PanelContainer 已把 3px 边距扣掉），所以在它内部按像素摆即可 ——
			# 满冷却时正好铺满内容区，不会盖住边框、更不会跑到格子外面。
			var total: float = float(SkillDB.get_skill_cost(sid).get("cooldown", 0.0))
			var ratio: float = clampf(left / total, 0.0, 1.0) if total > 0.0 else 1.0
			var area := cover.size
			var h := area.y * ratio
			mask.position = Vector2(0.0, area.y - h)
			mask.size = Vector2(area.x, h)
			mask.visible = true
			cd.visible = true
			cd.text = "%.1f" % left
		_update_ready_aura(e, left)


## 资源不足以释放时把图标压成灰色（2026-11-09 用户要求：蓝量 / 精力不够时变灰）
## 只在状态翻转时写 shader 参数 —— 每帧无条件 set 也没错，但没必要。
## ⚠ 判定一律走 player 的接口，**不要在这里另算一套**：灵力 / 精力 / 以意御法借剑意 /
##   试炼符箓解锁的口径都在那边，写重了必然出现「灰着却能放」或「亮着却放不出」。
func _update_slot_disabled(e: Dictionary, sid: String) -> void:
	var mat: ShaderMaterial = e.get("icon_mat")
	if mat == null:
		return
	var reason := ""
	if bool(e.get("is_talisman", false)):
		reason = player.talisman_slot_block(sid)
	else:
		reason = player.skill_resource_block(sid)
	var on := reason != ""
	# ⚠ 试炼四符的冷却占了整场的大半时间，冷却中再压暗图标 = 技能栏长期是四个黑洞：
	#   冷却只让遮罩与秒数表达，灰化留给「灵力不足 / 未解锁」这类真·放不出来的原因。
	if on and bool(e.get("is_talisman", false)) and RogueRun.active:
		var tal_base := CharacterData.talisman_slot_item_id(sid)
		if not TalismanDB.base_def(tal_base).is_empty() \
				and float(player.run_talisman_cd_left(tal_base)) > 0.0:
			on = false
	# 比起「灰没灰」，还要比原因：灵力不足 → 未解锁 这种切换时 tooltip 也得跟着改
	if on == bool(e.get("gray_on", false)) and reason == String(e.get("gray_reason", "")):
		return
	e["gray_on"] = on
	e["gray_reason"] = reason
	mat.set_shader_parameter("gray_mix", SKILL_GRAY_MIX if on else 0.0)
	mat.set_shader_parameter("dim", SKILL_GRAY_DIM if on else 0.0)
	var box: Control = e.get("box")
	if box != null:
		# 顺便把原因写进 tooltip：飘字会淡掉，灰着的时候悬停能一直看到为什么
		box.tooltip_text = _skill_slot_tooltip(sid, reason)


## UIKit.icon_node() 返回的是 CenterContainer（找不到图时是占位 PanelContainer）里套一层
## TextureRect，真正画贴图的是里面那层 —— 材质必须挂它，挂容器没有效果。
func _icon_paint_target(icon: Control) -> CanvasItem:
	if icon == null:
		return null
	if icon is TextureRect:
		return icon
	for n in icon.find_children("*", "TextureRect", true, false):
		return n as CanvasItem
	return icon as CanvasItem


## 剑意就绪光环：**剑意满层 + 冷却转好 + 该招式吃剑意**时绕格子旋转
## 「吃剑意」走数据判定（intent_full_at / intent_count_scale），不写死技能 id ——
## 一剑开天（intent_full_at）与万剑归宗（intent_count_scale）自动覆盖，换技能不改这里
func _update_ready_aura(e: Dictionary, cooldown_left: float) -> void:
	var aura: Node2D = e.get("aura")
	if aura == null or not is_instance_valid(aura):
		return
	var box: Control = e.get("box")
	if box == null:
		return
	var show: bool = cooldown_left <= 0.0 and player.is_sword_intent_full()
	if show:
		var form: Dictionary = SkillDB.get_skill_form(String(e.get("sid", "")))
		var ics: Dictionary = form.get("intent_count_scale", {})
		show = int(form.get("intent_full_at", 0)) > 0 or not ics.is_empty()
	aura.visible = show
	if show:
		# 光环挂在 row 下（sibling），位置每帧对齐格子中心
		aura.global_position = box.global_position + box.size * 0.5


## 格子 tooltip：完整功法信息（空槽说明可去哪装配）
## block_reason 非空时追加一行「为什么现在放不出来」——资源不足由 _update_slot_disabled 传入
## ⚠ 效果说明一律走 SkillDB.get_effect_text()（从招式表现算），**不要在这里另写一套**，
##   否则改了招式数值 tooltip 还留着旧文案
func _skill_slot_tooltip(sid: String, block_reason: String = "") -> String:
	if sid == "":
		return "空槽位 · 按 Y 打开功法库 / 符匣，把功法或符箓装到槽位"
	var out := ""
	if CharacterData.is_talisman_slot(sid):
		var base_id := CharacterData.talisman_slot_item_id(sid)
		if RogueRun.active and not TalismanDB.base_def(base_id).is_empty():
			var tier := RogueRun.talisman_tier(base_id)
			var lines: Array = TalismanDB.effect_lines(base_id, tier)
			# 连携是可选强化（2026-11-11）：没解锁就不提示这一行
			var chain_line := "\n连携：随机再放一张（70%%）" if RogueRun.has_flag("tal_chain_on") else ""
			out = "%s（%s）\n%s\n消耗 %.0f 灵力 · 冷却 %.1f 秒%s" % [
				TalismanDB.display_name(base_id), String(TalismanDB.QUALITY_NAME[tier]),
				"\n".join(lines), TalismanDB.mana_cost(base_id), TalismanDB.cooldown(base_id),
				chain_line]
		else:
			var def := ItemDB.get_consumable(CharacterData.talisman_slot_item_id(sid))
			out = "%s\n%s\n消耗 5 灵力，瞬发，无冷却" % [
				String(def.get("talisman_name", "符箓")), String(def.get("desc", ""))]
	else:
		out = "%s\n%s" % [SkillDB.get_skill_name(sid), SkillDB.get_effect_text(sid)]
	if block_reason != "":
		out += "\n· 当前%s，暂时无法释放" % block_reason
	return out


## 按键提示：停留 3 秒后渐隐消失
##
## 为什么用 tween 而不是计时器 + 手动改 alpha：
##   tween 跟着游戏时钟走，玩家按 ESC 打开确认框（游戏暂停）时提示会停在原处，
##   不会在暂停中悄悄消失，也不会在恢复时突然跳变。
## ⚠ 背景条（HintBG）必须和文字一起淡 —— 只淡文字会剩下一条黑带挂在屏幕下方
##   （2026-10-18 用户反馈过的 bug）。两者用 parallel 并行、同时长，观感才是一体的。
## 渐隐结束后隐藏节点：留着全透明的控件没意义，隐藏更干净
## （Label / ColorRect 的 mouse_filter 本来就是 IGNORE，不影响点击）。
## 左上角「基础操作」竖排（2026-11-12 用户定）
##   · 从屏幕底部那一整行挪到左上角，**竖着**排：一行一个操作，不再和底部功法栏抢位置；
##   · 战斗中常驻（不再几秒后渐隐），但**打完 / 死了就藏**（见 _update_key_hint）；
##   · 触屏没有键盘：整块不建（虚拟键自己会说话）。
func _build_key_hint(rogue_mode: bool) -> void:
	if VirtualPad.is_touch_enabled():
		return
	# 试炼之路不建这块：塔层 HUD（层/关/波、增益、行囊）本身就占着左上角，
	# 两叠在一起互相压字（2026-11-12 用户报）。试炼的按键照旧走键位习惯，不额外教。
	if rogue_mode:
		return
	var rows: Array = [
		["移动", "WASD"], ["攻击", "左键 / J"], ["弹刀", "右键 / K"],
		["闪避", "空格"], ["拾取", "F"], ["功法", "Q E R T"],
		["行囊" if rogue_mode else "角色", "Tab"], ["重开", "C"], ["返回", "ESC"],
	]
	if training_mode:
		rows.append(["记录", "H"])
	var accent: Color = UIKit.C_ACCENT
	var card := PanelContainer.new()
	card.name = "KeyHint"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.55, 0.30, 7))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	margin.add_child(grid)
	for r in rows:
		var key := UIKit.label(String(r[0]), UIKit.F_SMALL, Color(0.92, 0.79, 0.44, 0.92))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(key)
		var desc := UIKit.label(String(r[1]), UIKit.F_SMALL, Color(0.82, 0.84, 0.88, 0.72))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(desc)
	card.position = Vector2(12.0, 10.0)
	card.z_index = 25
	$HUD.add_child(card)
	_key_hint = card


## 「战斗中才显示」：打完 / 死了就藏（键盘图例只在还能操作的时候有用）
func _update_key_hint() -> void:
	if _key_hint == null or not is_instance_valid(_key_hint):
		return
	var alive := player != null and is_instance_valid(player) and not bool(player.get("is_dead"))
	_key_hint.visible = alive and not _cleared


## 按战斗来源替换 BOSS 模型（数据驱动）
## SOURCE_ARENA = 演武场训练木桩；位面 / 塔带 boss_id 就加载 WorldDB 登记的专属 BOSS。
func _spawn_boss_by_context() -> void:
	if BattleResolver.current_source() == BattleResolver.SOURCE_ARENA:
		_spawn_training_dummy()
		return
	if BattleResolver.current_source() == BattleResolver.SOURCE_WORLD_CORE:
		_spawn_world_core_boss()
		return
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		_spawn_rogue_boss()
		return
	var boss_id := String(GameState.battle_context.get("boss_id", ""))
	if boss_id == "":
		return
	var path := WorldDB.get_boss_scene(boss_id)
	# ⚠ 虎妖（boss_huyao）等就是 boss.tscn —— 与场景自带的是同一个，不需要替换节点，
	#   但**塔层血量成长仍要生效**，所以这里不能直接 return
	if path == WorldDB.DEFAULT_BOSS_SCENE:
		var old_boss := get_node_or_null("Boss")
		if old_boss != null:
			_apply_tower_hp(old_boss, true)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("BOSS 场景加载失败，回退原型 BOSS：" + path)
		return

	var old := get_node_or_null("Boss")
	if old:
		# 先改名再释放：queue_free 是延迟的，否则会与新 BOSS 撞名
		old.name = "OldBoss"
		old.queue_free()

	var nb: Node2D = packed.instantiate()
	nb.name = "Boss"
	# 入树前设 position —— 未入树的节点 global_position 不生效
	nb.position = boss_spawn.position
	# ★ 万界塔血量成长（见文件顶部 TOWER_HP_STEP）；入树前设置，_ready 里会 current_hp = max_hp
	_apply_tower_hp(nb, false)
	add_child(nb)


## 区域核心首领重战：把 WorldEnemy 按 CORE_BOSS 配置成可结算的独立 BOSS。
## 大世界里的核心只发 world_died（由大世界管理器处理）；这里置 standalone，
## 死亡时同时发 BossBase.died，让战斗箱庭走统一的胜利结算。
func _spawn_world_core_boss() -> void:
	var region_id := String(GameState.battle_context.get("region_id", ""))
	var cfg := SecretWorldDB.get_core_boss(region_id)
	if cfg.is_empty():
		push_warning("核心首领配置缺失：" + region_id)
		return
	var old_boss := get_node_or_null("Boss")
	if old_boss != null:
		old_boss.name = "OldBoss"
		old_boss.queue_free()

	var scene_path := String(cfg.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene \
		if scene_path != "" and ResourceLoader.exists(scene_path) else (load(WORLD_ENEMY_SCENE) as PackedScene)
	if packed == null:
		push_warning("核心首领场景缺失：" + scene_path)
		return
	var nb: WorldEnemy = packed.instantiate() as WorldEnemy
	if nb == null:
		push_warning("核心首领场景不是 WorldEnemy：" + scene_path)
		return
	nb.name = "Boss"
	var spawn_pos: Vector2 = cfg.get("arena_spawn", boss_spawn.position)
	nb.position = spawn_pos
	var stats: Dictionary = cfg.duplicate(true)
	stats["pos"] = spawn_pos
	# 分支重战也吃「每胜一次 +10% 血」：与塔层同一个上限（2 倍封顶）
	var clear_mult := CharacterData.core_hp_multiplier(region_id)
	if clear_mult > 1.0:
		stats["max_hp"] = float(stats.get("max_hp", 1.0)) * clear_mult
		print("[core-replay] %s 第 %d 次重战：血量 ×%.1f（已胜 %d 次）" % [
			region_id, CharacterData.get_core_clear_count(region_id) + 1, clear_mult,
			CharacterData.get_core_clear_count(region_id)])
	nb.boss_id = String(GameState.battle_context.get("boss_id", ""))
	nb.configure(stats, WorldEnemy.KIND_CORE, String(stats.get("name", "核心首领")))
	nb.standalone = true
	add_child(nb)


## 演武场：用不灭木桩替换场景自带的原型 BOSS
func _spawn_training_dummy() -> void:
	var old := get_node_or_null("Boss")
	if old != null:
		# 先改名再释放：queue_free 是延迟的，否则会与新木桩撞名
		old.name = "OldBoss"
		old.queue_free()
	var packed := load(TRAINING_DUMMY_SCENE) as PackedScene
	if packed == null:
		push_warning("训练木桩场景缺失：" + TRAINING_DUMMY_SCENE)
		return
	var dummy: Node2D = packed.instantiate()
	dummy.name = "Boss"
	dummy.position = boss_spawn.position
	add_child(dummy)
	training_dummy = dummy


## 把一只 BOSS 接进战斗：仇恨目标 / 三路信号 / 调试面板 / 顶栏血条。
## ⚠ BOSS 节点**不能跨层复用**：死亡后 state=DEAD，`died` 只发一次，
##   第二层再拿同一只去当关卡 BOSS 就永远等不到击杀信号 → 试炼卡在 BOSS 关
##   （2026-11-08 用户报「进不了下一层」）。所以每层 BOSS 关都走 `spawn_rogue_boss_now()` 重新实例化。
func _bind_boss(b: Node2D) -> void:
	if b == null or not is_instance_valid(b):
		return
	boss = b
	b.target = player
	b.health_changed.connect(_on_boss_health_changed)
	b.phase_changed.connect(_on_boss_phase_changed)
	b.died.connect(_on_boss_died)
	# 调试面板：绑定 BOSS 并同步当前数值（会应用 GameState 里保存的覆盖值）
	var debug_panel = $DebugPanel
	if debug_panel != null:
		debug_panel.boss = b
		debug_panel.refresh()
	# 初始血量显示（在应用覆盖值之后刷新，保证 max_hp 覆盖生效）
	_on_boss_health_changed(b.current_hp, b.max_hp)


## 试炼之路：进入 BOSS 关时按「本层」的 BOSS 重新造一只并接好信号。
## 返回新节点（失败返回 null）。非肉鸽模式不要调。
func spawn_rogue_boss_now() -> Node2D:
	_spawn_rogue_boss()
	var nb := get_node_or_null("Boss") as Node2D
	if nb == null:
		return null
	_bind_boss(nb)
	return nb


## 试炼之路：按本层抽到的 BOSS 实例化，但先「休眠」——要到第 4 小关才亮出来。
## 血量 / 攻击换成 RogueDB 的层数曲线；招式、阶段、骨骼动画全部沿用原 BOSS。
func _spawn_rogue_boss() -> void:
	var rogue_boss_id := RogueRun.boss_id
	if rogue_boss_id == "":
		rogue_boss_id = RogueDB.BOSS_TUTORIAL
	var path := WorldDB.get_boss_scene(rogue_boss_id)
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("试炼 BOSS 场景加载失败：" + path)
		return
	var old := get_node_or_null("Boss")
	if old != null:
		old.name = "OldBoss"
		old.queue_free()
	var nb: Node2D = packed.instantiate()
	nb.name = "Boss"
	nb.position = boss_spawn.position
	# 入树前写数值：BossBase._ready 会 current_hp = max_hp
	nb.set("max_hp", RogueDB.boss_hp(rogue_boss_id, RogueRun.floor_no))
	nb.set("attack_power", RogueDB.boss_atk(rogue_boss_id, RogueRun.floor_no))
	nb.visible = false
	nb.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(nb)


## 建肉鸽调度器（波次 / 三选一 / 结算都在里面）
func _setup_rogue() -> void:
	_rogue = RogueArena.new()
	_rogue.setup(self, player, boss)
	add_child(_rogue)
	# 小怪阶段没有 BOSS：先藏血条（RogueArena 也会重申一次）
	var bar := get_node_or_null("HUD/BossHealthBar") as Control
	if bar != null:
		bar.visible = false


## 把「万界塔反复挑战」的血量倍率应用到 BOSS 上（只在塔战斗生效）
## in_tree = true 表示这个 BOSS 已经入树（_ready 跑过、current_hp 已等于旧 max_hp），
## 需要同步当前血量与头顶血条，否则会出现「满血条但实际只有基础血」的错位
func _apply_tower_hp(boss_node: Node, in_tree: bool) -> void:
	if BattleResolver.current_source() != BattleResolver.SOURCE_TOWER:
		return
	var floor_no := int(GameState.battle_context.get("floor", 0))
	if floor_no <= 0:
		return
	var clears := CharacterData.get_tower_clear_count(floor_no)
	var mult := CharacterData.tower_hp_multiplier(floor_no)
	if mult <= 1.0:
		return
	boss_node.set("max_hp", float(boss_node.get("max_hp")) * mult)
	if in_tree:
		boss_node.set("current_hp", float(boss_node.get("max_hp")))
		if boss_node.has_method("_update_head_hp_bar"):
			boss_node.call("_update_head_hp_bar")
	print("[tower] 第 %d 层第 %d 次挑战：血量 ×%.1f（已通关 %d 次）"
		% [floor_no, clears + 1, mult, clears])


# ===================== HUD 视觉秩序（2026-11-04 用户定：靠光影排版，不靠粗描边强闪光）=====================

## HUD 是浮在战场之上的一层，统一按「左上打光」抬起来；
## 文字按标题 / 正文 / 数字三级分，只有主操作与关键数字保留高亮度。
func _style_hud() -> void:
	# 标题级：战斗来源（位面 / 塔层）
	var battle_title := get_node_or_null("HUD/BattleTitleLabel") as Label
	if battle_title != null:
		battle_title.add_theme_color_override("font_color", UIKit.C_TITLE)
		UIKit.soft_text_shadow(battle_title, 1)
	# 正文级：阶段提示、刀势标签退到次要
	var phase := get_node_or_null("HUD/PhaseLabel") as Label
	if phase != null:
		phase.add_theme_color_override("font_color", UIKit.C_TEXT_DIM)
		UIKit.soft_text_shadow(phase, 1)
	var mom_label := get_node_or_null("HUD/MomentumLabel") as Label
	if mom_label != null:
		mom_label.add_theme_color_override("font_color", UIKit.C_TEXT_FAINT)
		UIKit.soft_text_shadow(mom_label, 0)
	# 数字级：计时用阅读字体 + 最干净的一档，不加金边
	var time_label := get_node_or_null("HUD/TimeLabel") as Label
	if time_label != null:
		UIKit.make_readable(time_label)
		time_label.add_theme_color_override("font_color", UIKit.C_NUM)
		UIKit.soft_text_shadow(time_label, 1)
	# 条与框：整层一起抬起来，投影方向一致（不再各画各的边框）
	for path in ["HUD/BossHealthBar", "HUD/MomentumBar"]:
		var bar := get_node_or_null(path) as Control
		if bar != null:
			_elevate_stylebox(bar, "background")
			_elevate_stylebox(bar, "grabber")
			_elevate_stylebox(bar, "fill")
## ProgressBar 的样式不是 "panel"，走单独一条路
func _elevate_stylebox(ctrl: Control, key: String) -> void:
	var flat := ctrl.get_theme_stylebox(key) as StyleBoxFlat
	if flat == null:
		return
	var mine := flat.duplicate() as StyleBoxFlat
	mine.shadow_size = 5
	mine.shadow_color = UIKit.SHADOW_COLOR
	mine.shadow_offset = UIKit.elevation_offset(1)
	ctrl.add_theme_stylebox_override(key, mine)


# ===================== 演武场训练 HUD =====================

func _setup_training_mode() -> void:
	# 触屏没有 H 键；面板若默认隐藏就没有任何入口 → 触屏保留展开，PC 默认隐藏
	_training_hud_visible = VirtualPad.is_touch_enabled()
	training_dummy = boss
	# 木桩没有血量 / 阶段，隐藏 BOSS 专用 HUD；计时也由训练记录接管
	$HUD/BossHealthBar.visible = false
	$HUD/PhaseLabel.visible = false
	$HUD/MomentumBar.visible = false
	$HUD/MomentumLabel.visible = false
	$HUD/TimeLabel.visible = false
	$HUD/BattleTitleLabel.text = BattleResolver.battle_title()
	_build_training_hud()
	# 背包装备面板是 autoload，关闭后刷新战斗角色的属性缓存与法宝栏
	if not CharacterPanel.panel_closed.is_connected(_on_training_char_panel_closed):
		CharacterPanel.panel_closed.connect(_on_training_char_panel_closed)
	_show_opening_announce()


func _build_training_hud() -> void:
	if _training_panel != null and is_instance_valid(_training_panel):
		_training_panel.queue_free()
	if _training_hint != null and is_instance_valid(_training_hint):
		_training_hint.queue_free()
	_training_hint = null
	_training_values.clear()

	_training_panel = PanelContainer.new()
	_training_panel.name = "TrainingPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.032, 0.042, 0.052, 0.93)
	style.border_color = Color(0.78, 0.62, 0.34, 0.55)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_training_panel.add_theme_stylebox_override("panel", style)
	_training_panel.position = Vector2(18.0, 18.0)
	_training_panel.size = Vector2(400.0, 320.0)
	_training_panel.z_index = 25
	$HUD.add_child(_training_panel)

	var vbox := UIKit.vbox(6)
	_training_panel.add_child(vbox)

	var head := UIKit.hbox(10)
	vbox.add_child(head)
	var icon_path := String(ArtDB.get_visual("training_dummy").get("texture", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(44.0, 66.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(icon)
	var titles := UIKit.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UIKit.label("木桩试炼", UIKit.F_SUBTITLE, UIKit.C_TITLE))
	titles.add_child(UIKit.label("不灭 · 无反击 · 试招记录", UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	head.add_child(titles)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(grid)
	# 训练读数属数字级：靠明度站住，不占用主按钮的高亮强调色
	_add_training_stat(grid, "总伤害", "total", UIKit.C_NUM)
	_add_training_stat(grid, "5秒 DPS", "dps", UIKit.C_NUM)
	_add_training_stat(grid, "最高单次", "max_hit", UIKit.C_TEXT)
	_add_training_stat(grid, "命中 / 记录", "hits", UIKit.C_TEXT)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	vbox.add_child(actions)
	var b_skill := UIKit.button("功法库", Vector2(180.0, 30.0))
	b_skill.pressed.connect(_open_training_skill_panel)
	actions.add_child(b_skill)
	var b_bag := UIKit.button("背包 / 装备", Vector2(180.0, 30.0))
	b_bag.pressed.connect(_open_training_bag)
	actions.add_child(b_bag)
	var b_cd := UIKit.button("刷新功法CD", Vector2(180.0, 30.0))
	b_cd.pressed.connect(_on_training_refresh_cd)
	actions.add_child(b_cd)
	var b_reset := UIKit.button("重置记录", Vector2(180.0, 30.0))
	b_reset.pressed.connect(_on_training_reset_damage)
	actions.add_child(b_reset)

	_training_status = UIKit.label("", UIKit.F_SMALL, UIKit.C_OK)
	_training_status.custom_minimum_size = Vector2(0.0, 16.0)
	vbox.add_child(_training_status)
	var footer_text := "Tab 背包 / 装备 · Y 功法库 · 木桩不会死亡"
	if not VirtualPad.is_touch_enabled():
		footer_text = "Tab 背包 / 装备 · Y 功法库 · H 收起 · 木桩不会死亡"
	vbox.add_child(UIKit.label(footer_text, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	_training_panel.visible = _training_hud_visible

	# PC：面板收起时左上角常驻提示；面板展开后提示让位（H 再收起时恢复）
	if not VirtualPad.is_touch_enabled():
		_training_hint = UIKit.label("按 H 打开记录面板", 12, Color(0.90, 0.96, 0.88, 0.95))
		_training_hint.position = Vector2(18.0, 18.0)
		_training_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_training_hint.z_index = 26
		_training_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		_training_hint.add_theme_constant_override("outline_size", 5)
		_training_hint.visible = not _training_hud_visible
		$HUD.add_child(_training_hint)


func _add_training_stat(grid: GridContainer, title: String, key: String, color: Color) -> void:
	grid.add_child(UIKit.label(title, UIKit.F_SMALL, UIKit.C_TEXT_DIM))
	var value := UIKit.label("—", UIKit.F_BODY, color)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)
	_training_values[key] = value


func _update_training_hud() -> void:
	if not training_mode or not is_instance_valid(training_dummy):
		return
	var stats: Dictionary = training_dummy.call("get_training_stats")
	if _training_values.has("total"):
		_training_values["total"].text = "%d" % int(round(float(stats.get("total", 0.0))))
	if _training_values.has("dps"):
		_training_values["dps"].text = "%.1f" % float(stats.get("recent_dps", 0.0))
	if _training_values.has("max_hit"):
		_training_values["max_hit"].text = "%d" % int(round(float(stats.get("max_hit", 0.0))))
	if _training_values.has("hits"):
		_training_values["hits"].text = "%d · %s" % [
			int(stats.get("hits", 0)),
			CharacterData.format_duration(float(stats.get("time", 0.0))),
		]


func _set_training_status(text: String) -> void:
	if _training_status == null:
		return
	_training_status_token += 1
	var token := _training_status_token
	_training_status.text = text
	await get_tree().create_timer(1.4).timeout
	if token == _training_status_token and is_instance_valid(_training_status):
		_training_status.text = ""


## 演武场：打开功法库（SystemPanel，自动暂停；关闭后重建快捷栏）
func _open_training_skill_panel() -> void:
	if not training_mode:
		return
	if _training_skill_panel != null and is_instance_valid(_training_skill_panel):
		return
	var panel := SkillPanel.new()
	get_tree().root.add_child(panel)
	_training_skill_panel = panel
	panel.closed.connect(_on_training_skill_panel_closed)
	panel.open()


func _on_training_skill_panel_closed() -> void:
	_training_skill_panel = null
	# 演武场里改被动后，剑心通明的层数乘区要立刻按新被动重算
	if player != null and is_instance_valid(player):
		player._sync_sword_intent_skill_mult()
	_build_skill_bar()
	_update_skill_bar()
	_set_training_status("功法搭配已更新")


## 演武场：打开随身背包装备（CharacterPanel 是 autoload，Tab 与按钮等价）
func _open_training_bag() -> void:
	if training_mode:
		CharacterPanel.open_panel()


func _on_training_char_panel_closed() -> void:
	if not training_mode or not is_instance_valid(player):
		return
	player.call("refresh_training_loadout")
	_build_treasure_bar()
	_set_training_status("装备 / 背包已更新")


func _on_training_refresh_cd() -> void:
	if not training_mode or not is_instance_valid(player):
		return
	player.call("refresh_training_resources")
	_update_skill_bar()
	_set_training_status("功法冷却已刷新 · 精力已回满")


## 训练面板整块显示 / 隐藏；H 键与（隐藏时的）底部提示都走这里
func _toggle_training_hud() -> void:
	if not training_mode or _training_panel == null or not is_instance_valid(_training_panel):
		return
	_training_hud_visible = not _training_hud_visible
	_training_panel.visible = _training_hud_visible
	if _training_hint != null and is_instance_valid(_training_hint):
		_training_hint.visible = not _training_hud_visible
	GameState.play_ui("ui_tab")
	if _training_hud_visible:
		_update_training_hud()


func _on_training_reset_damage() -> void:
	if is_instance_valid(training_dummy):
		training_dummy.call("reset_training_stats")
	_update_training_hud()
	_set_training_status("木桩记录已清空")


func _process(delta: float) -> void:
	if training_mode:
		_update_training_hud()
	_update_momentum_bar()
	_update_skill_bar()
	_update_treasure_bar()
	_update_debuff_bar()
	_update_buff_bar()
	# 战败提示的呼吸要在「计时作废」之后继续跑，所以放在 _timing 判断前面
	_update_grow_pulse()
	# 自动拾取也要在计时作废之后继续跑（掉落是击杀那一刻才出现的）
	_update_auto_pickup(delta)
	_update_key_hint()
	if not _timing:
		return
	# 顿帧/慢动作会改 Engine.time_scale，除回去才是真实经过的秒数。
	# 暂停时本函数不执行，所以按 ESC 确认框停留的时间不会计入。
	_elapsed += delta / maxf(Engine.time_scale, 0.0001)
	_update_time_label()


## 打完在左侧挂「伤害统计」（2026-11-12 用户定：万界塔 / 万界秘境）
## ⚠ 用击杀那一刻冻结的 _elapsed 算每秒，和结算字幕里的「用时」同源。
func _show_damage_report() -> void:
	var src := BattleResolver.current_source()
	if src != BattleResolver.SOURCE_DOMAIN and src != BattleResolver.SOURCE_TOWER:
		return
	DamageMeter.finish()
	var rows := DamageMeter.ranked(8)
	if rows.is_empty():
		return
	$HUD.add_child(DamageReportPanel.create(rows, DamageMeter.total, _elapsed))


## 自动拾取节拍：走进范围就捡，不用按 F（2026-11-12 用户定）。
## ⚠ 通关后照样要跑（掉落是击杀那一刻才出现的）；死亡后不跑；面板打开时树暂停、本函数不执行。
func _update_auto_pickup(delta: float) -> void:
	if player == null or not is_instance_valid(player) or bool(player.get("is_dead")):
		return
	if _drops_on_ground.is_empty():
		return
	_auto_pick_left -= delta
	if _auto_pick_left > 0.0:
		return
	_auto_pick_left = AUTO_PICKUP_INTERVAL
	_try_pickup_nearest(true)


## 刀势条：只有「暴露 get_momentum()」的 BOSS 才显示
## ⚠ 2026-10-22：刀客的刀势机制已删除（满势断岳改为「目标踩刀痕」触发），
##   现在没有任何 BOSS 提供 get_momentum()，这条恒为隐藏。
##   保留这段通用逻辑是为了以后别的 BOSS 想显示同类资源条时直接复用，无需改 HUD 结构。
func _update_momentum_bar() -> void:
	if momentum_bar == null:
		return
	var has_momentum := is_instance_valid(boss) and boss.has_method("get_momentum")
	momentum_bar.visible = has_momentum
	momentum_label.visible = has_momentum
	if not has_momentum:
		return

	var value := float(boss.call("get_momentum"))
	momentum_bar.value = value
	# 满势（≥60）进危险色：一眼看出「它快放大了」
	momentum_bar.modulate = UIKit.C_MOMENTUM_DANGER if value >= 60.0 else UIKit.C_MOMENTUM
	momentum_label.add_theme_color_override("font_color",
		UIKit.C_MOMENTUM_DANGER if value >= 60.0 else UIKit.C_TEXT_DIM)


func _update_time_label() -> void:
	if is_instance_valid(time_label):
		time_label.text = "用时 %s" % CharacterData.format_duration(_elapsed)


func _on_boss_health_changed(current: float, max_hp: float) -> void:
	$HUD/BossHealthBar.value = current / max_hp * 100.0


func _on_boss_phase_changed(phase: int) -> void:
	if phase == 2:
		$HUD/PhaseLabel.text = "BOSS 第二阶段"
		$HUD/PhaseLabel.add_theme_color_override("font_color", UIKit.C_ALERT)
		# 屏幕中央大字提示 + 转阶段音效
		_show_center_announcement("第二阶段！", UIKit.C_ALERT)
		GameState.play_sfx("phase_change")
	else:
		$HUD/PhaseLabel.text = "BOSS 第一阶段"
		$HUD/PhaseLabel.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # 白色


## 屏幕中央大字提示：短暂放大浮现后渐隐
## ⚠ HUD 是 CanvasLayer，它下面的 Control 一律用**绝对 offset** 摆位；
##   曾用 anchors_preset=PRESET_CENTER，结果被算到左上角、字被裁掉一半（2026-11-08 截图发现）。
func _show_center_announcement(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(240.0, 300.0)
	label.size = Vector2(800.0, 120.0)
	# 从中心放大，别从左上角抻开
	label.pivot_offset = Vector2(400.0, 60.0)
	label.z_index = 30
	UIKit.soft_text_shadow(label, 2)
	$HUD.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.15)
	tween.tween_interval(0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _on_boss_died(_id: String) -> void:
	# 新手指引：打赢第一只 BOSS（试炼里的假 BOSS 不算，所以放在 rogue 分支之前拦掉）
	if BattleResolver.current_source() != BattleResolver.SOURCE_ROGUE:
		Tutorial.note("boss_died")
	# 试炼之路：不结算万界本源 / 功法 / 掉落，只推进到三选一
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		_timing = false
		_cleared = true
		GameState.trigger_slow_mo(0.5, 0.25)
		GameState.play_sfx("boss_death")
		if player != null and is_instance_valid(player) and player.has_method("_screen_shake"):
			player.call("_screen_shake", 8.0, 0.3)
		if _rogue != null and is_instance_valid(_rogue):
			_rogue.on_boss_defeated()
		return
	_timing = false
	# 首通快照：把此前累计死亡次数记成这只 BOSS 的「首通死亡次数」，重复通关不覆盖
	if BattleResolver.current_source() == BattleResolver.SOURCE_DOMAIN:
		var dctx: Dictionary = GameState.battle_context
		CharacterData.record_boss_first_clear_deaths(String(dctx.get("domain_id", "")),
			String(dctx.get("boss_id", "")))
	# 打赢 = 这一只的连败记录作废（连败只统计「同一只连续打死你」）
	CharacterData.clear_boss_fail(_fail_streak_key())
	# 战斗已结束：ESC 从这里开始不再问「放弃战斗」，而是推进收尾流程（见 _unhandled_input）
	_cleared = true
	_show_damage_report()
	# 结算奖励（位面产出万界本源；塔首杀的功法只出结果，等玩家在感悟 UI 里确认）
	var result := BattleResolver.resolve_victory()
	var reward := String(result.get("message", ""))
	# 本次待感悟的功法 id（空 = 不是塔首杀，或该层功法已全部掌握）
	_pending_insight = result.get("insight", [])
	# 通关用时只记进万界塔成绩；位面 BOSS 不记录通关时间
	var is_record := _record_clear_time()
	# 无伤通关：塔层 / 区域核心分支都按同一套规则
	#   - 塔层：任意一次全程未掉血 → 解锁该层一次性 50 晶石奖励（面板手动领）
	#   - 核心分支：第一次无伤直接发放 50 晶石（每个区域一次；分支没有记录碑）
	#   - 双倍气血场次（第 11 次起）无伤 → 卡包「纯华彩 · 无背景」
	var no_hit := false
	var no_hit_state := ""
	var core_nohit_bonus := 0
	if BattleResolver.current_source() in [BattleResolver.SOURCE_TOWER, BattleResolver.SOURCE_WORLD_CORE]:
		no_hit = player != null and is_instance_valid(player) \
			and not bool(player.get("took_damage_this_battle"))
		if no_hit and BattleResolver.current_source() == BattleResolver.SOURCE_TOWER:
			var floor_no := int(GameState.battle_context.get("floor", 0))
			CharacterData.mark_tower_no_hit_reward(floor_no)
			# 卡包「纯华彩 · 无背景」：无伤通关的必须是双倍气血场次（第 11 次起）
			if CharacterData.get_tower_clear_count(floor_no) >= CodexDB.HOLO_CLEAR_REQUIRED:
				CharacterData.mark_tower_no_hit_double(floor_no)
			no_hit_state = CharacterData.tower_no_hit_reward_state(floor_no)
		elif no_hit and BattleResolver.current_source() == BattleResolver.SOURCE_WORLD_CORE:
			var rid := String(GameState.battle_context.get("region_id", ""))
			# 通关次数已在 resolve_victory 里 +1；这一把是双倍血才记纯华彩
			if CharacterData.get_core_clear_count(rid) >= CodexDB.HOLO_CLEAR_REQUIRED:
				CharacterData.mark_core_no_hit_double(rid)
			core_nohit_bonus = CharacterData.grant_core_no_hit_reward(rid)
	# 按掉落表投掷掉落物，掉在 BOSS 尸身旁
	var drops := _spawn_drops(String(GameState.battle_context.get("boss_id", "")))

	# 中央大字幕「击杀成功」：停留 3 秒后渐隐
	var text := "击杀成功！"
	text += "\n用时 %s%s" % [CharacterData.format_duration(_elapsed), "　新纪录" if is_record else ""]
	if reward != "":
		text += "\n" + reward
	if no_hit:
		if BattleResolver.current_source() == BattleResolver.SOURCE_WORLD_CORE:
			text += ("\n无伤通关！+%d 锻造晶石" % core_nohit_bonus) if core_nohit_bonus > 0 \
				else "\n无伤通关！该核心的无伤奖励已领"
		elif no_hit_state == "ready":
			text += "\n无伤通关！可领取 %d 晶石" % CharacterData.TOWER_NO_HIT_BONUS_CRYSTALS
		else:
			text += "\n无伤通关！该层无伤奖励已领"
	if not drops.is_empty():
		text += "\n%s（走近按 F 拾取）" % ItemDB.drops_text(drops)
	_show_clear_banner(text)

	# 击杀镜头表现：慢动作 + 镜头震动 + 击杀音效，营造攻坚成功的仪式感
	GameState.trigger_slow_mo(0.5, 0.25)
	GameState.play_sfx("boss_death")
	if player.has_method("_screen_shake"):
		player._screen_shake(8.0, 0.3)
	_fade_out_battle_music()


## 通关计时入账：仅万界塔记录最快成绩，位面 BOSS 不计（用户要求取消位面通关时间记录）
## 返回是否刷新了纪录（非塔战斗恒为 false）
func _record_clear_time() -> bool:
	var source := BattleResolver.current_source()
	if source == BattleResolver.SOURCE_TOWER:
		var floor_no := int(GameState.battle_context.get("floor", 0))
		return CharacterData.record_tower_clear_time(floor_no, _elapsed)
	if source == BattleResolver.SOURCE_WORLD_CORE:
		var region_id := String(GameState.battle_context.get("region_id", ""))
		return CharacterData.record_core_clear_time(region_id, _elapsed)
	return false


## 通关大字幕：屏幕正中，从出现到完全消失总计 3 秒
## 节奏：完整显示 2 秒 → 1 秒渐隐 → 渐隐后先弹感悟面板（若有），再出返回按钮
func _show_clear_banner(text: String) -> void:
	var label := Label.new()
	label.text = text
	_clear_banner_label = label
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", UIKit.C_ANNOUNCE_TITLE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(140.0, 230.0)
	label.size = Vector2(1000.0, 240.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 30
	$HUD.add_child(label)

	var tween := label.create_tween()
	_clear_banner_tween = tween
	# 完整显示 2 秒
	tween.tween_interval(2.0)
	# 1 秒渐隐（含在此，总计 3 秒）
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		_clear_banner_label = null
		_clear_banner_tween = null
		label.queue_free()
	)
	# 渐隐结束 → 有待感悟功法则先弹感悟面板，否则直接出返回按钮
	tween.tween_callback(_after_clear_banner)


## ESC 跳过结算大字幕：立刻进入「感悟 / 返回按钮」环节
## 用途：塔层通关后玩家不想等那 3 秒，直接看这一把感悟到了什么
func _skip_clear_banner() -> void:
	if _clear_banner_tween != null and _clear_banner_tween.is_valid():
		_clear_banner_tween.kill()
	_clear_banner_tween = null
	if _clear_banner_label != null and is_instance_valid(_clear_banner_label):
		_clear_banner_label.queue_free()
	_clear_banner_label = null
	_after_clear_banner()


## 字幕结束后的分支：有感悟 → 弹感悟面板（面板关闭后才出返回按钮）
func _after_clear_banner() -> void:
	# 感悟面板已经被 ESC 提前弹出来了：等它关掉再出返回按钮（关掉时由 _on_insight_closed 接）
	if _insight_open:
		return
	if _pending_insight.is_empty():
		_show_return_button()
		return
	_open_insight_panel()


## 弹出「功法感悟」面板（就地感悟，不自动发放）
## 挂到 root 上：SystemPanel 是 CanvasLayer，不能挂在战斗场景的 Node2D 下
func _open_insight_panel() -> void:
	# 防重复：ESC 提前弹过一次之后，字幕的 tween 回调还会再走一遍 _after_clear_banner，
	# 这里必须拦住，否则会叠出第二个面板（且会重复连接 closed）
	if _pending_insight.is_empty() or _insight_open:
		return
	var floor_no := int(GameState.battle_context.get("floor", 0))
	var panel := InsightPanel.new()
	# ⚠ setup 必须在 add_child 之前：_ready 会立刻搭建结构并读取数据
	panel.setup(floor_no, _pending_insight)
	_pending_insight = []
	_insight_open = true
	get_tree().root.add_child(panel)
	panel.closed.connect(_on_insight_closed)
	panel.open()


## 感悟面板关闭（点「确认收下」或按 ESC 确认）→ 才出「返回原初位面」按钮
func _on_insight_closed() -> void:
	_insight_open = false
	_show_return_button()


## 左上角「返回原初位面」按钮：通关后出现，点击直接返回（不再走二次确认）
func _show_return_button() -> void:
	if _return_button != null and is_instance_valid(_return_button):
		return
	var btn := UIKit.primary_button("返回原初位面", Vector2(174, 42))
	btn.position = Vector2(24.0, 20.0)
	btn.z_index = 31
	btn.modulate.a = 0.0
	btn.pressed.connect(_on_return_button_pressed)
	btn.add_theme_font_size_override("font_size", 15)
	# 新手指引锚点：教学教玩家点这个按钮回城（c5 里出现两次）
	btn.set_meta("tut", "combat.return")
	$HUD.add_child(btn)
	_return_button = btn
	btn.create_tween().tween_property(btn, "modulate:a", 1.0, 0.35)
	# 塔通关后可 C 再战：在返回按钮旁常驻一行小提示，避免玩家不知道
	if BattleResolver.current_source() == BattleResolver.SOURCE_TOWER:
		var tip := UIKit.readable_label("按 C 再战一次", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
		tip.position = Vector2(196.0, 30.0)
		tip.z_index = 31
		$HUD.add_child(tip)


func _on_return_button_pressed() -> void:
	# 通关后的返回是「既定结果」，不需要再确认一次
	_return_to_realm()


## 区域核心首领重战的掉落：每次击杀固定掉它登记的核心装备（目前是藤甲）。
## 首杀专属核心材料 / 修为不在这里重复。
func _roll_world_core_repeat_drops() -> Array:
	var out: Array = []
	var region_id := String(GameState.battle_context.get("region_id", ""))
	var core := SecretWorldDB.get_core_boss(region_id)
	for raw in core.get("equipment_drops", []):
		var tpl_id := String(raw)
		var tpl := ItemDB.get_equipment_template(tpl_id)
		if tpl.is_empty():
			push_warning("核心首领掉落登记了未知装备模板：" + tpl_id)
			continue
		out.append({
			"type": CharacterData.ITEM_EQUIPMENT,
			"template_id": tpl_id,
			"item": CharacterData.make_equipment_instance(tpl),
			"count": 1,
		})
	return out


## 按掉落表生成可拾取掉落物；返回本次实际掉落的条目（空数组 = 没掉）
## 掉落来源分两路：
##   1. 位面 BOSS 掉落表（按 boss_id）——装备
##   2. 万界塔掉落表（按 floor）——锻造晶石，强化装备的唯一媒介
## 两路合并后一起落地，玩家逐个按 F 拾取。
func _spawn_drops(boss_id: String) -> Array:
	# 试炼之路不产出主模式掉落（唯一产出是结算时的锻造晶石）
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		return []
	var drops: Array = []
	# 区域核心重战：掉本首领的装备 + 锻造晶石（不重复首杀材料 / 功法）
	if BattleResolver.current_source() == BattleResolver.SOURCE_WORLD_CORE:
		drops.append_array(_roll_world_core_repeat_drops())
		var region_id := String(GameState.battle_context.get("region_id", ""))
		# 晶石数量按重战次数递减，与塔层同一张表（首胜 9 / 第二次 6 / 之后 3）
		var clear_index := CharacterData.get_core_clear_count(region_id)
		drops.append_array(ItemDB.roll_tower_drops(0, clear_index))
	# 位面/演武场：按 boss_id 投掷装备掉落（核心重战只走上面的专属装备表）
	if boss_id != "" and BattleResolver.current_source() != BattleResolver.SOURCE_WORLD_CORE:
		drops.append_array(ItemDB.roll_boss_drops(boss_id))
	# 万界秘境 BOSS：额外投掷锻造晶石（2026-11-10 用户定）。
	# ⚠ 必须按战斗来源分支 —— 塔投影复用同一个 boss_id，晶石走上面塔自己的表；
	#   数量看首杀标记（resolve_victory 在这一拍写进 battle_context）。
	if BattleResolver.current_source() == BattleResolver.SOURCE_DOMAIN:
		var n_crystal := DOMAIN_FIRST_KILL_CRYSTALS \
			if bool(GameState.battle_context.get("first_kill", false)) \
			else DOMAIN_REPEAT_CRYSTALS
		for _i in n_crystal:
			var crystal := ItemDB.make_material_drop(CharacterData.ENHANCE_MATERIAL)
			if not crystal.is_empty():
				drops.append(crystal)
	# 万界塔：额外投掷晶石（投影复用了本体 boss_id，必须按战斗来源区分）
	if BattleResolver.current_source() == BattleResolver.SOURCE_TOWER:
		var floor_no := int(GameState.battle_context.get("floor", 0))
		# 晶石数量按「第几次通关」浮动（首通 9 / 第二次 6 / 之后 3），
		# 通关次数已在 resolve_victory 里记好，这里直接读
		var clear_index := CharacterData.get_tower_clear_count(floor_no)
		drops.append_array(ItemDB.roll_tower_drops(floor_no, clear_index))
		# 蕴仙髓：塔层 BOSS 额外 5%（2026-11-13 用户定），落在地上自己捡
		var yunxian := ItemDB.roll_tower_yunxian_drop()
		if not yunxian.is_empty():
			drops.append(yunxian)
		# ★ BOSS 元魂（2026-10-21 用户定）：只有「血量翻倍」的场次（该层第 11 次及以后）才可能掉，
		#   概率 50%；**不限次数**（2026-10-21 晚改：取消「每种只掉一次」的限制）
		#   `obtained_souls` 仍然会记（拾取时写），但只作获得记录，不再拦截掉落
		# ⚠ 刚打完的是第 clear_index 次挑战，但 clear_count 已在结算里 +1；
		#   要用这一场开打时的倍率，不能读「下一次」的 tower_hp_multiplier（会早一场掉元魂）
		if floor_no > 0 and CharacterData.tower_hp_multiplier_at(clear_index) >= 2.0 - 0.001:
			if randf() < ItemDB.TOWER_SOUL_DROP_CHANCE:
				var soul := ItemDB.soul_for_boss(boss_id)
				var soul_id := String(soul.get("id", ""))
				if soul_id != "":
					var drop_entry := ItemDB.make_material_drop(soul_id)
					if not drop_entry.is_empty():
						drops.append(drop_entry)

	if drops.is_empty():
		return []

	var packed := load(ITEM_PICKUP_SCENE) as PackedScene
	if packed == null:
		push_warning("掉落物场景加载失败：" + ITEM_PICKUP_SCENE)
		return []
	# 多个掉落物在 BOSS 尸身旁随机散开（不是一排）：
	# 每件独立取随机角度/半径，并保证彼此至少隔开一点，避免叠在一起
	var base_pos: Vector2 = boss.global_position if is_instance_valid(boss) else Vector2.ZERO
	var count := drops.size()
	var used: Array[Vector2] = []
	for i in range(count):
		var d: Dictionary = drops[i]
		var pickup: Area2D = packed.instantiate()
		pickup.item = d.get("item", {})
		# 新手指引锚点：教学聚光要指向地上还没捡的掉落物（c5 捡晶石两步共用）
		pickup.set_meta("tut", "drop.item")
		var offset := Vector2(0.0, 26.0)
		if count > 1:
			for attempt in 8:
				var ang := randf() * TAU
				var radius := randf_range(40.0, 90.0)
				var cand := Vector2(cos(ang), sin(ang) * 0.55) * radius + Vector2(0.0, 16.0)
				var too_close := false
				for u in used:
					if cand.distance_to(u) < 42.0:
						too_close = true
						break
				if not too_close:
					offset = cand
					break
			used.append(offset)
		else:
			offset += Vector2(randf_range(-14.0, 14.0), randf_range(-6.0, 10.0))
		# 入树前设 position（未入树时 global_position 不生效）；夹在战场内
		var pos := base_pos + offset
		if arena_half_extents != Vector2.ZERO:
			pos.x = clampf(pos.x, -arena_half_extents.x + 48.0, arena_half_extents.x - 48.0)
			pos.y = clampf(pos.y, -arena_half_extents.y + 48.0, arena_half_extents.y - 48.0)
		pickup.position = pos
		add_child(pickup)
		_drops_on_ground.append(pickup)
	return drops


func _on_player_died() -> void:
	# 试炼之路：有复活就原地复活，没有就结算回主城
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		_timing = false
		GameState.trigger_slow_mo(0.4, 0.3)
		if player != null and is_instance_valid(player) and player.has_method("_screen_shake"):
			player.call("_screen_shake", 7.0, 0.25)
		if _rogue != null and is_instance_valid(_rogue):
			_rogue.on_player_died()
		return
	# 死亡不记录成绩，本关计时作废
	_timing = false
	$HUD/ResultLabel.text = "玩家死亡 - 按 C 重开"
	$HUD/ResultLabel.visible = true
	# 死亡镜头表现：慢动作 + 镜头震动
	GameState.trigger_slow_mo(0.4, 0.3)
	if player.has_method("_screen_shake"):
		player._screen_shake(7.0, 0.25)
	_fade_out_battle_music(1.2)
	# 连败提醒：同一只 BOSS 连着死两次，就在战败界面给出「怎么变强」的入口
	var streak := CharacterData.add_boss_fail(_fail_streak_key())
	# 万界秘境位面 BOSS 的累计死亡次数（塔 / 演武场不计）
	var deaths := 0
	if BattleResolver.current_source() == BattleResolver.SOURCE_DOMAIN:
		var dctx: Dictionary = GameState.battle_context
		deaths = CharacterData.add_boss_death(String(dctx.get("domain_id", "")),
			String(dctx.get("boss_id", "")))
	# 虎妖的「去取剑」提示优先占这块位置：同一场死亡只给一条最该做的建议
	if not _maybe_show_sword_hint(deaths) and streak >= BOSS_FAIL_HINT_AT:
		_show_grow_hint(streak)


## 连败计数的归属键：位面按 boss_id，万界塔按层号（同形投影与本体分开算），
## 演武场打木桩返回空串 = 不进统计
func _fail_streak_key() -> String:
	var ctx: Dictionary = GameState.battle_context
	var src := BattleResolver.current_source()
	if src == BattleResolver.SOURCE_TOWER:
		return "tower_%d" % int(ctx.get("floor", 0))
	if src == BattleResolver.SOURCE_DOMAIN:
		return String(ctx.get("boss_id", ""))
	if src == BattleResolver.SOURCE_WORLD_CORE:
		return "core_" + String(ctx.get("region_id", ""))
	return ""


## 提示里怎么称呼当前对手：已登记正式名的报名字（刀客 / 剑客 / 虎妖 / 两仪真人），
## 未定稿的占位名（"BOSS 03-B" 这类）与查不到的都退回空串，由调用方说「这一只」
func _boss_display_name() -> String:
	var bid := String(GameState.battle_context.get("boss_id", ""))
	if bid == "" or not WorldDB.BOSS_NAMES.has(bid):
		return ""
	var boss_name := String(WorldDB.get_boss_name(bid))
	if boss_name == "" or boss_name.begins_with("BOSS"):
		return ""
	return boss_name


## 战败提示横幅：压在 ResultLabel（y 300~380）下面、屏幕横向居中，整条可点
func _show_grow_hint(streak: int) -> void:
	if _grow_banner != null and is_instance_valid(_grow_banner):
		return
	var panel := PanelContainer.new()
	panel.name = "GrowHint"
	panel.custom_minimum_size = Vector2(660, 74)
	panel.position = Vector2(310.0, 396.0)
	panel.z_index = 32
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "翻开指引书 · 变强之道"
	panel.gui_input.connect(_on_grow_banner_input)
	var accent := UIKit.C_WARN
	panel.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.93, 0.70, 8))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := UIKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var col := UIKit.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var foe := _boss_display_name()
	var foe_text: String
	if foe == "":
		foe_text = "这一只"
	else:
		foe_text = "「%s」" % foe
	var head := UIKit.readable_label(
		"连续 %d 场无法战胜%s —— 怎么变强？" % [streak, foe_text], 18, Color(0.98, 0.93, 0.80))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var sub := UIKit.readable_label(
		"境界 / 装备 / 功法 / 法宝 / 丹药，按见效从大到小排好了", UIKit.F_SMALL, UIKit.C_TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	_grow_button = UIKit.primary_button("看指引", Vector2(116, 46))
	_grow_button.add_theme_font_size_override("font_size", 17)
	_grow_button.pressed.connect(_open_grow_guide)
	row.add_child(_grow_button)
	$HUD.add_child(panel)
	_grow_banner = panel
	# 入场：从下方 14px 浮起 + 淡入，让它「出现」而不是「一直在那」
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.24)
	tw.tween_property(panel, "position:y", 396.0, 0.24).from(410.0)


## 整条横幅都可点（右侧令签是按钮，两者走同一个出口）
func _on_grow_banner_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_open_grow_guide()


# ===== 虎妖战败 · 「封印松动」取剑提示 =====

## 虎妖死够两次 + 玩家还没拿到石台剑 → 弹「去取剑」卡。
## 返回 true = 这张卡占了战败提示的位置（调用方别再叠「怎么变强」横幅）。
## 「每次死亡都提示」= 只要条件成立就弹，不是只在第 2 次那一下。
## ⚠ 不用再判来源：`deaths` 只在真实位面战里累加（塔 / 演武场的死亡根本不进这张表），
##   塔里打虎妖投影时这里拿到的是 0。
func _maybe_show_sword_hint(deaths: int) -> bool:
	if deaths < SWORD_HINT_DEATHS:
		return false
	if String(GameState.battle_context.get("boss_id", "")) != SWORD_HINT_BOSS:
		return false
	# 前提：还没有这柄剑（背包 / 穿戴槽 / 法宝槽都算持有）
	if CharacterData.owns_equipment(SWORD_HINT_ITEM):
		return false
	_show_sword_hint_card()
	return true


## 战败卡：标题 + 一句话 + 「前往青岚野」。整张卡可点（和连败横幅同一个手感）。
## 位置压在 ResultLabel（y 300~380）上方，不和「按 C 重开」抢视线。
func _show_sword_hint_card() -> void:
	if _sword_hint != null and is_instance_valid(_sword_hint):
		return
	var panel := PanelContainer.new()
	panel.name = "SwordHint"
	panel.custom_minimum_size = Vector2(780, 126)
	panel.position = Vector2(250.0, 136.0)
	panel.z_index = 33
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "点击此卡 · 前往青岚野"
	panel.gui_input.connect(_on_sword_hint_input)
	var accent := Color(0.92, 0.79, 0.44)
	panel.add_theme_stylebox_override("panel", UIKit.accent_card_style(accent, 0.94, 0.74, 10))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var row := UIKit.hbox(20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var col := UIKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := UIKit.readable_label("青岚野 · 石台封印松动", 19, Color(0.99, 0.94, 0.80))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	# 文案按用户原话：青岚大陆有一柄剑，封印松动；获取此剑，可助你击败此獠
	var sub := UIKit.readable_label("青岚大陆有一柄剑，封印松动 —— 获取此剑，可助你击败此獠。",
		UIKit.F_SMALL, Color(0.88, 0.85, 0.78))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	var hint := UIKit.readable_label("点击此卡 · 直接打开青岚野", 11,
		Color(0.78, 0.74, 0.62, 0.85))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)

	var btn := UIKit.primary_button("前往青岚野", Vector2(150, 46), accent)
	btn.add_theme_font_size_override("font_size", 17)
	btn.pressed.connect(_goto_sword_region)
	row.add_child(btn)

	$HUD.add_child(panel)
	_sword_hint = panel
	# 入场：淡入 + 从下方浮起（与连败横幅同一套节奏，别做成「一直在那」）
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.26)
	tw.tween_property(panel, "position:y", 136.0, 0.26).from(150.0)


## 整张卡可点（按钮单独也走这个出口）
func _on_sword_hint_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_goto_sword_region()


## 回原初位面并**直接停在**「万界秘境 · 苍澜大陆 · 青岚野」那一页。
## ⚠ 走 _return_to_realm 的统一出口：它会区分「活着撤退 / 死了撤走」，
##   死了走这一步不会把这次的连败记录抹掉。
func _goto_sword_region() -> void:
	GameState.pending_panel = {
		"panel": "domain",
		"tab": "world",
		"region": SecretWorldDB.REGION_LIANQI,
	}
	_return_to_realm()


## 「看指引」令签呼吸：与角色面板 / 境界面板的突破提醒同一套参数
func _update_grow_pulse() -> void:
	if _grow_button == null or not is_instance_valid(_grow_button):
		return
	if _guide_panel != null and is_instance_valid(_guide_panel):
		_grow_button.modulate = Color.WHITE
		_grow_button.scale = Vector2.ONE
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	_grow_button.modulate = Color.WHITE.lerp(Color(1.0, 0.48, 0.32, 1.0), 0.45 + 0.35 * pulse)
	_grow_button.pivot_offset = _grow_button.size * 0.5
	_grow_button.scale = Vector2.ONE * (1.0 + 0.02 * pulse)


## 打开指引书并定位到「变强之道」页
## SystemPanel 是 CanvasLayer，不能挂在战斗场景的 Node2D 下 → 挂 root
func _open_grow_guide() -> void:
	if _guide_panel != null and is_instance_valid(_guide_panel):
		return
	var panel := GuidePanel.new()
	# ⚠ 必须在 add_child 之前注入：open() 会立刻按它翻到那一页
	panel.start_chapter_id = "grow"
	_guide_panel = panel
	panel.closed.connect(_on_guide_closed)
	get_tree().root.add_child(panel)
	panel.open()


func _on_guide_closed() -> void:
	_guide_panel = null


func _unhandled_input(event: InputEvent) -> void:
	# 入场卡开着时所有战斗快捷键让给卡片（ESC 由卡片自己吃掉）
	if _intro_open:
		return
	# 指引书开着时同理：ESC / C / F 都让给面板，不然会叠出「放弃战斗」确认框
	if _guide_panel != null and is_instance_valid(_guide_panel):
		return
	# ⚠ F（拾取）是全模式通用、无副作用的键，必须在下面的「模式分支」之前统一放行。
	#   试炼之路分支末尾有 return，以前把 F 放在下面的主模式 if/elif 链里 →
	#   试炼里按 F 完全没反应（2026-11-08 用户报「捡不了回血丹」）。
	#   探针当时直接调 _try_pickup_nearest()，绕过了输入入口，所以全绿却漏掉了这个 bug。
	#   以后再加模式分支也不会再吞掉它。
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F:
		_try_pickup_nearest()
		return
	# 重开键 C（R 已让给功法技能键 Q/E/R/T）
	# 开放条件：
	#   演武场 = 练习场 → 随时可按 C 重来
	#   正式战斗 → 玩家死亡后可按 C 重开（战斗中误按会白丢一场挑战）
	#   万界塔 → **通关后**也可按 C 立刻再战同一层（2026-10-24 用户定）
	# 试炼之路：关闭战斗内「按 C 重开」；ESC = 按当前层数结算并退出
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_ESCAPE and not _confirm_open:
			_confirm_open = true
			var dlg = ConfirmDialog.ask(
				"退出试炼",
				"退出将按当前层数结算（晶石照发），本局增益全部作废。",
				"退出并结算",
				"继续试炼",
				_rogue_quit_confirmed,
				true
			)
			dlg.cancelled.connect(func(): _confirm_open = false)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_C:
			if _can_c_restart():
				# 通关后还没确认感悟就按 C：先安全收下，再重开，绝不吞奖励
				if _cleared and BattleResolver.current_source() == BattleResolver.SOURCE_TOWER \
						and BattleResolver.has_pending_insight():
					BattleResolver.confirm_tower_rewards()
				_restart()
		elif training_mode and event.physical_keycode == KEY_Y:
			_open_training_skill_panel()
		elif training_mode and event.physical_keycode == KEY_H:
			_toggle_training_hud()
		elif event.physical_keycode == KEY_ESCAPE:
			# 通关后 ESC 不再问「放弃战斗」（战斗已经打完了，没进度可丢），
			# 而是**推进收尾流程**（2026-10-23 用户定）：
			#   ① 还有没确认的感悟 → 立刻跳过结算字幕、把感悟面板弹出来
			#      （不丢奖励，也不替玩家领悟 —— 领不领由面板上的确认决定）
			#   ② 已经确认过（或本层没有感悟）→ 直接返回原初位面
			# 感悟面板开着的时候走不到这里：ESC 被 InsightPanel 自己吃掉并当作「确认收下」。
			if _cleared:
				if not _pending_insight.is_empty():
					_skip_clear_banner()
				elif not _insight_open:
					_return_to_realm()
				return
			# 战斗中：二次确认，防止打到一半误触回城白丢一次挑战
			if not _confirm_open:
				_ask_return_to_realm()


## 拾取离玩家最近的、且玩家已走进范围内的掉落物
## auto = 自动拾取那一拍调的：失败不刷公告（每 0.12 秒喊一次太吵），成功照样给飘字。
func _try_pickup_nearest(auto: bool = false) -> void:
	_purge_drops()
	var nearest: Area2D = null
	var nearest_dist := 99999.0
	for p in _drops_on_ground:
		if not is_instance_valid(p) or not p.has_method("has_player_inside"):
			continue
		if not p.has_player_inside():
			continue
		var d := player.global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	if nearest == null:
		return
	if nearest.try_pickup():
		_drops_on_ground.erase(nearest)
		# ⚠ 局内归属（试炼回血丹等）由 pickup_handler 自己播公告，别再说「获得 X」——
		#   它根本不进背包，说「获得」会让人以为能带出局外。主模式掉落物不受影响。
		var handler: Variant = nearest.get("pickup_handler")
		var has_handler := false
		if handler is Callable:
			has_handler = (handler as Callable).is_valid()
		if not has_handler:
			# 背包满时物品溢到了仓库：提示必须说清落在哪，别让玩家以为丢了
			var went_warehouse := int(nearest.get("last_sink")) == 2
			_show_pickup_toast(String(nearest.item.get("name", "物品")), went_warehouse)
	elif not auto:
		# 背包与仓库都满：掉落物留在原地（自动拾取不重复喊这句）
		_show_center_announcement("背包与仓库都满了 —— 先整理一下", UIKit.C_ANNOUNCE_WARN)


## 清理已销毁 / 已被拾取的掉落物引用
func _purge_drops() -> void:
	for i in range(_drops_on_ground.size() - 1, -1, -1):
		if not is_instance_valid(_drops_on_ground[i]):
			_drops_on_ground.remove_at(i)


## 拾取提示：屏幕中下方浮字
func _show_pickup_toast(item_name: String, to_warehouse: bool = false) -> void:
	var label := Label.new()
	label.text = ("背包已满 · %s 已存入仓库" % item_name) if to_warehouse else ("获得 %s" % item_name)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", UIKit.C_ANNOUNCE_GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(340.0, 540.0)
	label.size = Vector2(600.0, 40.0)
	label.z_index = 30
	$HUD.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", 500.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)


## 开局提示：中央大字亮出本关名称，稍作停留后淡出
## 开场标题字：无入场卡的战斗（演武场 / 未做卡面的塔层）沿用旧的标题淡出
func _show_opening_announce() -> void:
	var label := Label.new()
	label.text = BattleResolver.battle_title()
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", UIKit.C_ANNOUNCE_TITLE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(320.0, 248.0)
	label.size = Vector2(640.0, 110.0)
	label.pivot_offset = Vector2(320.0, 55.0)
	label.z_index = 30
	$HUD.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.08, 1.08), 0.18)
	tween.tween_interval(0.75)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


# ===================== BOSS 入场卡 =====================

## 停时 + 亮卡；恢复暂停由卡片的 closed 信号负责（卡片自己淡出后才放行）
func _start_boss_intro(entry: Dictionary) -> void:
	get_tree().paused = true
	_intro_open = true
	var card := BossIntroCard.new()
	card.name = "BossIntroCard"
	card.closed.connect(_on_intro_closed)
	add_child(card)
	card.open(entry, {
		"title": BattleResolver.battle_title(),
		"source_line": _intro_source_line(entry),
		"hud": $HUD,
	})
	card.attach_music(_music_player, BgmPlayer.BATTLE_VOLUME_DB)


## 卡片第二行：位面用图鉴副标题；塔 / 核心重战显示重复挑战次数与血量加成
func _intro_source_line(entry: Dictionary) -> String:
	if BattleResolver.current_source() == BattleResolver.SOURCE_WORLD_CORE:
		var rid := String(GameState.battle_context.get("region_id", ""))
		var clears := CharacterData.get_core_clear_count(rid)
		var line := "苍澜大陆 · 核心重战"
		if clears > 0:
			var mult := CharacterData.core_hp_multiplier(rid)
			line += "　　第 %d 次 · 血量 +%d%%" % [
				clears + 1, int(round((mult - 1.0) * 100.0))]
		return line
	if BattleResolver.current_source() == BattleResolver.SOURCE_DOMAIN:
		var dctx: Dictionary = GameState.battle_context
		var dline := String(entry.get("subtitle", ""))
		var deaths := CharacterData.get_boss_death(String(dctx.get("domain_id", "")),
			String(dctx.get("boss_id", "")))
		if deaths > 0:
			dline += "　　◆ 已死亡 %d 次" % deaths
		return dline
	if BattleResolver.current_source() != BattleResolver.SOURCE_TOWER:
		return String(entry.get("subtitle", ""))
	var floor_no := int(GameState.battle_context.get("floor", 0))
	var line := "万界塔 · 第 %d 层" % floor_no
	var clears := CharacterData.get_tower_clear_count(floor_no)
	if clears > 0:
		var mult := CharacterData.tower_hp_multiplier(floor_no)
		line += "　　第 %d 次挑战 · 血量 +%d%%" % [
			clears + 1, int(round((mult - 1.0) * 100.0))]
	return line


func _on_intro_closed() -> void:
	_intro_open = false
	get_tree().paused = false


## ESC → 确认是否返回原初位面（确认框打开期间游戏暂停，BOSS 不会偷袭）
func _ask_return_to_realm() -> void:
	_confirm_open = true
	var dlg
	if training_mode:
		dlg = ConfirmDialog.ask(
			"离开演武场",
			"返回原初位面？本次木桩训练记录不会保留。",
			"返回原初位面",
			"继续训练",
			_return_to_realm,
			true
		)
	else:
		dlg = ConfirmDialog.ask(
			"返回原初位面",
			"确定放弃当前战斗，返回原初位面吗？\n本次未完成的挑战不会保留进度。",
			"返回原初位面",
			"继续战斗",
			_return_to_realm,
			true
		)
	dlg.cancelled.connect(func(): _confirm_open = false)


## 当前是否允许按 C 重开
## 万界塔通关后也允许（但感悟面板开着时交给面板处理，不能把面板盖在重载下面）
func _rogue_quit_confirmed() -> void:
	_confirm_open = false
	if _rogue != null and is_instance_valid(_rogue):
		_rogue.request_quit()


func _can_c_restart() -> bool:
	if BattleResolver.current_source() == BattleResolver.SOURCE_ROGUE:
		return false
	if BattleResolver.current_source() == BattleResolver.SOURCE_ARENA:
		return true
	if player != null and is_instance_valid(player) and bool(player.get("is_dead")):
		return true
	if _cleared and not _insight_open \
			and BattleResolver.current_source() == BattleResolver.SOURCE_TOWER:
		return true
	return false


func _restart() -> void:
	# 重开不再亮入场卡：重试节奏优先（一次性标记，由下一次战斗场景消费）
	BattleResolver.skip_next_intro = true
	# 重开副本 = 全新一场：丹药 / 符箓冷却与全部 buff / debuff 都刷新
	BattleWheel.reset_battle_state()
	if player != null and is_instance_valid(player):
		player.reset_player()
	GameState.reset_time_flow()
	get_tree().reload_current_scene()


## 返回原初位面（所有战斗来源的统一出口）
func _return_to_realm() -> void:
	# 撤退时的死活必须在 reset_player 之前取：重置会把 is_dead 清掉，
	# 之后就没法区分「活着放弃」和「死了撤走」（死了撤走仍算一次连败）
	var died := player != null and is_instance_valid(player) and bool(player.get("is_dead"))
	# 退出副本：清空丹药 / 符箓冷却与玩家全部 buff / debuff
	BattleWheel.reset_battle_state()
	if player != null and is_instance_valid(player):
		player.reset_player()
	GameState.reset_time_flow()
	# 保险：还有没确认的感悟就先收下 —— 打赢了不该什么都拿不到。
	# 正常路径走不到这里（通关后 ESC 会先把感悟面板弹出来，确认完才允许返回），
	# 只有异常退出（例如外部直接调返回）才会命中。
	if BattleResolver.has_pending_insight():
		BattleResolver.confirm_tower_rewards()
	# 活着主动撤退 = 放弃这一只，连败计数清零；死了才撤的不清（那次失败已经算数）
	if not died:
		CharacterData.clear_boss_fail(_fail_streak_key())
	# 清空战斗来源上下文，避免下次进战斗沿用旧来源
	BattleResolver.clear()
	# 新手指引：回城动作要报给教学（c5 的「返回原初位面」两步都听这个事件；
	# 放在 confirm 兜底之后 —— 感悟在那几行里补收，skill_learned 先于本事件入账）
	Tutorial.note("returned_realm")
	get_tree().change_scene_to_file("res://scenes/main/primordial_realm.tscn")
