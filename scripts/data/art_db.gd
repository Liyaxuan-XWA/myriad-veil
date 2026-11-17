@tool
extends Node
## 美术资源登记表（autoload: ArtDB）—— 集中式「皮肤表」
##
## 目的：让「替换美术素材」变成「只改这张表 + 往 assets/ 丢图」，不碰任何玩法代码。
##
## 工作方式：
##   1. 每个可视实体在 VISUALS 里登记一条：id → 贴图路径 / 帧数 / 缩放 / 锚点 / 朝向
##      每个特效在 EFFECTS 里登记一条：id → 序列帧 / 补间参数 / 回退绘制
##   2. 视觉节点（scripts/visual/skin_visual.gd）与特效播放器
##      （scripts/visual/fx_player.gd）启动时用 id 向本表取配置
##   3. 有贴图 → 自动切成 AnimatedSprite2D（多帧）或 Sprite2D（单帧）
##      没贴图 → 回退到程序化占位（实体=色块，特效=程序绘制），保证开发期始终可运行
##
## 替换流程（美术就位后）：
##   - 把图丢进 assets/characters/player/、assets/effects/ 等目录
##   - 在下面 VISUALS / EFFECTS 对应条目里填 texture / frames / frame_size
##   - 保存即生效，无需改场景、无需改代码
##
## ⚠ 本表只登记「表现层」，绝不登记任何数值（血量/攻击/碰撞等仍在各自数据表）。

## 视觉条目字段说明
##   texture        SpriteFrames 资源路径（.tres，用于多帧动画）或图片路径（用于单帧）
##   frames         多帧时的帧数；1 表示单帧贴图
##   frame_size     多帧图集里单帧的像素尺寸 Vector2；单帧留 Vector2.ZERO
##   fps            多帧播放速度
##   scale          贴图相对「逻辑尺寸」的缩放（逻辑尺寸仍是碰撞体尺寸，不受影响）
##   offset         贴图中心相对实体原点的偏移（像素）
##   flip_driven    是否由代码的 scale.x 翻转驱动朝向（玩家/BOSS 都是 true）
##   anchor_bottom  贴图底部是否对齐实体原点（俯视角人物常用，脚踩地面）
##   placeholder_color  未接入贴图时的占位色
##   placeholder_size   未接入贴图时的占位尺寸（也应等于逻辑尺寸）
const VISUALS: Dictionary = {
	# ============ 玩家：李青云 ============
	"player_liqingyun": {
		## ★ 正式素材（2026-10-19 接入）
		##   移动 = walk_side 侧向 6 帧（左右共用，代码 scale.x 镜像；上下移动也用它）
		##   静止 = daiji 正面站立 7 帧（循环呼吸，2026-10-19 用户导入的站立序列帧）
		##   攻击 = attack 41 帧（2026-10-19 接入：整段用 speed_scale 压进普攻后摇）
		##   换行走图：覆盖 assets/characters/player/spritesheet_1.png（3x2 网格 1536x1024，朝右跑）
		##   换站立图：覆盖 assets/characters/player/liqingyun_idle.png（7 帧横向 1260x270，已统一口径）
		##   换攻击图：覆盖 assets/characters/player/liqingyun_attack.png（41 帧横向 7380x270，已统一口径）
		##   切窗在 liqingyun_walk.tres 的 AtlasTexture region 里（180x270/帧）
		##   动画名约定：walk_side / walk_down / walk_up / walk / run / idle / daiji / attack
		"sprite_frames": "res://assets/characters/player/liqingyun_walk.tres",
		## texture 兜底已弃用（原图集已移除）；素材只走上面的 sprite_frames
		"texture": "",
		"frames": 6,
		"frame_size": Vector2.ZERO,
		"fps": 10.0,
		## 静止时停在第几帧（0~5；不满意可直接改）
		"idle_frame": 2,
		## 0.25 → 显示高约 67.5px（切窗高 270 × 0.25），与原朝下图 ~68px 大小衔接；
		## 想改角色大小只动这里；帧底 = 阴影贴地，anchor_bottom 自动脚踩地面
		"scale": Vector2(0.25, 0.25),
		## 脚底自动对齐（anchor_bottom 的 scale 补偿 bug 已于 2026-10-18 修复）
		"offset": Vector2.ZERO,
		"flip_driven": true,
		"anchor_bottom": true,
		"placeholder_color": Color(0.3, 0.7, 1.0, 1.0),
		"placeholder_size": Vector2(32.0, 32.0),
	},

	# ============ 御剑：常驻悬浮武器（跟随角色漂浮，攻击时绕角色扫弧）============
	## 换图方式：武器图丢进 assets/effects/，在 texture 填路径（或 sprite_frames 填 .tres）
	## **未填贴图时武器完全不显示**，不影响任何现有表现
	## 参数分三组：显示大小 / 悬浮姿态 / 攻击扫弧，下面逐项有注释
	"player_weapon": {
		"texture": "res://assets/effects/player_sword.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		## ★ 自动尺寸：只填「想让武器显示多长」（像素），scale 与 offset 由代码按图片实际内容算
		##   换任何武器图，改这一个数字即可
		"target_length": 68.0,
		## 普攻刀光拖尾的颜色（细弧带）；不填用 WEAPON_TRAIL 的默认钢蓝
		"trail_color": Color(0.74, 0.85, 0.98, 1.0),
		## 下面两个会被 target_length 覆盖，留着是为了调试时能手动接管（把 target_length 设回 0）
		"scale": Vector2(0.06, 0.06),
		"offset": Vector2.ZERO,
		## 武器图自身朝向：这把剑原图**刃尖朝下**，转到「朝外」需要 -90°
		"sprite_rotation_deg": -90.0,
		## ---- 悬浮姿态 ----
		## 离角色中心多远（像素）。**填 -1 表示自动** = target_length/2 + 6
		"orbit_radius": -1.0,
		## 圆心高度（相对角色原点，负值往上）。⚠ 武器最终高度 = 本值 + sin(待机角度)×半径，
		## 所以待机角度 -60° 时又会额外抬高约 28px。想让武器停在身体中部就填 -8 左右
		"orbit_height": -34.0,
		## 待机角度（相对朝向）：180° = 正后方（角色背后的位置）
		"idle_base_deg": 180.0,
		## 待机摆动幅度（度）与速度（越大越快）
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		## 上下浮动幅度（像素）与剑身微倾幅度（度）—— 让悬浮「活」起来，不是死板地摆
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		## ★ 待机时「背后」只按左右判定：角色朝右→剑在左，朝左→剑在右。
		##   上下行走时不会跑到身前挡脸（2D 俯视角里「背后」只有左右成立）
		"idle_horizontal_only": true,
		## 转身速度（度/秒）：越小剑飘得越慢。520 ≈ 0.35 秒从一侧转到另一侧
		"turn_speed_deg": 520.0,
		## ★ 待机时的固定旋转角（度）：180 = 刃尖朝上竖立。
		##   填 -999 表示不固定，改为「刃尖朝外」（径向）。攻击时始终按径向摆正
		"idle_rotation_deg": 180.0,
		## ---- 攻击扫弧 ----
		## 从哪个角度扫到哪个角度（相对朝向）。范围越大挥砍越夸张
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		## 蓄力：出击前先往后撤到这个角度（相对朝向），做出「收势再发力」
		"windup_deg": -115.0,
		## 蓄力时长（秒），越短越凌厉
		"windup_time": 0.09,
		## 扫过去用多久（秒），越小越快
		"sweep_time": 0.16,
		## 剑身自转圈数。**注意它贯穿「出击 + 回旋」全程**（不是只在扫击那 0.16s 里），
		## 所以 1.0 圈约 0.46 秒转完 ≈ 780°/秒；觉得快就调到 0.6，觉得慢就加到 1.5
		"spin_turns": 0.25,
		## 收回待机位用多久
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.85, 0.85, 0.95, 1.0),
		"placeholder_size": Vector2(6.0, 40.0),
	},

	# ============ 御剑：弯刀（装备弯刀时的战斗形象，悬浮/攻击参数与默认剑一致）============
	## 换图方式：图放 assets/effects/weapons/，在 texture 填路径
	## 尺寸交给 target_length 自动算（读图片非透明区域），换图只改这一个数字
	"weapon_curved_blade": {
		"texture": "res://assets/effects/weapons/curved_blade.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		## 弯刀内容 190×1150，比铁剑(143×1139)**宽 30%** —— 同高度下视觉重量明显更重。
		## 按面积等效算应为 59，这里给 56（略保守），看起来才和铁剑「一样大」
		"target_length": 56.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		## 原图刃尖朝下 → 转 -90° 让刃尖朝外
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.85, 0.85, 0.95, 1.0),
		"placeholder_size": Vector2(6.0, 40.0),
	},

	# ============ 锻造台（UI 形象）============
	## 锻造锤：锻造台右侧的锤子（点击拿起 → 移到装备上点击锻造）。
	## 换图方式：把锤子的图丢进 assets/，在这里填 texture（想让它有挥动动画就填多帧序列帧）。
	## 未接贴图时是灰色方块占位，尺寸见 placeholder_size。
	"forge_hammer": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.55, 0.57, 0.63, 1.0),
		"placeholder_size": Vector2(72.0, 72.0),
	},

	# ============ 刀客 BOSS（凡界守关者）============
	"boss_daoke": {
		## ★ 正式素材（2026-10-25 试点接入，管线见 tools/gen_boss_sprite_frames.py）
		##   素材 = 品红底 AI 姿势表 → 抠图 → 按连通块切帧 → 拼合归一 → 手写 SpriteFrames
		##   九套动画：idle / walk_side + 七式招式原型
		##     slash_h 横斩 · smash_v 竖劈下砸 · dash_slash 突进斩 · stomp_aoe 踏地圆域
		##     palm_project 推掌投射 · guard_charge 格挡蓄力 · ult_windup 大招起手
		##   玩法里没接到的动作名会自动回落 idle；每套的高度倍率与朝向镜像记在
		##     vibe_images/boss_work/boss_daoke/manifest.json（compose 会读它，别只靠命令行传）
		##   ⚠ 朝向：七套招式都是标准侧视、朝右（基准）。**idle 那张姿势表是正面站姿、眼神偏左**，
		##     不镜像的话站着时像在看反方向，所以 manifest 里给 idle 开了 flip_x。
		##     walk_side 原生就是朝右，**不要再加 flip_x**（早前误判过一次，镜像完反而倒着走）。
		##     判朝向别靠感觉：放大到头部看鼻尖朝哪，或跟 slash_h 的接触帧并排比。
		##   招式 → 动作名的对应表在 ArtDB.BOSS_MOVE_ANIMS（不在玩法代码里）
		##   换素材：覆盖同名 assets/characters/boss/boss_daoke_<anim>.png（帧宽 900 / 帧高 720）再重跑 compose
		##     帧高 720 是被 smash_v 举刀过头那一帧顶出来的：画布矮了刀尖会被上沿切平
		"sprite_frames": "res://assets/characters/boss/boss_daoke.tres",
		## ★ 骨骼（2026-10-26 接入）：idle / walk + 七式全部由 `BossRigHuman` 驱动，
		##   下面的 SpriteFrames 降级成**兜底**（骨骼缺某个动作时才回落到帧）。
		##   分件与关节数据由 tools/build_daoke_rig.py 从**侧身定妆图**（现行：垂刀式）拆出。
		##   换美术重跑那个脚本即可，本文件不用改；⚠ 但 **boss_rig_human.gd 多半要重算**：
		##   姿势一换，刀尖的静止指向就变（扛刀 −37.5° → 垂刀 +70.0°，肩肘正负号整个反过来），
		##   六招角度是按这个基准反解的。流程见 docs/美术资源接入记录.md §20.5 那 7 步。
		"rig": "res://assets/characters/boss/daoke_rig/rig.tres",
		"texture": "",
		"frames": 4,
		"frame_size": Vector2.ZERO,
		"fps": 5.0,
		## 0.25 与玩家同一口径：玩家切窗高 270×0.25=67.5px，BOSS 内容高 590×0.25≈147.5px
		##   → 约 2.2 倍玩家身高，压迫感靠这个 scale 体现，不要挪到 Visual.scale（那是玩法代码的朝向/蓄力脉动用）
		"scale": Vector2(0.25, 0.25),
		## 切帧画布脚底留了 20px 空白，anchor_bottom 会把画布底边贴地面，故下移 20×0.25=5px 让脚真正踩地
		"offset": Vector2(0.0, 5.0),
		"flip_driven": true,
		"anchor_bottom": true,
		"placeholder_color": Color(0.60, 0.20, 0.22, 1.0),
		"placeholder_size": Vector2(64.0, 92.0),
	},

	# ============ 演武场木桩（训练模式，不灭）============
	"training_dummy": {
		"texture": "res://assets/characters/training_dummy.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": true,
		"target_length": 150.0,
		"placeholder_color": Color(0.55, 0.36, 0.20, 1.0),
		"placeholder_size": Vector2(60.0, 140.0),
	},

	# ============ 刀痕（地面持续状态，双方共用）============
	# 普通刀痕：留存 10 秒，只占位限制走位；被激活时当场化为斩击（见 EFFECTS.scar_slash）
	"blade_scar": {
		## 2026-10-25：接入程序化灼痕贴图（斜向裂口 + 余烬），不再是 104×104 色块。
		"texture": "res://assets/effects/skills/blade_scar.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		# 显示长度 = 判定直径，保证「看到的范围 = 炸到的范围」
		"target_length": 104.0,
		"placeholder_color": Color(0.85, 0.30, 0.24, 0.55),
		"placeholder_size": Vector2(104.0, 104.0),
	},

	# ============ 虎妖（凡界第 1 位，演武场那只）============
	## 换图：填 texture 即替换虎妖形象（演武场与万界秘境共用这一个场景）
	"boss_huyao": {
		## ★ 正式素材（2026-10-26 接入）：**兽型**四足巨虎「山君」
		##   形象锚点与每套动作的提示词在 tools/boss_art_prompts.py（改长相只改那里的 ANCHOR）
		##   七套动画：idle / walk_side + 五式
		##     slash_single 虎爪横扫 · smash 碎岩下砸 · arrow 掷石
		##     element_orb 吐妖丹 · arrow_volley 砂石乱舞
		##   ⚠ 画布 1000×760（比刀客的 900×720 宽）：兽型横向长，900 宽会把腿脚质心挤到边界外、
		##     触发 compose 的钳格保护，走路时身体左右跳。
		##   ⚠ 归一化高度 560（刀客是 590）：同样是宽度问题，560 时最宽帧 940px 刚好落进 1000。
		##   ⚠ 兽型的「原点」用 anchor_bottom=true 踩地面 —— 与刀客同一口径；
		##     不要改回 false，否则脚会浮在碰撞圆中心。
		##
		## ★ 移动动画走骨骼（2026-10-26）：序列帧的「每格独立重画」让走路抽搐
		##   （8 帧上半身 IoU 只有 0.93~0.96，加密帧数只会让抽搐更频繁）。
		##   rig.tres 把定妆图拆成 8 块刚体件，躯干始终是同一张贴图 → 结构上不可能抽搐。
		##   · idle / walk  → 骨骼（BossRig.play_loop）
		##   · 五式招式     → 下面的 sprite_frames 作为覆盖层（出招时隐藏骨骼）
		##   分件图与关节数据由 tools/build_tiger_rig.py 生成，换美术重跑它即可。
		"rig": "res://assets/characters/boss/tiger_rig/rig.tres",
		"sprite_frames": "res://assets/characters/boss/boss_huyao.tres",
		"texture": "",
		"frames": 4,
		"frame_size": Vector2.ZERO,
		"fps": 6.0,
		"scale": Vector2(0.25, 0.25),
		## 切帧画布脚底留了 20px 空白，anchor_bottom 会把画布底边贴地面，故下移 20×0.25=5px
		"offset": Vector2(0.0, 5.0),
		"flip_driven": true,
		"anchor_bottom": true,
		"placeholder_color": Color(0.85, 0.35, 0.35, 1.0),
		"placeholder_size": Vector2(88.0, 48.0),
	},

	# ============ BOSS 投射物 ============
	# 物理投掷（土黄）与元素法球（蓝）分列两条，各自替换素材时互不影响
	"boss_projectile": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.9, 0.8, 0.4, 1.0),
		"placeholder_size": Vector2(18.0, 18.0),
	},
	"boss_projectile_elemental": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.4, 0.6, 1.0, 1.0),
		"placeholder_size": Vector2(18.0, 18.0),
	},

	# ============ 掉落物 ============
	"item_pickup": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 6.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.85, 0.82, 0.6, 1.0),
		"placeholder_size": Vector2(20.0, 20.0),
	},

	# ============ 玩家功法投射物（箭矢 / 法球）============
	"player_projectile": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.75, 0.9, 1.0, 1.0),
		"placeholder_size": Vector2(18.0, 8.0),
	},

	# ============ 玩家技能投射物正式形象（2026-10-25）============
	## 由 SkillDB/ArtDB.SKILL_FX 的 projectile_visual 指向这里；
	## 换图只需要覆盖 assets/effects/skills/ 下对应 PNG，代码无需改。
	"skill_blade_qi": {
		"texture": "res://assets/effects/skills/blade_qi.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 72.0,
		"placeholder_color": Color(1.0, 0.6, 0.2, 1.0),
		"placeholder_size": Vector2(48.0, 48.0),
	},
	"skill_sword_light": {
		"texture": "res://assets/effects/skills/sword_light.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 96.0,
		"placeholder_color": Color(0.6, 0.95, 1.0, 1.0),
		"placeholder_size": Vector2(10.0, 54.0),
	},
	"skill_tiger_rock": {
		"texture": "res://assets/effects/skills/tiger_rock.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 30.0,
		"placeholder_color": Color(0.55, 0.38, 0.2, 1.0),
		"placeholder_size": Vector2(26.0, 26.0),
	},
	"skill_tiger_orb": {
		"texture": "res://assets/effects/skills/tiger_orb.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 46.0,
		"placeholder_color": Color(0.85, 0.25, 0.1, 1.0),
		"placeholder_size": Vector2(22.0, 22.0),
	},
	## 青岚古猿的投射物（2026-10-28）：青灰苔石 / 碧玉灵球，
	## 由 tools/gen_lianqi_fx.py 生成，与虎妖的土黄投石、赤红妖丹区分开。
	"ape_boulder": {
		"texture": "res://assets/effects/skills/ape_boulder.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 28.0,
		"placeholder_color": Color(0.42, 0.50, 0.36, 1.0),
		"placeholder_size": Vector2(26.0, 26.0),
	},
	## 两仪·阴阳双鱼（2026-10-29）：此前走 boss_projectile 的 18px 占位方块，
	## 局内像两块色板；换成一对朝右的鱼形符箓，阳金 / 阴青。
	"liangyi_fish_yang": {
		"texture": "res://assets/effects/skills/liangyi_fish_yang.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 56.0,
		"placeholder_color": Color(0.96, 0.80, 0.35, 1.0),
		"placeholder_size": Vector2(46.0, 22.0),
	},
	"liangyi_fish_yin": {
		"texture": "res://assets/effects/skills/liangyi_fish_yin.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 56.0,
		"placeholder_color": Color(0.35, 0.78, 0.86, 1.0),
		"placeholder_size": Vector2(46.0, 22.0),
	},
	"ape_orb": {
		"texture": "res://assets/effects/skills/ape_orb.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": false, "anchor_bottom": false,
		"target_length": 48.0,
		"placeholder_color": Color(0.24, 0.72, 0.32, 1.0),
		"placeholder_size": Vector2(22.0, 22.0),
	},

	# ============ 原初位面主角（主城无战斗，独立一条便于单独换装）============
	"player_primordial": {
		## 主城主角：与战斗主角共用同一套侧向行走帧（liqingyun_walk.tres，见 player_liqingyun）
		"sprite_frames": "res://assets/characters/player/liqingyun_walk.tres",
		"texture": "",
		"frames": 6,
		"frame_size": Vector2.ZERO,
		"fps": 10.0,
		"idle_frame": 2,
		"scale": Vector2(0.25, 0.25),
		## 同 player_liqingyun：脚底对齐交给 anchor_bottom，offset 保持 0
		"offset": Vector2.ZERO,
		"flip_driven": true,
		"anchor_bottom": true,
		"placeholder_color": Color(0.3, 0.7, 1.0, 1.0),
		"placeholder_size": Vector2(32.0, 32.0),
	},

	# ============ 设施通用占位（各设施由 facility_id 覆盖配色）============
	"facility_generic": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.25, 0.35, 0.5, 1.0),
		"placeholder_size": Vector2(48.0, 48.0),
	},

	# ============ 主城四周能量屏障（2026-10-22 接入）============
	## 用 Line2D 沿矩形画一圈闭合环（不经 SkinVisual），两条线 = 外层辉光 + 内层能量流
	## 外观由程序化 shader `barrier_flow.gdshader` 生成：能量沿墙流动 + 灵力一呼一吸 + 纵向柔边
	## 换美术：① 换 shader 就改 shader 路径 ② 换配色/速度/宽度只改下面这些数
	## 想用贴图代替程序化外观：填 texture（会沿环平铺）并把 shader 留空
	"realm_barrier": {
		"texture": "",
		"shader": "res://assets/shaders/barrier_flow.gdshader",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		# 内层：细、亮、流动感强（读作「能量本身」）
		"barrier_width": 13.0,
		"core_color": Color(0.80, 1.0, 0.98, 1.0),
		"core_alpha": 0.95,
		"core_edge_softness": 1.15,
		# 外层：宽、淡、柔（读作「灵光外溢」）
		"glow_width": 86.0,
		"glow_color": Color(0.26, 0.80, 0.90, 1.0),
		"glow_alpha": 0.30,
		"glow_edge_softness": 2.6,
		# 流动与呼吸（两条线用同一套，视觉上才是一个整体）
		"flow_speed": 24.0,
		"turbulence": 0.030,
		"flow_contrast": 1.45,
		"pulse_speed": 1.0,
		"pulse_amount": 0.32,
		"placeholder_color": Color(0.55, 0.90, 1.0, 0.85),
		"placeholder_size": Vector2(32.0, 8.0),
	},

	# ============ 设施图标（2026-10-22 接入正式美术）============
	## 换图：覆盖 assets/scenes/facilities/<id>.png 即可（同 id 同名，本表不用改）
	## 尺寸走 target_length = 想让设施在场景里显示多高（像素）；宽度按图片比例自动算。
	## ⚠ 图标是 2048×2048 的方形画布，但**非透明内容**只占中间一块，
	##   target_length 读的是非透明区域高度（见 skin_visual._apply_auto_fit），所以显示大小稳定。
	"facility_arena": {
		"texture": "res://assets/scenes/facilities/arena.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 136.0,
		"placeholder_color": Color(0.55, 0.3, 0.25, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_tower": {
		"texture": "res://assets/scenes/facilities/tower.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 166.0,
		"placeholder_color": Color(0.45, 0.35, 0.6, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_domain_gate": {
		"texture": "res://assets/scenes/facilities/gateway.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 150.0,
		"placeholder_color": Color(0.3, 0.45, 0.65, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	# 万界棋坛（卡片自走棋入口）：宽矮型石台，target_length 走同类宽矮件（药圃 130 / 演武场 136）
	# 换图口 tools/prep_match_facility.py（洋红键色收片 → 2048² 画布、内容高占比 0.74）
	"facility_match": {
		"texture": "res://assets/scenes/facilities/match.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 136.0,
		"placeholder_color": Color(0.24, 0.42, 0.5, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_alchemy": {
		"texture": "res://assets/scenes/facilities/alchemy.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 136.0,
		"placeholder_color": Color(0.35, 0.5, 0.35, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_herb_garden": {
		"texture": "res://assets/scenes/facilities/herb_garden.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 130.0,
		"placeholder_color": Color(0.3, 0.5, 0.3, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_talisman": {
		"texture": "res://assets/scenes/facilities/talisman.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 136.0,
		"placeholder_color": Color(0.55, 0.45, 0.25, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_memory": {
		"texture": "res://assets/scenes/facilities/memory.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 146.0,
		"placeholder_color": Color(0.4, 0.4, 0.55, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_equipment": {
		"texture": "res://assets/scenes/facilities/forge.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 140.0,
		"placeholder_color": Color(0.5, 0.4, 0.3, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},
	"facility_warehouse": {
		"texture": "res://assets/scenes/facilities/warehouse.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 136.0,
		"placeholder_color": Color(0.4, 0.4, 0.45, 1.0),
		"placeholder_size": Vector2(120.0, 80.0),
	},

	# ============ 场景地面背景（2026-10-22 接入正式美术）============
	## 用 SkinVisual 铺在场景原点（z_index=-10），target_length = 可见区域的**高度**。
	## ⚠ 背景图是 16:9（2730×1536），按高度适配后宽度会超出可见区 ——
	##   这是有意的：**保证横向铺满**，超出的部分在镜头外，不会露底。
	"bg_primordial_realm": {
		"texture": "res://assets/scenes/primordial_realm_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1400.0,
		# 星点流动（2026-10-22 用户定）：**不改素材**，只改这张贴图的采样 ——
		# 图里本来就有的小亮星按 7,-3 像素/秒漂移，地形与灵脉原地不动。
		# 速度/亮度门槛都在这里调；strength = 0 可整体关掉。
		"shader": "res://assets/shaders/star_flow.gdshader",
		"shader_params": {
			"flow_px": Vector2(9.0, -4.0),
			"star_gain": 1.18,
			"strength": 1.0,
			# 星点权重图（由 tools/gen_star_mask.py 从原图派生；换图后重跑该脚本）
			"star_mask": "res://assets/scenes/primordial_star_mask.png",
		},
		"placeholder_color": Color(0.12, 0.14, 0.18, 1.0),
		"placeholder_size": Vector2(1800.0, 1400.0),
	},
	# ===== 试炼之路专属战场（2026-11-08）=====
	## ⚠ 试炼不再沿用「原初位面星海」，也不跟着本层抽到的 BOSS 换战场：
	##   整局固定同一座「无尽试炼台」——暗玄石砖 + 淡金刻纹，中心一枚阵眼。
	##   换皮只改这张表：texture（平铺地面）/ decal（阵眼，只画一次）/ grade（灯光）。
	##   三张都缺图时走 placeholder_color/size 回退，游戏照常能跑。
	"bg_rogue_trial": {
		"texture": "res://assets/scenes/rogue_trial_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		# 原图偏暗，整体略微提亮并偏冷；⚠ 明暗只调 tint / grade，不改原图
		"tint": Color(1.02, 1.04, 1.10, 1.0),
		# 中心阵眼：只画一次，不进平铺贴图（否则会跟着 map_tiles 重复 36 次）
		"decal": "res://assets/scenes/rogue_trial_seal.png",
		"decal_size": 660.0,
		"decal_tint": Color(0.95, 0.97, 1.02),
		"decal_opacity": 0.92,
		"placeholder_color": Color(0.08, 0.10, 0.14, 1.0),
		"placeholder_size": Vector2(1600.0, 1200.0),
		# 试炼=肃杀冷调：低饱和、强暗角、暗部偏蓝、高光留一点旧金
		"grade": {
			"exposure": 0.98,
			"contrast": 1.12,
			"saturation": 0.82,
			"lift": -0.008,
			"gamma": 1.02,
			"shadow_tint": Color(0.80, 0.90, 1.08, 1.0),
			"highlight_tint": Color(1.06, 1.02, 0.94, 1.0),
			"vignette": 0.52,
			"vignette_color": Color(0.015, 0.025, 0.045, 1.0),
			"light_dir": Vector2(0.0, -1.0),
			"light_strength": 0.18,
		},
	},
	"bg_huyao_arena": {
		"texture": "res://assets/scenes/huyao_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		# 地面平铺（2026-10-22 第二轮）：单张 TextureRect + texture_repeat 自动铺满，
		# map_tiles = 战场横向由几个 tile_width 宽的格子组成；6 → 3600×2028（旧 3×3 的两倍）
		"map_tiles": 6,
		"tile_width": 600.0,
		"placeholder_color": Color(0.15, 0.17, 0.2, 1.0),
		"placeholder_size": Vector2(1600.0, 1200.0),
		# 战场氛围（2026-10-27）：不改地面纹理，只叠动态层。
		# 整体灯光调色（2026-10-27）：不改地面纹理，只对整幅画面做分级（人物/特效一起调）。
		# 虎妖=夜林：月光冷调、整体压暗、暗部偏蓝、四周深蓝暗角。
		"grade": {
			"exposure": 0.92,
			"contrast": 1.08,
			"saturation": 0.80,
			"lift": -0.005,
			"gamma": 1.03,
			"shadow_tint": Color(0.80, 0.92, 1.12, 1.0),
			"highlight_tint": Color(0.96, 1.00, 1.10, 1.0),
			"vignette": 0.45,
			"vignette_color": Color(0.02, 0.035, 0.06, 1.0),
			"light_dir": Vector2(-0.35, -1.0),
			"light_strength": 0.20,
		},
	},
	"bg_daoke_arena": {
		"texture": "res://assets/scenes/daoke_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		# 地面平铺（2026-10-22 第二轮）：单张 TextureRect + texture_repeat 自动铺满，
		# map_tiles = 战场横向由几个 tile_width 宽的格子组成；6 → 3600×2028（旧 3×3 的两倍）
		"map_tiles": 6,
		"tile_width": 600.0,
		"placeholder_color": Color(0.15, 0.17, 0.2, 1.0),
		"placeholder_size": Vector2(1600.0, 1200.0),
		# 刀客=石灯废墟：暖灯调、提高对比、暗部偏红褐、暖色暗角。
		"grade": {
			"exposure": 1.02,
			"contrast": 1.10,
			"saturation": 1.02,
			"lift": 0.005,
			"gamma": 0.98,
			"shadow_tint": Color(1.08, 0.94, 0.86, 1.0),
			"highlight_tint": Color(1.08, 1.00, 0.90, 1.0),
			"vignette": 0.40,
			"vignette_color": Color(0.07, 0.04, 0.025, 1.0),
			"light_dir": Vector2(0.4, -1.0),
			"light_strength": 0.20,
		},
	},
	"bg_jianke_arena": {
		"texture": "res://assets/scenes/jianke_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		# 冰砖原图偏亮（近白），压到 0.68 并略带冷色，角色/特效才看得清
		"tint": Color(0.76, 0.80, 0.86, 1.0),
		# 地面平铺（2026-10-22 第二轮）：单张 TextureRect + texture_repeat 自动铺满，
		# map_tiles = 战场横向由几个 tile_width 宽的格子组成；6 → 3600×2028（旧 3×3 的两倍）
		"map_tiles": 6,
		"tile_width": 600.0,
		"placeholder_color": Color(0.15, 0.17, 0.2, 1.0),
		"placeholder_size": Vector2(1600.0, 1200.0),
		# 剑客=云海：冷白雾感，但整体压暗一档（2026-10-27 用户反馈太亮）
		"grade": {
			"exposure": 0.88,
			"contrast": 1.06,
			"saturation": 0.86,
			"lift": -0.008,
			"gamma": 1.04,
			"shadow_tint": Color(0.86, 0.94, 1.10, 1.0),
			"highlight_tint": Color(0.94, 0.99, 1.07, 1.0),
			"vignette": 0.40,
			"vignette_color": Color(0.40, 0.50, 0.64, 1.0),
			"light_dir": Vector2(-0.2, -1.0),
			"light_strength": 0.16,
		},
	},
	"boss_dingzhen": {
		## 与两仪同一口径：只给 rig，不给 texture / frame_size
		"rig": "res://assets/characters/boss/dingzhen_rig/rig.tres",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
	},
	"boss_qijun": {
		## 2D 骨骼（2026-10-28）：AI A-pose 切 body / arm_l / arm_r + 程序化气环
		"rig": "res://assets/characters/boss/qijun_rig/rig.tres",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.60, 0.86, 1.0, 1.0),
		"placeholder_size": Vector2(68.0, 100.0),
	},
	"boss_heiliao": {
		## 2D 骨骼（2026-10-29）：T-pose 拆 body / arm_pen / arm_free / drum + 程序化雷环。
		## 肩甲留在 body 上盖住肩关节；铁笔随右臂整块切，避免“武器粘衣服 / 手挥笔不动”。
		"rig": "res://assets/characters/boss/heiliao_rig/rig.tres",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.72, 0.52, 1.0, 1.0),
		"placeholder_size": Vector2(78.0, 108.0),
	},
	"boss_lizhao": {
		## 2D 骨骼（2026-10-29）：一臂持日轮扇的祭袍火正。
		## 分件 body / fan；只拆扇面+扇柄+持扇手，绕手腕旋转，宽袖留在身上不扯袍。
		"rig": "res://assets/characters/boss/lizhao_rig/rig.tres",
		"texture": "res://assets/characters/boss/boss_lizhao.png",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(1.0, 0.56, 0.24, 1.0),
		"placeholder_size": Vector2(78.0, 112.0),
	},
	"boss_yanwujiu": {
		## 2D 骨骼（2026-10-29）：灰白丧服、三目面具、无兵器的赤霄劫主。
		## 分件 body / arm_cast；背后三段劫环由 BossRigSanzai 程序化旋转。
		"rig": "res://assets/characters/boss/wujiu_rig/rig.tres",
		"texture": "res://assets/characters/boss/boss_wujiu.png",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.72, 0.68, 0.80, 1.0),
		"placeholder_size": Vector2(82.0, 118.0),
	},
	"boss_guanying": {
		## 2D 骨骼（2026-11-01）：观澜 · 镜主。披银灰镜纹长袍，右臂持一面
		## 可拆的圆镜；分件 body / arm_mirror / mirror。镜面本身单独一块，
		## 便于「换镜 / 碎镜 / 镜返」时绕手腕翻转而不撕扯袍袖。
		"rig": "res://assets/characters/boss/guanying_rig/rig.tres",
		"texture": "res://assets/characters/boss/boss_guanying.png",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.62, 0.84, 1.0, 1.0),
		"placeholder_size": Vector2(84.0, 122.0),
	},
	"boss_zhizhu": {
		## 2D 骨骼（2026-11-02）：执烛 · 影主。青黑广袖 + 一块垂到地的墨色披影，
		## 右手提一盏空铜界灯；分件 body / lantern —— 捻灯 / 挑灯 / 夺灯只转灯，不扯袖。
		## 它不挥兵刃：招式全交给地上那条影子，身体只演「压多低、灯举多高」。
		"rig": "res://assets/characters/boss/zhizhu_rig/rig.tres",
		"texture": "res://assets/characters/boss/boss_zhizhu.png",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.34, 0.36, 0.52, 1.0),
		"placeholder_size": Vector2(84.0, 126.0),
	},
	"boss_diezhi": {
		## 2D 骨骼（2026-11-02）：叠纸 · 折径。月白广袖纸袍，袍面无纹只有**硬折棱线**，
		## 脸是一张对折的纸，手里一把青铜镇尺（压纸用的文房器）。
		## 分件 body / rule —— 折 / 押 / 撕 全部由镇尺压出去，袍身只做硬折的角位移，
		## 不做布褶摆动：它是纸，动作用是「翻面」而不是「飘」。
		"rig": "res://assets/characters/boss/diezhi_rig/rig.tres",
		"texture": "res://assets/characters/boss/boss_diezhi.png",
		"frame_size": Vector2.ZERO,
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"placeholder_color": Color(0.86, 0.87, 0.82, 1.0),
		"placeholder_size": Vector2(86.0, 128.0),
	},
	"bg_chixiao_arena": {
		"decal": "res://assets/effects/skills/chixiao_seal.png",
		"decal_size": 500.0,
		"decal_tint": Color(0.70, 0.62, 0.80),
		"decal_opacity": 0.40,
		"texture": "res://assets/scenes/chixiao_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.88, "contrast": 1.16, "saturation": 0.88,
			"lift": -0.010, "gamma": 1.02,
			"shadow_tint": Color(0.90, 0.82, 1.00, 1.0),
			"highlight_tint": Color(1.08, 0.98, 0.88, 1.0),
			"vignette": 0.48,
			"vignette_color": Color(0.06, 0.03, 0.08, 1.0),
			"light_dir": Vector2(0.3, -1.0),
			"light_strength": 0.18,
		},
	},
	"bg_lizhao_arena": {
		## 离照的焚天祭坛：焦红金裂石坪 + 日轮刻痕；比赫连霄的雷云战场更暖、更亮一档。
		"decal": "res://assets/effects/skills/lizhao_sun_seal.png",
		"decal_size": 360.0,
		"decal_tint": Color(1.00, 0.78, 0.50),
		"decal_opacity": 0.30,
		"texture": "res://assets/scenes/lizhao_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.94, "contrast": 1.14, "saturation": 0.94,
			"lift": -0.008, "gamma": 1.02,
			"shadow_tint": Color(1.02, 0.86, 0.74, 1.0),
			"highlight_tint": Color(1.10, 0.98, 0.82, 1.0),
			"vignette": 0.44,
			"vignette_color": Color(0.08, 0.03, 0.03, 1.0),
			"light_dir": Vector2(0.1, -1.0),
			"light_strength": 0.22,
		},
	},
	"bg_calamity_arena": {
		## 三灾台：灰白焦土 + 三道断裂环痕；比赤霄界前两位更冷、更荒。
		"decal": "res://assets/effects/skills/calamity_wheel.png",
		"decal_size": 380.0,
		"decal_tint": Color(0.78, 0.76, 0.82),
		"decal_opacity": 0.34,
		"texture": "res://assets/scenes/calamity_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.92, "contrast": 1.12, "saturation": 0.72,
			"lift": -0.006, "gamma": 1.02,
			"shadow_tint": Color(0.88, 0.88, 0.98, 1.0),
			"highlight_tint": Color(1.04, 1.00, 0.94, 1.0),
			"vignette": 0.46,
			"vignette_color": Color(0.03, 0.03, 0.05, 1.0),
			"light_dir": Vector2(-0.2, -1.0),
			"light_strength": 0.18,
		},
	},
	"bg_qijun_arena": {
		"decal": "res://assets/effects/skills/qi_ring.png",
		"decal_size": 560.0,
		"decal_tint": Color(0.68, 0.86, 0.92),
		"decal_opacity": 0.52,
		"texture": "res://assets/scenes/qijun_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": { "exposure": 0.92, "contrast": 1.10, "saturation": 0.92,
			"vignette": 0.44 },
	},
	"bg_cangjiao_arena": {
		## 云隐谷核心重战：冷杉林下 + 谷心苔石圈贴花（与大地图地标同源）
		"decal": "res://assets/scenes/zhuji_stone_ring.png",
		"decal_size": 660.0,
		"decal_tint": Color(1.00, 1.02, 1.08),
		"decal_opacity": 0.94,
		"texture": "res://assets/scenes/tiles/zhuji_forestfloor.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.94, "contrast": 1.10, "saturation": 0.82,
			"gamma": 1.02,
			"shadow_tint": Color(0.84, 0.95, 1.12, 1.0),
			"highlight_tint": Color(0.98, 1.00, 1.07, 1.0),
			"vignette": 0.44,
			"vignette_color": Color(0.02, 0.045, 0.07, 1.0),
		},
	},
	"bg_youming_arena": {
		## 幽冥灵墟核心重战：冷紫石道 + 青裂地缝，和山门前的战场同源。
		"texture": "res://assets/scenes/tiles/youming_road.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.86, "contrast": 1.14, "saturation": 0.78,
			"gamma": 1.03,
			"shadow_tint": Color(0.80, 0.92, 1.14, 1.0),
			"highlight_tint": Color(0.94, 1.02, 1.10, 1.0),
			"vignette": 0.50,
			"vignette_color": Color(0.02, 0.03, 0.06, 1.0),
			"light_dir": Vector2(0.1, -1.0),
			"light_strength": 0.18,
		},
	},
	"bg_zhaoying_arena": {
		## 照影界 · 镜台：浅水覆过青灰石坪，水面能映出倒影；中央一圈断镜纹。
		## 比赤霄三场更冷、更亮一档，但整体压暗，保证镜面银光与镜像读得清。
		"decal": "res://assets/effects/skills/mirror_seal.png",
		"decal_size": 420.0,
		"decal_tint": Color(0.76, 0.92, 1.00),
		"decal_opacity": 0.32,
		"texture": "res://assets/scenes/zhaoying_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.90, "contrast": 1.13, "saturation": 0.70,
			"lift": -0.008, "gamma": 1.03,
			"shadow_tint": Color(0.80, 0.94, 1.16, 1.0),
			"highlight_tint": Color(0.98, 1.02, 1.10, 1.0),
			"vignette": 0.48,
			"vignette_color": Color(0.02, 0.04, 0.07, 1.0),
			"light_dir": Vector2(0.0, -1.0),
			"light_strength": 0.20,
		},
	},
	"bg_zhaoying_lamp_arena": {
		## 照影界 · 灯台石坪（执烛战场，2026-11-02 重做地面）：
		## 月白浅灰石坪覆一层薄水，**整张一样亮** —— 方向性的光改由灯下的光池 decal 提供。
		## 上一版把「偏北一处光池」画进 tile，一平铺就出现好几个假光源，
		## 和「全场只有一盏界灯」这条核心设定直接打架；而且中位亮度只有 19，
		## 影子的墨和地面的黑是同一个值，射程判定和 BOSS 剪影同时看不见。
		## 现在地面平均 73 / 中位 73 / 近黑 0%，比观澜那一档略亮、比赤霄亮两档。
		"decal": "res://assets/effects/skills/lamp_seal.png",
		"decal_size": 470.0,
		"decal_tint": Color(0.58, 0.70, 0.92),
		## 地面变亮后灯印要压暗一点，否则中央那圈黑核会把视线从影子上抢走
		"decal_opacity": 0.20,
		"texture": "res://assets/scenes/zhaoying_lamp_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.94, "contrast": 1.06, "saturation": 0.72,
			"lift": 0.004, "gamma": 1.00,
			"shadow_tint": Color(0.86, 0.94, 1.12, 1.0),
			"highlight_tint": Color(0.98, 1.01, 1.06, 1.0),
			"vignette": 0.30,
			"vignette_color": Color(0.03, 0.05, 0.09, 1.0),
			"light_dir": Vector2(0.0, -1.0),
			"light_strength": 0.14,
		},
	},
	"bg_zhaoying_fold_arena": {
		## 照影界 · 素纸战场（叠纸战场，2026-11-02）：
		## 一整张淡赭宣纸，纸面只有纤维与几处淡墨渍，**方向光一律交给 decal** ——
		## 执烛上一版把光池画进 tile、一平铺冒出好几个假光源的坑，这里不再踩。
		## 实测：平均 87 / 中位 76 / 近黑 0.0%，袍体月白 ≥ 210，反差拉开两档以上。
		## 折痕本体由 FoldField 画在场上，所以地面自己绝不能再画任何直线。
		"decal": "res://assets/effects/skills/fold_seal.png",
		"decal_size": 460.0,
		"decal_tint": Color(0.72, 0.74, 0.80),
		"decal_opacity": 0.22,
		"texture": "res://assets/scenes/zhaoying_fold_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		"grade": {
			"exposure": 0.97, "contrast": 1.04, "saturation": 0.62,
			"lift": 0.002, "gamma": 1.00,
			"shadow_tint": Color(0.92, 0.92, 1.02, 1.0),
			"highlight_tint": Color(1.00, 0.99, 0.96, 1.0),
			"vignette": 0.18,
			"vignette_color": Color(0.06, 0.06, 0.09, 1.0),
			"light_dir": Vector2(0.0, -1.0),
			"light_strength": 0.10,
		},
	},
	"array_flag_red": {
		"texture": "res://assets/effects/skills/array_flag_red.png",
		"frames": 1, "frame_size": Vector2(96.0, 140.0), "fps": 1.0,
	},
	"array_flag_gold": {
		"texture": "res://assets/effects/skills/array_flag_gold.png",
		"frames": 1, "frame_size": Vector2(96.0, 140.0), "fps": 1.0,
	},
"bg_dingzhen_arena": {
	"decal": "res://assets/effects/skills/array_decal.png",
	"decal_size": 620.0,
	"decal_tint": Color(0.78, 0.72, 0.72),
	"decal_opacity": 0.66,
	"texture": "res://assets/scenes/dingzhen_arena_ground.png",
	"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
	"target_length": 1200.0,
	"map_tiles": 6,
	"tile_width": 600.0,
	"grade": { "exposure": 0.90, "contrast": 1.14, "saturation": 0.90,
		"vignette": 0.46 },
},
"bg_liangyi_arena": {
		"texture": "res://assets/scenes/liangyi_arena_ground.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 1200.0,
		"map_tiles": 6,
		"tile_width": 600.0,
		## 场地中央贴花（2026-10-28 交接包）：太极嵌石盘**只画一次**，
		## 不能并进上面的平铺贴图（那样会跟着 map_tiles 重复 36 次）。
		## ⚠ decal_size 别贪大：1100（视野 1280 的 86%）会让太极盘变成画面主角、
		##   人物反而被吞掉（2026-10-28 模拟实测）。660 + 0.8 不透明度才退成背景。
		"decal": "res://assets/scenes/liangyi_taiji_decal.png",
		"decal_size": 660.0,
		## 白石那半边比石砖亮一大截，光靠 alpha 压不下去（模拟实测：只降 alpha
		## 时它仍然抢过人物）。decal_tint 是颜色乘算，把它压暗并拉回地面的冷灰调。
		"decal_tint": Color(0.62, 0.65, 0.72),
		"decal_opacity": 0.72,
		"placeholder_color": Color(0.12, 0.13, 0.15, 1.0),
		"placeholder_size": Vector2(1600.0, 1200.0),
		# 两仪=云海太极石台：冷墨底、金白高光、强暗角。
		# 与剑客的冷白雾面区分：这张更黑、更硬，石台黑白双色是主体。
		"grade": {
			# 2026-10-28 换成 AI 生图版石台（本身已偏暗、对比强）：
			# 程序化版那次压到 0.74 的曝光回收到 0.90，否则地面会糊成一团黑
			"exposure": 0.90,
			"contrast": 1.12,
			"saturation": 0.86,
			"lift": -0.010,
			"gamma": 1.02,
			"shadow_tint": Color(0.84, 0.91, 1.00, 1.0),
			"highlight_tint": Color(1.06, 1.01, 0.92, 1.0),
			"vignette": 0.44,
			"vignette_color": Color(0.03, 0.04, 0.06, 1.0),
			"light_dir": Vector2(0.2, -1.0),
			"light_strength": 0.20,
		},
	},

	# ============ 剑客 BOSS（凡界第 3 位，剑意蓄压体系）============
	## 换图方式：把剑客立绘/序列帧丢进 assets/characters/，填 texture 或 sprite_frames
	"boss_jianke": {
		## ★ 骨骼（2026-10-26 接入）：idle / walk + 九式全部由 `BossRigSwordsman` 驱动。
		##   素材 = 用户提供的正面立绘 → AI 侧身定妆图 → 拆 6 块刚体件
		##   （body / arm / leg_front / leg_back / shawl1 / shawl2）。
		##   管线：tools/cut_jianke_anchor.py（抠图+归一化）→ tools/build_jianke_rig.py（拆件）
		##   ⚠ 剑客**没有序列帧**，骨骼是唯一形象 —— 某一式没接上就是零动作，没有兜底。
		##     验证必须逐式走 `_begin_skill`，不能只看 idle。
		"rig": "res://assets/characters/boss/jianke_rig/rig.tres",
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 6.0,
		## 与刀客同一口径：内容高 590 × 0.25 ≈ 147.5px，两人同高
		"scale": Vector2(0.25, 0.25),
		## 切帧画布脚底留了 20px 空白，anchor_bottom 会把画布底边贴地面，故下移 5px 让脚真正踩地
		"offset": Vector2(0.0, 5.0),
		"flip_driven": true,
		"anchor_bottom": true,
		# 占位用青蓝色，与刀客的暗红区分
		"placeholder_color": Color(0.22, 0.52, 0.58, 1.0),
		"placeholder_size": Vector2(64.0, 92.0),
	},

	# ============ 两仪真人（位面 02 第 1 位）============
	## 形体：黑白云纹道袍、半黑半白长发、背后悬浮太极环、手持拂尘。
	## 与刀客（暗红巨刀）、剑客（青白剑指）区分：两仪的外轮廓是**长袍 + 背后的圆环**，
	##   剪影一眼就能认出。rig 分件与关节数据在 assets/characters/boss/liangyi_rig/。
	## ⚠ 若 rig.tres 缺失，SkinVisual 会回落到占位色块；这是可接受的降级，
	##   但正式验收前必须补上 rig（否则用户看到的是方块）。
	"boss_liangyi": {
		"rig": "res://assets/characters/boss/liangyi_rig/rig.tres",
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 6.0,
		## 与现有两只人形 BOSS 同一口径：内容高约 590×0.25 ≈ 147px，略高一点点靠发冠补足
		"scale": Vector2(0.25, 0.25),
		"offset": Vector2(0.0, 5.0),
		"flip_driven": true,
		"anchor_bottom": true,
		# 金白 / 青黑各半的占位色
		"placeholder_color": Color(0.72, 0.68, 0.52, 1.0),
		"placeholder_size": Vector2(68.0, 100.0),
	},

	# ============ 清风剑（剑客掉落的武器，御剑战斗形象）============
	## 战斗形象：竖直完整剑身、透明底、**刃尖朝下**（sprite_rotation_deg 按此写的）。
	## 当前图（2026-10-19）由 UI 图标 equip_qingfengjian.png 转正派生（38×161）；
	## 有高清原图时直接覆盖 res://assets/effects/weapons/qingfeng_jian.png 即可。
	## 只填 target_length（想让剑显示多长），scale/offset 由代码按图片内容区自动算。
	"weapon_qingfeng_jian": {
		"texture": "res://assets/effects/weapons/qingfeng_jian.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 68.0,
		## 普攻刀光拖尾：清风剑偏青
		"trail_color": Color(0.58, 0.92, 0.87, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		# 原图刃尖朝下 → 转 -90° 让刃尖朝外
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.62, 0.86, 0.88, 1.0),
		"placeholder_size": Vector2(6.0, 40.0),
	},

	# ============ 后加武器（2026-10-31）============
	## 朱弦阵尺：朱砂阵尺，法系武器；刃尖朝下原图
	"weapon_zhuxian_chizhang": {
		"texture": "res://assets/effects/weapons/zhuxian_chizhang.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 70.0,
		"trail_color": Color(0.92, 0.42, 0.30, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.86, 0.34, 0.26, 1.0),
		"placeholder_size": Vector2(6.0, 44.0),
	},
	## 判官铁笔：铁笔重器，法系武器
	"weapon_panguan_tiebi": {
		"texture": "res://assets/effects/weapons/panguan_tiebi.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 64.0,
		"trail_color": Color(0.92, 0.76, 0.44, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.84, 0.72, 0.48, 1.0),
		"placeholder_size": Vector2(7.0, 40.0),
	},
	## 劫锋：三灾劫刃，纯输出武器
	"weapon_jiefeng": {
		"texture": "res://assets/effects/weapons/jiefeng.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 66.0,
		"trail_color": Color(0.94, 0.52, 0.30, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.80, 0.46, 0.34, 1.0),
		"placeholder_size": Vector2(6.0, 42.0),
	},
	## 镜潭尺：照影界法系短尺，青银镜面，刃尖朝下原图
	"weapon_jingtan_chi": {
		"texture": "res://assets/effects/weapons/jingtan_chi.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 68.0,
		"trail_color": Color(0.62, 0.88, 1.0, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.62, 0.86, 1.0, 1.0),
		"placeholder_size": Vector2(6.0, 44.0),
	},
	## 纸错剑（叠纸掉落，2026-11-02）：薄成一页纸的剑，剑身中段有一道硬折。
	## 与长夜刃同一画布口径（512²、剑尖朝上、sprite_rotation_deg = -90 转持握方向）。
	"weapon_zhicuo_jian": {
		"texture": "res://assets/effects/weapons/zhicuo_jian.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 76.0,
		"trail_color": Color(0.88, 0.92, 1.0, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 9.0,
		"idle_speed": 1.9,
		"idle_bob_amp": 3.2,
		"idle_tilt_deg": 6.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 540.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -72.0,
		"sweep_to_deg": 72.0,
	},
	## 长夜刃：照影界执烛掉落的物理黑刃，刃口不吃光 —— 拖尾给冷银而不是暖金
	"weapon_changye_ren": {
		"texture": "res://assets/effects/weapons/changye_ren.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 74.0,
		"trail_color": Color(0.70, 0.84, 1.0, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 9.0,
		"idle_speed": 1.9,
		"idle_bob_amp": 3.2,
		"idle_tilt_deg": 6.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 540.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -72.0,
		"sweep_to_deg": 72.0,
		"windup_deg": -118.0,
		"windup_time": 0.09,
		"sweep_time": 0.15,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.34, 0.40, 0.58, 1.0),
		"placeholder_size": Vector2(7.0, 46.0),
	},

	# ============ 彩蛋武器：问天剑（2026-11-12）============
	## 练气区石台插剑取下来的那把。原图竖直、刃尖朝下 → sprite_rotation_deg -90 让刃尖朝外。
	## 金色剑身 → 拖尾走暖金，和清风剑的青、长夜刃的蓝灰一眼分开。
	## 长度 72：比清风剑 68 略长、比纸错剑 76 略短（宽刃按面积等效的口径见 WEAPON_DEFAULT_LENGTH 注释）。
	"weapon_wentian_jian": {
		"texture": "res://assets/effects/weapons/wentian_jian.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"target_length": 72.0,
		"trail_color": Color(0.98, 0.86, 0.52, 1.0),
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"sprite_rotation_deg": -90.0,
		"orbit_radius": -1.0,
		"orbit_height": -34.0,
		"idle_base_deg": 180.0,
		"idle_swing_deg": 10.0,
		"idle_speed": 1.8,
		"idle_bob_amp": 3.5,
		"idle_tilt_deg": 5.0,
		"idle_horizontal_only": true,
		"turn_speed_deg": 520.0,
		"idle_rotation_deg": 180.0,
		"sweep_from_deg": -70.0,
		"sweep_to_deg": 70.0,
		"windup_deg": -115.0,
		"windup_time": 0.09,
		"sweep_time": 0.16,
		"spin_turns": 0.25,
		"return_time": 0.3,
		"flip_driven": false,
		"anchor_bottom": false,
		"placeholder_color": Color(0.92, 0.78, 0.40, 1.0),
		"placeholder_size": Vector2(6.0, 44.0),
	},

	# ============ 飞剑（云 / 万剑归宗的投射物形象）============
	## BOSS 脚本生成投射物后会把它的 SkinVisual 指到这个条目（见 domain_boss_01_c.gd）
	"boss_sword_projectile": {
		## ★ 2026-10-21：飞剑形象 = 清风剑（玩家「万剑归宗」与剑客飞剑共用这一条）
		## 图是竖直、刃尖朝下的剑身；投射物每帧 rotation = direction.angle() - PI/2
		## （见 player_projectile / boss_projectile 的 align_visual、剑客 _spawn_sword 的初始朝向），
		## 正好转成「刃尖朝飞行方向」
		"texture": "res://assets/effects/weapons/qingfeng_jian.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": false,
		## 显示剑长（px）：按图片内容高度自动缩放，改这一个数字就能整体放大缩小
		## ⚠ 玩家侧「万剑归宗」与剑客飞剑共用这一条，改大两边一起变
		"target_length": 62.0,
		"placeholder_color": Color(0.55, 0.85, 0.88, 1.0),
		"placeholder_size": Vector2(12.0, 44.0),
	},

	# ============ 万界秘境·大世界（2026-10-26 接入美术）============
	## 药材：**直接复用已定稿的材料图标**（assets/ui/icon/mat_*.png，哑光手绘那 22 张）。
	## 图标和地面是同一套笔触，另出图反而会花；差别只靠 WorldResource 给的确定性
	## 旋转/翻转/缩放抖动，让同一丛三株不像复制粘贴。
	## target_length 按「不透明内容的像素高」定显示尺寸，图标四周的透明边自动被跳过。
	"world_herb_xuecao": {
		"texture": "res://assets/ui/icon/mat_xuecao.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 34.0,
		"placeholder_color": Color(0.80, 0.28, 0.30, 1.0),
		"placeholder_size": Vector2(20.0, 26.0),
	},
	"world_herb_lanying": {
		"texture": "res://assets/ui/icon/mat_lanyingcao.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 34.0,
		"placeholder_color": Color(0.32, 0.52, 0.92, 1.0),
		"placeholder_size": Vector2(20.0, 26.0),
	},
	"world_herb_liyuan": {
		"texture": "res://assets/ui/icon/mat_liyuanguo.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 34.0,
		"placeholder_color": Color(0.90, 0.62, 0.24, 1.0),
		"placeholder_size": Vector2(20.0, 26.0),
	},
	"world_herb_faling": {
		"texture": "res://assets/ui/icon/mat_falinghua.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"target_length": 34.0,
		"placeholder_color": Color(0.66, 0.40, 0.86, 1.0),
		"placeholder_size": Vector2(20.0, 26.0),
	},
	"world_herb_hugu": {
		"texture": "res://assets/ui/icon/mat_huguteng.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		## 护骨藤是一圈盘出来的带刺藤，比草类宽，给多一点才看得清刺
		"target_length": 38.0,
		"placeholder_color": Color(0.42, 0.70, 0.40, 1.0),
		"placeholder_size": Vector2(22.0, 28.0),
	},
	"world_qi_orb": {
		## 纯黑底 + 加色着色器，所以这张图没有 alpha 通道（见 qi_orb.gdshader 顶部）
		"texture": "res://assets/scenes/world/qi_orb.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		## 画布 836px → 显示 46px。⚠ 不能用 target_length：图是不透明的，
		##    get_used_rect() 会返回整张画布，算出来等于没算。
		"scale": Vector2(0.0550, 0.0550),
		"shader": "res://assets/shaders/qi_orb.gdshader",
		"placeholder_color": Color(0.50, 0.95, 0.95, 0.85),
		"placeholder_size": Vector2(26.0, 26.0),
	},
	"world_portal": {
		## 石制月门：品红底抠图 + 封闭洞恢复（虚空是紫的，单靠键色会被当成背景吃掉，
		## 详见 tools/prep_world_props.py 的 _restore_holes）
		"texture": "res://assets/scenes/world/portal_arch.png", "frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		## 内容 926px → 显示 128px；anchor_bottom 让底座落点正好踩在节点原点
		"scale": Vector2(0.1382, 0.1382),
		"anchor_bottom": true,
		"placeholder_color": Color(0.58, 0.36, 0.88, 0.9),
		"placeholder_size": Vector2(58.0, 86.0),
	},
	## 练气区石台插剑（一次性设施，取走即永久消失；见 SecretWorldDB.LIANQI_CONTENT.reliquaries）
	## 透明底单帧图 → 用 target_length 让 SkinVisual 按 used_rect 自动缩放（不像 qi_orb 那样手填 scale）
	## 显示 150px：传送门 128、灵田一格 104×70 —— 比门略大，站在门边一眼能看到「上面有东西」
	"world_sword_shrine": {
		"texture": "res://assets/scenes/world/lianqi_sword_shrine.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"target_length": 150.0,
		"anchor_bottom": true,
		"placeholder_color": Color(0.42, 0.46, 0.44, 1.0),
		"placeholder_size": Vector2(60.0, 96.0),
	},
	## 铸神祭坛（2026-11-13）：每个大世界区域一座，首次取铸神晶、化神后可再取铸神晶+补天石。
	## 带底石台 + 椭圆羽化，target_length 170 ≈ 比传送门(128) / 石台插剑(150) 略大，进区能看见。
	"world_god_altar": {
		"texture": "res://assets/scenes/world/god_altar.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"target_length": 170.0,
		"anchor_bottom": true,
		"placeholder_color": Color(0.55, 0.48, 0.62, 1.0),
		"placeholder_size": Vector2(110.0, 120.0),
	},
	## 2026-10-28：练气区灵兽正式立绘（品红底出图 → tools/prep_lianqi_art.py 抠图整形）。
	## 三只都是**朝右**的侧视，朝向交给 Visual.scale.x 翻转；脚底踩地面走 anchor_bottom。
	## target_length 只写内容高度，宽度随图片比例自动算；换图只改这一个数字。
	"world_beast_fengya": {
		"texture": "res://assets/characters/world/beast_fengya.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 54.0,
		"placeholder_color": Color(0.72, 0.44, 0.26, 1.0),
		"placeholder_size": Vector2(52.0, 40.0),
	},
	"world_beast_jianjia": {
		"texture": "res://assets/characters/world/beast_jianjia.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 58.0,
		"placeholder_color": Color(0.40, 0.48, 0.38, 1.0),
		"placeholder_size": Vector2(56.0, 46.0),
	},
	## 幽冥灵墟灵兽（2026-10-31）：与练气同骨架的阴气变体，单帧贴图
	"world_beast_youming_fengya": {
		"texture": "res://assets/characters/world/youming_beast_fengya.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 60.0,
		"placeholder_color": Color(0.28, 0.20, 0.36, 1.0),
		"placeholder_size": Vector2(54.0, 42.0),
	},
	"world_beast_youming_jianjia": {
		"texture": "res://assets/characters/world/youming_beast_jianjia.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 64.0,
		"placeholder_color": Color(0.24, 0.20, 0.34, 1.0),
		"placeholder_size": Vector2(58.0, 48.0),
	},
	## ===== 试炼之路（肉鸽爬塔）小怪｜2026-11-08 =====
	## 立绘已接（256² 透明底，侧身朝右、底边贴齐 → anchor_bottom 踩地）。
	## `target_length` = **可见内容高度**，SkinVisual 会按它自动算 scale/offset，
	## 所以这里的 scale / offset 只是兜底值。换图后不用改任何战斗或选卡逻辑。
	"rogue_rat": {
		"texture": "res://assets/characters/rogue/rogue_rat.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"placeholder_color": Color(0.52, 0.46, 0.40, 1.0),
		"placeholder_size": Vector2(46.0, 34.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 52.0,
	},
	"rogue_archer": {
		"texture": "res://assets/characters/rogue/rogue_archer.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"placeholder_color": Color(0.34, 0.46, 0.42, 1.0),
		"placeholder_size": Vector2(44.0, 62.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 62.0,
	},
	"rogue_golem": {
		"texture": "res://assets/characters/rogue/rogue_golem.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"placeholder_color": Color(0.46, 0.46, 0.50, 1.0),
		"placeholder_size": Vector2(64.0, 70.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 70.0,
	},
	"rogue_elite": {
		"texture": "res://assets/characters/rogue/rogue_elite.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2.ONE, "offset": Vector2.ZERO,
		"placeholder_color": Color(0.66, 0.30, 0.24, 1.0),
		"placeholder_size": Vector2(78.0, 62.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 62.0,
	},
	"world_core_lianqi": {
		## ★ 正面骨骼（2026-10-29）：body + 双臂 + 下半身，idle/walk/五式由 BossRigApe 驱动
		##   拆件/关节数据由 tools/build_world_boss_rigs.py 生成；texture/target_length 仅作 fallback
		"rig": "res://assets/characters/world/ape_rig/rig.tres",
		"texture": "res://assets/characters/world/ape_qinglan.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2(0.25, 0.25), "offset": Vector2(0.0, 10.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 126.0,
		"placeholder_color": Color(0.32, 0.56, 0.34, 1.0),
		"placeholder_size": Vector2(88.0, 104.0),
	},
	## 云隐谷核心首领「云隐苍角」：苔石古鹿。立绘/rig 后续接入；
	## 未接入时用苔灰占位，不影响战斗与图鉴。
	"world_core_zhuji": {
		## ★ 正面骨骼（2026-10-29）：body + head（含巨角）+ 四腿，idle/walk/八式由 BossRigStag 驱动
		"rig": "res://assets/characters/boss/cangjiao_rig/rig.tres",
		"texture": "res://assets/characters/boss/cangjiao.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2(0.25, 0.25), "offset": Vector2(0.0, 10.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 260.0,
		"placeholder_color": Color(0.33, 0.44, 0.37, 1.0),
		"placeholder_size": Vector2(150.0, 190.0),
	},
	## 赤金火麟：3/4 侧视（朝右），body + head（含双角）+ 火焰尾 + 三腿
	"world_core_jiedan": {
		"rig": "res://assets/characters/boss/qilin_rig/rig.tres",
		"texture": "res://assets/characters/boss/qilin.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2(0.25, 0.25), "offset": Vector2(0.0, 10.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 260.0,
		"placeholder_color": Color(0.62, 0.20, 0.12, 1.0),
		"placeholder_size": Vector2(150.0, 190.0),
	},
	## 镇墟石犼：3/4 侧视（朝右），body + head（含碑鬃）+ 石尾 + 四腿
	"world_core_shihou": {
		"rig": "res://assets/characters/boss/shihou_rig/rig.tres",
		"texture": "res://assets/characters/boss/shihou.png",
		"frames": 1, "frame_size": Vector2.ZERO, "fps": 8.0,
		"scale": Vector2(0.25, 0.25), "offset": Vector2(0.0, 10.0),
		"flip_driven": true, "anchor_bottom": true,
		"target_length": 280.0,
		"placeholder_color": Color(0.24, 0.26, 0.34, 1.0),
		"placeholder_size": Vector2(160.0, 200.0),
	},

	# ============ 插地剑（天剑阵 / 三角封绝）============
	## 竖直剑身插在地面；玩家普攻/功法命中一次即摧毁
	"sky_sword": {
		## ★ 2026-10-21：插地剑形象 = 清风剑（剑尖朝下正好插地）
		## anchor_bottom 让剑底（剑尖）对齐节点原点 = 落地点，剑身立在地面之上
		"texture": "res://assets/effects/weapons/qingfeng_jian.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 8.0,
		"scale": Vector2.ONE,
		"offset": Vector2.ZERO,
		"flip_driven": false,
		"anchor_bottom": true,
		## 显示剑长（px）：比飞剑略长，插在地上更有存在感
		"target_length": 80.0,
		"placeholder_color": Color(0.50, 0.80, 0.85, 1.0),
		"placeholder_size": Vector2(10.0, 52.0),
	},
}

## ============================================================================
## BOSS 招式动作表 —— form_id → SpriteFrames 动画名
## ============================================================================
## 为什么不塞进 MoveDB：招式数据是玩家与 BOSS 共用的（玩家学会同一式后走的还是那条 form），
## 而「这一式摆哪个姿势」只属于**这只 BOSS 的那套美术**。同一式在剑客身上要放它自己的一套动作。
##
## 键 = skin.visual_id（也就是 VISUALS 里那条），值 = {form_id: 动画名}
##   · 动画名必须存在于该 visual 的 SpriteFrames 里，否则 play_one_shot 静默跳过（不报错、只是不动）
##   · 没登记的 form_id 同样不动 —— 缺动作是美术进度问题，不该变成运行期错误
##   · 一个动作可以被多式共用：只要**身体语言与判定形状不矛盾**就行
##     （横扇 / 宽扇 / 留痕斩都是「一道横着扫出去的扇面」，共用 slash_h 反而比各画一套更清楚）
##
## 动作与判定的对应关系（这是本表的立表依据，加新行时照这个口径选）：
##   slash_h      横向扇面扫击    → SHAPE_FAN 宽角
##   smash_v      双手过头竖劈    → SHAPE_FAN 窄角 + 高伤害
##   dash_slash   压低身形前突斩  → 带 dash_speed 的位移招式
##   stomp_aoe    原地沉身踏地    → SHAPE_CIRCLE 以自己为圆心
##   palm_project 侧身伸臂送出    → SHAPE_PROJECTILE 直线投射
##   guard_charge 竖刀护身前摇    → 前摇极长的格挡反击
##   ult_windup   大幅后摆蓄力    → 大招 / 高伤害投射
const BOSS_MOVE_ANIMS: Dictionary = {
	# ============ 赫连霄（赤霄界第 1 位，甲胄判官）============
	## 八式全部由 `boss_rig_thunder.gd` 的「躯干前压宣读 + 双臂 / 铁笔 / 雷鼓」生成；
	## 动画名与 rig 的 TD_SKILLS 一一对应，新增招式时两边要同时加。
	"boss_heiliao": {
		"form_thunder_verdict": "verdict",
		"form_thunder_execute": "execute",
		"form_thunder_drum": "drum",
		"form_thunder_lock": "lock",
		"form_thunder_step": "step",
		"form_thunder_gather": "gather",
		"form_thunder_nine": "nine",
		"form_thunder_prison": "prison",
	},
	# ============ 离照（赤霄界第 2 位，持扇火正）============
	"boss_lizhao": {
		"form_sun_step": "step",
		"form_sun_slash": "slash",
		"form_sun_throw": "throw",
		"form_sun_pull": "pull",
		"form_sun_wind": "wind",
		"form_sun_eclipse": "eclipse",
		"form_sun_wheel": "wheel",
		"form_sun_meteor": "meteor",
	},
	# ============ 晏无咎（赤霄界第 3 位，三灾劫主）============
	"boss_yanwujiu": {
		"form_calamity_step": "step",
		"form_calamity_slash": "slash",
		"form_calamity_fire_seal": "fire_seal",
		"form_calamity_fire_field": "fire_field",
		"form_calamity_thunder_strike": "thunder_strike",
		"form_calamity_thunder_pool": "thunder_pool",
		"form_calamity_turn": "turn",
		"form_calamity_final": "final",
	},
	# ============ 观澜（照影界第 1 位，镜主）============
	## 八式由 `boss_rig_guanying.gd` 的「提镜 / 翻镜 / 推镜」生成；
	## 镜面单独一块，换镜与碎镜时只转镜不扯袍袖。
	"boss_guanying": {
		"form_mirror_slash": "slash",
		"form_mirror_thrust": "thrust",
		"form_mirror_bloom": "bloom",
		"form_mirror_shatter": "shatter",
		"form_mirror_swap": "swap",
		"form_mirror_return": "return",
		"form_mirror_ring": "ring",
		"form_mirror_myriad": "myriad",
	},
	# ============ 执烛（照影界第 2 位，影主）============
	## 八式由 `boss_rig_zhizhu.gd` 的「压身 / 举灯 / 捻灯 / 撕影」生成；
	## 灯笼单独一块，暗场与夺灯时只动灯不扯袖。
	"boss_zhizhu": {
		"form_shadow_cut": "cut",
		"form_shadow_reach": "reach",
		"form_shadow_bind": "bind",
		"form_shadow_step": "step",
		"form_shadow_dim": "dim",
		"form_shadow_beam": "beam",
		"form_shadow_split": "split",
		"form_shadow_longnight": "longnight",
	},
	# ============ 叠纸（照影界第 3 位，折径）============
	## 八式由 `boss_rig_diezhi.gd` 的「压尺 / 掀纸 / 对折 / 三面」生成；
	## ⚠ 这里的动画名必须在 rig 脚本里都存在 —— 名字对不上不会报错，只会静默放 idle。
	"boss_diezhi": {
		"form_fold_press": "press",
		"form_fold_trace": "trace",
		"form_fold_stride": "stride",
		"form_fold_pressmark": "pressmark",
		"form_fold_shroud": "shroud",
		"form_fold_tear": "tear",
		"form_fold_twin": "twin",
		"form_fold_triple": "triple",
	},
	# ============ 太虚气君（冲和界第 3 位，浮空气身）============
	"boss_qijun": {
		"form_qi_gather": "gather",
		"form_qi_wave": "wave",
		"form_qi_spin": "spin",
		"form_qi_lock": "lock",
		"form_qi_ward": "ward",
		"form_qi_step": "step",
		"form_qi_burst": "burst",
		"form_qi_breath": "breath",
	},
	# ============ 大陆核心首领（正面骨骼，2026-10-29）============
	## 每招在 CORE_SKILLS 里有自己的 `anim`；下面只保留 form 兜底（muzzle / 旧调用）
	"world_core_lianqi": {
		"form_smash": "slam",
		"form_arrow": "throw",
		"form_arrow_volley": "volley",
		"form_element_orb": "orb",
	},
	"world_core_zhuji": {
		"form_blade_dash": "gore",
		"form_smash": "stomp",
		"form_slash_single": "sweep",
		"form_arrow_volley": "rocks",
	},
	# ============ 虎妖（凡界第 1 位，兽型）============
	"boss_huyao": {
		"form_slash_single": "slash_single",
		"form_smash": "smash",
		"form_arrow": "arrow",
		"form_element_orb": "element_orb",
		"form_arrow_volley": "arrow_volley",
	},
	# ============ 剑客（凡界第 3 位，空手御剑）============
	## ⚠ 剑客**不持兵刃**：戏里的剑全是召唤出来的飞剑（走 EFFECTS），本体只有剑指。
	##   所以这里登记的是「手势」，不要在这张表里找挥剑动作。
	"boss_jianke": {
		"form_sword_stab": "stab",
		"form_sword_lift": "lift",
		"form_sword_chop": "chop",
		"form_sword_cloud": "cloud",
		"form_sword_pierce": "pierce",
		"form_sword_myriad": "myriad",
		"form_sword_heaven": "heaven",
		"form_sword_heaven_full": "heaven_full",
		"form_sword_triangle": "triangle",
	},
	# ============ 刀客（凡界守关者）============
	"boss_daoke": {
		"form_blade_slash": "slash_h",
		"form_blade_turn": "slash_h",
		"form_blade_scar": "slash_h",
		"form_blade_heavy": "smash_v",
		"form_blade_dash": "dash_slash",
		"form_blade_field": "stomp_aoe",
		"form_blade_qi": "palm_project",
		"form_blade_counter": "guard_charge",
		"form_blade_peak": "ult_windup",
	},
	# ============ 定阵先生（冲和界第 2 位，阵旗）============
	## 八式全部由 `boss_rig_dingzhen.gd` 的「慢蓄力 → 爆发 → 定格」生成；
	## 动画名与 rig 的 DZ_SKILLS 一一对应，新增招式时两边要同时加。
	"boss_dingzhen": {
		"form_array_plant": "plant",
		"form_array_line": "line",
		"form_array_pull": "pull",
		"form_array_seal": "seal",
		"form_array_sweep": "sweep",
		"form_array_step": "step",
		"form_array_pile": "pile",
		"form_array_burst": "burst",
	},
	# ============ 两仪真人（位面 02 第 1 位，人形）============
	## 空手 + 拂尘，动作原型：掌 / 指 / 转 / 崩 / 三叠 / 阴风 / 双鱼 / 倒悬。
	## 与刀客的「肩肘大甩刀」、剑客的「剑指」区分：两仪的表演主力是
	##   **躯干旋转 + 双臂开合 + 背后太极环**，手上不持长兵。
	"boss_liangyi": {
		"form_yinyang_palm": "palm",
		"form_yinyang_finger": "finger",
		"form_yinyang_flip": "flip",
		"form_yinyang_collapse": "collapse",
		"form_yinyang_triple": "triple",
		"form_yinyang_wind": "wind",
		"form_yinyang_fish": "fish",
		"form_yinyang_counter": "counter",
	},
}


## 取某只 BOSS 放某一式时的动作名；没登记返回空串（= 不播动作）
static func boss_move_anim(visual_id: String, form_id: String) -> String:
	var m: Dictionary = BOSS_MOVE_ANIMS.get(visual_id, {})
	return String(m.get(form_id, ""))


## 动画名约定（多帧图集用这些名字切分）
## 未提供对应帧时，视觉节点会回退到第一组帧
const ANIM_IDLE := "idle"
const ANIM_RUN := "run"
const ANIM_ATTACK := "attack"
const ANIM_HURT := "hurt"
const ANIM_DIE := "die"

## ============================================================================
## 特效登记表 —— 与 VISUALS 分离
## ============================================================================
## 为什么单独一张表：特效的语义与「实体形象」不同 ——
##   - 生命周期：播完即销毁（一次性），不常驻
##   - 表现：需要旋转 / 缩放 / 淡出等补间，单纯「贴图或占位」不够
##   - 无碰撞、无血条、不需要朝向翻转
## 由 scripts/visual/fx_player.gd（FxPlayer）消费。
##
## 字段说明（在 VISUALS 字段基础上增加特效专用项）：
##   texture          序列帧图集或 SpriteFrames 资源路径（空 = 用程序化回退绘制）
##   frames           序列帧数；1 = 单帧
##   frame_size       单帧像素尺寸；ZERO 时按图片高度推断（横向排列）
##   fps              序列帧播放速度
##   spawn_offset     特效初始位置相对调用者的偏移
##   spin_speed       播放期间每秒旋转弧度（0 = 不转）
##   sweep_angle_deg  播放期间扫过的角度（度）；与 swing_back 配合做"挥砍"感
##   scale_from/to    播放期间缩放起止值
##   fade_to          结束时透明度（1.0 = 不淡出）
##   lifetime         播放时长（秒）；贴图序列帧时按 frames/fps 自动推算
##   blend_add        是否用加法混合（发光特效通常开）
##   fallback_kind    无贴图时的程序化回退绘制类型（见 FxPlayer.FALLBACK_* 常量）
##   fallback_color   回退绘制的颜色
##   fallback_radius  回退绘制的半径（如弧形刀光的半径）
const EFFECTS: Dictionary = {
	# ============ 锻造台敲击火花（每次锻造命中时播放）============
	## 换图方式：把火花序列帧图集丢进 assets/，填 texture + frames + frame_size + fps。
	## 未接贴图时回退为程序化闪光（fallback_kind = flash），保证开发期也有反馈。
	"forge_strike": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 2.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.6, 0.6),
		"scale_to": Vector2(1.4, 1.4),
		"fade_to": 0.0,
		"lifetime": 0.28,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(1.0, 0.92, 0.7, 0.9),
		"fallback_radius": 34.0,
	},

	# ============ 凡界·换锋符：远程直线穿透剑气（2026-11-07）============
	## 换图方式：覆盖 assets/effects/skills/blade_form_qi.png，玩法代码不动。
	## 贴图 320×96 横向；调用方把节点 global_position 放在「玩家 → 终点」的中点。
	## 未接贴图时回退程序化 rect_beam，保证开发期也有反馈。
	"fx_blade_form_qi": {
		"texture": "res://assets/effects/skills/blade_form_qi.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(1.0, 1.0),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": true,
		"fallback_kind": "rect_beam",
		"fallback_color": Color(0.62, 0.88, 1.0, 0.85),
		"fallback_radius": 160.0,
		"placeholder_color": Color(0.62, 0.88, 1.0, 0.85),
		"placeholder_size": Vector2(320.0, 96.0),
	},

	# ============ 普通攻击刀光 —— 普通挥砍 / 回刀 ============
	"slash_normal": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 70.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.35,
		"blend_add": false,
		## 已改用御剑武器（WeaponOrbit）表现攻击，程序化月牙刀光关闭
		## 想换回刀光就把这里改回 "slash_arc"
		"fallback_kind": "none",
		"fallback_color": Color(1.0, 0.95, 0.8, 0.85),
		"fallback_radius": 60.0,
	},

	# ============ 普通攻击刀光 —— 终结技（第三段，更大更亮偏金）============
	"slash_finisher": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 90.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.5,
		"blend_add": false,
		## 同 slash_normal：终结技刀光也关闭，攻击只由御剑武器表现
		"fallback_kind": "none",
		"fallback_color": Color(1.0, 0.7, 0.3, 0.9),
		"fallback_radius": 84.0,
	},

	# ============ BOSS 近战斩击：**范围色块**（2026-10-19 用户定）============
	## 背景：`slash_normal` / `slash_finisher` 的 fallback 被设成 none（玩家改御剑表现），
	##   结果刀客系招式（横斩/沉步竖斩/破步突进斩/回身斩/留痕斩/纳势反击）连 BOSS 侧
	##   也一起没了画面。这里用「扇形范围色块」兜底：半径与张角**直接取判定值**
	##   （调用方传 radius = range×0.8、sweep_deg = angle），看到多大就是打多大。
	## 有正式美术后：填 texture（横向序列帧 / .tres）即可自动顶替色块，无需改代码。
	"boss_blade_arc": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 90.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 0.0,
		"lifetime": 0.35,
		"blend_add": false,
		## 实心扇形（尺寸=判定扇形），暗红半透明：与玩家黄/蓝伤害色区分
		"fallback_kind": "fan_plane",
		"fallback_color": Color(0.95, 0.38, 0.32, 0.34),
		"fallback_radius": 120.0,
	},

	"boss_blade_arc_heavy": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 110.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 0.0,
		"lifetime": 0.5,
		"blend_add": false,
		## 橙红更亮：终结级斩击（留痕斩 / 纳势反击），范围与判定同源
		"fallback_kind": "fan_plane",
		"fallback_color": Color(1.0, 0.55, 0.28, 0.42),
		"fallback_radius": 180.0,
	},

	# ============ 武器挥砍（贴图绕角色扫过，画出「武器划出一道弧」的效果）============
	## 换图方式：把武器图丢进 assets/effects/，把路径填进 texture 即可，无需改代码
	## 原理：pivot_offset 让武器贴图偏离旋转中心，再由 sweep_angle_deg 让它绕角色扫过。
	##   - pivot_offset.x = 武器离角色中心多远。**填「武器显示长度的一半」**，
	##     握柄就正好落在角色中心；想让手伸出一点就再加 8~12px
	##   - pivot_offset.y = 相对「身体中心」再抬/降多少，一般 0 即可（身体中心已由 body_center 给好）
	##   - scale_from/to 按你的武器图尺寸调：目标显示长度约 50~70px
	## 未填 texture 时本特效不生成（fallback_kind 为 none），不影响现有刀光
	"weapon_slash": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 12.0,
		"spawn_offset": Vector2.ZERO,
		"pivot_offset": Vector2(30.0, 0.0),
		## 武器图刃尖朝右就填 0；朝上填 -90；朝下填 90
		"sprite_rotation_deg": 0.0,
		"spin_speed": 0.0,
		"sweep_angle_deg": 120.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": false,
		"fallback_kind": "none",
		"fallback_color": Color(1.0, 1.0, 1.0, 1.0),
		"fallback_radius": 40.0,
	},

	# ============ 箭矢（物理投掷，可弹反）============
	"arrow_shot": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 0.0,
		"lifetime": 0.18,
		"blend_add": false,
		"fallback_kind": "flash",
		"fallback_color": Color(0.88, 0.90, 0.96, 0.95),
		"fallback_radius": 8.0,
		"fallback_rect_size": Vector2(30.0, 6.0),
	},

	# ============ 砸地冲击（圆形范围）============
	"smash_burst": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.6, 0.6),
		"scale_to": Vector2(1.15, 1.15),
		"fade_to": 0.0,
		"lifetime": 0.35,
		"blend_add": false,
		"fallback_kind": "flash",
		"fallback_color": Color(1.0, 0.6, 0.2, 0.5),
		"fallback_radius": 60.0,
	},

	# ============ 元素法球（不可弹反）============
	"element_orb": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 0.0,
		"lifetime": 0.2,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.4, 0.6, 1.0, 0.9),
		"fallback_radius": 11.0,
	},

	# ============ 刀气（直线法术，可激活刀痕）============
	"blade_qi": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.95, 0.55, 0.45, 0.9),
		"fallback_radius": 14.0,
		"fallback_rect_size": Vector2(120.0, 24.0),
	},

	# ============ 封路刀域（范围法术，激活刀痕）============
	"blade_field": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.5, 0.5),
		"scale_to": Vector2(1.2, 1.2),
		"fade_to": 0.0,
		"lifetime": 0.45,
		"blend_add": false,
		"fallback_kind": "ring",
		"fallback_color": Color(1.0, 0.45, 0.3, 0.75),
		"fallback_radius": 70.0,
	},

	# ========================================================================
	# 剑客（boss_01_c）招式特效 —— 全部青色系，与刀客的橙红区分
	# 未接贴图时走程序化回退（月牙/闪光/冲击环），开发期也有完整反馈
	# ========================================================================

	# ============ 刺：快速直线剑气 ============
	"fx_sword_stab": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.5, 0.5),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.16,
		"blend_add": true,
		"fallback_kind": "slash_arc",
		"fallback_color": Color(0.65, 0.92, 0.95, 0.9),
		"fallback_radius": 240.0,
	},

	# ============ 撩：中等弧线上撩 ============
	"fx_sword_lift": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 100.0,
		"scale_from": Vector2(0.8, 0.8),
		"scale_to": Vector2(1.05, 1.05),
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": true,
		"fallback_kind": "slash_arc",
		"fallback_color": Color(0.60, 0.90, 0.95, 0.9),
		"fallback_radius": 170.0,
	},

	# ============ 斩：大弧度下劈 ============
	"fx_sword_chop": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 160.0,
		"scale_from": Vector2(0.9, 0.9),
		"scale_to": Vector2(1.15, 1.15),
		"fade_to": 0.0,
		"lifetime": 0.28,
		"blend_add": true,
		"fallback_kind": "slash_arc",
		"fallback_color": Color(0.55, 0.88, 0.95, 0.95),
		"fallback_radius": 120.0,
	},

	# ============ 云：飞剑尾迹 ============
	"fx_sword_cloud": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.6, 0.6),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.18,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.70, 0.95, 1.00, 0.85),
		"fallback_radius": 22.0,
	},

	# ============ 万剑归宗：剑幕（多道流光）============
	"fx_sword_myriad": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 22.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.8, 0.8),
		"scale_to": Vector2(1.2, 1.2),
		"fade_to": 0.0,
		"lifetime": 0.5,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(0.60, 0.90, 1.00, 0.85),
		"fallback_radius": 90.0,
	},

	# ============ 一剑开天 · 四段表现（由 SwordHeavenFx 驱动，2026-10-19 重做）============
	## 流程：头顶蓄力（尺寸渐增）→ 直线劈落（带拖尾）→ 撞击生成地面劈痕 → 劈痕停 2 秒再渐隐
	## 换图方式：四张图分别丢进 assets/effects/，在下面四条里填 texture + frames + frame_size + fps即可

	# ---- ① 蓄力：头顶巨型光效，能量持续涌动，尺寸随时间增大 ----
	## 粒子向心聚集 = 能量涌动；scale 补间铺满「蓄力 + 劈落」全程（lifetime 由驱动节点传）
	"fx_sword_heaven_charge": {
		"texture": "res://assets/effects/skills/heaven_charge.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.45, 0.45),
		"scale_to": Vector2(0.95, 0.95),
		"fade_to": 1.0,
		"lifetime": 0.46,
		"blend_add": true,
		"fallback_kind": "gather_orbs",
		"fallback_color": Color(0.55, 0.90, 1.00, 0.95),
		"fallback_radius": 90.0,
		"particle_count": 12,
		"particle_size": Vector2(9.0, 9.0),
		"gather_radius": 90.0,
	},

	# ---- ② 劈落拖尾：沿途落下的光斑，留在原地自行渐隐 ----
	"fx_sword_heaven_trail": {
		"texture": "res://assets/effects/skills/heaven_trail.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.58, 0.58),
		"scale_to": Vector2(0.38, 0.38),
		"fade_to": 0.0,
		"lifetime": 0.34,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.60, 0.92, 1.00, 0.70),
		"fallback_radius": 42.0,
	},

	# ---- ③ 落地矩形劈痕（满剑意）：尺寸 = 判定矩形 1000×160 ----
	## 落地后**固定存活 2 秒**，之后 0.6 秒透明度插值渐隐，alpha 归零即销毁
	"fx_sword_heaven_plane": {
		"texture": "res://assets/effects/skills/heaven_crack_rect.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		## 1024×256 贴图 → 判定矩形 1000×160；pivot 让裂痕从左端（玩家脚下）向前延伸
		"scale_from": Vector2(1000.0 / 1024.0, 160.0 / 256.0),
		"scale_to": Vector2(1000.0 / 1024.0, 160.0 / 256.0),
		"pivot_offset": Vector2(512.0, 0.0),
		"fade_to": 0.0,
		"lifetime": 2.6,
		"hold_time": 2.0,
		"blend_add": false,
		"fallback_kind": "rect_plane",
		"fallback_color": Color(0.50, 0.88, 1.00, 0.55),
		"fallback_rect_size": Vector2(1000.0, 160.0),
	},

	# ---- ④ 落地扇形劈痕（非满剑意）：尺寸 = 判定扇形 220 / 130° ----
	"fx_sword_heaven_fan": {
		"texture": "res://assets/effects/skills/heaven_crack_fan.png",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		## 512×512 贴图 → 半径 220 的落地裂纹
		"scale_from": Vector2(0.86, 0.86),
		"scale_to": Vector2(0.86, 0.86),
		"fade_to": 0.0,
		"lifetime": 2.6,
		"hold_time": 2.0,
		"blend_add": false,
		"fallback_kind": "fan_plane",
		"fallback_color": Color(0.50, 0.88, 1.00, 0.48),
		"fallback_radius": 220.0,
		"fallback_sweep_deg": 130.0,
	},

	# ============ 三角封绝：三剑成阵后的斩决 ============
	"fx_sword_triangle": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.6, 0.6),
		"scale_to": Vector2(1.3, 1.3),
		"fade_to": 0.0,
		"lifetime": 0.35,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(0.50, 0.88, 1.00, 0.9),
		"fallback_radius": 150.0,
	},

	# ============ 天剑下落：坠剑警示 + 落地冲击 ============
	"fx_sky_sword_fall": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.5, 0.5),
		"scale_to": Vector2(1.1, 1.1),
		"fade_to": 0.0,
		"lifetime": 0.3,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.60, 0.90, 1.00, 0.9),
		"fallback_radius": 30.0,
	},

	# ============ 插地剑被击碎 ============
	"fx_sky_sword_break": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.7, 0.7),
		"scale_to": Vector2(1.2, 1.2),
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.70, 0.95, 1.00, 0.9),
		"fallback_radius": 34.0,
	},

	# ============ 剑意充盈（每层剑意的视觉提示）============
	"fx_sword_intent": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 14.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 1.2,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.6, 0.6),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.4,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(0.55, 0.90, 1.00, 0.8),
		"fallback_radius": 40.0,
	},

	# ============ 刀痕激活斩击（2026-10-18 新机制：激活即瞬间斩击）============
	## 每激活一道刀痕播放一次；激活越多，斩击越密（伤害系数 = 激活数量）。
	## 换图方式：把斩击序列帧图集丢进 assets/effects/，填 texture + frames + frame_size + fps。
	## 未接贴图时回退为程序化闪光（fallback_kind = flash），法术青蓝色。
	"scar_slash": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.7, 0.7),
		"scale_to": Vector2(1.3, 1.3),
		"fade_to": 0.0,
		"lifetime": 0.22,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.50, 0.80, 1.00, 0.95),
		"fallback_radius": 40.0,
	},

	# ============ 弹反火花（BOSS 投射物被弹反：径向迸发一簇小粒子）============
	## 换图方式：把迸发序列帧图集丢进 assets/effects/，填 texture + frames + frame_size + fps。
	## 未接贴图时回退为程序化粒子（fallback_kind = spark_burst）：数量/尺寸/飞距均可在表里调。
	"fx_deflect_spark": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,  # 粒子自行淡出，整节点不额外淡
		"lifetime": 0.18,
		"blend_add": false,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(1.0, 0.9, 0.4, 0.9),
		"fallback_radius": 30.0,
		"particle_count": 8,
		"particle_size": Vector2(4.0, 4.0),
		"spark_dist_min": 12.0,
		"spark_dist_max": 30.0,
	},

	# ============ BOSS 弹反：金色光芒迸发 ============
	## 二阶段刀客弹开玩家物理远程时用（2026-10-21 用户定：弹反要有金色光芒迸发）。
	## 比 fx_deflect_spark 更大更亮：粒子更多、飞得更远、加法混合。
	## 换图方式同其它 EFFECTS：assets/effects/ 放序列帧 → 填 texture + frames + frame_size + fps。
	"fx_boss_parry_gold": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.5,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(1.0, 0.86, 0.32, 1.0),
		"fallback_radius": 78.0,
		"particle_count": 26,
		"particle_size": Vector2(4.5, 4.5),
		"spark_dist_min": 22.0,
		"spark_dist_max": 92.0,
	},

	# ============ 玩家弹反：金铁迸溅（2026-10-26 简化，图形合成在 SkillFx.play_parry）============
	## 用户定：弹反不要华丽 —— 大光圈、柔光冲击环、散烟、完美专属月牙**全部取消**，
	## 只留「接触点一颗白点 + 一枚小星芒 + 零星几点碎星」。
	## 理由：弹反是高频动作，一屏里可能连弹四五次；华丽特效会糊住战场，
	##   而真正的反馈强度由顿帧 / 震动 / 音效负责，不该由粒子数量负责。
	## 光温只留两层：hot = 白点与星芒（近白），spark = 碎星尾色（金黄）。
	## 三档只差"量"，不差"层"（自动弹刀 1.2 秒内不限次数，必须比手动更克制）：
	##   fx_parry_auto    最小最暗，3 点碎星
	##   fx_parry_normal  5 点
	##   fx_parry_perfect 7 点、稍大 —— 完美的区分度靠顿帧与定身，不靠特效
	## 换色、改尺寸、调粒子数只动这张表；player.gd 里不写任何配色。
	"fx_parry_auto": {
		"hot": Color(1.0, 0.98, 0.88, 1.0),
		"spark": Color(1.0, 0.80, 0.30, 1.0),
		"contact_offset": 24.0,
		"core_diameter": 18.0,
		"flare_diameter": 40.0,
		"spark_count": 3,
		"spark_fan_deg": 46.0,
		"spark_dist_min": 16.0,
		"spark_dist_max": 42.0,
		"lifetime": 0.16,
	},
	"fx_parry_normal": {
		"hot": Color(1.0, 0.98, 0.88, 1.0),
		"spark": Color(1.0, 0.80, 0.30, 1.0),
		"contact_offset": 26.0,
		"core_diameter": 24.0,
		"flare_diameter": 54.0,
		"spark_count": 5,
		"spark_fan_deg": 62.0,
		"spark_dist_min": 22.0,
		"spark_dist_max": 62.0,
		"lifetime": 0.20,
	},
	"fx_parry_perfect": {
		"hot": Color(1.0, 0.99, 0.92, 1.0),
		"spark": Color(1.0, 0.84, 0.38, 1.0),
		"contact_offset": 30.0,
		"core_diameter": 30.0,
		"flare_diameter": 66.0,
		"spark_count": 7,
		"spark_fan_deg": 78.0,
		"spark_dist_min": 26.0,
		"spark_dist_max": 78.0,
		"lifetime": 0.24,
	},

	# ============ 极限闪避：冷蓝光带（2026-10-25 改版，图形合成在 SkillFx.play_dodge_slip）============
	## 与弹反必须一眼能分：闪避没有兵刃接触 → **不喷金属碎星、不放星芒**，
	## 只沿 _dodge_dir 拖一道冷蓝光带 + 一圈小柔光环 + 少量飘散光点。
	## 已有的 3 帧静止残影 / 全身 _flash / 子弹时间 / 蓝色飘字都不在这里，保持原样。
	"fx_dodge_slip": {
		"hot": Color(0.88, 0.98, 1.0, 1.0),
		"core": Color(0.46, 0.82, 1.0, 1.0),
		"glow": Color(0.22, 0.55, 0.94, 1.0),
		"contact_offset": 0.0,
		"streak_length": 152.0,
		"streak_width": 36.0,
		"streak_layers": 3,
		"ring_radius": 56.0,
		"ring_alpha": 0.34,
		"mote_count": 12,
		"lifetime": 0.34,
	},

	# ============ 召唤物黑色气体（2026-10-21 用户定）============
	## 友军 BOSS 身边持续冒的黑气：由 player._summon_ally_boss 挂的 Timer 每 0.25s 冒一团。
	## 未接贴图时回退为「大颗暗色粒子」（普通混合，加法混合会把黑烟变亮）。
	## 换图方式同其它 EFFECTS：assets/effects/ 放序列帧 → 填 texture + frames + frame_size + fps。
	"fx_summon_black_smoke": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 10.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.55, 0.55),
		"scale_to": Vector2(1.9, 1.9),
		"fade_to": 0.0,
		"lifetime": 0.85,
		"blend_add": false,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(0.17, 0.14, 0.21, 0.78),
		"fallback_radius": 34.0,
		"particle_count": 9,
		"particle_size": Vector2(12.0, 12.0),
		"spark_dist_min": 8.0,
		"spark_dist_max": 32.0,
	},

	# ============ 转阶段能量聚集（四周能量球向心汇聚）============
	## BOSS 转阶段共有演出；换图方式同其它 EFFECTS（assets/effects/ + texture）。
	## 未接贴图时回退为程序化能量球（fallback_kind = gather_orbs）。
	"fx_phase_gather": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,  # 能量球自行淡出，整节点不额外淡
		"lifetime": 0.6,
		"blend_add": false,
		"fallback_kind": "gather_orbs",
		"fallback_color": Color(1.0, 0.3, 0.3, 0.9),
		"fallback_radius": 90.0,
		"particle_count": 12,
		"particle_size": Vector2(10.0, 10.0),
		"gather_radius": 90.0,
	},

	# ============ 主动法宝表现（2026-10-25）============
	## 凝水佩启动：蓝色水灵光点从四周向身体聚拢
	"fx_treasure_water_gather": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.8, 0.8),
		"scale_to": Vector2(1.1, 1.1),
		"fade_to": 1.0,
		"lifetime": 0.7,
		"blend_add": true,
		"fallback_kind": "gather_orbs",
		"fallback_color": Color(0.35, 0.78, 1.0, 0.95),
		"fallback_radius": 70.0,
		"particle_count": 18,
		"particle_size": Vector2(6.0, 6.0),
		"gather_radius": 72.0,
	},
	## 逐电环启动：黄色雷光从身体向外炸开，之后由 TreasureFx 的雷弧与拖尾接续
	"fx_treasure_thunder_burst": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.38,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(1.0, 0.92, 0.28, 1.0),
		"fallback_radius": 56.0,
		"particle_count": 20,
		"particle_size": Vector2(5.0, 5.0),
		"spark_dist_min": 18.0,
		"spark_dist_max": 64.0,
	},
	## 续命灯触发：暖黄魂火炸开（灯替一死）
	"fx_treasure_lamp_break": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 22.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.55,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(1.0, 0.84, 0.42, 1.0),
		"fallback_radius": 72.0,
		"particle_count": 26,
		"particle_size": Vector2(6.0, 6.0),
		"spark_dist_min": 20.0,
		"spark_dist_max": 92.0,
	},
	## 蚀甲锥命中：暗绿蚀屑迸开，和「护体被钻开」对色
	"fx_treasure_cone_hit": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.34,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(0.60, 0.84, 0.44, 1.0),
		"fallback_radius": 42.0,
		"particle_count": 14,
		"particle_size": Vector2(4.0, 4.0),
		"spark_dist_min": 10.0,
		"spark_dist_max": 46.0,
	},
	## 血饲印：暗红血点从印面炸开
	"fx_treasure_blood_seal": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.48,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(0.84, 0.22, 0.18, 1.0),
		"fallback_radius": 52.0,
		"particle_count": 18,
		"particle_size": Vector2(5.0, 5.0),
		"spark_dist_min": 14.0,
		"spark_dist_max": 66.0,
	},
	## 棘甲佩反伤：暗红棘刺迸开
	"fx_treasure_thorns_burst": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.32,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(0.88, 0.28, 0.22, 1.0),
		"fallback_radius": 46.0,
		"particle_count": 12,
		"particle_size": Vector2(4.0, 4.0),
		"spark_dist_min": 12.0,
		"spark_dist_max": 50.0,
	},
	## 回风袋：一圈浅青风屑
	"fx_treasure_gust": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 20.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.42,
		"blend_add": true,
		"fallback_kind": "spark_burst",
		"fallback_color": Color(0.62, 0.88, 0.84, 1.0),
		"fallback_radius": 74.0,
		"particle_count": 20,
		"particle_size": Vector2(5.0, 5.0),
		"spark_dist_min": 20.0,
		"spark_dist_max": 96.0,
	},

	# ============ 角色传送登场（2026-10-24）============
	## 进入副本 / 返回原初位面的登场演出：外扩光环 + 向心光点 + 角色由小放大淡入。
	## 未接贴图时走程序化 ring / gather_orbs；后续换图直接填 texture / sprite_frames 即可。
	"teleport_arrival": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.35, 0.35),
		"scale_to": Vector2(1.9, 1.9),
		"fade_to": 0.0,
		"lifetime": 0.75,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(0.55, 0.9, 1.0, 0.92),
		"fallback_radius": 86.0,
	},
	"teleport_gather": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2.ONE,
		"scale_to": Vector2.ONE,
		"fade_to": 1.0,
		"lifetime": 0.65,
		"blend_add": true,
		"fallback_kind": "gather_orbs",
		"fallback_color": Color(0.62, 0.9, 1.0, 0.95),
		"fallback_radius": 80.0,
		"particle_count": 14,
		"particle_size": Vector2(7.0, 7.0),
		"gather_radius": 70.0,
	},
	## 竖直光柱：从脚底向上升起，作为传送登场的「落点」主视觉
	"teleport_beam": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 16.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.92, 0.72),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.6,
		"blend_add": true,
		"fallback_kind": "soft_beam",
		"fallback_color": Color(0.68, 0.92, 1.0, 0.95),
		"fallback_rect_size": Vector2(76.0, 200.0),
	},

	# ============ 符箓四式（2026-11-09）============
	## 换图方式：把符纸 / 符火贴图丢进 assets/effects/skills/，填 texture + frames + frame_size + fps，
	## 玩法代码一行不用改。未接贴图时全部走程序化回退（flash / ring / fan_plane），开发期也有反馈。
	## ⚠ 四张表只描述**表现**：判定范围与倍率在 MoveDB 的 form / player.gd 的符匣逻辑里。
	"fx_talisman_draw": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.45, 0.45),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.30,
		"blend_add": true,
		"fallback_kind": "flash",
		"fallback_color": Color(0.94, 0.52, 0.34, 0.85),
		"fallback_radius": 26.0,
	},
	"fx_talisman_paste": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.70, 0.70),
		"scale_to": Vector2(1.0, 1.0),
		"fade_to": 0.0,
		"lifetime": 0.28,
		"blend_add": true,
		"fallback_kind": "fan_plane",
		"fallback_color": Color(0.90, 0.74, 0.42, 0.80),
		"fallback_radius": 170.0,
		"fallback_sweep_deg": 90.0,
	},
	"fx_talisman_burst": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.35, 0.35),
		"scale_to": Vector2(1.15, 1.15),
		"fade_to": 0.0,
		"lifetime": 0.36,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(1.0, 0.56, 0.32, 0.92),
		"fallback_radius": 120.0,
	},
	"fx_talisman_ward": {
		"texture": "",
		"frames": 1,
		"frame_size": Vector2.ZERO,
		"fps": 18.0,
		"spawn_offset": Vector2.ZERO,
		"spin_speed": 0.0,
		"sweep_angle_deg": 0.0,
		"scale_from": Vector2(0.55, 0.55),
		"scale_to": Vector2(1.05, 1.05),
		"fade_to": 0.0,
		"lifetime": 0.42,
		"blend_add": true,
		"fallback_kind": "ring",
		"fallback_color": Color(0.92, 0.80, 0.44, 0.90),
		"fallback_radius": 62.0,
	},
}


## ===== 玩家技能表现（2026-10-25）=====
## 玩家主动功法不再共用「扇形/方块/圆环」占位，而是按功法名走一套「刀 / 剑 / 虎」分族视觉：
##   - 刀：炽金 + 余烬，重斩、刀气、刀域、蓄势
##   - 剑：霜青 + 流云，点刺、撩斩、云、万剑、天光
##   - 虎：暗金 + 赤煞，爪痕、飞砂、踏地、妖丹
## 一条数据只描述「这一招该怎么演」，具体绘制在 scripts/visual/skill_fx.gd；
## 想换配色/范围/震屏只改本表，想换主体贴图改 SKILL_TEXTURES / VISUALS。
## projectile_* 字段是给 player_projectile 的外观与拖尾用的。
const SKILL_FAMILIES: Dictionary = {
	"qi": {"glow": Color(0.60, 0.90, 1.00), "shake": 2.4, "sparks": 18, "dust": 10},
	"blade": {
		"motif": "slash", "arc": 120.0, "thickness": 0.24, "rotation": 0.0,
		"layers": 2, "lifetime": 0.38, "sweep": 0.13,
		"core": Color(1.0, 0.92, 0.70), "hot": Color(1.0, 0.98, 0.86),
		"glow": Color(1.0, 0.40, 0.10), "smoke": Color(0.18, 0.10, 0.06),
		"spark": Color(1.0, 0.62, 0.20),
		"sparks": 24, "dust": 14, "smoke_count": 10,
		"shake": 2.4, "weapon": "horizontal", "cast_glow": 0.6,
		"projectile_trail": "",
	},
	"sword": {
		"motif": "slash", "arc": 100.0, "thickness": 0.20, "rotation": 0.0,
		"layers": 2, "lifetime": 0.40, "sweep": 0.12,
		"core": Color(0.86, 0.99, 1.0), "hot": Color(0.97, 1.0, 1.0),
		"glow": Color(0.22, 0.62, 1.0), "smoke": Color(0.10, 0.17, 0.22),
		"spark": Color(0.72, 0.95, 1.0),
		"sparks": 22, "dust": 8, "smoke_count": 16,
		"shake": 2.0, "weapon": "horizontal", "cast_glow": 0.55,
		"projectile_trail": "",
	},
	"tiger": {
		"motif": "claw", "arc": 80.0, "thickness": 0.22, "rotation": 0.0,
		"layers": 3, "lifetime": 0.44, "sweep": 0.15,
		"core": Color(1.0, 0.82, 0.46), "hot": Color(1.0, 0.96, 0.72),
		"glow": Color(0.66, 0.12, 0.05), "smoke": Color(0.16, 0.09, 0.05),
		"spark": Color(1.0, 0.55, 0.16),
		"sparks": 30, "dust": 22, "smoke_count": 18,
		"shake": 4.6, "weapon": "none", "cast_glow": 0.7,
		"projectile_trail": "",
	},
	## 练气区灵兽（2026-10-28）：土黄 / 琥珀，比虎妖小一号、出手更快
	"beast": {
		"motif": "claw", "arc": 96.0, "thickness": 0.22, "rotation": 0.0,
		"layers": 2, "lifetime": 0.36, "sweep": 0.11,
		"core": Color(1.0, 0.90, 0.70), "hot": Color(1.0, 0.97, 0.88),
		"glow": Color(0.76, 0.40, 0.15), "smoke": Color(0.16, 0.12, 0.08),
		"spark": Color(1.0, 0.72, 0.34),
		"sparks": 24, "dust": 16, "smoke_count": 10,
		"shake": 2.6, "weapon": "none", "cast_glow": 0.45,
		"projectile_trail": "",
	},
	## 青岚古猿（2026-10-28）：木 / 石，碧玉高光 + 深苔底色
	"ape": {
		"motif": "slash", "arc": 120.0, "thickness": 0.30, "rotation": 0.0,
		"layers": 2, "lifetime": 0.42, "sweep": 0.12,
		"core": Color(0.88, 0.96, 0.72), "hot": Color(0.96, 1.0, 0.86),
		"glow": Color(0.30, 0.55, 0.22), "smoke": Color(0.10, 0.13, 0.08),
		"spark": Color(0.70, 0.92, 0.48),
		"sparks": 30, "dust": 30, "smoke_count": 20,
		"shake": 5.0, "weapon": "none", "cast_glow": 0.7,
		"projectile_trail": "",
	},
	"array": {
		## 定阵先生族：朱砂红 + 墨 + 石青。阵旗/阵线是机制本体，技能特效只做"引线成伤"。
		"motif": "slash", "arc": 120.0, "thickness": 0.22, "rotation": 0.0,
		"layers": 2, "lifetime": 0.40, "sweep": 0.12,
		"core": Color(1.0, 0.86, 0.72), "hot": Color(1.0, 0.94, 0.86),
		"glow": Color(0.86, 0.30, 0.22), "smoke": Color(0.10, 0.09, 0.09),
		"spark": Color(0.98, 0.62, 0.44),
		"sparks": 22, "dust": 10, "smoke_count": 16,
		"shake": 2.6, "weapon": "none", "cast_glow": 0.6,
	},
	"yinyang": {
		## 两仪族：金白（阳）/ 青黑（阴）双色。族默认取阳的暖金，
		## 阴招在自己的 SKILL_FX 条目里覆盖 glow / core / spark 为青黑。
		"motif": "slash", "arc": 116.0, "thickness": 0.22, "rotation": 0.0,
		"layers": 2, "lifetime": 0.40, "sweep": 0.12,
		"core": Color(1.0, 0.95, 0.78), "hot": Color(1.0, 1.0, 0.94),
		"glow": Color(0.90, 0.68, 0.24), "smoke": Color(0.06, 0.08, 0.09),
		"spark": Color(1.0, 0.84, 0.42),
		"sparks": 24, "dust": 10, "smoke_count": 18,
		"shake": 2.6, "weapon": "none", "cast_glow": 0.65,
		"projectile_trail": "",
	},
}

const SKILL_FX: Dictionary = {
	# ---------------- 太虚气君（气族，2026-10-28）----------------
	"skill_qi_gather": {"motif": "qi_cloud", "qi_mode": "gather", "family": "qi", "glow": Color(0.56, 0.86, 1.0),
		"lifetime": 0.8, "field_pulses": 3, "field_pulse_gap": 0.16, "shake": 1.6, "impact": 0.03, "sparks": 22},
	"skill_qi_wave": {"motif": "qi_cloud", "qi_mode": "wave", "family": "qi", "glow": Color(0.72, 0.95, 1.0),
		"layers": 3, "thickness": 0.30, "sweep": 0.06, "shake": 4.2, "impact": 0.03, "sparks": 36},
	"skill_qi_spin": {"motif": "qi_cloud", "qi_mode": "spin", "family": "qi", "glow": Color(0.62, 0.92, 1.0),
		"layers": 4, "thickness": 0.30, "shake": 4.6, "impact": 0.04, "dust": 28, "sparks": 30},
	"skill_qi_lock": {"motif": "qi_cloud", "qi_mode": "lock", "family": "qi", "glow": Color(0.58, 0.86, 1.0),
		"layers": 3, "thickness": 0.22, "shake": 3.0, "impact": 0.03, "sparks": 26},
	"skill_qi_ward": {"motif": "qi_cloud", "qi_mode": "ward", "family": "qi", "glow": Color(0.78, 0.98, 1.0),
		"layers": 3, "thickness": 0.30, "shake": 4.0, "sparks": 30},
	## 踏罡：玩家侧也走云烟一族（原来是通用 stomp，和这套气质不搭）；
	## BOSS 自己的踏罡仍由 QiFx.play_cloud_step 负责，不受这里影响
	"skill_qi_step": {"motif": "qi_cloud", "qi_mode": "step", "family": "qi", "glow": Color(0.62, 0.90, 1.0),
		"layers": 2, "thickness": 0.26, "shake": 3.0, "dust": 24, "sparks": 14},
	"skill_qi_burst": {"motif": "qi_cloud", "qi_mode": "burst", "family": "qi", "glow": Color(0.80, 0.98, 1.0),
		"layers": 4, "thickness": 0.34, "shake": 10.0, "impact": 0.06, "dust": 50, "sparks": 80},
	"skill_qi_breath": {"motif": "qi_cloud", "qi_mode": "breath", "family": "qi", "glow": Color(0.62, 0.98, 0.82),
		"lifetime": 1.1, "field_pulses": 4, "field_pulse_gap": 0.26, "shake": 0.0, "sparks": 18},

	# ---------------- 定阵先生 ----------------
	"skill_array_plant": {"motif": "rune", "family": "array", "cast_glow": 0.9, "shake": 1.4, "sparks": 12},
	"skill_array_line": {"motif": "cord", "family": "array", "layers": 3, "thickness": 0.16, "sweep": 0.06, "shake": 3.4, "sparks": 26},
	"skill_array_pull": {"motif": "cord", "family": "array", "arc": 90.0, "layers": 1, "thickness": 0.30, "shake": 2.4},
	"skill_array_seal": {"motif": "box", "family": "array", "lifetime": 1.6, "field_pulses": 3, "field_pulse_gap": 0.45, "shake": 2.2},
	"skill_array_sweep": {"motif": "slash", "family": "array", "arc": 150.0, "layers": 3, "thickness": 0.26, "sweep": 0.14, "shake": 4.4},
	"skill_array_step": {"motif": "dash", "family": "array", "dash_streaks": 9, "shake": 2.6},
	"skill_array_pile": {"motif": "stomp", "family": "array", "shake": 6.6, "sparks": 40, "dust": 30},
	"skill_array_burst": {"motif": "pillars", "family": "array", "shake": 8.2, "sparks": 56, "dust": 40},

	# ---------------- 虎妖 ----------------
	"skill_tiger_claw": {
		"motif": "claw", "arc": 74.0, "thickness": 0.22, "layers": 3,
		"sweep": 0.12, "sparks": 38, "dust": 20, "smoke_count": 24,
		"shake": 4.8, "weapon": "none", "noise_amount": 0.40,
	},
	"skill_tiger_rock": {
		"motif": "volley", "arc": 60.0, "layers": 1, "sweep": 0.10,
		"sparks": 16, "dust": 34, "smoke_count": 14, "shake": 2.0,
		"weapon": "none", "projectile_visual": "skill_tiger_rock",
		"projectile_align": false, "projectile_trail": "sand",
	},
	"skill_tiger_sandstorm": {
		"motif": "volley", "arc": 70.0, "layers": 1, "sweep": 0.10,
		"sparks": 26, "dust": 52, "smoke_count": 20, "shake": 3.0,
		"weapon": "none", "projectile_visual": "skill_tiger_rock",
		"projectile_align": false, "projectile_trail": "sand",
	},
	"skill_tiger_stomp": {
		"motif": "stomp", "arc": 360.0, "radius_mult": 1.25, "layers": 1,
		"sparks": 34, "dust": 56, "smoke_count": 44, "shake": 6.5,
		"weapon": "none", "cast_glow": 1.0,
	},
	"skill_tiger_orb": {
		"motif": "orb", "layers": 1, "sparks": 20, "dust": 10,
		"smoke_count": 32, "shake": 2.2, "weapon": "none", "cast_glow": 1.0,
		"projectile_visual": "skill_tiger_orb", "projectile_align": false,
		"projectile_trail": "smoke",
	},

	# ---------------- 练气区灵兽（2026-10-28）----------------
	## 锋牙兽「裂牙扑咬」：三道琥珀爪痕，张角直接取判定张角（WorldEnemy 传）
	"skill_beast_bite": {
		"family": "beast", "motif": "claw", "thickness": 0.18, "layers": 2,
		"lifetime": 0.32, "sweep": 0.10, "sparks": 20, "dust": 12,
		"smoke_count": 8, "shake": 2.4, "weapon": "none", "cast_glow": 0.4,
		"core": Color(0.98, 0.82, 0.52), "hot": Color(1.0, 0.93, 0.72),
		"glow": Color(0.70, 0.38, 0.14), "spark": Color(1.0, 0.64, 0.28),
		"flash_alpha": 0.55,
	},
	## 坚甲兽「甲背撞击」：厚石色横扫 + 大量扬尘，读作身体撞出的冲击
	"skill_beast_charge": {
		"family": "beast", "motif": "slash", "thickness": 0.30, "layers": 2,
		"lifetime": 0.38, "sweep": 0.13, "noise_amount": 0.40,
		"core": Color(0.58, 0.48, 0.30), "hot": Color(0.78, 0.66, 0.44),
		"glow": Color(0.24, 0.20, 0.12), "spark": Color(0.70, 0.56, 0.32),
		"sparks": 26, "dust": 36, "smoke_count": 20,
		"shake": 4.2, "weapon": "none", "cast_glow": 0.35,
		"flash_alpha": 0.22,
	},

	# ---------------- 青岚古猿（2026-10-28）----------------
	## 平A「古猿裂地击」：贴地厚冲击扇面；张角 / 距离由 WorldEnemy 按判定传入
	"skill_ape_swipe": {
		"family": "ape", "motif": "slash", "thickness": 0.32, "layers": 2,
		"lifetime": 0.40, "sweep": 0.11, "noise_amount": 0.42,
		"core": Color(1.0, 0.93, 0.74), "hot": Color(1.0, 0.97, 0.88),
		"glow": Color(0.58, 0.58, 0.26), "spark": Color(0.94, 0.84, 0.46),
		"sparks": 30, "dust": 30, "smoke_count": 22,
		"shake": 5.2, "weapon": "none", "cast_glow": 0.6,
	},
	## 裂地重锤：圆形砸地，视觉半径 = 判定半径；苔金冲击环
	"skill_ape_slam": {
		"family": "ape", "motif": "stomp", "lifetime": 0.5,
		"ring": Color(0.62, 0.86, 0.44), "crack_texture": "ape_crack",
		"crack_tint": Color(1.0, 1.0, 1.0, 1.0),
		"ring_alpha": 0.42, "flash_alpha": 0.60,
		"sparks": 40, "dust": 52, "smoke_count": 36, "shake": 7.0,
		"weapon": "none", "cast_glow": 1.0,
	},
	## 崩石投掷：单块苔石；投掷物外观由本条的 projectile_visual 决定
	"skill_ape_boulder": {
		"family": "ape", "motif": "volley", "lifetime": 0.4,
		"sparks": 10, "dust": 26, "smoke_count": 14, "shake": 2.2,
		"weapon": "none", "cast_glow": 0.8,
		"projectile_visual": "ape_boulder", "projectile_align": false,
		"projectile_scale": 1.15, "projectile_trail": "sand",
	},
	## 乱石飞掷：同一块石，数量 5、单颗更小
	"skill_ape_volley": {
		"family": "ape", "motif": "volley", "arc": 70.0, "lifetime": 0.45,
		"sparks": 18, "dust": 34, "smoke_count": 18, "shake": 3.2,
		"weapon": "none", "cast_glow": 0.9,
		"projectile_visual": "ape_boulder", "projectile_align": false,
		"projectile_scale": 0.85, "projectile_trail": "sand",
	},
	## 山崩地裂：二阶段大范围砸地，比裂地重锤更大、更绿、更晃
	"skill_ape_quake": {
		"family": "ape", "motif": "stomp", "lifetime": 0.6,
		"ring": Color(0.50, 0.82, 0.34), "crack_texture": "ape_crack",
		"crack_tint": Color(1.0, 1.0, 1.0, 1.0),
		"ring_alpha": 0.32, "flash_alpha": 0.45,
		"sparks": 54, "dust": 72, "smoke_count": 48, "shake": 10.0,
		"weapon": "none", "cast_glow": 1.2,
	},
	## 青岚灵爆：碧玉法球，比虎妖妖丹更冷、更绿
	"skill_ape_orb": {
		"family": "ape", "motif": "orb", "lifetime": 0.5,
		"sparks": 26, "dust": 12, "smoke_count": 34, "shake": 2.6,
		"weapon": "none", "cast_glow": 1.1,
		"projectile_visual": "ape_orb", "projectile_align": false,
		"projectile_scale": 1.25, "projectile_trail": "smoke",
	},
	# ---------------- 镇墟石犼（2026-10-31）----------------
	## 盲拍 / 裂石爪：墓石灰白 + 青幽火；claw 读作兽爪，不用人形剑光
	"skill_shihou_swipe": {
		"family": "beast", "motif": "claw", "thickness": 0.20, "layers": 2,
		"lifetime": 0.34, "sweep": 0.10, "sparks": 18, "dust": 18,
		"smoke_count": 10, "shake": 2.6, "weapon": "none", "cast_glow": 0.35,
		"core": Color(0.86, 0.94, 1.0), "hot": Color(0.98, 1.0, 1.0),
		"glow": Color(0.20, 0.40, 0.46), "spark": Color(0.55, 0.92, 0.90),
		"flash_alpha": 0.42,
	},
	"skill_shihou_claw": {
		"family": "beast", "motif": "claw", "thickness": 0.22, "layers": 2,
		"lifetime": 0.36, "sweep": 0.12, "sparks": 22, "dust": 16,
		"smoke_count": 10, "shake": 3.0, "weapon": "none", "cast_glow": 0.4,
		"core": Color(0.88, 0.96, 1.0), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.18, 0.38, 0.44), "spark": Color(0.52, 0.90, 0.88),
		"flash_alpha": 0.46,
	},
	"skill_shihou_pounce": {
		"family": "beast", "motif": "slash", "thickness": 0.30, "layers": 2,
		"lifetime": 0.40, "sweep": 0.14, "noise_amount": 0.42,
		"core": Color(0.80, 0.90, 0.98), "hot": Color(0.98, 1.0, 1.0),
		"glow": Color(0.18, 0.34, 0.40), "spark": Color(0.50, 0.86, 0.86),
		"sparks": 30, "dust": 38, "smoke_count": 22,
		"shake": 4.6, "weapon": "none", "cast_glow": 0.55,
		"flash_alpha": 0.28,
	},
	"skill_shihou_charge": {
		"family": "beast", "motif": "slash", "thickness": 0.34, "layers": 3,
		"lifetime": 0.50, "sweep": 0.18, "noise_amount": 0.55,
		"core": Color(0.76, 0.88, 0.96), "hot": Color(0.98, 1.0, 1.0),
		"glow": Color(0.16, 0.32, 0.38), "spark": Color(0.48, 0.84, 0.86),
		"sparks": 40, "dust": 54, "smoke_count": 32,
		"shake": 6.8, "weapon": "none", "cast_glow": 0.75,
		"flash_alpha": 0.30,
	},
	"skill_shihou_tail": {
		"family": "beast", "motif": "slash", "thickness": 0.28, "layers": 2,
		"lifetime": 0.42, "sweep": 0.24, "noise_amount": 0.36,
		"core": Color(0.82, 0.92, 1.0), "hot": Color(0.98, 1.0, 1.0),
		"glow": Color(0.20, 0.38, 0.44), "spark": Color(0.54, 0.90, 0.88),
		"sparks": 26, "dust": 30, "smoke_count": 18,
		"shake": 4.0, "weapon": "none", "cast_glow": 0.45,
		"flash_alpha": 0.26,
	},
	"skill_shihou_slam": {
		"family": "stag", "motif": "stomp", "lifetime": 0.52,
		"ring": Color(0.44, 0.80, 0.86), "crack_texture": "ape_crack",
		"crack_tint": Color(0.80, 0.96, 1.0, 1.0),
		"ring_alpha": 0.34, "flash_alpha": 0.42,
		"sparks": 36, "dust": 52, "smoke_count": 30, "shake": 6.8,
		"weapon": "none", "cast_glow": 0.85,
	},
	"skill_shihou_breath": {
		"family": "stag", "motif": "slash", "thickness": 0.30, "layers": 1,
		"lifetime": 0.55, "sweep": 0.10, "noise_amount": 0.60,
		"core": Color(0.78, 0.92, 1.0), "hot": Color(0.96, 1.0, 1.0),
		"glow": Color(0.18, 0.36, 0.42), "spark": Color(0.52, 0.88, 0.88),
		"sparks": 20, "dust": 40, "smoke_count": 38,
		"shake": 3.2, "weapon": "none", "cast_glow": 0.5,
	},
	# ---------------- 云隐苍角（2026-10-29）----------------
	## 角撞：冷白角风 + 石粉，区别于青岚古猿的暖金裂地
	"skill_stag_gore": {
		"family": "stag", "motif": "slash", "thickness": 0.30, "layers": 2,
		"lifetime": 0.38, "sweep": 0.10, "noise_amount": 0.36,
		"core": Color(0.90, 0.96, 1.00), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.34, 0.46, 0.44), "spark": Color(0.70, 0.88, 0.74),
		"sparks": 28, "dust": 26, "smoke_count": 18,
		"shake": 5.0, "weapon": "none", "cast_glow": 0.55,
	},
	## 角扫：更宽、更薄的横甩，草屑少一点，读作巨角扫风
	"skill_stag_sweep": {
		"family": "stag", "motif": "slash", "thickness": 0.22, "layers": 2,
		"lifetime": 0.34, "sweep": 0.15, "noise_amount": 0.30,
		"core": Color(0.84, 0.94, 1.00), "hot": Color(1.0, 1.0, 0.96),
		"glow": Color(0.30, 0.42, 0.40), "spark": Color(0.62, 0.84, 0.70),
		"sparks": 22, "dust": 20, "smoke_count": 14,
		"shake": 3.6, "weapon": "none", "cast_glow": 0.45,
	},
	## 踏地：青苔石环 + 冷灰裂痕
	"skill_stag_stomp": {
		"family": "stag", "motif": "stomp", "lifetime": 0.48,
		"ring": Color(0.55, 0.80, 0.68), "crack_texture": "ape_crack",
		"crack_tint": Color(0.86, 0.96, 0.94, 1.0),
		"ring_alpha": 0.38, "flash_alpha": 0.48,
		"sparks": 34, "dust": 46, "smoke_count": 28, "shake": 6.4,
		"weapon": "none", "cast_glow": 0.9,
	},
	## 鹿鸣·山回：二阶段大范围寒青震波
	"skill_stag_quake": {
		"family": "stag", "motif": "stomp", "lifetime": 0.58,
		"ring": Color(0.48, 0.74, 0.64), "crack_texture": "ape_crack",
		"crack_tint": Color(0.80, 0.94, 0.96, 1.0),
		"ring_alpha": 0.30, "flash_alpha": 0.40,
		"sparks": 50, "dust": 64, "smoke_count": 44, "shake": 9.0,
		"weapon": "none", "cast_glow": 1.1,
	},
	## 雾吐：冷雾为主的扇形，火花少、烟多
	"skill_stag_mist": {
		"family": "stag", "motif": "slash", "thickness": 0.26, "layers": 1,
		"lifetime": 0.5, "sweep": 0.08, "noise_amount": 0.55,
		"core": Color(0.76, 0.92, 1.00), "hot": Color(0.94, 0.99, 1.0),
		"glow": Color(0.30, 0.48, 0.56), "spark": Color(0.60, 0.84, 0.92),
		"sparks": 14, "dust": 18, "smoke_count": 46,
		"shake": 2.4, "weapon": "none", "cast_glow": 0.8,
	},
	## 落石：仍用苔石投掷物（石头本体通用），冷色尘烟
	"skill_stag_volley": {
		"family": "stag", "motif": "volley", "arc": 70.0, "lifetime": 0.44,
		"sparks": 16, "dust": 32, "smoke_count": 16, "shake": 3.0,
		"weapon": "none", "cast_glow": 0.8,
		"projectile_visual": "ape_boulder", "projectile_align": false,
		"projectile_scale": 0.82, "projectile_trail": "sand",
	},
	# ---------------- 刀客 ----------------
	"skill_blade_slash": {
		"motif": "slash", "arc": 132.0, "thickness": 0.22, "layers": 2,
		"sweep": 0.12, "sparks": 24, "dust": 10, "shake": 2.3,
		"weapon": "horizontal",
	},
	"skill_blade_heavy": {
		"motif": "slash", "arc": 64.0, "thickness": 0.30, "rotation": -90.0,
		"layers": 2, "sweep": 0.16, "sparks": 30, "dust": 24, "shake": 4.6,
		"weapon": "vertical",
	},
	"skill_blade_dash": {
		"motif": "dash", "arc": 142.0, "thickness": 0.24, "layers": 2,
		"sweep": 0.11, "sparks": 38, "dust": 28, "shake": 3.2,
		"weapon": "horizontal", "dash_streaks": 9,
	},
	"skill_blade_turn": {
		"motif": "spin", "arc": 232.0, "thickness": 0.22, "rotation": -105.0,
		"layers": 2, "sweep": 0.18, "sparks": 34, "dust": 22, "shake": 3.2,
		"weapon": "spin",
	},
	"skill_blade_scar": {
		"motif": "slash", "arc": 146.0, "thickness": 0.26, "layers": 2,
		"sweep": 0.15, "sparks": 32, "dust": 26, "smoke_count": 20,
		"shake": 3.8, "weapon": "horizontal",
	},
	"skill_blade_qi": {
		# 刀气追击：只去扇形刀光，保留挥刀 / 起手粒子 / 刀气投射物
		"motif": "qi", "no_slash": true,
		"arc": 92.0, "thickness": 0.18, "layers": 1,
		"sweep": 0.10, "sparks": 18, "dust": 8, "shake": 2.0,
		"weapon": "horizontal", "projectile_visual": "skill_blade_qi",
		"projectile_align": true, "projectile_trail": "ember",
		"projectile_color": Color(1.0, 0.88, 0.68),
	},
	"skill_blade_field": {
		"motif": "field", "arc": 360.0, "radius_mult": 1.25, "layers": 1,
		"sweep": 0.14, "sparks": 30, "dust": 40, "smoke_count": 36,
		"shake": 3.6, "weapon": "raise",
	},
	"skill_blade_counter": {
		"motif": "ward", "arc": 220.0, "thickness": 0.30, "layers": 2,
		"sweep": 0.16, "sparks": 46, "dust": 32, "smoke_count": 24,
		"shake": 5.2, "weapon": "horizontal", "ward": true,
	},
	"skill_blade_peak": {
		# 满势断岳：只去扇形刀光，保留举剑 / 地面裂痕 / 碎石 / 刀气投射物
		"motif": "peak", "no_slash": true,
		"arc": 92.0, "thickness": 0.34, "rotation": -90.0,
		"layers": 3, "sweep": 0.18, "sparks": 46, "dust": 48, "smoke_count": 36,
		"shake": 7.0, "weapon": "vertical",
		"projectile_visual": "skill_blade_qi", "projectile_align": true,
		"projectile_trail": "ember", "projectile_scale": 1.9,
		"projectile_color": Color(1.0, 0.95, 0.70),
	},
	# ---------------- 剑客 ----------------
	"skill_sword_stab": {
		"motif": "thrust", "arc": 0.0, "thickness": 0.22, "layers": 1,
		"sweep": 0.08, "sparks": 20, "dust": 6, "smoke_count": 10,
		"shake": 1.6, "weapon": "thrust",
	},
	"skill_sword_lift": {
		"motif": "slash", "arc": 106.0, "thickness": 0.22, "rotation": -55.0,
		"layers": 2, "sweep": 0.12, "sparks": 24, "dust": 8, "smoke_count": 20,
		"shake": 2.2, "weapon": "lift",
	},
	"skill_sword_chop": {
		"motif": "slash", "arc": 68.0, "thickness": 0.30, "rotation": -90.0,
		"layers": 2, "sweep": 0.16, "sparks": 30, "dust": 12, "smoke_count": 22,
		"shake": 4.2, "weapon": "vertical",
	},
	"skill_sword_cloud": {
		# 云：只去掉扇形刀光；起手聚能 / 挥剑 / 武器挥砍 / 弹体拖尾全部保留
		# （2026-10-25 用户修正：不要的是扇形刀光，不是挥剑）
		"motif": "cloud", "no_slash": true,
		"arc": 74.0, "thickness": 0.24, "layers": 1,
		"sweep": 0.10, "sparks": 18, "dust": 6, "smoke_count": 28,
		"shake": 1.8, "weapon": "horizontal",
		"projectile_visual": "skill_sword_light", "projectile_align": true,
		"projectile_trail": "mist",
	},
	"skill_sword_pierce": {
		"motif": "pierce", "arc": 0.0, "thickness": 0.20, "layers": 1,
		"sweep": 0.09, "sparks": 26, "dust": 14, "smoke_count": 20,
		"shake": 3.2, "weapon": "thrust", "dash_streaks": 10,
	},
	"skill_sword_myriad": {
		"motif": "summon", "arc": 360.0, "layers": 1,
		"sweep": 0.14, "sparks": 44, "dust": 14, "smoke_count": 26,
		"shake": 3.8, "weapon": "raise", "projectile_trail": "sword",
		"projectile_color": Color(0.78, 0.96, 1.0, 1.0),
	},
	"skill_sword_heaven": {
		"motif": "heaven", "layers": 1, "shake": 7.0,
		"weapon": "vertical", "cast_glow": 0.8,
	},
	"skill_sword_heaven_full": {
		"motif": "heaven", "layers": 1, "shake": 8.2,
		"weapon": "vertical", "cast_glow": 0.9,
	},
	# ---------------- 两仪真人 ----------------
	## 玩家侧八门（按 skill_id 取；BOSS 侧同四式另有 fx_ 前缀条目，见下）
	"skill_yinyang_palm": {
		"family": "yinyang", "motif": "slash", "arc": 150.0, "thickness": 0.24,
		"layers": 2, "sweep": 0.12, "sparks": 26, "dust": 12, "smoke_count": 16,
		"shake": 2.8, "weapon": "none", "cast_glow": 0.65,
		"bagua": true, "bagua_mult": 1.02, "sigil": "palm",
		"core": Color(1.0, 0.96, 0.82), "glow": Color(1.0, 0.72, 0.22),
		"spark": Color(1.0, 0.86, 0.44),
	},
	"skill_yinyang_finger": {
		"family": "yinyang", "motif": "thrust", "arc": 0.0, "thickness": 0.22,
		"layers": 1, "sweep": 0.08, "sparks": 20, "dust": 6, "smoke_count": 22,
		"shake": 2.0, "weapon": "none", "cast_glow": 0.7,
		"bagua": true, "bagua_mult": 0.5, "sigil": "beads",
		"core": Color(0.72, 1.0, 1.0), "glow": Color(0.12, 0.58, 0.64),
		"spark": Color(0.56, 0.96, 1.0),
	},
	"skill_yinyang_flip": {
		"family": "yinyang", "motif": "spin", "arc": 360.0, "thickness": 0.20,
		"layers": 1, "sweep": 0.20, "sparks": 22, "dust": 8, "smoke_count": 18,
		"shake": 1.6, "weapon": "none", "cast_glow": 0.8, "taiji": true,
		"bagua": true, "bagua_mult": 2.6, "bagua_spin": 2.6, "sigil": "taiji",
		"core": Color(1.0, 0.96, 0.82), "glow": Color(0.92, 0.72, 0.28),
		"spark": Color(0.72, 0.96, 1.0),
	},
	"skill_yinyang_collapse": {
		"family": "yinyang", "motif": "stomp", "arc": 360.0,
		"radius_mult": 1.0, "layers": 1, "sparks": 44, "dust": 36, "smoke_count": 40,
		"shake": 7.2, "weapon": "none", "cast_glow": 1.0, "taiji": true,
		"bagua": true, "bagua_mult": 1.05, "bagua_spin": -1.8,
		"core": Color(1.0, 1.0, 0.92), "glow": Color(0.92, 0.70, 0.24),
		"spark": Color(0.64, 0.96, 1.0),
	},
	"skill_yinyang_triple": {
		"family": "yinyang", "motif": "dash", "arc": 130.0, "thickness": 0.20,
		"layers": 1, "sweep": 0.10, "sparks": 22, "dust": 12, "smoke_count": 12,
		"shake": 2.4, "weapon": "none", "dash_streaks": 6, "cast_glow": 0.55,
		"bagua": true, "bagua_mult": 0.8, "sigil": "bars",
		"core": Color(1.0, 0.96, 0.80), "glow": Color(1.0, 0.70, 0.20),
		"spark": Color(1.0, 0.84, 0.40),
	},
	"skill_yinyang_wind": {
		# 每一跳重新起一次特效，所以 lifetime 只给一跳的间隔（0.45）多一点
		"family": "yinyang", "motif": "field", "arc": 360.0,
		"radius_mult": 1.0, "layers": 1, "lifetime": 0.55,
		"sweep": 0.12, "sparks": 16, "dust": 8, "smoke_count": 20,
		"shake": 1.4, "weapon": "none", "cast_glow": 0.6,
		"bagua": true, "bagua_mult": 0.85, "bagua_spin": -1.3,
		"core": Color(0.62, 0.96, 1.0), "glow": Color(0.08, 0.44, 0.50),
		"spark": Color(0.46, 0.90, 0.96),
	},
	"skill_yinyang_fish": {
		"family": "yinyang", "motif": "volley", "arc": 46.0, "layers": 1,
		"sweep": 0.09, "sparks": 14, "dust": 6, "smoke_count": 12,
		"shake": 1.8, "weapon": "none", "cast_glow": 0.7,
		"bagua": true, "bagua_mult": 0.5,
		"core": Color(1.0, 0.96, 0.82), "glow": Color(0.92, 0.72, 0.28),
		"spark": Color(0.60, 0.94, 1.0),
		"projectile_visual": "skill_tiger_orb", "projectile_align": false,
		"projectile_scale": 1.05,
		# ⚠ projectile_color / projectile_trail 这里不写：两枚弹一阳一阴，
		#   由 player._cast_yinyang_fish() 逐枚指定（阳=暖金余烬、阴=青雾）
	},
	"skill_yinyang_counter": {
		"family": "yinyang", "motif": "ward", "arc": 200.0, "thickness": 0.28,
		"layers": 1, "sweep": 0.14, "sparks": 26, "dust": 14, "smoke_count": 18,
		"shake": 3.6, "weapon": "none", "ward": true, "cast_glow": 0.75,
		"bagua": true, "bagua_mult": 0.85,
		"core": Color(1.0, 0.96, 0.82), "glow": Color(0.92, 0.72, 0.28),
		"spark": Color(0.64, 0.96, 1.0),
	},
	## BOSS 侧的另外四式：用 visual_id 当伪 skill_id 调 SkillFx.play。
	## ⚠ 这四式玩家也能学（skill_yinyang_triple/wind/fish/counter 在上面），
	##   两侧数值不同所以条目也分开写 —— BOSS 的范围更大、残影更多，玩家的精简一档。
	"fx_yinyang_triple": {
		"family": "yinyang", "motif": "dash", "arc": 142.0, "thickness": 0.22,
		"layers": 2, "sweep": 0.11, "sparks": 34, "dust": 20, "smoke_count": 16,
		"shake": 3.2, "weapon": "none", "dash_streaks": 9, "cast_glow": 0.6,
		"bagua": true, "bagua_mult": 0.9, "sigil": "bars",
		"core": Color(1.0, 0.96, 0.80), "glow": Color(1.0, 0.70, 0.20),
		"spark": Color(1.0, 0.84, 0.40),
	},
	"fx_yinyang_wind": {
		"family": "yinyang", "motif": "field", "arc": 360.0,
		"radius_mult": 1.0, "layers": 1, "lifetime": 1.4,
		"sweep": 0.14, "sparks": 26, "dust": 12, "smoke_count": 34,
		"shake": 2.2, "weapon": "none", "cast_glow": 0.7,
		"bagua": true, "bagua_mult": 0.95, "bagua_spin": -1.3,
		"field_pulses": 3, "field_pulse_gap": 0.45,
		"core": Color(0.62, 0.96, 1.0), "glow": Color(0.08, 0.44, 0.50),
		"spark": Color(0.46, 0.90, 0.96),
	},
	"fx_yinyang_fish": {
		"family": "yinyang", "motif": "volley", "arc": 60.0, "layers": 1,
		"sweep": 0.10, "sparks": 20, "dust": 8, "smoke_count": 18,
		"shake": 2.4, "weapon": "none", "cast_glow": 0.8,
		"bagua": true, "bagua_mult": 0.55,
		"core": Color(1.0, 0.96, 0.82), "glow": Color(0.92, 0.72, 0.28),
		"spark": Color(0.60, 0.94, 1.0),
	},
	"fx_yinyang_counter": {
		"family": "yinyang", "motif": "ward", "arc": 220.0, "thickness": 0.30,
		"layers": 2, "sweep": 0.16, "sparks": 40, "dust": 24, "smoke_count": 26,
		"shake": 4.8, "weapon": "none", "ward": true, "cast_glow": 0.8,
		"bagua": true, "bagua_mult": 0.95,
		"core": Color(1.0, 0.96, 0.82), "glow": Color(0.92, 0.72, 0.28),
		"spark": Color(0.64, 0.96, 1.0),
	},
	"fx_yinyang_counter_hit": {
		"family": "yinyang", "motif": "slash", "arc": 120.0, "thickness": 0.34,
		"layers": 3, "sweep": 0.16, "sparks": 52, "dust": 36, "smoke_count": 28,
		"shake": 6.8, "weapon": "none", "cast_glow": 0.9,
		"bagua": true, "bagua_mult": 1.1,
		"core": Color(1.0, 1.0, 0.90), "glow": Color(1.0, 0.76, 0.24),
		"spark": Color(0.60, 0.96, 1.0),
	},
	## 破盾 —— 之前每次护体崩碎都**没有任何特效**（条目根本不存在，
	## SkillFx 查不到就静默返回）。冲击波 + 裂纹 + 一道翻面的太极环。
	"fx_yinyang_shield_break": {
		"family": "yinyang", "motif": "stomp", "arc": 360.0,
		"layers": 1, "sparks": 64, "dust": 44, "smoke_count": 48,
		"shake": 9.5, "weapon": "none", "cast_glow": 0.9, "taiji": true,
		"bagua": true, "bagua_mult": 1.4, "bagua_spin": -2.2,
		"core": Color(1.0, 1.0, 0.94), "glow": Color(0.98, 0.78, 0.28),
		"spark": Color(0.62, 0.96, 1.0),
	},

	# ---------------- 赫连霄（赤霄界第 1 位，2026-10-29）----------------
	## 雷弧一族：统一用 skill_fx.gd 的 `thunder` motif（软边雷柱 + 雷印环 + 焦尘）。
	## 色板：雷紫 glow / 赤金 core / 焦黑 dust；与刀光的暖金、剑气的青白、
	## 兽爪的暗金赤煞、太极的金青、绞绳的朱砂、气云的青蓝全部分开。
	"skill_thunder_verdict": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "verdict",
		"thunder_ground": false,
		"core": Color(1.0, 0.90, 0.62), "glow": Color(0.74, 0.52, 1.0),
		"spark": Color(1.0, 0.80, 0.36),
		"lifetime": 0.55, "shake": 3.4, "sparks": 24, "dust": 10, "cast_glow": 0.7,
	},
	"skill_thunder_execute": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "execute",
		"thunder_ground": true,
		"core": Color(1.0, 0.94, 0.70), "glow": Color(0.70, 0.48, 1.0),
		"spark": Color(1.0, 0.82, 0.38),
		"lifetime": 0.60, "shake": 5.6, "sparks": 28, "dust": 18, "cast_glow": 0.8,
	},
	"skill_thunder_drum": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "drum",
		"thunder_ground": false,
		"core": Color(1.0, 0.88, 0.54), "glow": Color(0.78, 0.50, 1.0),
		"spark": Color(1.0, 0.84, 0.40),
		"lifetime": 0.55, "shake": 6.8, "sparks": 34, "dust": 26, "cast_glow": 0.9,
	},
	"skill_thunder_lock": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "lock",
		"thunder_ground": false,
		"core": Color(0.86, 0.96, 1.0), "glow": Color(0.64, 0.46, 1.0),
		"spark": Color(0.72, 0.90, 1.0),
		"lifetime": 0.45, "shake": 3.0, "sparks": 20, "dust": 8, "cast_glow": 0.7,
	},
	"skill_thunder_step": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "step",
		"thunder_ground": false,
		"core": Color(1.0, 0.94, 0.72), "glow": Color(0.72, 0.52, 1.0),
		"spark": Color(1.0, 0.82, 0.42),
		"lifetime": 0.42, "shake": 3.2, "sparks": 18, "dust": 10, "cast_glow": 0.6,
	},
	"skill_thunder_gather": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "gather",
		"thunder_ground": false,
		"core": Color(1.0, 0.96, 0.78), "glow": Color(0.66, 0.46, 1.0),
		"spark": Color(0.92, 0.82, 1.0),
		"lifetime": 1.40, "shake": 2.2, "sparks": 26, "dust": 14, "cast_glow": 0.9,
	},
	"skill_thunder_nine": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "nine",
		"thunder_ground": true,
		"core": Color(1.0, 0.94, 0.68), "glow": Color(0.68, 0.46, 1.0),
		"spark": Color(1.0, 0.80, 0.36),
		"lifetime": 0.65, "shake": 8.6, "sparks": 34, "dust": 22, "cast_glow": 1.0,
	},
	"skill_thunder_prison": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "prison",
		"thunder_ground": true,
		"core": Color(1.0, 0.92, 0.64), "glow": Color(0.72, 0.50, 1.0),
		"spark": Color(1.0, 0.82, 0.38),
		"lifetime": 1.50, "shake": 4.6, "sparks": 30, "dust": 18, "cast_glow": 0.8,
	},
	## 违律落雷：比定刑更小、更快，玩家能看出“这是判词在罚我”
	"fx_thunder_violation": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "execute",
		"thunder_ground": true,
		"core": Color(1.0, 0.90, 0.60), "glow": Color(0.82, 0.56, 1.0),
		"spark": Color(1.0, 0.80, 0.40),
		"lifetime": 0.40, "shake": 2.4, "sparks": 14, "dust": 8,
	},
	## 满雷势 · 平A协同雷击（玩家侧，2026-10-30）：更短更快，连击时不刷屏
	"fx_thunder_coop": {
		"family": "thunder", "motif": "thunder", "thunder_mode": "coop",
		"thunder_ground": true,
		"core": Color(1.0, 0.94, 0.72), "glow": Color(0.84, 0.62, 1.0),
		"spark": Color(1.0, 0.84, 0.44),
		"lifetime": 0.28, "shake": 1.2, "sparks": 9, "dust": 4,
	},
	## 满剑意 · 剑气随身（玩家侧肉鸽卡，2026-11-12）：平A在目标处补的第二道剑光。
	## 同 fx_thunder_coop 的口径 —— 附带型特效一律比正经剑招更短更薄，连击时不糊屏；
	## 冷青色调和「金」属性伤害对上，暖色的雷/日一眼分得开。weapon=none：不抢玩家挥剑。
	"fx_sword_qi_slash": {
		"family": "sword", "motif": "slash", "arc": 92.0, "thickness": 0.16,
		"rotation": -34.0, "layers": 1, "sweep": 0.09,
		"sparks": 10, "dust": 3, "smoke_count": 6,
		"lifetime": 0.22, "shake": 1.1, "weapon": "none",
		"core": Color(0.86, 0.98, 1.0), "glow": Color(0.42, 0.72, 0.98),
		"spark": Color(0.80, 0.96, 1.0),
	},

	# ---------------- 离照（赤霄界第 2 位，2026-10-29）----------------
	## 日轮一族：柔和金色日核 + 赤红日冕 + 逆飞余烬。
	## 形状全部是「圆 / 放射 / 弧」，不用雷柱、刀光、阵线、气环。
	"skill_sun_step": {
		"family": "sun", "motif": "sun", "sun_mode": "step",
		"core": Color(1.0, 0.96, 0.80), "glow": Color(1.0, 0.42, 0.12),
		"spark": Color(1.0, 0.78, 0.32),
		"lifetime": 0.50, "shake": 3.0, "sparks": 20, "dust": 10, "cast_glow": 0.65,
	},
	"skill_sun_slash": {
		"family": "sun", "motif": "sun", "sun_mode": "slash",
		"core": Color(1.0, 0.92, 0.66), "glow": Color(1.0, 0.38, 0.10),
		"spark": Color(1.0, 0.76, 0.28),
		"lifetime": 0.45, "shake": 3.4, "sparks": 26, "dust": 12, "cast_glow": 0.7,
	},
	"skill_sun_throw": {
		"family": "sun", "motif": "sun", "sun_mode": "throw",
		"core": Color(1.0, 0.98, 0.86), "glow": Color(1.0, 0.44, 0.10),
		"spark": Color(1.0, 0.82, 0.34),
		"lifetime": 0.60, "shake": 4.2, "sparks": 30, "dust": 14, "cast_glow": 0.8,
	},
	"skill_sun_pull": {
		"family": "sun", "motif": "sun", "sun_mode": "pull",
		"core": Color(1.0, 0.94, 0.72), "glow": Color(1.0, 0.52, 0.16),
		"spark": Color(1.0, 0.84, 0.40),
		"lifetime": 0.55, "shake": 2.0, "sparks": 18, "dust": 8, "cast_glow": 0.7,
	},
	"skill_sun_wind": {
		"family": "sun", "motif": "sun", "sun_mode": "wind",
		"core": Color(1.0, 0.88, 0.58), "glow": Color(0.96, 0.34, 0.10),
		"spark": Color(1.0, 0.66, 0.22),
		"lifetime": 0.55, "shake": 2.8, "sparks": 28, "dust": 22, "cast_glow": 0.65,
	},
	"skill_sun_eclipse": {
		"family": "sun", "motif": "sun", "sun_mode": "eclipse",
		"core": Color(1.0, 0.84, 0.40), "glow": Color(0.42, 0.06, 0.04),
		"spark": Color(1.0, 0.56, 0.16),
		"lifetime": 0.95, "shake": 7.0, "sparks": 38, "dust": 26, "cast_glow": 0.9,
	},
	"skill_sun_wheel": {
		"family": "sun", "motif": "sun", "sun_mode": "wheel",
		"core": Color(1.0, 0.94, 0.70), "glow": Color(1.0, 0.46, 0.12),
		"spark": Color(1.0, 0.80, 0.32),
		"lifetime": 4.5, "shake": 2.2, "sparks": 34, "dust": 12, "cast_glow": 0.8,
	},
	"skill_sun_meteor": {
		"family": "sun", "motif": "sun", "sun_mode": "meteor",
		"core": Color(1.0, 0.98, 0.86), "glow": Color(1.0, 0.34, 0.06),
		"spark": Color(1.0, 0.72, 0.24),
		"lifetime": 1.20, "shake": 8.4, "sparks": 44, "dust": 30, "cast_glow": 1.0,
	},

	# ---------------- 赤金火麟（赤金丹霞核心首领，2026-10-29）----------------
	## 复用「日轮」一族的表现（圆 / 放射 / 弧），配色往赤金偏：日核更白、日冕更金，
	## 与离照的赤红日冕区分开；形状按招式语义挑 mode。
	"skill_qilin_swipe": {
		"family": "sun", "motif": "sun", "sun_mode": "slash",
		"core": Color(1.0, 0.95, 0.76), "glow": Color(1.0, 0.50, 0.14),
		"spark": Color(1.0, 0.80, 0.34),
		"lifetime": 0.40, "shake": 2.6, "sparks": 18, "dust": 8, "cast_glow": 0.55,
	},
	"skill_qilin_gore": {
		"family": "sun", "motif": "sun", "sun_mode": "step",
		"core": Color(1.0, 0.94, 0.72), "glow": Color(1.0, 0.48, 0.12),
		"spark": Color(1.0, 0.76, 0.30),
		"lifetime": 0.55, "shake": 4.2, "sparks": 26, "dust": 16, "cast_glow": 0.7,
	},
	"skill_qilin_stomp": {
		"family": "sun", "motif": "sun", "sun_mode": "wind",
		"core": Color(1.0, 0.92, 0.66), "glow": Color(1.0, 0.46, 0.10),
		"spark": Color(1.0, 0.72, 0.26),
		"lifetime": 0.60, "shake": 6.0, "sparks": 34, "dust": 24, "cast_glow": 0.75,
	},
	"skill_qilin_rain": {
		"family": "sun", "motif": "sun", "sun_mode": "throw",
		"core": Color(1.0, 0.96, 0.80), "glow": Color(1.0, 0.52, 0.14),
		"spark": Color(1.0, 0.80, 0.32),
		"lifetime": 0.45, "shake": 2.2, "sparks": 16, "dust": 10, "cast_glow": 0.6,
	},
	"skill_qilin_orb": {
		"family": "sun", "motif": "sun", "sun_mode": "throw",
		"core": Color(1.0, 0.98, 0.86), "glow": Color(1.0, 0.55, 0.16),
		"spark": Color(1.0, 0.84, 0.36),
		"lifetime": 0.60, "shake": 4.6, "sparks": 30, "dust": 14, "cast_glow": 0.8,
	},
	"skill_qilin_claw": {
		"family": "sun", "motif": "sun", "sun_mode": "slash",
		"core": Color(1.0, 0.93, 0.70), "glow": Color(1.0, 0.44, 0.10),
		"spark": Color(1.0, 0.74, 0.28),
		"lifetime": 0.34, "shake": 3.0, "sparks": 16, "dust": 6, "cast_glow": 0.6,
	},
	"skill_qilin_ring": {
		"family": "sun", "motif": "sun", "sun_mode": "wind",
		"core": Color(1.0, 0.94, 0.72), "glow": Color(1.0, 0.50, 0.12),
		"spark": Color(1.0, 0.78, 0.30),
		"lifetime": 0.65, "shake": 4.0, "sparks": 30, "dust": 18, "cast_glow": 0.8,
	},
	"skill_qilin_eclipse": {
		"family": "sun", "motif": "sun", "sun_mode": "eclipse",
		"core": Color(1.0, 0.86, 0.42), "glow": Color(0.46, 0.08, 0.04),
		"spark": Color(1.0, 0.60, 0.18),
		"lifetime": 0.95, "shake": 7.0, "sparks": 40, "dust": 26, "cast_glow": 1.0,
	},
	"skill_qilin_meteor": {
		"family": "sun", "motif": "sun", "sun_mode": "meteor",
		"core": Color(1.0, 0.98, 0.86), "glow": Color(1.0, 0.38, 0.06),
		"spark": Color(1.0, 0.70, 0.22),
		"lifetime": 1.20, "shake": 9.0, "sparks": 48, "dust": 32, "cast_glow": 1.0,
	},
	"skill_qilin_brand": {
		"family": "sun", "motif": "sun", "sun_mode": "throw",
		"core": Color(1.0, 0.98, 0.88), "glow": Color(1.0, 0.58, 0.18),
		"spark": Color(1.0, 0.86, 0.40),
		"lifetime": 0.50, "shake": 5.0, "sparks": 24, "dust": 8, "cast_glow": 0.9,
	},

	# ---------------- 晏无咎（赤霄界第 3 位，2026-10-29）----------------
	## 三灾一族：碎环 + 灾印 + 灰烬，不用雷弧 / 日核 / 阵线 / 刀光。
	"skill_calamity_step": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "step",
		"core": Color(0.86, 0.97, 0.92), "glow": Color(0.40, 0.72, 0.66),
		"spark": Color(0.72, 0.94, 0.86),
		"lifetime": 0.48, "shake": 2.8, "sparks": 20, "dust": 12, "cast_glow": 0.6,
	},
	"skill_calamity_slash": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "slash",
		"core": Color(0.90, 0.98, 0.94), "glow": Color(0.34, 0.66, 0.62),
		"spark": Color(0.68, 0.94, 0.84),
		"lifetime": 0.42, "shake": 3.0, "sparks": 24, "dust": 10, "cast_glow": 0.65,
	},
	"skill_calamity_fire_seal": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "fire_seal",
		"core": Color(1.0, 0.92, 0.70), "glow": Color(0.96, 0.36, 0.10),
		"spark": Color(1.0, 0.70, 0.24),
		"lifetime": 0.60, "shake": 3.6, "sparks": 26, "dust": 18, "cast_glow": 0.75,
	},
	"skill_calamity_fire_field": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "fire_field",
		"core": Color(1.0, 0.86, 0.58), "glow": Color(0.92, 0.30, 0.08),
		"spark": Color(1.0, 0.64, 0.20),
		"lifetime": 4.5, "shake": 2.2, "sparks": 30, "dust": 16, "cast_glow": 0.8,
	},
	"skill_calamity_thunder_strike": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "thunder_strike",
		"core": Color(0.96, 0.94, 1.0), "glow": Color(0.62, 0.52, 1.0),
		"spark": Color(0.88, 0.82, 1.0),
		"lifetime": 0.55, "shake": 4.8, "sparks": 26, "dust": 10, "cast_glow": 0.8,
	},
	"skill_calamity_thunder_pool": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "thunder_pool",
		"core": Color(0.92, 0.90, 1.0), "glow": Color(0.52, 0.44, 0.94),
		"spark": Color(0.84, 0.78, 1.0),
		"lifetime": 4.0, "shake": 2.4, "sparks": 28, "dust": 10, "cast_glow": 0.7,
	},
	"skill_calamity_turn": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "turn",
		"core": Color(0.94, 0.92, 0.86), "glow": Color(0.66, 0.58, 0.80),
		"spark": Color(0.92, 0.80, 0.54),
		"lifetime": 0.70, "shake": 2.2, "sparks": 24, "dust": 18, "cast_glow": 0.8,
	},
	"skill_calamity_final": {
		"family": "calamity", "motif": "calamity", "calamity_mode": "final",
		"core": Color(1.0, 0.96, 0.88), "glow": Color(0.78, 0.58, 0.90),
		"spark": Color(1.0, 0.72, 0.36),
		"lifetime": 1.35, "shake": 9.0, "sparks": 48, "dust": 34, "cast_glow": 1.0,
	},

	# ---------------- 符箓局内特效（2026-10-31）----------------
	## 符卡飞出后落在目标点；这里只负责落点元素层，卡面飞行在 TalismanFx。
	"talisman_jinfeng": {
		"motif": "slash", "arc": 72.0, "thickness": 0.20, "layers": 3,
		"sweep": 0.08, "lifetime": 0.36, "sparks": 40, "dust": 4, "smoke_count": 8,
		"shake": 3.0, "weapon": "none", "cast_glow": 0.0, "noise_amount": 0.35,
		"core": Color(1.0, 0.96, 0.76), "glow": Color(0.92, 0.68, 0.22),
		"spark": Color(1.0, 0.86, 0.42),
	},
	"talisman_huoqiu": {
		"motif": "orb", "lifetime": 0.42, "sparks": 38, "dust": 16, "smoke_count": 26,
		"shake": 3.6, "weapon": "none", "cast_glow": 0.0,
		"core": Color(1.0, 0.78, 0.36), "glow": Color(0.98, 0.30, 0.08),
		"spark": Color(1.0, 0.58, 0.16),
	},
	"talisman_yinlei": {
		"motif": "thunder", "thunder_mode": "execute", "thunder_ground": true,
		"lifetime": 0.50, "shake": 4.4, "sparks": 26, "dust": 14, "cast_glow": 0.0,
		"weapon": "none",
		"core": Color(0.92, 0.96, 1.0), "glow": Color(0.60, 0.50, 1.0),
		"spark": Color(0.86, 0.92, 1.0),
	},
	"talisman_muling": {
		"motif": "qi_cloud", "qi_mode": "lock", "layers": 2, "thickness": 0.24,
		"lifetime": 0.60, "shake": 2.0, "sparks": 18, "dust": 10, "smoke_count": 16,
		"weapon": "none", "cast_glow": 0.0,
		"core": Color(0.72, 0.96, 0.62), "glow": Color(0.26, 0.66, 0.32),
		"spark": Color(0.60, 0.94, 0.48),
	},
	"talisman_shuihui": {
		"motif": "qi_cloud", "qi_mode": "breath", "field_pulses": 3,
		"field_pulse_gap": 0.22, "lifetime": 0.90, "shake": 0.0,
		"weapon": "none", "cast_glow": 0.0,
		"core": Color(0.72, 0.94, 1.0), "glow": Color(0.16, 0.50, 0.82),
		"spark": Color(0.48, 0.86, 1.0),
	},
	"talisman_fengji": {
		"motif": "qi_cloud", "qi_mode": "gather", "field_pulses": 2,
		"field_pulse_gap": 0.16, "lifetime": 0.70, "shake": 0.0,
		"weapon": "none", "cast_glow": 0.0,
		"core": Color(0.78, 1.0, 0.88), "glow": Color(0.28, 0.72, 0.62),
		"spark": Color(0.62, 0.98, 0.82),
	},
	"talisman_tushi": {
		"motif": "stomp", "lifetime": 0.50, "sparks": 24, "dust": 38,
		"smoke_count": 24, "shake": 4.6, "weapon": "none", "cast_glow": 0.0,
		"core": Color(0.88, 0.78, 0.58), "glow": Color(0.44, 0.34, 0.20),
		"spark": Color(0.78, 0.62, 0.38), "crack_tint": Color(0.78, 0.62, 0.40),
		"ring": Color(0.82, 0.64, 0.38),
	},

	# ---------------- 观澜（照影界第 1 位，2026-11-01）----------------
	## 镜水一族：薄银镜面 + 冷蓝水光 + 碎镜棱，不用刀光 / 雷弧 / 日核 / 云烟。
	## 每一式的水镜形状不同：弧、刺、立镜、碎镜、换位、镜返、水环、万镜。
	"skill_mirror_slash": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "slash",
		"core": Color(0.92, 0.99, 1.0), "glow": Color(0.26, 0.58, 0.84),
		"spark": Color(0.72, 0.94, 1.0),
		"layers": 2, "thickness": 0.12, "sweep": 0.10,
		"lifetime": 0.42, "shake": 3.2, "sparks": 22, "dust": 4, "cast_glow": 0.6,
	},
	"skill_mirror_thrust": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "thrust",
		"core": Color(0.95, 0.99, 1.0), "glow": Color(0.24, 0.54, 0.82),
		"spark": Color(0.74, 0.96, 1.0),
		"lifetime": 0.38, "shake": 3.6, "sparks": 20, "dust": 3, "cast_glow": 0.65,
	},
	"skill_mirror_bloom": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "bloom",
		"core": Color(0.90, 0.98, 1.0), "glow": Color(0.30, 0.62, 0.88),
		"spark": Color(0.78, 0.96, 1.0),
		"lifetime": 0.70, "shake": 1.8, "sparks": 18, "dust": 0, "cast_glow": 0.8,
	},
	"skill_mirror_shatter": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "shatter", "mirror_ground": true,
		"core": Color(0.94, 0.99, 1.0), "glow": Color(0.28, 0.60, 0.88),
		"spark": Color(0.78, 0.97, 1.0),
		"lifetime": 0.55, "shake": 5.4, "sparks": 40, "dust": 6, "cast_glow": 0.0,
	},
	"skill_mirror_swap": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "swap",
		"core": Color(0.92, 0.98, 1.0), "glow": Color(0.32, 0.64, 0.90),
		"spark": Color(0.80, 0.97, 1.0),
		"lifetime": 0.55, "shake": 1.2, "sparks": 16, "dust": 0, "cast_glow": 0.0,
	},
	"skill_mirror_return": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "return",
		"core": Color(0.96, 1.0, 1.0), "glow": Color(0.30, 0.62, 0.88),
		"spark": Color(0.82, 0.98, 1.0),
		"lifetime": 0.48, "shake": 2.6, "sparks": 18, "dust": 0, "cast_glow": 0.0,
	},
	"skill_mirror_ring": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "ring", "mirror_ground": true,
		"core": Color(0.90, 0.98, 1.0), "glow": Color(0.24, 0.56, 0.84),
		"spark": Color(0.70, 0.94, 1.0),
		"lifetime": 0.85, "shake": 1.6, "sparks": 20, "dust": 0, "cast_glow": 0.0,
	},
	"skill_mirror_myriad": {
		"family": "mirror", "motif": "mirror", "mirror_mode": "myriad",
		"core": Color(0.95, 0.99, 1.0), "glow": Color(0.28, 0.58, 0.88),
		"spark": Color(0.78, 0.97, 1.0),
		"layers": 3, "thickness": 0.14, "sweep": 0.08,
		"lifetime": 0.65, "shake": 7.2, "sparks": 36, "dust": 8, "cast_glow": 1.0,
	},

	# ---------------- 执烛（照影界第 2 位，2026-11-02）----------------
	## 影族：墨黑柔边带 + 影尖一枚冷银亮点 + 灯焰明暗。
	## 与观澜的镜水一族刻意相反 —— 观澜亮在镜片（加色银白 + 碎棱），
	## 执烛亮在暗部（普通混合的墨黑，只有影尖/残焰漏一点冷光）。
	## 不用刀光月牙、不用云烟、不用雷弧、不用日核。
	"skill_shadow_cut": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "cut", "weapon": "none",
		"ink": Color(0.03, 0.04, 0.07), "core": Color(0.80, 0.92, 1.0),
		"glow": Color(0.22, 0.34, 0.56), "hot": Color(0.78, 0.92, 1.0),
		"lifetime": 0.40, "shake": 3.4, "sparks": 16, "dust": 3, "cast_glow": 0.55,
	},
	"skill_shadow_reach": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "reach", "weapon": "none",
		"ink": Color(0.02, 0.03, 0.06), "core": Color(0.84, 0.94, 1.0),
		"glow": Color(0.20, 0.30, 0.52), "hot": Color(0.86, 0.96, 1.0),
		"lifetime": 0.46, "shake": 4.4, "sparks": 20, "dust": 4, "cast_glow": 0.7,
	},
	"skill_shadow_bind": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "bind", "weapon": "none",
		"ink": Color(0.05, 0.04, 0.10), "core": Color(0.72, 0.78, 0.98),
		"glow": Color(0.24, 0.26, 0.48), "hot": Color(0.70, 0.74, 0.96),
		"lifetime": 0.55, "shake": 2.2, "sparks": 12, "dust": 2, "cast_glow": 0.4,
	},
	"skill_shadow_step": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "step", "weapon": "none",
		"ink": Color(0.03, 0.04, 0.08), "core": Color(0.78, 0.90, 1.0),
		"glow": Color(0.22, 0.32, 0.54), "hot": Color(0.74, 0.88, 1.0),
		"dash_streaks": 7, "lifetime": 0.38, "shake": 3.0, "sparks": 14, "dust": 6,
		"cast_glow": 0.35,
	},
	"skill_shadow_dim": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "dim", "weapon": "none",
		"ink": Color(0.02, 0.02, 0.05), "core": Color(0.98, 0.86, 0.58),
		"glow": Color(0.30, 0.28, 0.36), "hot": Color(0.98, 0.86, 0.58),
		"lifetime": 0.70, "shake": 1.0, "sparks": 8, "dust": 0, "cast_glow": 0.2,
	},
	"skill_shadow_beam": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "beam", "weapon": "none",
		"ink": Color(0.04, 0.06, 0.10), "core": Color(0.88, 0.97, 1.0),
		"glow": Color(0.26, 0.52, 0.80), "hot": Color(0.92, 0.98, 1.0),
		"lifetime": 0.44, "shake": 3.8, "sparks": 18, "dust": 0, "cast_glow": 0.8,
	},
	"skill_shadow_split": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "split", "weapon": "none",
		"ink": Color(0.03, 0.03, 0.08), "core": Color(0.74, 0.82, 1.0),
		"glow": Color(0.20, 0.24, 0.46), "hot": Color(0.76, 0.84, 1.0),
		"lifetime": 0.62, "shake": 4.8, "sparks": 24, "dust": 8, "cast_glow": 0.6,
	},
	"skill_shadow_longnight": {
		"family": "shadow", "motif": "shadow", "shadow_mode": "longnight", "weapon": "none",
		"ink": Color(0.02, 0.02, 0.06), "core": Color(0.86, 0.94, 1.0),
		"glow": Color(0.18, 0.24, 0.46), "hot": Color(0.90, 0.96, 1.0),
		"lifetime": 0.86, "shake": 9.0, "sparks": 40, "dust": 12, "cast_glow": 1.0,
	},
	# ---------------- 叠纸 · 折族（2026-11-02）----------------
	## 同位面第三位。这一族的语言是**纸的硬折吃光成棱 + 一片片翻面的白纸**：
	## 观澜亮在镜片、执烛亮在暗部，叠纸亮在**棱线**（月白加色芯 + 迅速羽化），
	## 并在落点旁留一道墨影说明「这一下是折过来的」。
	## 不用墨带（那是影族）、不用银白碎棱（那是镜族）、不用雷弧 / 日核 / 云烟。
	"skill_fold_press": {
		"family": "fold", "motif": "fold", "fold_mode": "press", "weapon": "none",
		"paper": Color(0.90, 0.93, 0.98), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.62, 0.70, 0.86), "lifetime": 0.40,
		"shake": 3.2, "sparks": 14, "dust": 4, "cast_glow": 0.5,
	},
	"skill_fold_trace": {
		"family": "fold", "motif": "fold", "fold_mode": "trace", "weapon": "none",
		"paper": Color(0.90, 0.93, 0.98), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.62, 0.70, 0.86), "dash_streaks": 6, "lifetime": 0.38,
		"shake": 3.0, "sparks": 16, "dust": 6, "cast_glow": 0.35,
	},
	"skill_fold_stride": {
		"family": "fold", "motif": "fold", "fold_mode": "stride", "weapon": "none",
		"paper": Color(0.92, 0.90, 0.80), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.70, 0.66, 0.50), "lifetime": 0.44,
		"shake": 4.0, "sparks": 18, "dust": 5, "cast_glow": 0.6,
	},
	"skill_fold_seam": {
		"family": "fold", "motif": "fold", "fold_mode": "pressmark", "weapon": "none",
		"paper": Color(0.90, 0.93, 0.98), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.60, 0.68, 0.84), "lifetime": 0.52,
		"shake": 2.2, "sparks": 12, "dust": 8, "cast_glow": 0.75,
	},
	"skill_fold_shroud": {
		"family": "fold", "motif": "fold", "fold_mode": "shroud", "weapon": "none",
		"paper": Color(0.94, 0.94, 0.92), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.66, 0.72, 0.80), "lifetime": 0.62,
		"shake": 1.2, "sparks": 8, "dust": 6, "cast_glow": 0.45,
	},
	"skill_fold_tear": {
		"family": "fold", "motif": "fold", "fold_mode": "tear", "weapon": "none",
		"paper": Color(0.96, 0.93, 0.82), "hot": Color(1.0, 0.98, 0.86),
		"glow": Color(0.78, 0.74, 0.52), "lifetime": 0.50,
		"shake": 5.6, "sparks": 26, "dust": 10, "cast_glow": 0.8,
	},
	"skill_fold_twin": {
		"family": "fold", "motif": "fold", "fold_mode": "twin", "weapon": "none",
		"paper": Color(0.90, 0.93, 0.98), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.62, 0.70, 0.86), "lifetime": 0.46,
		"shake": 3.6, "sparks": 18, "dust": 6, "cast_glow": 0.7,
	},
	"skill_fold_triple": {
		"family": "fold", "motif": "fold", "fold_mode": "triple", "weapon": "none",
		"paper": Color(0.96, 0.89, 0.70), "hot": Color(1.0, 1.0, 0.94),
		"glow": Color(0.74, 0.66, 0.44), "lifetime": 0.80,
		"shake": 8.4, "sparks": 36, "dust": 12, "cast_glow": 1.0,
	},
	"skill_fold_measure": {
		"family": "fold", "motif": "fold", "fold_mode": "stride", "weapon": "none",
		"paper": Color(0.90, 0.93, 0.98), "hot": Color(1.0, 1.0, 1.0),
		"glow": Color(0.62, 0.70, 0.86), "lifetime": 0.36,
		"shake": 2.0, "sparks": 10, "dust": 3, "cast_glow": 0.4,
	},
}

## 技能表现用到的程序化贴图（可替换为正式美术，路径只在这里维护）
const SKILL_TEXTURES: Dictionary = {
	"field": "res://assets/effects/skills/skill_field.png",
	"blade_qi": "res://assets/effects/skills/blade_qi.png",
	"sword_light": "res://assets/effects/skills/sword_light.png",
	"ward": "res://assets/effects/skills/skill_ward.png",
	"stomp_crack": "res://assets/effects/skills/heaven_crack_fan.png",
	## 古猿砸地裂纹：透明底放射裂痕（虎妖那张带一整块灰雾，染绿会糊成绿云）
	"ape_crack": "res://assets/effects/skills/ape_crack.png",
	"heaven_charge": "res://assets/effects/skills/heaven_charge.png",
	"heaven_trail": "res://assets/effects/skills/heaven_trail.png",
	"heaven_crack_rect": "res://assets/effects/skills/heaven_crack_rect.png",
	"heaven_crack_fan": "res://assets/effects/skills/heaven_crack_fan.png",
	## 两仪一族的专属贴图（2026-10-28 重做：让八式一眼能认出、且与别家 BOSS 质感区分开）
	## 生成脚本 tools/gen_liangyi_fx.py，正式美术同名覆盖即可
	"bagua": "res://assets/effects/skills/liangyi_bagua.png",
	"qi_ring": "res://assets/effects/skills/qi_ring.png",
	"thunder_seal": "res://assets/effects/skills/chixiao_seal.png",
	"sun_seal": "res://assets/effects/skills/lizhao_sun_seal.png",
	"sun_orb": "res://assets/effects/skills/lizhao_sun_orb.png",
	"calamity_wheel": "res://assets/effects/skills/calamity_wheel.png",
	"qi_cloud_thick": "res://assets/effects/skills/qi_cloud_thick.png",
	"qi_cloud_wisp": "res://assets/effects/skills/qi_cloud_wisp.png",
	"taiji": "res://assets/effects/skills/liangyi_taiji.png",
	"palm_seal": "res://assets/effects/skills/liangyi_palm_seal.png",
	"bar": "res://assets/effects/skills/liangyi_bar.png",
	## 影族三件（执烛，2026-11-02 外部生图）：墨迹是这一族的主体语言，
	## 之前借用通用柔边椭圆，和好几个家族共用同一原语 —— 现在换成真笔触。
	"ink_stroke": "res://assets/effects/skills/ink_stroke_long.png",
	"ink_blob": "res://assets/effects/skills/ink_blob.png",
	"lamp_flame": "res://assets/effects/skills/lamp_flame_tip.png",
	"lamp_post": "res://assets/effects/skills/lamp_post.png",
	"lamp_pool": "res://assets/effects/skills/lamp_pool.png",
	## 折族（叠纸，2026-11-03 外部生图）。同批还给了折棱与圆牌两张，实测**没有采用**：
	## tools/ab_fold_fx_textures.py 按实机显示尺寸对量 —— 生图折棱羽化总厚只有 11px（程序化 42px）
	## 且 RGB 中位 146，叠在平均 77 的地面上芯亮度反而**低于**地面（78 vs 82）；
	## 生图圆牌是个空心环（牌心 alpha 0.02），代码画的编号点会飘在裸地面上。
	## 结论：这两件继续用程序化贴图，理由写回 skill_fx.gd 的原地。
	"fold_sheet": "res://assets/effects/skills/fold_sheet.png",
}


## 取某门功法的表现配置：先读族默认，再用功法条目覆盖
## 没有登记 = 空字典（调用方回退到旧的 form visual）
## 族按 skill_id 前缀推导：skill_tiger_ / skill_blade_ / skill_sword_
static func get_skill_fx(skill_id: String) -> Dictionary:
	var entry: Dictionary = SKILL_FX.get(skill_id, {})
	if entry.is_empty():
		return {}
	var family := String(entry.get("family", ""))
	if family == "":
		if skill_id.begins_with("skill_tiger_"):
			family = "tiger"
		elif skill_id.begins_with("skill_blade_"):
			family = "blade"
		elif skill_id.begins_with("skill_sword_"):
			family = "sword"
	var out: Dictionary = {}
	if SKILL_FAMILIES.has(family):
		out = (SKILL_FAMILIES[family] as Dictionary).duplicate(true)
	out["family"] = family
	for k in entry.keys():
		out[k] = entry[k]
	return out


## 取某特效的配置（未登记返回默认条目）
## 与 get_visual 一致：返回**副本**，调用方可安全修改
func get_effect(effect_id: String) -> Dictionary:
	var entry: Dictionary = EFFECTS.get(effect_id, {})
	var merged := DEFAULT_EFFECT.duplicate(true)
	for k in entry.keys():
		merged[k] = entry[k]
	return merged


## 该特效是否已接入真实贴图（用于 UI 提示 / 调试）
func effect_has_texture(effect_id: String) -> bool:
	var entry := get_effect(effect_id)
	return String(entry.get("texture", "")) != ""


## ===== 光环（AURAS）：常驻循环的发光装饰，与 EFFECTS 的区别是「不自动销毁、由调用方控制显隐」 =====
## 用途示例：战斗 HUD 技能栏里「剑意已满且冷却转好」时绕技能图标的旋转剑气环
## 外观全部由本表驱动（旋转速度 / 弧段数 / 颜色 / 粗细 / 半径 / 呼吸幅度）—— 换美术只改表
## ===== 阵旗三色（2026-10-28）=====
## 0=攻(朱砂) 1=困(墨) 2=守(石青)；玩家旗统一金面，靠杆顶饰区分类型。
## 三面 BOSS 旗共用同一张底图派生的布面色，杆、金线、投影完全一致。
const ARRAY_FLAG_KIND_NAMES := ["攻", "困", "守"]
const ARRAY_FLAG_KIND_COLORS: Dictionary = {
	0: Color(0.86, 0.34, 0.26, 1.0),
	1: Color(0.34, 0.35, 0.40, 1.0),
	2: Color(0.38, 0.70, 0.74, 1.0),
}
const ARRAY_FLAG_TEXTURES: Dictionary = {
	0: "res://assets/effects/skills/array_flag_red.png",
	1: "res://assets/effects/skills/array_flag_ink.png",
	2: "res://assets/effects/skills/array_flag_blue.png",
}
const ARRAY_FLAG_PLAYER_TEXTURE := "res://assets/effects/skills/array_flag_gold.png"
const ARRAY_FLAG_ORNAMENTS: Dictionary = {
	0: "res://assets/effects/skills/flag_top_spear.png",
	1: "res://assets/effects/skills/flag_top_ring.png",
	2: "res://assets/effects/skills/flag_top_jade.png",
}
const ARRAY_FLAG_WARN_TEX := "res://assets/effects/skills/flag_warn_ring.png"

## 太虚气君：气环贴图（BOSS 身周 3 枚 + 化劲气罩 + 各种气环）
const QI_RING_TEX := "res://assets/effects/skills/qi_ring.png"
## 赫连霄：判词挂在目标头顶的雷印（玩家 / BOSS 两侧共用）
const THUNDER_LAW_SEAL_TEX := "res://assets/effects/skills/thunder_law_seal.png"
const ARRAY_FLAG_BIND_TEX := "res://assets/effects/skills/flag_bind_ring.png"
const ARRAY_FLAG_GUARD_TEX := "res://assets/effects/skills/flag_guard_ring.png"

static func array_flag_texture(kind: int, player_owned: bool) -> String:
	if player_owned:
		return ARRAY_FLAG_PLAYER_TEXTURE
	return String(ARRAY_FLAG_TEXTURES.get(kind, ARRAY_FLAG_TEXTURES[0]))


const AURAS: Dictionary = {

	"fx_skill_intent_ready": {
		## 主色（剑气弧）与芯色（内侧描边）
		"color": Color(0.55, 0.90, 1.00, 0.90),
		"core_color": Color(1.0, 1.0, 1.0, 0.80),
		## 光环半径（像素，绕图标中心）
		"radius": 30.0,
		## 弧段数量与单段张角（度）
		"arc_count": 3,
		"arc_sweep_deg": 70.0,
		## 线宽（像素）
		"thickness": 2.5,
		## 旋转速度（度/秒，正值顺时针）
		"spin_deg": 240.0,
		## 呼吸幅度（0~1，乘在半径上）与频率
		"pulse_amp": 0.10,
		"pulse_speed": 6.0,
	},
}

## 默认光环条目（id 未登记时使用）
const DEFAULT_AURA: Dictionary = {
	"color": Color(1.0, 1.0, 1.0, 0.8),
	"core_color": Color(1.0, 1.0, 1.0, 0.6),
	"radius": 30.0,
	"arc_count": 3,
	"arc_sweep_deg": 70.0,
	"thickness": 2.5,
	"spin_deg": 240.0,
	"pulse_amp": 0.10,
	"pulse_speed": 6.0,
}


## 取某个光环的配置（未登记返回默认条目；返回副本，调用方可安全修改）
func get_aura(aura_id: String) -> Dictionary:
	var entry: Dictionary = AURAS.get(aura_id, {})
	var merged := DEFAULT_AURA.duplicate(true)
	for k in entry.keys():
		merged[k] = entry[k]
	return merged


## ===== 满剑意「一剑开天」巨剑演出（2026-10-27 用户定稿）=====
## 程序化金黄半透明巨剑 + 蓄力期镜头拉远/压暗暗角 + 落地强震屏。
## 巨剑只在 form_sword_heaven_full（fx_giant_sword=true）出现；现有四段特效不动。
## 换算路径：sword_size 是巨剑的世界像素尺寸（剑尖在贴图底边，落点对齐施法者脚下）。
const HEAVEN_CINEMATIC: Dictionary = {
	"sword_size": Vector2(200.0, 860.0),
	"sword_alpha": 0.78,
	## 巨剑落地后停留多久再开始渐隐（让它压在残留扇面上，姿势读得出来）
	"sword_hold_after_land": 0.12,
	## 剑柄轴心（相对施法者脚底）：巨剑以这里为轴，从竖直向上劈下去
	"hilt_offset": Vector2(0.0, -100.0),
	## 劈落弧线：从竖直向上（0°）顺时针扫过的角度；负朝向自动镜像
	"swing_deg": 130.0,
	## 扇形弧光：尾迹角度 / 内外半径 / 亮度 / 落地后消散时长
	## inner 越小，扇面越宽（0.12 = 从剑柄附近一直铺到剑尖，巨剑落地后整把剑压在扇面上）
	"arc_tail_deg": 66.0,
	"arc_inner": 0.12,
	"arc_alpha": 0.34,
	## 落地后扇面先保持一拍（压在剑下），再慢慢散；时间覆盖巨剑的停留 + 渐隐
	"arc_hold_after_land": 0.15,
	"arc_fade": 0.40,
	## 地面劈痕上的流动能量层（叠在贴图上，不改变判定尺寸）
	"crack_energy_strength": 0.40,
	"sword_fade_in": 0.45,
	"sword_fade_out": 0.45,
	## 镜头拉远：zoom 1.0 → zoom_out；前摇内拉出去，落地稍等再缓回。
	## 0.50 是按「落地那一帧能看见整把巨剑（含剑格）」反推的，别只按手感调小
	"zoom_out": 0.50,
	"zoom_in_time": 0.45,
	"zoom_back_time": 0.55,
	"zoom_hold_after_land": 0.12,
	## 蓄力压暗暗角（0~1 强度）
	"vignette_strength": 0.85,
	"vignette_in_time": 0.55,
	"vignette_out_time": 0.45,
	## 落地震屏（BOSS 侧也要震到玩家相机）
	"shake": 9.5,
	"shake_time": 0.36,
}

## 取巨剑演出参数（返回副本，调用方可安全修改）
func heaven_cinematic() -> Dictionary:
	return HEAVEN_CINEMATIC.duplicate(true)


## ===== 掉落物外观（PICKUP_BEAM）：常驻的地面光柱 + 名称/提示标签 =====
## 与 EFFECTS 的区别：这是**常驻**表现（掉落物在场上就一直在），不自动销毁。
## 换美术 / 调感观只改本表，item_pickup.gd 不含任何写死的尺寸与颜色。
const PICKUP_BEAM: Dictionary = {
	## 品质光柱（2026-10-27 改版）：高斯软边圆柱光，颜色按物品品阶/稀有度取；不再用半透明矩形
	"beam_size": Vector2(96.0, 232.0),
	"beam_offset": Vector2(-48.0, -232.0),
	"beam_strength": 0.72,
	## 地面光晕（径向渐变 + 加法混合），尺寸按 64px 贴图缩放
	"glow_size": Vector2(150.0, 50.0),
	"glow_position": Vector2(0.0, -6.0),
	"glow_alpha": 0.40,
	## 物品落地阴影（普通混合的黑色径向渐变），让物品「贴地」而不是浮在光里
	"shadow_size": Vector2(72.0, 24.0),
	"shadow_position": Vector2(0.0, -4.0),
	"shadow_alpha": 0.38,
	## 紧贴物品的接触阴影，比大光晕更实，进一步压出「贴地」感
	"contact_shadow_size": Vector2(46.0, 16.0),
	"contact_shadow_position": Vector2(0.0, -2.0),
	"contact_shadow_alpha": 0.42,
	## 躺地厚度：在物品下方叠几层同形暗色（模拟侧面），层距按世界 Y 压扁前的像素
	"thickness_layers": 2,
	"thickness_step": 2.6,
	## 没有品阶/稀有度时的光柱颜色（金黄）
	"fallback_color": Color(0.98, 0.84, 0.45, 1.0),
	## 图标统一缩放到「最长边 62px」（地面上不需要原图分辨率，也不能大小不一）
	"icon_longest": 62.0,
	## 躺地表现：倾斜角 + 世界 Y 方向压扁，模拟物品倒在地上
	"ground_tilt_deg": 10.0,
	"ground_tilt_weapon_deg": 38.0,
	"ground_squash": 0.60,
	## 落地姿势高度 + 掉落入场（开始高度 / 下落时间）
	"body_offset_y": -16.0,
	"placeholder_offset_y": -12.0,
	"drop_in_height": 20.0,
	"drop_in_time": 0.28,
	## 没有品阶信息时的色块颜色
	"fallback_placeholder_color": Color(0.85, 0.82, 0.6, 1.0),
	## 「F 拾取」提示（青绿）—— 掉落物不显示名字
	"hint_text": "F 拾取",
	"hint_color": Color(0.55, 0.95, 0.6, 1.0),
	"hint_offset": Vector2(-60.0, 28.0),
	"hint_size": Vector2(120.0, 20.0),
	"hint_font_size": 13,
	## 拾取后飞起高度与消散时长
	"pickup_rise": 28.0,
	"pickup_time": 0.35,
}

## 取掉落物外观配置（返回副本，调用方可安全修改）
## 试炼回血丹专属落地表现（2026-11-08 用户定「要小巧」）。
## ⚠ 通过 item["pickup_style"] 覆盖上面的全局 PICKUP_BEAM，主模式其它掉落物一行都不动。
## 旧版沿用装备级 96×232 光柱 + 62px 图标，一颗回血丹看起来像大盘子；
## 这里整体收到约 1/2，并去掉「躺地厚度」叠层 —— 它本来就是一颗小丹丸，不需要厚度。
const ROGUE_HEAL_PICKUP_STYLE: Dictionary = {
	"beam_size": Vector2(38.0, 88.0),
	"beam_offset": Vector2(-19.0, -88.0),
	"beam_strength": 0.50,
	"glow_size": Vector2(58.0, 20.0),
	"glow_position": Vector2(0.0, -3.0),
	"glow_alpha": 0.30,
	"shadow_size": Vector2(30.0, 10.0),
	"shadow_position": Vector2(0.0, -2.0),
	"shadow_alpha": 0.28,
	"contact_shadow_size": Vector2(20.0, 7.0),
	"contact_shadow_position": Vector2(0.0, -1.0),
	"contact_shadow_alpha": 0.32,
	"thickness_layers": 0,
	"icon_longest": 30.0,
	"ground_tilt_deg": 6.0,
	"ground_squash": 0.80,
	"body_offset_y": -8.0,
	"drop_in_height": 10.0,
	"drop_in_time": 0.22,
	"hint_offset": Vector2(-40.0, 16.0),
	"hint_size": Vector2(80.0, 18.0),
	"hint_font_size": 11,
	"pickup_rise": 16.0,
	"pickup_time": 0.28,
}


func get_pickup_beam() -> Dictionary:
	return PICKUP_BEAM.duplicate(true)


## 试炼 BOSS 遗物（装备）落地表现。
## ⚠ 为什么不能直接用全局 PICKUP_BEAM：装备图标画布留白很大（实测「青锋剑」有效内容
##   只占 256 画布的 45%），全局 icon_longest=62 摊到地上只剩 28px，再被光柱一照几乎看不见
##   （2026-11-09 用户要求「掉落的装备要在地上显示」）。这里放大图标、收一点光柱强度，
##   只作用于试炼 BOSS 掉落，主模式掉落物一行都不动。
const ROGUE_GEAR_PICKUP_STYLE: Dictionary = {
	"beam_size": Vector2(74.0, 196.0),
	"beam_offset": Vector2(-37.0, -196.0),
	# ⚠ 光柱别太亮：装备原画偏暗，光柱一白就把物品糊成一团剪影（第一版 0.52 就是这样）
	"beam_strength": 0.28,
	"glow_size": Vector2(184.0, 60.0),
	"glow_position": Vector2(0.0, -8.0),
	# ⚠ 加法混合的光晕一浓，暗色的装备原画就变成「光斑里的一个洞」（试到 0.52 时最明显）
	"glow_alpha": 0.26,
	"shadow_size": Vector2(96.0, 30.0),
	"shadow_position": Vector2(0.0, -4.0),
	"shadow_alpha": 0.40,
	"contact_shadow_size": Vector2(64.0, 20.0),
	"contact_shadow_position": Vector2(0.0, -2.0),
	"contact_shadow_alpha": 0.44,
	"thickness_layers": 2,
	"thickness_step": 3.0,
	"icon_longest": 124.0,
	"ground_tilt_deg": 8.0,
	"ground_tilt_weapon_deg": 34.0,
	"ground_squash": 0.78,
	"body_offset_y": -30.0,
	"drop_in_height": 26.0,
	"drop_in_time": 0.30,
	"hint_offset": Vector2(-60.0, 34.0),
	"hint_size": Vector2(120.0, 20.0),
	"hint_font_size": 14,
	"pickup_rise": 28.0,
	"pickup_time": 0.30,
}


func get_rogue_gear_pickup_style() -> Dictionary:
	return ROGUE_GEAR_PICKUP_STYLE.duplicate(true)


## 局内小件（试炼回血丹）的覆盖参数；换皮只改这张表
func get_rogue_heal_pickup_style() -> Dictionary:
	return ROGUE_HEAL_PICKUP_STYLE.duplicate(true)


## ===== 御剑普攻的连续刀光拖尾（2026-10-27 替换分身式残影）=====
## 贴着剑尖扫过的细弧带：越新越亮，尾部按寿命衰减；颜色由武器的 trail_color 决定。
## 口径：克制细拖尾，不要分身、不要冷白闪光；终结段略长略亮。
const WEAPON_TRAIL: Dictionary = {
	"color": Color(0.74, 0.85, 0.98, 1.0),
	"alpha": 0.30,
	"life": 0.16,
	"width": 14.0,
	"finisher_alpha": 0.40,
	"finisher_life": 0.20,
	"finisher_width": 18.0,
}

## 取刀光拖尾参数（返回副本，调用方可安全修改）
func weapon_trail() -> Dictionary:
	return WEAPON_TRAIL.duplicate(true)


## 所有御剑武器的**统一显示长度**（像素，按图片非透明内容的**高度**算）
## 武器条目没单独写 target_length 就用这个值。
##
## ⚠ 这是「高度」不是「视觉重量」：**细长剑 68 合适，宽刃/弯曲武器要更小**。
##   经验公式：target ≈ 68 × √(细剑内容面积 ÷ 该武器内容面积)
##   例：弯刀内容 190×1150（细剑 143×1139）→ 68 × √(162877/218500) ≈ 59，实际给 56 更稳
##
## 📋 加新武器的完整流程见 `.workbuddy/memory/MEMORY.md` §一「加新武器的标准流程」
##    （素材放哪 / 图标要斜放 / 绝不能同时设 scale_override）
const WEAPON_DEFAULT_LENGTH := 68.0

## 三段普攻的默认挥砍轨迹 —— **所有武器共用这一套攻击表现**
## 单把武器若要不同的手感，可在它的 ArtDB 条目里写自己的 `combo_sweeps` 覆盖，否则自动用这里。
## from_deg / to_deg：起止角（相对朝向；**-90 = 屏幕上方**，+90 = 下方）
## reach_mult：伸出倍数（>1 = 往攻击方向捅出去，前刺用）
## hit_at：刀锋扫到正前方的进度（0~1），普攻出伤就卡在这个时刻
## spin_turns：自旋圈数（负数 = 反向转）
## windup：是否先「蓄力后撤」（只有第 1 段需要）
const WEAPON_COMBO_SWEEPS: Array = [
	# 第 1 段：从上往下劈（扫过半程时刀锋正好压到正前方）
	{"from_deg": -85.0, "to_deg": 70.0, "sweep_time": 0.17,
		"spin_turns": 0.25, "reach_mult": 1.0, "windup": true, "hit_at": 0.55},
	# 第 2 段：从下往上撩（反向，起点接第 1 段终点）
	{"from_deg": 70.0, "to_deg": -85.0, "sweep_time": 0.17,
		"spin_turns": -0.25, "reach_mult": 1.0, "hit_at": 0.50},
	# 第 3 段：向前刺 —— 角度只小幅前扫，靠 reach_mult 捅出去（距离更远）
	# spin_turns = 0：刺击不旋转，刃尖始终指向攻击方向
	{"from_deg": -30.0, "to_deg": 8.0, "sweep_time": 0.16,
		"spin_turns": 0.0, "reach_mult": 1.75, "hit_at": 0.70},
]


## 默认特效条目（id 未登记时使用）
const DEFAULT_EFFECT: Dictionary = {
	"texture": "",
	"frames": 1,
	"frame_size": Vector2.ZERO,
	"fps": 12.0,
	"spawn_offset": Vector2.ZERO,
	## 旋转半径：贴图偏离旋转中心多远。
	## 0 = 原地旋转（刀光等默认行为）；非 0 = 绕父级原点（角色）扫过 —— 武器挥砍用这个
	"pivot_offset": Vector2.ZERO,
	## 贴图自身的旋转角（度）：武器图刃尖朝上就填 -90，朝右填 0。
	## 绕角色扫过时用这个把图摆正，避免「武器横着转」
	"sprite_rotation_deg": 0.0,
	"spin_speed": 0.0,
	"sweep_angle_deg": 0.0,
	"scale_from": Vector2.ONE,
	"scale_to": Vector2.ONE,
	"fade_to": 1.0,
	"lifetime": 0.3,
	"blend_add": false,
	"fallback_kind": "none",
	"fallback_color": Color(1.0, 1.0, 1.0, 0.8),
	"fallback_radius": 40.0,
	"fallback_rect_size": Vector2.ZERO,
}

## 默认条目（id 未登记时使用），保证任何实体都有可渲染的占位
const DEFAULT_ENTRY: Dictionary = {
	## 骨骼 rig 数据路径（BossRigData .tres）—— **四足 BOSS 的移动动画走这条**
	## 配了它之后：idle / walk 由骨骼驱动（躯干是同一张贴图，结构上不会抽搐），
	## 招式仍用下面的 sprite_frames 作覆盖层。两者画布同尺寸，可随时互换。
	## 生成：python tools/build_tiger_rig.py
	"rig": "",
	## 原生 SpriteFrames 资源路径（.tres / .res）—— **正式素材走这条，优先级最高**
	## 在 Godot 里用 SpriteFrames 面板建好后填这里即可，不需要 frames / frame_size
	"sprite_frames": "",
	## 单张 PNG 路径：frames == 1 时走 Sprite2D（静态贴图）
	##                  frames > 1 时按 frame_size 代码切分（快速原型用，正式素材不必用）
	"texture": "",
	"frames": 1,
	"frame_size": Vector2.ZERO,
	"fps": 8.0,
	## 目标显示长度（像素）。> 0 时**自动**按贴图的实际内容范围算出 scale 与 offset，
	## 此时 scale / offset 字段会被覆盖，不必手算。仅对单帧贴图（无 frames 动画）生效。
	## 用途：换任何武器/道具图，只改这一个数字，尺寸和轴心自动对齐。
	"target_length": 0.0,
	"scale": Vector2.ONE,
	"offset": Vector2.ZERO,
	"flip_driven": true,
	"anchor_bottom": false,
	## 整体着色（乘法，1,1,1 = 原色）：战场地面太亮/偏色时调这里，**不要改原图**
	"tint": Color(1.0, 1.0, 1.0, 1.0),
	## 贴图着色器（可选）：只改变这张贴图的呈现方式，**不新增节点/特效**。
	## 参数写进 shader_params（键 = uniform 名），tex_size 会自动填。
	"shader": "",
	"shader_params": {},
	"placeholder_color": Color(0.8, 0.8, 0.8, 1.0),
	"placeholder_size": Vector2(32.0, 32.0),
}


## 取某个实体的视觉配置（未登记返回默认条目）
## 返回值是**副本**，调用方可安全修改而不污染本表
func get_visual(visual_id: String) -> Dictionary:
	var entry: Dictionary = VISUALS.get(visual_id, {})
	var merged := DEFAULT_ENTRY.duplicate(true)
	for k in entry.keys():
		merged[k] = entry[k]
	return merged


## 取设施视觉配置：优先 facility_<id>，其次 facility_generic，最后默认
func get_facility_visual(facility_id: String) -> Dictionary:
	var key := "facility_" + facility_id
	if VISUALS.has(key):
		return get_visual(key)
	if VISUALS.has("facility_generic"):
		return get_visual("facility_generic")
	return get_visual("")


## 该实体是否已接入真实贴图（用于 UI 提示 / 调试）
func has_texture(visual_id: String) -> bool:
	var entry := get_visual(visual_id)
	return String(entry.get("texture", "")) != ""


## 已接入贴图的实体 id 列表（调试/进度查看用）
func textured_ids() -> Array:
	var out: Array = []
	for id in VISUALS.keys():
		if has_texture(String(id)):
			out.append(id)
	return out


## 把图片路径转成 SpriteFrames（供纯图片素材直接使用，无需手工做 .tres）
## 仅处理「横向排列的图集」这种最常见形式；frame_size 为零时按图片高度推断
func build_sprite_frames(texture_path: String, frame_size: Vector2, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if texture_path == "" or not ResourceLoader.exists(texture_path):
		return sf
	var tex: Texture2D = load(texture_path)
	if tex == null:
		return sf

	var size := frame_size
	if size == Vector2.ZERO:
		size = Vector2(float(tex.get_height()), float(tex.get_height()))
	var count := maxi(1, int(tex.get_width() / maxf(size.x, 1.0)))

	# 只有一组帧时统一命名为 idle；玩家/BOSS 后续可扩展多组
	sf.add_animation(ANIM_IDLE)
	sf.set_animation_speed(ANIM_IDLE, fps)
	sf.set_animation_loop(ANIM_IDLE, true)
	for i in range(count):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(Vector2(size.x * float(i), 0.0), size)
		sf.add_frame(ANIM_IDLE, at)
	return sf


# =====================================================================
# 试炼符箓（2026-11-10 重做）
# =====================================================================
## 每张符的占位色 / 卡面 / 元素字。**美术替换口就在这里**：
##   卡面到位后把 card 填成 res://assets/... 即可，UI 会自动改用贴图；
##   符阵、符灵、飘字、描边一律读 color，不在业务代码里另写一份。
## ⚠ 十张符现在**三件套齐全**（card / icon / glyph）——2026-11-10 补齐冰/光/暗之后
##   已经没有「只有 glyph」的符了；glyph 退化成纯兜底（贴图丢失时才会看到）。
## ⚠ 三件套各管一处，别混用：
##   card  大卡面（结符页 / 换符页 / 符匣），190×285 竖构图
##   icon  48px 技能栏小图标（战斗 HUD 的 Q/E/R/T 用），没有就退回 card
##   glyph 连占位图都没有时的单字
const TALISMANS: Dictionary = {
	"tal_jinfeng": {"color": Color(0.94, 0.86, 0.62, 1.0), "glyph": "金",
		"icon": "res://assets/ui/icon/tal_element_metal.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_metal.png"},
	"tal_huoqiu": {"color": Color(0.96, 0.52, 0.28, 1.0), "glyph": "火",
		"icon": "res://assets/ui/icon/tal_element_fire.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_fire.png"},
	"tal_yinlei": {"color": Color(0.76, 0.60, 1.0, 1.0), "glyph": "雷",
		"icon": "res://assets/ui/icon/tal_element_thunder.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_thunder.png"},
	"tal_muling": {"color": Color(0.56, 0.86, 0.58, 1.0), "glyph": "木",
		"icon": "res://assets/ui/icon/tal_element_wood.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_wood.png"},
	"tal_shuihui": {"color": Color(0.48, 0.78, 0.94, 1.0), "glyph": "水",
		"icon": "res://assets/ui/icon/tal_element_water.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_water.png"},
	"tal_fengji": {"color": Color(0.62, 0.90, 0.80, 1.0), "glyph": "风",
		"icon": "res://assets/ui/icon/tal_element_wind.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_wind.png"},
	"tal_tushi": {"color": Color(0.80, 0.68, 0.48, 1.0), "glyph": "土",
		"icon": "res://assets/ui/icon/tal_element_earth.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_earth.png"},
	# 下面三张是试炼专属（符方获得）：卡面由 ImageGen 出图后经
	# tools/finish_talisman_cards.py 去水印 + 缩放，图标由 tools/gen_talisman_icons.py 生成，
	# 与另外七张同一套宣纸 / 朱砂边框。glyph 只在贴图缺失时兜底。
	"tal_bingning": {"color": Color(0.66, 0.90, 1.0, 1.0), "glyph": "冰",
		"icon": "res://assets/ui/icon/tal_element_ice.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_ice.png"},
	"tal_zheguang": {"color": Color(1.0, 0.92, 0.62, 1.0), "glyph": "光",
		"icon": "res://assets/ui/icon/tal_element_light.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_light.png"},
	"tal_shiyuan": {"color": Color(0.58, 0.42, 0.72, 1.0), "glyph": "暗",
		"icon": "res://assets/ui/icon/tal_element_dark.png",
		"card": "res://assets/ui/talisman/cards/talisman_card_dark.png"},
}

## 元素配色：符箓落点 / 符阵 / 符灵 / 飘字共用一份
## ⚠ 这是**元素**（AttributeDB.ELEMENTS 那一套 + 冰/光），不是符 id ——
##   op 里写的是 "fire" / "thunder"，别拿 TalismanDB 的 base_id 来查。
const ELEMENT_COLORS: Dictionary = {
	"metal": Color(0.94, 0.86, 0.62, 1.0),
	"wood": Color(0.56, 0.86, 0.58, 1.0),
	"water": Color(0.48, 0.78, 0.94, 1.0),
	"fire": Color(0.96, 0.52, 0.28, 1.0),
	"earth": Color(0.80, 0.68, 0.48, 1.0),
	"wind": Color(0.62, 0.90, 0.80, 1.0),
	"thunder": Color(0.76, 0.60, 1.0, 1.0),
	"ice": Color(0.66, 0.90, 1.0, 1.0),
	"light": Color(1.0, 0.92, 0.62, 1.0),
	"dark": Color(0.62, 0.46, 0.76, 1.0),
}


## 元素 → 代表符：局内按**元素**取卡面时用（符灵、地面符阵等，
## 它们只有 element 没有 base_id，不能走 talisman_style(base_id)）。
## ⚠ 这里只存 id，卡面路径仍然只在 TALISMANS 里存一份，不复制十条 res:// 路径。
const ELEMENT_BASE: Dictionary = {
	"metal": "tal_jinfeng", "wood": "tal_muling", "water": "tal_shuihui",
	"fire": "tal_huoqiu", "earth": "tal_tushi", "wind": "tal_fengji",
	"thunder": "tal_yinlei", "ice": "tal_bingning", "light": "tal_zheguang",
	"dark": "tal_shiyuan",
}


static func element_color(element: String) -> Color:
	return Color(ELEMENT_COLORS.get(element, Color(0.82, 0.76, 0.64, 1.0)))


## 按元素取**大卡面**路径；没登记或资源缺失返回空串（调用方画占位，不报错）
static func element_card(element: String) -> String:
	var base := String(ELEMENT_BASE.get(element, ""))
	if base == "":
		return ""
	var path := String(talisman_style(base).get("card", ""))
	if path != "" and ResourceLoader.exists(path):
		return path
	return ""


const DEFAULT_TALISMAN: Dictionary = {
	"color": Color(0.82, 0.76, 0.64, 1.0), "glyph": "符", "card": "",
}


static func talisman_style(base_id: String) -> Dictionary:
	if TALISMANS.has(base_id):
		return TALISMANS[base_id]
	return DEFAULT_TALISMAN


static func talisman_color(base_id: String) -> Color:
	return Color((talisman_style(base_id) as Dictionary).get("color", Color(0.82, 0.76, 0.64, 1.0)))


## 技能栏小图标：没有小图就退回大卡面，两者都没有返回空串（调用方画单字占位）
static func talisman_icon(base_id: String) -> String:
	var st := talisman_style(base_id)
	var icon := String(st.get("icon", ""))
	return icon if icon != "" else String(st.get("card", ""))
