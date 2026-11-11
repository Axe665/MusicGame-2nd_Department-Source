class_name ChartIO
extends RefCounted

const FORMAT := "tamaki3-chart"
const VERSION := 1

static var last_error: String = ""


static func chart_to_dict(chart: Chart) -> Dictionary:
	var timing_points: Array[Dictionary] = []
	for point in chart.timing.points:
		timing_points.append(point.to_dict())
	var shape_code := BoundaryShape.shapes_to_code(chart.sorted_shapes())
	var event_list: Array[Dictionary] = []
	for event in chart.events:
		event_list.append(event.to_dict())
	event_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["start_beat"]) == float(b["start_beat"]):
			return String(a["id"]) < String(b["id"])
		return float(a["start_beat"]) < float(b["start_beat"]))
	var view_list: Array[Dictionary] = []
	for state in chart.view_states:
		view_list.append(state.to_dict())
	view_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["beat"]) < float(b["beat"]))
	var region_rows: Array[Dictionary] = []
	for region in chart.regions:
		region_rows.append({"beat": region.start_beat, "id": region.id, "code": region.to_code()})
	region_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["beat"]) == float(b["beat"]):
			return int(a["id"]) < int(b["id"])
		return float(a["beat"]) < float(b["beat"]))
	var region_list: Array[String] = []
	for row in region_rows:
		region_list.append(String(row["code"]))
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	var note_entries: Array[Dictionary] = []
	for note in chart.notes:
		if note.type == "path" and note.path_prev_id >= 0 and by_id.has(note.path_prev_id):
			continue
		var code: String = _note_code(note, by_id)
		if code.is_empty():
			continue
		note_entries.append({"beat": note.beat, "id": note.id, "code": code})
	note_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["beat"]) == float(b["beat"]):
			return int(a["id"]) < int(b["id"])
		return float(a["beat"]) < float(b["beat"]))
	var note_list: Array[String] = []
	for entry in note_entries:
		note_list.append(String(entry["code"]))
	var meta := {}
	for key in ["title", "artist", "creator", "version", "tags", "license", "background"]:
		meta[key] = String(chart.metadata.get(key, ""))
	return {
		"format": FORMAT,
		"version": VERSION,
		"general": {
			"audio": chart.audio_path,
			"video": chart.video_path,
			"video_offset_ms": snappedf(chart.video_offset_ms, 0.001),
			"video_fps": snappedf(chart.video_fps, 0.001),
			"video_opacity": snappedf(chart.video_opacity, 0.001),
			"pre_read_ms": snappedf(chart.pre_read_ms, 0.001),
			"offset_ms": snappedf(chart.offset_ms, 0.001),
			"difficulty": chart.difficulty,
		},
		"metadata": meta,
		"default_shape": chart.default_shape_id,
		"shapes": shape_code,
		"events": event_list,
		"view_states": view_list,
		"regions": region_list,
		"timing": {
			"offset_ms": snappedf(chart.offset_ms, 0.001),
			"points": timing_points,
		},
		"notes": note_list,
		"editor": {
			"snap": int(chart.editor.get("snap", 4)),
			"zoom": snappedf(float(chart.editor.get("zoom", 1.0)), 0.001),
			"waveform": bool(chart.editor.get("waveform", true)),
			"hud": bool(chart.editor.get("hud", true)),
			"flow_down": bool(chart.editor.get("flow_down", true)),
		},
	}


static func _note_code(note: Note, by_id: Dictionary) -> String:
	if note.type != "path" or note.path_next_id < 0:
		return note.to_code()
	var chain: Array[Note] = []
	var cursor: Note = note
	var guard := 0
	while cursor != null and guard < 64:
		chain.append(cursor)
		if cursor.path_next_id < 0 or not by_id.has(cursor.path_next_id):
			break
		cursor = by_id[cursor.path_next_id]
		guard += 1
	var segments: Array[String] = []
	for i in chain.size():
		var part := chain[i]
		segments.append(part.path_part_code())
	return "[%d]path{%s}" % [note.id, ";".join(segments)]


static func chart_from_dict(data: Dictionary) -> Chart:
	last_error = ""
	if String(data.get("format", FORMAT)) != FORMAT:
		last_error = "不是 Tamaki₃ 谱面文件"
		return null
	var chart := Chart.new()
	chart.format_version = int(data.get("version", VERSION))
	var general: Dictionary = data.get("general", {})
	chart.audio_path = String(general.get("audio", ""))
	chart.video_path = String(general.get("video", ""))
	chart.video_offset_ms = float(general.get("video_offset_ms", 0.0))
	chart.video_fps = float(general.get("video_fps", 60.0))
	chart.video_opacity = float(general.get("video_opacity", 0.35))
	chart.pre_read_ms = float(general.get("pre_read_ms", 1000.0))
	chart.offset_ms = float(general.get("offset_ms", 0.0))
	chart.difficulty = String(general.get("difficulty", "Normal"))
	var meta: Dictionary = data.get("metadata", {})
	for key in ["title", "artist", "creator", "version", "tags", "license", "background"]:
		chart.metadata[key] = String(meta.get(key, ""))
	var timing_data: Dictionary = data.get("timing", {})
	chart.timing = TimingMap.new()
	chart.timing.points.clear()
	chart.timing.offset_ms = float(timing_data.get("offset_ms", chart.offset_ms))
	var points_raw: Array = timing_data.get("points", [])
	if points_raw.is_empty():
		points_raw = [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]
	for raw in points_raw:
		if raw is Dictionary:
			chart.timing.points.append(TimingPoint.from_dict(raw))
	chart.timing.sort_points()
	chart.default_shape_id = String(data.get("default_shape", "S0"))
	chart.shapes.clear()
	var shapes_raw: Variant = data.get("shapes", [])
	if shapes_raw is String:
		for shape in BoundaryShape.shapes_from_code(shapes_raw):
			chart.shapes[shape.id] = shape
	elif shapes_raw is Array:
		for raw in shapes_raw:
			if raw is String:
				for shape in BoundaryShape.shapes_from_code(raw):
					chart.shapes[shape.id] = shape
			elif raw is Dictionary:
				var shape := BoundaryShape.from_dict(raw)
				chart.shapes[shape.id] = shape
	elif shapes_raw is Dictionary:
		for key in shapes_raw.keys():
			if shapes_raw[key] is Dictionary:
				var shape := BoundaryShape.from_dict(shapes_raw[key])
				chart.shapes[shape.id] = shape
	if chart.shapes.is_empty():
		chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 32)
	if not chart.shapes.has(chart.default_shape_id):
		chart.default_shape_id = chart.shapes.keys()[0]
	chart.events.clear()
	for raw in data.get("events", []):
		if raw is Dictionary:
			chart.events.append(BoundaryEvent.from_dict(raw))
	chart.view_states.clear()
	for raw in data.get("view_states", []):
		if raw is Dictionary:
			chart.view_states.append(ViewState.from_dict(raw))
	if chart.view_states.is_empty():
		chart.view_states.append(ViewState.new())
	chart.regions.clear()
	for raw in data.get("regions", []):
		if raw is Dictionary:
			var region := Region.from_dict(raw)
			if region.kind == "red":
				region.kind = "limit"
			chart.regions.append(region)
		elif raw is String:
			var region := Region.from_code(raw)
			if region != null:
				chart.regions.append(region)
	chart.notes.clear()
	for raw in data.get("notes", []):
		if raw is String:
			var code: String = raw.strip_edges()
			if code.contains("path{"):
				chart.notes.append_array(Note.path_parts_from_code(code))
			else:
				var parsed := Note.from_code(code)
				if parsed != null:
					chart.notes.append(parsed)
		elif raw is Dictionary and String(raw.get("type", "")) != "trace":
			chart.notes.append(Note.from_dict(raw))
	# Normalize legacy Path JSON to the new centrifuge/axis representation on
	# every chart load, not just for the bundled demo.
	for note in chart.notes:
		if note.type == "path" and note.path_legacy:
			note.generate_path_shape()
			note.path_legacy = false
	chart.merge_center_bells()
	chart.editor = data.get("editor", {}).duplicate(true)
	chart.refresh_ids()
	return chart


static func to_json(chart: Chart) -> String:
	return JSON.stringify(chart_to_dict(chart), "\t", false) + "\n"


static func from_json(text: String) -> Chart:
	last_error = ""
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		last_error = "JSON 解析失败：%s（第 %d 行）" % [parser.get_error_message(), parser.get_error_line()]
		return null
	var data: Variant = parser.data
	if data is not Dictionary:
		last_error = "谱面根节点必须是对象"
		return null
	return chart_from_dict(data)


static func load_chart(path: String) -> Chart:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "文件不存在：%s" % path
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取：%s" % path
		return null
	var text := file.get_as_text()
	file.close()
	return from_json(text)


static func save_chart(chart: Chart, path: String) -> Error:
	var text := to_json(chart)
	return atomic_write(path, text)


## ── 难度套组（一首歌多个难度，存成一个文件）──────────────────────────────
const SET_FORMAT := "tamaki3-set"


static func is_set_dict(data: Dictionary) -> bool:
	return String(data.get("format", "")) == SET_FORMAT


## 读一个套组文件：entries = [{"name": String, "chart": Chart}]。
static func load_set(path: String) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "文件不存在：%s" % path
		return {"ok": false, "error": last_error}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取：%s" % path
		return {"ok": false, "error": last_error}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		last_error = "JSON 解析失败：%s" % parser.get_error_message()
		return {"ok": false, "error": last_error}
	var data: Variant = parser.data
	if not (data is Dictionary) or not is_set_dict(data):
		last_error = "不是难度套组文件"
		return {"ok": false, "error": last_error}
	var raw: Dictionary = data
	var entries: Array = []
	for item in raw.get("difficulties", []):
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var chart_data: Variant = entry.get("chart", {})
		if not (chart_data is Dictionary):
			continue
		var chart := chart_from_dict(chart_data)
		if chart == null:
			continue
		var name := String(entry.get("name", "难度"))
		chart.metadata["version"] = name
		entries.append({"name": name, "chart": chart})
	if entries.is_empty():
		last_error = "套组里没有可用的难度"
		return {"ok": false, "error": last_error}
	return {
		"ok": true,
		"title": String(raw.get("title", "")),
		"source": String(raw.get("source", "")),
		"entries": entries,
	}


static func save_set(path: String, entries: Array, title: String = "", source: String = "") -> Error:
	var difficulties: Array = []
	for item in entries:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var chart: Chart = entry.get("chart", null)
		if chart == null:
			continue
		difficulties.append({
			"name": String(entry.get("name", "难度")),
			"chart": chart_to_dict(chart),
		})
	if difficulties.is_empty():
		last_error = "没有可保存的难度"
		return ERR_INVALID_DATA
	var data := {
		"format": SET_FORMAT,
		"version": 1,
		"title": title,
		"source": source,
		"difficulties": difficulties,
	}
	return atomic_write(path, JSON.stringify(data, "\t", true) + "\n")


static func atomic_write(path: String, text: String) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	if FileAccess.file_exists(path):
		_backup(path)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入临时文件：%s" % tmp
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "无法替换目标文件：%s" % path
	return err


static func _backup(path: String) -> void:
	for i in range(5, 1, -1):
		var older := "%s.bak.%d" % [path, i - 1]
		var newer := "%s.bak.%d" % [path, i]
		if FileAccess.file_exists(older):
			if FileAccess.file_exists(newer):
				DirAccess.remove_absolute(newer)
			DirAccess.copy_absolute(older, newer)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak.1")


static func copy_audio_to_user(source: String) -> String:
	if source.begins_with("res://") or source.begins_with("user://"):
		return source
	if not FileAccess.file_exists(source):
		return ""
	var target_dir := "user://audio"
	DirAccess.make_dir_recursive_absolute(target_dir)
	var target := target_dir.path_join(source.get_file())
	if DirAccess.copy_absolute(source, target) != OK:
		return ""
	return target


static func audio_stream_from_path(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var ext := path.get_extension().to_lower()
	if path.begins_with("res://") and ext in MediaIO.NATIVE_AUDIO:
		return load(path) as AudioStream
	var resolved := path
	if path.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(path)
	match ext:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(resolved)
		"wav":
			return AudioStreamWAV.load_from_file(resolved)
		"mp3":
			return AudioStreamMP3.load_from_file(resolved)
	# FLAC is not a native Godot stream class; decode it through ffmpeg into
	# the cached OGG and load that instead.
	if ext == "flac":
		var prepared := MediaIO.prepare_audio(path)
		if not prepared.is_empty() and prepared != path:
			return audio_stream_from_path(prepared)
	return load(path) as AudioStream


static func video_stream_from_path(path: String) -> VideoStream:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as VideoStream
	if path.get_extension().to_lower() == "ogv":
		var theora := VideoStreamTheora.new()
		theora.file = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
		return theora
	return null


static func resolve_path(_chart_path: String, path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	# v2.1 paths are relative to the project, not to the chart file.
	return "res://" + path.trim_prefix("/")
