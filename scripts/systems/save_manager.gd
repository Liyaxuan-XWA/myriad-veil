extends Node
## 存档管理器（任务书 §5.8 存档数据）
##
## 槽位规则（用户确认）：
##   - 共 5 个槽；第 1–4 槽为自动存档槽，每次回到主城时轮流覆盖（1→2→3→4→1）
##   - 第 5 槽为手动存档槽，只有手动存档才会覆盖它
##   - 游戏内点「返回登录界面」/ 主城 ESC 确认返回时，先自动存档再切回开始界面
##
## 序列化格式：JSON。所有业务数据本就是 Dictionary / Array，天然适配。
## ⚠ JSON 的 key 只能是字符串，所以 int 键字段（塔层号、药田地块号）存取时需转换，
##   否则存进去是 1，读出来变成 "1"，用 int 索引就查不到。

const SAVE_VERSION := 1
const SLOT_COUNT := 5
const AUTO_SLOT_COUNT := 4
const MANUAL_SLOT := 5

## ===================== 覆盖前备份（2026-10-22 用户报「存档没了」后加）=====================
## 事故链：自动档每次进主城轮换写 1–4 槽；只要有一次是**新开局**（读档失败/点了新游戏），
##   连进 4 次主城就把 4 个槽全盖成空档，且磁盘上没有任何副本可以回滚。
## 现在两道保险：
##   ① 每次覆盖某槽前，先把旧文件复制成 `save_slot_N.bak.json`（只留上一版）
##   ② 自动存档遇到空档（新开局）**直接不写、也不占槽位** —— 新局绝不允许冲掉旧进度，
##      更不该把第 1 槽轮转掉（2026-10-26 修：空白快照 + 每局指针归 1 = 第 1 槽永远写不进去）
## 设置面板「读取/删除」旁边会多一个「恢复备份」按钮（有备份时才有）。
const BACKUP_SUFFIX := ".bak"

## 下一个自动存档要写入的槽（1..4 轮转）
var _next_auto_slot: int = 1

## 刚读完档 → 下一次 auto_save 直接跳过。
## ⚠ 主城场景 _ready 就会 auto_save。启动流程是「读档 → 切主城」，如果不跳过，
##   每启动一次就白写一槽（内容与盘上完全一样），四个自动槽会被同一份内容轮转占满，
##   真正的历史版本反而被挤掉。
var _skip_next_autosave := false

## ===================== 测试保护开关 =====================
## ⚠ 为什么需要：主城场景 _ready 就会自动存档，跑自动化测试/截图脚本时会反复
##   覆盖玩家的自动存档槽（实测存在误覆盖风险）。测试脚本在实例化场景前关掉即可。
## 自动存档开关（默认开启）：false 时 auto_save() 直接跳过，一个字节都不写
var auto_save_enabled := true
## 全局写盘开关（默认开启）：false 时**所有**写入都被拒绝（含手动存档槽），最保险
var write_enabled := true


func _ready() -> void:
	# 命令行保险：`godot -- --no-save` 启动时彻底禁止写盘，冒烟/截图脚本用这个最省事
	if OS.get_cmdline_user_args().has("--no-save"):
		disable_saving()
		print("[SaveManager] 已启用 --no-save：本次运行不写任何存档")


## 测试脚本用：一次性关闭全部写盘（等价于命令行 --no-save）
func disable_saving() -> void:
	auto_save_enabled = false
	write_enabled = false


func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


## 覆盖前备份的路径（上一版内容）
func backup_path(slot: int) -> String:
	return "user://save_slot_%d%s.json" % [slot, BACKUP_SUFFIX]


## 该槽有没有可用的备份文件
func has_backup(slot: int) -> bool:
	return FileAccess.file_exists(backup_path(slot))


## 文件级复制（备份用）：读不到源文件返回 false
func _copy_file(src: String, dst: String) -> bool:
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return false
	var w := FileAccess.open(dst, FileAccess.WRITE)
	if w == null:
		return false
	w.store_string(text)
	w.close()
	return true


## 读一个存档文件为字典（失败/不存在返回 {}）
func _read_slot_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	return parsed


## 这一档是不是「什么都没做过」的空档（新开局）
## 用于拦住「新局自动存档覆盖旧进度」——只要有任何一处进度痕迹就不算空档
func is_blank_run(snap: Dictionary) -> bool:
	for key in ["boss_progress", "domain_progress", "tower_progress", "story_progress",
			"memory_progress", "home_progress", "tilled_plots", "obtained_souls", "pill_data", "talisman_data",
			"quest_data"]:
		var v = snap.get(key, {})
		if v is Dictionary and not (v as Dictionary).is_empty():
			return false
	# 大世界进度：默认结构里就有三个空子字典，不能只看外层是否为空
	var world = snap.get("secret_world", {})
	if world is Dictionary:
		for key in ["core_kills", "nodes", "cultivators", "god_altars"]:
			var sub = (world as Dictionary).get(key, {})
			if sub is Dictionary and not (sub as Dictionary).is_empty():
				return false
	var skills = snap.get("skill_data", {})
	if skills is Dictionary:
		for k in ["learned_skills", "active_skill_loadout", "passive_skill_loadout"]:
			var arr = (skills as Dictionary).get(k, [])
			if arr is Array and not (arr as Array).is_empty():
				return false
	var inv = snap.get("inventory_data", [])
	# 背包里有任何一件就说明动过手（新手铁剑在装备槽，不在背包里，已由 _is_starter_equipment 排除）
	if inv is Array and not (inv as Array).is_empty():
		return false
	# 仓库（2026-11-02 起独立存储）里有东西同样算进度
	var whd = snap.get("warehouse_data", [])
	if whd is Array and not (whd as Array).is_empty():
		return false
	# 符匣里有一张符也算进度（符箓不占背包格）
	var stock = snap.get("talisman_stock", {})
	if stock is Dictionary and not (stock as Dictionary).is_empty():
		return false
	for key in ["equipment_data", "treasure_data"]:
		var d = snap.get(key, {})
		if d is Dictionary:
			for k in (d as Dictionary).keys():
				var item = (d as Dictionary)[k]
				# ⚠ 新手自带装备不算进度。新开局就装备着铁剑（ItemDB 里 is_starting_equipment = true），
				#   旧写法「任何非空装备槽都算有进度」会让新号永远不像空档，
				#   于是空白快照能一路覆盖真实存档（2026-10-26 用户报「自动存档没写进第 1 槽」）。
				if item != null and not _is_starter_equipment(item):
					return false
	if float(snap.get("origin_energy", 0.0)) > 0.0:
		return false
	var realm = snap.get("realm_data", {})
	if realm is Dictionary:
		# 修为清零（刚突破）但境界 / 阶段已经推进的存档，同样不能算空档
		var saved_realm := CharacterData.normalize_realm_name(
			String((realm as Dictionary).get("current_realm", "练气")))
		if saved_realm != "练气" or int((realm as Dictionary).get("realm_stage", 0)) > 0:
			return false
		if int((realm as Dictionary).get("realm_exp", 0)) > 0:
			return false
		# 旧档字段：0.0~1.0 的小阶段进度
		if float((realm as Dictionary).get("realm_progress", 0.0)) > 0.0:
			return false
	var chapter := String(snap.get("chapter_state", ""))
	if chapter != "" and chapter != "第一篇章 · 未启":
		return false
	return true


## 这件装备是不是「新手自带」（铁剑）。查 ItemDB 的 is_starting_equipment 标记，
## 不硬编码 id —— 以后新手套装加东西，这里自动跟着走。
## 存档里的装备是完整字典（没有那个标记），只能按 id 回查模板。
static func _is_starter_equipment(item) -> bool:
	if not (item is Dictionary):
		return false
	var id := String((item as Dictionary).get("id", ""))
	if id == "":
		return false
	for tpl in ItemDB.EQUIPMENT_TEMPLATES:
		if String((tpl as Dictionary).get("equipment_id", "")) == id:
			return bool((tpl as Dictionary).get("is_starting_equipment", false))
	return false


## 从备份恢复某槽：把 .bak 复制回主文件并读取
func restore_backup(slot: int) -> bool:
	if not has_backup(slot):
		return false
	if not _copy_file(backup_path(slot), slot_path(slot)):
		return false
	return load_slot(slot)


# ===================== 序列化 =====================

## src 传别的 CharacterData 实例时按那份数据取快照（开新存档要用「出厂实例」覆盖当前单例）
func capture(src = null) -> Dictionary:
	var d = CharacterData if src == null else src
	return {
		"save_version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		# §5.8 realm_data
		"realm_data": {
			"current_realm": d.current_realm,
			"realm_stage": d.realm_stage,
			"realm_exp": d.realm_exp,
			"original_world_max_realm": d.original_world_max_realm,
			"current_world_realm_limit": d.current_world_realm_limit,
			# 九天门开过没有：没存这个位，玩家回档就会拿着已被门吃掉的钥匙卡在化神前
			"huashen_gate_opened": d.huashen_gate_opened,
		},
		# §5.8 player_state
		"player_state": {
			"character_name": d.character_name,
			# 属性改为整表存取：新增属性不会破坏旧档
			# ⚠ 必须深拷贝：否则快照与运行时共用同一个 Dictionary，
			#   之后改角色属性会把快照一起改掉，capture→apply 就不再有还原效果
			"base_attributes": d.base_attributes.duplicate(true),
			"cultivation_state": d.cultivation_state.duplicate(true),
			"unlocked_abilities": d.unlocked_abilities.duplicate(true),
		},
		# §5.8 equipment_data（装备槽内容可能为 null，JSON 支持）
		"equipment_data": d.equipment_slots.duplicate(true),
		# 法宝槽位（与装备分开存，便于单独扩展）
		"treasure_data": d.treasure_slots.duplicate(true),
		# 开局装备/法宝发放标记（防止读档后被重新补发）
		"starting_equipment_granted": d.starting_equipment_granted,
		"starting_treasure_granted": d.starting_treasure_granted,
		# 物品：装备 / 丹药 / 材料存在 inventory
		"inventory_data": d.inventory.duplicate(true),
		# 仓库：独立存储空间，不与背包混用（2026-11-02）
		"warehouse_data": d.warehouse.duplicate(true),
		# 符箓库存：只有 id -> 张数，不占背包格
		"talisman_stock": d.talisman_stock.duplicate(true),
		# 图鉴永久解锁记录：{ item_id: true }
		"codex_data": d.codex_unlocked.duplicate(true),
		# §5.8 skill_data
		"skill_data": {
			"learned_skills": d.learned_skills.duplicate(true),
			"new_skill_ids": d.new_skill_ids.duplicate(true),
			"active_skill_loadout": d.active_skill_loadout.duplicate(true),
			"passive_skill_loadout": d.passive_skill_loadout.duplicate(true),
		},
		# §5.8 pill_data / talisman_data / home_progress
		"pill_data": d.alchemy_progress.duplicate(true),
		"talisman_data": d.talisman_crafting_progress.duplicate(true),
		"home_progress": _keys_to_str(d.home_progress),
		"tilled_plots": _keys_to_str(d.tilled_plots),
		# 战斗轮盘装配（2026-10-24）：六个槽位 → 物品 id
		"quick_slots": d.quick_slots.duplicate(true),
		# §5.8 domain_progress / boss_progress / tower_progress
		# 背包「首次获得」红点：见过 / 还没看过（旧档没有 → _apply 里按现有物品补种）
		"bag_seen_ids": d.bag_seen_ids.duplicate(true),
		"bag_new_ids": d.bag_new_ids.duplicate(true),
		"domain_progress": d.domain_progress.duplicate(true),
		"boss_progress": d.boss_progress.duplicate(true),
		# BOSS 连败提醒计数（键是字符串，不用转义）；旧存档没有 → 空字典
		"boss_fail_streak": d.boss_fail_streak.duplicate(true),
		# 位面 BOSS 累计死亡 / 首通死亡快照；旧存档没有 → 空字典
		"boss_death_count": d.boss_death_count.duplicate(true),
		"boss_first_clear_deaths": d.boss_first_clear_deaths.duplicate(true),
		# 万界塔各层最快通关时间（秒）；key 是 int（JSON 只认字符串键，读档时转回）
		"tower_best_time": _keys_to_str(d.tower_best_time),
		# 试炼之路（肉鸽爬塔）元进度：历史最高层 / 累计局数；旧存档没有 → 0
		"rogue_data": {
			"best_floor": d.rogue_best_floor,
			"runs": d.rogue_runs,
		},
		# 新手指引进度：{done:{step_id:true}, seen_items, seen_codex, legacy}
		"tutorial_data": d.tutorial_data.duplicate(true),
		# 顺序任务面板进度：{done:{quest_id:true}}；旧存档没有 → 空字典（任务从头亮起）
		"quest_data": d.quest_data.duplicate(true),
		# 无伤通关奖励状态（"ready" / "claimed"）；旧存档没有 → 空字典
		"tower_no_hit_reward": _keys_to_str(d.tower_no_hit_reward),
		# 无伤通关双倍气血的层（纯华彩卡解锁）；旧存档没有 → 空字典
		"tower_no_hit_double": _keys_to_str(d.tower_no_hit_double),
		# 大世界核心首领重战：次数 / 双倍无伤 / 无伤奖励；旧存档没有 → 空字典
		"core_replay": d.core_replay.duplicate(true),
		# 卡包卡序（第一位是封面）；旧存档没有 → 空字典
		"card_order": d.card_order.duplicate(true),
		# 对局卡面种类（显示偏好）；旧存档没有 → ""（跟随卡包）
		"match_card_kind": d.match_card_kind,
		# 棋坛关卡进度（已通关的最高关号）；旧存档没有 → 0（当前关 = 第 1 关）
		"match_level_cleared": d.match_level_cleared,
		"match_quick_mode": d.match_quick_mode,
		# 非普通卡解锁奖励领取记录；旧存档没有 → 空字典
		"card_reward_claimed": d.card_reward_claimed.duplicate(true),
		"tower_progress": _keys_to_str(d.tower_progress),
		# 万界秘境·大世界（核心首领击杀 / 资源与野外修士的重生状态）
		"secret_world": d.secret_world.duplicate(true),
		# 已获得过的元魂 id（每种元魂全局只掉一次）
		"obtained_souls": d.obtained_souls.duplicate(true),
		# §5.8 origin_energy / memory_progress / story_progress / chapter_state
		"origin_energy": d.origin_energy,
		"memory_progress": d.memory_progress.duplicate(true),
		"story_progress": d.story_progress,
		"chapter_state": d.chapter_state,
	}


func apply(snap: Dictionary) -> void:
	var d := CharacterData

	var realm: Dictionary = snap.get("realm_data", {})
	# 境界名迁移（2026-10-23：金丹 → 结丹）。旧档 JSON 里的旧名必须在这里换掉，
	# 否则 REALM_ORDER.find() 返回 -1，界面上会出现「第 0 / 5 阶」且无法突破。
	d.current_realm = CharacterData.normalize_realm_name(String(realm.get("current_realm", d.current_realm)))
	# 旧档还没有「前期/中期/后期」阶段字段，一律从前期开始（保存的进度直接沿用）
	d.realm_stage = clampi(int(realm.get("realm_stage", 0)), 0, CharacterData.REALM_STAGES.size() - 1)
	d.realm_exp = _migrate_realm_exp(realm)
	# 2026-11-01 化神不再分小阶段：旧档若停在化神某阶段，统一落到单阶段，并吃 99,999 上限
	if d.current_realm == CharacterData.REALM_HUASHEN:
		d.realm_stage = 0
		d.realm_exp = mini(d.realm_exp, CharacterData.HUASHEN_EXP_CAP)
	d.original_world_max_realm = CharacterData.normalize_realm_name(
		String(realm.get("original_world_max_realm", d.original_world_max_realm)))
	d.current_world_realm_limit = CharacterData.normalize_realm_name(
		String(realm.get("current_world_realm_limit", d.current_world_realm_limit)))
	# 2026-11-01 境界上限改为「最多到化神」：旧档的元婴上限不再挡住大突破
	if d.current_world_realm_limit == "元婴":
		d.current_world_realm_limit = CharacterData.REALM_HUASHEN
	d.huashen_gate_opened = bool(realm.get("huashen_gate_opened", d.huashen_gate_opened))
	# 旧档兼容：2026-11-02 之前化神是在境界面板点的、没有山门这个位，
	#   已经化神的存档必须视为「门开过」，否则九天之上永远进不去。
	if d.current_realm == CharacterData.REALM_HUASHEN:
		d.huashen_gate_opened = true
	var legacy_save := not realm.has("realm_stage")

	var player: Dictionary = snap.get("player_state", {})
	d.character_name = String(player.get("character_name", d.character_name))
	# 属性：新档有 base_attributes；旧档只有 base_max_hp / base_max_stamina / base_max_mana 等
	# 逐字段回填，缺失的沿用当前默认值（不会把老档属性抹成 0）
	var saved_attrs = player.get("base_attributes", {})
	if saved_attrs is Dictionary and not saved_attrs.is_empty():
		for k in saved_attrs.keys():
			d.base_attributes[String(k)] = float(saved_attrs[k])
	else:
		_migrate_legacy_player_stats(d, player)
	# 2026-10-24 调整了练气基础值（力量 12→10 / 灵力 60→50 / 双抗 0→10）。
	# 旧档存的是**旧的基础值**、且没有境界成长字段，直接重置为当前默认值，
	# 否则老玩家会永远停在旧数值上。
	if legacy_save:
		for k in CharacterData.REALM_GROWTH_ATTRS:
			d.base_attributes[k] = float(CharacterData.BASE_ATTRIBUTE_DEFAULTS[k])
	d.cultivation_state = player.get("cultivation_state", {})
	d.unlocked_abilities = player.get("unlocked_abilities", [])

	d.equipment_slots = snap.get("equipment_data", _empty_slots())
	_migrate_legacy_slots(d.equipment_slots)
	# 槽位缺字段时补齐，防止旧档结构不完整
	for slot in CharacterData.SLOT_ORDER:
		if not d.equipment_slots.has(slot):
			d.equipment_slots[slot] = null

	d.treasure_slots = snap.get("treasure_data", _empty_treasure_slots())
	for slot in CharacterData.TREASURE_SLOT_ORDER:
		if not d.treasure_slots.has(slot):
			d.treasure_slots[slot] = null
	# 法宝已并入装备体系（2026-10-17）：旧档里的法宝是 type="treasure" 的老结构，
	# 这里补齐成装备实例结构，否则它无法进背包、无法上砧强化。
	d.migrate_legacy_treasures()
	# 旧档没有这个字段：视为「已发过」，避免读档时凭空多出一把铁剑。
	# 默认值给 true 而不是 false，是为了让老存档保持原样（它们本来就没有开局装备）。
	d.starting_equipment_granted = bool(snap.get("starting_equipment_granted", true))
	# 旧档没有法宝字段：视为「已发过」，避免读档时凭空多出一件法宝
	d.starting_treasure_granted = bool(snap.get("starting_treasure_granted", true))

	d.inventory = snap.get("inventory_data", [])
	# 仓库：2026-11-02 起独立于背包。旧档没有这个字段 → 空仓库，背包物品原地不动
	d.warehouse = []
	var wh = snap.get("warehouse_data", [])
	if wh is Array:
		for raw_item in (wh as Array):
			if raw_item is Dictionary and not (raw_item as Dictionary).is_empty():
				d.warehouse.append((raw_item as Dictionary).duplicate(true))
	# 符匣库存：旧档没有这个字段，先读空，随后把背包里的符箓迁进来
	d.talisman_stock = {}
	var stock = snap.get("talisman_stock", {})
	if stock is Dictionary:
		for raw_id in (stock as Dictionary).keys():
			var tid := String(raw_id)
			var n := int((stock as Dictionary)[raw_id])
			if tid != "" and n > 0:
				d.talisman_stock[tid] = n
	# 丹药 / 符箓改版：物品 id 不变，但旧档里存的是旧名字与旧说明，
	# 读档时按数据表刷新显示字段（丹药加境界前缀等）。仓库里的副本同样要刷。
	_refresh_consumable_item_defs(d.inventory)
	_refresh_consumable_item_defs(d.warehouse)
	# 图标补录（2026-10-25）：旧档只存了早年的空 icon，按数据表把当前物品的图标补上。
	_refresh_all_item_icons(d)
	# 旧档装备类别别名规范化（2026-10-19：清风鞋的 "boots" → "shoes"）。
	# 只修 item_db 模板救不了旧存档 JSON——错误值会随读档原样带回，导致穿不上。
	d.migrate_legacy_equip_types()
	# 2026-11-01 法宝不带词条、只靠进阶成长：清旧实例的属性/普通强化/磨损/破损。
	# 必须在 inventory 与 treasure_slots 都读入之后调用。
	d.migrate_treasure_no_affixes()
	# 同种饰品只能戴一件（2026-10-31 新规）：旧档多戴的挪回背包
	d.migrate_duplicate_accessories()
	# 旧档绝对值词条 → 百分比词条（2026-10-19：清风剑 stamina_regen / 清风鞋 speed
	# 实测过量，改成 _pct 百分比词条；换算口径见 CharacterData.LEGACY_PCT_CONVERT）
	d.migrate_legacy_pct_attrs()
	# 2026-10-31 灵力恢复 ÷10：旧档基础值与装备词条一起折算（幂等）
	d.migrate_mana_regen_tenth()
	# 2026-10-31 旧烈火 / 磐石符下架：清物品、符方、图鉴与槽位
	d.migrate_remove_legacy_talismans()
	# 2026-11-01 符箓不再占背包：旧档背包里的符整堆迁进符匣
	d.migrate_talismans_to_cabinet()

	# 图鉴（2026-10-25）：先清空再读本档记录，避免切换存档时串档；
	# 旧档没有 codex_data 时，末尾按当前持有物自动补录。
	d.codex_unlocked = {}
	var codex = snap.get("codex_data", {})
	if codex is Dictionary:
		for key in (codex as Dictionary).keys():
			if bool((codex as Dictionary)[key]):
				d.codex_unlocked[String(key)] = true
	elif codex is Array:
		for key in codex:
			d.codex_unlocked[String(key)] = true

	var skill: Dictionary = snap.get("skill_data", {})
	d.learned_skills = skill.get("learned_skills", [])
	d.new_skill_ids = []
	for sid in skill.get("new_skill_ids", []):
		if String(sid) in d.learned_skills:
			d.new_skill_ids.append(String(sid))
	d.active_skill_loadout = skill.get("active_skill_loadout", [])
	d.passive_skill_loadout = skill.get("passive_skill_loadout", [])
	# 2026-10-30 用户定：被动功法只能带 1 门；旧档多带的保留第一门，其余卸下
	d.trim_passive_loadout()
	# 2026-10-29：玩家侧「日轮」改为被动「盗火者」。旧档若把它装在主动槽，
	# 这里自动挪到被动槽（只有 1 格；已被别的被动占用时不强行顶掉）。
	if "skill_sun_wheel" in d.learned_skills and "skill_sun_wheel" in d.active_skill_loadout:
		# 只清空它占的键位，不能让后面的技能整体前移
		var sun_slot := d.active_skill_loadout.find("skill_sun_wheel")
		if sun_slot >= 0:
			d.active_skill_loadout[sun_slot] = ""
		if not ("skill_sun_wheel" in d.passive_skill_loadout):
			if d.passive_skill_loadout.is_empty():
				d.passive_skill_loadout.append("skill_sun_wheel")

	d.alchemy_progress = snap.get("pill_data", {})
	d.talisman_crafting_progress = snap.get("talisman_data", {})
	d.home_progress = _keys_to_int(snap.get("home_progress", {}))
	d.tilled_plots = _keys_to_int(snap.get("tilled_plots", {}))
	# 轮盘：老存档没有这个字段，逐键合并到默认的六个空槽上
	var qs = snap.get("quick_slots", {})
	if qs is Dictionary:
		for sid in d.quick_slots.keys():
			d.quick_slots[sid] = String((qs as Dictionary).get(sid, ""))
	d.prune_quick_slots()
	# 2026-10-31：符箓改占 4 个功法格，旧轮盘符箓格直接清空（物品仍在背包）
	for old_talisman_slot in ["talisman_1", "talisman_2", "talisman_3"]:
		d.quick_slots.erase(old_talisman_slot)
	# 背包「首次获得」红点：新档照读；**旧档没有这两个键** → 现有物品一律算见过、不补红点
	var seen = snap.get("bag_seen_ids", null)
	var fresh = snap.get("bag_new_ids", null)
	if seen is Dictionary and fresh is Dictionary:
		d.bag_seen_ids = (seen as Dictionary).duplicate(true)
		d.bag_new_ids = (fresh as Dictionary).duplicate(true)
	else:
		d.bag_seen_ids = {}
		for raw in d.inventory:
			var it: Dictionary = raw
			d.bag_seen_ids[String(it.get("id", ""))] = true
		d.bag_new_ids = {}
	d.domain_progress = snap.get("domain_progress", {})
	d.boss_progress = snap.get("boss_progress", {})
	# 连败提醒计数：旧档没有这个字段 → 空字典（等于一只都没连败过）
	d.boss_fail_streak = snap.get("boss_fail_streak", {})
	# 位面 BOSS 死亡记录：旧档没有 → 空字典
	var death_counts = snap.get("boss_death_count", {})
	d.boss_death_count = (death_counts as Dictionary).duplicate(true) if death_counts is Dictionary else {}
	var clear_deaths = snap.get("boss_first_clear_deaths", {})
	d.boss_first_clear_deaths = (clear_deaths as Dictionary).duplicate(true) if clear_deaths is Dictionary else {}
	d.tower_best_time = _keys_to_int(snap.get("tower_best_time", {}))
	# 试炼之路元进度：旧存档没有 → 0（等于一局都没跑过）
	var rogue = snap.get("rogue_data", {})
	if rogue is Dictionary:
		d.rogue_best_floor = maxi(0, int((rogue as Dictionary).get("best_floor", 0)))
		d.rogue_runs = maxi(0, int((rogue as Dictionary).get("runs", 0)))
	else:
		d.rogue_best_floor = 0
		d.rogue_runs = 0

	# 新手指引：旧存档没有这个字段 → 标 legacy，不自动弹（用户 2026-11-10 定：
	# 老号不弹、可从小书重看）。空档（新号）保持空字典，Tutorial 会自动开第 1 章。
	var tut = snap.get("tutorial_data", null)
	if tut is Dictionary and not (tut as Dictionary).is_empty():
		d.tutorial_data = (tut as Dictionary).duplicate(true)
	elif is_blank_run(snap):
		d.tutorial_data = {}
	else:
		d.tutorial_data = {"legacy": true}
	# 旧「极速通关」状态不再迁移：奖励规则已改为无伤通关，旧 ready/claimed 一并作废
	# 顺序任务面板：旧存档没有这个字段 → 空字典（任务从头开始；cond 轮询会把
	# 「击败虎妖」这类存档级事实立刻补上勾）
	var qst = snap.get("quest_data", null)
	d.quest_data = (qst as Dictionary).duplicate(true) if qst is Dictionary else {}
	d.tower_no_hit_reward = _keys_to_int(snap.get("tower_no_hit_reward", {}))
	d.tower_no_hit_double = _keys_to_int(snap.get("tower_no_hit_double", {}))
	# 核心首领重战：旧存档没有 → 空字典（等于一次都没重战过）
	var cr = snap.get("core_replay", {})
	d.core_replay = (cr as Dictionary).duplicate(true) if cr is Dictionary else {}
	# 卡序：只保留 {boss_id: [card_id...]} 结构，坏档不至于让收藏册崩
	d.card_order = {}
	var stored_order = snap.get("card_order", {})
	if stored_order is Dictionary:
		for bid in (stored_order as Dictionary).keys():
			var arr = (stored_order as Dictionary)[bid]
			if arr is Array:
				d.card_order[String(bid)] = (arr as Array).duplicate()
	var claimed_cards = snap.get("card_reward_claimed", {})
	d.card_reward_claimed = (claimed_cards as Dictionary).duplicate(true) \
		if claimed_cards is Dictionary else {}
	# 对局卡面种类：旧档没有这个字段 → ""（跟随卡包封面）
	d.match_card_kind = snap.get("match_card_kind", "")
	# 棋坛关卡进度：旧档没这个键 → 0（还没打过，当前关就是第 1 关）。
	# 存档是玩家会直接改的边界，脏值（字符串 / null / 字典 / 负数）一律压回非负整数，
	# 否则负号会让「当前关」和长卷的预览窗口一起算歪。
	var raw_level: Variant = snap.get("match_level_cleared", 0)
	var level_v := 0
	if raw_level is String:
		level_v = int(String(raw_level))
	elif raw_level is int or raw_level is float:
		level_v = int(raw_level)
	d.match_level_cleared = maxi(level_v, 0)
	# 快速模式开关：旧档没这个键 → 关。
	# ⚠ 只认真布尔。`bool("false")` 的语义是"非空字符串即为真"，直接转会把玩家手改
	#   存档写的 "false" 读成开；而且本机这个 4.7.2 build **没有 bool() 构造函数**
	#   （和 Color.to_hsv / Rect2.intersects_and_clamp 同一类缺口，写了就是 parse error）。
	#   脏值一律压回关，比"猜他大概想开"安全。
	var raw_quick: Variant = snap.get("match_quick_mode", false)
	d.match_quick_mode = (raw_quick is bool and raw_quick == true)
	d.tower_progress = _keys_to_int(snap.get("tower_progress", {}))
	# 旧存档没有这个字段 → 空数组（等于「还没获得过任何元魂」）
	d.obtained_souls = snap.get("obtained_souls", [])
	# 旧档 / 本档都按现有持有物补录（幂等）：至少把当前背包、穿戴、元魂记录纳入图鉴
	d.rebuild_codex_from_owned()
	d.origin_energy = float(snap.get("origin_energy", 0.0))
	d.memory_progress = snap.get("memory_progress", {})
	d.story_progress = int(snap.get("story_progress", 0))
	d.chapter_state = String(snap.get("chapter_state", d.chapter_state))
	# 大世界状态：旧档没有该字段 → 保持默认空结构（子字段逐个兜底，防止旧档缺键）
	var world = snap.get("secret_world", {})
	if world is Dictionary:
		for key in ["core_kills", "nodes", "cultivators", "god_altars"]:
			var sub = (world as Dictionary).get(key, {})
			d.secret_world[key] = sub.duplicate(true) if sub is Dictionary else {}


func _empty_slots() -> Dictionary:
	var out := {}
	for slot in CharacterData.SLOT_ORDER:
		out[slot] = null
	return out


func _empty_treasure_slots() -> Dictionary:
	var out := {}
	for slot in CharacterData.TREASURE_SLOT_ORDER:
		out[slot] = null
	return out


## 丹药 / 符箓的显示字段刷新：旧档只存了 craft 当时的名字与说明。
## 物品 id 不变，所以读档时按数据表现算一遍即可。
func _refresh_consumable_item_defs(inv: Array) -> void:
	for raw in inv:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		var t := String(item.get("type", ""))
		if t != "pill" and t != "talisman":
			continue
		var def := ItemDB.get_consumable(String(item.get("id", "")))
		if def.is_empty():
			continue
		item["name"] = String(def.get("pill_name", def.get("talisman_name", item.get("name", ""))))
		item["desc"] = String(def.get("desc", item.get("desc", "")))
		item["battle_cooldown"] = float(def.get("battle_cooldown", 0.0))
		var icon := String(def.get("icon", ""))
		if icon != "":
			item["icon"] = icon


## 图标补录：材料 / 丹药 / 符箓 / 装备 / 法宝。
## ⚠ 图标由模板现查，旧存档 JSON 里的空 icon 不需要整体迁移版本号。
func _refresh_all_item_icons(d: CharacterData) -> void:
	for slot in d.equipment_slots.values():
		if slot is Dictionary:
			_refresh_item_icon(slot)
	for slot in d.treasure_slots.values():
		if slot is Dictionary:
			_refresh_item_icon(slot)
	for raw in d.inventory:
		if raw is Dictionary:
			_refresh_item_icon(raw)
	for raw in d.warehouse:
		if raw is Dictionary:
			_refresh_item_icon(raw)


func _refresh_item_icon(item: Dictionary) -> void:
	var id := String(item.get("id", ""))
	if id == "":
		return
	var icon := ""
	match String(item.get("type", "")):
		"material":
			icon = String(ItemDB.get_material(id).get("icon", ""))
		"pill", "talisman":
			icon = String(ItemDB.get_consumable(id).get("icon", ""))
		"equipment", "treasure":
			var tpl := ItemDB.get_equipment_template(id)
			if tpl.is_empty():
				tpl = ItemDB.get_treasure_template(id)
			icon = String(tpl.get("icon", ""))
	if icon != "":
		item["icon"] = icon


## 旧档装备槽迁移：早期只有 weapon / armor / accessory 三个槽
## → 把 accessory 的内容搬到 accessory_1，并删掉旧键，避免残留脏数据
func _migrate_legacy_slots(slots: Dictionary) -> void:
	if not slots.has("accessory"):
		return
	var legacy = slots.get("accessory")
	slots.erase("accessory")
	if legacy is Dictionary and slots.get("accessory_1") == null:
		slots["accessory_1"] = legacy
	elif legacy is Dictionary:
		# accessory_1 已被占用：塞进第一个空饰品槽，实在没有就丢弃（避免消失得更糟）
		for slot in CharacterData.slots_for_type("accessory"):
			if slots.get(String(slot)) == null:
				slots[String(slot)] = legacy
				return


## 旧档的修为存的是 0.0~1.0 的小阶段进度：按当前境界/阶段的新阈值换算成点数。
## 新档直接读 realm_exp（必须在 current_realm / realm_stage 已赋值后调用）。
func _migrate_realm_exp(realm: Dictionary) -> int:
	if realm.has("realm_exp"):
		return maxi(0, int(realm.get("realm_exp", 0)))
	var old := float(realm.get("realm_progress", 0.0))
	if old <= 0.0:
		return 0
	if old <= 1.0001:
		return int(round(old * float(CharacterData.get_stage_exp_required())))
	return int(round(old))


## 旧档属性迁移：早期没有 base_attributes，只有几个散落字段
## 逐项回填到新属性表，缺失的保留默认值
func _migrate_legacy_player_stats(d: Node, player: Dictionary) -> void:
	if player.has("base_max_hp"):
		d.base_attributes[AttributeDB.ATTR_HP_MAX] = float(player["base_max_hp"])
	if player.has("base_max_stamina"):
		d.base_attributes[AttributeDB.ATTR_STAMINA_MAX] = float(player["base_max_stamina"])
	if player.has("base_max_mana"):
		d.base_attributes[AttributeDB.ATTR_MANA_MAX] = float(player["base_max_mana"])
	# 旧版「攻击力」没有力量概念：把攻击力等值折算成力量，保证老档手感不跳变
	if player.has("base_attack"):
		d.base_attributes[AttributeDB.ATTR_STRENGTH] = float(player["base_attack"]) \
			/ CharacterData.STRENGTH_TO_ATTACK


# ===================== 槽位操作 =====================

func save_to_slot(slot: int) -> bool:
	# ⚠ 写盘总闸：测试/截图脚本关闭后连手动存档都不会落盘
	if not write_enabled:
		return false
	# 覆盖前先留一份上一版（没有旧档 / 旧档读不出来就不备份）
	if FileAccess.file_exists(slot_path(slot)):
		_copy_file(slot_path(slot), backup_path(slot))
	var snap := capture()
	snap["slot"] = slot
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：" + slot_path(slot))
		return false
	f.store_string(JSON.stringify(snap))
	f.close()
	return true


## 自动存档：轮流写入 1–4 槽，返回实际写入的槽号（没写 / 被测试开关禁用时返回 -1）
## ⚠ 2026-10-22：空档绝不许覆盖旧进度（那次「存档没了」就是新局连进 4 次主城把 1–4 全写成空档）。
## ⚠ 2026-10-26：空档不但不覆盖，**连写都不写、也不占轮转位** —— 否则每局第一发自动存档
##   （进主城那一刻还没进度）会把第 1 槽的回合吃掉，第 1 槽就永远轮不到真实进度。
func auto_save() -> int:
	if not auto_save_enabled or not write_enabled:
		return -1
	# 刚读完档就进主城：内容与盘上一致，没必要再写一遍（见 _skip_next_autosave 注释）
	if _skip_next_autosave:
		_skip_next_autosave = false
		return -1
	var snap := capture()
	# 空跑（新开局：只有新手铁剑，没有背包 / 功法 / 进度）没有值得保存的东西。
	# 旧版只拦「空档覆盖有进度的槽」：空档仍会写进空槽，被跳过时也照样占掉一次轮转；
	# 而 _next_auto_slot 每次启动都从 1 开始 —— 于是每局的第一发自动存档都是空档，
	# 第 1 槽永远是空的或旧的，真实进度只能落进 2~4 槽。
	# 这就是 2026-10-26 用户报的「自动存档没有写入第一个存档槽」。空档干脆不写、也不动指针。
	if is_blank_run(snap):
		push_warning("自动存档跳过：本次没有进度可存（新开局），不占用槽位")
		return -1
	var slot := _next_auto_slot
	save_to_slot(slot)
	# 指针只在真正写入后前进：跳过的那次不占槽位，下一发仍然写回同一槽
	_next_auto_slot = slot + 1 if slot < AUTO_SLOT_COUNT else 1
	return slot


## 手动存档：只覆盖第 5 槽
func manual_save() -> bool:
	return save_to_slot(MANUAL_SLOT)


## 开新存档：角色数据回到出厂状态 + 5 个槽清空（清之前各留一份 .bak）。
##
## ⚠ 槽文件必须真的清掉：标题界面的「开始旅程」是「读最近一档」，
##   只要旧档还在盘上，重开一进主城就会被旧档覆盖回来（表现就是「点了新游戏还是老角色」）。
## ⚠ .bak 会被这次覆盖 —— 这是仅剩的一层后悔药，调用方必须先弹确认框。
func new_game() -> void:
	for i in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(i)):
			_copy_file(slot_path(i), backup_path(i))
			DirAccess.remove_absolute(slot_path(i))
	# 出厂数据：另开一个 CharacterData 实例 —— 成员初始值就是新开局的默认值。
	# 单例走不到那条初始化路径，开局装备要自己发一遍（_ready 里那两行只对单例生效）。
	var fresh = load("res://scripts/systems/character_data.gd").new()
	fresh.ensure_starting_equipment()
	fresh.ensure_starting_treasures()
	apply(capture(fresh))
	fresh.free()
	_next_auto_slot = 1
	_skip_next_autosave = false


## 读档：主文件坏了/不在了 → 自动退回上次覆盖前的备份（如果有）
func load_slot(slot: int) -> bool:
	var parsed := _read_slot_dict(slot_path(slot))
	if parsed.is_empty() and has_backup(slot):
		parsed = _read_slot_dict(backup_path(slot))
		if not parsed.is_empty():
			push_warning("第 %d 槽主档不可用，已改用备份" % slot)
	if parsed.is_empty():
		return false
	apply(parsed)
	return true


## 读「最近的一档」：在 1–4 自动槽里按 saved_at 取最新；都没有则回退第 5 槽（手动）。
## 返回是否真的读到了（false = 没有可用存档，调用方按新开局处理）。
##
## ⚠ 这个函数是「每次进游戏都是新存档」的修复核心：标题界面只有一个「开始旅程」入口，
##   之前它只做 change_scene_to_file，从不读档 —— 于是每次都拿内存里的新开局进主城。
##   磁盘上的进度一直是好的（主城的 auto_save 被 is_blank_run 拦住，不会覆盖真档），
##   纯粹是「没人去读」。
## ⚠ 必须用 get_slot_info 的 saved_at，不能用槽号：自动槽是轮转写的，
##   槽号大不代表更新（第 4 槽可能是上周的，第 1 槽是刚存的）。
func load_latest_auto() -> bool:
	var best_slot := -1
	var best_at := -1
	for i in range(1, AUTO_SLOT_COUNT + 1):
		var info := get_slot_info(i)
		if not bool(info.get("exists", false)):
			continue
		var at := int(info.get("saved_at", 0))
		if at > best_at:
			best_at = at
			best_slot = i
	if best_slot < 0:
		# 自动槽全空 → 玩家可能只手动存过档，读第 5 槽
		if get_slot_info(MANUAL_SLOT).get("exists", false):
			best_slot = MANUAL_SLOT
	if best_slot < 0:
		return false
	if not load_slot(best_slot):
		return false
	# 轮转接着这一槽往后走，否则下一次自动存档会从 1 开始把旧档盖掉
	_next_auto_slot = best_slot + 1 if best_slot < AUTO_SLOT_COUNT else 1
	_skip_next_autosave = true
	print("[SaveManager] 已读取最近存档：第 %d 槽（%s）" % [best_slot, _format_time(best_at)])
	return true


## 槽位摘要（供设置界面显示，只读取不加载）
func get_slot_info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {"exists": false, "slot": slot, "backup_exists": has_backup(slot)}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {"exists": false, "slot": slot, "backup_exists": has_backup(slot)}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		return {"exists": false, "slot": slot, "corrupted": true, "backup_exists": has_backup(slot)}
	var realm: Dictionary = parsed.get("realm_data", {})
	return {
		"exists": true,
		"slot": slot,
		"realm": String(realm.get("current_realm", "?")),
		"saved_at": int(parsed.get("saved_at", 0)),
		"time_text": _format_time(int(parsed.get("saved_at", 0))),
		"version": int(parsed.get("save_version", 0)),
		"backup_exists": has_backup(slot),
	}


func is_slot_manual(slot: int) -> bool:
	return slot == MANUAL_SLOT


func slot_display_name(slot: int) -> String:
	return "手动存档" if is_slot_manual(slot) else "自动存档 %d" % slot


func has_any_save() -> bool:
	for i in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(i)):
			return true
	return false


func delete_slot(slot: int) -> void:
	var dir := DirAccess.open("user://")
	if dir:
		# 连备份一起删：否则「删除」之后还能从备份里把旧档捞回来，玩家会以为没删掉
		dir.remove("save_slot_%d.json" % slot)
		dir.remove("save_slot_%d%s.json" % [slot, BACKUP_SUFFIX])


# ===================== 工具 =====================

## int 键 → 字符串键（JSON 只支持字符串 key）
## 注意：GDScript 里 int 转字符串只能用 str()，不能用 String()
static func _keys_to_str(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		out[str(k)] = src[k]
	return out


## 字符串键 → int 键（读档还原）
static func _keys_to_int(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		out[int(k)] = src[k]
	return out


static func _format_time(unix_sec: int) -> String:
	if unix_sec <= 0:
		return "—"
	# ⚠ get_datetime_dict_from_unix_time 返回的是 **UTC**，直接显示会差 8 小时
	#   （实测 05:13 存的档显示成 21:13）。存档列表要按时间判断「哪个最新」，
	#   差 8 小时会让人看错，必须补上本机时区偏移。
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var dt := Time.get_datetime_dict_from_unix_time(unix_sec + bias * 60)
	return "%02d-%02d %02d:%02d" % [dt["month"], dt["day"], dt["hour"], dt["minute"]]
