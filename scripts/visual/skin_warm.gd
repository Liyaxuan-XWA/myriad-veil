class_name SkinWarm
extends RefCounted
## 角色美术资源的「线程预载 + 按住引用」小管家
##
## ### 为什么需要它（2026-11-05 实机报「点开战卡一下」，实测定位）
## 棋坛快速模式点「开战」要同帧激活 12 只 BOSS，实测那一帧 645ms（预算 16.7ms）。
## 拆开量之后，钱几乎全花在 `SkinVisual._build_rig()` 里的一句 `load(sprite_frames)`：
##   · 石犼（boss_huyao 皮）455ms　· 刀客 190ms　· 挂到节点上的 attach 只 0.1ms
## 原因是这些招式序列帧表走的是**有损压缩、非 VRAM** 的导入档（`.import` 里
## `compress/mode=1` + `vram_texture=false`），`load()` 要在主线程把整张图集
## 解成 RGBA8 再交给渲染端 —— 两张表就吃掉 270MB 显存，解码自然是几百毫秒。
##
## ### 两件事
## ① **线程预载**：`ResourceLoader.load_threaded_request()` 把解码挪到工作线程。
##    实测两张表同时预载：墙钟 438ms、期间主线程峰值帧 16.70ms（空闲基线 16.67ms）
##    —— 一帧都没卡。所以要在「进关 / 选完卡」这些还有空档的时刻提前点火。
## ② **按住引用**：Godot 的资源缓存在**没人引用时就把资源连同纹理一起丢掉**。
##    一场打完，场上实例全灭 ⇒ 下一场从头再解一遍（实测第二场仍是 400ms，
##    不是"一次性的"）。所以预载过的路径要把 Resource 押在本类里，
##    等这局真正结束（离场）再放。
##
## ⚠ 只有**被 `request()` 点名过的**路径才会被押住；没点名的照旧用完即弃。
##   这样大世界 / 塔 / 演武场完全不受影响，显存峰值也不会超出「这一局本来就要摆的牌」。
##
## ### 用法
## 场景方（棋局）：`request(场景路径)` → 每帧 `poll()` → 节点内部走 `resource(path)`。
## 场景先预载是有讲究的：PackedScene 到手后本类会扫一遍它里面挂的 `visual_id`，
## 顺手把那份美术条目下的 rig / sprite_frames / texture 也排进队列，
## 调用方不必再维护一张「BOSS → 贴图路径」的对照表（那种表一定会和场景漂开）。

## path -> true：已经点过名（决定 `resource()` 要不要押引用）
static var _tracked: Dictionary = {}
## path -> true：请求已发出、还没取回
static var _pending: Dictionary = {}
## path -> Resource：取回后押住的引用
static var _held: Dictionary = {}


## 预载一份资源（.tscn / .tres / 贴图路径都可以）。重复调用安全。
static func request(path: String) -> void:
	if path == "" or _tracked.has(path):
		return
	if not ResourceLoader.exists(path):
		return
	_tracked[path] = true
	_pending[path] = true
	ResourceLoader.load_threaded_request(path)


## 把一个 ArtDB 美术条目下会 load 的资源全部点名。
static func request_visual_paths(entry: Dictionary) -> void:
	for key in ["rig", "sprite_frames", "texture"]:
		request(String(entry.get(key, "")))


## 按 visual_id 点名（调用方手里只有 id、拿不到场景的时候用，例如核心首领的皮）
static func request_visual_entry(visual_id: String) -> void:
	if visual_id == "":
		return
	var entry: Dictionary = ArtDB.get_visual(visual_id)
	if entry.is_empty():
		return
	request_visual_paths(entry)


## 每帧调一次：取回调好的资源并押住引用。没有排队时几乎零成本。
static func poll() -> void:
	if _pending.is_empty():
		return
	var settled: Array = []
	for raw in _pending.keys():
		var path := String(raw)
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		settled.append(path)
		if st != ResourceLoader.THREAD_LOAD_LOADED:
			# INVALID / FAILED：留着引用位也没意义，让 resource() 走同步兜底
			continue
		var res: Resource = ResourceLoader.load_threaded_get(path)
		if res == null:
			continue
		_held[path] = res
		if res is PackedScene:
			_request_scene_art(res as PackedScene)
	for path in settled:
		_pending.erase(String(path))


## 取资源：押着的直接给；没押的同步 load（点过名的顺手补押一份）。
## SkinVisual 与 MatchAdapter 里的 `load()` 都换走这里，两条入口才不会一条快一条慢。
static func resource(path: String) -> Resource:
	if _held.has(path):
		return _held[path]
	var res := load(path)
	if _tracked.has(path) and res != null:
		_held[path] = res
	return res


## 已经到位了吗（给「要不要再等一帧」这类判据用，不参与玩法）
static func is_ready(path: String) -> bool:
	return _held.has(path)


## 还有没有在路上的
static func is_busy() -> bool:
	return not _pending.is_empty()


## 一局结束 / 离开场景时调用：把押住的引用全放开，显存还给系统。
static func clear() -> void:
	# ⚠ 没有取消在路上的请求：本机 4.7.2 的 ResourceLoader 没有 load_threaded_cancel。
	#   留着让它自己跑完就行 —— 取回方（_pending）已经清空，解出来的资源没人引用，
	#   下一步就被系统回收，不会漏显存。
	_tracked.clear()
	_pending.clear()
	_held.clear()


## 从 PackedScene 里读出各 SkinVisual 的 `visual_id`，把对应美术条目排进预载队列。
## 为什么读场景而不是查表：`visual_id` 是**挂在场景节点上的导出值**（石犼用的就是
## boss_huyao 那份皮），另存一份 BOSS→贴图 的对照表等于把同一个事实写两处，
## 迟早和场景漂开。
static func _request_scene_art(packed: PackedScene) -> void:
	for vid in _visual_ids_of(packed):
		request_visual_entry(String(vid))


static func _visual_ids_of(packed: PackedScene) -> Array:
	var out: Array = []
	var st := packed.get_state()
	if st == null:
		return out
	for i in st.get_node_count():
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) != "visual_id":
				continue
			var v: Variant = st.get_node_property_value(i, j)
			if typeof(v) != TYPE_STRING or String(v) == "":
				continue
			if not out.has(v):
				out.append(String(v))
	return out
