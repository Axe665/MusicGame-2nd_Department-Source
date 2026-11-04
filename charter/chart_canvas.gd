class_name ChartCanvas
extends Control

signal hover_changed(u: float, beat: float)
signal notice(message: String, level: String)

const LEFT_MARGIN := 58.0
const TOP_MARGIN := 24.0
const BOTTOM_MARGIN := 12.0
const RIGHT_MARGIN := 12.0
const WAVE_WIDTH := 24.0
const NOTE_SNAP_PX := 6.0
const NOTE_TOOLS := ["tap", "hold", "path", "trace", "anchor", "bell"]

var _app: Node = null
var px_per_beat: float = 28.0
var scroll_beat: float = 0.0
var follow_playhead: bool = true

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
var _pending_path: Note = null
var _trace_hint_shown: bool = false

var _waveform_peaks: PackedFloat32Array = PackedFloat32Array()
var _waveform_duration: float = 0.0
var _waveform_audio_path: String = ""
var _last_playhead_redraw: int = 0
var _overlay: Control
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
		px_per_beat = _app.zoom_px_per_beat
	var ghost_script: Script = load("res://charter/chart_ghost_layer.gd")
	if ghost_script != null:
		_ghost_layer = ghost_script.new()
		_ghost_layer.name = "GhostLayer"
		_ghost_layer.visible = false
		add_child(_ghost_layer)
		_ghost_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ghost_layer._app = _app
	_overlay = load("res://charter/chart_overlay.gd").new()
	_overlay.canvas = self
	add_child(_overlay)
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
	return plot.position.y + (beat - scroll_beat) * _effective_px_per_beat()


func _y_to_beat(y: float) -> float:
	var plot := _plot_rect()
	return scroll_beat + (y - plot.position.y) / maxf(0.1, _effective_px_per_beat())


func _visible_beats() -> float:
	return size.y / maxf(10.0, _effective_px_per_beat())


func _clear_clipboard_on_chart_replace() -> void:
	cancel_clipboard(false)


func has_clipboard() -> bool:
	return _clipboard_active and not _clipboard_notes.is_empty()


func copy_selection(cut: bool = false) -> void:
	if _app == null or _app.chart == null:
		return
	var selected: Array[Note] = _app.get_selected_notes()
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
		if copy.type in ["hold", "path", "trace"]:
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
	var note: Note = selected[0]
	if note.lock:
		notice.emit("音符已锁定，无法镜像。", "warning")
		return false
	_app.begin_edit()
	note.mirror_u()
	_app.finish_edit()
	queue_redraw()
	notice.emit("已镜像音符 %d。" % note.id, "info")
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
		if copy.type in ["hold", "path", "trace"]:
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
	_ghost_layer.visible = _clipboard_active
	_ghost_layer.queue_redraw()
	_ghost_last_scroll = scroll_beat
	_ghost_last_px = px_per_beat
	_ghost_last_stretch = float(_app.vertical_stretch) if _app != null else 0.0
	_ghost_last_size = size


func _on_chart_changed() -> void:
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
	_pending_path = null
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


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
	var right := PackedVector2Array()
	var left := PackedVector2Array()
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
		right.append(Vector2(center_x + peak * half, y))
		left.append(Vector2(center_x - peak * half, y))
	if right.size() > 1:
		draw_polyline(right, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.42), 1.0, true)
	if left.size() > 1:
		draw_polyline(left, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.26), 1.0, true)


func _draw_grid(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var font := UITheme.mono_font()
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
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
	var first_beat := floori(scroll_beat)
	var last_beat := ceili(scroll_beat + _visible_beats() + 1.0)
	var last_bar := -999
	for beat in range(first_beat, last_beat + 1):
		var y := _beat_to_y(float(beat))
		if y < plot.position.y - 2.0 or y > plot.end.y + 2.0:
			continue
		var bpb := chart.timing.beats_per_bar_at(float(beat))
		var is_bar := beat % bpb == 0
		var color := Color(1, 1, 1, 0.16 if is_bar else 0.055)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), color, 1.0 if not is_bar else 1.5)
		if is_bar:
			var bar := floori(float(beat) / float(bpb))
			if bar != last_bar:
				last_bar = bar
				draw_string(font, Vector2(4, y + 4), "bar %d" % bar, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.52))
	_draw_beat_subdivisions(plot)
	_draw_vertical_lines(plot)
	for point in chart.timing.points:
		if point.beat < scroll_beat or point.beat > scroll_beat + _visible_beats():
			continue
		var y := _beat_to_y(point.beat)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1.5)
		draw_string(font, Vector2(plot.end.x - 120, y - 4), "BPM %.1f" % point.bpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.GOLD)


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
		var color := UITheme.RED if region.kind == "red" else UITheme.GOLD
		var y0 := _beat_to_y(region.start_beat)
		var y1 := _beat_to_y(region.end_beat)
		if y1 < plot.position.y or y0 > plot.end.y:
			continue
		for interval in _u_intervals(region.angle, region.width):
			var x0 := _u_to_x(interval.x)
			var x1 := _u_to_x(interval.y)
			var rect := Rect2(Vector2(x0, y0), Vector2(maxf(2.0, x1 - x0), maxf(2.0, y1 - y0)))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.16))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
			draw_string(UITheme.mono_font(), Vector2(x0 + 4, y0 + 12), "RED %d" % region.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
		if _is_region_selected(region.id):
			draw_rect(Rect2(Vector2(_u_to_x(0.0), y0), Vector2(plot.size.x, maxf(2.0, y1 - y0))), Color(1, 1, 1, 0.35), false, 1.0)


func _draw_events(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for event in chart.events:
		var y0 := _beat_to_y(event.start_beat)
		var y1 := _beat_to_y(event.end_beat + event.restore_duration)
		if y1 < plot.position.y or y0 > plot.end.y:
			continue
		var x0 := _u_to_x(event.target_u0)
		var x1 := _u_to_x(event.target_u1)
		var rect := Rect2(Vector2(x0, y0), Vector2(maxf(2.0, x1 - x0), maxf(2.0, y1 - y0)))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.07))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.30), false, 1.0)
		if y1 - y0 > 14.0:
			draw_string(UITheme.mono_font(), Vector2(x0 + 3, y0 + 10), "%s → %s" % [event.from_shape, event.to_shape], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.7))


func _draw_notes(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for note in chart.notes:
		match note.type:
			"tap":
				_draw_tap(note)
			"hold":
				_draw_hold(note)
			"path":
				_draw_path(note)
			"trace":
				_draw_trace(note, plot)
			"anchor":
				_draw_anchor(note)
			"bell":
				_draw_bell(note)
	if _pending_path != null:
		var head := Vector2(_u_to_x(_pending_path.angle / 360.0), _beat_to_y(_pending_path.beat))
		var tail := Vector2(_u_to_x(_hover_u), _beat_to_y(_hover_beat))
		draw_dashed_line(head, tail, UITheme.CYAN, 1.5, 6.0)


func _draw_tap(note: Note) -> void:
	var y := _beat_to_y(note.beat)
	var selected := _is_note_selected(note.id)
	if note.space == "plane":
		var px := _u_to_x(clampf(note.plane_x, 0.0, 1.0))
		var point := Vector2(px, y)
		draw_circle(point, 7.0 if selected else 6.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.20))
		draw_arc(point, 6.0, 0.0, TAU, 24, UITheme.CORAL, 2.0, true)
		draw_circle(point, 2.0, UITheme.INK)
		if _show_type_label(note):
			_draw_type_label("PLANE TAP", point + Vector2(9, 12), UITheme.CORAL)
		return
	for interval in _u_intervals(note.angle, note.width):
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
	_draw_hexagon(Vector2(x, y0), 9.0 if selected else 8.0, color)
	_draw_ring(Vector2(x, y1), 6.0, color)
	_draw_width_band(note.angle, note.width, y0, color)
	if _show_type_label(note):
		_draw_type_label("HOLD", Vector2(x + 11.0, y0 + 12.0), color)


func _draw_path(note: Note) -> void:
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.end_beat)
	var x0 := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	var x1 := _u_to_x(fposmod(note.tail_angle, 360.0) / 360.0)
	var selected := _is_note_selected(note.id)
	var total := maxf(0.001, note.duration())
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in 41:
		var rel := total * float(i) / 40.0
		if note.erased_at(rel):
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			continue
		run.append(Vector2(
			_u_to_x(fposmod(note.path_angle_at(rel), 360.0) / 360.0),
			_beat_to_y(note.beat + rel)
		))
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
			var rel := float(point.get("db", 0.0))
			if note.erased_at(rel):
				continue
			draw_circle(Vector2(
				_u_to_x(fposmod(note.path_angle_at(rel), 360.0) / 360.0),
				_beat_to_y(note.beat + rel)
			), 2.5, UITheme.CYAN)
	_draw_width_band(note.angle, note.width, y0, UITheme.CYAN)
	_draw_width_band(note.tail_angle, note.tail_width, y1, UITheme.GOLD)
	_draw_star(Vector2(x0, y0), 9.0 if selected else 8.0, UITheme.CORAL)
	_draw_donut(Vector2(x1, y1), 7.0, UITheme.GOLD)
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


func _draw_trace(note: Note, _plot: Rect2) -> void:
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.end_beat)
	var selected := _is_note_selected(note.id)
	var cx := _u_to_x(0.5)
	var rect := Rect2(Vector2(cx - 24, y0), Vector2(48, maxf(12, y1 - y0)))
	draw_rect(rect, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.12))
	draw_rect(rect, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.60), false, 1.0)
	if selected:
		draw_rect(rect, UITheme.INK, false, 1.0)
	var mini := PackedVector2Array()
	for point in note.trace_pts:
		var px := float(point.get("x", 0.0))
		var py := float(point.get("y", 0.0))
		if note.trace_style == "slider":
			px = px * 0.5 + 0.5
			py = py * 0.5 + 0.5
		mini.append(Vector2(cx - 20 + px * 40.0, y0 + 4 + py * maxf(4, y1 - y0 - 8)))
	if mini.size() > 1:
		draw_polyline(mini, UITheme.MINT, 2.0, true)
	draw_line(Vector2(cx - 19, y0 + 3), Vector2(cx - 11, y0 + 11), UITheme.MINT, 1.5, true)
	draw_line(Vector2(cx - 11, y0 + 3), Vector2(cx - 19, y0 + 11), UITheme.MINT, 1.5, true)
	if _show_type_label(note):
		_draw_type_label("SLIDE" if note.trace_style == "slider" else "TRACE", Vector2(cx + 27.0, y0 + 10.0), UITheme.MINT)


func _draw_anchor(note: Note) -> void:
	var p := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat))
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
	draw_circle(p, 8.0 if selected else 7.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.20))
	draw_arc(p, 8.0 if selected else 7.0, 0.0, TAU, 28, UITheme.GOLD, 2.0, true)
	draw_circle(p, 3.0, UITheme.GOLD)
	draw_circle(p, 1.2, UITheme.INK)
	if _show_type_label(note):
		_draw_type_label("BELL", p + Vector2(10, 12), UITheme.GOLD)


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
		{"type": "trace", "label": "Trace", "color": UITheme.MINT},
		{"type": "anchor", "label": "Anchor", "color": UITheme.VIOLET},
		{"type": "bell", "label": "Bell", "color": UITheme.GOLD},
		{"type": "red", "label": "Red", "color": UITheme.RED},
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
			"trace":
				draw_line(p + Vector2(-4, 3), p + Vector2(4, -3), color, 3.0, true)
				draw_line(p + Vector2(-3, -3), p + Vector2(3, 3), UITheme.INK, 1.0, true)
			"anchor":
				_draw_diamond(p, 4.0, color)
			"bell":
				draw_arc(p, 4.0, 0.0, TAU, 16, color, 1.5, true)
				draw_circle(p, 1.5, color)
			"red":
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
		hover_changed.emit(_hover_u, _hover_beat)
		if _clipboard_active:
			_clipboard_mouse_beat = _hover_beat
			_rebuild_ghost()
		if _drag_mode == "note":
			_drag_notes_update(event.position, event)
		elif _drag_mode == "width":
			_drag_width_update(event.position)
		elif _drag_mode == "red":
			_drag_red_update(event.position, event)
		elif _drag_mode == "hold_end":
			_drag_hold_update(event.position, event)
		elif _drag_mode == "marquee":
			_marquee = Rect2(_drag_start, event.position - _drag_start).abs()
		if _drag_mode != "" or _pending_path != null:
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
			if event.pressed and _drag_mode == "" and _pending_path == null:
				_begin_marquee(event.position)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			# A right-drag starts the marquee; the following left release ends
			# it and must not be interpreted as a note placement click.
			if _drag_mode == "marquee":
				if not event.pressed:
					_on_left_release(event)
				accept_event()
				return
			if event.pressed:
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
			if has_clipboard():
				cancel_clipboard()
			accept_event()


func _handle_wheel(event: InputEventMouseButton) -> void:
	if event.ctrl_pressed:
		var beat := _y_to_beat(event.position.y)
		var factor := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.89
		px_per_beat = clampf(px_per_beat * factor, 10.0, 400.0)
		scroll_beat = maxf(0.0, beat - (event.position.y - _plot_rect().position.y) / _effective_px_per_beat())
		if _app != null:
			_app.zoom_px_per_beat = px_per_beat
	else:
		var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		scroll_beat = maxf(0.0, scroll_beat + direction * 3.0)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _snap_beat_u(raw_beat: float, raw_u: float, bypass: bool) -> Vector2:
	## Notes near a coarse beat line or one of the vertical lines are pulled
	## onto that line. When both are close, the result is their intersection;
	## otherwise only the close axis moves.
	if bypass or _app == null:
		return Vector2(raw_beat, raw_u)
	var beat: float = _app.snap_beat(raw_beat, false)
	var u := raw_u
	var beat_tolerance_px := minf(NOTE_SNAP_PX, _effective_px_per_beat() * 0.18)
	var nearest_beat := roundf(raw_beat)
	if absf(raw_beat - nearest_beat) * _effective_px_per_beat() <= beat_tolerance_px:
		beat = nearest_beat
	var lines := mini(int(_app.vertical_lines), TimingMap.MAX_VERTICAL_LINES)
	if lines > 0:
		var plot := _plot_rect()
		var nearest_u := TimingMap.nearest_vertical_line_u(raw_u, lines)
		var step := 1.0 / float(lines + 1)
		var u_tolerance_px := minf(NOTE_SNAP_PX, step * plot.size.x * 0.25)
		if absf(raw_u - nearest_u) * plot.size.x <= u_tolerance_px:
			u = nearest_u
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
		if note.type in ["hold", "path", "trace"]:
			note.end_beat = maxf(note.beat + 0.25, note.end_beat + beat_delta)
		if note.type == "bell":
			note.angle = fposmod(snapped.y * 360.0, 360.0)
			note.center_u = snapped.y
		elif note.type != "trace":
			note.angle = fposmod(note.angle + angle_delta, 360.0)
			if note.type == "path":
				note.tail_angle = fposmod(note.tail_angle + angle_delta, 360.0)
	_app.touch_chart()


func _on_left_press(event: InputEventMouseButton) -> void:
	if _app == null:
		return
	var plot := _plot_rect()
	var beat: float = _app.snap_beat(_y_to_beat(event.position.y), event.alt_pressed)
	var u := _x_to_u(event.position.x)
	if event.position.x < plot.position.x - 4.0:
		if event.shift_pressed and not _app.selected_notes.is_empty():
			_app.begin_edit()
			for note in _app.get_selected_notes():
				note.beat = beat
				if note.type in ["hold", "path", "trace"]:
					note.end_beat = maxf(note.end_beat, note.beat + 0.25)
			_app.finish_edit()
		else:
			_app.set_playhead(beat)
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
		"trace":
			_create_trace_at(beat)
		"red":
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
	if _drag_mode in ["note", "width", "red", "hold_end"]:
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
	_marquee = Rect2(position, Vector2.ZERO)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _select_press(event: InputEventMouseButton) -> void:
	var hit := _hit_test(event.position)
	if hit.is_empty():
		if event.double_click:
			_app.set_playhead(_app.snap_beat(_y_to_beat(event.position.y)))
			return
		_app.clear_selection()
		return
	match hit["kind"]:
		"note":
			var note_id := int(hit["id"])
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
			if absf(pos.y - note_y) <= 7.0 and JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, note.angle, note.width):
				return {"kind": "note", "id": note.id, "part": "body"}
		if note.type == "hold" or note.type == "path" or note.type == "trace":
			var y0 := _beat_to_y(note.beat)
			var y1 := _beat_to_y(note.end_beat)
			if pos.y >= minf(y0, y1) - 4 and pos.y <= maxf(y0, y1) + 4:
				var body_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0) if note.type != "trace" else _u_to_x(0.5)
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


func _width_edge_hit(note: Note, pos: Vector2) -> Dictionary:
	var y := _beat_to_y(note.beat)
	if absf(pos.y - y) > 7.0:
		return {}
	var center := fposmod(note.angle, 360.0) / 360.0
	var half := note.width / 720.0
	var left := fposmod(center - half + 1.0, 1.0)
	var right := fposmod(center + half, 1.0)
	if absf(pos.x - _u_to_x(left)) < 6.0 or absf(pos.x - _u_to_x(right)) < 6.0:
		return {"kind": "note", "id": note.id, "part": "width"}
	return {}


func _note_positions(note: Note) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match note.type:
		"path":
			result.append({"point": Vector2(_u_to_x(note.angle / 360.0), _beat_to_y(note.beat)), "part": "head"})
			result.append({"point": Vector2(_u_to_x(note.tail_angle / 360.0), _beat_to_y(note.end_beat)), "part": "tail"})
		"trace":
			result.append({"point": Vector2(_u_to_x(0.5), _beat_to_y(note.beat)), "part": "head"})
		"bell":
			result.append({"point": Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat)), "part": "head"})
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
		if note.type == "anchor":
			note.beat = maxf(0.0, _app.snap_beat(float(item["beat"]) + delta_beat, event.alt_pressed))
			continue
		if note.type == "trace":
			var new_beat := maxf(0.0, _app.snap_beat(float(item["beat"]) + delta_beat, event.alt_pressed))
			var offset := new_beat - note.beat
			note.beat = new_beat
			note.end_beat = maxf(note.beat + 0.25, float(item["end"]) + offset)
			continue
		var new_beat := maxf(0.0, _app.snap_beat(float(item["beat"]) + delta_beat, event.alt_pressed))
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
	var beat: float = _app.snap_beat(_y_to_beat(screen.y), event.alt_pressed)
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
	var new_width := _drag_width_start + delta * 2.0 * float(_drag_width_side)
	_drag_width_note.width = clampf(new_width, 5.0, 360.0)
	_app.touch_chart()


func _create_simple(type: String, beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var note := Note.new(type, beat, u * 360.0, 60.0)
	note.id = chart.next_note_id()
	if type == "anchor":
		note.width = 0.0
		note.anchor_pair = -1
	elif type == "bell":
		note.width = 0.0
		note.center_u = u
		note.radius = 26.0
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
	_drag_mode = "hold_end"
	_drag_start_beat = beat
	_drag_start_u = u
	_drag_notes = [{"note": note}]


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
		_app.begin_edit()
		chart.notes.append(note)
		_app.finish_edit()
		_app.select_note(note.id)
		_pending_path = note
		notice.emit("Path：再点一次放置尾部；Esc 取消。", "info")
	else:
		_app.begin_edit()
		_pending_path.end_beat = maxf(_pending_path.beat + 0.25, beat)
		_pending_path.tail_angle = u * 360.0
		_app.finish_edit()
		_pending_path = null
		_app.set_tool("select")


func _create_trace_at(beat: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var note := Note.new("trace", beat, 0.0, 0.0)
	note.id = chart.next_note_id()
	note.end_beat = beat + 2.0
	note.move_px = 120.0
	note.trace_pts = [
		{"x": 0.28, "y": 0.68, "db": 0.0},
		{"x": 0.45, "y": 0.52, "db": 0.67},
		{"x": 0.62, "y": 0.45, "db": 1.34},
		{"x": 0.74, "y": 0.34, "db": 2.0},
	]
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)
	if not _trace_hint_shown:
		_trace_hint_shown = true
		notice.emit("Trace 已创建；在预览窗拖拽可重画二维擦带。", "info")


func _begin_red(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var region := Region.new(chart.next_region_id(), beat, beat + 1.0)
	region.angle = u * 360.0
	region.width = 30.0
	_app.begin_edit()
	chart.regions.append(region)
	_drag_mode = "red"
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
	var ids: Array[int] = []
	var chart: Chart = _app.chart
	for note in chart.notes:
		var p := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat))
		var box := Rect2(p - Vector2(8, 8), Vector2(16, 16))
		if _marquee.intersects(box):
			ids.append(note.id)
	_app.select_notes(ids)


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


func _delete_selection() -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart
	_app.begin_edit()
	var note_ids: Array = _app.selected_notes.duplicate()
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
	if _pending_path != null:
		if _app != null and _app.chart != null:
			_app.begin_edit()
			_app.chart.notes.erase(_pending_path)
			_app.finish_edit()
			_app.clear_selection()
		_pending_path = null
	if _drag_mode != "":
		if _drag_mode == "marquee":
			_marquee = Rect2()
		_drag_mode = ""
		_app.finish_edit()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _find_note(note_id: int) -> Note:
	if _app == null or _app.chart == null:
		return null
	for note in _app.chart.notes:
		if note.id == note_id:
			return note
	return null
