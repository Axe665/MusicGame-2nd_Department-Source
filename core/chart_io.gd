class_name ChartIO
extends RefCounted

const FORMAT := "tamaki3-chart"
## v3：形状/镜头关键帧的过渡改为「目标帧前完成」，新增镜头 dolly/入场过渡时长；
## 不再双写旧 events。v1/v2 读入时自动迁移，保持旧演出。
const VERSION := 3

static var last_error: String = ""


static func chart_to_dict(chart: Chart) -> Dictionary:
	# 序列化前补稳定 id：旧内存谱面也能写出可往返的 v2。
	chart.ensure_key_ids()
	var timing_points: Array[Dictionary] = []
	for point in chart.timing.points:
		timing_points.append(point.to_dict())
	var shape_code := BoundaryShape.shapes_to_code(chart.sorted_shapes())
	# 直接对原始数组排序，不读 Chart 的排序缓存：缓存失效一旦漏掉，
	# 这里会把新加的关键帧整帧丢掉（存盘/撤销快照都会少一帧）。
	var sorted_keys: Array = chart.shape_keys.duplicate()
	sorted_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	var key_rows: Array[Dictionary] = []
	var previous_beat := 0.0
	for index in sorted_keys.size():
		var key: Dictionary = sorted_keys[index]
		var key_beat := float(key.get("beat", 0.0))
		var row := {
			"beat": snappedf(key_beat, 0.001),
			"shape": String(key.get("shape_id", "")),
			"easing": String(key.get("easing", "in-out")),
			"id": int(key.get("id", 0)),
		}
		# morph = 进入本帧的过渡拍数：0 = 硬切，span = 整段。第一帧的上一帧
		# 是 0 拍的默认圆，所以它的上限就是自己的拍号。
		var max_morph := maxf(0.0, key_beat - previous_beat)
		row["morph"] = snappedf(clampf(float(key.get("morph", 0.0)), 0.0, max_morph), 0.001)
		var curve: Array = key.get("curve", [])
		if curve.size() == 4:
			row["curve"] = [snappedf(float(curve[0]), 0.001), snappedf(float(curve[1]), 0.001),
				snappedf(float(curve[2]), 0.001), snappedf(float(curve[3]), 0.001)]
		key_rows.append(row)
		previous_beat = key_beat
	# 现代谱只写 boundary_keys，不再生成旧 events 副本：副本会在删光关键帧后
	# 被当成真源，重开时把已删的动画带回来。只有纯旧谱（没有关键帧）才保留。
	var event_list: Array[Dictionary] = []
	if key_rows.is_empty():
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
	for key in ["title", "artist", "creator", "version", "tags", "license", "background", "storyboard"]:
		meta[key] = String(chart.metadata.get(key, ""))
	# 宽屏故事板标志：不存的话重开谱面会退回按内容猜（854/640 混判）。
	if bool(chart.metadata.get("widescreen", false)):
		meta["widescreen"] = 1
	# 正对镜头：旧谱没有这个键时按 true 读，保持原来的「倾斜不参与演出」。
	meta["face_camera"] = 1 if bool(chart.metadata.get("face_camera", true)) else 0
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
			"beat_subdivisions": clampi(int(chart.editor.get("beat_subdivisions", 4)), 1, TimingMap.MAX_BEAT_SUBDIVISIONS),
			"rail_snap": bool(chart.editor.get("rail_snap", true)),
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
		# 事件开始：硬切成 from_shape；事件结束：在 end 前整段完成到 to_shape。
		keys.append({"beat": event.start_beat, "shape_id": event.from_shape,
			"morph": 0.0, "easing": "linear"})
		keys.append({"beat": event.end_beat, "shape_id": event.to_shape,
			"morph": maxf(0.0, event.end_beat - event.start_beat), "easing": event.easing})
		if event.end_behavior == "restore" and event.restore_duration > 0.0001:
			keys.append({"beat": event.end_beat + event.restore_duration, "shape_id": event.from_shape,
				"morph": event.restore_duration, "easing": event.restore_easing})
	# 同一拍只留一个：同形状时保留更长的入场过渡（事件首尾相接的链），
	# 不同形状时后一个事件硬切，保持旧事件的覆盖顺序。
	var merged: Array[Dictionary] = []
	for key in keys:
		if merged.is_empty() or absf(float(merged[-1]["beat"]) - float(key["beat"])) >= 0.0005:
			merged.append(key)
			continue
		var previous: Dictionary = merged[-1]
		if String(previous.get("shape_id", "")) == String(key.get("shape_id", "")):
			if float(key.get("morph", 0.0)) > float(previous.get("morph", 0.0)):
				previous["morph"] = key.get("morph", 0.0)
				previous["easing"] = key.get("easing", "in-out")
		else:
			merged[-1] = key
	return merged


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
	var file_version := int(data.get("version", 1))
	if file_version > VERSION:
		last_error = "谱面版本过新（v%d），请升级制谱器" % file_version
		return null
	var chart := Chart.new()
	chart.format_version = file_version
	var general: Dictionary = data.get("general", {})
	chart.audio_path = String(general.get("audio", ""))
	chart.video_path = String(general.get("video", ""))
	chart.video_offset_ms = float(general.get("video_offset_ms", 0.0))
	chart.video_fps = float(general.get("video_fps", 60.0))
	chart.video_opacity = float(general.get("video_opacity", 0.35))
	# 旧文件里的 general.pre_read_ms 读进来直接忽略：飞行时长固定 1 秒（Chart.NOTE_FALL_MS）。
	chart.offset_ms = float(general.get("offset_ms", 0.0))
	chart.difficulty = String(general.get("difficulty", "Normal"))
	var meta: Dictionary = data.get("metadata", {})
	for key in ["title", "artist", "creator", "version", "tags", "license", "background", "storyboard"]:
		chart.metadata[key] = String(meta.get(key, ""))
	# 兼容旧存档：没有这个键就交给故事板内容启发式判断。
	if meta.has("widescreen"):
		chart.metadata["widescreen"] = int(meta.get("widescreen", 0)) != 0
	# 旧谱没有 face_camera：按 true 读，保持倾斜/椭圆不进入演出的旧行为。
	chart.metadata["face_camera"] = int(meta.get("face_camera", 1)) != 0
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
			var key_row := {
				"beat": float(raw.get("beat", 0.0)),
				"shape_id": String(raw.get("shape", raw.get("shape_id", ""))),
				"easing": String(raw.get("easing", "in-out")),
				"id": int(raw.get("id", 0)),
			}
			# v3 总是写 morph（0 = 硬切）；v1/v2 缺字段表示整段，迁移时补。
			if raw.has("morph"):
				key_row["morph"] = float(raw.get("morph", 0.0))
			var raw_curve: Variant = raw.get("curve", [])
			if raw_curve is Array and (raw_curve as Array).size() == 4:
				key_row["curve"] = [float(raw_curve[0]), float(raw_curve[1]),
					float(raw_curve[2]), float(raw_curve[3])]
			chart.shape_keys.append(key_row)
	for raw in data.get("events", []):
		if raw is Dictionary:
			chart.events.append(BoundaryEvent.from_dict(raw))
	if not chart.shape_keys.is_empty():
		# 形状帧是真源：旧文件里那份等价的 events 直接丢掉，避免事件轨重复
		# 和「删光关键帧后旧 events 把动画带回来」。
		chart.events.clear()
	elif not chart.events.is_empty():
		# 旧谱的局部 u 事件没有对应的关键帧表达：拒绝打开，避免悄悄改掉形变。
		for event in chart.events:
			if event.target_u0 > 0.0001 or event.target_u1 < 0.9999:
				last_error = "旧谱里的局部形变事件 %s 无法转换，请先在旧版本合并成整环再保存" % event.id
				return null
		chart.shape_keys = _keys_from_events(chart)
		chart.events.clear()
	chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	if file_version < 3 and not chart.shape_keys.is_empty():
		# v1/v2：旧 key[i] 的 morph/easing 管 i→i+1（离开源帧就开始变）。
		# v3 改成目标帧前完成，等价迁移是把 i 的过渡搬到 i+1；整段过渡完全等价，
		# 短过渡会从「变完再保持」变成「保持到目标帧前再变」。
		var shifted := false
		for i in range(chart.shape_keys.size() - 1, 0, -1):
			var before: Dictionary = chart.shape_keys[i - 1]
			var target: Dictionary = chart.shape_keys[i]
			var span := maxf(0.0, float(target.get("beat", 0.0)) - float(before.get("beat", 0.0)))
			var old_morph := float(before.get("morph", span))
			if old_morph > 0.0001 and old_morph < span - 0.0001:
				shifted = true
			target["easing"] = String(before.get("easing", "in-out"))
			target["curve"] = (before.get("curve", []) as Array).duplicate()
			target["morph"] = clampf(old_morph, 0.0, span)
		var first: Dictionary = chart.shape_keys[0]
		if not first.has("morph"):
			# 旧谱第一帧之前从默认圆整段渐变到第一帧。
			first["morph"] = maxf(0.0, float(first.get("beat", 0.0)))
		if shifted:
			chart.load_warnings.append("旧谱的短形变已改为在目标帧前完成，请检查过渡位置")
	chart.view_states.clear()
	for raw in data.get("view_states", []):
		if raw is Dictionary:
			chart.view_states.append(ViewState.from_dict(raw))
	if chart.view_states.is_empty():
		chart.view_states.append(ViewState.new())
	chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
	if file_version == 2:
		# v2 的镜头缓动存在左帧（出向）；v3 归目标帧（入场），等价迁移是
		# 把左帧的 easing/curve 搬到右帧。v1 本来就用目标帧，不需要动。
		for i in range(chart.view_states.size() - 2, -1, -1):
			chart.view_states[i + 1].easing = chart.view_states[i].easing
			chart.view_states[i + 1].curve = (chart.view_states[i].curve as Array).duplicate()
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
	chart.ensure_key_ids()
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
