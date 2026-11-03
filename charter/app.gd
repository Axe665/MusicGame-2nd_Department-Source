extends Node

signal chart_changed
signal chart_live_changed
signal selection_changed
signal playhead_changed(beat: float)
signal tool_changed(tool: String)
signal status_changed
signal save_state_changed
signal validation_changed(issues: Array)
signal notice(message: String, level: String)

var chart: Chart = null
var chart_path: String = ""
var dirty: bool = false
var playhead_beat: float = 0.0
var last_import_report: String = ""
var playtest_offset_ms: float = 0.0

var selected_notes: Array[int] = []
var selected_region_id: int = -1
var selected_event_id: String = ""
var selected_shape_id: String = "S0"
var selected_segment_index: int = -1
var selected_view_index: int = -1

var tool: String = "select"
var snap_denominator: int = 4
var snap_triplet: bool = false
var snap_quint: bool = false
var zoom_px_per_beat: float = 28.0
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


func _set_initial_focus_notice() -> void:
	notice.emit("已载入示例谱：按空格播放，F5 试玩，Ctrl+S 保存。", "info")


func set_chart(new_chart: Chart, path: String = "", mark_dirty: bool = false) -> void:
	_live_change_pending = false
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
	chart_changed.emit()
	selection_changed.emit()
	playhead_changed.emit(playhead_beat)
	save_state_changed.emit()
	status_changed.emit()
	_emit_validation()


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
	autosave()


func set_playhead(beat: float) -> void:
	if chart == null:
		return
	playhead_beat = clampf(beat, -4.0, chart.duration_beats() + 8.0)
	playhead_changed.emit(playhead_beat)


func snap_beat(beat: float, bypass: bool = false) -> float:
	if bypass or snap_denominator <= 0:
		return beat
	var step := 1.0 / float(snap_denominator)
	if snap_triplet:
		step *= 2.0 / 3.0
	elif snap_quint:
		step *= 4.0 / 5.0
	return roundf(beat / step) * step


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
