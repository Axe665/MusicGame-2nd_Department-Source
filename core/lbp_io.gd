class_name LBPIO
extends RefCounted

static var last_error: String = ""


static func export_to_file(chart: Chart, path: String) -> Error:
	if chart == null:
		last_error = "没有谱面"
		return ERR_INVALID_PARAMETER
	var text := export_chart(chart)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入 %s：%s" % [path, error_string(FileAccess.get_open_error())]
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


static func export_chart(chart: Chart) -> String:
	var lines: Array[String] = ["lbp file format v2", ""]
	lines.append("[General]")
	lines.append("FormatVersion: 2.1")
	lines.append("Mode: Ring")
	lines.append("Audio: %s" % _clean(chart.audio_path))
	lines.append("Background: %s" % _clean(String(chart.metadata.get("background", ""))))
	lines.append("PreviewTime: 0")
	lines.append("Offset: %s" % _num(chart.offset_ms))
	lines.append("PreRead: %s" % _num(chart.pre_read_ms))
	lines.append("JudgeProfile: standard")
	lines.append("Difficulty: %s" % _clean(chart.difficulty))
	lines.append("")
	if not chart.video_path.is_empty():
		lines.append("[Video]")
		lines.append("Path: %s" % _clean(chart.video_path))
		lines.append("Offset: %s" % _num(chart.video_offset_ms))
		lines.append("FPS: %s" % _num(chart.video_fps))
		lines.append("Muted: 1")
		lines.append("Loop: 0")
		lines.append("Opacity: %s" % _num(chart.video_opacity))
		lines.append("")
	lines.append("[Metadata]")
	lines.append("Title: %s" % _clean(String(chart.metadata.get("title", ""))))
	lines.append("Artist: %s" % _clean(String(chart.metadata.get("artist", ""))))
	lines.append("Creator: %s" % _clean(String(chart.metadata.get("creator", ""))))
	lines.append("Version: %s" % _clean(String(chart.metadata.get("version", chart.difficulty))))
	lines.append("Tags: %s" % _clean(String(chart.metadata.get("tags", ""))))
	lines.append("License: %s" % _clean(String(chart.metadata.get("license", ""))))
	lines.append("")
	lines.append("[TimingPoints]")
	var timing := chart.timing.points.duplicate()
	timing.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
	for point in timing:
		lines.append("%s,%s,%d" % [_beat(chart, point.beat), _num(point.bpm), point.beats_per_bar])
	lines.append("")
	lines.append("[BoundaryShapes]")
	for shape in chart.sorted_shapes():
		lines.append("shape,%s,%d" % [shape.id, 1 if shape.closed else 0])
		var segments := shape.sorted_segments()
		for segment in segments:
			var suffix := ",1" if segment.gap else ""
			lines.append("seg,%s,%s,%s,%s,%s,%s,%s,%s,%s%s" % [
				shape.id, _num(segment.u0), _num(segment.u1),
				_num(segment.p0.x), _num(segment.p0.y),
				_num(segment.p1.x), _num(segment.p1.y),
				segment.ix, segment.iy, suffix,
			])
	lines.append("")
	if not chart.shape_keys.is_empty():
		lines.append("[BoundaryKeys]")
		var keys := chart.sorted_shape_keys()
		for key in keys:
			lines.append("key,%s,%s,%s" % [
				_beat(chart, float(key.get("beat", 0.0))),
				String(key.get("shape_id", "")),
				String(key.get("easing", "in-out")),
			])
		lines.append("")
	if not chart.events.is_empty():
		lines.append("[BoundaryEvents]")
		var events := chart.events.duplicate()
		events.sort_custom(func(a: BoundaryEvent, b: BoundaryEvent) -> bool: return a.start_beat < b.start_beat)
		for event in events:
			lines.append("event,%s,%s,%s,%s..%s,%s,%s,%s,%s,%s,%s" % [
				event.id, _beat(chart, event.start_beat), _beat(chart, event.end_beat),
				_num(event.target_u0), _num(event.target_u1),
				event.from_shape, event.to_shape, event.easing, event.end_behavior,
				_num(event.restore_duration), event.restore_easing,
			])
		lines.append("")
	if not chart.view_states.is_empty():
		lines.append("[ViewStates]")
		var states := chart.view_states.duplicate()
		states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		for state in states:
			lines.append("ring,%s,%s,%s,%s,%s,%s,%s" % [
				_beat(chart, state.beat), _num(state.zoom), _num(state.tilt_x), _num(state.tilt_y),
				_num(state.ellipse), _num(state.rotation), state.easing,
			])
		lines.append("")
	if not chart.regions.is_empty():
		lines.append("[Regions]")
		var regions := chart.regions.duplicate()
		regions.sort_custom(func(a: Region, b: Region) -> bool: return a.start_beat < b.start_beat)
		for region in regions:
			var suffix := ",shape=%s" % region.shape if not region.shape.is_empty() else ""
			lines.append("region,%d,%s,%s,%s,%s,%s%s" % [
				region.id, region.kind, _beat(chart, region.start_beat), _beat(chart, region.end_beat),
				_num(region.angle), _num(region.width), suffix,
			])
		lines.append("")
	if not chart.palette.is_empty():
		lines.append("[Palette]")
		for index in range(chart.palette.size()):
			var group := chart.palette_group(index + 1)
			var parts: Array[String] = ["group", str(index + 1), _clean(chart.palette_name(index + 1))]
			for key in Chart.PALETTE_TYPES:
				var text := String(group.get(key, String(Chart.PALETTE_DEFAULTS[key])))
				if not Color.html_is_valid(text):
					text = String(Chart.PALETTE_DEFAULTS[key])
				parts.append("%s=%s" % [key, text])
			lines.append(",".join(parts))
		lines.append("")
	lines.append("[Notes]")
	var notes := chart.notes.duplicate()
	notes.sort_custom(func(a: Note, b: Note) -> bool:
		if is_equal_approx(a.beat, b.beat):
			return a.id < b.id
		return a.beat < b.beat
	)
	for note in notes:
		lines.append(_note_line(chart, note))
	lines.append("")
	lines.append("[Editor]")
	lines.append("snap=%d" % int(chart.editor.get("snap", 4)))
	lines.append("zoom=%s" % _num(float(chart.editor.get("zoom", 1.0))))
	lines.append("waveform=%d" % (1 if bool(chart.editor.get("waveform", true)) else 0))
	lines.append("hud=%d" % (1 if bool(chart.editor.get("hud", true)) else 0))
	lines.append("playhead=%s" % _beat(chart, float(chart.editor.get("playhead", 0.0))))
	lines.append("")
	return "\n".join(lines)


static func _note_line(chart: Chart, note: Note) -> String:
	var options := _note_options(note)
	match note.type:
		"tap":
			return "tap,%s,%s,%s%s" % [_beat(chart, note.beat), _num(note.angle), _num(note.arc_width()), options]
		"hold":
			var suffix := ""
			if note.hold_style == "curved":
				suffix = ",style=curved"
			if not note.visual_pts.is_empty():
				suffix += ",body=%s" % _points(note.visual_pts)
			return "hold,%s,%s,%s,%s%s%s" % [_beat(chart, note.beat), _num(note.angle), _num(note.arc_width()), _beat(chart, note.end_beat), suffix, options]
		"path":
			var suffix := ",tol=%s,samples=%s" % [_num(note.tolerance), _num(note.samples_per_beat)]
			if not note.visual_pts.is_empty():
				suffix += ",visual=%s" % _points(note.visual_pts)
			if not note.trace_pts.is_empty():
				suffix += ",pts=%s" % _trace_points(note.trace_pts)
			if note.path_style != "arc":
				suffix += ",style=%s" % note.path_style
			if note.path_speed != 1.0:
				suffix += ",speed=%s" % _num(note.path_speed)
			if not note.path_gaps.is_empty():
				var ranges: Array[String] = []
				for gap in note.path_gaps:
					ranges.append("%s:%s" % [_num(float(gap.get("from", 0.0))), _num(float(gap.get("to", 0.0)))])
				suffix += ",erase=%s" % "|".join(ranges)
			return "path,%s,%s,%s,%s,%s,%s%s%s" % [
				_beat(chart, note.beat), _num(note.angle), _num(note.width),
				_beat(chart, note.end_beat), _num(note.tail_angle), _num(note.tail_width),
				suffix, options,
			]
		"seek":
			return "seek,%s,%d%s" % [_beat(chart, note.beat), 1 if note.seek_orien == 1 else 0, options]
		"anchor":
			var suffix := ""
			if note.anchor_pair >= 0:
				suffix += ",pair=%d" % note.anchor_pair
			if not note.pair_id.is_empty():
				suffix += ",pairId=%s" % _clean(note.pair_id)
			return "anchor,%s,%s%s%s" % [_beat(chart, note.beat), _num(note.angle), suffix, options]
		"bell":
			var suffix := ",width=%s" % _num(note.bell_width())
			return "bell,%s,%s,%s%s%s" % [_beat(chart, note.beat), _num(note.center_u), _num(note.radius), suffix, options]
	return "tap,%s,%s,%s%s" % [_beat(chart, note.beat), _num(note.angle), _num(note.width), options]


static func _note_options(note: Note) -> String:
	var options: Array[String] = []
	if note.color != 0:
		options.append("color=%d" % note.color)
	if note.has_custom_color:
		# 自定义色：color 槽位没有 RGB，附加 rgb= 给能读的编辑器，不认识的会忽略。
		options.append("rgb=#%s" % note.custom_color.to_html(false))
	if note.lock:
		options.append("lock=1")
	if options.is_empty():
		return ""
	return ";" + ";".join(options)


static func _points(points: Array[Dictionary]) -> String:
	var result: Array[String] = []
	for point in points:
		result.append("(%s,%s)" % [_num(float(point.get("db", 0.0))), _num(float(point.get("da", 0.0)))])
	return "".join(result)


static func _trace_points(points: Array[Dictionary]) -> String:
	var result: Array[String] = []
	for point in points:
		result.append("(%s,%s,%s)" % [
			_num(float(point.get("x", 0.0))), _num(float(point.get("y", 0.0))),
			_num(float(point.get("db", 0.0))),
		])
	return "".join(result)


static func _beat(chart: Chart, beat: float) -> String:
	return chart.timing.format_beat(beat, 16)


static func _num(value: float) -> String:
	return "%.3f" % value


static func _clean(value: String) -> String:
	return value.replace("\r", " ").replace("\n", " ").strip_edges()


# ── 可解压的 .lbp 包 ────────────────────────────────────────────────────────
# 单个 zip：manifest.json + chart.json（完整 JSON，能往返）+ assets/（音频/曲绘/
# 视频/故事板）。纯文本 LBP 是有损旁路，这里只负责“能带走、能读回来”。
const PACK_FORMAT := "tamaki3-pack"
const PACK_VERSION := 1
const PACK_CHART := "chart.json"
const PACK_MANIFEST := "manifest.json"


static func export_package(chart: Chart, path: String) -> Error:
	if chart == null:
		last_error = "没有谱面"
		return ERR_INVALID_PARAMETER
	var data := ChartIO.chart_to_dict(chart)
	var general: Dictionary = data.get("general", {})
	var metadata: Dictionary = data.get("metadata", {})
	var files: Array[String] = []
	for key in ["audio", "video"]:
		var value := String(general.get(key, ""))
		if FileAccess.file_exists(value):
			files.append(value)
	var cover := String(metadata.get("background", ""))
	if FileAccess.file_exists(cover):
		files.append(cover)
	var sb_dir := String(metadata.get("storyboard", ""))
	var sb_files: Array[String] = []
	if not sb_dir.is_empty() and DirAccess.dir_exists_absolute(sb_dir):
		for name in DirAccess.get_files_at(sb_dir):
			sb_files.append(sb_dir + "/" + name)

	# 写临时文件再改名：导出中断不会留下半个包。
	var temp := path + ".tmp"
	var packer := ZIPPacker.new()
	var err := packer.open(temp)
	if err != OK:
		last_error = "无法写入 %s：%s" % [path, error_string(err)]
		return err

	var index := 0
	for src in files:
		var dst := "assets/%02d_%s" % [index, _pack_name(src.get_file())]
		index += 1
		if _pack_write(packer, dst, FileAccess.get_file_as_bytes(src)) != OK:
			packer.close()
			last_error = "打包失败：%s" % src.get_file()
			return ERR_CANT_CREATE
		for key in ["audio", "video"]:
			if String(general.get(key, "")) == src:
				general[key] = dst
		if cover == src:
			metadata["background"] = dst
	if not sb_files.is_empty():
		for src in sb_files:
			if _pack_write(packer, "assets/sb/" + _pack_name(src.get_file()),
					FileAccess.get_file_as_bytes(src)) != OK:
				packer.close()
				last_error = "打包故事板失败：%s" % src.get_file()
				return ERR_CANT_CREATE
		metadata["storyboard"] = "assets/sb"
	data["general"] = general
	data["metadata"] = metadata

	var manifest := {
		"format": PACK_FORMAT,
		"version": PACK_VERSION,
		"chart": PACK_CHART,
		"title": String(metadata.get("title", "")),
		"difficulty": chart.difficulty,
	}
	if _pack_write(packer, PACK_CHART, JSON.stringify(data, "\t").to_utf8_buffer()) != OK \
			or _pack_write(packer, PACK_MANIFEST, JSON.stringify(manifest, "\t").to_utf8_buffer()) != OK:
		packer.close()
		last_error = "打包失败：写不进谱面"
		return ERR_CANT_CREATE
	packer.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if err != OK:
		last_error = "无法写入 %s：%s" % [path, error_string(err)]
	return err


static func import_package(path: String) -> Chart:
	last_error = ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		last_error = "不是可读的谱面包：%s" % path.get_file()
		return null
	var manifest = JSON.parse_string(zip.read_file(PACK_MANIFEST).get_string_from_utf8())
	if not (manifest is Dictionary) or String((manifest as Dictionary).get("format", "")) != PACK_FORMAT:
		zip.close()
		last_error = "不是 Tamaki 谱面包"
		return null
	var data = JSON.parse_string(zip.read_file(PACK_CHART).get_string_from_utf8())
	if not (data is Dictionary):
		zip.close()
		last_error = "谱面包里的谱面损坏"
		return null
	var base := "user://imports/lbp_%s" % path.md5_text().substr(0, 8)
	for name in zip.get_files():
		if name == PACK_MANIFEST or name == PACK_CHART or not _pack_safe(name):
			continue
		var target := base + "/" + name
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file != null:
			file.store_buffer(zip.read_file(name))
			file.close()
	zip.close()

	var general: Dictionary = data.get("general", {})
	for key in ["audio", "video"]:
		general[key] = _unpack_path(String(general.get(key, "")), base)
	var metadata: Dictionary = data.get("metadata", {})
	metadata["background"] = _unpack_path(String(metadata.get("background", "")), base)
	metadata["storyboard"] = _unpack_path(String(metadata.get("storyboard", "")), base)
	data["general"] = general
	data["metadata"] = metadata
	var chart := ChartIO.chart_from_dict(data)
	if chart == null:
		last_error = "谱面包里的谱面无法解析"
	return chart


static func is_package(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var magic := file.get_buffer(2)
	file.close()
	return magic.size() == 2 and magic[0] == 0x50 and magic[1] == 0x4B


static func _pack_write(packer: ZIPPacker, name: String, bytes: PackedByteArray) -> Error:
	var err := packer.start_file(name)
	if err != OK:
		return err
	err = packer.write_file(bytes)
	packer.close_file()
	return err


static func _pack_name(name: String) -> String:
	var clean := name.validate_filename().strip_edges()
	return clean if not clean.is_empty() else "asset"


## 包内路径只允许相对、正斜杠；挡住 zip-slip（../、绝对路径、盘符）。
static func _pack_safe(name: String) -> bool:
	return not name.contains("..") and not name.begins_with("/") and not name.contains("\\") \
		and not name.contains(":")


static func _unpack_path(value: String, base: String) -> String:
	if value.begins_with("assets/"):
		return base + "/" + value
	return value
