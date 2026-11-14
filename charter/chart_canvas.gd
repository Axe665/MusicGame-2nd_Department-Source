class_name ChartCanvas
extends Control

signal hover_changed(u: float, beat: float)
signal notice(message: String, level: String)

const LEFT_MARGIN := 58.0
const TOP_MARGIN := 24.0
const BOTTOM_MARGIN := 12.0
const RIGHT_MARGIN := 58.0
const WAVE_WIDTH := 24.0
const NOTE_TOOLS := ["tap", "hold", "path", "seek", "anchor", "bell"]
const PATH_HIT_RADIUS := 12.0
const PATH_CHAIN_BLUE := Color("#4D8DFF")
const DIVISION_WIDTH := 42.0
const DIVISION_ITEM_HEIGHT := 22.0
const DIVISION_GAP := 3.0
const DIVISION_MARGIN := 8.0

var _app: Node = null
var px_per_beat: float = 28.0
var scroll_beat: float = 0.0
var follow_playhead: bool = true
var flow_down: bool = true
var snap_division: int = GridDivisions.DEFAULT_DIVISION

var _mouse_pos: Vector2 = Vector2.ZERO
var _hover_u: float = 0.0
var _hover_beat: float = 0.0
var _drag_mode: String = ""
var _drag_start: Vector2 = Vector2.ZERO
var _drag_start_beat: float = 0.0
var _drag_start_u: float = 0.0
var _drag_notes: Array[Dictionary] = []
var _drag_region: Region = null
var _drag_width_side: int = 0
var _drag_width_note: Note = null
var _drag_width_origin: float = 0.0
var _drag_width_start: float = 0.0
var _marquee: Rect2 = Rect2()
var _marquee_start_beat: float = 0.0
var _marquee_start_u: float = 0.0
var _marquee_end_beat: float = 0.0
var _marquee_end_u: float = 0.0
var _right_hit: Dictionary = {}
var _pending_path: Note = null
var _pending_path_parent: Note = null
var _pending_hold: Note = null

var _waveform_peaks: PackedFloat32Array = PackedFloat32Array()
var _waveform_duration: float = 0.0
var _waveform_audio_path: String = ""
var _wave_key: String = ""
var _wave_right: PackedVector2Array = PackedVector2Array()
var _wave_left: PackedVector2Array = PackedVector2Array()
var _last_playhead_redraw: int = 0
var _overlay: Control
var _sorted_notes: Array[Note] = []
var _sorted_chart: Chart = null
var _sorted_count: int = -1
var _sorted_dirty: bool = true
var _sorted_max_duration: float = 0.0
var _ghost_layer = null
var _clipboard_notes: Array[Note] = []
var _clipboard_reference_beat: float = 0.0
var _clipboard_mouse_beat: float = 0.0
var _clipboard_active: bool = false
var _clipboard_cut: bool = false
var _ghost_last_scroll: float = -INF
var _ghost_last_px: float = -INF
var _ghost_last_stretch: float = -INF
var _ghost_last_size: Vector2 = Vector2.ZERO
var _division_rects: Array[Rect2] = []
var _division_hover: int = -1
var _flow_button: Button


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	set_process(true)
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_replaced.connect(_clear_clipboard_on_chart_replace)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.selection_changed.connect(_on_selection_changed)
		_app.tool_changed.connect(_on_tool_changed)
		_app.snap_changed.connect(_on_snap_changed)
		_app.flow_changed.connect(_on_flow_changed)
		px_per_beat = _app.zoom_px_per_beat
	var ghost_script: Script = load("res://charter/chart_ghost_layer.gd")
	if ghost_script != null:
		_ghost_layer = ghost_script.new()
		_ghost_layer.name = "GhostLayer"
		_ghost_layer.visible = false
		add_child(_ghost_layer)
		_ghost_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ghost_layer._app = _app
		snap_division = _app.snap_division
		flow_down = _app.time_flows_down
		_ghost_layer.flow_down = flow_down
	_overlay = load("res://charter/chart_overlay.gd").new()
	_overlay.canvas = self
	add_child(_overlay)
	_build_flow_button()
	_refresh_waveform()


func _process(_delta: float) -> void:
	if not _clipboard_active or _ghost_layer == null:
		return
	var stretch: float = float(_app.vertical_stretch) if _app != null else 0.0
	if (not is_equal_approx(_ghost_last_scroll, scroll_beat)
			or not is_equal_approx(_ghost_last_px, px_per_beat)
			or not is_equal_approx(_ghost_last_stretch, stretch)
			or _ghost_last_size != size):
		_sync_ghost_layer()


func _plot_rect() -> Rect2:
	return Rect2(LEFT_MARGIN, TOP_MARGIN, maxf(10.0, size.x - LEFT_MARGIN - RIGHT_MARGIN), maxf(10.0, size.y - TOP_MARGIN - BOTTOM_MARGIN))


func _u_to_x(u: float) -> float:
	var plot := _plot_rect()
	return plot.position.x + clampf(u, 0.0, 1.0) * plot.size.x


func _x_to_u(x: float) -> float:
	var plot := _plot_rect()
	return clampf((x - plot.position.x) / maxf(1.0, plot.size.x), 0.0, 0.999999)


func _vertical_scale() -> float:
	if _app == null:
		return 1.0
	return 1.0 + clampf(float(_app.vertical_stretch), 0.0, 10.0) * 0.5


func _effective_px_per_beat() -> float:
	return px_per_beat * _vertical_scale()


func _beat_to_y(beat: float) -> float:
	var plot := _plot_rect()
	var distance := (beat - scroll_beat) * _effective_px_per_beat()
	if flow_down:
		return plot.position.y + distance
	return plot.end.y - distance


func _y_to_beat(y: float) -> float:
	var plot := _plot_rect()
	if flow_down:
		return scroll_beat + (y - plot.position.y) / maxf(0.1, _effective_px_per_beat())
	return scroll_beat + (plot.end.y - y) / maxf(0.1, _effective_px_per_beat())


func _visible_beats() -> float:
	return size.y / maxf(10.0, _effective_px_per_beat())


func _clear_clipboard_on_chart_replace() -> void:
	_cancel_pending()
	cancel_clipboard(false)


func has_clipboard() -> bool:
	return _clipboard_active and not _clipboard_notes.is_empty()


func copy_selection(cut: bool = false) -> void:
	if _app == null or _app.chart == null:
		return
	var selected: Array[Note] = _app.selection_with_partners()
	if selected.is_empty():
		notice.emit("先选中音符，再复制或剪切。", "warning")
		return
	var copies: Array[Note] = []
	var first_beat := INF
	for note in selected:
		copies.append(Note.from_dict(note.to_dict()))
		first_beat = minf(first_beat, note.beat)
	copies.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_clipboard_notes = copies
	_clipboard_reference_beat = first_beat
	_clipboard_mouse_beat = _current_mouse_beat()
	_clipboard_active = true
	_clipboard_cut = cut
	if cut:
		var ids: Array[int] = []
		for note in selected:
			ids.append(note.id)
		_app.begin_edit()
		for note in _app.chart.notes.duplicate():
			if ids.has(note.id):
				_app.chart.notes.erase(note)
		_app.finish_edit()
		_app.clear_selection()
	_rebuild_ghost()
	_sync_ghost_layer()
	notice.emit(
		("已剪切 %d 个音符；移动鼠标选点，Ctrl+V 粘贴，Ctrl+A 镜像粘贴。" if cut
		else "已复制 %d 个音符；移动鼠标选点，Ctrl+V 粘贴，Ctrl+A 镜像粘贴。") % copies.size(),
		"info"
	)


func paste_clipboard(mirror: bool = false) -> bool:
	if _app == null or _app.chart == null or not has_clipboard():
		notice.emit("剪贴板为空：先 Ctrl+C 复制或 Ctrl+X 剪切。", "warning")
		return false
	var chart: Chart = _app.chart
	var delta := _clipboard_mouse_beat - _clipboard_reference_beat
	var new_ids: Array[int] = []
	_app.begin_edit()
	for note in _clipboard_notes:
		var copy := Note.from_dict(note.to_dict())
		copy.id = chart.next_note_id()
		copy.beat = maxf(0.0, note.beat + delta)
		if copy.type in ["hold", "path"]:
			copy.end_beat = maxf(copy.beat + 0.25, note.end_beat + delta)
		if mirror:
			copy.mirror_u()
		chart.notes.append(copy)
		new_ids.append(copy.id)
	_app.finish_edit()
	_app.select_notes(new_ids)
	# A paste consumes the pending clipboard: drop the ghost preview and keep
	# the freshly pasted notes selected for immediate follow-up editing.
	cancel_clipboard(false)
	queue_redraw()
	notice.emit(("已镜像粘贴 %d 个音符。" if mirror else "已粘贴 %d 个音符。") % new_ids.size(), "info")
	return true


func mirror_selected_note() -> bool:
	if _app == null or _app.chart == null:
		return false
	var selected: Array[Note] = _app.get_selected_notes()
	if selected.size() != 1:
		return false
	var group: Array[Note] = _app.with_anchor_partners(selected)
	for item in group:
		if item.lock:
			notice.emit("音符已锁定，无法镜像。", "warning")
			return false
	_app.begin_edit()
	for item in group:
		item.mirror_u()
	_app.finish_edit()
	queue_redraw()
	notice.emit("已镜像 %d 个音符。" % group.size(), "info")
	return true


func cancel_clipboard(show_notice: bool = true) -> void:
	var had_clipboard := _clipboard_active
	_clipboard_active = false
	_clipboard_cut = false
	_clipboard_notes.clear()
	if _ghost_layer != null:
		_ghost_layer.ghost_notes.clear()
		_ghost_layer.visible = false
		_ghost_layer.queue_redraw()
	if show_notice and had_clipboard:
		notice.emit("已取消复制/剪切预览；已剪切的音符可用 Ctrl+Z 恢复。", "info")


func _current_mouse_beat() -> float:
	if _mouse_pos != Vector2.ZERO and _plot_rect().has_point(_mouse_pos):
		return _y_to_beat(_mouse_pos.y)
	if _app != null:
		return _app.playhead_beat
	return 0.0


func _rebuild_ghost() -> void:
	if _ghost_layer == null:
		return
	if not _clipboard_active:
		_ghost_layer.ghost_notes = []
		_ghost_layer.visible = false
		_ghost_layer.queue_redraw()
		return
	var delta := _clipboard_mouse_beat - _clipboard_reference_beat
	var ghosts: Array[Note] = []
	for note in _clipboard_notes:
		var copy := Note.from_dict(note.to_dict())
		copy.id = -1 - ghosts.size()
		copy.beat = maxf(0.0, note.beat + delta)
		if copy.type in ["hold", "path"]:
			copy.end_beat = maxf(copy.beat + 0.25, note.end_beat + delta)
		ghosts.append(copy)
	_ghost_layer.ghost_notes = ghosts
	_ghost_layer.visible = true
	_sync_ghost_layer()


func _sync_ghost_layer() -> void:
	if _ghost_layer == null:
		return
	_ghost_layer._app = _app
	_ghost_layer.scroll_beat = scroll_beat
	_ghost_layer.px_per_beat = px_per_beat
	_ghost_layer.flow_down = flow_down
	_ghost_layer.visible = _clipboard_active
	_ghost_layer.queue_redraw()
	_ghost_last_scroll = scroll_beat
	_ghost_last_px = px_per_beat
	_ghost_last_stretch = float(_app.vertical_stretch) if _app != null else 0.0
	_ghost_last_size = size


func _on_chart_changed() -> void:
	_sorted_dirty = true
	_refresh_waveform()
	queue_redraw()


func _on_chart_live_changed() -> void:
	queue_redraw()


func _on_playhead_changed(beat: float) -> void:
	var scrolled := false
	if follow_playhead:
		var visible := _visible_beats()
		if beat < scroll_beat - 0.1 or beat > scroll_beat + visible:
			scroll_beat = maxf(0.0, beat - visible * 0.25)
			scrolled = true
	if scrolled:
		queue_redraw()
	var now := Time.get_ticks_msec()
	if now - _last_playhead_redraw >= 16:
		_last_playhead_redraw = now
		if _overlay != null:
			_overlay.queue_redraw()


func _on_selection_changed() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_tool_changed(_tool: String) -> void:
	if _app != null and _app.chart != null:
		for item in _app.chart.notes:
			if item.type == "seek" and item.seek_pending:
				item.seek_pending = false
	if _pending_hold != null or _pending_path != null:
		_cancel_pending()
	else:
		_pending_path = null
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_snap_changed(division: int) -> void:
	snap_division = division
	queue_redraw()


func _on_flow_changed(down: bool) -> void:
	flow_down = down
	if _flow_button != null and _flow_button.button_pressed != down:
		_flow_button.set_pressed_no_signal(down)
	if _ghost_layer != null:
		_ghost_layer.flow_down = down
		_ghost_layer.queue_redraw()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _build_flow_button() -> void:
	_flow_button = Button.new()
	_flow_button.name = "FlowToggle"
	_flow_button.text = "从上往下"
	_flow_button.toggle_mode = true
	_flow_button.focus_mode = Control.FOCUS_NONE
	_flow_button.tooltip_text = "开启时新音符向下写入；关闭后整个写谱区上下翻转（时间向上流动）"
	_flow_button.add_theme_font_size_override("font_size", 10)
	_flow_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_flow_button.add_theme_color_override("font_pressed_color", UITheme.BG)
	_flow_button.add_theme_color_override("font_hover_color", UITheme.INK)
	_flow_button.add_theme_stylebox_override("normal", UITheme._box(UITheme.PANEL, UITheme.BORDER, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("hover", UITheme._box(UITheme.RAISED_HOVER, UITheme.BORDER_BRIGHT, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("pressed", UITheme._box(UITheme.ACCENT, UITheme.ACCENT, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("focus", UITheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 0))
	_flow_button.set_anchor(SIDE_LEFT, 1.0)
	_flow_button.set_anchor(SIDE_RIGHT, 1.0)
	_flow_button.set_anchor(SIDE_TOP, 0.0)
	_flow_button.set_anchor(SIDE_BOTTOM, 0.0)
	_flow_button.offset_left = -106.0
	_flow_button.offset_right = -8.0
	_flow_button.offset_top = TOP_MARGIN + 2.0
	_flow_button.offset_bottom = TOP_MARGIN + 22.0
	_flow_button.button_pressed = flow_down
	_flow_button.toggled.connect(_on_flow_toggled)
	add_child(_flow_button)


func _on_flow_toggled(pressed: bool) -> void:
	if _app != null:
		_app.set_time_flows_down(pressed)
		return
	flow_down = pressed
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _division_index_at(position: Vector2) -> int:
	for i in _division_rects.size():
		if _division_rects[i].has_point(position):
			return i
	return -1


func _refresh_waveform() -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart
	var path := chart.audio_path
	if path == _waveform_audio_path:
		return
	_waveform_audio_path = path
	_waveform_peaks.clear()
	_waveform_duration = 0.0
	_wave_key = ""
	if path.is_empty() or not path.to_lower().ends_with(".wav"):
		return
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		if _app.chart_path != "":
			resolved = ChartIO.resolve_path(_app.chart_path, path)
	var stream: AudioStream = null
	if resolved.get_extension().to_lower() == "wav":
		var absolute := resolved if resolved.is_absolute_path() else ProjectSettings.globalize_path(resolved)
		stream = AudioStreamWAV.load_from_file(absolute)
	else:
		stream = ChartIO.audio_stream_from_path(resolved)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			return
		var data := wav.data
		var channels := 2 if wav.stereo else 1
		var frame_bytes := 2 * channels
		var frames := data.size() / frame_bytes
		if frames <= 0:
			return
		var peak_count := 512
		for i in peak_count:
			var start := int(float(i) / peak_count * frames)
			var finish := int(float(i + 1) / peak_count * frames)
			finish = maxi(finish, start + 1)
			var peak := 0.0
			var step := maxi(1, (finish - start) / 32)
			for frame in range(start, mini(finish, frames), step):
				var offset := frame * frame_bytes
				var value := absf(float(data.decode_s16(offset)))
				peak = maxf(peak, value)
			_waveform_peaks.append(clampf(peak / 32768.0, 0.0, 1.0))
		_waveform_duration = wav.get_length()


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0E1015"))
	draw_rect(plot, Color("#11141B"))
	_division_rects.clear()
	_draw_waveform(plot)
	_draw_grid(plot)
	_draw_regions(plot)
	_draw_events(plot)
	_draw_notes(plot)
	_draw_legend(plot)


func _draw_waveform(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var strip := Rect2(plot.position.x - WAVE_WIDTH - 6.0, plot.position.y, WAVE_WIDTH, plot.size.y)
	draw_rect(strip, Color("#0A0C11"))
	draw_line(Vector2(strip.end.x, strip.position.y), Vector2(strip.end.x, strip.end.y), Color(1, 1, 1, 0.08), 1.0)
	if _waveform_peaks.is_empty() or _waveform_duration <= 0.0:
		draw_line(Vector2(strip.position.x, strip.get_center().y), Vector2(strip.end.x, strip.get_center().y), Color(1, 1, 1, 0.10), 1.0)
		draw_string(UITheme.mono_font(), Vector2(strip.position.x - 2, plot.position.y + 12), "WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.22))
		return
	var chart: Chart = _app.chart
	var timing_sig := "%.3f|%d" % [chart.offset_ms, chart.timing.points.size()]
	for point in chart.timing.points:
		timing_sig += "|%.4f" % point.bpm
	var key := "%s|%.4f|%.4f|%.1f|%.1f|%.1f|%d|%s" % [
		_waveform_audio_path, _waveform_duration, scroll_beat, px_per_beat,
		plot.position.y, plot.size.y, _waveform_peaks.size(), timing_sig,
	]
	if key != _wave_key:
		_wave_key = key
		_wave_right = PackedVector2Array()
		_wave_left = PackedVector2Array()
		var center_x := strip.position.x + strip.size.x * 0.5
		var half := strip.size.x * 0.5 - 2.0
		for y in range(int(plot.position.y), int(plot.end.y), 2):
			var beat := _y_to_beat(float(y))
			var chart_ms := chart.timing.beat_to_chart_ms(beat)
			var audio_ms := chart_ms - chart.offset_ms
			var fraction := audio_ms / 1000.0 / _waveform_duration
			if fraction < 0.0 or fraction > 1.0:
				continue
			var index := clampi(int(fraction * _waveform_peaks.size()), 0, _waveform_peaks.size() - 1)
			var peak := _waveform_peaks[index]
			_wave_right.append(Vector2(center_x + peak * half, y))
			_wave_left.append(Vector2(center_x - peak * half, y))
	if _wave_right.size() > 1:
		draw_polyline(_wave_right, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.42), 1.0, true)
	if _wave_left.size() > 1:
		draw_polyline(_wave_left, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.26), 1.0, true)


func _draw_grid(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var font := UITheme.mono_font()
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	# Special-angle reference lines: every 30°, with the 90° lines emphasised.
	for i in 13:
		var x := _u_to_x(float(i) / 12.0)
		var major := i % 3 == 0
		var color := Color(1, 1, 1, 0.16 if major else 0.055)
		if i == 0 or i == 12:
			_draw_dashed_vertical(x, plot.position.y, plot.end.y, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.25))
		else:
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), color, 1.0)
		if major:
			var label := "%d°" % (i * 30)
			draw_string(font, Vector2(x - 12, plot.position.y - 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.52))
	# Beat / bar lines with continuous beat numbers. Bar lines stay thicker but
	# are no longer labelled "bar N": the left column counts beats, like the
	# Malody editor, so a note's row can be read as 1, 2, 3, 4, 5 ...
	var first_beat := maxi(0, floori(scroll_beat) - 1)
	var last_beat := ceili(scroll_beat + _visible_beats()) + 1
	for beat in range(first_beat, last_beat + 1):
		var y := _beat_to_y(float(beat))
		if y < plot.position.y - 2.0 or y > plot.end.y + 2.0:
			continue
		var bpb := chart.timing.beats_per_bar_at(float(beat))
		var is_bar := beat % bpb == 0
		var beat_color := Color(1, 1, 1, 0.17 if is_bar else 0.075)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), beat_color, 1.5 if is_bar else 1.0)
		draw_string(font, Vector2(1, y + 3.5), str(beat + 1), HORIZONTAL_ALIGNMENT_RIGHT, 22, 10, Color(1, 1, 1, 0.62 if is_bar else 0.38))
	_draw_beat_subdivisions(plot)
	_draw_vertical_lines(plot)
	for point in chart.timing.points:
		if point.beat < scroll_beat or point.beat > scroll_beat + _visible_beats():
			continue
		var y := _beat_to_y(point.beat)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1.5)
		draw_string(font, Vector2(plot.position.x + 6, y + 12), "BPM %.1f" % point.bpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.GOLD)


func _draw_divisions(plot: Rect2) -> void:
	var font := UITheme.mono_font()
	var left := plot.end.x + DIVISION_MARGIN
	var total := float(GridDivisions.ITEMS.size()) * (DIVISION_ITEM_HEIGHT + DIVISION_GAP) - DIVISION_GAP
	var top := clampf(plot.get_center().y - total * 0.5, plot.position.y + 18.0, maxf(plot.position.y + 18.0, plot.end.y - total - 4.0))
	_division_rects.clear()
	draw_line(Vector2(plot.end.x + 3.0, plot.position.y), Vector2(plot.end.x + 3.0, plot.end.y), Color(1, 1, 1, 0.06), 1.0)
	draw_string(font, Vector2(left, top - 7.0), "分音", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
	for i in GridDivisions.ITEMS.size():
		var division: int = GridDivisions.ITEMS[i]
		var rect := Rect2(Vector2(left, top + float(i) * (DIVISION_ITEM_HEIGHT + DIVISION_GAP)), Vector2(DIVISION_WIDTH, DIVISION_ITEM_HEIGHT))
		_division_rects.append(rect)
		var active := division == snap_division
		var hovered := i == _division_hover
		if active:
			draw_rect(rect, UITheme.ACCENT)
		elif hovered:
			draw_rect(rect, Color(1, 1, 1, 0.10))
		draw_rect(rect, UITheme.ACCENT if active else Color(1, 1, 1, 0.14), false, 1.0)
		draw_string(font, Vector2(rect.position.x, rect.position.y + 15.0), GridDivisions.LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, DIVISION_WIDTH, 10, UITheme.BG if active else Color(1, 1, 1, 0.55))


func _draw_beat_subdivisions(plot: Rect2) -> void:
	if _app == null:
		return
	var offsets := TimingMap.beat_subdivision_offsets(int(_app.beat_subdivisions))
	if offsets.is_empty():
		return
	var first_beat := floori(scroll_beat)
	var last_beat := ceili(scroll_beat + _visible_beats() + 1.0)
	var points := PackedVector2Array()
	for beat in range(first_beat, last_beat + 1):
		for offset in offsets:
			var y := _beat_to_y(float(beat) + offset)
			if y < plot.position.y - 0.5 or y > plot.end.y + 0.5:
				continue
			points.append(Vector2(plot.position.x, y))
			points.append(Vector2(plot.end.x, y))
	if points.size() >= 2:
		draw_multiline(points, Color(1, 1, 1, 0.035), 1.0)


func _draw_vertical_lines(plot: Rect2) -> void:
	if _app == null:
		return
	var offsets := TimingMap.vertical_line_offsets(int(_app.vertical_lines))
	if offsets.is_empty():
		return
	var color := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.09)
	for u in offsets:
		var x := _u_to_x(u)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), color, 1.0)


func _draw_dashed_vertical(x: float, y0: float, y1: float, color: Color) -> void:
	var y := y0
	while y < y1:
		draw_line(Vector2(x, y), Vector2(x, minf(y + 5.0, y1)), color, 1.0)
		y += 10.0


func _draw_regions(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for region in chart.regions:
		var color := UITheme.RED if region.kind == "limit" else UITheme.GOLD
		var y0 := _beat_to_y(region.start_beat)
		var y1 := _beat_to_y(region.end_beat)
		var top := minf(y0, y1)
		var height := maxf(2.0, absf(y1 - y0))
		if top + height < plot.position.y or top > plot.end.y:
			continue
		for interval in _u_intervals(region.angle, region.width):
			var x0 := _u_to_x(interval.x)
			var x1 := _u_to_x(interval.y)
			var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), height))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.16))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
			draw_string(UITheme.mono_font(), Vector2(x0 + 4, top + 12), "LIMIT %d" % region.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
		if _is_region_selected(region.id):
			draw_rect(Rect2(Vector2(_u_to_x(0.0), top), Vector2(plot.size.x, height)), Color(1, 1, 1, 0.35), false, 1.0)


func _draw_events(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for event in chart.events:
		var y0 := _beat_to_y(event.start_beat)
		var y1 := _beat_to_y(event.end_beat + event.restore_duration)
		var top := minf(y0, y1)
		var height := maxf(2.0, absf(y1 - y0))
		if top + height < plot.position.y or top > plot.end.y:
			continue
		var x0 := _u_to_x(event.target_u0)
		var x1 := _u_to_x(event.target_u1)
		var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), height))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.07))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.30), false, 1.0)
		if height > 14.0:
			draw_string(UITheme.mono_font(), Vector2(x0 + 3, top + 10), "%s → %s" % [event.from_shape, event.to_shape], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.7))


func _draw_notes(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	var first_beat := scroll_beat - 2.0
	var last_beat := scroll_beat + _visible_beats() + 2.0
	if _drag_mode != "" or _drag_width_note != null:
		# 拖拽时音符会临时改变 beat，直接全量绘制，避免二分索引顺序失效。
		for note in chart.notes:
			var note_end := note.end_beat if note.type in ["hold", "path"] else note.beat
			if note.beat <= last_beat and note_end >= first_beat:
				_draw_note(note, plot)
	else:
		if _sorted_dirty or _sorted_chart != chart or _sorted_count != chart.notes.size():
			_sorted_chart = chart
			_sorted_count = chart.notes.size()
			_sorted_notes = chart.notes.duplicate()
			_sorted_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
			_sorted_max_duration = 0.0
			for note in _sorted_notes:
				if note.type in ["hold", "path"]:
					_sorted_max_duration = maxf(_sorted_max_duration, note.end_beat - note.beat)
			_sorted_dirty = false
		var search_start := first_beat - _sorted_max_duration
		var low := 0
		var high := _sorted_notes.size()
		while low < high:
			var mid := (low + high) / 2
			if _sorted_notes[mid].beat < search_start:
				low = mid + 1
			else:
				high = mid
		for i in range(low, _sorted_notes.size()):
			var note := _sorted_notes[i]
			if note.beat > last_beat:
				break
			var note_end := note.end_beat if note.type in ["hold", "path"] else note.beat
			if note_end < first_beat:
				continue
			_draw_note(note, plot)
	if _pending_path != null:
		var head := Vector2(_u_to_x(_pending_path.angle / 360.0), _beat_to_y(_pending_path.beat))
		var tail := Vector2(_u_to_x(_hover_u), _beat_to_y(_hover_beat))
		draw_dashed_line(head, tail, UITheme.CYAN, 1.5, 6.0)


func _draw_note(note: Note, plot: Rect2) -> void:
	match note.type:
		"tap":
			_draw_tap(note)
		"hold":
			_draw_hold(note)
		"path":
			_draw_path(note)
		"seek":
			_draw_seek(note)
		"anchor":
			_draw_anchor(note)
		"bell":
			_draw_bell(note)


func _draw_tap(note: Note) -> void:
	var y := _beat_to_y(note.beat)
	var selected := _is_note_selected(note.id)
	for interval in _u_intervals(note.angle, note.arc_width()):
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		if x1 - x0 < 1.0:
			continue
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.92), 10.0, true)
		draw_circle(Vector2(x0, y), 5.0, UITheme.CORAL)
		draw_circle(Vector2(x1, y), 5.0, UITheme.CORAL)
		var tick_x := x0 + 5.0
		while tick_x < x1 - 4.0:
			draw_line(Vector2(tick_x, y - 4.0), Vector2(tick_x, y + 4.0), Color(0, 0, 0, 0.24), 1.0)
			tick_x += 7.0
		if selected:
			draw_line(Vector2(x0, y - 7.0), Vector2(x1, y - 7.0), UITheme.INK, 1.0)
			draw_line(Vector2(x0, y + 7.0), Vector2(x1, y + 7.0), UITheme.INK, 1.0)
	var center_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	draw_line(Vector2(center_x, y - 8.0), Vector2(center_x, y + 8.0), UITheme.INK, 2.0)
	draw_circle(Vector2(center_x, y), 2.2, UITheme.INK)
	if _show_type_label(note):
		_draw_type_label("TAP", Vector2(center_x + 8.0, y + 12.0), UITheme.CORAL)


func _draw_hold(note: Note) -> void:
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.end_beat)
	var x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	var selected := _is_note_selected(note.id)
	var color := UITheme.AMBER
	# 弯长条已移除：没有体节点就按直 Hold 画实心矩形。
	var straight := note.visual_pts.is_empty()
	if straight:
		# 制谱器里直长条画成实心矩形：宽 = 判定弧宽，长 = 拍长。
		# 弧宽跨过 0°/360° 接缝时拆成两段画（以前“x1<x0 就铺满整行”会让压接缝的 Hold 变成满屏长条）。
		var top := minf(y0, y1)
		var height := maxf(2.0, absf(y1 - y0))
		for span in _u_intervals(note.angle, note.arc_width()):
			var x0 := _u_to_x(span.x)
			var x1 := _u_to_x(span.y)
			if x1 - x0 < 1.0:
				continue
			var rect := Rect2(Vector2(x0, top), Vector2(x1 - x0, height))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.32))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.95), false, 1.5)
	else:
		var body := PackedVector2Array([Vector2(x, y0)])
		for point in note.visual_pts:
			body.append(Vector2(
				_u_to_x(fposmod(note.angle + float(point.get("da", 0.0)), 360.0) / 360.0),
				_beat_to_y(note.beat + float(point.get("db", 0.0)))
			))
		body.append(Vector2(x, y1))
		if body.size() > 1:
			draw_polyline(body, Color(color.r, color.g, color.b, 0.28), 12.0, true)
			draw_polyline(body, color, 2.0, true)
		for i in range(1, body.size() - 1):
			draw_circle(body[i], 3.0, UITheme.MINT)
		_draw_width_band(note.angle, note.arc_width(), y0, color)
	_draw_hexagon(Vector2(x, y0), 9.0 if selected else 8.0, color)
	_draw_ring(Vector2(x, y1), 6.0, color)
	if _show_type_label(note):
		_draw_type_label("HOLD", Vector2(x + 11.0, y0 + 12.0), color)


func _path_screen_point(note: Note, local: float) -> Vector2:
	## Follow the same local geometry as the 3D Path (trace points included)
	## and project it to the u×time canvas. This keeps a negative tail radius
	## connected to the body instead of ending at the author-facing tail angle.
	var design := note.path_local_at(local)
	var angle := rad_to_deg(atan2(design.y, design.x))
	return Vector2(
		_u_to_x(fposmod(angle, 360.0) / 360.0),
		_beat_to_y(note.beat + local)
	)


func _draw_path(note: Note) -> void:
	var total := maxf(0.001, note.duration())
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.beat + total)
	var head_local := note.path_local_at(0.0)
	var head_draw_angle := note.angle
	if head_local.length() > 0.0001:
		head_draw_angle = rad_to_deg(atan2(head_local.y, head_local.x))
	var x0 := _path_screen_point(note, 0.0).x
	var tail_local := note.path_tail_local()
	var tail_draw_angle := note.tail_angle
	if tail_local.length() > 0.0001:
		tail_draw_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
	var x1 := _u_to_x(fposmod(tail_draw_angle, 360.0) / 360.0)
	var selected := _is_note_selected(note.id)
	var tail_color := PATH_CHAIN_BLUE if note.path_next_id >= 0 else UITheme.GOLD
	var head_color := PATH_CHAIN_BLUE if note.path_part > 0 else UITheme.CORAL
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in 41:
		var local := total * float(i) / 40.0
		if note.erased_at(local):
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			continue
		run.append(_path_screen_point(note, local))
	if run.size() > 1:
		runs.append(run)
	for piece in runs:
		draw_polyline(piece, Color(0.52, 0.56, 0.64, 0.28), 14.0, true)
		var dashes := PackedVector2Array()
		for i in piece.size() - 1:
			_append_dashes(piece[i], piece[i + 1], 5.0, dashes)
		if dashes.size() > 1:
			draw_multiline(dashes, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.90), 2.0)
		for fraction in [0.33, 0.66]:
			var sample := _polyline_sample(piece, fraction)
			_draw_arrowhead(sample["point"], sample["direction"], UITheme.CYAN)
	for point in note.visual_pts:
			var local := float(point.get("db", 0.0))
			if note.erased_at(local):
				continue
			draw_circle(_path_screen_point(note, local), 2.5, UITheme.CYAN)
	_draw_width_band(head_draw_angle, note.width, y0, UITheme.CYAN)
	_draw_width_band(tail_draw_angle, note.tail_width, y1, tail_color)
	_draw_star(Vector2(x0, y0), 9.0 if selected else 8.0, head_color)
	_draw_donut(Vector2(x1, y1), 7.0, tail_color)
	if _show_type_label(note):
		_draw_type_label("PATH", Vector2(x0 + 11.0, y0 + 12.0), UITheme.CYAN)


func _append_dashes(a: Vector2, b: Vector2, dash: float, out: PackedVector2Array) -> void:
	var length := a.distance_to(b)
	if length <= 0.01:
		return
	var direction := (b - a) / length
	var cursor := 0.0
	while cursor < length:
		var end := minf(cursor + dash, length)
		out.append(a + direction * cursor)
		out.append(a + direction * end)
		cursor += dash * 2.0


func _draw_donut(point: Vector2, radius: float, color: Color) -> void:
	draw_circle(point, radius, color)
	draw_circle(point, radius * 0.48, UITheme.BG)


func _draw_seek(note: Note) -> void:
	var y := _beat_to_y(note.beat)
	var selected := _is_note_selected(note.id)
	var x0 := _u_to_x(0.0)
	var x1 := _u_to_x(1.0)
	var color := UITheme.INK
	if not note.seek_pending:
		color = UITheme.SEEK_OUT if note.seek_orien == 0 else UITheme.SEEK_IN
	var width := 3.0 if selected else 1.6
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(color.r, color.g, color.b, 0.95), width, true)
	if selected:
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.25), width + 2.0, true)
	if note.seek_pending:
		return
	# 外在上、里在下；尖端指向滚轮方向（外 = 上滑）。
	var direction := -1.0 if note.seek_orien == 0 else 1.0
	var count := 12
	for i in range(1, count):
		var x := lerpf(x0, x1, float(i) / float(count))
		var tip := Vector2(x, y + 4.5 * direction)
		draw_colored_polygon(PackedVector2Array([
			tip,
			Vector2(x - 2.5, y + 1.2 * direction),
			Vector2(x + 2.5, y + 1.2 * direction),
		]), color)
	if _show_type_label(note):
		_draw_type_label("SEEK OUT" if note.seek_orien == 0 else "SEEK IN", Vector2(x0 + 6.0, y - 6.0), color)


func _draw_anchor(note: Note) -> void:
	var p := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat))
	# 双押线：只由 id 较小的一颗画一次，连到同拍反向的伙伴。
	var chart: Chart = _app.chart if _app != null else null
	if chart != null:
		var partner := chart.anchor_partner(note)
		if partner != null and note.id < partner.id:
			var q := Vector2(_u_to_x(fposmod(partner.angle, 360.0) / 360.0), _beat_to_y(partner.beat))
			draw_line(p, q, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.55), 1.2, true)
	var selected := _is_note_selected(note.id)
	_draw_diamond(p, 8.0 if selected else 6.5, UITheme.VIOLET)
	draw_line(p + Vector2(0, -2), p + Vector2(0, 4), UITheme.VIOLET, 1.2, true)
	draw_line(p + Vector2(0, 4), p + Vector2(4, 6), UITheme.VIOLET, 1.2, true)
	if not note.pair_id.is_empty():
		draw_string(UITheme.mono_font(), p + Vector2(9, 12), "A %s" % note.pair_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.85))
	if _show_type_label(note):
		_draw_type_label("ANCHOR", p + Vector2(9, -9), UITheme.VIOLET)


func _draw_bell(note: Note) -> void:
	var p := Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat))
	var selected := _is_note_selected(note.id)
	# 时间轴里的金键 = 游戏内那段弧带的俯视图：白壳 + 金色核心 + 圆头。
	var span := clampf(12.0 + note.width * 0.35, 14.0, 64.0)
	var half := 7.0 if selected else 6.0
	var tip := 4.5
	if selected:
		draw_circle(p, span * 0.5 + 9.0, Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.16))
	_bell_bar(p, span + 4.0, half + 2.0, Color(0, 0, 0, 0.5))
	_bell_bar(p, span, half, Color(1, 1, 1, 0.94))
	_bell_bar(p, span, half * 0.62, UITheme.KEY_YELLOW)
	if _show_type_label(note):
		_draw_type_label("BELL", p + Vector2(span * 0.5 + 10.0, 4.0), UITheme.KEY_YELLOW)


func _bell_bar(p: Vector2, span: float, half: float, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-span * 0.5, -half), Vector2(span, half * 2.0)), color)
	draw_circle(p + Vector2(-span * 0.5, 0.0), half, color)
	draw_circle(p + Vector2(span * 0.5, 0.0), half, color)


func _show_type_label(note: Note) -> bool:
	return _app != null and (_app.debug_overlay or _is_note_selected(note.id))


func _draw_type_label(text: String, pos: Vector2, color: Color) -> void:
	draw_string(UITheme.mono_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(color.r, color.g, color.b, 0.9))


func _draw_star(p: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var radius := r if i % 2 == 0 else r * 0.45
		points.append(p + Vector2(cos(angle), sin(angle)) * radius)
	points.append(points[0])
	draw_polyline(points, color, 2.0, true)
	draw_circle(p, 1.8, color)


func _draw_hexagon(p: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 6:
		var angle := -PI * 0.5 + TAU * float(i) / 6.0
		points.append(p + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, UITheme.BG, 1.5, true)
	draw_circle(p, r * 0.35, UITheme.BG)


func _draw_ring(p: Vector2, r: float, color: Color) -> void:
	draw_arc(p, r, 0.0, TAU, 28, color, 2.0, true)
	draw_circle(p, 1.6, color)


func _draw_arrowhead(p: Vector2, direction: Vector2, color: Color) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		p + dir * 6.0,
		p - dir * 4.0 + normal * 4.0,
		p - dir * 4.0 - normal * 4.0,
	])
	draw_colored_polygon(points, color)


func _polyline_sample(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := clampf(fraction, 0.0, 1.0) * total
	var cursor := 0.0
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if cursor + segment >= target and segment > 0.01:
			var t := (target - cursor) / segment
			return {"point": points[i].lerp(points[i + 1], t), "direction": points[i + 1] - points[i]}
		cursor += segment
	return {"point": points[-1], "direction": points[-1] - points[-2] if points.size() > 1 else Vector2.ZERO}


func _draw_width_band(angle: float, width: float, y: float, color: Color) -> void:
	for interval in _u_intervals(angle, width):
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(color.r, color.g, color.b, 0.40), 6.0, true)


func _draw_diamond(p: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
	draw_polyline(points, color, 2.0, true)
	draw_circle(p, 2.0, color)


func _u_intervals(angle: float, width: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for interval in JudgeMath.interval(angle, width):
		result.append(Vector2(interval.x / 360.0, interval.y / 360.0))
	return result


func _draw_legend(plot: Rect2) -> void:
	if _app == null:
		return
	var y := plot.end.y + 8.0
	var entries := [
		{"type": "tap", "label": "Tap", "color": UITheme.CORAL},
		{"type": "hold", "label": "Hold", "color": UITheme.AMBER},
		{"type": "path", "label": "Path", "color": UITheme.CYAN},
		{"type": "seek", "label": "Seek", "color": UITheme.SEEK_IN},
		{"type": "anchor", "label": "Anchor", "color": UITheme.VIOLET},
		{"type": "bell", "label": "Bell", "color": UITheme.GOLD},
		{"type": "limit", "label": "Limit", "color": UITheme.RED},
	]
	var x := plot.position.x + 4.0
	for entry in entries:
		var color: Color = entry["color"]
		var p := Vector2(x, y)
		match String(entry["type"]):
			"tap":
				draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), color, 4.0, true)
				draw_line(p + Vector2(0, -4), p + Vector2(0, 4), UITheme.INK, 1.0)
			"hold":
				_draw_hexagon(p, 4.0, color)
			"path":
				_draw_star(p, 5.0, color)
			"seek":
				draw_arc(p, 4.0, 0.0, TAU, 18, color, 1.6, true)
				draw_arc(p, 2.2, 0.0, TAU, 14, Color(color.r, color.g, color.b, 0.6), 1.0, true)
			"anchor":
				_draw_diamond(p, 4.0, color)
			"bell":
				draw_arc(p, 4.0, 0.0, TAU, 16, color, 1.5, true)
				draw_circle(p, 1.5, color)
			"limit":
				draw_arc(p, 4.0, -PI * 0.8, PI * 0.2, 12, color, 3.0, true)
		draw_string(UITheme.mono_font(), Vector2(x + 9, y + 4), String(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.48))
		x += 88.0


func _is_note_selected(note_id: int) -> bool:
	return _app != null and _app.selected_notes.has(note_id)


func _is_region_selected(region_id: int) -> bool:
	return _app != null and _app.selected_region_id == region_id


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		_hover_u = _x_to_u(event.position.x)
		_hover_beat = _y_to_beat(event.position.y)
		var hover_index := _division_index_at(event.position)
		if hover_index != _division_hover:
			_division_hover = hover_index
			queue_redraw()
		hover_changed.emit(_hover_u, _hover_beat)
		if _clipboard_active:
			_clipboard_mouse_beat = _hover_beat
			_rebuild_ghost()
		if _pending_hold != null:
			var end_beat := _snap_beat_to_subdivision(_y_to_beat(event.position.y), event.alt_pressed)
			_pending_hold.end_beat = maxf(_pending_hold.beat, end_beat)
			_app.touch_chart()
		if _drag_mode == "note":
			_drag_notes_update(event.position, event)
		elif _drag_mode == "width":
			_drag_width_update(event.position)
		elif _drag_mode == "limit":
			_drag_red_update(event.position, event)
		elif _drag_mode == "hold_end":
			_drag_hold_update(event.position, event)
		elif _drag_mode == "marquee":
			_update_marquee(event.position)
		elif _drag_mode == "scrub":
			_app.seek(_app.snap_beat(_y_to_beat(event.position.y), event.alt_pressed))
		elif _drag_mode == "right_delete":
			# 动过就当成框选，避免右键拖选时误删。
			if event.position.distance_to(_drag_start) > 5.0:
				_drag_mode = ""
				_right_hit = {}
				_begin_marquee(_drag_start)
		if _drag_mode != "" or _pending_path != null or _pending_hold != null:
			queue_redraw()
		if _overlay != null:
			_overlay.queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton:
		_mouse_pos = event.position
		_hover_u = _x_to_u(event.position.x)
		_hover_beat = _y_to_beat(event.position.y)
		if _clipboard_active:
			_clipboard_mouse_beat = _hover_beat
			_rebuild_ghost()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_handle_wheel(event)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键单击音符 = 删除；右键按住拖动 = 框选（沿用旧操作）。
			if event.pressed and _drag_mode == "" and _pending_path == null:
				var tail_note := _path_tail_hit(event.position)
				if tail_note != null:
					# Right-clicking a Path tail is the "new part" gesture and
					# must not start a marquee or delete the Path.
					if tail_note.path_next_id < 0:
						_begin_path_part(tail_note)
					else:
						_app.select_note(tail_note.path_next_id)
					accept_event()
					return
				var hit := _hit_test(event.position)
				if hit.is_empty():
					_begin_marquee(event.position)
				else:
					_drag_mode = "right_delete"
					_drag_start = event.position
					_right_hit = hit
			elif not event.pressed and _drag_mode == "right_delete":
				_delete_hit(_right_hit)
				_drag_mode = ""
				_right_hit = {}
				queue_redraw()
				if _overlay != null:
					_overlay.queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Right-click stores the start time; the following left click sets
			# the end time and completes the marquee.
			if _drag_mode == "marquee":
				if event.pressed:
					_update_marquee(event.position)
					_finish_marquee()
					_drag_mode = ""
					_marquee = Rect2()
					queue_redraw()
					if _overlay != null:
						_overlay.queue_redraw()
				accept_event()
				return
			if event.pressed:
				var division_index := _division_index_at(event.position)
				if division_index >= 0:
					if _app != null:
						_app.set_snap_division(GridDivisions.ITEMS[division_index])
					accept_event()
					return
				grab_focus()
				_on_left_press(event)
			else:
				_on_left_release(event)
			accept_event()
			return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selection()
			accept_event()
		elif event.keycode == KEY_A and event.ctrl_pressed:
			if has_clipboard():
				paste_clipboard(true)
			else:
				_select_visible()
			accept_event()
		elif event.keycode == KEY_ESCAPE:
			_cancel_pending()
			if _app != null:
				_app.set_tool("select")
			if has_clipboard():
				cancel_clipboard()
			accept_event()


func _handle_wheel(event: InputEventMouseButton) -> void:
	if event.ctrl_pressed:
		# Ctrl+wheel edits vertical stretch (clamped by App); it no longer zooms.
		var step := 0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
		if _app != null:
			_app.set_vertical_stretch(_app.vertical_stretch + step)
	else:
		var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		scroll_beat = maxf(0.0, scroll_beat + direction * 3.0)
	if _drag_mode == "marquee":
		# Re-anchor the marquee's start screen point after scrolling/stretching;
		# its stored start beat is unchanged.
		_update_marquee(event.position)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _snap_beat_to_subdivision(raw_beat: float, bypass: bool = false) -> float:
	if bypass or _app == null:
		return raw_beat
	return TimingMap.nearest_beat_subdivision(raw_beat, int(_app.beat_subdivisions))


func _snap_beat_u(raw_beat: float, raw_u: float, bypass: bool) -> Vector2:
	## Always pull the note to the nearest intersection of a configured 小节线
	## and a configured 竖线. Both axes move together, so changing either
	## input immediately affects new placements and drag-release snapping.
	if bypass or _app == null:
		return Vector2(raw_beat, raw_u)
	var beat := _snap_beat_to_subdivision(raw_beat, false)
	var lines := mini(int(_app.vertical_lines), TimingMap.MAX_VERTICAL_LINES)
	if lines <= 0:
		return Vector2(beat, raw_u)
	var u := TimingMap.nearest_vertical_line_u(raw_u, lines)
	return Vector2(beat, u)


func _snap_note_placement(screen: Vector2, bypass: bool) -> Vector2:
	return _snap_beat_u(_y_to_beat(screen.y), _x_to_u(screen.x), bypass)


func _snap_dragged_notes(bypass: bool) -> void:
	## Re-apply the grid magnet when the mouse is released. Every dragged note
	## is checked independently, so batch drags keep each note on its nearest
	## line instead of relying on the mouse-up cursor position alone.
	if _app == null or bypass:
		return
	for item in _drag_notes:
		var note: Note = item["note"]
		if note.lock:
			continue
		var raw_u := fposmod(note.angle, 360.0) / 360.0
		var snapped := _snap_beat_u(note.beat, raw_u, false)
		var beat_delta := snapped.x - note.beat
		var angle_delta := snapped.y * 360.0 - note.angle
		if absf(beat_delta) <= 0.000001 and absf(angle_delta) <= 0.001:
			continue
		note.beat = snapped.x
		if note.type in ["hold", "path"]:
			note.end_beat = maxf(note.beat + 0.25, note.end_beat + beat_delta)
		if note.type == "bell":
			note.angle = fposmod(snapped.y * 360.0, 360.0)
			note.center_u = snapped.y
		elif note.type != "seek":
			note.angle = fposmod(note.angle + angle_delta, 360.0)
			if note.type == "path":
				note.tail_angle = fposmod(note.tail_angle + angle_delta, 360.0)
	_app.touch_chart()


func _on_left_press(event: InputEventMouseButton) -> void:
	if _app == null:
		return
	var plot := _plot_rect()
	if event.position.x > plot.end.x + 1.0:
		return
	var beat: float = _app.snap_beat(_y_to_beat(event.position.y), event.alt_pressed)
	# 顶部标尺那一行没有对应的拍，按到它就算了视口最上面那一拍，免得跳到奇怪的位置。
	beat = maxf(beat, scroll_beat)
	var u := _x_to_u(event.position.x)
	if event.position.x < plot.position.x - 4.0 or event.position.y < plot.position.y:
		# 左侧刻度栏和顶部标尺：按下去就跳转，并继续跟着拖动走 scrub。
		if event.shift_pressed and not _app.selected_notes.is_empty():
			_app.begin_edit()
			for note in _app.get_selected_notes():
				note.beat = beat
				if note.type in ["hold", "path"]:
					note.end_beat = maxf(note.end_beat, note.beat + 0.25)
			_app.finish_edit()
		else:
			_drag_mode = "scrub"
			_app.seek(beat)
		return
	# A pending hold consumes the next left click as its end time, before the
	# overlap guard can select another note.
	if _pending_hold != null:
		var end_beat := _snap_beat_to_subdivision(_y_to_beat(event.position.y), event.alt_pressed)
		_finish_pending_hold(end_beat)
		return
	# Ctrl is a selection modifier across all tools: toggle the clicked note
	# and suppress every placement action while it is held. A pending Path is
	# exempt because its second click is the tail-placement step.
	if _pending_path == null and event.ctrl_pressed:
		var ctrl_hit := _hit_test(event.position)
		if String(ctrl_hit.get("kind", "")) == "note":
			_app.toggle_note_selection(int(ctrl_hit["id"]))
		return
	# When a note tool is active, clicking an existing note selects it instead
	# of stacking a new note on top.
	if _pending_path == null and _app.tool in NOTE_TOOLS:
		var hit := _hit_test(event.position)
		if String(hit.get("kind", "")) == "note":
			_app.select_note(int(hit["id"]), event.shift_pressed)
			return
	if _app.tool in NOTE_TOOLS:
		var placement := _snap_note_placement(event.position, event.alt_pressed)
		beat = placement.x
		u = placement.y
	match _app.tool:
		"select":
			_select_press(event)
		"tap", "anchor", "bell":
			_create_simple(_app.tool, beat, u)
		"hold":
			_create_hold(beat, u)
		"path":
			_place_path(beat, u)
		"seek":
			_create_seek_at(beat)
		"limit":
			_begin_red(beat, u)
		"boundary":
			notice.emit("边界形状在左侧预览中拖拽控制点；双击分段可拆分。", "info")
		"event":
			_create_event_at(beat, u)


func _on_left_release(event: InputEventMouseButton) -> void:
	if _app == null:
		return
	if _drag_mode == "note":
		_snap_dragged_notes(event.alt_pressed)
	if _drag_mode in ["note", "width", "limit", "hold_end"]:
		_app.finish_edit()
	if _drag_mode == "marquee":
		_finish_marquee()
		_marquee = Rect2()
	_drag_mode = ""
	_drag_notes.clear()
	_drag_region = null
	_drag_width_note = null
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _begin_marquee(position: Vector2) -> void:
	if _app == null:
		return
	grab_focus()
	_drag_mode = "marquee"
	_drag_start = position
	_marquee_start_beat = _y_to_beat(position.y)
	_marquee_start_u = _x_to_u(position.x)
	_marquee_end_beat = _marquee_start_beat
	_marquee_end_u = _marquee_start_u
	_marquee = Rect2(position, Vector2.ZERO)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _update_marquee(current: Vector2) -> void:
	_marquee_end_beat = _y_to_beat(current.y)
	_marquee_end_u = _x_to_u(current.x)
	# The start is anchored to its beat, not to a screen pixel: scrolling or
	# stretching between the right-click and the left-click keeps it fixed.
	var start := Vector2(_u_to_x(_marquee_start_u), _beat_to_y(_marquee_start_beat))
	_marquee = Rect2(start, current - start).abs()


func _select_press(event: InputEventMouseButton) -> void:
	var hit := _hit_test(event.position)
	if hit.is_empty():
		if event.ctrl_pressed:
			return
		if event.double_click:
			_app.seek(_app.snap_beat(_y_to_beat(event.position.y)))
			return
		_app.clear_selection()
		return
	match hit["kind"]:
		"note":
			var note_id := int(hit["id"])
			if event.ctrl_pressed:
				_app.toggle_note_selection(note_id)
				return
			_app.select_note(note_id, event.shift_pressed)
			if hit.get("part", "") == "width":
				_begin_width_drag(note_id, event.position)
			else:
				_begin_note_drag(event.position)
		"region":
			_app.select_region(int(hit["id"]))
		"event":
			_app.select_event(String(hit["id"]))


func _hit_test(pos: Vector2) -> Dictionary:
	var chart: Chart = _app.chart
	if chart == null:
		return {}
	var best := {}
	var best_distance := 12.0
	for note in chart.notes:
		var positions := _note_positions(note)
		for item in positions:
			var distance: float = item["point"].distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = {"kind": "note", "id": note.id, "part": item["part"]}
		if note.type in ["tap", "hold"]:
			var edge := _width_edge_hit(note, pos)
			if not edge.is_empty():
				return edge
			var note_y := _beat_to_y(note.beat)
			if absf(pos.y - note_y) <= 7.0 and JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, note.angle, note.arc_width()):
				return {"kind": "note", "id": note.id, "part": "body"}
		if note.type == "path":
			# The whole drawn Path is selectable, not just its head/tail or
			# the column at the start angle.
			if _path_body_hit(note, pos):
				return {"kind": "note", "id": note.id, "part": "body"}
		if note.type == "seek":
			if absf(pos.y - _beat_to_y(note.beat)) <= 8.0:
				return {"kind": "note", "id": note.id, "part": "body"}
		if note.type == "hold":
			var y0 := _beat_to_y(note.beat)
			var y1 := _beat_to_y(note.end_beat)
			if pos.y >= minf(y0, y1) - 4 and pos.y <= maxf(y0, y1) + 4:
				var body_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
				if absf(pos.x - body_x) < 8.0:
					return {"kind": "note", "id": note.id, "part": "body"}
	for region in chart.regions:
		var y0 := _beat_to_y(region.start_beat)
		var y1 := _beat_to_y(region.end_beat)
		if pos.y < minf(y0, y1) or pos.y > maxf(y0, y1):
			continue
		if JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, region.angle, region.width):
			return {"kind": "region", "id": region.id}
	for event in chart.events:
		var y0 := _beat_to_y(event.start_beat)
		var y1 := _beat_to_y(event.end_beat)
		if pos.y < minf(y0, y1) or pos.y > maxf(y0, y1):
			continue
		var u := _x_to_u(pos.x)
		if u >= event.target_u0 and u <= event.target_u1:
			return {"kind": "event", "id": event.id}
	return best


func _path_body_hit(note: Note, pos: Vector2) -> bool:
	var total := maxf(0.001, note.duration())
	var run: Array[Vector2] = []
	for i in 41:
		var local := total * float(i) / 40.0
		if note.erased_at(local):
			if _path_run_hit(run, pos):
				return true
			run = []
			continue
		run.append(_path_screen_point(note, local))
	return _path_run_hit(run, pos)


func _path_run_hit(run: Array[Vector2], pos: Vector2) -> bool:
	if run.is_empty():
		return false
	return JudgeMath.trace_distance(pos, run) <= PATH_HIT_RADIUS


func _width_edge_hit(note: Note, pos: Vector2) -> Dictionary:
	var y := _beat_to_y(note.beat)
	if absf(pos.y - y) > 7.0:
		return {}
	var center := fposmod(note.angle, 360.0) / 360.0
	var half := note.arc_width() / 720.0
	var left := fposmod(center - half + 1.0, 1.0)
	var right := fposmod(center + half, 1.0)
	if absf(pos.x - _u_to_x(left)) < 6.0 or absf(pos.x - _u_to_x(right)) < 6.0:
		return {"kind": "note", "id": note.id, "part": "width"}
	return {}


func _note_positions(note: Note) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match note.type:
		"path":
			result.append({"point": _path_screen_point(note, 0.0), "part": "head"})
			var tail_local := note.path_tail_local()
			var tail_angle := note.tail_angle
			if tail_local.length() > 0.0001:
				tail_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
			result.append({"point": Vector2(_u_to_x(fposmod(tail_angle, 360.0) / 360.0), _beat_to_y(note.end_beat)), "part": "tail"})
		"bell":
			result.append({"point": Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat)), "part": "head"})
		"tap":
			result.append({"point": Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat)), "part": "head"})
		_:
			result.append({"point": Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat)), "part": "head"})
	return result


func _begin_note_drag(screen: Vector2) -> void:
	_drag_mode = "note"
	_drag_start = screen
	_drag_start_beat = _y_to_beat(screen.y)
	_drag_start_u = _x_to_u(screen.x)
	_drag_notes.clear()
	for note in _app.get_selected_notes():
		_drag_notes.append({
			"note": note,
			"beat": note.beat,
			"angle": note.angle,
			"end": note.end_beat,
			"tail": note.tail_angle,
			"center": note.center_u,
		})
	_app.begin_edit()


func _drag_notes_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	var beat := _y_to_beat(screen.y)
	var u := _x_to_u(screen.x)
	var delta_beat := beat - _drag_start_beat
	if event.shift_pressed:
		delta_beat = 0.0
	var delta_u := u - _drag_start_u
	if event.ctrl_pressed:
		delta_u = 0.0
	for item in _drag_notes:
		var note: Note = item["note"]
		if note.lock:
			continue
		var new_beat := maxf(0.0, _snap_beat_to_subdivision(float(item["beat"]) + delta_beat, event.alt_pressed))
		var new_angle := fposmod(float(item["angle"]) + delta_u * 360.0, 360.0)
		var beat_delta := new_beat - note.beat
		note.beat = new_beat
		note.angle = new_angle
		if note.type == "bell":
			note.center_u = new_angle / 360.0
		if note.type in ["hold", "path"]:
			note.end_beat = maxf(note.beat + 0.25, float(item["end"]) + beat_delta)
		if note.type == "path":
			note.tail_angle = fposmod(float(item["tail"]) + delta_u * 360.0, 360.0)
	_app.touch_chart()


func _drag_hold_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	if _drag_notes.is_empty():
		return
	var note: Note = _drag_notes[0]["note"]
	var beat: float = _snap_beat_to_subdivision(_y_to_beat(screen.y), event.alt_pressed)
	note.end_beat = maxf(note.beat + 0.25, beat)
	_app.touch_chart()


func _begin_width_drag(note_id: int, screen: Vector2) -> void:
	var note := _find_note(note_id)
	if note == null:
		return
	_drag_mode = "width"
	_drag_width_note = note
	var center_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	_drag_width_side = -1 if screen.x < center_x else 1
	_drag_width_origin = _x_to_u(screen.x)
	_drag_width_start = note.width
	_app.begin_edit()


func _drag_width_update(screen: Vector2) -> void:
	if _drag_width_note == null:
		return
	var u := _x_to_u(screen.x)
	var delta := (u - _drag_width_origin) * 360.0
	# 画出来的是 width × length_ratio，把鼠标位移换算回 width，边缘才跟手。
	var visual := maxf(0.05, _drag_width_note.length_ratio())
	var new_width := _drag_width_start + delta * 2.0 * float(_drag_width_side) / visual
	_drag_width_note.width = clampf(new_width, 5.0, 360.0)
	_app.touch_chart()


func _create_simple(type: String, beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var added: Array[Note] = []
	if type == "anchor":
		# Anchor 是双押配置：一次放两颗同拍反向的锚点。
		added = chart.make_anchor_pair(beat, u * 360.0)
	else:
		var note := Note.new(type, beat, u * 360.0, 60.0)
		note.id = chart.next_note_id()
		if type == "bell":
			note.width = 0.0
			note.center_u = u
			note.radius = 26.0
		added = [note]
	_app.begin_edit()
	for item in added:
		chart.notes.append(item)
	_app.finish_edit()
	_app.select_note(added[0].id)


func _create_sized_tap(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	# 默认与旧版 Tap 同长（1.0 l），按下去就能在检查器里改成 0–1.5 l 的任意值。
	var note := Note.new("tap", beat, u * 360.0, 60.0)
	note.id = chart.next_note_id()
	note.set_size_ratio(1.0)
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)


func _create_hold(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var note := Note.new("hold", beat, u * 360.0, 60.0)
	note.id = chart.next_note_id()
	note.end_beat = beat + 1.0
	_app.begin_edit()
	chart.notes.append(note)
	_app.select_note(note.id)
	_pending_hold = note
	notice.emit("Hold：移动鼠标到结束拍并再次左键单击；Esc 取消。", "info")


func _finish_pending_hold(end_beat: float) -> void:
	if _pending_hold == null:
		return
	var note := _pending_hold
	var start := note.beat
	var finish := maxf(0.0, end_beat)
	if finish < start:
		# The author dragged upward/backwards: the second click becomes the
		# new start, the first click becomes the end.
		note.beat = finish
		note.end_beat = start
	else:
		note.end_beat = finish
	if note.end_beat - note.beat < 0.25:
		note.end_beat = note.beat + 0.25
	_pending_hold = null
	_app.finish_edit()
	_app.select_note(note.id)
	queue_redraw()


func _begin_path_part(parent: Note) -> void:
	var chart: Chart = _app.chart
	if chart == null or parent == null:
		return
	_app.set_tool("path")
	var head := parent.path_tail_local()
	var beat := parent.end_beat
	var angle := rad_to_deg(atan2(head.y, head.x))
	var note := Note.new("path", beat, angle, parent.width)
	note.id = chart.next_note_id()
	note.end_beat = beat + 1.0
	note.tail_angle = angle
	note.tail_width = parent.tail_width
	note.tolerance = parent.tolerance
	note.samples_per_beat = parent.samples_per_beat
	note.path_part = parent.path_part + 1
	note.path_prev_id = parent.id
	note.path_head_local = head
	note.path_centrifuge = 0.72
	note.path_axis = 0.0
	note.generate_path_shape()
	_app.begin_edit()
	chart.notes.append(note)
	_app.select_note(note.id)
	_pending_path = note
	_pending_path_parent = parent
	notice.emit("Path part%d：左键放置本段尾部；Esc 取消。" % note.path_part, "info")


func _place_path(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	if _pending_path == null:
		var note := Note.new("path", beat, u * 360.0, 60.0)
		note.id = chart.next_note_id()
		note.end_beat = beat + 1.0
		note.tail_angle = u * 360.0
		note.tail_width = 45.0
		note.tolerance = 0.24
		note.samples_per_beat = 4.0
		note.path_centrifuge = 0.72
		note.path_axis = 0.0
		note.generate_path_shape()
		_app.begin_edit()
		chart.notes.append(note)
		_app.finish_edit()
		_app.select_note(note.id)
		_pending_path = note
		_pending_path_parent = null
		notice.emit("Path：再点一次放置尾部；Esc 取消。", "info")
	else:
		_app.begin_edit()
		_pending_path.end_beat = maxf(_pending_path.beat + 0.25, beat)
		_pending_path.tail_angle = u * 360.0
		if _pending_path_parent != null:
			_pending_path.path_head_local = _pending_path_parent.path_tail_local()
			_pending_path.path_prev_id = _pending_path_parent.id
			_pending_path_parent.path_next_id = _pending_path.id
		_pending_path.generate_path_shape()
		_app.finish_edit()
		# Keep the Path tool active so the note-selection block stays on Path
		# after choosing the tail; Esc is the explicit way to deselect it.
		_pending_path = null
		_pending_path_parent = null


func _create_seek_at(beat: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	for item in chart.notes:
		if item.type == "seek" and item.seek_pending:
			item.seek_pending = false
	var note := Note.new("seek", beat, 0.0, 360.0)
	note.id = chart.next_note_id()
	note.end_beat = beat
	note.seek_orien = 0
	note.seek_pending = true
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)
	notice.emit("Seek：按 W 朝里 / S 朝外；放置期间 W/S 快捷键被屏蔽。", "info")


func has_pending_seek() -> bool:
	if _app == null or _app.chart == null:
		return false
	for item in _app.chart.notes:
		if item.type == "seek" and item.seek_pending:
			return true
	return false


func set_pending_seek_orientation(orien: int) -> void:
	if _app == null or _app.chart == null:
		return
	for item in _app.chart.notes:
		if item.type == "seek" and item.seek_pending:
			_app.begin_edit()
			item.seek_orien = 1 if orien == 1 else 0
			item.seek_pending = false
			_app.finish_edit()
			_app.select_note(item.id)
			queue_redraw()
			if _overlay != null:
				_overlay.queue_redraw()
			return


func _begin_red(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var region := Region.new(chart.next_region_id(), beat, beat + 1.0)
	region.angle = u * 360.0
	region.width = 30.0
	_app.begin_edit()
	chart.regions.append(region)
	_drag_mode = "limit"
	_drag_start_beat = beat
	_drag_start_u = u
	_drag_region = region
	_app.select_region(region.id)


func _drag_red_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	if _drag_region == null:
		return
	var u := _x_to_u(screen.x)
	var beat: float = _app.snap_beat(_y_to_beat(screen.y), event.alt_pressed)
	var start_u := _drag_start_u
	var delta := (u - start_u) * 360.0
	if absf(delta) < 8.0:
		delta = 30.0 if delta >= 0.0 else -30.0
	_drag_region.angle = fposmod(start_u * 360.0 + delta * 0.5, 360.0)
	_drag_region.width = clampf(absf(delta), 10.0, 359.0)
	_drag_region.start_beat = minf(_drag_start_beat, beat)
	_drag_region.end_beat = maxf(_drag_start_beat + 0.25, minf(beat, _drag_start_beat + 4.0))
	_app.touch_chart()


func _create_event_at(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var event := BoundaryEvent.new(chart.next_event_id(), beat, beat + 4.0, u, minf(1.0, u + 0.5), chart.default_shape_id, chart.default_shape_id)
	_app.begin_edit()
	chart.events.append(event)
	_app.finish_edit()
	_app.select_event(event.id)
	notice.emit("事件已创建；在事件页选择目标形状与恢复方式。", "info")


func _finish_marquee() -> void:
	if _marquee.size.x < 3.0 and _marquee.size.y < 3.0:
		_app.clear_selection()
		return
	if _marquee_start_beat > _marquee_end_beat:
		var beat := _marquee_start_beat
		_marquee_start_beat = _marquee_end_beat
		_marquee_end_beat = beat
		var u := _marquee_start_u
		_marquee_start_u = _marquee_end_u
		_marquee_end_u = u
	var ids: Array[int] = []
	var chart: Chart = _app.chart
	for note in chart.notes:
		if _note_in_marquee(note):
			ids.append(note.id)
	_app.select_notes(ids)


func _note_in_marquee(note: Note) -> bool:
	for item in _note_positions(note):
		if _circle_hits_marquee(item["point"], _note_point_radius(note, String(item.get("part", "head")))):
			return true
	if note.type in ["tap", "hold", "path"]:
		var head_width := note.width if note.type == "path" else note.arc_width()
		if _arc_hits_marquee(note.angle, head_width, _beat_to_y(note.beat)):
			return true
	if note.type == "path":
		var tail_local := note.path_tail_local()
		var tail_angle := note.tail_angle
		if tail_local.length() > 0.0001:
			tail_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
		if _arc_hits_marquee(tail_angle, note.tail_width, _beat_to_y(note.end_beat)):
			return true
		var total := maxf(0.001, note.duration())
		var previous := Vector2.INF
		for i in 41:
			var local := total * float(i) / 40.0
			if note.erased_at(local):
				previous = Vector2.INF
				continue
			var point := _path_screen_point(note, local)
			if previous.is_finite() and _segment_hits_marquee(previous, point):
				return true
			previous = point
	if note.type == "seek":
		var seek_y := _beat_to_y(note.beat)
		if _marquee.intersects(Rect2(Vector2(_u_to_x(0.0), seek_y - 4.0), Vector2(_u_to_x(1.0) - _u_to_x(0.0), 8.0))):
			return true
	if note.type == "hold":
		var y0 := _beat_to_y(note.beat)
		var y1 := _beat_to_y(note.end_beat)
		var body_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
		var half_width := 8.0
		var body := Rect2(Vector2(body_x - half_width, minf(y0, y1)), Vector2(half_width * 2.0, maxf(2.0, absf(y1 - y0))))
		if _marquee.intersects(body):
			return true
	return false


func _note_point_radius(note: Note, part: String) -> float:
	if note.type == "path":
		return 7.0 if part == "tail" else 9.0
	if note.type == "hold" or note.type == "tap":
		return 9.0
	return 8.0


func _arc_hits_marquee(center_angle: float, width: float, y: float) -> bool:
	var steps := 8
	var previous := Vector2.INF
	var half := maxf(0.0, width) * 0.5
	for i in steps + 1:
		var angle := center_angle - half + half * 2.0 * float(i) / float(steps)
		var point := Vector2(_u_to_x(fposmod(angle, 360.0) / 360.0), y)
		if _circle_hits_marquee(point, 4.0):
			return true
		if previous.is_finite() and _segment_hits_marquee(previous, point):
			return true
		previous = point
	return false


func _circle_hits_marquee(center: Vector2, radius: float) -> bool:
	var closest := Vector2(
		clampf(center.x, _marquee.position.x, _marquee.end.x),
		clampf(center.y, _marquee.position.y, _marquee.end.y)
	)
	return center.distance_squared_to(closest) <= radius * radius


func _segment_hits_marquee(a: Vector2, b: Vector2) -> bool:
	if _marquee.has_point(a) or _marquee.has_point(b):
		return true
	var corners := [
		_marquee.position,
		Vector2(_marquee.end.x, _marquee.position.y),
		_marquee.end,
		Vector2(_marquee.position.x, _marquee.end.y),
	]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


func _select_visible() -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var ids: Array[int] = []
	var top := scroll_beat
	var bottom := scroll_beat + _visible_beats()
	for note in chart.notes:
		if note.beat >= top and note.beat <= bottom:
			ids.append(note.id)
	_app.select_notes(ids)


func _delete_hit(hit: Dictionary) -> void:
	# 右键单击直接删掉命中的那一个：音符 / 红区 / 事件。
	if _app == null or _app.chart == null or hit.is_empty():
		return
	var chart: Chart = _app.chart
	_app.begin_edit()
	match String(hit.get("kind", "")):
		"note":
			var note_id := int(hit.get("id", -1))
			for note in chart.notes.duplicate():
				if note.id == note_id:
					chart.notes.erase(note)
		"region":
			var region_id := int(hit.get("id", -1))
			for region in chart.regions.duplicate():
				if region.id == region_id:
					chart.regions.erase(region)
		"event":
			var event_id := String(hit.get("id", ""))
			for event in chart.events.duplicate():
				if event.id == event_id:
					chart.events.erase(event)
	_app.finish_edit()
	_app.clear_selection()
	_pending_path = null


func _delete_selection() -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart
	_app.begin_edit()
	var note_ids: Array = []
	for note in _app.selection_with_partners():
		note_ids.append(note.id)
	for note in chart.notes.duplicate():
		if note_ids.has(note.id):
			chart.notes.erase(note)
	if _app.selected_region_id >= 0:
		for region in chart.regions.duplicate():
			if region.id == _app.selected_region_id:
				chart.regions.erase(region)
	if not _app.selected_event_id.is_empty():
		for event in chart.events.duplicate():
			if event.id == _app.selected_event_id:
				chart.events.erase(event)
	_app.finish_edit()
	_app.clear_selection()
	_pending_path = null


func _cancel_pending() -> void:
	if _pending_hold != null:
		if _app != null and _app.chart != null:
			_app.begin_edit()
			_app.chart.notes.erase(_pending_hold)
			_app.finish_edit()
			_app.clear_selection()
		_pending_hold = null
	if _pending_path != null:
		if _app != null and _app.chart != null:
			_app.begin_edit()
			_app.chart.notes.erase(_pending_path)
			_app.finish_edit()
			_app.clear_selection()
		_pending_path = null
		_pending_path_parent = null
	if _drag_mode != "":
		if _drag_mode == "marquee":
			_marquee = Rect2()
		_drag_mode = ""
		_app.finish_edit()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _path_tail_hit(pos: Vector2) -> Note:
	if _app == null or _app.chart == null:
		return null
	var best: Note = null
	var best_distance := 14.0
	for note in _app.chart.notes:
		if note.type != "path":
			continue
		var tail: Vector2 = note.path_tail_local()
		var angle: float = float(note.tail_angle)
		if tail.length() > 0.0001:
			angle = rad_to_deg(atan2(tail.y, tail.x))
		var point := Vector2(_u_to_x(fposmod(angle, 360.0) / 360.0), _beat_to_y(note.end_beat))
		var distance := point.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = note
	return best


func _find_note(note_id: int) -> Note:
	if _app == null or _app.chart == null:
		return null
	for note in _app.chart.notes:
		if note.id == note_id:
			return note
	return null
