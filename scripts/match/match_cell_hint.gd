class_name MatchCellHint
extends Node2D
## 布阵阶段的可落空格子提示（2026-11-04 用户：一眼要能看出该点哪儿）
##
## 只有玩家**已经选中一张手牌**之后才画 —— 没选牌就铺满 36 个空格等于噪声。
## 每个格子一圈淡淡的暖金呼吸边 + 中心一个小菱形：边表示"这里能落"，
## 菱形表示"落点在这里"，两者都不许挡住底下的棋盘格线。
##
## ⚠ 呼吸靠 `_process` 里 queue_redraw，但**没格子可画时不跑**：
##   布阵只占一局里的一小段，全程每帧重绘 36 个框是白烧。

const PAD := 20.0            ## 提示框比格子内缩多少（留出让格线看得见）
const CYCLE := 1.7
const LO := 0.30
const HI := 0.74
## 线宽与菱形半径按**世界像素**给：棋盘整屏缩到 zoom≈0.31，
## 2px 的线落到屏幕上只剩 0.6px —— 截图里整片格子只看得见中心一个点、
## 呼吸框等于没画（这条是"在 1:1 尺度上设计、在 0.31 尺度上验收"的经典坑）。
## 6.5 世界 px ≈ 2 屏幕 px，14 世界 px 的菱形 ≈ 4.3 屏幕 px。
const EDGE_W := 6.5
const DIAMOND := 14.0

var cells: Array = []        ## 可落子的格子坐标（Vector2i）
var _hover := Vector2i(-1, -1)    ## 拖牌时鼠标正压着的那一格（-1 = 没有）
var _pulse := 0.0


## 拖动布阵时把光标下那一格单独点亮（2026-11-04 用户要拖拽上场）：
## 36 个框只说"这些格能落"，到底落进哪一格得有一圈加粗的，否则松手全靠猜。
func set_hover(c: Vector2i) -> void:
	if c == _hover:
		return
	_hover = c
	queue_redraw()


func set_cells(v: Array) -> void:
	var same := v.size() == cells.size()
	if same:
		for i in v.size():
			if (v[i] as Vector2i) != (cells[i] as Vector2i):
				same = false
				break
	cells = v
	# ⚠ 顺序：先落 cells、再定 set_process，最后才用 same 跳过重绘。
	#   原来 same 的早退写在 set_process 前面，于是「建好就推一批空数组」
	#   的提示节点会一路开着 _process 空转（probe_match_cards 抓到）。
	set_process(not cells.is_empty())
	if not same:
		queue_redraw()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, CYCLE)
	queue_redraw()


func _breath() -> float:
	return lerpf(LO, HI, 0.5 - 0.5 * cos(_pulse / CYCLE * TAU))


func _draw() -> void:
	var b := _breath()
	var side := MatchDB.CELL_PX - PAD * 2.0
	var r := MatchCard.corner_radius(side) * 1.6
	# 与可点牌的呼吸灯同一个色相：全场"现在可以点这里"只用一种光色，
	# 免得空格框和牌框各金各绿，玩家要分两回
	var edge := Color(1.0, 0.95, 0.78, b)
	for raw in cells:
		var c: Vector2 = MatchDB.cell_to_pos(raw as Vector2i)
		var pts := MatchCard.rounded_points(side, side, r)
		var shifted := PackedVector2Array()
		for p in pts:
			shifted.append((p as Vector2) + c)
		# 光标正压着的那一格：整圈加粗提亮，填充也压深一档 —— 拖牌松手前
		# 玩家必须知道"就是这一格"，36 个一模一样的框做不到这件事。
		var hot := (raw as Vector2i) == _hover
		var w := EDGE_W + (5.0 if hot else 0.0)
		var col := Color(edge.r, edge.g, edge.b, minf(edge.a + (0.26 if hot else 0.0), 1.0))
		draw_colored_polygon(shifted, Color(1.0, 0.90, 0.56,
				edge.a * 0.16 + (0.20 if hot else 0.0)))
		draw_polyline(shifted, col, w, true)
		# 中心小菱形：告诉玩家"落点算在格心"，与卡片 token 的锚点同一处
		var d := DIAMOND + (7.0 if hot else 0.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0),
				c + Vector2(0, d), c + Vector2(-d, 0)]),
				Color(1.0, 0.92, 0.62, minf(edge.a * 1.4 + (0.35 if hot else 0.0), 1.0)))
