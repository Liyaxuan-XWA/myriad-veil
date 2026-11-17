class_name BgmPlayer
extends AudioStreamPlayer
## 通用 BGM 播放器：循环 WAV + 淡入淡出
##
## 战斗 / 主城 / 苍澜大陆共用；只负责「把一首已生成的 WAV 循环播放」，
## 选曲逻辑留在各场景（战斗随机三选一、主城固定空灵曲、大陆固定探索曲）。
## 曲目生成器见 tools/gen_battle_music.py。

const BATTLE_VOLUME_DB := -18.0
## 主城 / 大世界是氛围音乐，比战斗再轻 2dB
const AMBIENT_VOLUME_DB := -20.0
const DEFAULT_FADE_IN := 1.6
const DEFAULT_FADE_OUT := 2.0

var _fade_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	# 暂停（角色面板 / 感悟面板 / 轮盘）时 BGM 也不要跟着停
	process_mode = Node.PROCESS_MODE_ALWAYS


## 循环播放一首 WAV；返回是否成功
func play_loop(path: String, target_db: float = BATTLE_VOLUME_DB,
		fade_in: float = DEFAULT_FADE_IN) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("BGM 加载失败：" + path)
		return false
	var src := load(path) as AudioStreamWAV
	if src == null:
		push_warning("BGM 不是 WAV：" + path)
		return false
	# 复制一份再设循环，避免改到全局共享资源
	var looped := src.duplicate() as AudioStreamWAV
	if looped != null:
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		var frames := int(round(looped.get_length() * float(looped.mix_rate)))
		if frames <= 0:
			frames = int(looped.data.size() / (2 * (2 if looped.stereo else 1)))
		looped.loop_end = frames
		src = looped
	stream = src
	volume_db = -45.0
	play()
	_fade_to(target_db, fade_in, false)
	return true


func fade_out(duration: float = DEFAULT_FADE_OUT) -> void:
	if not playing:
		return
	_fade_to(-50.0, duration, true)


## 外部调目标音量（BOSS 入场卡压低 / 关卡拉回）
func fade_to_db(target_db: float, duration: float = 0.4) -> void:
	if not playing:
		return
	_fade_to(target_db, duration, false)


func _fade_to(target_db: float, duration: float, stop_after: bool) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "volume_db", target_db, duration)
	if stop_after:
		_fade_tween.tween_callback(stop)
