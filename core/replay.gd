class_name Replay
extends RefCounted

## 一局试玩的输入流。
##
## 只记录「输入」不记录「判定结果」：回放时把同样的事件按时间喂回同一套判定代码。
## 判定用的是事件自带的时间戳，所以回放卡顿、变速、静音都不影响结果
##（和 osu!lazer / danser 的思路一致）。
##
## 事件种类：
##   move    {t, x, y}                     光标位置（预览区局部坐标）
##   press   {t, key, lo, hi, x, y, a, u, v}  按键按下（带一帧区间与当时光标）
##   release {t, key}                      按键松开
##   seek    {t, lo, hi, dir}              滚轮 / Sweep
##   offset  {t, v}                        判定偏移发生变化（动态校准、手动微调）

const FORMAT := "tamaki-replay"
const VERSION := 1

var chart_path: String = ""
var chart_hash: String = ""
var start_beat: float = 0.0
var settings: Dictionary = {}
var events: Array[Dictionary] = []
var result: Dictionary = {}


func add_move(time_ms: float, point: Vector2) -> void:
	events.append({
		"t": snappedf(time_ms, 0.01),
		"k": "move",
		"x": snappedf(point.x, 0.01),
		"y": snappedf(point.y, 0.01),
	})


func add_press(time_ms: float, lo_ms: float, hi_ms: float, key: int, cursor: Vector2,
		angle: float, u: float, valid: bool) -> void:
	events.append({
		"t": snappedf(time_ms, 0.01),
		"k": "press",
		"key": key,
		"lo": snappedf(lo_ms, 0.01),
		"hi": snappedf(hi_ms, 0.01),
		"x": snappedf(cursor.x, 0.01),
		"y": snappedf(cursor.y, 0.01),
		"a": snappedf(angle, 0.01),
		"u": snappedf(u, 0.0001),
		"v": valid,
	})


func add_release(time_ms: float, key: int) -> void:
	events.append({"t": snappedf(time_ms, 0.01), "k": "release", "key": key})


func add_seek(time_ms: float, lo_ms: float, hi_ms: float, direction: int) -> void:
	events.append({
		"t": snappedf(time_ms, 0.01),
		"k": "seek",
		"lo": snappedf(lo_ms, 0.01),
		"hi": snappedf(hi_ms, 0.01),
		"dir": direction,
	})


func add_offset(time_ms: float, value_ms: float) -> void:
	events.append({"t": snappedf(time_ms, 0.01), "k": "offset", "v": snappedf(value_ms, 0.01)})


func event_count() -> int:
	return events.size()


## 只保留回放需要的信息：谱面身份、设置、起始位置、结果摘要。
func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"chart": {"path": chart_path, "hash": chart_hash},
		"start_beat": start_beat,
		"settings": settings.duplicate(true),
		"result": result.duplicate(true),
		"events": events.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Replay:
	if String(data.get("format", "")) != FORMAT:
		return null
	var version := int(data.get("version", 0))
	if version < 1 or version > VERSION:
		return null
	var replay := Replay.new()
	var chart: Dictionary = data.get("chart", {})
	replay.chart_path = String(chart.get("path", ""))
	replay.chart_hash = String(chart.get("hash", ""))
	replay.start_beat = float(data.get("start_beat", 0.0))
	var raw_settings: Variant = data.get("settings", {})
	replay.settings = (raw_settings as Dictionary).duplicate(true) if raw_settings is Dictionary else {}
	var raw_result: Variant = data.get("result", {})
	replay.result = (raw_result as Dictionary).duplicate(true) if raw_result is Dictionary else {}
	var raw_events: Variant = data.get("events", [])
	if raw_events is Array:
		for raw in raw_events:
			if raw is Dictionary:
				replay.events.append((raw as Dictionary).duplicate())
	return replay


## 谱面内容哈希：谱面被改过之后，旧回放不该悄悄按新谱面播。
static func hash_chart(chart: Chart) -> String:
	if chart == null:
		return ""
	return JSON.stringify(ChartIO.chart_to_dict(chart)).sha256_text()


## gzip 压缩的 JSON。2 分钟的谱面大约 50–80 KB。
func save_to(path: String) -> Error:
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return OK


static func load_from(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return null
	return from_dict(parsed)
