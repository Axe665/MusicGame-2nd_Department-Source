class_name ChartIO
extends RefCounted

const FORMAT := "tamaki3-chart"
## v3：形状/镜头关键帧的过渡改为「目标帧前完成」，新增镜头 dolly/入场过渡时长；
## 不再双写旧 events。v1/v2 读入时自动迁移，保持旧演出。
## v4：Anchor 的 width 改成胶囊实际弧宽（8–120°，未设置为 30°）；v3 及更早的 0/60 收敛成未设置。
const VERSION := 4
const PROJECT_FORMAT := "tamaki3-project"
const PROJECT_VERSION := 1

static var last_error: String = ""


const LoadTrace = preload("res://core/load_trace.gd")


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
	# 演出指令单独一段：旧版本读到会忽略，音符代码不受影响。
	var command_rows: Array[Dictionary] = []
	for command in chart.sorted_commands():
		command_rows.append(command.to_dict())
	# 正对镜头：旧谱没有这个键时按 true 读，保持原来的「倾斜不参与演出」。
	meta["face_camera"] = 1 if bool(chart.metadata.get("face_camera", true)) else 0
	# 紧凑代码丢不掉的字段旁挂在这里；旧版本读到会直接忽略。
	var note_extras := {}
	for note in chart.notes:
		var extra := {}
		match note.type:
			"hold":
				if not note.visual_pts.is_empty():
					extra["visual"] = Note._points_to_dict(note.visual_pts)
			"path":
				extra["tolerance"] = snappedf(note.tolerance, 0.001)
				extra["samples"] = snappedf(note.samples_per_beat, 0.001)
				# Path 头/尾的可见弧宽是检查器可改的；紧凑代码只写离心/轴，宽度旁挂。
				if not is_equal_approx(note.width, 60.0):
					extra["path_width"] = snappedf(note.width, 0.001)
				if not is_equal_approx(note.tail_width, 45.0):
					extra["tail_width"] = snappedf(note.tail_width, 0.001)
				if note.path_speed != 1.0:
					extra["speed"] = snappedf(note.path_speed, 0.001)
				if not note.path_gaps.is_empty():
					extra["path_gaps"] = Note._ranges_to_array(note.path_gaps)
				if not note.trace_pts.is_empty():
					extra["trace"] = Note._points_to_dict(note.trace_pts)
				if not note.visual_pts.is_empty():
					extra["visual"] = Note._points_to_dict(note.visual_pts)
				if note.path_custom_shape:
					extra["custom_shape"] = true
				if not note.show_trail:
					extra["show_trail"] = false
				if note.has_trail_color:
					extra["trail_rgb"] = "#" + note.trail_color.to_html(false)
			"bell":
				if absf(note.bell_radius - 1.0) > 0.0001:
					extra["bell_radius"] = snappedf(note.bell_radius, 0.001)
		if note.group_id != 0:
			extra["group"] = note.group_id
		if not note.enabled:
			extra["enabled"] = false
		# 演出修饰（alpha / hs / sv / spawn / bounce / touch）对所有类型通用。
		extra.merge(note.mods_to_dict(), true)
		if not extra.is_empty():
			note_extras[str(note.id)] = extra
	var result := {
		"format": FORMAT,
		"version": VERSION,
		"general": {
			"audio": String(chart.metadata.get("audio_source", "")) if not String(chart.metadata.get("audio_source", "")).is_empty() else chart.audio_path,
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
		"groups": chart.groups.duplicate(true),
		"group_bpm_points": _group_bpm_rows(chart),
		"current_group": chart.current_group,
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
	if not command_rows.is_empty():
		result["commands"] = command_rows
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
	if extra.has("tolerance"):
		note.tolerance = float(extra["tolerance"])
	if extra.has("samples"):
		note.samples_per_beat = float(extra["samples"])
	if extra.has("path_width"):
		note.width = float(extra["path_width"])
	if extra.has("tail_width"):
		note.tail_width = float(extra["tail_width"])
	if extra.has("speed"):
		note.path_speed = float(extra["speed"])
	if extra.has("path_gaps"):
		note.path_gaps = Note._ranges_from_array(extra["path_gaps"])
	if extra.has("trace"):
		note.trace_pts = Note._points_from_array(extra["trace"])
	if extra.has("custom_shape"):
		note.path_custom_shape = bool(extra["custom_shape"])
	if extra.has("show_trail"):
		note.show_trail = bool(extra["show_trail"])
	if extra.has("trail_rgb"):
		var trail_text := String(extra["trail_rgb"])
		if Color.html_is_valid(trail_text):
			note.trail_color = Color(trail_text)
			note.has_trail_color = true
	if extra.has("visual"):
		note.visual_pts = Note._points_from_array(extra["visual"])
	if extra.has("bell_radius"):
		note.bell_radius = float(extra["bell_radius"])
	if extra.has("group"):
		note.group_id = int(extra["group"])
	if extra.has("enabled"):
		note.enabled = bool(extra["enabled"])
	# 未知键由 apply_mods 自己忽略，所以整包传进去最省事。
	note.apply_mods(extra)


static func _group_bpm_rows(chart: Chart) -> Dictionary:
	var result := {}
	for group in chart.groups:
		var gid := int(group.get("id", 0))
		var rows: Array[Dictionary] = []
		for point in chart.group_bpm_points_for(gid):
			rows.append(point.to_dict())
		result[str(gid)] = rows
	return result


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


## 解析进度：WorkerThreadPool 里的构建阶段写、主线程只读（单个写者，仅用于进度条）。
static var parse_done: int = 0
static var parse_total: int = 0


static func chart_from_dict(data: Dictionary) -> Chart:
	last_error = ""
	parse_done = 0
	parse_total = 0
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
	chart.audio_path = str(general.get("audio", ""))
	chart.video_path = str(general.get("video", ""))
	chart.video_offset_ms = float(general.get("video_offset_ms", 0.0))
	chart.video_fps = float(general.get("video_fps", 60.0))
	chart.video_opacity = float(general.get("video_opacity", 0.35))
	# 旧文件里的 general.pre_read_ms 读进来直接忽略：飞行时长固定 1 秒（Chart.NOTE_FALL_MS）。
	chart.offset_ms = float(general.get("offset_ms", 0.0))
	chart.difficulty = str(general.get("difficulty", "Normal"))
	var meta: Dictionary = data.get("metadata", {})
	for key in ["title", "artist", "creator", "version", "tags", "license", "background", "storyboard", "audio_source"]:
		chart.metadata[key] = str(meta.get(key, ""))
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
	chart.groups.clear()
	var groups_raw: Variant = data.get("groups", [])
	if groups_raw is Array:
		for raw in groups_raw:
			if raw is Dictionary:
				chart.groups.append((raw as Dictionary).duplicate(true))
	chart.current_group = int(data.get("current_group", 0))
	chart.ensure_groups()
	var bpm_groups: Variant = data.get("group_bpm_points", {})
	if bpm_groups is Dictionary:
		chart.group_bpm_points.clear()
		for raw_gid in bpm_groups.keys():
			var gid := int(raw_gid)
			var rows: Array[TimingPoint] = []
			for raw_point in bpm_groups[raw_gid]:
				if raw_point is Dictionary:
					rows.append(TimingPoint.from_dict(raw_point))
			if not rows.is_empty():
				chart.group_bpm_points[gid] = rows
		chart.ensure_groups()
	# 组 0 的 BPM 点才是全谱时间轴；旧版本删点只改了组列表，这里顺手修复。
	chart.sync_group_bpm_points(0, chart.group_bpm_points_for(0))
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
	var notes_raw: Variant = data.get("notes", [])
	parse_total = notes_raw.size() if notes_raw is Array else 0
	for raw in notes_raw:
		parse_done += 1
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
	# v3 及更早：anchor 的 width 从来没参与过绘制（代码格式解析成 0，JSON 里是默认 60）。
	# v4 起 width 就是胶囊的实际弧宽，把旧数据里的 0/60 收敛成「未设置 = 30°」。
	if file_version < 4:
		for note in chart.notes:
			if note.type == "anchor" and (note.width <= 0.001 or is_equal_approx(note.width, 60.0)):
				note.width = 0.0
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
	chart.commands.clear()
	for raw in data.get("commands", []):
		if raw is Dictionary:
			var command := AlphaCommand.from_dict(raw)
			# 未知指令名（来自更新版本的文件）整条丢弃，不让它污染时间轴。
			if not command.spec().is_empty():
				chart.commands.append(command)
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
	LoadTrace.begin("open %s" % path.get_file())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取：%s" % path
		LoadTrace.end("失败")
		return null
	var text := file.get_as_text()
	file.close()
	LoadTrace.mark("读文件")
	var chart := from_json(text)
	LoadTrace.mark("构建谱面")
	if chart != null:
		chart.project_dir = ""
		chart.project_main_path = ""
	LoadTrace.end("%d 音符" % (chart.notes.size() if chart != null else 0))
	return chart


static func save_chart(chart: Chart, path: String) -> Error:
	# From this version on, saving a chart writes a project folder. A legacy
	# .json path is converted to <basename>/main.json and removed afterwards.
	var entries: Array = [{"name": String(chart.metadata.get("version", chart.difficulty)), "chart": chart}]
	return save_project(entries, path, String(chart.metadata.get("title", "")), "")


## Legacy single-file chart, kept for compatibility with the old .json form.
static func save_chart_file(chart: Chart, path: String) -> Error:
	last_error = ""
	chart.reassign_note_ids()
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var err := atomic_write(path, to_json(chart))
	if err != OK:
		last_error = "无法写入谱面文件：%s" % path
	return err


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
	if DirAccess.dir_exists_absolute(p):
		return p
	if p.get_file().to_lower() in ["main.json", "main.tmc"]:
		return p.get_base_dir()
	if p.get_extension().is_empty():
		return p
	return p.get_basename()


static func project_main_path(path: String) -> String:
	return project_dir_for(path).path_join("main.tmc")


static func is_project_path(path: String) -> bool:
	if path.is_empty():
		return false
	var dir := project_dir_for(path)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	return FileAccess.file_exists(dir.path_join("main.tmc")) or FileAccess.file_exists(dir.path_join("main.json"))


## 回放记录的是“谱面路径”：可能是单文件、三文件文件夹或 TMC 工程主文件。
static func chart_path_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) or is_project_path(path)


static func _project_file(dir: String, stem: String) -> String:
	var tmc := dir.path_join(stem + ".tmc")
	if FileAccess.file_exists(tmc):
		return tmc
	var json := dir.path_join(stem + ".json")
	return json if FileAccess.file_exists(json) else ""


static func _project_needs_template(dir: String) -> bool:
	for stem in ["main", "chart0", "color", "shaped", "bpmlist", "storyboard"]:
		if FileAccess.file_exists(dir.path_join(stem + ".json")):
			return true
	for chart_file in _project_chart_files(dir):
		if not String(chart_file).ends_with(".tmc"):
			return true
		var text := FileAccess.get_file_as_string(dir.path_join(String(chart_file)))
		for raw in text.replace("\r\n", "\n").split("\n"):
			var line := String(raw).strip_edges()
			if line.begins_with("group") and line.contains("{") and not line.ends_with("{"):
				return true
	var shaped_path := _project_file(dir, "shaped")
	if not shaped_path.is_empty() and shaped_path.ends_with(".tmc"):
		for raw in FileAccess.get_file_as_string(shaped_path).replace("\r\n", "\n").split("\n"):
			var line := String(raw).strip_edges()
			if line.begins_with("shape{") and line.length() > "shape{".length():
				return true
	var bpm_path := _project_file(dir, "bpmlist")
	if not bpm_path.is_empty() and bpm_path.ends_with(".tmc"):
		var lines := FileAccess.get_file_as_string(bpm_path).replace("\r\n", "\n").split("\n")
		for i in lines.size() - 1:
			var line := String(lines[i]).strip_edges()
			if line.begins_with("group") and line.ends_with("{"):
				var next_line := String(lines[i + 1])
				if next_line.strip_edges() != "}" and not next_line.begins_with("\t"):
					return true
	return false


static func load_project(path: String) -> Dictionary:
	last_error = ""
	var dir := project_dir_for(path)
	var main_path := _project_file(dir, "main")
	if main_path.is_empty():
		last_error = "谱面工程缺少 main.tmc / main.json：%s" % dir
		return {"ok": false, "error": last_error}
	var main := _read_project_struct(main_path, "main")
	if main.is_empty():
		return {"ok": false, "error": last_error}
	if String(main.get("format", "")) != PROJECT_FORMAT:
		last_error = "不是 Tamaki 谱面工程"
		return {"ok": false, "error": last_error}
	var shaped_path := _project_file(dir, "shaped")
	var color_path := _project_file(dir, "color")
	if shaped_path.is_empty() or color_path.is_empty():
		last_error = "谱面工程必须包含 shaped 和 color（.tmc/.json）"
		return {"ok": false, "error": last_error}
	var shaped := _read_project_struct(shaped_path, "shaped")
	var color := _read_project_struct(color_path, "color")
	var bpm_path := _project_file(dir, "bpmlist")
	var bpm_data := _read_project_struct(bpm_path, "bpm") if not bpm_path.is_empty() else {}
	var story_path := _project_file(dir, "storyboard")
	var storyboard := _read_project_struct(story_path, "story") if not story_path.is_empty() else {}
	var chart_files := _project_chart_files(dir)
	if chart_files.is_empty():
		last_error = "谱面工程没有 chartN.tmc / chartN.json"
		return {"ok": false, "error": last_error}
	var music_name := String(main.get("music", ""))
	if music_name.is_empty() or not FileAccess.file_exists(dir.path_join(music_name)):
		last_error = "谱面工程必须包含 music 音频文件"
		return {"ok": false, "error": last_error}
	var names: Array = main.get("difficulty_list", main.get("difficulties", []))
	var stars_raw: Array = main.get("difficulty_stars", [])
	var view: Dictionary = main.get("view", {})
	var entries: Array = []
	for i in chart_files.size():
		var part_path := dir.path_join(String(chart_files[i]))
		var part := _read_project_struct(part_path, "chart")
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
		var group_parts := _group_parts(part)
		var groups_meta: Array = main.get("groups", [])
		var saved_group_names := {}
		if groups_meta is Array:
			for saved in groups_meta:
				if saved is Dictionary:
					saved_group_names[int(saved.get("id", -1))] = String(saved.get("name", ""))
		var current_group := int(main.get("current_group", 0))
		var note_codes: Array = part.get("notes", [])
		var local_map := {}
		if not group_parts.is_empty():
			groups_meta = []
			note_codes = []
			current_group = int(part.get("current_group", 0))
			for gp in group_parts:
				var gid := int(gp.get("id", 0))
				var saved_name := String(saved_group_names.get(gid, ""))
				groups_meta.append({
					"id": gid, "name": saved_name if not saved_name.is_empty() else "组 %d" % gid,
					"bpm": float(gp.get("bpm", 120.0)),
					"alpha": int(gp.get("alpha", 255)), "enabled": bool(gp.get("enabled", true)),
				})
				for code in gp.get("codes", []):
					var local := _leading_code_id(String(code))
					var internal := _internal_note_id(gid, local)
					local_map[str(internal)] = local
					note_codes.append(_prefix_code_id(String(code), internal, gid))
		var group_points := _project_group_bpm_points(bpm_data, main, groups_meta)
		var points: Array = group_points.get("0", _project_timing_points(main, bpm_data))
		var extras: Dictionary = _ungroup_table(part.get("note_extras", {}), 0)
		if not group_parts.is_empty():
			extras = {}
			var raw_extras: Dictionary = part.get("note_extras", {})
			for key in raw_extras.keys():
				var text := String(key)
				if text.begins_with("g") and text.contains(":"):
					var pieces := text.substr(1).split(":", true)
					if pieces.size() == 2:
						extras[str(_internal_note_id(int(pieces[0]), int(pieces[1])))] = raw_extras[key]
		var flags: Dictionary = _ungroup_table(part.get("note_flags", {}), 0)
		if not group_parts.is_empty():
			flags = {}
			var raw_flags: Dictionary = part.get("note_flags", {})
			for key in raw_flags.keys():
				var text := String(key)
				if text.begins_with("g") and text.contains(":"):
					var pieces := text.substr(1).split(":", true)
					if pieces.size() == 2:
						flags[str(_internal_note_id(int(pieces[0]), int(pieces[1])))] = raw_flags[key]
		var data := {
			"format": FORMAT,
			"version": VERSION,
			"general": {
				"audio": audio,
				"video": String(main.get("video", "")),
				"video_offset_ms": float(main.get("video_offset_ms", 0.0)),
				"video_fps": float(main.get("video_fps", 60.0)),
				"video_opacity": float(main.get("video_opacity", 0.35)),
				"offset_ms": float(main.get("offset_ms", 0.0)),
				"pre_read_ms": float(main.get("pre_read_ms", 1000.0)),
				"difficulty": name,
			},
			"metadata": {
				"title": String(main.get("title", "")),
				"artist": String(main.get("artist", "")),
				"creator": String(main.get("creator", main.get("charter", ""))),
				"version": String(part.get("chart_version", "")) if not String(part.get("chart_version", "")).is_empty() else String(main.get("chart_version", name)),
				"tags": String(main.get("tags", "")),
				"license": String(main.get("license", "")),
				"background": String(main.get("background", "")) if not String(main.get("background", "")).is_empty() else (dir.path_join(jacket) if not jacket.is_empty() else ""),
				"storyboard": String(main.get("storyboard", "")),
				"widescreen": int(main.get("widescreen", 0)),
				"face_camera": int(main.get("face_camera", 1)),
				"audio_source": String(main.get("audio_source", "")),
			},
			"timing": {"offset_ms": float(main.get("offset_ms", 0.0)), "points": points},
			"default_shape": String(view.get("default_shape", main.get("default_shape", "S0"))),
			"shapes": String(shaped.get("shapes", "")),
			"events": storyboard.get("events", []),
			"boundary_keys": storyboard.get("shape_keys", []),
			"view_states": view.get("view_states", main.get("view_states", [])),
			"regions": part.get("regions", []),
			"commands": part.get("commands", []),
			"notes": note_codes,
			"editor": view.get("editor", main.get("editor", {})),
			"groups": groups_meta,
			"group_bpm_points": group_points,
			"current_group": current_group,
			"note_extras": extras,
			"note_flags": flags,
			"note_colors": _project_colors_for(color, i),
			"palette": color.get("palette", []),
		}
		var chart := chart_from_dict(data)
		if chart == null:
			continue
		for note in chart.notes:
			if local_map.has(str(note.id)):
				note.local_id = int(local_map[str(note.id)])
		chart.ensure_note_local_ids()
		chart.project_dir = dir
		chart.project_main_path = main_path
		var stars := float(stars_raw[i]) if i < stars_raw.size() else -1.0
		entries.append({"name": name, "stars": stars, "chart": chart})
	if entries.is_empty():
		last_error = "谱面工程没有可用难度"
		return {"ok": false, "error": last_error}
	# Apply the TMC formatting template to projects read from old JSON or from
	# pre-template compact TMC files.
	if _project_needs_template(dir):
		var normalized := save_project(entries, dir, String(main.get("title", "")), String(main.get("source", "")))
		if normalized != OK:
			last_error = "谱面工程格式规范化失败：%s" % last_error
			return {"ok": false, "error": last_error}
		main_path = dir.path_join("main.tmc")
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
	var main_path := dir.path_join("main.tmc")
	var legacy_path := path if path.to_lower().ends_with(".json") and path.get_file().to_lower() != "main.json" else ""
	DirAccess.make_dir_recursive_absolute(dir)
	var first: Chart = entries[0].get("chart", null)
	if first == null:
		last_error = "第一个难度为空"
		return ERR_INVALID_DATA
	var base := chart_to_dict(first)
	var meta: Dictionary = first.metadata
	var names: Array[String] = []
	var stars: Array = []
	for entry in entries:
		names.append(String(entry.get("name", "难度")))
		stars.append(snappedf(float(entry.get("stars", -1.0)), 0.01))
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
		"difficulty_stars": stars,
		"bpm": _first_bpm(first),
		"beats_per_bar": _first_beats_per_bar(first),
		"offset_ms": snappedf(first.offset_ms, 0.001),
		"pre_read_ms": snappedf(Chart.NOTE_FALL_MS, 0.001),
		"music": audio_name,
		"audio_source": String(first.metadata.get("audio_source", first.audio_path)),
		"jacket": jacket_name,
		"video": first.video_path,
		"video_offset_ms": snappedf(first.video_offset_ms, 0.001),
		"video_fps": snappedf(first.video_fps, 0.001),
		"video_opacity": snappedf(first.video_opacity, 0.001),
		"tags": String(first.metadata.get("tags", "")),
		"license": String(first.metadata.get("license", "")),
		"background": String(first.metadata.get("background", "")),
		"storyboard": String(first.metadata.get("storyboard", "")),
		"chart_version": String(first.metadata.get("version", names[0])),
		"widescreen": int(first.metadata.get("widescreen", 0)),
		"face_camera": 1 if bool(first.metadata.get("face_camera", true)) else 0,
		"groups": first.groups.duplicate(true),
		"view": view,
		"source": source,
	}
	var err := atomic_write(main_path, _main_tmc(main), false)
	if err != OK:
		return err
	err = atomic_write(dir.path_join("shaped.tmc"), _shaped_tmc(BoundaryShape.shapes_to_tmc(first.sorted_shapes())), false)
	if err != OK:
		return err
	var bpm_groups := _project_group_bpm_groups(first)
	var any_bpm_changes := false
	for row in bpm_groups:
		if not (row.get("changes", []) as Array).is_empty():
			any_bpm_changes = true
			break
	var keep_bpm_file: bool = any_bpm_changes or first.groups.size() > 1
	var bpm_path := dir.path_join("bpmlist.tmc")
	if not keep_bpm_file:
		for old in [bpm_path, dir.path_join("bpmlist.json")]:
			if FileAccess.file_exists(old):
				DirAccess.remove_absolute(old)
	else:
		err = atomic_write(bpm_path, _bpm_tmc(bpm_groups), false)
		if err != OK:
			return err
	var events: Array = base.get("events", [])
	var keys: Array = base.get("boundary_keys", base.get("shape_keys", []))
	var story_path := dir.path_join("storyboard.tmc")
	if events.is_empty() and keys.is_empty():
		for old in [story_path, dir.path_join("storyboard.json")]:
			if FileAccess.file_exists(old):
				DirAccess.remove_absolute(old)
	else:
		err = atomic_write(story_path, _storyboard_tmc(events, keys), false)
		if err != OK:
			return err
	var color_charts: Array = []
	for i in entries.size():
		var chart: Chart = entries[i].get("chart", null)
		if chart == null:
			continue
		chart.ensure_note_local_ids()
		var part := chart_to_dict(chart)
		var part_data := {
			"format": FORMAT,
			"version": VERSION,
			"difficulty": String(chart.difficulty if not chart.difficulty.is_empty() else entries[i].get("name", "难度")),
			"chart_version": String(chart.metadata.get("version", "")),
			"groups": _group_codes(chart, part),
			"current_group": chart.current_group,
			"regions": part.get("regions", []),
			"commands": part.get("commands", []),
			"note_flags": _group_keyed_table(part.get("note_flags", {}), chart),
			"note_extras": _group_keyed_table(part.get("note_extras", {}), chart),
		}
		err = atomic_write(dir.path_join("chart%d.tmc" % i), _chart_tmc(part_data), false)
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
	err = atomic_write(dir.path_join("color.tmc"), _color_tmc(color_data), false)
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
	# Old JSON project files are replaced by the .tmc text format.
	for old_stem in ["main", "shaped", "color", "bpmlist", "storyboard"]:
		var old_json := dir.path_join(old_stem + ".json")
		if FileAccess.file_exists(old_json):
			DirAccess.remove_absolute(old_json)
	for old_name in DirAccess.get_files_at(dir):
		if String(old_name).begins_with("chart") and String(old_name).ends_with(".json"):
			DirAccess.remove_absolute(dir.path_join(String(old_name)))
	if not legacy_path.is_empty() and FileAccess.file_exists(legacy_path):
		DirAccess.remove_absolute(legacy_path)
	return OK


static func _group_codes(chart: Chart, part: Dictionary) -> Array[String]:
	chart.ensure_note_local_ids()
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	var result: Array[String] = []
	for group in chart.groups:
		var gid := int(group.get("id", 0))
		var codes: Array[String] = []
		for note in chart.sorted_notes():
			if note.group_id != gid:
				continue
			if note.type == "path" and note.path_prev_id >= 0 and by_id.has(note.path_prev_id):
				continue
			var code := _note_code(note, by_id)
			if not code.is_empty():
				codes.append(code)
		var block: Array[String] = ["group%d(%s,%d,%s){" % [
			gid, str(snappedf(float(group.get("bpm", chart.timing.bpm_at(0.0))), 0.001)),
			clampi(int(group.get("alpha", 255)), 0, 255),
			"True" if bool(group.get("enabled", true)) else "False",
		]]
		for code in codes:
			block.append("\t" + code)
		block.append("}")
		result.append("\n".join(block))
	return result


static func _leading_code_id(code: String) -> int:
	var text := String(code).strip_edges()
	if not text.begins_with("["):
		return 0
	var close := text.find("]")
	return int(text.substr(1, close - 1)) if close > 1 else 0


## 分组代码里的 Path 链：不仅根 [id]，每个 part 的第 9 段也要换成组内全局 id。
## 否则 note_extras / note_colors 按 id 旁挂的组、颜色、锁定、容差等属性会在
## TMC 工程往返时对不上号（Path 的 to_code 会把每段自己的 id 写进代码）。
static func _prefix_code_id(code: String, new_id: int, group_id: int) -> String:
	var text := String(code).strip_edges()
	var close := text.find("]")
	if not text.begins_with("[") or close <= 1:
		return text
	var rest := text.substr(close + 1)
	var packed := rest.strip_edges()
	if not (packed.begins_with("path{") and packed.ends_with("}")):
		return "[%d]%s" % [new_id, rest]
	var root_local := _local_note_id(new_id)
	var body := packed.substr(5, packed.length() - 6)
	var rewritten: Array[String] = []
	var index := 0
	for raw in body.split(";", true):
		var segment := String(raw).strip_edges()
		var inner := segment.trim_prefix("(").trim_suffix(")")
		var fields := inner.split(",", true)
		# 老代码没有 wait / id 两段：补 0，再用解析器的同一套回退规则。
		while fields.size() < 9:
			fields.append("0")
		var local := int(fields[8]) if int(fields[8]) > 0 else (root_local + 1000 * index)
		fields[8] = str(_internal_note_id(group_id, local))
		rewritten.append("(" + ",".join(fields) + ")")
		index += 1
	return "[%d]path{%s}" % [new_id, ";".join(rewritten)]


static func _ungroup_table(table: Dictionary, prefix: int) -> Dictionary:
	var result := {}
	for key in table.keys():
		var text := String(key)
		if text.begins_with("g") and text.contains(":"):
			var pieces := text.substr(1).split(":", true)
			if pieces.size() == 2:
				result[str(_internal_note_id(int(pieces[0]), int(pieces[1])))] = table[key]
		else:
			result[str(prefix + int(text))] = table[key]
	return result


static func _group_keyed_table(table: Dictionary, chart: Chart) -> Dictionary:
	if table.is_empty():
		return table
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	var result := {}
	for raw_key in table.keys():
		var note: Note = by_id.get(int(raw_key), null)
		if note != null:
			result["g%d:%d" % [note.group_id, note.local_id]] = table[raw_key]
	return result


static func _parse_group_code(code: String) -> Dictionary:
	var text := String(code).strip_edges()
	if not text.begins_with("group"):
		return {}
	var open_paren := text.find("(")
	var open_brace := text.find("{")
	var close_brace := text.rfind("}")
	if open_paren < 0 or open_brace < 0 or close_brace <= open_brace:
		return {}
	var header := text.substr(open_paren + 1, open_brace - open_paren - 1)
	var fields := header.split(",", true)
	if fields.size() < 3:
		return {}
	var group_id := int(text.substr(5, open_paren - 5).strip_edges())
	var body := text.substr(open_brace + 1, close_brace - open_brace - 1)
	var codes: Array[String] = []
	for line in body.split("\n", false):
		var clean := String(line).strip_edges()
		if not clean.is_empty():
			codes.append(clean)
	return {
		"id": group_id,
		"bpm": float(fields[0]),
		"alpha": clampi(int(fields[1]), 0, 255),
		"enabled": String(fields[2]).strip_edges().to_lower() != "false",
		"codes": codes,
	}


static func _group_parts(part: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = part.get("groups", [])
	if raw is Array:
		for block in raw:
			var parsed := _parse_group_code(String(block))
			if not parsed.is_empty():
				result.append(parsed)
	return result


static func _main_tmc(main: Dictionary) -> String:
	var view: Dictionary = main.get("view", {})
	var lines: Array[String] = ["!tmc-project 1"]
	lines.append("title=" + String(main.get("title", "")))
	lines.append("artist=" + String(main.get("artist", "")))
	lines.append("charter=" + String(main.get("charter", main.get("creator", ""))))
	lines.append("creator=" + String(main.get("creator", main.get("charter", ""))))
	lines.append("difficulty=" + String(main.get("difficulty", "")))
	lines.append("difficulty_list=" + JSON.stringify(main.get("difficulty_list", [])))
	lines.append("difficulty_stars=" + JSON.stringify(main.get("difficulty_stars", [])))
	lines.append("bpm=" + str(main.get("bpm", 120.0)))
	lines.append("beats_per_bar=" + str(main.get("beats_per_bar", 4)))
	lines.append("offset_ms=" + str(main.get("offset_ms", 0.0)))
	lines.append("pre_read_ms=" + str(main.get("pre_read_ms", 1000.0)))
	lines.append("music=" + String(main.get("music", "")))
	lines.append("audio_source=" + String(main.get("audio_source", "")))
	lines.append("jacket=" + String(main.get("jacket", "")))
	lines.append("video=" + String(main.get("video", "")))
	lines.append("video_offset_ms=" + str(main.get("video_offset_ms", 0.0)))
	lines.append("video_fps=" + str(main.get("video_fps", 60.0)))
	lines.append("video_opacity=" + str(main.get("video_opacity", 0.35)))
	lines.append("tags=" + String(main.get("tags", "")))
	lines.append("license=" + String(main.get("license", "")))
	lines.append("background=" + String(main.get("background", "")))
	lines.append("storyboard=" + String(main.get("storyboard", "")))
	lines.append("chart_version=" + String(main.get("chart_version", main.get("difficulty", ""))))
	lines.append("widescreen=" + str(main.get("widescreen", 0)))
	lines.append("face_camera=" + str(main.get("face_camera", 1)))
	lines.append("groups=" + JSON.stringify(main.get("groups", [])))
	lines.append("source=" + String(main.get("source", "")))
	lines.append("default_shape=" + String(view.get("default_shape", "S0")))
	lines.append("editor=" + JSON.stringify(view.get("editor", {})))
	lines.append("view_states=" + JSON.stringify(view.get("view_states", [])))
	return "\n".join(lines) + "\n"


static func _chart_tmc(part: Dictionary) -> String:
	var lines: Array[String] = ["!tmc-chart 1"]
	lines.append("difficulty=" + String(part.get("difficulty", "")))
	lines.append("chart_version=" + String(part.get("chart_version", "")))
	lines.append("current_group=" + str(part.get("current_group", 0)))
	for block in part.get("groups", []):
		lines.append(String(block))
	for region in part.get("regions", []):
		lines.append("region=" + String(region))
	for command in part.get("commands", []):
		lines.append("command=" + JSON.stringify(command))
	var flags: Dictionary = part.get("note_flags", {})
	for key in flags.keys():
		lines.append("note_flag=%s\t%s" % [String(key), JSON.stringify(flags[key])])
	var extras: Dictionary = part.get("note_extras", {})
	for key in extras.keys():
		lines.append("note_extra=%s\t%s" % [String(key), JSON.stringify(extras[key])])
	return "\n".join(lines) + "\n"


static func _color_tmc(color: Dictionary) -> String:
	var lines: Array[String] = ["!tmc-color 1"]
	lines.append("default=" + String(color.get("default", "begin")))
	lines.append("palette=" + JSON.stringify(color.get("palette", [])))
	for code in color.get("notes", []):
		lines.append("note=" + String(code))
	for chart in color.get("charts", []):
		lines.append("chart=" + JSON.stringify(chart))
	return "\n".join(lines) + "\n"


static func _bpm_tmc(groups: Array) -> String:
	var lines: Array[String] = ["!tmc-bpm 1"]
	for row in groups:
		var gid := int(row.get("id", 0))
		lines.append("group%d{" % gid)
		for change in row.get("changes", []):
			lines.append("\t" + String(change))
		lines.append("}")
	return "\n".join(lines) + "\n"


static func _shaped_tmc(shapes: String) -> String:
	return "!tmc-shapes 1\n" + shapes + "\n"


static func _storyboard_tmc(events: Array, keys: Array) -> String:
	var lines: Array[String] = ["!tmc-story 1"]
	for event in events:
		lines.append("event=" + JSON.stringify(event))
	for key in keys:
		lines.append("shape_key=" + JSON.stringify(key))
	return "\n".join(lines) + "\n"


static func _read_project_struct(path: String, kind: String) -> Dictionary:
	if path.ends_with(".tmc"):
		return _read_tmc(path, kind)
	return _read_json(path)


static func _read_tmc(path: String, kind: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	match kind:
		"main": return _parse_main_tmc(text)
		"chart": return _parse_chart_tmc(text)
		"color": return _parse_color_tmc(text)
		"bpm": return _parse_bpm_tmc(text)
		"shaped": return _parse_shaped_tmc(text)
		"story": return _parse_storyboard_tmc(text)
	return {}


static func _tmc_lines(text: String) -> Array[String]:
	var result: Array[String] = []
	for raw in text.replace("\r\n", "\n").split("\n", false):
		var line := String(raw)
		if not line.strip_edges().is_empty() and not line.strip_edges().begins_with("#"):
			result.append(line)
	return result


static func _tmc_value(text: String) -> Variant:
	var stripped := text.strip_edges()
	if stripped.begins_with("{") or stripped.begins_with("["):
		var parsed: Variant = JSON.parse_string(stripped)
		return parsed if parsed != null else stripped
	if stripped.is_valid_float():
		return float(stripped)
	if stripped == "True" or stripped == "true":
		return true
	if stripped == "False" or stripped == "false":
		return false
	return stripped


static func _parse_main_tmc(text: String) -> Dictionary:
	# _tmc_value 会把 1 解析成 float；GDScript 的 String(number) 会直接报错，
	# 所以文本字段统一走 str()，否则 chart_version=1 这类工程会打不开。
	var fields := {}
	for line in _tmc_lines(text):
		var at := line.find("=")
		if at < 0:
			continue
		fields[line.substr(0, at).strip_edges()] = _tmc_value(line.substr(at + 1))
	var view := {
		"editor": fields.get("editor", {}),
		"view_states": fields.get("view_states", []),
		"default_shape": str(fields.get("default_shape", "S0")),
	}
	return {
		"format": PROJECT_FORMAT,
		"version": PROJECT_VERSION,
		"title": str(fields.get("title", "")),
		"artist": str(fields.get("artist", "")),
		"charter": str(fields.get("charter", fields.get("creator", ""))),
		"creator": str(fields.get("creator", fields.get("charter", ""))),
		"difficulty": str(fields.get("difficulty", "")),
		"difficulty_list": fields.get("difficulty_list", []),
		"difficulty_stars": fields.get("difficulty_stars", []),
		"bpm": float(fields.get("bpm", 120.0)),
		"beats_per_bar": int(fields.get("beats_per_bar", 4)),
		"offset_ms": float(fields.get("offset_ms", 0.0)),
		"pre_read_ms": float(fields.get("pre_read_ms", 1000.0)),
		"music": str(fields.get("music", "")),
		"audio_source": str(fields.get("audio_source", "")),
		"jacket": str(fields.get("jacket", "")),
		"video": str(fields.get("video", "")),
		"video_offset_ms": float(fields.get("video_offset_ms", 0.0)),
		"video_fps": float(fields.get("video_fps", 60.0)),
		"video_opacity": float(fields.get("video_opacity", 0.35)),
		"tags": str(fields.get("tags", "")),
		"license": str(fields.get("license", "")),
		"background": str(fields.get("background", "")),
		"storyboard": str(fields.get("storyboard", "")),
		"chart_version": str(fields.get("chart_version", fields.get("difficulty", ""))),
		"widescreen": int(fields.get("widescreen", 0)),
		"face_camera": int(fields.get("face_camera", 1)),
		"groups": fields.get("groups", []),
		"source": str(fields.get("source", "")),
		"view": view,
	}


static func _parse_chart_tmc(text: String) -> Dictionary:
	var result := {"groups": [], "regions": [], "commands": [], "note_flags": {}, "note_extras": {}}
	var lines := _tmc_lines(text)
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("group") and stripped.contains("{"):
			var start := i
			var depth := 0
			while i < lines.size():
				depth += String(lines[i]).count("{") - String(lines[i]).count("}")
				i += 1
				if depth <= 0:
					break
			var block := "\n".join(lines.slice(start, i))
			result["groups"].append(block)
			continue
		var at := line.find("=")
		if at > 0:
			var key := line.substr(0, at).strip_edges()
			var value := line.substr(at + 1)
			match key:
				"difficulty": result["difficulty"] = value.strip_edges()
				"chart_version": result["chart_version"] = value.strip_edges()
				"current_group": result["current_group"] = int(value)
				"region": result["regions"].append(value.strip_edges())
				"command": result["commands"].append(_tmc_value(value))
				"note_flag", "note_extra":
					var tab := value.find("\t")
					if tab > 0:
						var table: Dictionary = result["note_flags"] if key == "note_flag" else result["note_extras"]
						table[value.substr(0, tab)] = _tmc_value(value.substr(tab + 1))
		i += 1
	return result


static func _parse_color_tmc(text: String) -> Dictionary:
	var result := {"format": "tamaki3-colors", "version": 1, "default": "begin", "palette": [], "notes": [], "charts": []}
	for line in _tmc_lines(text):
		var at := line.find("=")
		if at < 0:
			continue
		var key := line.substr(0, at).strip_edges()
		var value := line.substr(at + 1)
		match key:
			"default": result["default"] = value.strip_edges()
			"palette": result["palette"] = _tmc_value(value)
			"note": result["notes"].append(value.strip_edges())
			"chart": result["charts"].append(_tmc_value(value))
	return result


static func _parse_bpm_tmc(text: String) -> Dictionary:
	var groups: Array = []
	var lines := _tmc_lines(text)
	var i := 0
	while i < lines.size():
		var stripped := String(lines[i]).strip_edges()
		if stripped.begins_with("group") and stripped.ends_with("{"):
			var gid_text := stripped.substr(5, stripped.length() - 6)
			var gid := int(gid_text)
			var changes: Array[String] = []
			i += 1
			while i < lines.size() and String(lines[i]).strip_edges() != "}":
				changes.append(String(lines[i]).strip_edges())
				i += 1
			groups.append({"id": gid, "changes": changes})
		i += 1
	return {"format": "tamaki3-bpm", "version": 1, "groups": groups}


static func _parse_shaped_tmc(text: String) -> Dictionary:
	var lines := _tmc_lines(text)
	var start := -1
	for i in lines.size():
		if String(lines[i]).strip_edges().begins_with("shape"):
			start = i
			break
	if start < 0:
		return {"format": "tamaki3-shapes", "version": 1, "shapes": ""}
	return {"format": "tamaki3-shapes", "version": 1, "shapes": "\n".join(lines.slice(start))}


static func _parse_storyboard_tmc(text: String) -> Dictionary:
	var events: Array = []
	var keys: Array = []
	for line in _tmc_lines(text):
		var at := line.find("=")
		if at < 0:
			continue
		var key := line.substr(0, at).strip_edges()
		var value: Variant = _tmc_value(line.substr(at + 1))
		if key == "event" and value is Dictionary:
			events.append(value)
		elif key == "shape_key" and value is Dictionary:
			keys.append(value)
	return {"format": "tamaki3-storyboard", "version": 1, "events": events, "shape_keys": keys}


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
		if not name.begins_with("chart"):
			continue
		if not (name.ends_with(".tmc") or name.ends_with(".json")):
			continue
		var stem := name.get_basename()
		var index_text := stem.trim_prefix("chart")
		if index_text.is_valid_int():
			names.append(name)
	if names.is_empty():
		for fallback in ["chart.tmc", "chart.json"]:
			if FileAccess.file_exists(dir.path_join(fallback)):
				names.append(fallback)
				break
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


static func _project_group_bpm_points(bpm_data: Dictionary, main: Dictionary, groups_meta: Array) -> Dictionary:
	var result := {}
	for group in groups_meta:
		var gid := int(group.get("id", 0))
		result[str(gid)] = [{
			"beat": 0.0, "bpm": float(group.get("bpm", main.get("bpm", 120.0))),
			"beats_per_bar": int(main.get("beats_per_bar", 4)),
		}]
	var grouped: Variant = bpm_data.get("groups", [])
	if grouped is Array:
		for item in grouped:
			if not (item is Dictionary):
				continue
			var gid := int(item.get("id", 0))
			if not result.has(str(gid)):
				continue
			for raw in item.get("changes", []):
				var point := _parse_bpm_change(String(raw))
				if point.is_empty():
					continue
				result[str(gid)].append(point)
	else:
		for raw in bpm_data.get("changes", []):
			var point := _parse_bpm_change(String(raw))
			if not point.is_empty():
				result["0"].append(point)
	return result


static func _parse_bpm_change(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("\\[\\s*([0-9.]+)\\s*\\]\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9]+)\\s*\\)")
	var found := regex.search(text)
	if found == null:
		return {}
	return {
		"beat": float(found.get_string(1)), "bpm": float(found.get_string(2)),
		"beats_per_bar": int(found.get_string(3)),
	}


static func _project_group_bpm_groups(chart: Chart) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group in chart.groups:
		var gid := int(group.get("id", 0))
		var changes: Array[String] = []
		var points: Array[TimingPoint] = chart.group_bpm_points_for(gid)
		for i in range(1, points.size()):
			var point: TimingPoint = points[i]
			changes.append("[%s](%s,%d)" % [
				str(snappedf(point.beat, 0.001)), str(snappedf(point.bpm, 0.001)),
				point.beats_per_bar,
			])
		result.append({"id": gid, "changes": changes})
	return result


static func _project_colors_for(color: Dictionary, index: int) -> Dictionary:
	var rows: Array = color.get("notes", [])
	var charts: Array = color.get("charts", [])
	if index < charts.size() and charts[index] is Dictionary:
		rows = (charts[index] as Dictionary).get("notes", [])
	var result := {}
	var grouped := RegEx.new()
	grouped.compile("^\\[g(\\d+):(\\d+)\\][^(]*\\((\\d+)(?:,([^)]+))?\\)$")
	var legacy := RegEx.new()
	legacy.compile("^\\[(\\d+)\\][^(]*\\((\\d+)\\)$")
	for raw in rows:
		var text := String(raw).strip_edges()
		var found := grouped.search(text)
		if found != null:
			var entry := {"g": int(found.get_string(3))}
			var rgb := found.get_string(4).strip_edges()
			if not rgb.is_empty() and Color.html_is_valid(rgb):
				entry["rgb"] = rgb
			result[str(_internal_note_id(int(found.get_string(1)), int(found.get_string(2))))] = entry
			continue
		found = legacy.search(text)
		if found != null:
			result[found.get_string(1)] = {"g": int(found.get_string(2))}
	return result


static func _internal_note_id(group_id: int, local_id: int) -> int:
	return group_id * 100000 + local_id


static func _local_note_id(note_id: int) -> int:
	return int(note_id) % 100000


static func _project_color_codes(chart: Chart) -> Array[String]:
	var result: Array[String] = []
	for note in chart.sorted_notes():
		if note.color != 0:
			result.append("[g%d:%d]%s(%d)" % [note.group_id, note.local_id, note.type, note.color])
		if note.has_custom_color:
			result.append("[g%d:%d]%s(%d,%s)" % [
				note.group_id, note.local_id, note.type, note.color,
				"#" + note.custom_color.to_html(false),
			])
	return result


static func _copy_project_audio(chart: Chart, dir: String) -> String:
	if chart.audio_path.is_empty():
		_write_silent_music(dir)
		return "music.wav"
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


static func _write_silent_music(dir: String) -> void:
	# A project must contain music.<ext> even for a chart that has not imported
	# audio yet; write a tiny valid mono PCM WAV so the project remains openable.
	var sample_rate := 44100
	var bytes := PackedByteArray()
	bytes.append_array("RIFF".to_ascii_buffer())
	var data_size := 2
	var riff_size := 36 + data_size
	bytes.append_array(PackedByteArray([riff_size & 0xff, (riff_size >> 8) & 0xff, (riff_size >> 16) & 0xff, (riff_size >> 24) & 0xff]))
	bytes.append_array("WAVEfmt ".to_ascii_buffer())
	bytes.append_array(PackedByteArray([16, 0, 0, 0, 1, 0, 1, 0]))
	bytes.append_array(PackedByteArray([sample_rate & 0xff, (sample_rate >> 8) & 0xff, (sample_rate >> 16) & 0xff, (sample_rate >> 24) & 0xff]))
	var byte_rate := sample_rate * 2
	bytes.append_array(PackedByteArray([byte_rate & 0xff, (byte_rate >> 8) & 0xff, (byte_rate >> 16) & 0xff, (byte_rate >> 24) & 0xff]))
	bytes.append_array(PackedByteArray([2, 0, 16, 0]))
	bytes.append_array("data".to_ascii_buffer())
	bytes.append_array(PackedByteArray([data_size & 0xff, (data_size >> 8) & 0xff, (data_size >> 16) & 0xff, (data_size >> 24) & 0xff]))
	bytes.append_array(PackedByteArray([0, 0]))
	var file := FileAccess.open(dir.path_join("music.wav"), FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()


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
	var result: Dictionary = write_chart_text(path, text, backup)
	if result["code"] != OK:
		last_error = result["message"]
	return result["code"]


## 返回独立的错误信息，后台自动保存可与前台读写不同文件。
static func write_chart_text(path: String, text: String, backup: bool = true) -> Dictionary:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	if backup and FileAccess.file_exists(path):
		_backup(path)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"code": FileAccess.get_open_error(), "message": "无法写入临时文件：%s" % tmp}
	file.store_string(text)
	file.flush()
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return {"code": err, "message": "无法替换目标文件：%s" % path if err != OK else ""}


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


## ── 三文件谱面工程：谱面文件 + 音频 + 曲绘 ───────────────────────────────
static func _three_find(dir: String) -> Dictionary:
	var chart_file := ""
	var audio_file := ""
	var jacket_file := ""
	for name in DirAccess.get_files_at(dir):
		var lower := String(name).to_lower()
		if chart_file.is_empty() and (lower.ends_with(".json") or lower.ends_with(".txt")) and lower != "main.json":
			chart_file = String(name)
		elif audio_file.is_empty() and (lower.ends_with(".wav") or lower.ends_with(".ogg")):
			audio_file = String(name)
		elif jacket_file.is_empty() and (lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".png")):
			jacket_file = String(name)
	return {"chart": chart_file, "audio": audio_file, "jacket": jacket_file}


static func is_three_file_path(path: String) -> bool:
	var dir := path
	if not DirAccess.dir_exists_absolute(dir):
		dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return false
	if (FileAccess.file_exists(dir.path_join("main.tmc")) or FileAccess.file_exists(dir.path_join("main.json"))) \
			and not FileAccess.file_exists(dir.path_join("chart.json")):
		return false
	var found := _three_find(dir)
	return not String(found["chart"]).is_empty() and not String(found["audio"]).is_empty() and not String(found["jacket"]).is_empty()


static func load_three_file(path: String) -> Chart:
	last_error = ""
	var dir := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	var found := _three_find(dir)
	var chart_name := String(found.get("chart", ""))
	if chart_name.is_empty():
		last_error = "谱面文件夹缺少谱面文件"
		return null
	var chart := from_json(FileAccess.get_file_as_string(dir.path_join(chart_name)))
	if chart == null:
		last_error = "无法读取谱面文件"
		return null
	var audio_name := String(found.get("audio", ""))
	var jacket_name := String(found.get("jacket", ""))
	if not audio_name.is_empty():
		chart.audio_path = dir.path_join(audio_name)
	if not jacket_name.is_empty():
		chart.metadata["background"] = dir.path_join(jacket_name)
	chart.project_dir = dir
	chart.project_main_path = ""
	return chart


static func save_three_file(chart: Chart, path: String) -> Error:
	last_error = ""
	var dir := path
	if not DirAccess.dir_exists_absolute(dir) and not path.get_extension().is_empty():
		dir = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	chart.reassign_note_ids()
	var err := atomic_write(dir.path_join("chart.json"), to_json(chart), false)
	if err != OK:
		last_error = "无法写入谱面文件"
		return err
	var audio_name := "audio.wav"
	var source_audio := chart.audio_path
	var ext := source_audio.get_extension().to_lower()
	if ext == "ogg":
		audio_name = "audio.ogg"
	elif ext != "wav":
		ext = ""
	var audio_path := dir.path_join(audio_name)
	if ext.is_empty():
		_write_silent_music(dir)
		var silent := dir.path_join("music.wav")
		if FileAccess.file_exists(silent):
			if FileAccess.file_exists(audio_path):
				DirAccess.remove_absolute(audio_path)
			DirAccess.rename_absolute(silent, audio_path)
	else:
		_copy_file(source_audio, audio_path)
	var jacket_name := "cover.png"
	var source_jacket := String(chart.metadata.get("background", ""))
	var jext := source_jacket.get_extension().to_lower()
	if jext in ["jpg", "jpeg", "png"] and _copy_file(source_jacket, dir.path_join("cover." + jext)):
		jacket_name = "cover." + jext
	else:
		_write_placeholder_jacket(dir.path_join(jacket_name))
	chart.audio_path = audio_path
	chart.metadata["background"] = dir.path_join(jacket_name)
	chart.project_dir = dir
	chart.project_main_path = ""
	return OK


static func _write_placeholder_jacket(path: String) -> void:
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color("#18202c"))
	for y in 512:
		for x in 512:
			var glow := 1.0 - Vector2(x - 256, y - 256).length() / 360.0
			image.set_pixel(x, y, Color(0.08, 0.12, 0.18).lerp(Color(0.30, 0.42, 0.58), clampf(glow, 0.0, 1.0)))
	image.save_png(path)
