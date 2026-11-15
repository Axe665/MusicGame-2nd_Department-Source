class_name ChartIO
extends RefCounted

const FORMAT := "tamaki3-chart"
const VERSION := 1
const PROJECT_FORMAT := "tamaki3-project"
const PROJECT_VERSION := 1

static var last_error: String = ""


static func chart_to_dict(chart: Chart) -> Dictionary:
	var timing_points: Array[Dictionary] = []
	for point in chart.timing.points:
		timing_points.append(point.to_dict())
	var shape_code := BoundaryShape.shapes_to_code(chart.sorted_shapes())
	var key_rows: Array[Dictionary] = []
	for key in chart.sorted_shape_keys():
		key_rows.append({
			"beat": snappedf(float(key.get("beat", 0.0)), 0.001),
			"shape": String(key.get("shape_id", "")),
			"easing": String(key.get("easing", "in-out")),
		})
	var event_list: Array[Dictionary] = []
	if key_rows.is_empty():
		for event in chart.events:
			event_list.append(event.to_dict())
	else:
		# 关键帧是真源；这里同时写一份旧事件，旧版本打开时还能看到形变。
		var legacy_index := 0
		var first := chart.sorted_shape_keys()[0]
		var default_shape := chart.get_default_shape()
		var first_beat := float(first.get("beat", 0.0))
		if default_shape != null and first_beat > 0.001 and String(first.get("shape_id", "")) != default_shape.id:
			event_list.append(_legacy_event(legacy_index, 0.0, first_beat, default_shape.id,
				String(first.get("shape_id", "")), String(first.get("easing", "in-out"))))
			legacy_index += 1
		var keys := chart.sorted_shape_keys()
		for i in keys.size() - 1:
			event_list.append(_legacy_event(legacy_index, float(keys[i].get("beat", 0.0)),
				float(keys[i + 1].get("beat", 0.0)), String(keys[i].get("shape_id", "")),
				String(keys[i + 1].get("shape_id", "")), String(keys[i].get("easing", "in-out"))))
			legacy_index += 1
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
	# 颜色不塞进紧凑代码，避免旧版本读到后缀后整条音符解析失败；
	# 旁挂在 note_colors 里，旧版本会忽略，音符本身照常载入。
	var note_colors := {}
	for note in chart.notes:
		var entry := {}
		if note.color != 0:
			entry["g"] = note.color
		if note.has_custom_color:
			entry["rgb"] = "#" + note.custom_color.to_html(false)
		if not entry.is_empty():
			note_colors[str(note.id)] = entry
	# 锁定同样旁挂，避免每个音符代码都多一段。
	var note_flags := {}
	for note in chart.notes:
		if note.lock:
			note_flags[str(note.id)] = {"lock": true}
	var meta := {}
	for key in ["title", "artist", "creator", "version", "tags", "license", "background"]:
		meta[key] = String(chart.metadata.get(key, ""))
	# 紧凑代码丢不掉的字段旁挂在这里；旧版本读到会直接忽略。
	var note_extras := {}
	for note in chart.notes:
		var extra := {}
		match note.type:
			"hold":
				if note.hold_style != "straight":
					extra["hold_style"] = note.hold_style
				if not note.visual_pts.is_empty():
					extra["visual"] = Note._points_to_dict(note.visual_pts)
			"path":
				extra["tolerance"] = snappedf(note.tolerance, 0.001)
				extra["samples"] = snappedf(note.samples_per_beat, 0.001)
				if note.path_speed != 1.0:
					extra["speed"] = snappedf(note.path_speed, 0.001)
				if note.path_style != "arc":
					extra["path_style"] = note.path_style
				if not note.path_gaps.is_empty():
					extra["path_gaps"] = Note._ranges_to_array(note.path_gaps)
				if not note.trace_pts.is_empty():
					extra["trace"] = Note._points_to_dict(note.trace_pts)
				if not note.visual_pts.is_empty():
					extra["visual"] = Note._points_to_dict(note.visual_pts)
			"bell":
				if absf(note.bell_radius - 1.0) > 0.0001:
					extra["bell_radius"] = snappedf(note.bell_radius, 0.001)
		if not extra.is_empty():
			note_extras[str(note.id)] = extra
	var result := {
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
		"boundary_keys": key_rows,
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
	# 只有真的用了配色才写这两个键：老谱存盘结果保持逐字节不变。
	if not chart.palette.is_empty():
		result["palette"] = _palette_rows(chart)
	if not note_colors.is_empty():
		result["note_colors"] = note_colors
	if not note_flags.is_empty():
		result["note_flags"] = note_flags
	if not note_extras.is_empty():
		result["note_extras"] = note_extras
	return result


## 旧谱迁移：整环事件 → 形状关键帧。局部 u 事件没有对应表达，直接丢弃。
static func _keys_from_events(chart: Chart) -> Array[Dictionary]:
	var keys: Array[Dictionary] = []
	var events := chart.events.duplicate()
	events.sort_custom(func(a: BoundaryEvent, b: BoundaryEvent) -> bool: return a.start_beat < b.start_beat)
	for event in events:
		keys.append({"beat": event.start_beat, "shape_id": event.from_shape, "easing": event.easing})
		var restore_easing: String = event.restore_easing if event.end_behavior == "restore" else "in-out"
		keys.append({"beat": event.end_beat, "shape_id": event.to_shape, "easing": restore_easing})
		if event.end_behavior == "restore" and event.restore_duration > 0.0001:
			keys.append({"beat": event.end_beat + event.restore_duration, "shape_id": event.from_shape, "easing": "in-out"})
	# 同一拍只留最后一个。
	var merged: Array[Dictionary] = []
	for key in keys:
		if not merged.is_empty() and absf(float(merged[-1]["beat"]) - float(key["beat"])) < 0.0005:
			merged[-1] = key
		else:
			merged.append(key)
	return merged


## 旧版本只认 BoundaryEvent：由关键帧推导出等价的 hold 链。
static func _legacy_event(index: int, start: float, end: float, from_id: String, to_id: String, easing: String) -> Dictionary:
	return {
		"id": "E%d" % (index + 1),
		"start_beat": snappedf(start, 0.001),
		"end_beat": snappedf(end, 0.001),
		"target_u0": 0.0,
		"target_u1": 1.0,
		"from_shape": from_id,
		"to_shape": to_id,
		"easing": easing,
		"end_behavior": "hold",
		"restore_duration": 0.0,
		"restore_easing": "in-out",
	}


## note_extras 侧表：补齐紧凑代码丢掉的 Hold/Path/Bell 字段。
static func _apply_note_extras(note: Note, extra: Dictionary) -> void:
	if extra.has("hold_style"):
		note.hold_style = String(extra["hold_style"])
	if extra.has("tolerance"):
		note.tolerance = float(extra["tolerance"])
	if extra.has("samples"):
		note.samples_per_beat = float(extra["samples"])
	if extra.has("speed"):
		note.path_speed = float(extra["speed"])
	if extra.has("path_style"):
		note.path_style = String(extra["path_style"])
	if extra.has("path_gaps"):
		note.path_gaps = Note._ranges_from_array(extra["path_gaps"])
	if extra.has("trace"):
		note.trace_pts = Note._points_from_array(extra["trace"])
	if extra.has("visual"):
		note.visual_pts = Note._points_from_array(extra["visual"])
	if extra.has("bell_radius"):
		note.bell_radius = float(extra["bell_radius"])


static func _palette_rows(chart: Chart) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for group in chart.palette:
		var row := {"name": String(group.get("name", "")).strip_edges()}
		for key in Chart.PALETTE_TYPES:
			row[key] = _hex(String(group.get(key, String(Chart.PALETTE_DEFAULTS[key]))), key)
		rows.append(row)
	return rows


static func _palette_row(raw: Dictionary) -> Dictionary:
	var row := {"name": String(raw.get("name", "")).strip_edges()}
	for key in Chart.PALETTE_TYPES:
		row[key] = _hex(String(raw.get(key, String(Chart.PALETTE_DEFAULTS[key]))), key)
	return row


## 统一成 "#rrggbb"；非法颜色退回该类型的默认色。
static func _hex(text: String, key: String) -> String:
	var value := text.strip_edges()
	if value.is_empty() or not Color.html_is_valid(value):
		return String(Chart.PALETTE_DEFAULTS[key])
	return "#" + Color(value).to_html(false)


static func _apply_note_colors(chart: Chart, stored: Dictionary) -> void:
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	for key in stored.keys():
		var id_text := String(key)
		if not id_text.is_valid_int():
			continue
		var note: Note = by_id.get(int(id_text), null)
		if note == null:
			continue
		var raw: Variant = stored[key]
		if raw is Dictionary:
			if raw.has("g"):
				note.color = maxi(0, int(raw.get("g", 0)))
			if raw.has("rgb"):
				var rgb_text := String(raw.get("rgb", ""))
				if Color.html_is_valid(rgb_text):
					note.custom_color = Color(rgb_text)
					note.has_custom_color = true
		elif raw is int or raw is float:
			note.color = maxi(0, int(raw))


static func _apply_note_flags(chart: Chart, stored: Dictionary) -> void:
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	for key in stored.keys():
		var id_text := String(key)
		if not id_text.is_valid_int():
			continue
		var note: Note = by_id.get(int(id_text), null)
		if note == null:
			continue
		var raw: Variant = stored[key]
		if raw is Dictionary and bool(raw.get("lock", false)):
			note.lock = true


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
	for shape in chart.shapes.values():
		if shape is BoundaryShape:
			# 老谱每段的自定义曲线（si/so/s/b）没有关键帧模型里的等价物，
			# 载入后按直线重采样；这里留一条提示，避免以为是文件坏了。
			for segment in shape.segments:
				if segment.ix != "l" or segment.iy != "l":
					chart.load_warnings.append("形状 %s 的自定义曲线已按直线处理" % shape.id)
					break
			shape.normalize()
	if chart.shapes.is_empty():
		chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 48)
	if not chart.shapes.has(chart.default_shape_id):
		chart.default_shape_id = chart.shapes.keys()[0]
	chart.events.clear()
	chart.shape_keys.clear()
	for raw in data.get("boundary_keys", []):
		if raw is Dictionary:
			chart.shape_keys.append({
				"beat": float(raw.get("beat", 0.0)),
				"shape_id": String(raw.get("shape", raw.get("shape_id", ""))),
				"easing": String(raw.get("easing", "in-out")),
			})
	for raw in data.get("events", []):
		if raw is Dictionary:
			chart.events.append(BoundaryEvent.from_dict(raw))
	if chart.shape_keys.is_empty() and not chart.events.is_empty():
		# 旧谱的局部 u 事件没有对应的关键帧表达：拒绝打开，避免悄悄改掉形变。
		for event in chart.events:
			if event.target_u0 > 0.0001 or event.target_u1 < 0.9999:
				last_error = "旧谱里的局部形变事件 %s 无法转换，请先在旧版本合并成整环再保存" % event.id
				return null
		chart.shape_keys = _keys_from_events(chart)
		chart.events.clear()
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
	chart.palette.clear()
	var palette_raw: Variant = data.get("palette", [])
	if palette_raw is Array:
		for raw in palette_raw:
			if raw is Dictionary:
				chart.palette.append(_palette_row(raw))
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
			# 旧 plane Tap 已移除；旧数据直接跳过，不转成 0° 环上 Tap。
			if String(raw.get("type", "")) == "tap" and String(raw.get("space", "ring")) == "plane":
				continue
			chart.notes.append(Note.from_dict(raw))
	var extras_raw: Variant = data.get("note_extras", {})
	if extras_raw is Dictionary:
		for note in chart.notes:
			var extra: Variant = extras_raw.get(str(note.id), {})
			if extra is Dictionary and not (extra as Dictionary).is_empty():
				_apply_note_extras(note, extra)
	var stored_colors: Variant = data.get("note_colors", {})
	if stored_colors is Dictionary:
		_apply_note_colors(chart, stored_colors)
	var stored_flags: Variant = data.get("note_flags", {})
	if stored_flags is Dictionary:
		_apply_note_flags(chart, stored_flags)
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
	if is_project_path(path):
		var project := load_project(path)
		if not bool(project.get("ok", false)):
			return null
		var entries: Array = project.get("entries", [])
		if entries.is_empty():
			last_error = "谱面工程没有可用难度"
			return null
		return entries[0].get("chart", null)
	if not FileAccess.file_exists(path):
		# A legacy .json path may have been migrated to its project folder.
		if is_project_path(project_dir_for(path)):
			return load_chart(project_dir_for(path))
		last_error = "文件不存在：%s" % path
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取：%s" % path
		return null
	var text := file.get_as_text()
	file.close()
	var chart := from_json(text)
	if chart != null:
		chart.project_dir = ""
		chart.project_main_path = ""
	return chart


static func save_chart(chart: Chart, path: String) -> Error:
	# From this version on, saving a chart writes a project folder. A legacy
	# .json path is converted to <basename>/main.json and removed afterwards.
	var entries: Array = [{"name": String(chart.metadata.get("version", chart.difficulty)), "chart": chart}]
	return save_project(entries, path, String(chart.metadata.get("title", "")), "")


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
		entries.append({"name": name, "stars": float(entry.get("stars", -1.0)), "chart": chart})
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
			# 星数只影响显示与排序；<=0 表示未知，不写进文件。
			"stars": float(entry.get("stars", -1.0)),
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


## ── 谱面工程 ────────────────────────────────────────────────────────────────
static func project_dir_for(path: String) -> String:
	var p := path.trim_suffix("/")
	if p.get_file().to_lower() == "main.json":
		return p.get_base_dir()
	if p.get_extension().is_empty():
		return p
	return p.get_basename()


static func project_main_path(path: String) -> String:
	return project_dir_for(path).path_join("main.json")


static func is_project_path(path: String) -> bool:
	if path.is_empty():
		return false
	var dir := project_dir_for(path)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	return FileAccess.file_exists(dir.path_join("main.json"))


static func load_project(path: String) -> Dictionary:
	last_error = ""
	var dir := project_dir_for(path)
	var main_path := dir.path_join("main.json")
	if not FileAccess.file_exists(main_path):
		last_error = "谱面工程缺少 main.json：%s" % dir
		return {"ok": false, "error": last_error}
	var main := _read_json(main_path)
	if main.is_empty():
		return {"ok": false, "error": last_error}
	if String(main.get("format", "")) != PROJECT_FORMAT:
		last_error = "不是 Tamaki 谱面工程"
		return {"ok": false, "error": last_error}
	var shaped := _read_json(dir.path_join("shaped.json"))
	var color := _read_json(dir.path_join("color.json"))
	var bpm_data := _read_json(dir.path_join("bpmlist.json"))
	var storyboard := _read_json(dir.path_join("storyboard.json"))
	var chart_files := _project_chart_files(dir)
	if chart_files.is_empty():
		last_error = "谱面工程没有 chartN.json"
		return {"ok": false, "error": last_error}
	var names: Array = main.get("difficulty_list", main.get("difficulties", []))
	var points := _project_timing_points(main, bpm_data)
	var view: Dictionary = main.get("view", {})
	var entries: Array = []
	for i in chart_files.size():
		var part := _read_json(dir.path_join(String(chart_files[i])))
		if part.is_empty():
			continue
		var name := String(part.get("difficulty", ""))
		if name.is_empty() and i < names.size():
			name = String(names[i])
		if name.is_empty():
			name = "难度 %d" % (i + 1)
		var music := String(main.get("music", ""))
		var audio := dir.path_join(music) if not music.is_empty() else ""
		var jacket := String(main.get("jacket", ""))
		var data := {
			"format": FORMAT,
			"version": VERSION,
			"general": {
				"audio": audio,
				"video": "",
				"offset_ms": float(main.get("offset_ms", 0.0)),
				"pre_read_ms": float(main.get("pre_read_ms", 1000.0)),
				"difficulty": name,
			},
			"metadata": {
				"title": String(main.get("title", "")),
				"artist": String(main.get("artist", "")),
				"creator": String(main.get("creator", main.get("charter", ""))),
				"version": name,
				"tags": String(main.get("tags", "")),
				"license": String(main.get("license", "")),
				"background": dir.path_join(jacket) if not jacket.is_empty() else "",
			},
			"timing": {"offset_ms": float(main.get("offset_ms", 0.0)), "points": points},
			"default_shape": String(view.get("default_shape", main.get("default_shape", "S0"))),
			"shapes": String(shaped.get("shapes", "")),
			"events": storyboard.get("events", []),
			"shape_keys": storyboard.get("shape_keys", []),
			"view_states": view.get("view_states", main.get("view_states", [])),
			"regions": part.get("regions", []),
			"notes": part.get("notes", []),
			"editor": view.get("editor", main.get("editor", {})),
			"note_extras": part.get("note_extras", {}),
			"note_flags": part.get("note_flags", {}),
			"note_colors": _project_colors_for(color, i),
			"palette": color.get("palette", []),
		}
		var chart := chart_from_dict(data)
		if chart == null:
			continue
		chart.project_dir = dir
		chart.project_main_path = main_path
		entries.append({"name": name, "chart": chart})
	if entries.is_empty():
		last_error = "谱面工程没有可用难度"
		return {"ok": false, "error": last_error}
	return {
		"ok": true,
		"title": String(main.get("title", "")),
		"source": String(main.get("source", "")),
		"dir": dir,
		"main_path": main_path,
		"entries": entries,
	}


static func save_project(entries: Array, path: String, title: String = "", source: String = "") -> Error:
	if entries.is_empty():
		last_error = "没有可保存的难度"
		return ERR_INVALID_DATA
	var dir := project_dir_for(path)
	var main_path := dir.path_join("main.json")
	var legacy_path := path if path.to_lower().ends_with(".json") and path.get_file().to_lower() != "main.json" else ""
	DirAccess.make_dir_recursive_absolute(dir)
	var first: Chart = entries[0].get("chart", null)
	if first == null:
		last_error = "第一个难度为空"
		return ERR_INVALID_DATA
	var base := chart_to_dict(first)
	var meta: Dictionary = first.metadata
	var names: Array[String] = []
	for entry in entries:
		names.append(String(entry.get("name", "难度")))
	var audio_name := _copy_project_audio(first, dir)
	var jacket_name := _copy_project_jacket(first, dir)
	var view := {
		"editor": base.get("editor", {}),
		"view_states": base.get("view_states", []),
		"default_shape": base.get("default_shape", "S0"),
	}
	var main := {
		"format": PROJECT_FORMAT,
		"version": PROJECT_VERSION,
		"title": String(meta.get("title", title)),
		"artist": String(meta.get("artist", "")),
		"charter": String(meta.get("creator", "")),
		"creator": String(meta.get("creator", "")),
		"difficulty": names[0],
		"difficulty_list": names,
		"bpm": _first_bpm(first),
		"beats_per_bar": _first_beats_per_bar(first),
		"offset_ms": snappedf(first.offset_ms, 0.001),
		"pre_read_ms": snappedf(first.pre_read_ms, 0.001),
		"music": audio_name,
		"jacket": jacket_name,
		"view": view,
		"source": source,
	}
	var err := atomic_write(main_path, JSON.stringify(main, "\t", false) + "\n", false)
	if err != OK:
		return err
	err = atomic_write(dir.path_join("shaped.json"), JSON.stringify({
		"format": "tamaki3-shapes",
		"version": 1,
		"shapes": String(base.get("shapes", "")),
	}, "\t", false) + "\n", false)
	if err != OK:
		return err
	var bpm_changes := _project_bpm_changes(first)
	var bpm_path := dir.path_join("bpmlist.json")
	if bpm_changes.is_empty():
		if FileAccess.file_exists(bpm_path):
			DirAccess.remove_absolute(bpm_path)
	else:
		err = atomic_write(bpm_path, JSON.stringify({"changes": bpm_changes}, "\t", false) + "\n", false)
		if err != OK:
			return err
	var events: Array = base.get("events", [])
	var keys: Array = base.get("shape_keys", [])
	var story_path := dir.path_join("storyboard.json")
	if events.is_empty() and keys.is_empty():
		if FileAccess.file_exists(story_path):
			DirAccess.remove_absolute(story_path)
	else:
		err = atomic_write(story_path, JSON.stringify({
			"format": "tamaki3-storyboard",
			"version": 1,
			"events": events,
			"shape_keys": keys,
		}, "\t", false) + "\n", false)
		if err != OK:
			return err
	var color_charts: Array = []
	for i in entries.size():
		var chart: Chart = entries[i].get("chart", null)
		if chart == null:
			continue
		var part := chart_to_dict(chart)
		var part_data := {
			"format": FORMAT,
			"version": VERSION,
			"difficulty": String(entries[i].get("name", "难度")),
			"notes": part.get("notes", []),
			"regions": part.get("regions", []),
			"note_flags": part.get("note_flags", {}),
			"note_extras": part.get("note_extras", {}),
		}
		err = atomic_write(dir.path_join("chart%d.json" % i), JSON.stringify(part_data, "\t", false) + "\n", false)
		if err != OK:
			return err
		color_charts.append({
			"name": String(entries[i].get("name", "难度")),
			"notes": _project_color_codes(chart),
		})
	var color_data := {
		"format": "tamaki3-colors",
		"version": 1,
		"default": "begin",
		"palette": base.get("palette", []),
		"notes": color_charts[0].get("notes", []) if color_charts.size() == 1 else [],
	}
	if color_charts.size() > 1:
		color_data["charts"] = color_charts
	err = atomic_write(dir.path_join("color.json"), JSON.stringify(color_data, "\t", false) + "\n", false)
	if err != OK:
		return err
	# Remove stale chartN.json when difficulties were removed.
	for name in _project_chart_files(dir):
		var index_text := String(name).get_basename().trim_prefix("chart")
		if index_text.is_valid_int() and int(index_text) >= entries.size():
			DirAccess.remove_absolute(dir.path_join(String(name)))
	for chart_entry in entries:
		var chart: Chart = chart_entry.get("chart", null)
		if chart != null:
			chart.project_dir = dir
			chart.project_main_path = main_path
	for name in DirAccess.get_files_at(dir):
		if String(name).contains(".bak."):
			DirAccess.remove_absolute(dir.path_join(String(name)))
	if not legacy_path.is_empty() and FileAccess.file_exists(legacy_path):
		DirAccess.remove_absolute(legacy_path)
	return OK


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var text := file.get_as_text()
	file.close()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		last_error = "JSON 解析失败：%s" % path
		return {}
	return parser.data


static func _project_chart_files(dir: String) -> Array[String]:
	var names: Array[String] = []
	var files := DirAccess.get_files_at(dir)
	for name in files:
		if name.begins_with("chart") and name.ends_with(".json") and name.substr(5, name.length() - 10).is_valid_int():
			names.append(name)
	if names.is_empty() and FileAccess.file_exists(dir.path_join("chart.json")):
		names.append("chart.json")
	names.sort_custom(func(a: String, b: String) -> bool:
		var ai := String(a).get_basename().trim_prefix("chart")
		var bi := String(b).get_basename().trim_prefix("chart")
		return (int(ai) if ai.is_valid_int() else 0) < (int(bi) if bi.is_valid_int() else 0))
	return names


static func _project_timing_points(main: Dictionary, bpm_data: Dictionary) -> Array:
	var points: Array = [{
		"beat": 0.0,
		"bpm": float(main.get("bpm", 120.0)),
		"beats_per_bar": int(main.get("beats_per_bar", 4)),
	}]
	var changes: Array = bpm_data.get("changes", [])
	var regex := RegEx.new()
	regex.compile("\\[\\s*([0-9.]+)\\s*\\]\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9]+)\\s*\\)")
	for raw in changes:
		var found := regex.search(String(raw))
		if found != null:
			points.append({
				"beat": float(found.get_string(1)),
				"bpm": float(found.get_string(2)),
				"beats_per_bar": int(found.get_string(3)),
			})
	return points


static func _project_bpm_changes(chart: Chart) -> Array[String]:
	var result: Array[String] = []
	if chart.timing.points.size() <= 1:
		return result
	for i in range(1, chart.timing.points.size()):
		var point := chart.timing.points[i]
		result.append("[%s](%s,%d)" % [
			str(snappedf(point.beat, 0.001)), str(snappedf(point.bpm, 0.001)),
			point.beats_per_bar,
		])
	return result


static func _project_colors_for(color: Dictionary, index: int) -> Dictionary:
	var rows: Array = color.get("notes", [])
	var charts: Array = color.get("charts", [])
	if index < charts.size() and charts[index] is Dictionary:
		rows = (charts[index] as Dictionary).get("notes", [])
	var result := {}
	var regex := RegEx.new()
	regex.compile("^\\[(\\d+)\\][^(]*\\((\\d+)\\)$")
	for raw in rows:
		var found := regex.search(String(raw).strip_edges())
		if found != null:
			result[found.get_string(1)] = {"g": int(found.get_string(2))}
	return result


static func _project_color_codes(chart: Chart) -> Array[String]:
	var result: Array[String] = []
	for note in chart.sorted_notes():
		if note.color != 0:
			result.append("[%d]%s(%d)" % [note.id, note.type, note.color])
	return result


static func _copy_project_audio(chart: Chart, dir: String) -> String:
	if chart.audio_path.is_empty():
		return ""
	var ext := chart.audio_path.get_extension().to_lower()
	if ext.is_empty():
		ext = "wav"
	var target := dir.path_join("music." + ext)
	if chart.audio_path == target:
		return target.get_file()
	if _copy_file(chart.audio_path, target):
		return target.get_file()
	return ""


static func _copy_project_jacket(chart: Chart, dir: String) -> String:
	var source := String(chart.metadata.get("background", ""))
	if source.is_empty():
		return ""
	var ext := source.get_extension().to_lower()
	if ext not in ["jpg", "jpeg", "png"]:
		return ""
	var target := dir.path_join("jacket." + ext)
	if source != target and not _copy_file(source, target):
		return ""
	return target.get_file()


static func _copy_file(source: String, target: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false
	var data := input.get_buffer(input.get_length())
	input.close()
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null:
		return false
	output.store_buffer(data)
	output.close()
	return true


static func _first_bpm(chart: Chart) -> float:
	return chart.timing.points[0].bpm if not chart.timing.points.is_empty() else 120.0


static func _first_beats_per_bar(chart: Chart) -> int:
	return chart.timing.points[0].beats_per_bar if not chart.timing.points.is_empty() else 4


static func atomic_write(path: String, text: String, backup: bool = true) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	if backup and FileAccess.file_exists(path):
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


## 视频流：.ogv 走引擎自带 Theora；其他格式用 gdffmpeg 直接解码（不转码）。
## 没装解码扩展时返回 null，调用方再退回 ffmpeg 转码缓存。
static func video_stream_from_path(path: String) -> VideoStream:
	if path.is_empty():
		return null
	var ext := path.get_extension().to_lower()
	if ext == "ogv":
		if path.begins_with("res://"):
			return load(path) as VideoStream
		var theora := VideoStreamTheora.new()
		theora.file = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
		return theora
	if not ffmpeg_video_available() or not FileAccess.file_exists(path):
		return null
	if not (ext in MediaIO.SUPPORTED_VIDEO):
		return null
	var stream: Variant = ClassDB.instantiate("FFmpegVideoStream")
	if stream == null:
		return null
	stream.set("file", ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
	return stream as VideoStream


## gdffmpeg 扩展是否加载成功（addons/ffmpeg）。
static func ffmpeg_video_available() -> bool:
	return ClassDB.class_exists("FFmpegVideoStream")


## 能否不转码直接播：原生 ogv，或装了 gdffmpeg 且扩展名在支持表里。
static func can_decode_video_directly(path: String) -> bool:
	if path.is_empty():
		return false
	var ext := path.get_extension().to_lower()
	if ext == "ogv":
		return true
	return ffmpeg_video_available() and ext in MediaIO.SUPPORTED_VIDEO


static func resolve_path(_chart_path: String, path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	# v2.1 paths are relative to the project, not to the chart file.
	return "res://" + path.trim_prefix("/")
