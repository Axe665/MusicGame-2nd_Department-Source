class_name StoryboardTimeline
extends Control

## 故事板编辑器的时间轴（多对象视图）：
## 每一行 = 一个对象，行上画它的命令条；顶部刻度可拖播放头。
##
## 交互：
## - 点/拖顶部刻度区 → 移动播放头（发 seek）
## - 拖命令条中间 → 整条平移；拖左右边缘 → 只改起点 / 终点
## - 点命令条 → 选中该对象（发 sprite_picked）
## - 滚轮 → 上下滚动对象行
## - 按住 Ctrl 滚轮 → 横向缩放时间轴

signal seek(ms: float)
signal changed()
signal sprite_picked(index: int)

const RULER_H := 22.0
const ROW_H := 16.0
const EDGE := 4.0
const GUTTER := 88.0
const LAYER_ORDER := ["Video", "Background", "Fail", "Pass", "Foreground", "Overlay"]

var board: Storyboard = null
var chart: Chart = null
var span_ms := 60000.0
var view_from_ms := 0.0
var view_to_ms := -1.0
var playhead_ms := 0.0
var selected_index := -1
## 吸附：0 = 不吸附，>0 = 吸附到 1/N 拍
var snap_divisor := 4.0

var _scroll := 0.0
var _rows: Array[int] = []
var _drag_mode := 0  # 0=none 1=playhead 2=move 3=left 4=right
var _drag_sprite: Storyboard.Sprite = null
var _drag_command: Storyboard.Command = null
var _drag_start_ms := 0.0
var _drag_origin_start := 0.0
var _drag_origin_end := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_chart(value: Chart) -> void:
	chart = value
	queue_redraw()


func set_board(value: Storyboard) -> void:
	board = value
	_rebuild_rows()
	queue_redraw()


func set_selected(index: int) -> void:
	selected_index = index
	_ensure_visible(index)
	queue_redraw()


func set_playhead(ms: float) -> void:
	playhead_ms = maxf(0.0, ms)
	queue_redraw()


func set_zoom(from_ms: float, to_ms: float) -> void:
	view_from_ms = maxf(0.0, from_ms)
	if to_ms <= view_from_ms:
		to_ms = span_ms
	view_to_ms = maxf(view_from_ms + 200.0, to_ms)
	queue_redraw()


func visible_span() -> float:
	return (view_to_ms - view_from_ms) if view_to_ms > view_from_ms else span_ms


func _rebuild_rows() -> void:
	_rows.clear()
	if board == null:
		return
	var order := {}
	for i in LAYER_ORDER.size():
		order[LAYER_ORDER[i]] = i
	var pairs: Array = []
	for i in board.sprites.size():
		var sprite := board.sprites[i] as Storyboard.Sprite
		pairs.append({"index": i, "layer": int(order.get(sprite.layer, LAYER_ORDER.size())), "order": sprite.order})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["layer"]) != int(b["layer"]):
			return int(a["layer"]) < int(b["layer"])
		return int(a["order"]) < int(b["order"]))
	for pair in pairs:
		_rows.append(int(pair["index"]))
	_recompute_span()


func _recompute_span() -> void:
	var longest := 8000.0
	if board != null:
		for sprite in board.sprites:
			var s := sprite as Storyboard.Sprite
			for command in s.commands:
				longest = maxf(longest, (command as Storyboard.Command).end)
	span_ms = longest * 1.05 + 500.0
	if view_to_ms <= view_from_ms:
		view_from_ms = 0.0
		view_to_ms = span_ms


func _ensure_visible(index: int) -> void:
	var row := _rows.find(index)
	if row < 0:
		return
	var visible_rows := maxf(1.0, floor((size.y - RULER_H) / ROW_H))
	if float(row) < _scroll:
		_scroll = float(row)
	elif float(row) >= _scroll + visible_rows:
		_scroll = float(row) - visible_rows + 1.0


func _ms_to_x(ms: float) -> float:
	var span := visible_span()
	var width := maxf(1.0, size.x - GUTTER)
	return GUTTER + clampf((ms - view_from_ms) / span, 0.0, 1.0) * width


func _x_to_ms(x: float) -> float:
	var width := maxf(1.0, size.x - GUTTER)
	return view_from_ms + clampf((x - GUTTER) / width, 0.0, 1.0) * visible_span()


## 吸附到 1/snap_divisor 拍（用谱面的 BPM 表算）。
func snap_ms(ms: float) -> float:
	if snap_divisor <= 0.0 or chart == null:
		return ms
	var beat := chart.ms_to_beat(maxf(0.0, ms))
	var snapped := roundf(beat * snap_divisor) / snap_divisor
	return chart.beat_to_ms(maxf(0.0, snapped))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.09, 1.0))
	draw_rect(Rect2(0.0, 0.0, size.x, RULER_H), Color(0.11, 0.12, 0.13, 1.0))
	var step := _pick_step()
	var t: float = floor(view_from_ms / step) * step
	while t <= view_from_ms + visible_span():
		var x := _ms_to_x(t)
		draw_line(Vector2(x, 0.0), Vector2(x, RULER_H), Color(0.3, 0.32, 0.34, 1.0), 1.0)
		draw_line(Vector2(x, RULER_H), Vector2(x, size.y), Color(0.15, 0.16, 0.18, 1.0), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(x + 3.0, 15.0), _fmt_time(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.62, 0.66, 0.7, 1.0))
		t += step
	if board == null or _rows.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(10.0, RULER_H + 20.0), "（还没有对象）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.53, 0.56, 1.0))
	else:
		var first := int(floor(_scroll))
		var count := int(ceil((size.y - RULER_H) / ROW_H))
		for row in range(first, mini(first + count + 1, _rows.size())):
			var y := RULER_H + float(row - first) * ROW_H
			var index := _rows[row]
			var sprite := board.sprites[index] as Storyboard.Sprite
			var selected := index == selected_index
			if selected:
				draw_rect(Rect2(0.0, y, size.x, ROW_H), Color(0.18, 0.2, 0.24, 1.0))
			draw_string(ThemeDB.fallback_font, Vector2(2.0, y + 11.0), sprite.path.get_file(), HORIZONTAL_ALIGNMENT_LEFT, 90.0, 9,
				Color(0.85, 0.88, 0.92, 1.0) if selected else Color(0.55, 0.58, 0.62, 1.0))
			for command in sprite.commands:
				var c := command as Storyboard.Command
				if c.end < view_from_ms or c.start > view_from_ms + visible_span():
					continue
				var x0 := _ms_to_x(c.start)
				var x1 := maxf(x0 + 1.5, _ms_to_x(c.end))
				var rect := Rect2(x0, y + 1.0, x1 - x0, ROW_H - 3.0)
				var colour := _kind_colour(c.kind_name)
				colour.a = 0.9 if selected else 0.55
				draw_rect(rect, colour)
				if c == _drag_command:
					draw_rect(rect, Color(1.0, 0.9, 0.4, 1.0), false, 1.5)
	var px := _ms_to_x(playhead_ms)
	draw_line(Vector2(px, 0.0), Vector2(px, size.y), Color(1.0, 0.35, 0.4, 1.0), 1.5)
	draw_circle(Vector2(px, 6.0), 3.5, Color(1.0, 0.35, 0.4, 1.0))


func _pick_step() -> float:
	var span := visible_span()
	for step in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 30000.0, 60000.0]:
		if span / step <= 10.0:
			return step
	return 60000.0


static func _fmt_time(ms: float) -> String:
	return "%.1fs" % (ms / 1000.0)


static func _kind_colour(kind: String) -> Color:
	match kind:
		"alpha":
			return Color(0.55, 0.78, 1.0)
		"move", "x", "y":
			return Color(0.55, 0.95, 0.7)
		"scale", "vector":
			return Color(1.0, 0.85, 0.55)
		"rotation":
			return Color(0.9, 0.7, 1.0)
		"colour":
			return Color(1.0, 0.6, 0.6)
		"additive":
			return Color(0.8, 0.8, 0.8)
	return Color(0.7, 0.7, 0.7)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.index == MOUSE_BUTTON_WHEEL_UP or button.index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var direction := -1.0 if button.index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if button.ctrl_pressed:
					var center := _x_to_ms(button.position.x)
					var span := visible_span()
					var factor := 0.85 if direction < 0.0 else 1.18
					var new_span := clampf(span * factor, 500.0, span_ms * 1.2)
					var ratio := (center - view_from_ms) / span
					view_from_ms = maxf(0.0, center - new_span * ratio)
					view_to_ms = view_from_ms + new_span
				else:
					_scroll = clampf(_scroll + direction, 0.0, maxf(0.0, float(_rows.size()) - 3.0))
				queue_redraw()
			accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin_drag(button.position)
		else:
			if _drag_mode != 0:
				_drag_mode = 0
				_drag_command = null
				_drag_sprite = null
				accept_event()
				changed.emit()
		return
	if event is InputEventMouseMotion and _drag_mode != 0:
		_drag_to((event as InputEventMouseMotion).position)
		accept_event()


func _row_at(y: float) -> int:
	if y < RULER_H:
		return -1
	var row := int(_scroll) + int(floor((y - RULER_H) / ROW_H))
	return row if row >= 0 and row < _rows.size() else -1


func _begin_drag(pos: Vector2) -> void:
	if pos.y < RULER_H:
		_drag_mode = 1
		playhead_ms = snap_ms(_x_to_ms(pos.x))
		seek.emit(playhead_ms)
		queue_redraw()
		accept_event()
		return
	var row := _row_at(pos.y)
	if row < 0:
		return
	var index := _rows[row]
	var sprite := board.sprites[index] as Storyboard.Sprite
	var ms := _x_to_ms(pos.x)
	var row_y := RULER_H + float(row - int(_scroll)) * ROW_H
	for command in sprite.commands:
		var c := command as Storyboard.Command
		var x0 := _ms_to_x(c.start)
		var x1 := maxf(x0 + 1.5, _ms_to_x(c.end))
		if pos.x < x0 - 2.0 or pos.x > x1 + 2.0:
			continue
		_drag_sprite = sprite
		_drag_command = c
		_drag_origin_start = c.start
		_drag_origin_end = c.end
		_drag_start_ms = ms
		_drag_mode = 2
		if pos.x - x0 <= EDGE:
			_drag_mode = 3
		elif x1 - pos.x <= EDGE:
			_drag_mode = 4
		if index != selected_index:
			selected_index = index
			sprite_picked.emit(index)
		queue_redraw()
		accept_event()
		return
	# 空白：跳播放头
	_drag_mode = 1
	playhead_ms = snap_ms(ms)
	seek.emit(playhead_ms)
	if index != selected_index:
		selected_index = index
		sprite_picked.emit(index)
	queue_redraw()
	accept_event()


func _drag_to(pos: Vector2) -> void:
	var ms := snap_ms(_x_to_ms(pos.x))
	if _drag_mode == 1:
		playhead_ms = ms
		seek.emit(playhead_ms)
		queue_redraw()
		return
	if _drag_command == null or _drag_sprite == null:
		return
	var delta := ms - _drag_start_ms
	match _drag_mode:
		2:
			var length := _drag_origin_end - _drag_origin_start
			var new_start := maxf(0.0, _drag_origin_start + delta)
			_drag_command.start = snap_ms(new_start)
			_drag_command.end = _drag_command.start + length
		3:
			_drag_command.start = clampf(snap_ms(_drag_origin_start + delta), 0.0, _drag_command.end)
		4:
			_drag_command.end = maxf(_drag_command.start, snap_ms(_drag_origin_end + delta))
	_drag_sprite.build()
	queue_redraw()
	changed.emit()
