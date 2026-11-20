class_name Replay
extends RefCounted

## 一局试玩的输入流。
##
## 只记录「输入」不记录「判定结果」：回放时把同样的事件按时间喂回同一套判定代码。
## 判定用的是事件自带的时间戳，所以回放卡顿、变速、静音都不影响结果
##（和 osu!lazer / danser 的思路一致）。
##
## 事件种类：
##   move    {t, x, y}                     光标位置（v2 = 0..1 归一化，v1 = 录制窗口像素）
##   press   {t, key, lo, hi, x, y, a, u, v}  按键按下（带一帧区间与当时光标）
##   release {t, key}                      按键松开
##   seek    {t, lo, hi, dir}              滚轮 / Sweep
##   offset  {t, v}                        判定偏移发生变化（动态校准、手动微调）

const FORMAT := "tamaki-replay"
const VERSION := 2
## v1 存的是录制窗口的像素坐标；v2 归一化到 0..1，换分辨率/换机器都对得上。
const COORDS_UNIT := "unit"
const COORDS_PIXELS := "px"

## 新建的 Replay 默认按像素解释（老用法/老文件）；录制器显式切成 unit。
var coords: String = COORDS_PIXELS
var chart_path: String = ""
var chart_hash: String = ""
var start_beat: float = 0.0
var settings: Dictionary = {}
var events: Array[Dictionary] = []
var result: Dictionary = {}


## 同一帧里的多次鼠标事件合并成一条（取最后一个位置），否则 1000Hz 鼠标
## 会让 2 分钟的谱写出几万条几乎重复的移动事件。
func add_move(time_ms: float, point: Vector2) -> void:
	var stamp := snappedf(time_ms, 1.0)
	if not events.is_empty():
		var last: Dictionary = events[events.size() - 1]
		if String(last.get("k", "")) == "move" and absf(float(last.get("t", 0.0)) - stamp) <= 1.0:
			last["x"] = snappedf(point.x, 0.0001)
			last["y"] = snappedf(point.y, 0.0001)
			return
	events.append({
		"t": stamp,
		"k": "move",
		"x": snappedf(point.x, 0.0001),
		"y": snappedf(point.y, 0.0001),
	})


func add_press(time_ms: float, lo_ms: float, hi_ms: float, key: int, cursor: Vector2,
		angle: float, u: float, valid: bool) -> void:
	events.append({
		"t": snappedf(time_ms, 1.0),
		"k": "press",
		"key": key,
		"lo": snappedf(lo_ms, 0.01),
		"hi": snappedf(hi_ms, 0.01),
		"x": snappedf(cursor.x, 0.0001),
		"y": snappedf(cursor.y, 0.0001),
		"a": snappedf(angle, 0.01),
		"u": snappedf(u, 0.0001),
		"v": valid,
	})


func add_release(time_ms: float, key: int) -> void:
	events.append({"t": snappedf(time_ms, 1.0), "k": "release", "key": key})


func add_seek(time_ms: float, lo_ms: float, hi_ms: float, direction: int) -> void:
	events.append({
		"t": snappedf(time_ms, 1.0),
		"k": "seek",
		"lo": snappedf(lo_ms, 0.01),
		"hi": snappedf(hi_ms, 0.01),
		"dir": direction,
	})


func add_offset(time_ms: float, value_ms: float) -> void:
	events.append({"t": snappedf(time_ms, 1.0), "k": "offset", "v": snappedf(value_ms, 0.01)})


func event_count() -> int:
	return events.size()


## 只保留回放需要的信息：谱面身份、设置、起始位置、结果摘要。
func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"chart": {"path": chart_path, "hash": chart_hash},
		"coords": coords,
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
	# 旧文件没有 coords 字段：里面是录制窗口的像素坐标，读的时候按 cursor_size 缩放。
	replay.coords = String(data.get("coords", COORDS_PIXELS if version < 2 else COORDS_UNIT))
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
## 只算「影响判定」的部分（BPM/变速、音符、offset）：改曲名、改配色、
## 编辑器换个存盘路径都不该让回放失效——之前整份 to_dict 一起哈希，
## 连「保存难度套组」这种重写都会换掉 hash。
static func hash_chart(chart: Chart) -> String:
	if chart == null:
		return ""
	var full := ChartIO.chart_to_dict(chart)
	var gameplay := {
		"offset_ms": full.get("offset_ms", 0.0),
		"timing": full.get("timing", {}),
		"notes": full.get("notes", []),
	}
	return JSON.stringify(gameplay).sha256_text()


## 在难度套组 / TMC 工程里找录制时的那张谱；匹配不到再反推旧镜像。
static func match_chart_entry(entries: Array, data: Replay) -> int:
	if data == null or data.chart_hash.is_empty():
		return -1
	for i in entries.size():
		var chart: Chart = (entries[i] as Dictionary).get("chart", null)
		if chart != null and data.chart_hash == hash_chart(chart):
			return i
	for i in entries.size():
		var chart: Chart = (entries[i] as Dictionary).get("chart", null)
		if chart == null:
			continue
		var inferred := infer_mirror(data, chart)
		if not inferred.is_empty():
			data.settings["mirror"] = inferred
			return i
	return -1


## 旧回放没有 settings.mirror：用录制时的谱面 hash 反推镜像模式。
## 录制 hash 以前是按镜像副本算的，所以 lr/rot180 的旧文件能靠这个救回来。
static func infer_mirror(data: Replay, chart: Chart) -> String:
	if data == null or chart == null or data.chart_hash.is_empty():
		return ""
	if data.chart_hash == hash_chart(chart):
		return "off"
	for mode in ["lr", "rot180"]:
		if data.chart_hash == hash_chart(chart.mirrored_copy(mode)):
			return mode
	return ""


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
