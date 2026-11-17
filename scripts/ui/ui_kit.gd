class_name UIKit
extends RefCounted
## UI 样式与控件工厂 —— 更换美术资源的唯一入口
##
## 约定：所有面板只能通过本文件取颜色、字号、样式、控件，不得自行硬编码。
## 换皮时只需改这里的常量 / 三个 style 工厂；换图标只需在数据表里填 icon 路径。
##
## 美术接入流程：
##   1. 换配色 → 改下面 C_* 常量
##   2. 换底图 → 改 panel_style() / slot_style()，把 StyleBoxFlat 换成 StyleBoxTexture
##   3. 换图标 → 在数据条目里填 icon="res://assets/icon/xxx.png"，UI 自动从占位切换为贴图
##   4. 换字体 → 改 apply_font() 里加载的 Font 资源

# ===== 配色 =====
const C_PANEL_BG := Color(0.07, 0.07, 0.11, 0.97)
const C_PANEL_BORDER := Color(0.42, 0.35, 0.22, 1.0)
const C_ACCENT := Color(0.95, 0.82, 0.45, 1.0)
const C_TEXT := Color(0.88, 0.88, 0.92, 1.0)
const C_TEXT_DIM := Color(0.62, 0.62, 0.68, 1.0)
const C_SLOT_BG := Color(0.13, 0.13, 0.17, 0.85)
const C_SLOT_BG_FILLED := Color(0.18, 0.16, 0.24, 0.95)
const C_SLOT_BORDER := Color(0.26, 0.24, 0.30, 1.0)
const C_OK := Color(0.45, 0.78, 0.45, 1.0)
const C_WARN := Color(0.85, 0.60, 0.35, 1.0)
const C_DANGER := Color(0.82, 0.35, 0.35, 1.0)
const C_DISABLE := Color(0.48, 0.48, 0.53, 1.0)
## 大成功高亮色（强化飘字用）
const C_GREAT := Color(1.0, 0.85, 0.25, 1.0)
## 强化进阶成功色（紫）
const C_ASCEND := Color(0.85, 0.60, 1.00, 1.0)
## 锻造台铁砧底色（金属冷灰）
const C_ANVIL := Color(0.24, 0.25, 0.29, 1.0)
const C_ANVIL_HOVER := Color(0.36, 0.38, 0.46, 1.0)
const C_ANVIL_BORDER := Color(0.42, 0.44, 0.50, 1.0)

# ===== 正式美术贴图（2026-10-22 接入）=====
## 面板金框：**只有边框**、内部透明（叠在 panel_style 的深色底上）
const TEX_PANEL_FRAME := "res://assets/ui/panel/panel_frame_9p.png"
## 位面选择 / BOSS 选择界面背景（2026-10-22 导入，目前只用作面板背景）
const TEX_BG_REALM_SELECT := "res://assets/ui/realm_select_bg.png"
const TEX_BG_BOSS_SELECT := "res://assets/ui/boss_select_bg.png"
## 全局水墨按钮皮肤（2026-10-25）：墨签 / 朱印 / 纸签 + 小印 + 笔刷线
## 源图用 tools/gen_ui_ink_skin.py 生成，按钮控件见 scripts/ui/ink_button.gd
const TEX_BTN_INK := "res://assets/ui/panel/button_ink_9p.png"
const TEX_BTN_SEAL := "res://assets/ui/panel/button_seal_9p.png"
const TEX_BTN_PAPER := "res://assets/ui/panel/button_paper_9p.png"
const TEX_SEAL_MARK := "res://assets/ui/panel/seal_mark.png"
const TEX_BRUSH_LINE := "res://assets/ui/panel/brush_line.png"
## 竖长符纸纹理（画符台用；边框由 TalismanCanvas 现画）
const TEX_TALISMAN_PAPER := "res://assets/ui/panel/talisman_paper.png"
const BTN_PATCH_X := 40
const BTN_PATCH_Y := 12
## 设施面板用素材（2026-10-25 生成）：圆形徽章 / 透明立绘 / 柔光 / 圆环 / 光点
## 源图在 assets/scenes/facilities/，重新生成跑 tools/gen_facility_ui_art.py
const DIR_FACILITY_UI := "res://assets/ui/facilities/"
const TEX_GLOW_SOFT := DIR_FACILITY_UI + "glow_soft.png"
const TEX_RING_SOFT := DIR_FACILITY_UI + "ring_soft.png"
const TEX_DOT_SOFT := DIR_FACILITY_UI + "dot_soft.png"

## 设施主题：插画抬头 + 氛围色 + 副标题（所有面板共用一套识别）
## glyph 用于没有专属插画的系统（功法库 / 境界 / 图鉴 / 指引），在圆形印记里显示单字。
const FACILITY_STYLES := {
	"gateway": {
		"accent": Color(0.52, 0.84, 1.00),
		"subtitle": "万界星门 · 择界而入",
		"medallion": DIR_FACILITY_UI + "gateway_medallion.png",
		"cutout": DIR_FACILITY_UI + "gateway_cutout.png",
	},
	"tower": {
		"accent": Color(0.46, 0.90, 0.82),
		"subtitle": "登塔问道 · 一层一影",
		"medallion": DIR_FACILITY_UI + "tower_medallion.png",
		"cutout": DIR_FACILITY_UI + "tower_cutout.png",
	},
	"alchemy": {
		"accent": Color(0.64, 0.88, 0.52),
		"subtitle": "采药入炉 · 火候即丹心",
		"medallion": DIR_FACILITY_UI + "alchemy_medallion.png",
		"cutout": DIR_FACILITY_UI + "alchemy_cutout.png",
	},
	"talisman": {
		"accent": Color(0.96, 0.55, 0.38),
		"subtitle": "朱砂落纸 · 符成惊神",
		"medallion": DIR_FACILITY_UI + "talisman_medallion.png",
		"cutout": DIR_FACILITY_UI + "talisman_cutout.png",
	},
	"memory": {
		"accent": Color(0.46, 0.87, 0.86),
		"subtitle": "旧事如碑 · 照见前尘",
		"medallion": DIR_FACILITY_UI + "memory_medallion.png",
		"cutout": DIR_FACILITY_UI + "memory_cutout.png",
	},
	"forge": {
		"accent": Color(0.64, 0.78, 0.96),
		"subtitle": "千锤百炼 · 器以载道",
		"medallion": DIR_FACILITY_UI + "forge_medallion.png",
		"cutout": DIR_FACILITY_UI + "forge_cutout.png",
	},
	"warehouse": {
		"accent": Color(0.92, 0.76, 0.46),
		"subtitle": "万物有归 · 自有清点",
		"medallion": DIR_FACILITY_UI + "warehouse_medallion.png",
		"cutout": DIR_FACILITY_UI + "warehouse_cutout.png",
	},
	"herb_garden": {
		"accent": Color(0.60, 0.90, 0.55),
		"subtitle": "灵田三亩 · 草木有时",
		"medallion": DIR_FACILITY_UI + "herb_garden_medallion.png",
		"cutout": DIR_FACILITY_UI + "herb_garden_cutout.png",
	},
	"arena": {
		"accent": Color(0.96, 0.72, 0.46),
		"subtitle": "以武证道 · 木桩试炼",
		"medallion": DIR_FACILITY_UI + "arena_medallion.png",
		"cutout": DIR_FACILITY_UI + "arena_cutout.png",
	},
	"skill": {
		"accent": Color(0.95, 0.82, 0.45),
		"subtitle": "万千招式 · 皆由感悟",
		"glyph": "功",
	},
	"realm": {
		"accent": Color(0.80, 0.66, 1.00),
		"subtitle": "炼气化神 · 一步一境",
		"glyph": "境",
	},
	"codex": {
		"accent": Color(0.86, 0.78, 0.52),
		"subtitle": "万界所藏 · 皆入此卷",
		"glyph": "鉴",
	},
	"achievement": {
		"accent": Color(0.94, 0.76, 0.42),
		"subtitle": "功行有记 · 山海入藏",
		"glyph": "成",
	},
	"guide": {
		"accent": Color(0.92, 0.80, 0.50),
		"subtitle": "初入此界 · 先读此书",
		"glyph": "引",
	},
	"insight": {
		"accent": Color(0.96, 0.82, 0.48),
		"subtitle": "观其形 · 悟其意",
		"glyph": "悟",
	},
}
## 新手指引「小书」图标（原初位面左上角）
## 美术就位后：把图放到这个路径即可，缺失时自动回退成「书」字占位块
const TEX_ICON_GUIDE := "res://assets/ui/icon/guide_book.png"
## 9-patch 边距（像素）：**只取云纹角的一部分**
## 取满（190）时云纹太大、会压住面板里靠边的标题/书签/关闭按钮，缩到 72：
## 云纹被压扁一点，但软云纹看不出来，反而给内容腾出了空间。
## ⚠ 不要靠「加大 PANEL_MARGIN」避让：锻造台铁砧区是绝对定位，内边距一改按钮就被裁。
const FRAME_PATCH_MARGIN := 72

# 物品类型色（用于图标占位块底色，换美术后可继续用或废弃）
const TYPE_COLOR := {
	"pill": Color(0.30, 0.55, 0.42, 1.0),
	"talisman": Color(0.55, 0.42, 0.62, 1.0),
	"material": Color(0.50, 0.46, 0.32, 1.0),
	"equipment": Color(0.36, 0.46, 0.60, 1.0),
	"skill": Color(0.58, 0.38, 0.34, 1.0),
	"memory": Color(0.42, 0.50, 0.58, 1.0),
	## 新手指引小书（未接贴图时的占位底色：竹简褐）
	"guide": Color(0.40, 0.31, 0.18, 1.0),
}

# ===== 伤害数字配色（用户定：玩家打 BOSS 分物理/法术，BOSS 打玩家统一红）=====
## 物理伤害 = 黄　法术伤害 = 蓝　玩家挨打 = 红
## 换美术时只需改这三个常量，飘字的字号/描边/动画在 damage_number.gd 顶部
const C_DMG_PHYS := Color(1.00, 0.84, 0.30, 1.0)   # 物理伤害（黄）
const C_DMG_SPELL := Color(0.40, 0.72, 1.00, 1.0)  # 法术伤害（蓝）

## ===== 资源条配色（原「刀势条」）=====
## ⚠ 刀客的刀势机制已于 2026-10-22 删除，目前无人使用；保留配色供以后同类资源条复用。
const C_MOMENTUM := Color(0.85, 0.62, 0.30, 1.0)      ## 常态（暖金）
const C_MOMENTUM_DANGER := Color(1.00, 0.38, 0.28, 1.0) ## ≥60：满势断岳抢跑预警（赤红）

## ===== 战斗 HUD 配色（血 / 精力 / 灵力三条）=====
const C_HUD_HP := Color(0.25, 0.80, 0.40, 1.0)          ## 血量充足（绿）
const C_ALERT := Color(1.00, 0.20, 0.20, 1.0)           ## 告急红：血条低血量 + 战斗中央公告共用
const C_HUD_MANA := Color(0.35, 0.55, 1.00, 1.0)        ## 灵力充足（蓝）
const C_HUD_MANA_LOW := Color(0.50, 0.45, 0.85, 1.0)    ## 灵力低于半数（暗紫）
const C_HUD_STAMINA_ON := Color(1.00, 0.82, 0.38, 1.0)  ## 有精力的原点（金，2026-11-12 从亮白改）
const C_HUD_STAMINA_OFF := Color(1.0, 1.0, 1.0, 0.15)   ## 空精力原点（近乎透明）
## 原 C_HUD_STAMINA_HIDDEN 已删：那是「场景里固定 5 段 ColorRect、超出格数就整段透明」
## 的补丁，精力现在由 ResourceVessel 按 max_stamina 现画，不存在多余格子。

## ===== 玩法提示飘字配色 =====
const C_FLOAT_WARN := Color(0.95, 0.75, 0.35, 1.0)      ## 资源不足等通用警告
const C_FLOAT_BLOCK := Color(0.70, 0.90, 1.00, 1.0)     ## 蓄力格挡（冷蓝）
const C_FLOAT_COUNTER := Color(1.00, 0.72, 0.25, 1.0)   ## 纳势反击（暖金）

## ===== 战斗中央公告配色 =====
const C_ANNOUNCE_WARN := Color(1.00, 0.60, 0.30, 1.0)   ## 背包已满等警告（橙）
const C_ANNOUNCE_TITLE := Color(0.96, 0.85, 0.52, 1.0)  ## 阶段标题 / 通用提示（金）
const C_ANNOUNCE_GOLD := Color(1.00, 0.90, 0.55, 1.0)   ## 高亮金

## ===== BOSS 头顶技能名飘字 =====
const C_SKILL_NAME := Color(1.00, 0.72, 0.35, 1.0)      ## 前摇瞬间飘出，释放时才淡出
const SKILL_NAME_SIZE := 20
const SKILL_NAME_WIDTH := 120.0

# ===== 字号 =====
const F_TITLE := 20
const F_SUBTITLE := 18
const F_SECTION := 15
const F_BODY := 13
const F_SMALL := 11
## 强化角标字号（比 F_SMALL 再小一档，角标只占图标角落）
const F_BADGE := 10

# ===== 尺寸 =====
const SLOT_SIZE := Vector2(92.0, 56.0)
const SLOT_SIZE_LG := Vector2(120.0, 72.0)
const ROW_MIN_HEIGHT := 34.0
## 面板内边距（内容离金框留出的空间）
## ⚠ 2026-10-22 试过 18 → 28 避让金框云纹角，结果锻造台铁砧区是**绝对定位**的，
##   「分解装备」按钮被裁出面板 → 回退 18。云纹角改为缩小（见 FRAME_PATCH_MARGIN）。
const PANEL_MARGIN := 18.0
const DIM_ALPHA := 0.55
## 槽位内容内衬厚度（与 slot_style 的 content_margin 保持一致）
const SLOT_PADDING := 3
## 小格子（素材格 / 背包格）里的图标尺寸：92px 宽的格子减去内衬后只剩约 50px 给文字，
## 图标再大就会把「锻造晶石」这类四字名挤成省略号
const SLOT_ICON := Vector2(32.0, 32.0)

## ===== 品阶配色（用户 2026-10-17 定，七色环）=====
## 凡品 白 → 法器 绿 → 灵器 蓝 → 宝器 紫 → 道器 橙 → 仙器 红 → 神器/先天至宝 粉
## 这是**唯一**的品质色来源：边框、文字、掉落光柱占位色都从这里取。
## 换皮 / 调色只改这一段，不要去各面板里找颜色。
const GRADE_COLORS := {
	"凡品": Color(0.93, 0.94, 0.97, 1.0),
	"法器": Color(0.45, 0.80, 0.45, 1.0),
	"灵器": Color(0.42, 0.66, 0.95, 1.0),
	"宝器": Color(0.72, 0.52, 0.92, 1.0),
	"道器": Color(0.95, 0.62, 0.28, 1.0),
	"仙器": Color(0.92, 0.32, 0.32, 1.0),
	"神器/先天至宝": Color(1.00, 0.60, 0.85, 1.0),
}
## 强化角标配色：深底金字（角标只是辅助信息，不该抢品阶色的视觉焦点）
const C_ENHANCE_TEXT := Color(1.00, 0.86, 0.42, 1.0)
const C_ENHANCE_BG := Color(0.06, 0.07, 0.10, 0.90)
## 技能冷却遮罩色（战斗内功法快捷栏，盖在图标上表示「还没转好」）
const C_CD_MASK := Color(0.05, 0.06, 0.10, 0.74)


# ===== 光影模型（2026-11-04 用户定：靠光影与排版建立秩序，不靠粗描边和强闪光）=====
## 全局唯一光源：从**左上**打光。所有面板、槽位、卡片、浮层的亮边与投影都必须服从这一方向。
## 要换光向只改 LIGHT_FROM 这一个常量，apply_elevation() / edge_light() 会自动跟着走。
const LIGHT_FROM := Vector2(-1.0, -1.0)   ## 光源在左上 → 投影落向右下
## 抬层次序：0 = 贴在面板上的平面元素（不投影）；1 = 卡片 / 信息条；2 = 弹窗 / 浮签；3 = 拖拽跟随
const ELEV_FLAT := 0
const ELEV_CARD := 1
const ELEV_FLOAT := 2
const ELEV_DRAG := 3
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.40)
const SHADOW_SIZES: Array[int] = [0, 7, 14, 22]
## 受光侧 1px 细亮边 + 背光侧 1px 收边：用这两个代替粗外框来分层
const EDGE_LIGHT := Color(1.0, 0.97, 0.88, 0.14)
const EDGE_SHADE := Color(0.0, 0.0, 0.0, 0.34)

## ===== 文字三级（标题 / 正文 / 数字）=====
## 标题**降饱和**，把最高亮度的强调色只留给主按钮和关键数字；正文一律阅读字体、不加描边。
const C_TITLE := Color(0.84, 0.80, 0.71, 1.0)      ## 标题：暖宣纸，不再用亮金
const C_NUM := Color(0.95, 0.94, 0.90, 1.0)        ## 数字：最干净的一档，靠字号而不是靠颜色抢
const C_TEXT_FAINT := Color(0.50, 0.51, 0.56, 1.0) ## 三级注释 / 占位说明
const C_EMPHASIS := Color(1.00, 0.83, 0.40, 1.0)   ## 唯一的高亮度强调色：只给主按钮与关键数字

## ===== 留白 =====
const GAP_SECTION := 14.0   ## 大区块之间
const GAP_BLOCK := 8.0      ## 区块内的小节之间
const GAP_PRIMARY_ROW := 18.0   ## 主按钮行上方必须留出的空

## 把颜色向灰阶收：次要元素统一用它，避免满屏高彩互相抢。
## 这版 Color 没有 to_hsv()，直接用亮度做灰底线性插值，效果等价且不会改色相。
static func muted(c: Color, amount: float = 0.34) -> Color:
	var k := clampf(amount, 0.0, 1.0)
	var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var gray := Color(l, l, l, c.a)
	var out := c.lerp(gray, k)
	# 顺带压一点点明度，收完的次要色不该比原来更亮
	return Color(out.r * (1.0 - k * 0.08), out.g * (1.0 - k * 0.08),
		out.b * (1.0 - k * 0.08), c.a)


## 投影偏移：沿光源反方向（左上打光 → 阴影向右下），层次越高走得越远
static func elevation_offset(level: int) -> Vector2:
	var lv := clampi(level, 1, SHADOW_SIZES.size() - 1)
	return -LIGHT_FROM.normalized() * float(2 + lv)


## 给 StyleBoxFlat 上光影：柔和投影落在光源反方向，边框收到 1px
static func apply_elevation(sb: StyleBoxFlat, level: int = ELEV_CARD) -> StyleBoxFlat:
	if sb == null:
		return sb
	var lv := clampi(level, 0, SHADOW_SIZES.size() - 1)
	sb.shadow_size = int(SHADOW_SIZES[lv])
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_offset = elevation_offset(lv) if lv > 0 else Vector2.ZERO
	return sb


## 亮边覆盖层：只画直段、两端让开圆角，避免圆角外冒出孤立亮点
class EdgeOverlay:
	extends Control
	var light: Color = Color(1.0, 0.97, 0.88, 0.14)
	var shade: Color = Color(0.0, 0.0, 0.0, 0.34)
	var corner: float = 6.0
	var thickness: float = 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if r.size.x <= thickness * 3.0 or r.size.y <= thickness * 3.0:
			return
		var inset := minf(corner, minf(r.size.x, r.size.y) * 0.35)
		draw_rect(Rect2(Vector2(r.position.x + inset, r.position.y),
			Vector2(r.size.x - inset * 2.0, thickness)), light, true)
		draw_rect(Rect2(Vector2(r.position.x, r.position.y + inset),
			Vector2(thickness, r.size.y - inset * 2.0)), light, true)
		draw_rect(Rect2(Vector2(r.position.x + inset, r.end.y - thickness),
			Vector2(r.size.x - inset * 2.0, thickness)), shade, true)
		draw_rect(Rect2(Vector2(r.end.x - thickness, r.position.y + inset),
			Vector2(thickness, r.size.y - inset * 2.0)), shade, true)


## 给一个控件叠受光边（重复调用只更新，不叠第二层）
static func edge_light(host: Control, corner: float = 6.0) -> void:
	if host == null:
		return
	var existing := host.get_node_or_null("__edge_light") as EdgeOverlay
	if existing != null:
		existing.corner = corner
		existing.queue_redraw()
		return
	var ov := EdgeOverlay.new()
	ov.name = "__edge_light"
	ov.light = EDGE_LIGHT
	ov.shade = EDGE_SHADE
	ov.corner = corner
	host.add_child(ov)
	# 亮边画在底色之上、内容之下
	host.move_child(ov, 0)


## 一步上光影：现有 StyleBoxFlat 加柔和投影 + 受光细亮边
static func elevate(host: Control, level: int = ELEV_CARD, corner: int = 6) -> Control:
	if host == null:
		return host
	for key in ["panel", "normal"]:
		var flat := host.get_theme_stylebox(key) as StyleBoxFlat
		if flat == null:
			continue
		var mine := flat.duplicate() as StyleBoxFlat
		apply_elevation(mine, level)
		host.add_theme_stylebox_override(key, mine)
	edge_light(host, float(corner))
	return host


# ===================== 设施主题 / 氛围素材 =====================

## 取设施主题（返回副本，调用方可放心改字段）
static func facility_style(id: String) -> Dictionary:
	var d: Variant = FACILITY_STYLES.get(id, {})
	if not (d is Dictionary):
		return {}
	var out: Dictionary = (d as Dictionary).duplicate()
	# 设施主题色是「识别色」不是「强调色」，统一收饱和，别和主按钮抢亮度
	if out.has("accent"):
		out["accent"] = muted(out["accent"], 0.30)
	return out


static var _ui_tex_cache: Dictionary = {}
static var _additive_mat: CanvasItemMaterial = null


## 带缓存的 UI 贴图读取（缺失返回 null，调用方自行跳过装饰）
static func ui_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _ui_tex_cache.has(path):
		return _ui_tex_cache[path] as Texture2D
	var tex := load(path) as Texture2D
	_ui_tex_cache[path] = tex
	return tex


## 加法混合材质（柔光 / 光点 / 符印都靠它，避免亮部被暗底压灰）
## 材质本身无状态，可安全共享。
static func additive_material() -> CanvasItemMaterial:
	if _additive_mat == null:
		_additive_mat = CanvasItemMaterial.new()
		_additive_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_mat


## 横向渐变（左 → 右），用于设施抬头 / 星图信息条
static func horizontal_gradient(left: Color, right: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, left)
	g.set_color(1, right)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.0, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 32
	return t


## 纵向渐变（上 → 下）
static func vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 32
	t.height = 256
	return t


## 氛围卡片底：深色半透明 + 主题色细边（信息条 / 浮层卡）
static func accent_card_style(accent: Color, bg_alpha: float = 0.86,
		border_alpha: float = 0.55, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.045, 0.075, bg_alpha)
	sb.border_color = Color(accent.r, accent.g, accent.b, border_alpha)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return apply_elevation(sb, ELEV_CARD) as StyleBoxFlat


## 设施圆形印记：有专属徽章用徽章，没有就显示单字印
static func facility_disc(style: Dictionary, disc_size: float = 44.0) -> Control:
	var accent: Color = style.get("accent", C_ACCENT)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(disc_size, disc_size)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := glow_node(Vector2(disc_size * 1.8, disc_size * 1.8), accent, 0.26)
	glow.position = Vector2.ONE * (disc_size * 0.5 - glow.size.x * 0.5)
	holder.add_child(glow)

	var disc := PanelContainer.new()
	disc.custom_minimum_size = Vector2(disc_size, disc_size)
	disc.size = Vector2(disc_size, disc_size)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.045, 0.075, 0.94)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.58)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(disc_size * 0.5))
	disc.add_theme_stylebox_override("panel", sb)
	holder.add_child(disc)

	var medallion := ui_texture(String(style.get("medallion", "")))
	if medallion != null:
		var art := TextureRect.new()
		art.texture = medallion
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(art)
	else:
		var glyph := String(style.get("glyph", "◆"))
		var l := label(glyph, int(disc_size * 0.42), accent)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(l)
	return holder


## 小进度条：熟练度 / 收藏度等辅助信息，不放百分比文字
static func mini_progress(ratio: float, color: Color = C_ACCENT,
		bar_size := Vector2(110, 6)) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = bar_size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.035, 0.04, 0.06, 0.9)
	bg.border_color = Color(color.r, color.g, color.b, 0.22)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(bar_size.y * 0.5))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(color.r, color.g, color.b, 0.88)
	fill.set_corner_radius_all(int(bar_size.y * 0.5))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## 小状态签：淡色圆角底 + 同色文字（可挑战 / 已通关 / 未开放）
static func chip(text: String, color: Color, size: int = F_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	var soft := muted(color, 0.26)
	sb.bg_color = Color(soft.r, soft.g, soft.b, 0.12)
	sb.border_color = Color(soft.r, soft.g, soft.b, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, size, muted(color, 0.10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## 压在插画 / 星图 / 战斗场景上的文字：**柔和投影优先，描边最多 1px**。
## 2026-11-04 改版：原来默认 4px 粗描边，满屏字都像贴纸（页游感的主要来源）。
## 现在默认走「左上受光、右下投影」的柔影（与 LIGHT_FROM 同向），
## 只有背景确实太亮太花时才显式传 outline=1~2 补一条极细的边。
static func outlined_label(text: String, size: int, color: Color,
		outline: int = 0, outline_color: Color = Color(0.02, 0.03, 0.05, 0.55)) -> Label:
	var l := label(text, size, color)
	soft_text_shadow(l, outline)
	return l


## 给文字上柔和投影：影子沿光源反方向偏移，不靠加粗描边撑可读性
static func soft_text_shadow(l: Control, outline: int = 0) -> Control:
	if l == null:
		return l
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.46))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.55))
	l.add_theme_constant_override("outline_size", maxi(0, outline))
	return l


## 柔光块：一张径向渐变贴图 + 加法混合，颜色走 modulate
static func glow_node(size: Vector2, color: Color, alpha: float = 1.0,
		tex_path: String = TEX_GLOW_SOFT) -> TextureRect:
	var tex := ui_texture(tex_path)
	var r := TextureRect.new()
	if tex != null:
		r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = size
	r.size = size
	r.modulate = Color(color.r, color.g, color.b, alpha)
	r.material = additive_material()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ===================== 样式工厂 =====================

## 面板底：深色填充（金框由 apply_panel_frame 叠在上面）
## ⚠ 为什么分两层：panel_frame 贴图**内部是透明的**，只当 StyleBoxTexture 用会漏出场景。
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_BG
	# 层级靠「柔和投影 + 受光细亮边」建立，外框只留 1px 收边（金框贴图仍叠在上面）
	sb.border_color = Color(C_PANEL_BORDER.r, C_PANEL_BORDER.g, C_PANEL_BORDER.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	return apply_elevation(sb, ELEV_FLOAT) as StyleBoxFlat


## 给面板叠一层金色云纹框（贴图缺失时静默跳过 → 只剩深色底，不影响可用性）
## root 必须是 PanelContainer：框用 NinePatchRect 铺满它的矩形。
## 换框：覆盖 assets/ui/panel/panel_frame_9p.png（保持「只有边框、内部透明」）
static func apply_panel_frame(root: Control) -> void:
	if root == null:
		return
	if not ResourceLoader.exists(TEX_PANEL_FRAME):
		return
	# 防重复：同一个面板重复构建时不叠第二层
	var existing := root.get_node_or_null("__panel_frame")
	if existing != null:
		existing.queue_free()
	var np := NinePatchRect.new()
	np.name = "__panel_frame"
	np.texture = load(TEX_PANEL_FRAME)
	np.patch_margin_left = FRAME_PATCH_MARGIN
	np.patch_margin_right = FRAME_PATCH_MARGIN
	np.patch_margin_top = FRAME_PATCH_MARGIN
	np.patch_margin_bottom = FRAME_PATCH_MARGIN
	np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(np)


## 格子底：filled=true 用于有物品的格子
## 槽位底框样式
## border_color / border_width 用来给装备格染**品阶色**（见 grade_border_color）；
## 不传时保持旧外观（暗边 1px），老调用点无需改动。
##
## ⚠ content_margin 必须给：Button 的子节点默认从 (0,0) 开始绘制，
##   会把 stylebox 的边框**盖住**（表现为「代码设了品阶边，界面上看不到」）。
##   留 3px 内边距让内容缩进来，边框才露得出来；PanelContainer 用同一个样式也只会内缩，无害。
static func slot_style(filled: bool = false,
		border_color: Color = C_SLOT_BORDER, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SLOT_BG_FILLED if filled else C_SLOT_BG
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	# 槽位是贴在面板上的平面元素：不投影，最多 1px 边，靠底色明差分「空 / 有物」
	sb.shadow_size = 0
	return sb


## 把同一套槽位样式应用到控件的各个状态
## ⚠ 坑：**Button 读的是 "normal"，Panel 系控件读的是 "panel"**。
##   只设 "panel" 的话 Button 会用引擎默认样式（1px 暗边），
##   表现为「代码里样式明明设了，界面上看不到」——所以这里两类名字都设上，
##   用不到的 override 无害。
## 另外 hover 设成描金边、pressed 压暗，避免鼠标划过时样式「眨眼」。
static func apply_slot_style(control: Control, sb: StyleBoxFlat) -> void:
	if control == null:
		return
	for state in ["panel", "normal", "disabled"]:
		control.add_theme_stylebox_override(state, sb)
	var hover := sb.duplicate() as StyleBoxFlat
	if hover != null:
		hover.border_color = C_ACCENT
	control.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate() as StyleBoxFlat
	if pressed != null:
		pressed.bg_color = pressed.bg_color.lightened(0.12)
	control.add_theme_stylebox_override("pressed", pressed)


## 品阶描边色：空品阶（材料 / 空格）用默认暗边，避免满屏彩色边框
static func grade_border_color(grade: String) -> Color:
	if grade == "":
		return C_SLOT_BORDER
	return grade_color(grade)


## 槽位内容内衬：**Button 不会自动按 stylebox 的 content_margin 排布子节点**，
## 直接 add_child 的内容会从 (0,0) 开始画，把品阶边框盖住。
## 所以格子（Button）里装内容时，先套一层这个 MarginContainer。
## PanelContainer 会自己处理 margin，不需要它。
static func slot_padding() -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", SLOT_PADDING)
	mc.add_theme_constant_override("margin_right", SLOT_PADDING)
	mc.add_theme_constant_override("margin_top", SLOT_PADDING)
	mc.add_theme_constant_override("margin_bottom", SLOT_PADDING)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mc


# ===================== 点击音效（2026-10-22 用户定）=====================
## 所有点击都要有声音，且音色/音量统一（全部走 GameState.play_ui，峰值已归一化）。
## 默认 ui_click；页签、领取之类想换音色就调 set_click_sfx()，连接不用改。
## 音效本体在 GameState._ui_cache 里（同一合成器生成，见那边的四条口径）。
const META_CLICK_SFX := "_click_sfx"


## 给按钮挂点击音效（重复调用安全，不会重复连接）
## ⚠ 用 root 查 GameState 而不是直接写 GameState：本类是静态工具类，
##   静态上下文里访问 autoload 在面板 _init 阶段并不可靠。
static func attach_click_sfx(b: BaseButton, sfx: String = "ui_click") -> void:
	if b == null or b.has_meta("_click_sfx_bound"):
		return
	b.set_meta("_click_sfx_bound", true)
	b.set_meta(META_CLICK_SFX, sfx)
	b.pressed.connect(func() -> void:
		_play_ui(String(b.get_meta(META_CLICK_SFX, "ui_click")))
	)
	# 禁用态也给个闷响：引擎不会为 disabled 按钮发 pressed，
	# 否则玩家按了"没反应"（其实是被禁用）会以为界面卡了
	b.gui_input.connect(func(e: InputEvent) -> void:
		if not b.disabled:
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_play_ui("ui_deny")
	)


## 换这个按钮的点击音色（attach 之后再调也有效：回调每次现读 meta）
static func set_click_sfx(b: BaseButton, sfx: String) -> void:
	if b == null:
		return
	b.set_meta(META_CLICK_SFX, sfx)


static func _play_ui(sfx: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("play_ui"):
		gs.call("play_ui", sfx)


# ===================== 控件工厂 =====================

## 小字统一放大一档（2026-10-27 用户反馈：设施界面里的小字看着费劲）。
##
## 为什么放在 label() 这一个入口而不是改各处的字号常量：
##   设施面板里散落着 7–13 的字面量（角标、行注、表头、提示），
##   逐个改容易漏、也容易在别处改重。这里只把小字区间抬一档：
##   大字（≥15 的标题 / 分节）完全不动，所以版式高度基本不变。
##   映射：7→9、8→10、9→11、10→12、11→12、12→13、13→14。
##   7/8 这一档多是槽位角标与「层」之类的符号，也只抬 2px，不动版式。
## 给「直接设字号」的控件（按钮 / 特殊 Label）套用同一套小字放大规则
static func set_readable_font(c: Control, size: int) -> void:
	if c == null:
		return
	c.add_theme_font_size_override("font_size", readable_size(size))


static func readable_size(size: int) -> int:
	match size:
		7: return 9
		8: return 10
		9: return 11
		10: return 12
		11: return 12
		12: return 13
		13: return 14
	return size


static func label(text: String, size: int = F_BODY, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", readable_size(size))
	l.add_theme_color_override("font_color", color)
	return l


## ===== 阅读字体（2026-10-24 用户定）=====
## 三极泼墨体只用于标题 / 按钮 / 短标签；长说明、详情、指引正文改回系统无衬线，
## 小字号下更容易读。不要直接改全局字体，也不要给每个面板单独换字体。
static var _readable_font: Font = null

static func readable_font() -> Font:
	if _readable_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC",
			"WenQuanYi Micro Hei", "sans-serif",
		])
		f.allow_system_fallback = true
		_readable_font = f
	return _readable_font


## 把一个控件（Label / RichTextLabel 等）切到阅读字体
static func make_readable(control: Control) -> Control:
	if control != null:
		control.add_theme_font_override("font", readable_font())
	return control


static func readable_label(text: String, size: int = F_BODY, color: Color = C_TEXT) -> Label:
	var l := label(text, size, color)
	make_readable(l)
	return l


static func readable_note(text: String) -> Label:
	var l := note(text)
	make_readable(l)
	return l


## 卷首/说明卡：深墨底 + 左侧主题色墨条，替代一段裸露的灰字
static func note_card(text: String, accent: Color = C_ACCENT) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := accent_card_style(accent, 0.66, 0.26, 6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", sb)
	var row := hbox(9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var bar := ColorRect.new()
	bar.color = Color(accent.r, accent.g, accent.b, 0.82)
	bar.custom_minimum_size = Vector2(2, 0)
	bar.size_flags_vertical = Control.SIZE_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var l := readable_label(text, F_SMALL, Color(0.78, 0.79, 0.84, 0.96))
	# 说明卡经常要塞整段规则（例如两仪势的七行说明）：不换行就会溢出卡片宽度
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return card


## 一级：标题（暖宣纸，低饱和；亮度让给主按钮与数字）
static func title(text: String) -> Label:
	return label(text, F_TITLE, C_TITLE)


static func subtitle(text: String) -> Label:
	return label(text, F_SUBTITLE, muted(C_ACCENT, 0.42))


static func section(text: String, accent: Color = C_ACCENT) -> HBoxContainer:
	var row := hbox(8)
	row.add_child(_section_seal(accent))
	var l := label(text, F_SECTION, C_TITLE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var soft := muted(accent, 0.30)
	var line := TextureRect.new()
	line.texture = horizontal_gradient(
		Color(soft.r, soft.g, soft.b, 0.26),
		Color(soft.r, soft.g, soft.b, 0.0)
	)
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row


## 章节标题前的小朱印：比纯文字/横线更有「卷册」感，也不占操作空间
static func _section_seal(accent: Color) -> Control:
	var tex := ui_texture(TEX_SEAL_MARK)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(15, 15)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var seal := TextureRect.new()
		seal.texture = tex
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seal.modulate = Color(1.0, 1.0, 1.0, 0.92)
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(seal)
	else:
		var bar := ColorRect.new()
		bar.color = Color(accent.r, accent.g, accent.b, 0.9)
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.offset_right = -9
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bar)
	return holder


## 三级：注释 / 说明（最暗一档，不与正文抢）
static func note(text: String) -> Label:
	var l := label(text, F_SMALL, C_TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 全局文字按钮：默认使用 InkButton 水墨皮肤（见 scripts/ui/ink_button.gd）
## tone：default / primary / paper / danger / quiet / tab
## 旧调用点只传 text / min_size 也自动升级，不需要逐个改。
static func button(text: String, min_size := Vector2.ZERO,
		tone: String = "default", accent_color: Color = C_ACCENT) -> Button:
	var script := load("res://scripts/ui/ink_button.gd")
	var b := script.new() as Button
	if b == null:
		return null
	b.text = text
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	b.call("setup", tone, accent_color)
	# 所有走工厂的按钮自动带点击音效（2026-10-22 用户定）
	attach_click_sfx(b)
	return b


## 主操作（朱印）：突破 / 开炉 / 执笔 / 踏入 / 确认 / 挑战
static func primary_button(text: String, min_size := Vector2.ZERO,
		accent_color: Color = C_ACCENT) -> Button:
	return button(text, min_size, "primary", accent_color)


## 行内轻操作（无底笔字）：卸下 / 装配 / 回放
static func quiet_button(text: String, min_size := Vector2.ZERO,
		accent_color: Color = C_ACCENT) -> Button:
	return button(text, min_size, "quiet", accent_color)


## 危险操作（血印）：删除 / 丢弃 / 返回登录
static func danger_button(text: String, min_size := Vector2.ZERO,
		accent_color: Color = C_ACCENT) -> Button:
	return button(text, min_size, "danger", accent_color)


## 浅色纸面上的墨字纸签
static func paper_button(text: String, min_size := Vector2.ZERO,
		accent_color: Color = C_ACCENT) -> Button:
	return button(text, min_size, "paper", accent_color)


## 书签 / 分类页签：选中态换成米纸签 + 墨字
static func tab_button(text: String, min_size := Vector2.ZERO,
		accent_color: Color = C_ACCENT) -> Button:
	return button(text, min_size, "tab", accent_color)


## 统一设置页签的选中态（不再用 modulate 压暗，避免选中/未选中共用同一套文字色）
static func set_tab_selected(b: Button, selected: bool) -> void:
	if b == null:
		return
	if b.has_method("set_selected"):
		b.call("set_selected", selected)
	else:
		b.modulate = Color.WHITE if selected else Color(0.62, 0.62, 0.68)



static func vbox(sep: int = 6) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", sep)
	return c


static func hbox(sep: int = 8) -> HBoxContainer:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", sep)
	return c


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


## 键值行：左键右值，值右对齐
## 数字级：右对齐、阅读字体、不加描边也不加粗，靠明度而不是颜色抢注意力
static func num_label(text: String, size: int = F_BODY, color: Color = C_NUM) -> Label:
	var l := readable_label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func stat_row(key: String, value: String, value_color: Color = C_NUM) -> HBoxContainer:
	var row := hbox(10)
	var k := label(key, F_BODY, C_TEXT_DIM)
	row.add_child(k)
	row.add_child(spacer())
	row.add_child(num_label(value, F_BODY, value_color))
	return row


## 全屏遮罩：半透明 + 拦截点击
static func dim_rect() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, DIM_ALPHA)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


# ===================== 图标占位 =====================

## 图标画布留白缓存：装备原画在 256 画布里常常只占中间一小块（实测青锋剑 45%），
## 直接缩放显示会「看着只有格子一半大」。裁掉透明边只影响显示，不动素材文件。
static var _trim_cache: Dictionary = {}


static func trimmed_texture(path: String) -> Texture2D:
	if _trim_cache.has(path):
		return _trim_cache[path] as Texture2D
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		_trim_cache[path] = tex
		return tex
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0 or used.size == img.get_size():
		_trim_cache[path] = tex
		return tex
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(used)
	_trim_cache[path] = at
	return at


## 物品/功法图标：填了 icon 就显示贴图，没填就用「类型色块 + 首字」占位
## 美术接入时只需在数据里补 icon 路径，这里不用改
## trim=true 会裁掉画布留白让图形填满格子（装备原画留白多的地方用）
static func icon_node(icon_path: String, display_name: String, type: String = "",
		size: Vector2 = Vector2(48, 48), trim: bool = false) -> Control:
	# ⚠ 图标是纯装饰，所有层级都必须 IGNORE：
	#   格子中心的图标若吃到鼠标，会抢走拖拽起点/拖放落点，表现为「只能拖边框」。
	var holder := CenterContainer.new()
	holder.custom_minimum_size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex: Texture2D = trimmed_texture(icon_path) if trim else load(icon_path)
		if tex != null:
			var tex_rect := TextureRect.new()
			tex_rect.texture = tex
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = size
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(tex_rect)
			return holder

	# 占位：类型色块 + 名称首字
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = TYPE_COLOR.get(type, C_SLOT_BG)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)

	var initial := display_name.substr(0, 1) if display_name.length() > 0 else "?"
	var l := label(initial, F_SECTION, Color(0.95, 0.95, 0.95, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)

	holder.add_child(panel)
	return holder


## 装备图标 = icon_node + 右下角强化角标（+N）
## 所有显示装备的地方（锻造台素材格 / 背包 / 已穿戴格 / 持有装备行）都走这一个函数，
## 保证「有强化就一定看得到角标」，不会这边加了那边忘了。
## 没有 icon 路径时仍是占位色块，所以没接美术也能跑。
static func equip_icon(item: Dictionary, size: Vector2, trim: bool = false) -> Control:
	var box := Control.new()
	box.custom_minimum_size = size
	# ⚠ 必须收缩而不是撑满：Control 默认 size_flags_horizontal = FILL，
	#   在 HBox 里会被拉宽，右下角角标会被带到很远的地方（看起来「角标不见了」）。
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# 同理，纵向也要收缩：HBox 会按最高的子节点统一高度，
	# 不收缩的话图标块会被文字行拉高，右下角角标跟着跑偏。
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var itype := String(item.get("equipment_type", ""))
	box.add_child(icon_node(
		String(item.get("icon", "")),
		String(item.get("name", "")),
		"treasure" if itype == "treasure" else "equipment",
		size,
		trim
	))
	var enh := maxi(0, int(item.get("enhancement_level", 0)))
	if enh > 0:
		box.add_child(enhance_badge(enh))
	return box


## 强化角标：图标右下角的「+N」小牌子
static func enhance_badge(level: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 1

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ENHANCE_BG
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", sb)

	var l := label("+%d" % level, F_BADGE, C_ENHANCE_TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(l)

	# 贴到父控件右下角：四个锚点都设 1，再用 offset 拉回来；
	# grow 设成 BEGIN 让它向左上方生长，否则会溢出父控件
	badge.anchor_left = 1.0
	badge.anchor_top = 1.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_left = -34.0
	badge.offset_top = -15.0
	badge.offset_right = -1.0
	badge.offset_bottom = -1.0
	return badge


# ===================== 工具 =====================

static func clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


static func percent_text(v: float) -> String:
	return "%.0f%%" % (v * 100.0)


## 品阶文字 / 边框着色（数据口径见上面的 GRADE_COLORS 七色环）
## 未登记品阶（材料、空格）回落到默认文字色
static func grade_color(grade: String) -> Color:
	return GRADE_COLORS.get(grade, C_TEXT)
