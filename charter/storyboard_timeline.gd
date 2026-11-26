class_name StoryboardTimeline
extends Control

## 故事板编辑器的时间轴（参考 Flash/Animate 的 Timeline 面板）：
## - 左侧是图层行（Background/Fail/Pass/Foreground/Overlay/Video），带显隐、锁定、展开
## - 展开后是这一层的 sprite 行；每一行画对象的生命周期和命令条
## - 顶部是时间标尺 + 播放头；底部是当前时间/总时长/帧率
##
## 3936 个 sprite 只画当前可见行（虚拟滚动），图层行聚合显示整层的覆盖范围。

signal seek(ms: float)
signal changed()
signal sprite_picked(index: int)
signal command_picked(index: int, command: Storyboard.Command)
signal layer_visibility_changed(layer: String, visible: bool)
signal layer_lock_changed(layer: String, locked: bool)
## 开始拖命令条（编辑器在这里压一次 undo 快照）。
signal drag_started()
## 命令条第一次真正移动（编辑器在这里压 undo，单纯按下不压）。
signal drag_moved()
signal drag_finished()

const HEADER_H := 24.0
const RULER_H := 24.0
const ROW_H := 18.0
const FOOTER_H := 24.0
const GUTTER := 196.0
const EDGE := 4.0
const LAYER_ORDER := ["Video", "Background", "Fail", "Pass", "Foreground", "Overlay"]


class PlayheadOverlay:
	extends Control

	var timeline: Control = null

	func _draw() -> void:
		if timeline != null and is_instance_valid(timeline):
			timeline.call("_draw_playhead_overlay", self)


var board: Storyboard = null
var chart: Chart = null
var span_ms := 60000.0
var view_from_ms := 0.0
var view_to_ms := -1.0
var playhead_ms := 0.0
var selected_index := -1
## 吸附：0 = 不吸附，>0 = 吸附到 1/N 拍
var snap_divisor := 4.0
## 播放时播放头跑出视野就跟着滚。
var follow_playhead := true
## 时间轴选项：L 块（只读）可以隐藏。
var show_blocks := true
var _menu: MenuButton = null
var _playhead_overlay: Control = null
## 计数供性能测试确认播放头更新不会失效静态轨道。
var _static_invalidations := 0
var _playhead_invalidations := 0

## 图层状态（只在编辑器里生效，不写回 .osb）。
var hidden_layers: Dictionary = {}
var locked_layers: Dictionary = {}
var expanded: Dictionary = {}

var _scroll := 0.0
## 行：{type: "layer"|"sprite", layer, index}
var _rows: Array[Dictionary] = []
var _layer_spans: Dictionary = {}
var _layer_counts: Dictionary = {}
var _drag_mode := 0  # 0=none 1=playhead 2=move 3=left 4=right 5=pan 6=hscroll
var _drag_sprite: Storyboard.Sprite = null
var _drag_command: Storyboard.Command = null
var _drag_start_ms := 0.0
var _drag_origin_start := 0.0
var _drag_origin_end := 0.0
var _drag_origin_x := 0.0
var _drag_origin_view := 0.0
var _drag_origin_scroll := 0.0


func _init() -> void:
	var overlay := PlayheadOverlay.new()
	overlay.name = "PlayheadOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.timeline = self
	add_child(overlay)
	_playhead_overlay = overlay


func _ready() -> void:
	custom_minimum_size = Vector2(0, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "点标尺/空白跳转播放头；拖命令条改时间；双击命令条跳到起点；眼睛=显隐，锁=只读，箭头=展开图层"
	_menu = MenuButton.new()
	_menu.text = "⋯"
	_menu.tooltip_text = "时间轴选项"
	var popup := _menu.get_popup()
	popup.add_item("适配全部", 1)
	popup.add_item("跳到开头", 2)
	popup.add_item("跳到结尾", 3)
	popup.add_check_item("跟随播放头", 4)
	popup.set_item_checked(popup.get_item_index(4), follow_playhead)
	popup.add_check_item("显示 L 块", 5)
	popup.set_item_checked(popup.get_item_index(5), show_blocks)
	popup.add_item("展开全部图层", 6)
	popup.add_item("折叠全部图层", 7)
	popup.id_pressed.connect(_on_menu)
	add_child(_menu)
	_layout_menu()
	_queue_timeline_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_menu()
		_queue_timeline_redraw()


func _layout_menu() -> void:
	if _menu != null:
		_menu.position = Vector2(size.x - 38.0, 1.0)


func _queue_timeline_redraw() -> void:
	_static_invalidations += 1
	queue_redraw()
	_queue_playhead_redraw()


func _queue_playhead_redraw() -> void:
	_playhead_invalidations += 1
	if _playhead_overlay != null and is_instance_valid(_playhead_overlay):
		_playhead_overlay.queue_redraw()


func _on_menu(id: int) -> void:
	match id:
		1:
			set_zoom(0.0, 0.0)
		2:
			playhead_ms = 0.0
			_queue_playhead_redraw()
			seek.emit(0.0)
		3:
			playhead_ms = span_ms
			_queue_playhead_redraw()
			seek.emit(span_ms)
		4:
			follow_playhead = not follow_playhead
			_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(4), follow_playhead)
		5:
			show_blocks = not show_blocks
			_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(5), show_blocks)
			_queue_timeline_redraw()
		6:
			for layer in LAYER_ORDER:
				expanded[layer] = true
			_rebuild_rows()
			_queue_timeline_redraw()
		7:
			for layer in LAYER_ORDER:
				expanded[layer] = false
			_rebuild_rows()
			_queue_timeline_redraw()


func set_chart(value: Chart) -> void:
	chart = value
	_recompute_span()
	_queue_timeline_redraw()


func set_board(value: Storyboard) -> void:
	board = value
	_rebuild_rows()
	_queue_timeline_redraw()


func set_selected(index: int) -> void:
	selected_index = index
	if index >= 0 and board != null and index < board.sprites.size():
		var layer := (board.sprites[index] as Storyboard.Sprite).layer
		if not expanded.get(layer, false):
			expanded[layer] = true
			_rebuild_rows()
	_ensure_visible(index)
	_queue_timeline_redraw()


func set_playhead(ms: float) -> void:
	var old_view_from := view_from_ms
	var old_view_to := view_to_ms
	playhead_ms = maxf(0.0, ms)
	if follow_playhead:
		var span := visible_span()
		if playhead_ms < view_from_ms or playhead_ms > view_from_ms + span:
			view_from_ms = maxf(0.0, playhead_ms - span * 0.1)
			view_to_ms = view_from_ms + span
	var view_changed := not is_equal_approx(view_from_ms, old_view_from) or not is_equal_approx(view_to_ms, old_view_to)
	if view_changed:
		_queue_timeline_redraw()
	else:
		_queue_playhead_redraw()


func set_zoom(from_ms: float, to_ms: float) -> void:
	view_from_ms = maxf(0.0, from_ms)
	if to_ms <= view_from_ms:
		to_ms = span_ms
	view_to_ms = maxf(view_from_ms + 200.0, to_ms)
	_queue_timeline_redraw()


func visible_span() -> float:
	return (view_to_ms - view_from_ms) if view_to_ms > view_from_ms else span_ms


func _recompute_span() -> void:
	var longest := 8000.0
	if board != null:
		for sprite in board.sprites:
			var s := sprite as Storyboard.Sprite
			for command in s.commands:
				longest = maxf(longest, (command as Storyboard.Command).end)
	if chart != null:
		longest = maxf(longest, chart.beat_to_ms(chart.content_end_beat()) - chart.offset_ms)
	span_ms = longest * 1.02 + 500.0
	if view_to_ms <= view_from_ms:
		view_from_ms = 0.0
		view_to_ms = span_ms


func _rebuild_rows() -> void:
	_rows.clear()
	_layer_spans.clear()
	_layer_counts.clear()
	if board == null:
		return
	var buckets: Dictionary = {}
	for i in board.sprites.size():
		var sprite := board.sprites[i] as Storyboard.Sprite
		var layer := sprite.layer if sprite.layer in LAYER_ORDER else "Background"
		_layer_counts[layer] = int(_layer_counts.get(layer, 0)) + 1
		if sprite.commands.is_empty():
			continue
		if not buckets.has(layer):
			buckets[layer] = []
		(buckets[layer] as Array).append(Vector2(sprite.start_time, sprite.end_time))
	for layer in LAYER_ORDER:
		var spans: Array = buckets.get(layer, [])
		_layer_spans[layer] = _merge_spans(spans)
		_rows.append({"type": "layer", "layer": layer})
		if not expanded.get(layer, false):
			continue
		for i in board.sprites.size():
			var sprite := board.sprites[i] as Storyboard.Sprite
			if sprite.layer == layer:
				_rows.append({"type": "sprite", "layer": layer, "index": i})
	_recompute_span()


## 图层行只画合并后的覆盖区间：3936 个 sprite 各自画一条会把时间轴拖慢。
static func _merge_spans(spans: Array) -> Array:
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array = []
	for raw in spans:
		var span := raw as Vector2
		if merged.is_empty():
			merged.append(span)
			continue
		var last: Vector2 = merged[merged.size() - 1]
		if span.x > last.y:
			merged.append(span)
		else:
			merged[merged.size() - 1] = Vector2(last.x, maxf(last.y, span.y))
	return merged


func _ensure_visible(index: int) -> void:
	for row in _rows.size():
		var item := _rows[row]
		if String(item["type"]) != "sprite" or int(item["index"]) != index:
			continue
		var visible_rows := _visible_row_count()
		if float(row) < _scroll:
			_scroll = float(row)
		elif float(row) >= _scroll + visible_rows:
			_scroll = float(row) - visible_rows + 1.0
		return


func _visible_row_count() -> float:
	return maxf(1.0, floor((size.y - HEADER_H - RULER_H - FOOTER_H) / ROW_H))


func _rows_top() -> float:
	return HEADER_H + RULER_H


func _rows_bottom() -> float:
	return size.y - FOOTER_H


func _ms_to_x(ms: float) -> float:
	var span := visible_span()
	var width := maxf(1.0, size.x - GUTTER - 10.0)
	return GUTTER + clampf((ms - view_from_ms) / span, 0.0, 1.0) * width


func _x_to_ms(x: float) -> float:
	var width := maxf(1.0, size.x - GUTTER - 10.0)
	return view_from_ms + clampf((x - GUTTER) / width, 0.0, 1.0) * visible_span()


## 吸附到 1/snap_divisor 拍。时间轴是 osb ms，谱面是 chart ms，差一个 offset。
func snap_ms(ms: float) -> float:
	if snap_divisor <= 0.0 or chart == null:
		return ms
	var beat := chart.ms_to_beat(maxf(0.0, ms + chart.offset_ms))
	var snapped := roundf(beat * snap_divisor) / snap_divisor
	return maxf(0.0, chart.beat_to_ms(maxf(0.0, snapped)) - chart.offset_ms)


func _row_at(y: float) -> int:
	if y < _rows_top() or y >= _rows_bottom():
		return -1
	var row := int(_scroll) + int(floor((y - _rows_top()) / ROW_H))
	return row if row >= 0 and row < _rows.size() else -1


func _row_y(row: int) -> float:
	return _rows_top() + float(row - int(_scroll)) * ROW_H


## 图层行的三个小按钮：眼睛 / 锁 / 展开箭头。
func _layer_button_at(x: float) -> String:
	if x >= 4.0 and x < 22.0:
		return "eye"
	if x >= 24.0 and x < 42.0:
		return "lock"
	if x >= 44.0 and x < 60.0:
		return "expand"
	return ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.095, 1.0))
	# 顶部标题栏
	draw_rect(Rect2(0.0, 0.0, size.x, HEADER_H), Color(0.10, 0.11, 0.13, 1.0))
	draw_string(UITheme.FONT_REGULAR, Vector2(8.0, 16.0), "时间轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.82, 0.86, 0.9, 1.0))
	draw_string(UITheme.FONT_REGULAR, Vector2(GUTTER + 8.0, 16.0), _ruler_text(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.66, 1.0))
	# 标尺
	draw_rect(Rect2(0.0, HEADER_H, size.x, RULER_H), Color(0.10, 0.11, 0.13, 1.0))
	var step := _pick_step()
	var t: float = floor(view_from_ms / step) * step
	while t <= view_from_ms + visible_span():
		var x := _ms_to_x(t)
		draw_line(Vector2(x, HEADER_H), Vector2(x, HEADER_H + RULER_H), Color(0.3, 0.32, 0.36, 1.0), 1.0)
		draw_string(UITheme.FONT_REGULAR, Vector2(x + 3.0, HEADER_H + 15.0), _fmt_tick(t),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.62, 0.66, 0.7, 1.0))
		t += step
	# 左侧栏图标含义（标尺左侧的空白处）
	draw_string(UITheme.FONT_REGULAR, Vector2(6.0, HEADER_H + 16.0), "显/隐   锁   展开",
		HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 12.0, 9, Color(0.5, 0.54, 0.6, 1.0))
	# 行
	draw_rect(Rect2(0.0, _rows_top(), GUTTER, _rows_bottom() - _rows_top()), Color(0.085, 0.095, 0.11, 1.0))
	if _rows.is_empty():
		draw_string(UITheme.FONT_REGULAR, Vector2(10.0, _rows_top() + 20.0), "（还没有对象）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.53, 0.56, 1.0))
	else:
		var first := int(floor(_scroll))
		var count := int(ceil(_visible_row_count())) + 1
		for row in range(first, mini(first + count, _rows.size())):
			var data := _rows[row]
			var y := _row_y(row)
			if y + ROW_H < _rows_top() or y > _rows_bottom():
				continue
			if String(data["type"]) == "layer":
				_draw_layer_row(data, row, y)
			else:
				_draw_sprite_row(data, row, y)
	# 底栏背景是静态内容；动态文字和滚动条由覆盖层重画。
	draw_rect(Rect2(0.0, _rows_bottom(), size.x, FOOTER_H), Color(0.10, 0.11, 0.13, 1.0))


func _draw_playhead_overlay(canvas: CanvasItem) -> void:
	var px := _ms_to_x(playhead_ms)
	if px >= GUTTER and playhead_ms >= view_from_ms and playhead_ms <= view_from_ms + visible_span():
		canvas.draw_line(Vector2(px, HEADER_H), Vector2(px, _rows_bottom()), Color(1.0, 0.32, 0.38, 0.95), 1.5)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(px - 4.0, HEADER_H + 1.0), Vector2(px + 4.0, HEADER_H + 1.0), Vector2(px, HEADER_H + 8.0),
		]), Color(1.0, 0.32, 0.38, 1.0))
		# 原来底栏背景画在播放头之后；覆盖层最后绘制时重涂播放头端点，保持原来的遮挡。
		canvas.draw_rect(Rect2(px - 1.0, _rows_bottom(), 2.0, FOOTER_H), Color(0.10, 0.11, 0.13, 1.0))
	_draw_scrollbar(canvas)
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(8.0, _rows_bottom() + 16.0), _footer_text(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.66, 0.7, 0.75, 1.0))
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(size.x - 250.0, _rows_bottom() + 16.0),
		"滚轮滚动 · Ctrl+滚轮缩放 · Shift+滚轮平移", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(0.45, 0.49, 0.54, 1.0))


func _draw_layer_row(data: Dictionary, row: int, y: float) -> void:
	var layer := String(data["layer"])
	var row_rect := Rect2(0.0, y, size.x, ROW_H)
	draw_rect(row_rect, Color(0.12, 0.13, 0.16, 1.0))
	if row == int(_scroll):
		draw_rect(row_rect, Color(0.16, 0.18, 0.22, 0.55))
	# 眼睛
	var hidden := hidden_layers.has(layer)
	_draw_eye(Vector2(13.0, y + ROW_H * 0.5), hidden)
	# 锁
	var locked := locked_layers.has(layer)
	_draw_lock(Vector2(33.0, y + ROW_H * 0.5), locked)
	# 展开箭头
	var open := bool(expanded.get(layer, false))
	_draw_arrow(Vector2(52.0, y + ROW_H * 0.5), open)
	# 图层名 + 数量
	var label := "%s  %d" % [LayerName.zh(layer), int(_layer_counts.get(layer, 0))]
	draw_string(UITheme.FONT_REGULAR, Vector2(66.0, y + 12.5), label,
		HORIZONTAL_ALIGNMENT_LEFT, 124.0, 10,
		Color(0.5, 0.54, 0.6, 1.0) if (hidden or locked) else Color(0.86, 0.89, 0.93, 1.0))
	# 整层覆盖范围：细条 + 命令起点刻度
	var spans: Array = _layer_spans.get(layer, [])
	var bar_y := y + ROW_H - 6.0
	for raw in spans:
		var span := raw as Vector2
		var x0 := _ms_to_x(span.x)
		var x1 := maxf(x0 + 1.0, _ms_to_x(span.y))
		if x1 < GUTTER or x0 > size.x:
			continue
		draw_rect(Rect2(maxf(x0, GUTTER), bar_y, maxf(1.0, minf(x1, size.x) - maxf(x0, GUTTER)), 2.0),
			Color(0.35, 0.55, 0.72, 0.75))
	draw_line(Vector2(0.0, y + ROW_H), Vector2(size.x, y + ROW_H), Color(0.16, 0.18, 0.21, 0.8), 1.0)


func _draw_sprite_row(data: Dictionary, row: int, y: float) -> void:
	var index := int(data["index"])
	if board == null or index < 0 or index >= board.sprites.size():
		return
	var sprite := board.sprites[index] as Storyboard.Sprite
	var layer := sprite.layer
	var locked := locked_layers.has(layer)
	var selected := index == selected_index
	var row_rect := Rect2(0.0, y, size.x, ROW_H)
	if selected:
		draw_rect(row_rect, Color(0.20, 0.23, 0.28, 1.0))
	# 缩进 + 文件名
	var label := sprite.path.get_file() if not sprite.path.is_empty() else "(未填路径)"
	if sprite.commands.is_empty():
		label += "  ⚠"
	draw_string(UITheme.FONT_REGULAR, Vector2(66.0, y + 12.5), label, HORIZONTAL_ALIGNMENT_LEFT, 122.0, 9,
		Color(0.48, 0.52, 0.57, 1.0) if locked else (Color(0.96, 0.98, 1.0, 1.0) if selected else Color(0.7, 0.74, 0.79, 1.0)))
	# 命令条
	for command in sprite.commands:
		var c := command as Storyboard.Command
		if c.in_block and not show_blocks:
			continue
		if c.end < view_from_ms or c.start > view_from_ms + visible_span():
			continue
		var x0 := _ms_to_x(c.start)
		var x1 := maxf(x0 + 1.5, _ms_to_x(c.end))
		var rect := Rect2(maxf(x0, GUTTER), y + 2.0, maxf(2.0, x1 - maxf(x0, GUTTER)), ROW_H - 5.0)
		if c.in_block:
			# L 块展开出来的副本：只读，斜线标记。
			draw_rect(rect, Color(0.35, 0.38, 0.44, 0.45))
			var step := 6.0
			var sx := rect.position.x - rect.size.y
			while sx < rect.end.x:
				draw_line(Vector2(sx, rect.end.y), Vector2(sx + rect.size.y, rect.position.y),
					Color(0.55, 0.58, 0.64, 0.35), 1.0)
				sx += step
			continue
		var colour := _kind_colour(c.kind_name)
		colour.a = 0.92 if selected else 0.6
		if locked:
			colour.a *= 0.45
		draw_rect(rect, colour)
		# 起止关键帧：菱形
		_draw_diamond(Vector2(x0, y + ROW_H * 0.5), 3.0, Color(0.98, 0.98, 1.0, 0.9 if not locked else 0.4))
		if x1 > x0 + 2.0:
			_draw_diamond(Vector2(x1, y + ROW_H * 0.5), 3.0, Color(0.98, 0.98, 1.0, 0.55 if not locked else 0.25))
		if c == _drag_command:
			draw_rect(rect, Color(1.0, 0.9, 0.4, 1.0), false, 1.5)
	draw_line(Vector2(0.0, y + ROW_H), Vector2(size.x, y + ROW_H), Color(0.13, 0.15, 0.18, 0.6), 1.0)


func _draw_eye(center: Vector2, hidden: bool) -> void:
	var colour := Color(0.35, 0.4, 0.46, 1.0) if hidden else Color(0.62, 0.86, 0.9, 1.0)
	draw_arc(center, 5.0, 0.0, TAU, 14, colour, 1.0)
	draw_circle(center, 2.0, colour)
	if hidden:
		draw_line(center + Vector2(-6, -6), center + Vector2(6, 6), Color(0.9, 0.35, 0.4, 1.0), 1.5)


func _draw_lock(center: Vector2, locked: bool) -> void:
	var colour := Color(0.95, 0.72, 0.35, 1.0) if locked else Color(0.35, 0.4, 0.46, 1.0)
	draw_rect(Rect2(center + Vector2(-4, -1), Vector2(8, 7)), colour, false, 1.0)
	if locked:
		draw_arc(center + Vector2(0, -2), 3.0, PI, TAU, 8, colour, 1.0)


func _draw_arrow(center: Vector2, open: bool) -> void:
	var colour := Color(0.6, 0.66, 0.72, 1.0)
	if open:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-4, -2), center + Vector2(4, -2), center + Vector2(0, 3),
		]), colour)
	else:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-2, -4), center + Vector2(-2, 4), center + Vector2(3, 0),
		]), colour)


func _draw_diamond(center: Vector2, radius: float, colour: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0),
	]), colour)


func _draw_scrollbar(canvas: CanvasItem) -> void:
	var width := size.x - GUTTER - 10.0
	if width <= 1.0:
		return
	var y := size.y - FOOTER_H - 5.0
	canvas.draw_rect(Rect2(GUTTER, y, width, 3.0), Color(0.16, 0.18, 0.21, 1.0))
	var ratio := clampf(visible_span() / maxf(1.0, span_ms), 0.02, 1.0)
	var left := clampf(view_from_ms / maxf(1.0, span_ms), 0.0, 1.0)
	var bar_w := maxf(18.0, width * ratio)
	var bar_x := GUTTER + clampf(left * width, 0.0, width - bar_w)
	canvas.draw_rect(Rect2(bar_x, y - 1.0, bar_w, 5.0), Color(0.42, 0.46, 0.52, 1.0))


func _pick_step() -> float:
	var span := visible_span()
	for step in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 30000.0, 60000.0]:
		if span / step <= 10.0:
			return step
	return 60000.0


static func _fmt_tick(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%d:%02d" % [total / 60, total % 60]


static func _fmt_time(ms: float) -> String:
	var total := maxf(0.0, ms)
	var minutes := int(total / 60000.0)
	var seconds := int(fmod(total, 60000.0) / 1000.0)
	var millis := int(fmod(total, 1000.0))
	return "%d:%02d.%03d" % [minutes, seconds, millis]


func _ruler_text() -> String:
	return "点标尺/空白跳转 · L 块只读"


func _footer_text() -> String:
	var beat := 0.0
	if chart != null:
		beat = chart.ms_to_beat(maxf(0.0, playhead_ms + chart.offset_ms))
	var snap := "关" if snap_divisor <= 0.0 else "1/%d 拍" % int(snap_divisor)
	return "当前 %s  ·  %.2f 拍  ·  总长 %s  ·  %d FPS  ·  吸附 %s  ·  可见 %d 行" % [
		_fmt_time(playhead_ms), beat, _fmt_time(span_ms), int(Engine.get_frames_per_second()),
		snap, int(_visible_row_count())]


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
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var direction := -1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if button.ctrl_pressed:
					var center := _x_to_ms(button.position.x)
					var span := visible_span()
					var factor := 0.85 if direction < 0.0 else 1.18
					var new_span := clampf(span * factor, 500.0, span_ms * 1.2)
					var ratio := (center - view_from_ms) / span
					view_from_ms = maxf(0.0, center - new_span * ratio)
					view_to_ms = view_from_ms + new_span
				elif button.shift_pressed:
					var shift := visible_span() * 0.12 * direction
					view_from_ms = clampf(view_from_ms + shift, 0.0, maxf(0.0, span_ms - visible_span()))
					view_to_ms = view_from_ms + visible_span()
				else:
					_scroll = clampf(_scroll + direction, 0.0,
						maxf(0.0, float(_rows.size()) - _visible_row_count()))
				_queue_timeline_redraw()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_mode = 5 if button.pressed else 0
			_drag_origin_x = button.position.x
			_drag_origin_view = view_from_ms
			accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin_drag(button.position, button.double_click)
		else:
			if _drag_mode != 0:
				var redraw_static := _drag_mode != 1
				_drag_mode = 0
				_drag_command = null
				_drag_sprite = null
				_recompute_span()
				drag_finished.emit()
				if redraw_static:
					_queue_timeline_redraw()
				else:
					_queue_playhead_redraw()
				accept_event()
		return
	if event is InputEventMouseMotion and _drag_mode != 0:
		_drag_to((event as InputEventMouseMotion).position)
		accept_event()


func _begin_drag(pos: Vector2, double_click: bool = false) -> void:
	# 标尺 / 标尺以下的空白：跳播放头
	if pos.y < _rows_top() or pos.y >= _rows_bottom():
		if pos.y >= _rows_bottom() - 8.0:
			_drag_mode = 6
			_drag_origin_x = pos.x
			_drag_origin_view = view_from_ms
			accept_event()
			return
		_drag_mode = 1
		playhead_ms = snap_ms(_x_to_ms(pos.x))
		seek.emit(playhead_ms)
		_queue_playhead_redraw()
		accept_event()
		return
	var row := _row_at(pos.y)
	if row < 0:
		_drag_mode = 1
		playhead_ms = snap_ms(_x_to_ms(pos.x))
		seek.emit(playhead_ms)
		_queue_playhead_redraw()
		accept_event()
		return
	var data := _rows[row]
	if String(data["type"]) == "layer":
		var layer := String(data["layer"])
		# 左侧栏：眼睛 / 锁 / 展开；右侧时间区：跳播放头。
		var hit := _layer_button_at(pos.x) if pos.x < GUTTER else ""
		var redraw_static := true
		if hit == "eye":
			# 用 erase 表示“关”：留一个 false 值进去后 has() 仍然为真，
			# 第二次点眼睛就永远取消不掉隐藏。
			if hidden_layers.has(layer):
				hidden_layers.erase(layer)
			else:
				hidden_layers[layer] = true
			layer_visibility_changed.emit(layer, not hidden_layers.has(layer))
		elif hit == "lock":
			if locked_layers.has(layer):
				locked_layers.erase(layer)
			else:
				locked_layers[layer] = true
			layer_lock_changed.emit(layer, locked_layers.has(layer))
		elif pos.x < GUTTER:
			expanded[layer] = not bool(expanded.get(layer, false))
			_rebuild_rows()
		else:
			_drag_mode = 1
			playhead_ms = snap_ms(_x_to_ms(pos.x))
			seek.emit(playhead_ms)
			redraw_static = false
		if redraw_static:
			_queue_timeline_redraw()
		else:
			_queue_playhead_redraw()
		accept_event()
		return
	var index := int(data["index"])
	var sprite := board.sprites[index] as Storyboard.Sprite
	var layer := sprite.layer
	if locked_layers.has(layer):
		return
	var ms := _x_to_ms(pos.x)
	var row_y := _row_y(row)
	# 点命令条：选中对象 + 选中命令；拖条改时间。
	for command in sprite.commands:
		var c := command as Storyboard.Command
		var x0 := _ms_to_x(c.start)
		var x1 := maxf(x0 + 1.5, _ms_to_x(c.end))
		# 瞬时命令（start == end）只有 1.5px 宽，给它一个 8px 的可点范围。
		if pos.x < x0 - 4.0 or pos.x > maxf(x1, x0 + 8.0) + 4.0:
			continue
		selected_index = index
		sprite_picked.emit(index)
		command_picked.emit(index, c)
		if c.in_block:
			# L 块展开副本只读，不拖。
			_queue_timeline_redraw()
			accept_event()
			return
		if double_click:
			# 双击命令条：跳到这条命令的起点，而不是跟着拖动改时间。
			playhead_ms = c.start
			seek.emit(c.start)
			_queue_timeline_redraw()
			accept_event()
			return
		drag_started.emit()
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
		_queue_timeline_redraw()
		accept_event()
		return
	# 空白：跳播放头并选中这一行
	_drag_mode = 1
	selected_index = index
	sprite_picked.emit(index)
	playhead_ms = snap_ms(ms)
	seek.emit(playhead_ms)
	_queue_timeline_redraw()
	accept_event()


## Esc 取消当前拖动：把命令条恢复到按下时的起止时间。
## 返回 true 表示确实有东西被取消（编辑器据此决定要不要回滚快照）。
func cancel_drag() -> bool:
	if _drag_mode == 0:
		return false
	var redraw_static := _drag_mode != 1
	if _drag_mode >= 2 and _drag_mode <= 4 and _drag_command != null and _drag_sprite != null:
		_drag_command.start = _drag_origin_start
		_drag_command.end = _drag_origin_end
		_drag_sprite.build()
	_drag_mode = 0
	_drag_command = null
	_drag_sprite = null
	if redraw_static:
		_queue_timeline_redraw()
	else:
		_queue_playhead_redraw()
	return true


func _drag_to(pos: Vector2) -> void:
	if _drag_mode == 5:
		view_from_ms = clampf(_drag_origin_view - (pos.x - _drag_origin_x) / maxf(1.0, size.x - GUTTER) * visible_span(),
			0.0, maxf(0.0, span_ms - visible_span()))
		view_to_ms = view_from_ms + visible_span()
		_queue_timeline_redraw()
		return
	if _drag_mode == 6:
		var width := maxf(1.0, size.x - GUTTER - 10.0)
		var shift := (pos.x - _drag_origin_x) / width * span_ms
		view_from_ms = clampf(_drag_origin_view + shift, 0.0, maxf(0.0, span_ms - visible_span()))
		view_to_ms = view_from_ms + visible_span()
		_queue_timeline_redraw()
		return
	var ms := snap_ms(_x_to_ms(pos.x))
	if _drag_mode == 1:
		playhead_ms = ms
		seek.emit(playhead_ms)
		_queue_playhead_redraw()
		return
	if _drag_command == null or _drag_sprite == null:
		return
	var delta := ms - _drag_start_ms
	if _drag_mode >= 2 and _drag_mode <= 4:
		drag_moved.emit()
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
	_queue_timeline_redraw()
	changed.emit()


## 图层中文名（时间轴和画布共用）。
class LayerName:
	static func zh(layer: String) -> String:
		match layer:
			"Video":
				return "视频"
			"Background":
				return "背景"
			"Fail":
				return "失败层"
			"Pass":
				return "通过层"
			"Foreground":
				return "前景"
			"Overlay":
				return "覆盖层"
		return layer
