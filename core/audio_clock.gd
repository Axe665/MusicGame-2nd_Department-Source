class_name AudioClock
extends RefCounted

## 设备无关的音频时钟。
##
## 起播不预测「下一次 mix + 驱动延迟」：这个预估在 PipeWire 上实测能在 14–55ms
## 之间跳，`get_time_to_next_mix()` 还会变负，一次采样错了就是整首歌固定偏移。
## 这里改成等音频真的出声（playback > 0）后，用实际播放位置锚定，起播误差不再
## 依赖平台和单次采样。
##
## 驱动报告的延迟只用来把“混音位置”换算成“听到的位置”，而且在起播后一小段
## 窗口里取中位数后**冻结**：不再每帧追着驱动噪声跑（Windows/PipeWire 实测
## 29–58ms 抖动）。驱动报 0 的平台（Android/Web）自然退化成混音位置时钟。
const LATENCY_WINDOW_MS := 250.0
const MAX_LATENCY_SEC := 0.25
const MAX_MIX_SEC := 0.25
## 单帧最多前进多少；超过按卡顿处理（长卡顿靠漂移校正慢慢追上）。
const MAX_HITCH_MS := 1000.0
## 起播锚定允许的最大回跳；更大的采样当成坏数据，等下一帧。
const MAX_ANCHOR_JUMP_MS := 600.0
## 小于这个误差不修：驱动延迟本身就有几毫秒噪声，修它只会让时钟抖。
const DEADBAND_MS := 4.0
const CORRECTION_RATE := 0.05
const MAX_CORRECTION_MS := 1.0
const MAX_CATCHUP_ERROR_MS := 600.0
const MAX_CATCHUP_MS := 8.0

var clock_ms := -INF
## 已经用真实播放位置锚定过。
var anchored := false
var _last_usec := 0
var _started := false
var _latency := 0.0
## 当前用于换算“听到的位置”的延迟（ms），日志/诊断用。
var latency_ms := 0.0
var _latency_samples: Array[float] = []
var _latency_start_usec := 0
var _latency_frozen := false
var _anchor_jump := false


func start(at_ms: float, now_usec: int) -> void:
	clock_ms = at_ms
	_last_usec = now_usec
	_started = true
	anchored = false
	_latency = 0.0
	latency_ms = 0.0
	_latency_samples.clear()
	_latency_frozen = false
	_anchor_jump = false


func resume(now_usec: int) -> void:
	_last_usec = now_usec


## 起播锚定是一次真实的向后对齐（要把延迟减掉），调用方要允许这一帧回跳。
func consume_anchor_jump() -> bool:
	var jumped := _anchor_jump
	_anchor_jump = false
	return jumped


## `audio_playing` = 播放器真的在放；`playback_sec <= 0` 表示音频还没开始出声。
## `rate` = 播放倍速：墙钟按它前进，驱动延迟/混音间隔是真实秒数，换算成
##   谱面时间时也要乘它。
## `stream_rate` = 当前音频流的时间伸缩倍率（1 = 原始音频；2 = 已经用
##   atempo 拉长/压缩过，流里 1 秒对应谱面 2 秒）。
func update(now_usec: int, audio_playing: bool, playback_sec: float, chart_offset_ms: float,
		latency_sec: float, mix_sec: float, rate: float = 1.0, stream_rate: float = 1.0) -> float:
	if not _started:
		return 0.0
	var speed := maxf(0.01, rate)
	var stretch := maxf(0.01, stream_rate)
	var dt := clampf(float(now_usec - _last_usec) / 1000.0, 0.0, MAX_HITCH_MS)
	_last_usec = now_usec
	var step := dt * speed
	if not audio_playing:
		# 没有音频（基准模式 / 音频不可用）：退回墙钟。
		if is_finite(clock_ms + step):
			clock_ms += step
		return clock_ms
	if playback_sec <= 0.0:
		# 已经 play() 但混音还没开始：停在起点等它，避免起播前空跑。
		return clock_ms
	var mix := clampf(mix_sec, 0.0, MAX_MIX_SEC)
	var latency := _latency_estimate(now_usec, latency_sec)
	var audio_ms := (playback_sec * stretch + (mix - latency) * speed) * 1000.0 + chart_offset_ms
	if not anchored:
		if absf(audio_ms - clock_ms) <= MAX_ANCHOR_JUMP_MS:
			anchored = true
			_anchor_jump = true
			clock_ms = audio_ms
		return clock_ms
	var wall := clock_ms + step
	var error := audio_ms - wall
	# 按经过时间缩放：鼠标事件会一帧调用多次，固定步长会把时钟推快。
	var scale := clampf(dt / 16.0, 0.0, 4.0)
	if absf(error) > DEADBAND_MS and absf(error) <= MAX_CATCHUP_ERROR_MS:
		if absf(error) <= 120.0:
			wall += clampf(error * CORRECTION_RATE * scale,
				-MAX_CORRECTION_MS * scale, MAX_CORRECTION_MS * scale)
		else:
			wall += clampf(error, -MAX_CATCHUP_MS * scale, MAX_CATCHUP_MS * scale)
	if is_finite(wall):
		clock_ms = wall
	return clock_ms


## 起播后一小段窗口取中位数再冻结；窗口内用当前采样。
func _latency_estimate(now_usec: int, latency_sec: float) -> float:
	var sample := clampf(latency_sec, 0.0, MAX_LATENCY_SEC)
	if _latency_frozen:
		return _latency
	if _latency_samples.is_empty():
		_latency_start_usec = now_usec
	_latency_samples.append(sample)
	if float(now_usec - _latency_start_usec) / 1000.0 < LATENCY_WINDOW_MS:
		_latency = sample
		latency_ms = _latency * 1000.0
		return _latency
	var sorted := _latency_samples.duplicate()
	sorted.sort()
	_latency = sorted[sorted.size() / 2]
	_latency_frozen = true
	latency_ms = _latency * 1000.0
	return _latency
