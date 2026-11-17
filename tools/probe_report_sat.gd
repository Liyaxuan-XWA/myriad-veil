extends Node2D
## 战报探针用的卫星桩（票 002）
##
## 卫星实体 = **不是 BossBase 的一击来源**（刀痕、场地、弹体、镜像…）。
## 台账要求它带两个字段：`report_owner`（并进谁名下）与 `report_tag`（自己那一行的名字）。
## 这个桩只提供这两个字段，不真出招 —— 用来单独量"归属与行名"这一段逻辑。
## 等真卫星（blade_scar / mirror_ring_field …）补上这两个字段后，
## `probe_shadow_match` / `probe_treasure_match` 那一侧再各自验自己的行名。

var report_owner: Node = null
var report_tag: String = ""
