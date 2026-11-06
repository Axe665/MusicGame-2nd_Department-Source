extends Node

signal chart_changed
signal chart_replaced
signal chart_live_changed
signal selection_changed
signal playhead_changed(beat: float)
## 用户主动跳转（点时间轴、拖进度条）。播放中收到它会重新对齐音频。
signal seek_requested(beat: float)
signal tool_changed(tool: String)
signal status_changed
signal save_state_changed
signal validation_changed(issues: Array)
signal notice(message: String, level: String)
signal appearance_changed
signal preview_sfx
signal snap_changed(division: int)
signal flow_changed(down: bool)
signal audio_import_requested
signal audio_detect_requested(path: String)

var chart: Chart = null
var chart_path: String = ""
var dirty: bool = false
var playhead_beat: float = 0.0
var last_import_report: String = ""
var playtest_offset_ms: float = 0.0
var flow_scale: float = 1.0
var ffmpeg_path: String = "ffmpeg"
var star_speed: float = 1.0
## 星星主色（舞萌蓝），所有 Path 共用；试玩设置里可改。
var star_color: Color = Color(0.55, 0.75, 1.0)
## Trace 门框主色（默认银白）。
var trace_color: Color = Color(0.78, 0.86, 1.0)
var note_skin: String = "candy"
var hit_fx_style: String = "burst"
var hit_sfx_style: String = "default"
## 帧率上限："60" / "120" / "vsync" / "unlimited"。
var frame_cap: String = "vsync"
## 局内动态校准判定偏移（默认关）。
var dynamic_offset: bool = false
## 上一局的平均判定偏差，供试玩设置显示。
var last_bias_ms: float = 0.0

var selected_notes: Array[int] = []
var clipboard_notes: Array[Dictionary] = []
var selected_region_id: int = -1
var selected_event_id: String = ""
var selected_shape_id: String = "S0"
var selected_segment_index: int = -1
var selected_view_index: int = -1

var tool: String = "select"
var snap_division: int = GridDivisions.DEFAULT_DIVISION
var beat_subdivisions: int = 4
var vertical_lines: int = 11
var vertical_stretch: float = 0.0
var zoom_px_per_beat: float = 28.0
var time_flows_down: bool = true
var hud_visible: bool = true
var use_3d_ring: bool = true
var mouse_tilt: bool = true
var debug_overlay: bool = false
var waveform_visible: bool = true
var ghost_regions: bool = false
var boundary_mode: bool = false
var trace_draw_mode: bool = false

var undo := UndoStack.new()
var _edit_before: Dictionary = {}
var _editing: bool = false
var _live_change_pending: bool = false
var _commands_since_autosave: int = 0
var _autosave_timer: Timer


func _ready() -> void:
	_load_settings()
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 60.0
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timer)
	add_child(_autosave_timer)
	var demo_path := "user://charts/demo.json"
	var start_chart: Chart = null
	var from_repo := false
	if FileAccess.file_exists(demo_path):
		start_chart = ChartIO.load_chart(demo_path)
	if start_chart == null and FileAccess.file_exists("res://charts/demo.json"):
		start_chart = ChartIO.load_chart("res://charts/demo.json")
		from_repo = true
	if start_chart == null:
		start_chart = DemoChart.make_demo()
		from_repo = true
	set_chart(start_chart, demo_path, from_repo)
	call_deferred("_set_initial_focus_notice")


const SETTINGS_PATH := "user://settings.json"


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			var data: Dictionary = parsed
			note_skin = String(data.get("note_skin", note_skin))
			hit_fx_style = String(data.get("hit_fx_style", hit_fx_style))
			hit_sfx_style = String(data.get("hit_sfx_style", hit_sfx_style))
			ffmpeg_path = String(data.get("ffmpeg", ffmpeg_path))
			frame_cap = String(data.get("frame_cap", frame_cap))
			playtest_offset_ms = float(data.get("playtest_offset_ms", playtest_offset_ms))
			dynamic_offset = bool(data.get("dynamic_offset", dynamic_offset))
			last_bias_ms = float(data.get("last_bias_ms", last_bias_ms))
	MediaIO.set_ffmpeg_exe(ffmpeg_path)
	apply_frame_cap()


## 帧率选项：60 / 120 关垂直同步；vsync 跟随显示器；unlimited 不限帧。
func apply_frame_cap() -> void:
	match frame_cap:
		"60":
			Engine.max_fps = 60
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"120":
			Engine.max_fps = 120
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"unlimited":
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_:
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func save_settings() -> void:
	var data := {"note_skin": note_skin, "hit_fx_style": hit_fx_style, "hit_sfx_style": hit_sfx_style, "ffmpeg": ffmpeg_path, "frame_cap": frame_cap, "playtest_offset_ms": playtest_offset_ms, "dynamic_offset": dynamic_offset, "last_bias_ms": last_bias_ms}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _set_initial_focus_notice() -> void:
	notice.emit("已载入示例谱：按空格播放，F5 试玩，Ctrl+S 保存。", "info")


func set_ffmpeg_path(path: String) -> void:
	ffmpeg_path = path.strip_edges()
	if ffmpeg_path.is_empty():
		ffmpeg_path = "ffmpeg"
	MediaIO.set_ffmpeg_exe(ffmpeg_path)
	save_settings()
	notice.emit("ffmpeg 路径：%s" % ffmpeg_path, "info")


func set_chart(new_chart: Chart, path: String = "", mark_dirty: bool = false) -> void:
	_live_change_pending = false
	chart_replaced.emit()
	chart = new_chart
	chart_path = path
	dirty = mark_dirty
	playhead_beat = 0.0
	undo.clear()
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = ""
	selected_shape_id = chart.default_shape_id if chart != null else "S0"
	selected_segment_index = -1
	selected_view_index = -1
	if chart != null:
		snap_division = GridDivisions.normalize(int(chart.editor.get("snap", snap_division)))
		time_flows_down = bool(chart.editor.get("flow_down", time_flows_down))
	chart_changed.emit()
	snap_changed.emit(snap_division)
	flow_changed.emit(time_flows_down)
	selection_changed.emit()
	playhead_changed.emit(playhead_beat)
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()


func apply_detected_timing(bpm: float, offset_ms: float, apply_offset: bool, audio_path: String) -> bool:
	if chart == null:
		return false
	if not is_finite(bpm) or bpm <= 0.0:
		notice.emit("BPM 无效，未应用音频。", "error")
		return false
	if not is_finite(offset_ms):
		notice.emit("offset 无效，未应用音频。", "error")
		return false
	if apply_offset:
		var period_ms := 60000.0 / maxf(1.0, bpm)
		if absf(offset_ms) > period_ms + 1.0:
			notice.emit("offset 超出单拍范围，未应用音频。", "error")
			return false
	var prepared := MediaIO.prepare_audio(audio_path)
	if prepared.is_empty():
		notice.emit("音频读取失败：%s" % MediaIO.last_error, "error")
		return false
	var stream := ChartIO.audio_stream_from_path(prepared)
	if stream == null or stream.get_length() <= 0.0:
		notice.emit("音频播放流加载失败：%s" % audio_path.get_file(), "error")
		return false
	var length_ms := stream.get_length() * 1000.0
	begin_edit()
	chart.audio_path = audio_path
	if not chart.timing.points.is_empty():
		chart.timing.points[0].bpm = clampf(bpm, 20.0, 600.0)
		chart.timing.sort_points()
	if apply_offset:
		chart.offset_ms = offset_ms
		chart.timing.offset_ms = offset_ms
	finish_edit()
	notice.emit("已应用 %s：%.1f BPM，offset %.0f ms，音频 %.2f 秒。" % [
		audio_path.get_file(), chart.timing.bpm_at(0.0), chart.offset_ms, length_ms / 1000.0,
	], "info")
	return true


func snapshot() -> Dictionary:
	if chart == null:
		return {}
	return ChartIO.chart_to_dict(chart)


func restore_snapshot(data: Dictionary) -> void:
	var restored := ChartIO.chart_from_dict(data)
	if restored == null:
		notice.emit("撤销失败：%s" % ChartIO.last_error, "error")
		return
	chart = restored
	_prune_selection()
	chart_changed.emit()
	selection_changed.emit()
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()


func mutate(callback: Callable) -> void:
	if chart == null:
		return
	var before := snapshot()
	callback.call()
	var after := snapshot()
	if before == after:
		return
	undo.record(before)
	dirty = true
	_after_change()


func begin_edit() -> void:
	if _editing or chart == null:
		return
	_edit_before = snapshot()
	_editing = true


func finish_edit() -> void:
	if not _editing:
		return
	_flush_live_change()
	_editing = false
	var after := snapshot()
	if _edit_before == after:
		return
	undo.record(_edit_before)
	dirty = true
	_after_change()


func _after_change() -> void:
	_commands_since_autosave += 1
	chart_changed.emit()
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()
	if _commands_since_autosave >= 20:
		autosave()


func touch_chart() -> void:
	## Emit live updates during a drag; the undo entry is recorded on finish_edit().
	# Mouse input may arrive several times per rendered frame. Full validation
	# belongs to the committed edit, not to every intermediate mouse position.
	_live_change_pending = true


func _process(_delta: float) -> void:
	_flush_live_change()


func _flush_live_change() -> void:
	if not _live_change_pending:
		return
	_live_change_pending = false
	chart_live_changed.emit()
	status_changed.emit()


func undo_chart() -> void:
	if chart == null or not undo.can_undo():
		return
	var current := snapshot()
	restore_snapshot(undo.undo(current))
	dirty = true


func redo_chart() -> void:
	if chart == null or not undo.can_redo():
		return
	var current := snapshot()
	restore_snapshot(undo.redo(current))
	dirty = true


func save_chart() -> bool:
	if chart == null:
		return false
	if chart_path.is_empty():
		notice.emit("请先另存为（Ctrl+Shift+S）", "warning")
		return false
	var errors := Validator.errors(Validator.validate(chart))
	if not errors.is_empty():
		notice.emit("有 %d 个校验错误，已阻止保存：%s" % [errors.size(), errors[0].get("message", "")], "error")
		return false
	chart.offset_ms = chart.timing.offset_ms
	var err := ChartIO.save_chart(chart, chart_path)
	if err != OK:
		notice.emit("保存失败：%s" % ChartIO.last_error, "error")
		return false
	dirty = false
	_commands_since_autosave = 0
	save_state_changed.emit()
	status_changed.emit()
	notice.emit("已保存 %s" % chart_path.get_file(), "info")
	return true


func save_chart_as(path: String) -> bool:
	chart_path = path
	return save_chart()


func load_chart(path: String) -> bool:
	var loaded := ChartIO.load_chart(path)
	if loaded == null:
		notice.emit("打开失败：%s" % ChartIO.last_error, "error")
		return false
	set_chart(loaded, path)
	notice.emit("已打开 %s" % path.get_file(), "info")
	return true


func new_chart(meta: Dictionary) -> void:
	set_chart(DemoChart.make_empty(meta), "", true)
	notice.emit("新谱面已创建；先设置 BPM/offset，再画第一条边界。", "info")


func import_osz(path: String, difficulty_index: int = 0) -> bool:
	var result := OsuIO.import_osz(path, difficulty_index)
	last_import_report = String(result.get("report", ""))
	if result.is_empty():
		notice.emit("osu! 导入失败：%s" % OsuIO.last_error, "error")
		return false
	var imported: Chart = result["chart"]
	set_chart(imported, "", true)
	var stream := ChartIO.audio_stream_from_path(imported.audio_path)
	if stream is AudioStream:
		last_import_report += "\n音频流已加载：%s（%.1fs）" % [imported.audio_path.get_file(), stream.get_length()]
		print("[audio] imported ", imported.audio_path, " len=", stream.get_length())
	else:
		last_import_report += "\n音频流未加载：%s" % imported.audio_path
		print("[audio] FAILED to load ", imported.audio_path)
	notice.emit("已导入 %s：%d 个音符，%d 个 BPM 点。请另存为 JSON。" % [path.get_file(), imported.notes.size(), imported.timing.points.size()], "info")
	return true


func import_maimai(path: String, difficulty_index: int = 0) -> bool:
	var imported := SimaiIO.import_maidata(path, difficulty_index)
	last_import_report = SimaiIO.last_report
	if imported == null:
		notice.emit("舞萌导入失败：%s" % SimaiIO.last_error, "error")
		return false
	set_chart(imported, "", true)
	notice.emit("已导入 %s：%d 个音符，%d 个 BPM 点。请另存为 JSON。" % [path.get_file(), imported.notes.size(), imported.timing.points.size()], "info")
	return true


func export_lbp(path: String) -> bool:
	if chart == null:
		return false
	var err := LBPIO.export_to_file(chart, path)
	if err != OK:
		notice.emit("导出 .lbp 失败：%s" % LBPIO.last_error, "error")
		return false
	notice.emit("已导出 %s" % path.get_file(), "info")
	return true


func autosave() -> void:
	if chart == null or not dirty:
		return
	var data := ChartIO.to_json(chart)
	var err := ChartIO.atomic_write("user://autosave.json", data)
	if err == OK:
		_commands_since_autosave = 0
		status_changed.emit()


func load_autosave() -> bool:
	if not FileAccess.file_exists("user://autosave.json"):
		notice.emit("没有自动保存文件", "warning")
		return false
	var loaded := ChartIO.load_chart("user://autosave.json")
	if loaded == null:
		notice.emit("自动保存损坏：%s" % ChartIO.last_error, "error")
		return false
	set_chart(loaded, "", true)
	notice.emit("已恢复自动保存；请另存为正式文件。", "info")
	return true


func _on_autosave_timer() -> void:
	# 基准/导入测试会换掉当前谱面，自动保存会把用户正在编辑的谱面覆盖掉。
	if "--bench" in OS.get_cmdline_user_args():
		return
	autosave()


func set_playhead(beat: float) -> void:
	if chart == null:
		return
	playhead_beat = clampf(beat, -4.0, chart.duration_beats() + 8.0)
	playhead_changed.emit(playhead_beat)


## 用户发起的跳转：点时间轴、拖进度条、按定位按钮都走这里。
## 播放中光改 playhead_beat 会被下一帧的音频推进覆盖，所以要先发信号让播放器重新对齐。
func seek(beat: float) -> void:
	if chart == null:
		return
	var target := clampf(beat, -4.0, chart.duration_beats() + 8.0)
	seek_requested.emit(target)
	set_playhead(target)


func snap_beat(beat: float, bypass: bool = false) -> float:
	return GridDivisions.snap(beat, snap_division, bypass)


func set_snap_division(division: int) -> void:
	var normalized := GridDivisions.normalize(division)
	if chart != null:
		chart.editor["snap"] = normalized
	if snap_division == normalized:
		return
	snap_division = normalized
	snap_changed.emit(snap_division)
	status_changed.emit()


func set_time_flows_down(down: bool) -> void:
	if chart != null:
		chart.editor["flow_down"] = down
	if time_flows_down == down:
		return
	time_flows_down = down
	flow_changed.emit(down)
	status_changed.emit()


func request_audio_import() -> void:
	audio_import_requested.emit()


func request_audio_detect() -> void:
	audio_detect_requested.emit(chart.audio_path if chart != null else "")


## Writes an auto-detected tempo into the chart. The base BPM always lives on
## the first timing point (the inspector labels it "基准 BPM"), and the offset is
## mirrored into both Chart.offset_ms and TimingMap.offset_ms because the save
## path treats the timing map as authoritative.
func set_tool(new_tool: String) -> void:
	tool = new_tool
	boundary_mode = new_tool == "boundary"
	trace_draw_mode = new_tool == "trace"
	tool_changed.emit(tool)
	status_changed.emit()


func select_note(note_id: int, additive: bool = false) -> void:
	if not additive:
		selected_notes.clear()
		selected_region_id = -1
		selected_event_id = ""
		selected_view_index = -1
	if note_id >= 0 and not selected_notes.has(note_id):
		selected_notes.append(note_id)
	selection_changed.emit()
	status_changed.emit()


func mirror_selected_notes() -> void:
	var notes := get_selected_notes()
	if notes.is_empty():
		return
	begin_edit()
	for note in notes:
		note.angle = fposmod(360.0 - note.angle, 360.0)
		note.tail_angle = fposmod(360.0 - note.tail_angle, 360.0)
		for point in note.visual_pts:
			point["da"] = -float(point.get("da", 0.0))
		if note.type == "bell":
			note.center_u = fposmod(1.0 - note.center_u, 1.0)
		if note.type == "trace" or note.trace_style == "slider":
			for point in note.trace_pts:
				point["x"] = -float(point.get("x", 0.0))
		elif note.type == "path":
			for point in note.trace_pts:
				point["x"] = -float(point.get("x", 0.0))
	finish_edit()
	notice.emit("已镜像 %d 个音符" % notes.size(), "info")


func rotate_selected_notes(degrees: float) -> void:
	var notes := get_selected_notes()
	if notes.is_empty():
		return
	begin_edit()
	for note in notes:
		note.angle = fposmod(note.angle + degrees, 360.0)
		note.tail_angle = fposmod(note.tail_angle + degrees, 360.0)
		for point in note.visual_pts:
			point["da"] = float(point.get("da", 0.0)) + degrees
		if note.type == "bell":
			note.center_u = fposmod(note.center_u + degrees / 360.0, 1.0)
		if note.type in ["trace", "path"] or note.trace_style == "slider":
			var rad := deg_to_rad(degrees)
			for point in note.trace_pts:
				var x := float(point.get("x", 0.0))
				var y := float(point.get("y", 0.0))
				point["x"] = x * cos(rad) - y * sin(rad)
				point["y"] = x * sin(rad) + y * cos(rad)
	finish_edit()
	notice.emit("已旋转 %d 个音符 %.0f°" % [notes.size(), degrees], "info")


func copy_selected_notes() -> void:
	clipboard_notes.clear()
	var notes := get_selected_notes()
	if notes.is_empty():
		return
	var base_beat := notes[0].beat
	for note in notes:
		var data := note.to_dict()
		data["beat"] = note.beat - base_beat
		data["end_beat"] = note.end_beat - base_beat
		clipboard_notes.append(data)
	notice.emit("已复制 %d 个音符" % notes.size(), "info")


func paste_notes() -> void:
	if chart == null or clipboard_notes.is_empty():
		return
	var base_beat := playhead_beat
	var pasted: Array[int] = []
	begin_edit()
	for data in clipboard_notes:
		var note := Note.from_dict(data)
		note.id = chart.next_note_id()
		note.beat = base_beat + float(data.get("beat", 0.0))
		note.end_beat = base_beat + float(data.get("end_beat", 0.0))
		chart.notes.append(note)
		pasted.append(note.id)
	finish_edit()
	select_notes(pasted)
	notice.emit("已粘贴 %d 个音符" % pasted.size(), "info")


func select_notes(ids: Array[int]) -> void:
	selected_notes = ids.duplicate()
	selected_region_id = -1
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_region(region_id: int) -> void:
	selected_notes.clear()
	selected_region_id = region_id
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_event(event_id: String) -> void:
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = event_id
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func select_shape(shape_id: String) -> void:
	selected_shape_id = shape_id
	selection_changed.emit()
	status_changed.emit()


func select_segment(index: int) -> void:
	selected_segment_index = index
	selection_changed.emit()
	status_changed.emit()


func select_view(index: int) -> void:
	selected_view_index = index
	selection_changed.emit()
	status_changed.emit()


func clear_selection() -> void:
	selected_notes.clear()
	selected_region_id = -1
	selected_event_id = ""
	selected_view_index = -1
	selection_changed.emit()
	status_changed.emit()


func get_selected_notes() -> Array[Note]:
	var result: Array[Note] = []
	if chart == null:
		return result
	for note in chart.notes:
		if selected_notes.has(note.id):
			result.append(note)
	return result


func get_selected_note() -> Note:
	var notes := get_selected_notes()
	return notes[0] if notes.size() == 1 else null


func get_selected_region() -> Region:
	if chart == null or selected_region_id < 0:
		return null
	for region in chart.regions:
		if region.id == selected_region_id:
			return region
	return null


func get_selected_event() -> BoundaryEvent:
	if chart == null or selected_event_id.is_empty():
		return null
	for event in chart.events:
		if event.id == selected_event_id:
			return event
	return null


func get_selected_shape() -> BoundaryShape:
	if chart == null:
		return null
	return chart.get_shape(selected_shape_id)


func get_selected_segment() -> BoundarySegment:
	var shape := get_selected_shape()
	if shape == null:
		return null
	var sorted := shape.sorted_segments()
	if selected_segment_index < 0 or selected_segment_index >= sorted.size():
		return null
	return sorted[selected_segment_index]


func get_selected_view() -> ViewState:
	if chart == null or selected_view_index < 0 or selected_view_index >= chart.view_states.size():
		return null
	return chart.view_states[selected_view_index]


func _prune_selection() -> void:
	var valid_notes: Array[int] = []
	for note in chart.notes:
		if selected_notes.has(note.id):
			valid_notes.append(note.id)
	selected_notes = valid_notes
	if selected_region_id >= 0:
		var found := false
		for region in chart.regions:
			if region.id == selected_region_id:
				found = true
				break
		if not found:
			selected_region_id = -1
	if not selected_event_id.is_empty():
		var found := false
		for event in chart.events:
			if event.id == selected_event_id:
				found = true
				break
		if not found:
			selected_event_id = ""
	if chart.get_shape(selected_shape_id) == null:
		selected_shape_id = chart.default_shape_id
	selected_segment_index = -1


func _emit_validation() -> void:
	if chart == null:
		validation_changed.emit([])
		return
	validation_changed.emit(Validator.validate(chart))


func validation_issues() -> Array[Dictionary]:
	if chart == null:
		return []
	return Validator.validate(chart)
