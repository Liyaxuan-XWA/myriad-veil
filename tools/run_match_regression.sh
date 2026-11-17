#!/usr/bin/env bash
# 棋坛全套回归：一条命令跑完所有 match 探针并汇总绿/红数。
#
# ⚠ 点击/拖拽/换场景类只能窗口化跑（合成鼠标要过真实 viewport transform，
#   change_scene 在 --headless 下拿不到 root 的尺寸），其余一律 --headless。
#
# 汇总行有**两代**格式，两种都得认，否则老探针会被读成 "NO RESULT"：
#   新：RESULT passes=56 fails=0
#   老：########## 结果：43 项通过，0 项失败 ##########
#
# 用法：bash tools/run_match_regression.sh [探针名子串]
G="D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
cd "$(dirname "$0")/.." || exit 1

HEADLESS="probe_match_rules probe_match_cards probe_match_faction probe_match_freeze \
probe_match_entry probe_match_pieces probe_match_balance probe_match_ranged \
probe_match_abandon probe_match_scroll_preview probe_match_level_deck \
probe_match_level_flow probe_match_level_reward probe_match_level_all \
probe_match_quick_switch probe_match_quick_setup probe_match_quick_open \
probe_match_quick_battle probe_match_quick_camera probe_match_quick_rubbing \
probe_match_quick_all probe_breakable_group probe_hostile_units \
probe_scar_match probe_treasure_match probe_sun_seed_match probe_mirror_match \
probe_shadow_match probe_shihou_scope probe_match_quick_stagger \
probe_match_report probe_match_report_live probe_match_replay"
WINDOWED="probe_match_clicks probe_match_drag probe_match_quick_chain"

FILTER="${1:-}"
fail_total=0

run_one() {
	local p="$1" ; shift
	local out line="" verdict="没读到汇总行"
	out=$("$G" "$@" "res://tools/$p.tscn" -- --no-save 2>&1 | tr -d '\r')
	line=$(printf '%s' "$out" | grep -oE "passes=[0-9]+ fails=[0-9]+|[0-9]+ 项通过，[0-9]+ 项失败" | tail -1)
	[ -z "$line" ] && line="NO RESULT"
	echo "[$p] $line"
	printf '%s' "$out" | grep "^FAIL" | sed 's/^/    /'
	# ⚠ 判绿只认**抓出来的这一串**，不用 grep 去整份输出里找 "fails=0$"：
	#   Godot 在 Windows 上写 CRLF，`$` 锚点会被那个 \r 顶掉（第一版就这么把
	#   24 个全绿的探针报成"8 个有红"，而文件里一行 FAIL 都没有）。
	case "$line" in
		"passes="*"fails=0") verdict="ok" ;;
		*"项通过，0 项失败") verdict="ok" ;;
	esac
	if [ "$verdict" != "ok" ] || printf '%s' "$out" | grep -q "^FAIL"; then
		fail_total=$((fail_total + 1))
		echo "    ⇒ 记为有红：$line"
	fi
}

for p in $HEADLESS; do
	[ -n "$FILTER" ] && [[ "$p" != *"$FILTER"* ]] && continue
	run_one "$p" --headless --path .
done
for p in $WINDOWED; do
	[ -n "$FILTER" ] && [[ "$p" != *"$FILTER"* ]] && continue
	run_one "$p" --path . --windowed --resolution 1280x720
done
echo "==================== 有红的探针脚本数：$fail_total ===================="
