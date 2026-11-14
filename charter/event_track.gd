class_name EventTrack
extends Control

var _app: Node = null
var canvas: ChartCanvas = null
var _last_scroll: float = -999.0
var _last_px: float = -999.0
var _dragging: bool = false
var _last_redraw_msec: int = 0


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	custom_minimum_size = Vector2(0, 28)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _app != null:
		_app.chart_changed.connect(queue_redraw)
		_app.chart_live_changed.connect(queue_redraw)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.selection_changed.connect(queue_redraw)


func _on_playhead_changed(_beat: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_redraw_msec >= 50:
		_last_redraw_msec = now
		queue_redraw()


func _process(_delta: float) -> void:
	if canvas == null:
		return
	if not is_equal_approx(_last_scroll, canvas.scroll_beat) or not is_equal_approx(_last_px, canvas.px_per_beat):
		_last_scroll = canvas.scroll_beat
		_last_px = canvas.px_per_beat
		queue_redraw()


func _beat_to_x(beat: float) -> float:
	if canvas == null:
		return 0.0
	return (beat - canvas.scroll_beat) / maxf(0.1, canvas._visible_beats()) * size.x


func _x_to_beat(x: float) -> float:
	if canvas == null:
		return 0.0
	return canvas.scroll_beat + (x / maxf(1.0, size.x)) * canvas._visible_beats()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0B0D12"))
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(1, 1, 1, 0.08), 1.0)
	if _app == null or _app.chart == null or canvas == null:
		return
	var chart: Chart = _app.chart
	var visible_start := canvas.scroll_beat
	var visible_end := canvas.scroll_beat + canvas._visible_beats()
	var first_bar := floori(visible_start / float(chart.timing.beats_per_bar_at(visible_start))) * chart.timing.beats_per_bar_at(visible_start)
	for bar_beat in range(first_bar, ceili(visible_end) + chart.timing.beats_per_bar_at(visible_end) * 2):
		var bpb := chart.timing.beats_per_bar_at(float(bar_beat))
		if bar_beat % bpb != 0:
			continue
		var x := _beat_to_x(float(bar_beat))
		if x < 0.0 or x > size.x:
			continue
		draw_line(Vector2(x, 1), Vector2(x, size.y - 1), Color(1, 1, 1, 0.10), 1.0)
	var keys := chart.sorted_shape_keys()
	for i in keys.size():
		var x := _beat_to_x(float(keys[i].get("beat", 0.0)))
		if x < -6.0 or x > size.x + 6.0:
			continue
		var next_beat := float(keys[i + 1].get("beat", float(keys[i].get("beat", 0.0)))) if i + 1 < keys.size() else float(keys[i].get("beat", 0.0))
		var x1 := _beat_to_x(next_beat)
		if x1 > x + 2.0:
			draw_line(Vector2(x, 13), Vector2(x1, 13), Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.25), 3.0)
		var diamond := PackedVector2Array([Vector2(x, 9), Vector2(x + 5, 14), Vector2(x, 19), Vector2(x - 5, 14)])
		draw_colored_polygon(diamond, UITheme.CYAN)
		if x1 - x > 30.0:
			draw_string(UITheme.mono_font(), Vector2(x + 7, 17), String(keys[i].get("shape_id", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.7))
	for region in chart.regions:
		var x0 := _beat_to_x(region.start_beat)
		var x1 := _beat_to_x(region.end_beat)
		var rect := Rect2(Vector2(x0, 19), Vector2(maxf(2.0, x1 - x0), 7))
		var selected: bool = _app.selected_region_id == region.id
		draw_rect(rect, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.42 if selected else 0.28))
		draw_rect(rect, UITheme.RED if selected else Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.55), false, 1.0)
		if x1 - x0 > 30.0:
			draw_string(UITheme.mono_font(), Vector2(x0 + 3, 25), "LIMIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.75))
	var playhead_x := _beat_to_x(_app.playhead_beat)
	draw_line(Vector2(playhead_x, 0), Vector2(playhead_x, size.y), Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.9), 1.5)
	if chart.shape_keys.is_empty() and chart.regions.is_empty():
		draw_string(UITheme.mono_font(), Vector2(8, 18), "形状关键帧：视图 → 环编辑", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.30))


func _gui_input(event: InputEvent) -> void:
	if _app == null or canvas == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			grab_focus()
			_press(event.position, event)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_app.seek(_app.snap_beat(_x_to_beat(event.position.x), event.alt_pressed))
		accept_event()


func _press(pos: Vector2, event: InputEventMouseButton) -> void:
	if pos.y >= 8 and pos.y <= 20:
		for key in _app.chart.sorted_shape_keys():
			var x := _beat_to_x(float(key.get("beat", 0.0)))
			if absf(pos.x - x) <= 6.0:
				_app.seek(float(key.get("beat", 0.0)))
				return
	for region in _app.chart.regions:
		var x0 := _beat_to_x(region.start_beat)
		var x1 := _beat_to_x(region.end_beat)
		if pos.x >= minf(x0, x1) - 2 and pos.x <= maxf(x0, x1) + 2 and pos.y >= 18:
			_app.select_region(region.id)
			return
	var beat: float = _app.snap_beat(_x_to_beat(pos.x), event.alt_pressed)
	_app.seek(beat)
