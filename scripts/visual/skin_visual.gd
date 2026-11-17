@tool
class_name SkinVisual
extends Node2D
## 通用视觉节点 —— 美术替换的唯一接入点
##
## 一个实体（玩家 / BOSS / 投射物 / 掉落物）把「长什么样」全部交给本节点。
## 玩法代码只操作本节点（scale 翻转朝向、modulate 闪色、duplicate 残影），
## 因此**替换美术时玩法代码一行都不用改**。
##
## 渲染优先级（自动选择，无需人工干预）：
##   1. ArtDB 里登记了 texture + frames > 1  → AnimatedSprite2D（多帧动画）
##   2. 登记了 texture + frames == 1         → Sprite2D（单帧贴图）
##   3. 没登记 texture                        → 程序化占位（纯色矩形，即当前阶段形态）
##
## 用法：
##   var v := SkinVisual.new()
##   v.visual_id = "player_liqingyun"
##   节点入树后自动构建。之后随时可调 refresh() 热重载。

## 向 ArtDB 取配置用的 id（见 ArtDB.VISUALS 的键）
@export var visual_id: String = ""

## 可选：当 visual_id 未在 ArtDB 登记时使用的回退 id
## 例如设施统一用 "facility_<id>"，未单独登记时回退到 "facility_generic"
@export var fallback_visual_id: String = ""

## 可选：整条视觉配置覆盖（优先级最高，跳过 ArtDB 查询）
## 用途：同一 id 的异色变体 / 精英怪、测试时临时指定贴图，无需往 ArtDB 加条目
## 置为空字典表示不覆盖
## 注意：必须 @export，否则 Node.duplicate() 不会复制它，
##       导致「残影」等复制体丢失配置而退化成默认占位
@export var config_override: Dictionary = {}

## 可选：覆盖配置里的占位色（如掉落物按品阶着色）
## 置为 Color(0,0,0,0) 表示不覆盖，沿用 ArtDB 的 placeholder_color
## 同样需要 @export 以保证 Node.duplicate()（残影）能带走
@export var placeholder_color_override: Color = Color(0, 0, 0, 0)
## 可选：覆盖配置里的占位尺寸（如设施沿用场景碰撞体尺寸）
## 置为 Vector2.ZERO 表示不覆盖，沿用 ArtDB 的 placeholder_size
@export var placeholder_size_override: Vector2 = Vector2.ZERO

## 可直接在检查器里指定的 SpriteFrames（拖入资源，或点开选 .tres 文件）
## **优先级最高** —— 适合「动画资源内嵌在场景里」的配法，不必经过 ArtDB 的路径字段
## ⚠ 内嵌资源只有本场景能用（别的场景引用不到）；要跨场景共用请存成 .tres 再填 ArtDB
@export var sprite_frames_override: SpriteFrames = null:
	set(value):
		sprite_frames_override = value
		if Engine.is_editor_hint() and is_inside_tree():
			refresh()

## 可选：在检查器里覆盖缩放（Vector2.ZERO 表示不覆盖，改用 ArtDB 配置）
## 用途：在编辑器里拖数字直接调角色大小，**改完立刻在场景视图看到效果**，不必改数据表
## ⚠ 这是「本节点专用」的覆盖：战斗玩家和主城玩家是两个场景，需各调一次
@export var scale_override: Vector2 = Vector2.ZERO:
	set(value):
		scale_override = value
		if Engine.is_editor_hint() and is_inside_tree():
			refresh()

## 可选：在检查器里覆盖偏移（同样 ZERO = 不覆盖）
## 一般不需要动：勾选了 anchor_bottom 后脚底会自动对齐
@export var offset_override: Vector2 = Vector2.ZERO:
	set(value):
		offset_override = value
		if Engine.is_editor_hint() and is_inside_tree():
			refresh()

## 占位色块尺寸（未接入贴图时用）
var _placeholder_size: Vector2 = Vector2(32.0, 32.0)
var _placeholder_color: Color = Color(0.8, 0.8, 0.8, 1.0)

## 当前实际渲染节点（Sprite2D / AnimatedSprite2D / ColorRect），供调试与外部微调
var render_node: Node = null
## 当前是否使用了真实贴图（false = 走的占位）
var using_texture: bool = false
## 当前形象在局部坐标下的包围盒（以本节点原点为基准，供血条 / 受击点定位）
var visual_rect: Rect2 = Rect2()

## 配置缓存
var _cfg: Dictionary = {}

## 自动缩放结果缓存（key = "贴图路径|目标长度"）
## ⚠ 必须缓存：_apply_auto_fit 里 get_image() + get_used_rect() 会**扫描整张图片素**，
##   批量实体（万剑归宗十几把飞剑）逐个实例化时，每把都扫一次大图会明显掉帧。
##   当前飞剑还没接贴图（走占位）看不出问题，等美术就位后这就是必踩的坑 —— 先堵上。
static var _auto_fit_cache: Dictionary = {}

## 是否处于「移动中」：驱动行走动画的播放 / 暂停
## 初值 true 是为了向后兼容 —— 没人调用 set_moving 的实体（BOSS / 设施 / 投射物）
## 会保持「一直循环播放」，与本字段加入之前的行为完全一致
var _is_moving: bool = true

## 当前朝向（归一化）。默认朝下 —— 与初版只有朝下素材时的行为一致
## 由角色控制器通过 set_facing() 每帧更新
var _facing_dir: Vector2 = Vector2.DOWN

## ===== 一次性动作（攻击 / 受击等）=====
## 非空时**优先于**移动/待机动画，期间 set_moving / set_facing 都不切走；
## 播完（或 duration 到）自动清空并回到常规状态。
## 用计时器而不是 animation_finished 信号：动画可能被下一次攻击打断，
## 且时长由攻击后摇决定（41 帧塞进 0.35s 的普攻后摇），不依赖资源 fps。
var _one_shot: String = ""
var _one_shot_left: float = 0.0


func _ready() -> void:
	# 没有一次性动作时不跑 _process（避免给每个实体都加每帧开销）
	set_process(false)
	refresh()


## 当前资源里是否有这个动画（没有专用序列帧时，调用方可以回退到别的动作）
func has_animation(anim_name: String) -> bool:
	if render_node is BossRig:
		return (render_node as BossRig).has_animation(anim_name)
	if not (render_node is AnimatedSprite2D):
		return false
	var a := render_node as AnimatedSprite2D
	return a.sprite_frames != null and a.sprite_frames.has_animation(anim_name)


## 播放一次性动作（攻击动画等）：播完自动回到待机/行走
## duration <= 0 时用资源里的原始速度（帧数 / fps）
## ⚠ 内部用 speed_scale 把整段动画压进 duration，所以 41 帧也能正好填满 0.35 秒后摇
func play_one_shot(anim_name: String, duration: float = -1.0) -> void:
	# 骨骼 BOSS：招式走 rig 内的序列帧覆盖层，时长换算与下面完全一致
	if render_node is BossRig:
		var rig := render_node as BossRig
		var natural := rig.animation_length(anim_name)
		if natural <= 0.0:
			return
		_one_shot = anim_name
		_one_shot_left = natural if duration <= 0.0 else maxf(duration, 0.02)
		rig.play_one_shot(anim_name, _one_shot_left)
		set_process(true)
		return
	if not (render_node is AnimatedSprite2D):
		return
	var a := render_node as AnimatedSprite2D
	if a.sprite_frames == null or not a.sprite_frames.has_animation(anim_name):
		return
	var fps := maxf(a.sprite_frames.get_animation_speed(anim_name), 1.0)
	var natural := float(a.sprite_frames.get_frame_count(anim_name)) / fps
	_one_shot = anim_name
	_one_shot_left = natural if duration <= 0.0 else maxf(duration, 0.02)
	a.speed_scale = natural / _one_shot_left
	a.animation = anim_name
	a.frame = 0
	a.play(anim_name)
	set_process(true)


## 立即结束一次性动作（攻击被闪避/弹刀取消时调），恢复待机/行走
func cancel_one_shot() -> void:
	if _one_shot == "":
		return
	_one_shot = ""
	_one_shot_left = 0.0
	if render_node is BossRig:
		(render_node as BossRig).stop_one_shot()
	elif render_node is AnimatedSprite2D:
		(render_node as AnimatedSprite2D).speed_scale = 1.0
	set_process(false)
	_apply_anim_state()


## 一次性动作计时：到点清空并恢复常规动画
## ⚠ 用 delta 递减（而非真实时钟），慢动作时动作与会话一起放慢，观感一致
func _process(delta: float) -> void:
	if _one_shot == "":
		set_process(false)
		return
	_one_shot_left -= delta
	if _one_shot_left > 0.0:
		return
	# 骨骼招式：计时器到点后再确认一次「播放头真的到底了」。
	# 首帧 delta 异常大时（进场 / 卡顿）计时器会先归零，直接收招就会把
	# 「爆发 + 打击定格」整段吞掉（实测横斩只挥到一半）。留 0.35 秒硬上限兜底：
	# 动画若因故卡住不动，也不能让 BOSS 永远停在招式里。
	if render_node is BossRig:
		var rig_done := render_node as BossRig
		if not rig_done.one_shot_finished() and _one_shot_left > -0.35:
			return
	_one_shot = ""
	if render_node is BossRig:
		(render_node as BossRig).stop_one_shot()
	elif render_node is AnimatedSprite2D:
		(render_node as AnimatedSprite2D).speed_scale = 1.0
	set_process(false)
	_apply_anim_state()


## 按当前 visual_id 重建视觉（可在运行时调用以热替换贴图）
func refresh() -> void:
	# 配置来源优先级：整条覆盖 > visual_id > fallback_visual_id > 默认条目
	if not config_override.is_empty():
		var merged := ArtDB.DEFAULT_ENTRY.duplicate(true)
		for k in config_override.keys():
			merged[k] = config_override[k]
		_cfg = merged
	elif ArtDB.VISUALS.has(visual_id) or fallback_visual_id == "":
		_cfg = ArtDB.get_visual(visual_id)
	else:
		_cfg = ArtDB.get_visual(fallback_visual_id)
	_placeholder_size = _cfg.get("placeholder_size", Vector2(32.0, 32.0))
	_placeholder_color = _cfg.get("placeholder_color", Color(0.8, 0.8, 0.8, 1.0))
	# 外部指定的占位色优先级最高（如掉落物按品阶着色、设施沿用场景配色）
	if placeholder_color_override.a > 0.0:
		_placeholder_color = placeholder_color_override
	if placeholder_size_override != Vector2.ZERO:
		_placeholder_size = placeholder_size_override

	_clear_render_node()

	var sf_path := String(_cfg.get("sprite_frames", ""))
	var tex_path := String(_cfg.get("texture", ""))
	var rig_path := String(_cfg.get("rig", ""))
	var frames := int(_cfg.get("frames", 1))
	using_texture = false

	# ⓪ 骨骼 rig（四足 BOSS）：idle / walk 由骨骼驱动，招式仍用同条目的 SpriteFrames
	#    作为覆盖层。优先级最高 —— 配了 rig 就说明「移动必须丝滑」，不能回落到序列帧。
	if rig_path != "" and ResourceLoader.exists(rig_path):
		using_texture = _build_rig(rig_path)

	# ① 检查器直接指定的 SpriteFrames（可以是场景内嵌资源，优先级最高）
	if not using_texture and sprite_frames_override != null:
		using_texture = _build_from_frames(sprite_frames_override)

	# ② ArtDB 里填的 .tres 路径
	if not using_texture and sf_path != "" and ResourceLoader.exists(sf_path):
		using_texture = _build_from_sprite_frames(sf_path)

	# ② 兜底：单张 PNG（frames > 1 走代码切分图集；== 1 走 Sprite2D）
	if not using_texture and tex_path != "" and ResourceLoader.exists(tex_path):
		if frames > 1:
			using_texture = _build_animated(tex_path, frames)
		else:
			using_texture = _build_sprite(tex_path)

	# 未接入贴图 / 加载失败 → 占位
	if not using_texture:
		_build_placeholder()

	_apply_auto_fit()
	_apply_common_transform()
	_apply_anim_state()
	_apply_shader_material()


## 设置「是否在移动」：移动时循环播，静止时停在中性帧
## 只对多帧动画生效（frames > 1）；单帧贴图与占位色块直接忽略。
## 由角色控制器每帧调用（player.gd / primordial_player.gd 的 _update_visual）。
## 中性帧由配置项 idle_frame 决定（默认 0 = 图集第一帧）。
func set_moving(moving: bool) -> void:
	if moving == _is_moving:
		return
	_is_moving = moving
	_apply_anim_state()


## 设置当前朝向（由角色控制器每帧调用，静止时也要调 —— 站着朝上就该显示背面）
## 只在资源里存在按方向命名的动画时才产生效果；只有单个 idle 的资源行为完全不变
##
## 动画命名约定（缺哪套就自动退化到下一档）：
##   walk_down / walk_up / walk_side   ← 推荐：左右共用一套 side，靠 scale.x 翻转
##   walk_left / walk_right            ← 可选：左右各画一套（此时不应再翻转）
##   walk / run / idle / 第一个动画     ← 兜底
func set_facing(dir: Vector2) -> void:
	if dir.length_squared() <= 0.0001:
		return
	var d := dir.normalized()
	# 按「上下左右」档位比较，避免斜向移动时每帧都触发动画切换
	if _facing_key_of(d) == _facing_key():
		return
	_facing_dir = d
	_apply_anim_state()


## 朝向 → 动画关键词（右/左/下/上）
func _facing_key_of(d: Vector2) -> String:
	if absf(d.x) > absf(d.y):
		return "right" if d.x > 0.0 else "left"
	return "down" if d.y >= 0.0 else "up"


func _facing_key() -> String:
	return _facing_key_of(_facing_dir)


## 按当前朝向挑「行走」动画；找不到返回空串
## 候选顺序：walk_<当前方向> → walk_side → walk → run
## ⚠ walk_side 是**所有方向**的次选：本项目只做了一套侧向行走（用户 2026-10-19 定，不做朝下/朝上），
##   上下移动也播它，方向感靠 Visual.scale.x 翻转表达。若哪天补了 walk_up/walk_down，会自动优先用它们。
func _facing_anim(sf: SpriteFrames) -> String:
	var key := _facing_key()
	var candidates: Array[String] = ["walk_" + key]
	candidates.append("walk_side")
	candidates.append("walk")
	candidates.append("run")
	for c in candidates:
		if sf.has_animation(c):
			return c
	return ""


## 决定「现在该播哪个动画」
## 移动中 → 对应方向的行走动画；静止 → 停在同方向行走动画上（保持朝向），
## 没有方向动画时退回 idle / 第一个动画
func _desired_anim(sf: SpriteFrames) -> String:
	var names := sf.get_animation_names()
	if names.is_empty():
		return ""
	var walking := _facing_anim(sf)
	if not _is_moving:
		# 静止：优先专用待机动画（idle / daiji），有就循环播它
		var idle_now := _idle_anim(sf)
		if idle_now != "":
			return idle_now
		# 没有待机动画：沿用旧行为（停在当前方向的行走帧当站立）
		if walking != "":
			return walking
		return names[0]
	if walking != "":
		return walking
	var idle_move := _idle_anim(sf)
	if idle_move != "":
		return idle_move
	return names[0]


## 待机动画候选名：`idle`（英文约定）→ `daiji`（中文拼音别名，2026-10-19 站立素材用这个名）
func _idle_anim(sf: SpriteFrames) -> String:
	if sf == null:
		return ""
	if sf.has_animation(ArtDB.ANIM_IDLE):
		return ArtDB.ANIM_IDLE
	if sf.has_animation("daiji"):
		return "daiji"
	return ""


## 把「移动 / 静止」同步到 AnimatedSprite2D
## 用 pause 而不是 stop：stop 会把帧重置到 0 并清空播放进度，
## 而 pause 保留当前位置，恢复播放时不跳帧
func _apply_anim_state() -> void:
	# 骨骼 BOSS：只有两条循环（walk / idle）+ 招式覆盖层，没有按方向分套动画 ——
	# 朝向由外层 Visual.scale.x 翻转表达，和序列帧的 walk_side 同一口径。
	if render_node is BossRig:
		var rig := render_node as BossRig
		if _one_shot != "" and rig.has_animation(_one_shot):
			rig.play_one_shot(_one_shot, _one_shot_left)
			return
		rig.play_loop("walk" if _is_moving else "idle")
		return
	if not (render_node is AnimatedSprite2D):
		return
	var a := render_node as AnimatedSprite2D
	if a.sprite_frames == null:
		return
	# ★ 一次性动作优先（攻击/受击）：播完前不受移动、朝向、待机逻辑影响
	if _one_shot != "" and a.sprite_frames.has_animation(_one_shot):
		if a.animation != _one_shot:
			a.animation = _one_shot
			a.frame = 0
		if not a.is_playing():
			a.play(_one_shot)
		return
	var anim := _desired_anim(a.sprite_frames)
	if anim == "":
		return
	# 朝向变化时需要真正切到另一个动画（同一个 AnimatedSprite2D 上换 animation）
	if a.animation != anim:
		a.animation = anim
	if _is_moving:
		if not a.is_playing():
			a.play(anim)
	else:
		# 静止：有专用待机动画（idle / daiji）→ 循环播放；
		# 没有 → 暂停并停在 idle_frame（旧行为，用行走帧挑一帧当站立）
		if _idle_anim(a.sprite_frames) != "":
			if not a.is_playing():
				a.play(anim)
		else:
			if a.is_playing():
				a.pause()
			# idle_frame 可能超出该动画的帧数（换过素材后尤其容易），clamp 住避免越界
			var last: int = maxi(0, a.sprite_frames.get_frame_count(anim) - 1)
			a.frame = clampi(int(_cfg.get("idle_frame", 0)), 0, last)


func _clear_render_node() -> void:
	if render_node != null and is_instance_valid(render_node):
		remove_child(render_node)
		render_node.queue_free()
	render_node = null


## 从原生 SpriteFrames 资源（.tres / .res）构建 AnimatedSprite2D
## 这是**正式美术素材的推荐路径**：帧切分、帧序、帧率全部在 Godot 的 SpriteFrames 面板里配好，
## 代码只负责加载与播放。缺动画 / 资源损坏时返回 false，由上层回落到 PNG 或占位。
func _build_from_sprite_frames(sf_path: String) -> bool:
	# 走 SkinWarm：被点名预载过的表已经在主线程之外解好码了，直接取；
	# 没点名的仍然同步 load（行为与旧写法一致）。详见 skin_warm.gd 的说明。
	var res: Resource = SkinWarm.resource(sf_path)
	if res == null:
		push_warning("SkinVisual：SpriteFrames 加载失败 → %s" % sf_path)
		return false
	var sf := res as SpriteFrames
	if sf == null:
		push_warning("SkinVisual：%s 不是 SpriteFrames 资源" % sf_path)
		return false
	return _build_from_frames(sf)


## 从 BossRigData 构建骨骼形象（四足 BOSS）
## 骨骼只负责 idle / walk；同条目的 sprite_frames 会作为「招式覆盖层」挂进去，
## 两套素材画布相同，出招时隐藏骨骼、显示序列帧，不会错位。
func _build_rig(rig_path: String) -> bool:
	var res: Resource = SkinWarm.resource(rig_path)
	var data := res as BossRigData
	if data == null:
		push_warning("SkinVisual：%s 不是 BossRigData（class_name 可能还没被编辑器扫描到）" % rig_path)
		return false
	# 骨骼动画集由数据指定：空 = 四足（BossRig），人形填 boss_rig_human.gd。
	# ⚠ 换 BOSS 只换 .tres，不改这里的代码 —— 与「美术可替换性最高优先」一致。
	var rig: BossRig = BossRig.new()
	if data.rig_script != "" and ResourceLoader.exists(data.rig_script):
		# ⚠ 必须 as GDScript：`new()` 是 GDScript 自己的构造方法，不是 `Script` 基类的，
		#   写成 `var sc: Script = load(...)` 再 `sc.new()` 会在运行期报
		#   「Nonexistent function 'new' in base 'GDScript'」，然后静默回落序列帧。
		var sc := load(data.rig_script) as GDScript
		if sc != null and sc.can_instantiate():
			var inst: Variant = sc.new()
			if inst is BossRig:
				rig = inst
			else:
				push_warning("SkinVisual：%s 不是 BossRig 的子类，回落四足版" % data.rig_script)
		else:
			push_warning("SkinVisual：%s 编译失败（can_instantiate=false），回落四足版" % data.rig_script)
	rig.name = "BossRig"
	add_child(rig)
	if not rig.setup(data):
		rig.queue_free()
		return false
	# 招式序列帧：同条目的 sprite_frames，缺了也不影响骨骼跑
	# ⚠ 这几张表是**有损压缩、非 VRAM** 的导入档，同步 load 要在主线程解码整张图集：
	#   实测石犼 455ms、刀客 190ms，正是快速模式点「开战」那一帧的主要开销。
	#   预载由 SkinWarm 在工作线程做完，这里只取现成的（没预载过仍走同步兜底）。
	var sf_path := String(_cfg.get("sprite_frames", ""))
	if sf_path != "" and ResourceLoader.exists(sf_path):
		var sf := SkinWarm.resource(sf_path) as SpriteFrames
		if sf != null:
			rig.attach_frames(sf)
	render_node = rig
	return true


## 用已经拿到的 SpriteFrames 构建节点
## 「检查器直接指定」与「按 .tres 路径加载」两条入口都走这里，保证行为一致
func _build_from_frames(sf: SpriteFrames) -> bool:
	if sf == null:
		return false
	if sf.get_animation_names().is_empty():
		push_warning("SkinVisual：SpriteFrames 里没有任何动画")
		return false

	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	var anim := _pick_anim(sf)
	spr.animation = anim
	spr.autoplay = anim
	spr.play()
	add_child(spr)
	render_node = spr
	return true


## 选一个要播放的动画：优先 idle；资源里叫别的名字（如 Godot 默认的 default）就用第一个
## ⚠ 在 Godot 里建 SpriteFrames 时动画名默认是 "default"，不会自动叫 idle，
##   所以这里必须做兼容，否则会「有资源但不动」
func _pick_anim(sf: SpriteFrames) -> String:
	if sf == null:
		return ""
	if sf.has_animation(ArtDB.ANIM_IDLE):
		return ArtDB.ANIM_IDLE
	var names := sf.get_animation_names()
	return names[0] if names.size() > 0 else ""


## 多帧：走 AnimatedSprite2D，循环播放 idle
func _build_animated(tex_path: String, frames: int) -> bool:
	var fps := float(_cfg.get("fps", 8.0))
	var frame_size: Vector2 = _cfg.get("frame_size", Vector2.ZERO)
	var sf: SpriteFrames
	# 优先当成 SpriteFrames 资源（.tres）加载；否则按横向图集切
	if tex_path.ends_with(".tres") or tex_path.ends_with(".res"):
		sf = load(tex_path)
	else:
		sf = ArtDB.build_sprite_frames(tex_path, frame_size, fps)
	if sf == null or sf.get_animation_names().is_empty():
		return false

	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	var anim := _pick_anim(sf)
	spr.animation = anim
	spr.autoplay = anim
	spr.play()
	add_child(spr)
	render_node = spr
	return true


## 单帧：走 Sprite2D
func _build_sprite(tex_path: String) -> bool:
	var tex: Texture2D = load(tex_path)
	if tex == null:
		return false
	var spr := Sprite2D.new()
	spr.texture = tex
	add_child(spr)
	render_node = spr
	return true


## 占位：纯色矩形（保持与既有 ColorRect 占位外观一致）
## 摆放位置由 _apply_common_transform 统一负责（以原点为中心 / 底部对齐）
func _build_placeholder() -> void:
	var rect := ColorRect.new()
	rect.color = _placeholder_color
	rect.size = _placeholder_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	render_node = rect


## 统一应用缩放 / 偏移 / 底部对齐
##
## 约定：本节点原点 = 实体逻辑原点（碰撞体中心）。
##   - 占位色块 / Sprite2D 默认以原点为中心摆放
##   - anchor_bottom = true 时，把形象整体上移「半个高度 + 偏移」，
##     使图像底部落在原点下沿，符合俯视角「脚踩地面」的习惯
##   - offset 在底部对齐之后再叠加，用于美术微调
## 按「目标显示长度」自动算 scale 与 offset —— 换图不用再手算
## 原理：读贴图的**非透明区域**（used_rect），用内容高度除以目标长度得到 scale；
## 再把内容中心补偿到节点原点，保证旋转/缩放绕的是「看得见的部分」而不是带透明边的画布。
## 只对单帧贴图生效：多帧图集的 used_rect 覆盖的是整张图，算出来没有意义。
## 贴图着色器（可选）：ArtDB 条目里填 `shader` 就会给这个形象挂 ShaderMaterial，
## 额外 uniform 写在 `shader_params`（键 = uniform 名）。
## 用途：**不改美术素材**，只用代码改变这张贴图的呈现（如地面星点流动）。
## ⚠ 只作用于渲染节点（render_node），不影响玩法逻辑、残影快照与 _flash_attack 的 modulate。
func _apply_shader_material() -> void:
	var path := String(_cfg.get("shader", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	if render_node == null or not (render_node is CanvasItem):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	var params: Dictionary = _cfg.get("shader_params", {})
	# 贴图尺寸默认自动填：shader 里要用它把「每秒多少像素」换算成 UV 偏移
	if not params.has("tex_size"):
		var tex := current_texture()
		if tex != null:
			mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	for k in params.keys():
		var v = params[k]
		# 值是图片路径 → 当成贴图 uniform（如星点权重图 star_mask）
		if v is String and ResourceLoader.exists(v):
			mat.set_shader_parameter(String(k), load(v))
		else:
			mat.set_shader_parameter(String(k), v)
	(render_node as CanvasItem).material = mat


func _apply_auto_fit() -> void:
	var target := float(_cfg.get("target_length", 0.0))
	if target <= 0.0:
		return
	if not (render_node is Sprite2D):
		return
	var spr := render_node as Sprite2D
	var tex: Texture2D = spr.texture
	if tex == null:
		return

	# 先查缓存：同一张图 + 同一个目标长度，结果必然相同
	var key := tex.resource_path + "|" + str(target)
	if _auto_fit_cache.has(key):
		var cached: Dictionary = _auto_fit_cache[key]
		_cfg["scale"] = cached["scale"]
		_cfg["offset"] = cached["offset"]
		return

	var img: Image = tex.get_image()
	if img == null:
		return
	var used: Rect2i = img.get_used_rect()
	if used.size.y <= 0:
		return

	var s := target / float(used.size.y)
	# 内容中心相对贴图中心的偏移 → 反向补偿，让「可见内容」的中心落在节点原点
	var tex_center := Vector2(float(tex.get_width()), float(tex.get_height())) * 0.5
	var used_center := Vector2(used.position) + Vector2(used.size) * 0.5
	var scl := Vector2(s, s)
	var off := -(used_center - tex_center) * s
	_cfg["scale"] = scl
	_cfg["offset"] = off
	_auto_fit_cache[key] = {"scale": scl, "offset": off}


func _apply_common_transform() -> void:
	if render_node == null:
		return
	# 检查器的 override 优先级最高（方便在编辑器里所见即所得地调大小）
	var off: Vector2 = offset_override if offset_override != Vector2.ZERO else _cfg.get("offset", Vector2.ZERO)
	var scl: Vector2 = scale_override if scale_override != Vector2.ZERO else _cfg.get("scale", Vector2.ONE)
	var anchor_bottom := bool(_cfg.get("anchor_bottom", false))
	var half := _raw_half_size()

	# 基础摆放：中心对齐原点；开启底部对齐时上移一个半高
	var base := Vector2.ZERO
	if anchor_bottom:
		# ⚠ 必须乘 scl.y：half 是「原始贴图半高」，而 position 是父空间坐标（已缩放后的空间）。
		#   不乘就会出现 scale=0.02 时把角色推到原点上方 1026px 的 bug（历史问题，已修）
		base = Vector2(0.0, -half.y * scl.y)

	if render_node is Node2D:
		var n := render_node as Node2D
		n.scale = scl
		n.position = base + off
		_measure_node2d(n)
	elif render_node is Control:
		var c := render_node as Control
		# ColorRect 用左上角定位，换算成「中心在原点」的摆放
		c.scale = scl
		c.pivot_offset = _placeholder_size * 0.5
		c.position = -_placeholder_size * 0.5 + base + off
		visual_rect = Rect2(base + off - _placeholder_size * 0.5 * scl, _placeholder_size * scl)


## 原始贴图尺寸的一半（不含缩放），无贴图时返回占位尺寸的一半
func _raw_half_size() -> Vector2:
	if render_node is BossRig:
		# 骨骼 rig 报的是「画布一半」，与序列帧图集同口径，两套素材可以直接互换
		return (render_node as BossRig).half_size()
	if render_node is Sprite2D:
		var t: Texture2D = (render_node as Sprite2D).texture
		if t != null:
			return Vector2(float(t.get_width()), float(t.get_height())) * 0.5
	if render_node is AnimatedSprite2D:
		var a := render_node as AnimatedSprite2D
		var fr := _current_frame_texture(a)
		if fr != null:
			return Vector2(float(fr.get_width()), float(fr.get_height())) * 0.5
	return _placeholder_size * 0.5


## 当前画面正在显示的那一帧贴图 —— 供残影快照用（闪避拖影）
## AnimatedSprite2D → 当前动画的当前帧；Sprite2D → 整张贴图；BossRig → 招式帧或躯干；
## 占位色块 → null
func current_texture() -> Texture2D:
	if render_node is BossRig:
		return (render_node as BossRig).current_texture()
	if render_node is AnimatedSprite2D:
		return _current_frame_texture(render_node as AnimatedSprite2D)
	if render_node is Sprite2D:
		return (render_node as Sprite2D).texture
	return null


## 读取 AnimatedSprite2D 当前帧贴图（动画/帧索引越界时返回 null）
func _current_frame_texture(a: AnimatedSprite2D) -> Texture2D:
	var f := a.sprite_frames
	if f == null:
		return null
	var anim_name := a.animation
	if not f.has_animation(anim_name):
		var names := f.get_animation_names()
		if names.is_empty():
			return null
		anim_name = String(names[0])
	var count := f.get_frame_count(anim_name)
	if count <= 0:
		return null
	var idx := clampi(a.frame, 0, count - 1)
	return f.get_frame_texture(anim_name, idx)


## 记录 Node2D 形象的实际占位矩形（含缩放），供外部定位血条等
func _measure_node2d(n: Node2D) -> void:
	var half := _raw_half_size() * n.scale.abs()
	visual_rect = Rect2(n.position - half, half * 2.0)


## 当前形象上半部分的高度（供血条 / 受击点等外部定位使用）
## 取的是「以本节点原点为基准」的上边界，已包含锚点与偏移
func top_extent() -> float:
	# 贴图与占位体都直接读 visual_rect（_apply_layout 已按 anchor_bottom / scale / offset 摆好）
	# ⚠ 旧实现给占位体写死「-半高」，只对「中心在原点」成立；条目一旦写 anchor_bottom=true
	#   上边界就变成 -整高，血条 / 名字会被压进身体里（2026-11-08 肉鸽小怪截图发现）
	if visual_rect.size.y > 0.0:
		return visual_rect.position.y
	return -_placeholder_size.y * 0.5


## 视觉中心（相对「角色根节点」原点）—— 供攻击特效、伤害飘字等定位到**身体**而不是脚底
## 计算：本节点 position + 父节点（如 Visual）的 position + visual_rect 中心
## 角色贴图越高，返回值越靠上；未接入贴图时按占位尺寸估算（中心约在原点）
func body_center() -> Vector2:
	var c: Vector2 = position + visual_rect.get_center()
	var p := get_parent()
	if p is Node2D:
		c += (p as Node2D).position
	return c


## 当前形象左右半宽（供血条宽度对齐使用）
func half_width() -> float:
	if using_texture:
		return visual_rect.size.x * 0.5
	return _placeholder_size.x * 0.5


## 出招原点（世界坐标）：嘴 / 爪尖 / 刀尖，按**动作名**查骨骼的锚点表。
## 没接骨骼（序列帧 / 占位色块）、或该动作没登记锚点时返回 null —— 调用方据此回落，
## 不要在这里编一个「身体中心」的替代值：那会让「锚点没配好」永远看不出来。
func muzzle_position(anim: String) -> Variant:
	if render_node is BossRig:
		return (render_node as BossRig).muzzle_position(anim)
	return null


## 取当前渲染节点的「逻辑中心偏移」，供血条 / 受击点等外部定位使用
## 未接入贴图时返回占位尺寸的一半相关值
func logic_half_size() -> Vector2:
	if using_texture:
		return visual_rect.size * 0.5
	return _placeholder_size * 0.5


## 当前占位尺寸（外部需要知道「这个实体多大」时用）
func placeholder_size() -> Vector2:
	return _placeholder_size
