class_name RingWorkspace
extends Control

## 环编辑工作区：形状关键帧 + 形变时间轴 + 镜头，一屏直操作。
## 形状关键帧是唯一真源；v1/v2 的旧 BoundaryEvent 只读兼容，不再双写。

signal closed
signal play_toggled
signal loop_requested(start: float, end: float, enabled: bool)

const MIN_VIEW_BEATS := 1.0
const MAX_VIEW_BEATS := 4096.0
const THUMB_SIZE := Vector2(64, 64)


## 一段关键帧的长度文字：不足 1 小节写拍，超过写「N 小节 M 拍」。
static func span_label(beats: float, bpb: float) -> String:
	bpb = maxf(1.0, bpb)
	var bars := floori(beats / bpb + 0.0001)
	var rest := beats - float(bars) * bpb
	if bars <= 0:
		return "%s 拍" % _beat_num(rest)
	if rest < 0.005:
		return "%d 小节" % bars
	return "%d 小节 %s 拍" % [bars, _beat_num(rest)]


## 页脚用的 m:ss.mmm。ring 时间轴是拍，这里是谱面毫秒。
static func _fmt_clock(ms: float) -> String:
	var total := maxf(0.0, ms)
	var minutes := int(total / 60000.0)
	var seconds := int(fmod(total, 60000.0) / 1000.0)
	var millis := int(fmod(total, 1000.0))
	return "%d:%02d.%03d" % [minutes, seconds, millis]


## 标尺上的 m:ss（不带毫秒）：小节号和秒数并排，一屏内能对上时间。
static func _fmt_short(ms: float) -> String:
	var total := maxf(0.0, ms)
	return "%d:%02d" % [int(total / 60000.0), int(fmod(total, 60000.0) / 1000.0)]


static func _beat_num(value: float) -> String:
	var snapped := snappedf(value, 0.01)
	if absf(snapped - round(snapped)) < 0.001:
		return str(int(round(snapped)))
	return String.num(snapped, 2)


## 第 index 帧的保持段到哪结束：下一帧，或最后一个内容/音频结束；空谱至少留 1 小节。
static func span_end(beats: Array, index: int, content_end: float, bpb: float) -> float:
	if index < 0 or index >= beats.size():
		return 0.0
	var start := float(beats[index])
	if index + 1 < beats.size():
		return float(beats[index + 1])
	var end := maxf(start, content_end)
	if end - start < 0.001:
		end = start + maxf(1.0, bpb)
	return end


var _app: Node = null
var _preview: Preview3D = null
var _preview_slot: Control = null
var _restore_preview: Callable = Callable()
var _thumbs: GridContainer = null
var _panel: VBoxContainer = null
var _inspector: RingInspector = null
var _timeline: RingTimeline = null
var _title: Label = null
var _beat_spin: SpinBox = null
var _time_label: Label = null
var _fps_label: Label = null
var _fps_accum := 0.0
## 时间轴窗口宽度（拍）。Ctrl+滚轮连续缩放，不再使用固定档位。
var _view_beats := 16.0
var _zoom_label: Label = null
## 播放时时间轴是否跟着播放头滚（时间轴选项里可关）。
var follow_playhead_view := true
var _view_start := 0.0
var onion_skin := false
var onion_range := 2
var _play_button: Button = null
var _loop_button: Button = null
var _loop_on := false
var _pad: ShapePadOverlay = null
var _insert_menu: PopupMenu = null
var _shape_pick: PopupMenu = null

var _thumb_signature := ""
var _drag_kind := ""
var _drag_key: Dictionary = {}
var _drag_view: ViewState = null
var _last_key_beat: float = -999.0
var _sync_last_msec: int = 0
var _sync_last_beat: float = -99999.0
var _sync_last_spin: float = -99999.0
## 拖动关键帧期间冻结内容末尾，避免每帧 mark_dirty 重扫 10k 音符。
var _drag_content_end: float = -1.0
## 滑杆/滚轮等连续手势结束后恢复音符层；拖关键帧走 begin/end_preview_drag。
var _preview_gesture_timer: Timer = null


class ShapeThumb:
	extends Control
	var workspace: RingWorkspace
	var shape_id: String = ""
	var selected := false

	func _init(p_workspace: RingWorkspace, p_id: String) -> void:
		workspace = p_workspace
		shape_id = p_id
		custom_minimum_size = RingWorkspace.THUMB_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = p_id

	func _draw() -> void:
		var chart: Chart = workspace.chart()
		if chart == null:
			return
		var shape := chart.get_shape(shape_id)
		if shape == null:
			return
		if shape_id == chart.default_shape_id:
			tooltip_text = shape_id + "（基础圆，锁定）"
		else:
			tooltip_text = shape_id
		var center := size * 0.5
		var scale := minf(size.x, size.y) * 0.42 / 400.0
		var points := PackedVector2Array()
		for i in 73:
			var data := shape.point_at(float(i) / 72.0)
			if bool(data.get("gap", false)):
				continue
			points.append(center + (data.point as Vector2) * scale)
		var locked := shape_id == chart.default_shape_id
		var tint := UITheme.MUTED if locked else (UITheme.CORAL if selected else UITheme.CYAN)
		if points.size() > 1:
			draw_polyline(points, tint, 2.0, true)
		if selected and not locked:
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.CORAL, false, 1.0)
		if locked:
			draw_string(UITheme.FONT_REGULAR, Vector2(size.x - 14, 13), "锁",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.42))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if workspace.chart() != null and shape_id == workspace.chart().default_shape_id:
				workspace._set_hint("基础圆 S0 已锁定；点「复制」建一个可编辑的形状。")
			else:
				workspace.open_pad_for_shape(shape_id)
			accept_event()


class ShapePadOverlay:
	extends Control
	var workspace: RingWorkspace
	var shape_id: String = ""
	var shape: BoundaryShape = null
	var _drag_vertex := -1
	var _canvas: Control = null
	var _box: Panel = null
	var _dragging_window := false
	var _resizing := false
	var _grab_offset := Vector2.ZERO
	var _resize_start := Vector2.ZERO
	var _resize_size := Vector2.ZERO

	func _init(p_workspace: RingWorkspace) -> void:
		workspace = p_workspace
		visible = false
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		_box = Panel.new()
		_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#10131B")
		style.set_corner_radius_all(6)
		_box.add_theme_stylebox_override("panel", style)
		add_child(_box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_box.add_child(col)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 10
		col.offset_right = -10
		col.offset_top = 8
		col.offset_bottom = -8

		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		header.gui_input.connect(_window_input)
		col.add_child(header)
		var title := Label.new()
		title.text = "画形状，拖标题栏移动，右下角缩放"
		UITheme.style_section(title)
		header.add_child(title)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)
		var close := Button.new()
		close.text = "完成"
		close.pressed.connect(close_pad)
		header.add_child(close)

		var quick := HBoxContainer.new()
		quick.add_theme_constant_override("separation", 4)
		col.add_child(quick)
		quick.add_child(_button("放大", func() -> void: _scale_shape(1.1)))
		quick.add_child(_button("缩小", func() -> void: _scale_shape(1.0 / 1.1)))
		quick.add_child(_button("居中", _center_shape))
		quick.add_child(_button("圆形化", _round_shape))
		quick.add_child(_button("切一刀", func() -> void: _preset("gap")))

		_canvas = Control.new()
		_canvas.custom_minimum_size = Vector2(520, 360)
		_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		_canvas.draw.connect(_draw_pad)
		_canvas.gui_input.connect(_pad_input)
		col.add_child(_canvas)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col.add_child(row)
		row.add_child(_button("圆", func() -> void: _preset("circle")))
		row.add_child(_button("椭圆", func() -> void: _preset("ellipse")))
		row.add_child(_button("竖椭圆", func() -> void: _preset("tall")))
		row.add_child(_button("加点", _add_vertex))
		row.add_child(_button("删点", _delete_vertex))
		var hint := Label.new()
		hint.text = "拖顶点改形状，双击线上加点，G 切换缺口片段，背景 3D 环实时更新"
		UITheme.style_mono(hint, 11, UITheme.MUTED)
		col.add_child(hint)

		var resize := Control.new()
		resize.custom_minimum_size = Vector2(14, 14)
		resize.mouse_filter = Control.MOUSE_FILTER_STOP
		resize.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		resize.gui_input.connect(_resize_input)
		_box.add_child(resize)
		resize.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		resize.offset_left = -16
		resize.offset_top = -16
		resize.offset_right = -2
		resize.offset_bottom = -2

	func open(p_shape_id: String) -> void:
		shape_id = p_shape_id
		shape = workspace.chart().get_shape(p_shape_id)
		visible = true
		_apply_saved_rect()
		_canvas.queue_redraw()

	func close_pad() -> void:
		_save_rect()
		visible = false
		workspace._refresh()

	func _apply_saved_rect() -> void:
		var rect: Array = workspace._app.ring_pad_rect
		var view := get_viewport_rect().size
		if rect.size() == 4:
			_box.position = Vector2(float(rect[0]), float(rect[1]))
			_box.size = Vector2(maxf(520.0, float(rect[2])), maxf(360.0, float(rect[3])))
		else:
			_box.size = Vector2(640, 600)
			_box.position = (view - _box.size) * 0.5
		_box.size.x = minf(_box.size.x, maxf(420.0, view.x - 20.0))
		_box.size.y = minf(_box.size.y, maxf(300.0, view.y - 20.0))
		_box.position.x = clampf(_box.position.x, 0.0, maxf(0.0, view.x - _box.size.x))
		_box.position.y = clampf(_box.position.y, 0.0, maxf(0.0, view.y - _box.size.y))

	func _save_rect() -> void:
		workspace._app.ring_pad_rect = [_box.position.x, _box.position.y, _box.size.x, _box.size.y]
		workspace._app.save_settings()

	func _window_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_window = event.pressed
			_grab_offset = event.position
			if not event.pressed:
				_save_rect()
			_box.accept_event()
		elif event is InputEventMouseMotion and _dragging_window:
			_box.position += event.relative
			_box.accept_event()

	func _resize_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_resizing = event.pressed
			_resize_start = event.position
			_resize_size = _box.size
			if not event.pressed:
				_save_rect()
			_box.accept_event()
		elif event is InputEventMouseMotion and _resizing:
			var delta: Vector2 = event.position - _resize_start
			_box.size = Vector2(maxf(520.0, _resize_size.x + delta.x), maxf(360.0, _resize_size.y + delta.y))
			_box.accept_event()

	func _scale() -> float:
		return minf(_canvas.size.x, _canvas.size.y) * 0.40 / 420.0

	func _center() -> Vector2:
		return _canvas.size * 0.5

	func _draw_pad() -> void:
		_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#0B0D12"))
		if shape == null:
			return
		var center := _center()
		var scale := _scale()
		var points := PackedVector2Array()
		for i in 145:
			var data := shape.point_at(float(i) / 144.0)
			if bool(data.get("gap", false)):
				continue
			points.append(center + (data.point as Vector2) * scale)
		if points.size() > 1:
			_canvas.draw_polyline(points, UITheme.CYAN, 2.0, true)
		# 洋葱皮：相邻关键帧的轮廓。
		var keys := workspace.chart().sorted_shape_keys()
		var current_index := -1
		for i in keys.size():
			if String(keys[i].get("shape_id", "")) == shape_id and absf(float(keys[i].get("beat", 0.0)) - workspace.playhead()) < 0.01:
				current_index = i
				break
		if current_index >= 0 and workspace.onion_skin:
			for offset in [-1, 1]:
				var other_index: int = current_index + int(offset)
				if other_index < 0 or other_index >= keys.size():
					continue
				var other := workspace.chart().get_shape(String(keys[other_index].get("shape_id", "")))
				if other == null:
					continue
				var ghost := PackedVector2Array()
				for i in 145:
					var data := other.point_at(float(i) / 144.0)
					if bool(data.get("gap", false)):
						continue
					ghost.append(center + (data.point as Vector2) * scale)
				if ghost.size() > 1:
					_canvas.draw_polyline(ghost, Color(1, 1, 1, 0.20), 1.0, true)
		var index := int(workspace._app.selected_segment_index)
		var vertices := shape.vertices()
		for i in vertices.size():
			var p := center + vertices[i] * scale
			var color := UITheme.CORAL if i == index else UITheme.CYAN
			_canvas.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), color)
			_canvas.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), UITheme.BG, false, 1.0)

	func _pad_input(event: InputEvent) -> void:
		if shape == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					var index: int = _nearest_segment(event.position)
					if index >= 0:
						workspace._app.mutate_ring(func() -> void: shape.insert_vertex(index))
						_canvas.queue_redraw()
					return
				_drag_vertex = _pick(event.position)
				if _drag_vertex >= 0:
					workspace._app.select_segment(_drag_vertex)
					workspace.begin_preview_drag()
					workspace._app.begin_edit()
					_canvas.queue_redraw()
			else:
				if _drag_vertex >= 0:
					_drag_vertex = -1
					workspace.end_preview_drag()
					workspace._app.finish_edit()
			_canvas.accept_event()
		elif event is InputEventMouseMotion and _drag_vertex >= 0:
			var local: Vector2 = (event.position - _center()) / maxf(0.0001, _scale())
			shape.set_vertex(_drag_vertex, local)
			workspace._app.touch_chart()
			# 3D 网格只认 _mesh_dirty：不标它，拖顶点时环不会跟着变形。
			if workspace._preview != null:
				workspace._preview._mesh_dirty = true
			_canvas.queue_redraw()
			_canvas.accept_event()

	func _pick(pos: Vector2) -> int:
		var center := _center()
		var scale := _scale()
		var best := -1
		var best_distance := 16.0
		var vertices := shape.vertices()
		for i in vertices.size():
			var distance := (center + vertices[i] * scale).distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = i
		return best

	func _nearest_segment(pos: Vector2) -> int:
		var center := _center()
		var scale := _scale()
		var best := -1
		var best_distance := 12.0
		for i in 72:
			var u := float(i) / 72.0
			var data := shape.point_at(u)
			if bool(data.get("gap", false)):
				continue
			var distance := (center + (data.point as Vector2) * scale).distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				var segment := shape.segment_at(u)
				if segment != null:
					best = shape.sorted_segments().find(segment)
		return best

	func _scale_shape(factor: float) -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var centroid := Vector2.ZERO
		for point in vertices:
			centroid += point
		centroid /= float(vertices.size())
		workspace._app.mutate_ring(func() -> void:
			for i in vertices.size():
				shape.set_vertex(i, centroid + (vertices[i] - centroid) * factor)
		)
		_canvas.queue_redraw()

	func _center_shape() -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var centroid := Vector2.ZERO
		for point in vertices:
			centroid += point
		centroid /= float(vertices.size())
		workspace._app.mutate_ring(func() -> void:
			for i in vertices.size():
				shape.set_vertex(i, vertices[i] - centroid)
		)
		_canvas.queue_redraw()

	func _round_shape() -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var total := 0.0
		for point in vertices:
			total += point.length()
		var radius := total / float(vertices.size())
		workspace._app.mutate_ring(func() -> void:
			for i in vertices.size():
				var direction := vertices[i].normalized()
				if direction.length_squared() < 0.0001:
					direction = Vector2.RIGHT
				shape.set_vertex(i, direction * radius)
		)
		_canvas.queue_redraw()

	func _preset(kind: String) -> void:
		var replacement: BoundaryShape
		match kind:
			"circle":
				replacement = BoundaryShape.circle(shape_id, 330.0, 48)
			"ellipse":
				replacement = BoundaryShape.ellipse(shape_id, 410.0, 245.0, 48)
			"tall":
				replacement = BoundaryShape.ellipse(shape_id, 300.0, 400.0, 48)
			"gap":
				replacement = BoundaryShape.circle(shape_id, 330.0, 48)
				replacement.segments[0].gap = true
			_:
				return
		workspace._app.mutate_ring(func() -> void:
			shape.segments = replacement.segments
			shape.closed = replacement.closed
		)
		_canvas.queue_redraw()

	func _add_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate_ring(func() -> void:
			shape.insert_vertex(index)
			workspace._app.select_segment(mini(index + 1, shape.vertex_count() - 1))
		)
		_canvas.queue_redraw()

	func _delete_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate_ring(func() -> void:
			shape.remove_vertex(index)
			workspace._app.select_segment(clampi(index, 0, shape.vertex_count() - 1))
		)
		_canvas.queue_redraw()

	func _button(text: String, callback: Callable) -> Button:
		var button := Button.new()
		button.text = text
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(callback)
		return button


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build()
	_pad = ShapePadOverlay.new(self)
	add_child(_pad)
	_preview_gesture_timer = Timer.new()
	_preview_gesture_timer.one_shot = true
	_preview_gesture_timer.wait_time = 0.75
	_preview_gesture_timer.timeout.connect(end_preview_drag)
	add_child(_preview_gesture_timer)
	if _app != null:
		_app.chart_live_changed.connect(func() -> void:
			_timeline.on_live_change()
			if _pad.visible:
				_pad._canvas.queue_redraw()
		)
		_app.ring_live_changed.connect(func() -> void:
			_timeline.on_live_change()
			if _pad.visible:
				_pad._canvas.queue_redraw()
		)
		_app.chart_changed.connect(func() -> void:
			if visible:
				_timeline.on_chart_changed()
				_rebuild_thumbs()
				_sync_time_tool()
				if _inspector != null:
					_inspector.call_deferred("refresh", true)
		)
		_app.playhead_changed.connect(func(_beat: float) -> void:
			var window_moved := _follow_playhead()
			_sync_time_tool()
			if window_moved:
				_timeline.invalidate()
			else:
				_timeline.on_playhead_changed()
		)
		# 选中形状帧时同步高亮左侧形状库；复制/删除作用于当前形状。
		_app.selection_changed.connect(func() -> void:
			if visible:
				_rebuild_thumbs()
		)


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0C11")
	style.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	bg.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var title := Label.new()
	title.text = "环编辑"
	UITheme.style_section(title)
	header.add_child(title)
	_title = Label.new()
	UITheme.style_mono(_title, 12, UITheme.MUTED)
	_title.add_theme_font_override("font", UITheme.FONT_REGULAR)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = "返回 (Esc)"
	close.pressed.connect(close_workspace)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	var library := VBoxContainer.new()
	library.custom_minimum_size = Vector2(78, 0)
	library.add_theme_constant_override("separation", 6)
	body.add_child(library)
	_thumbs = GridContainer.new()
	_thumbs.columns = 1
	library.add_child(_thumbs)
	library.add_child(_button("＋ 新形状", _new_shape))
	library.add_child(_button("复制", _duplicate_shape))
	library.add_child(_button("删除", _delete_shape))

	_preview_slot = Control.new()
	_preview_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_slot.clip_contents = true
	body.add_child(_preview_slot)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_inspector = RingInspector.new(self, null)
	_panel = _inspector
	scroll.add_child(_panel)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	root.add_child(time_row)
	var beat_label := Label.new()
	beat_label.text = "拍"
	UITheme.style_mono(beat_label, 11, UITheme.MUTED)
	time_row.add_child(beat_label)
	_beat_spin = SpinBox.new()
	_beat_spin.min_value = 0.0
	_beat_spin.max_value = 100000.0
	_beat_spin.step = 0.25
	_beat_spin.custom_minimum_size = Vector2(110, 0)
	_beat_spin.value_changed.connect(func(value: float) -> void:
		if _app != null and absf(value - playhead()) > 0.0001:
			_app.seek(value)
	)
	time_row.add_child(_beat_spin)
	time_row.add_child(_button("◀ 关键帧", _prev_key))
	time_row.add_child(_button("关键帧 ▶", _next_key))
	time_row.add_child(_button("◀ 帧", func() -> void: _step_frame(-1)))
	time_row.add_child(_button("帧 ▶", func() -> void: _step_frame(1)))
	_play_button = _button("播放 / 暂停", func() -> void: play_toggled.emit())
	time_row.add_child(_play_button)
	_loop_button = _button("循环本段", _toggle_loop)
	time_row.add_child(_loop_button)
	time_row.add_child(_button("−", func() -> void: zoom_timeline(1)))
	time_row.add_child(_button("＋", func() -> void: zoom_timeline(-1)))
	time_row.add_child(_button("适配帧 (F)", fit_key_range_timeline))
	time_row.add_child(_button("全部", fit_all_timeline))
	_zoom_label = Label.new()
	UITheme.style_mono(_zoom_label, 11, UITheme.MUTED)
	time_row.add_child(_zoom_label)
	var onion := CheckBox.new()
	onion.text = "洋葱皮"
	onion.tooltip_text = "显示当前关键帧前后各 N 帧的环轮廓"
	onion.add_theme_font_size_override("font_size", 11)
	onion.toggled.connect(func(value: bool) -> void:
		onion_skin = value
		_update_onion()
	)
	time_row.add_child(onion)
	var onion_n := SpinBox.new()
	onion_n.min_value = 1
	onion_n.max_value = 5
	onion_n.step = 1
	onion_n.value = onion_range
	onion_n.custom_minimum_size = Vector2(52, 0)
	onion_n.tooltip_text = "前后各显示几帧"
	onion_n.add_theme_font_size_override("font_size", 10)
	onion_n.value_changed.connect(func(value: float) -> void:
		onion_range = int(value)
		_update_onion()
	)
	time_row.add_child(onion_n)
	_time_label = Label.new()
	UITheme.style_mono(_time_label, 12, UITheme.CYAN)
	_time_label.add_theme_font_override("font", UITheme.FONT_REGULAR)
	time_row.add_child(_time_label)
	_fps_label = Label.new()
	UITheme.style_mono(_fps_label, 12, UITheme.MUTED)
	time_row.add_child(_fps_label)
	var hint := Label.new()
	hint.text = "拖关键帧改时间；点色带选中过渡段；F 适配关键帧；Ctrl+滚轮缩放，滚轮平移。"
	UITheme.style_mono(hint, 11, UITheme.MUTED)
	time_row.add_child(hint)

	_timeline = RingTimeline.new(self)
	root.add_child(_timeline)
	if _inspector != null:
		_inspector.timeline = _timeline
		# 延迟到当前信号结束后重建，避免在按钮的 pressed 回调里释放按钮。
		_timeline.selection_changed.connect(func() -> void: _inspector.call_deferred("refresh", true))
	# 选中变化时立即更新标题（镜头帧/形状帧），不等下一次跨拍。
	_timeline.selection_changed.connect(func() -> void: _sync_time_tool(true))
	_timeline.selection_changed.connect(_sync_preview_selection)


## 复用主预览：把同一个 Preview3D 挪进来，省掉第二个 3D 视口。
func open_workspace(preview: Preview3D = null, restore: Callable = Callable()) -> void:
	visible = true
	# 每次打开都要重新搬入预览并记录恢复回调；只搬第一次会导致第二次打开时预览槽为空。
	if preview != null:
		if preview.get_parent() != _preview_slot:
			if preview.get_parent() != null:
				preview.get_parent().remove_child(preview)
			_preview_slot.add_child(preview)
			preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_preview = preview
		_restore_preview = restore
	if _preview != null:
		if not _preview.command_selected.is_connected(_on_preview_command_selected):
			_preview.command_selected.connect(_on_preview_command_selected)
		_sync_preview_selection()
		_preview.ring_edit_mode = true
		_preview.show_hud = false
		_preview.use_3d_ring = _app.use_3d_ring
		_preview.flow_scale = _app.flow_scale
		_preview.note_skin = _app.note_skin
		_preview.cursor_scale = _app.cursor_scale
		if not _preview.notice.is_connected(_set_hint):
			_preview.notice.connect(_set_hint)
		if not _preview.ring_zoom.is_connected(_on_ring_zoom):
			_preview.ring_zoom.connect(_on_ring_zoom)
		if not _preview.ring_rotate.is_connected(_on_ring_rotate):
			_preview.ring_rotate.connect(_on_ring_rotate)
		_preview.set_process(true)
		_preview.queue_redraw()
	grab_focus()
	_follow_playhead(true)
	if chart() != null and (not chart().shape_keys.is_empty() or chart().view_states.size() > 1):
		fit_key_range_timeline()
	# 形状库高亮播放头当前实际使用的形状，避免基础圆盖住当前形状的选中框。
	var at_key := current_key()
	if not at_key.is_empty():
		_app.select_shape(String(at_key.get("shape_id", "")))
	_refresh()
	# 打开后再预热，避免阻塞首帧；第一次拖关键帧不必再拍一次冷快照。
	if _app != null and _app.has_method("warm_snapshot"):
		_app.call_deferred("warm_snapshot")


func close_workspace() -> void:
	if _pad != null and _pad.visible:
		_pad.close_pad()
		return
	end_preview_drag()
	visible = false
	if _preview != null and _preview.get_parent() == _preview_slot:
		_preview_slot.remove_child(_preview)
	if _restore_preview.is_valid():
		_restore_preview.call(_preview)
		_restore_preview = Callable()
	closed.emit()


func chart() -> Chart:
	return _app.chart if _app != null else null


## 时间轴选中的指令同步给预览：文本拖动和滤镜区域描边都靠它。
func _sync_preview_selection() -> void:
	if _preview == null:
		return
	_preview.selected_command = _timeline.selected_command() if _timeline != null else null
	_preview.queue_redraw()
	if _preview._overlay != null:
		_preview._overlay.queue_redraw()


func _on_preview_command_selected(command: AlphaCommand) -> void:
	if _timeline != null:
		_timeline.select_command(command, false)


## 拖动期间使用冻结值；松手后重新扫描一次。
func content_end_beat() -> float:
	if _drag_content_end >= 0.0:
		return _drag_content_end
	var chart_data := chart()
	return chart_data.content_end_beat() if chart_data != null else 0.0


func begin_preview_drag() -> void:
	if _preview_gesture_timer != null:
		_preview_gesture_timer.stop()
	if _preview != null:
		_preview.ring_drag_low_detail = true
		_preview.queue_redraw()


func end_preview_drag() -> void:
	if _preview != null:
		_preview.ring_drag_low_detail = false
		_preview.queue_redraw()


func begin_content_freeze() -> void:
	_drag_content_end = content_end_beat()


func end_content_freeze() -> void:
	_drag_content_end = -1.0


func playhead() -> float:
	return float(_app.playhead_beat) if _app != null else 0.0


func view_beats() -> float:
	return clampf(_view_beats, MIN_VIEW_BEATS, MAX_VIEW_BEATS)


func window_start() -> float:
	return _view_start


## 「适配关键帧」：只框住形状/镜头关键帧，不压缩整首歌。
func fit_key_range_timeline() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var low := INF
	var high := -INF
	for key in chart_data.shape_keys:
		low = minf(low, float(key.get("beat", 0.0)))
		high = maxf(high, float(key.get("beat", 0.0)))
	for state in chart_data.view_states:
		# 默认的 0 拍镜头帧会把范围拉到整首歌；只有它时不参与适配。
		if state.beat > 0.001:
			low = minf(low, state.beat)
			high = maxf(high, state.beat)
	if not is_finite(low) or not is_finite(high):
		return
	# 关键帧很少时也至少给 16 拍：只有一帧在 0 拍时，4 拍窗口看不清前后关系。
	_view_beats = clampf(maxf(16.0, high - low + 2.0), MIN_VIEW_BEATS, MAX_VIEW_BEATS)
	_view_start = maxf(0.0, low - 1.0)
	_update_zoom_label()
	_timeline.invalidate()


## 「适配全部」：缩放到能看到整张谱。
func fit_all_timeline() -> void:
	_view_beats = clampf(content_end_beat() + chart().bar_length() if chart() != null else 16.0,
		MIN_VIEW_BEATS, MAX_VIEW_BEATS)
	_view_start = 0.0
	_update_zoom_label()
	_timeline.invalidate()


## step > 0 缩小（显示更多拍），step < 0 放大（显示更少拍）。
func zoom_timeline(step: int) -> void:
	var factor := pow(1.25, float(step))
	zoom_view_at(playhead(), factor)


## 以指定拍为锚点缩放：锚点在屏幕上的位置保持不动。
func zoom_view_at(anchor_beat: float, factor: float) -> void:
	var old_span := view_beats()
	var new_span := clampf(old_span * factor, MIN_VIEW_BEATS, MAX_VIEW_BEATS)
	if is_equal_approx(new_span, old_span):
		return
	var ratio := clampf((anchor_beat - _view_start) / maxf(0.0001, old_span), 0.0, 1.0)
	_view_beats = new_span
	_view_start = maxf(0.0, anchor_beat - ratio * new_span)
	_update_zoom_label()
	_timeline.invalidate()


func _update_zoom_label() -> void:
	if _zoom_label == null:
		return
	var span := view_beats()
	_zoom_label.text = ("%.0f 拍" % span) if span >= 10.0 else ("%.1f 拍" % span)


func scroll_timeline(direction: float) -> void:
	var ahead := view_beats() * 0.15 * direction
	var end := content_end_beat() + chart().bar_length() if chart() != null else 0.0
	_view_start = clampf(_view_start + ahead, 0.0, maxf(0.0, end - view_beats()))
	_timeline.invalidate()


func _follow_playhead(force: bool = false) -> bool:
	if not force and not follow_playhead_view:
		return false
	var before := _view_start
	var span := view_beats()
	if chart() != null and span >= content_end_beat() + chart().bar_length():
		# 「全部」视图下播放头走动时不要把它滚走。
		_view_start = 0.0
		return not is_equal_approx(before, _view_start)
	var beat := playhead()
	# 按页跳动，避免静态内容层每帧重绘。
	if force or beat < _view_start or beat > _view_start + span * 0.9:
		_view_start = maxf(0.0, beat - span * 0.3)
	return not is_equal_approx(before, _view_start)


func seek(beat: float) -> void:
	if _app != null:
		_app.seek(beat)


func dragging() -> bool:
	return not _drag_kind.is_empty() or scrubbing()


## 正在拖动时间轴播放头。拖动时不要重建面板：一次重建约 70–80 个控件，
## 跨帧时进出各一次，是拖过关键帧卡顿的主要来源。
func scrubbing() -> bool:
	return _timeline != null and _timeline._drag_kind == "playhead"


## 拖动播放头结束：面板与洋葱皮补一次，拖动过程中跳过。
func finish_scrub() -> void:
	var key := current_key()
	_last_key_beat = float(key.get("beat", -999.0)) if not key.is_empty() else -999.0
	_update_onion()
	_sync_time_tool(true)
	_timeline.invalidate()


func current_key() -> Dictionary:
	var chart_data := chart()
	if chart_data == null:
		return {}
	return chart_data.shape_key_at(playhead())


func _refresh() -> void:
	if _app == null or _app.chart == null:
		return
	_rebuild_thumbs()
	_rebuild_panel()
	_sync_time_tool()
	_update_zoom_label()
	_timeline.invalidate()


func snap(beat: float) -> float:
	return float(_app.snap_beat(beat, false)) if _app != null else beat


# ---- RingTimeline 的回调：把手势/撤销细节留在 App --------------------------

func begin_edit() -> void:
	if _app != null:
		_app.begin_edit()


func touch_chart() -> void:
	if _app != null:
		_app.touch_ring_chart()


func finish_edit() -> void:
	if _app != null:
		_app.finish_edit()


func mutate_chart(callback: Callable) -> void:
	if _app != null:
		_app.mutate_ring(callback)


func gesture_mutate_chart(callback: Callable) -> void:
	if _app == null:
		return
	begin_preview_drag()
	_app.gesture_mutate_ring(callback)
	if _preview_gesture_timer != null:
		_preview_gesture_timer.start()


## 按当前吸附细分步进播放头：1/4、1/8…；没有吸附时退到 1/4 拍。
func _step_frame(direction: int) -> void:
	var step := GridDivisions.step_beats(snap_division())
	if step <= 0.0001:
		step = 0.25
	seek(maxf(0.0, playhead() + step * float(direction)))


func snap_division() -> int:
	return int(_app.snap_division) if _app != null else GridDivisions.DEFAULT_DIVISION


func _process(delta: float) -> void:
	if not visible or _fps_label == null:
		return
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _sync_time_tool(force: bool = false) -> void:
	# 每帧写 Label / SpinBox 会触发整页重新排版（实测 78ms/帧）；
	# 只在显示值变化时写，并限到约 12Hz。播放头位置本身仍然逐帧更新。
	var now := Time.get_ticks_msec()
	if not force and now - _sync_last_msec < 80:
		return
	_sync_last_msec = now
	var beat := playhead()
	if not is_equal_approx(beat, _sync_last_beat):
		_sync_last_beat = beat
		# SpinBox / Label 文本变化会触发整页重新排版（实测约 40ms），
		# 所以只在显示值真正变化时写：拍数按 1/4 拍、时间按 0.1 拍。
		if _beat_spin != null:
			var spin_value := snappedf(beat, 0.25)
			if not is_equal_approx(spin_value, _sync_last_spin):
				_sync_last_spin = spin_value
				_beat_spin.set_value_no_signal(spin_value)
		if _time_label != null and chart() != null:
			var bpb := maxf(1.0, chart().timing.beats_per_bar_at(beat))
			var text := "第 %d 小节，拍 %.1f / %d" % [int(floorf(beat / bpb)) + 1, fmod(beat, bpb), int(bpb)]
			if _time_label.text != text:
				_time_label.text = text
	var key := current_key()
	if _title != null:
		var view: ViewState = _timeline.primary_view() if _timeline != null else null
		var command: AlphaCommand = _timeline.selected_command() if _timeline != null else null
		var suffix := "无关键帧"
		if command != null:
			suffix = "指令 " + command.label()
		elif view != null:
			suffix = "镜头帧 %d" % view.id
		elif not key.is_empty():
			suffix = "形状帧 " + String(key.get("shape_id", ""))
		var text := "拍 %.1f，%s" % [beat, suffix]
		if _title.text != text:
			_title.text = text
	# 播放或拖动跨过关键帧时，右侧按钮跟着换。
	var key_beat := float(key.get("beat", -999.0)) if not key.is_empty() else -999.0
	if not is_equal_approx(key_beat, _last_key_beat) and not dragging():
		_last_key_beat = key_beat
		# 新面板按选中重建，不按播放头；跨关键帧只更新洋葱皮。
		_update_onion()


func _current_shape() -> BoundaryShape:
	var key: Dictionary = _timeline.primary_key() if _timeline != null else {}
	if key.is_empty():
		key = current_key()
	if not key.is_empty():
		return chart().get_shape(String(key.get("shape_id", "")))
	return null


## 形状库按钮作用于当前选中的库形状；没有选中时退回播放头关键帧的形状。
func _library_shape() -> BoundaryShape:
	var chart_data := chart()
	if chart_data != null and _app != null:
		var picked := chart_data.get_shape(String(_app.selected_shape_id))
		if picked != null:
			return picked
	return _current_shape()


func _rebuild_thumbs() -> void:
	var chart_data := chart()
	if chart_data == null or _thumbs == null:
		return
	var active := String(_app.selected_shape_id)
	var signature := active
	for shape in chart_data.sorted_shapes():
		signature += "|" + shape.id
	if signature == _thumb_signature:
		return
	_thumb_signature = signature
	for child in _thumbs.get_children():
		child.queue_free()
	for shape in chart_data.sorted_shapes():
		var thumb := ShapeThumb.new(self, shape.id)
		thumb.selected = shape.id == active
		_thumbs.add_child(thumb)


func _rebuild_panel() -> void:
	if _inspector != null:
		_inspector.refresh()


func _update_onion() -> void:
	if _preview == null:
		return
	_preview.onion_shapes.clear()
	if not onion_skin or chart() == null:
		return
	var keys := chart().sorted_shape_keys()
	if keys.is_empty():
		return
	# 当前段左键 = 播放头之前最后一帧；前后各取 N 帧。
	var index := 0
	for i in keys.size():
		if float(keys[i].get("beat", 0.0)) <= playhead() + 0.0001:
			index = i
	var seen := {}
	for n in onion_range:
		for j in [index - n, index + 1 + n]:
			if j < 0 or j >= keys.size():
				continue
			var shape_id := String(keys[j].get("shape_id", ""))
			if seen.has(shape_id):
				continue
			var other := chart().get_shape(shape_id)
			if other != null:
				seen[shape_id] = true
				_preview.onion_shapes.append(other)
		_preview.queue_redraw()
	if _pad != null and _pad.visible:
		_pad._canvas.queue_redraw()


func _active_view() -> Dictionary:
	var chart_data := chart()
	if chart_data == null:
		return ViewState.default_state()
	var selected: ViewState = _timeline.primary_view() if _timeline != null else null
	if selected == null:
		selected = _app.get_selected_view()
	if selected != null:
		return {
			"zoom": selected.zoom, "rotation": selected.rotation,
			"tilt_x": selected.tilt_x, "tilt_y": selected.tilt_y, "ellipse": selected.ellipse,
			"dolly": selected.dolly,
		}
	return BoundaryRuntime.eval_view(chart_data, playhead())


func _apply_view(key: String, value: float) -> void:
	var state: ViewState = _timeline.primary_view() if _timeline != null else null
	if state == null:
		state = _app.get_selected_view()
	if state == null:
		_add_view_keyframe()
		state = _timeline.primary_view() if _timeline != null else _app.get_selected_view()
		if state == null:
			return
	match key:
		"zoom":
			state.zoom = value
		"dolly":
			state.dolly = value
		"rotation":
			state.rotation = value
		"tilt_x":
			state.tilt_x = value
		"tilt_y":
			state.tilt_y = value
		"ellipse":
			state.ellipse = value


func _on_ring_zoom(delta: float) -> void:
	# 预览里的滚轮是推拉：改镜头距离，不改环的世界缩放。
	var view := _active_view()
	var target := clampf(float(view.get("dolly", 1.0)) + delta, 0.6, 1.6)
	gesture_mutate_chart(func() -> void: _apply_view("dolly", target))


func _on_ring_rotate(degrees: float) -> void:
	var view := _active_view()
	var target := clampf(float(view.get("rotation", 0.0)) + degrees, -180.0, 180.0)
	# 旋转是连续拖动量：整段拖动合并为一条撤销。
	gesture_mutate_chart(func() -> void: _apply_view("rotation", target))
	_preview.queue_redraw()


## 从 after 之后找第一个没有对应关键帧的吸附拍，插入时不再覆盖同一拍。
func _free_beat(after: float, kind: String) -> float:
	var chart_data := chart()
	if chart_data == null:
		return after
	var step := GridDivisions.step_beats(snap_division())
	if step <= 0.0001:
		step = 0.25
	var beat := after + step
	for i in 512:
		var used := false
		if kind == "shape":
			used = not chart_data.shape_key_at(beat).is_empty()
		else:
			for state in chart_data.view_states:
				if absf(state.beat - beat) < 0.001:
					used = true
					break
		if not used:
			return beat
		beat += step
	return after


func _add_view_keyframe() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var at := playhead()
	for existing in chart_data.view_states:
		if absf(existing.beat - at) < 0.001:
			# 播放头已有镜头帧：自动放到下一拍，连点可连续打帧。
			at = _free_beat(at, "view")
			seek(at)
			break
	var current := BoundaryRuntime.eval_view(chart_data, at)
	var state := ViewState.new(at, float(current.get("zoom", 1.0)), float(current.get("tilt_x", 0.0)),
		float(current.get("tilt_y", 0.0)), float(current.get("ellipse", 1.0)), float(current.get("rotation", 0.0)),
		"in-out", float(current.get("dolly", 1.0)))
	state.morph = -1.0
	state.id = chart_data.next_key_id()
	_app.mutate_ring(func() -> void:
		chart_data.view_states.append(state)
		chart_data.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		_app.select_view(chart_data.view_states.find(state))
		if _timeline != null:
			_timeline._select_only("view", state.id)
	)
	_refresh()


func _delete_view_keyframe() -> void:
	if _timeline != null and _timeline.primary_view() != null:
		_timeline.delete_selection()
		return
	var chart_data := chart()
	if chart_data == null or _app.selected_view_index < 0:
		return
	var state: ViewState = _app.get_selected_view()
	if state == null:
		return
	_app.mutate_ring(func() -> void:
		chart_data.view_states.erase(state)
		_app.select_view(-1)
	)
	_refresh()


# ---- 形状关键帧 -------------------------------------------------------------

func _next_shape_id() -> String:
	var chart_data := chart()
	if chart_data == null:
		return "S0"
	var index := 1
	while chart_data.shapes.has("S%d" % index):
		index += 1
	return "S%d" % index


## 把当前拍实际显示的轮廓定型为一个新形状。
func _snapshot_shape(beat: float) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = _next_shape_id()
	shape.closed = true
	var count := BoundaryShape.MAX_VERTICES
	var points := BoundaryRuntime.eval_shape(chart(), beat, count)
	for i in count:
		var a: Dictionary = points[i]
		var b: Dictionary = points[(i + 1) % count]
		shape.segments.append(BoundarySegment.new(
			float(i) / float(count), float(i + 1) / float(count),
			a.point, b.point, "l", "l", bool(a.get("gap", false))
		))
	return shape


## 插入形状帧：当前轮廓 / 已有形状 / 基础圆，三选一。
func _add_key() -> void:
	open_insert_menu()


func open_insert_menu() -> void:
	if chart() == null:
		return
	_ensure_insert_menu()
	_insert_menu.popup_centered(Vector2i(300, 170))


func _ensure_insert_menu() -> void:
	if _insert_menu != null:
		return
	_insert_menu = PopupMenu.new()
	_insert_menu.add_item("用当前轮廓新建形状", 1)
	_insert_menu.add_item("使用已有形状…", 2)
	_insert_menu.add_item("放一个圆（S0）", 3)
	_insert_menu.id_pressed.connect(_on_insert_menu)
	add_child(_insert_menu)
	_shape_pick = PopupMenu.new()
	_shape_pick.id_pressed.connect(_on_shape_pick)
	add_child(_shape_pick)


func _on_insert_menu(id: int) -> void:
	match id:
		1:
			_insert_key_snapshot()
		2:
			_popup_shape_pick()
		3:
			var chart_data := chart()
			if chart_data != null:
				_insert_key_with_shape(chart_data.default_shape_id)


func _popup_shape_pick() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	_shape_pick.clear()
	var ids: Array = chart_data.shapes.keys()
	ids.sort()
	for i in ids.size():
		var shape_id := String(ids[i])
		var label := shape_id
		if shape_id == chart_data.default_shape_id:
			label += "（基础圆，锁定）"
		_shape_pick.add_item(label, i)
	_shape_pick.popup_centered(Vector2i(240, 220))


func _on_shape_pick(index: int) -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var ids: Array = chart_data.shapes.keys()
	ids.sort()
	if index >= 0 and index < ids.size():
		_insert_key_with_shape(String(ids[index]))


func _insert_key_snapshot() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var beat := _free_beat(playhead(), "shape")
	if not chart_data.shape_key_at(beat).is_empty():
		_set_hint("附近没有空拍可插；先拖时间轴到别的拍。")
		return
	if not is_equal_approx(beat, playhead()):
		seek(beat)
	var shape := _snapshot_shape(beat)
	_app.mutate_ring(func() -> void:
		chart_data.shapes[shape.id] = shape
		var key := {"beat": beat, "shape_id": shape.id, "easing": "linear", "morph": 0.0,
			"id": chart_data.next_key_id()}
		chart_data.shape_keys.append(key)
		_app.select_shape(shape.id)
		_app.select_segment(0)
	)
	var created := chart_data.shape_key_at(beat)
	if not created.is_empty() and _timeline != null:
		_timeline._select_only("shape", int(created.get("id", 0)))
	_refresh()
	_set_hint("已插入形状帧 %s；点「编辑形状（2D）」开始画。" % shape.id)


func _insert_key_with_shape(shape_id: String) -> void:
	var chart_data := chart()
	if chart_data == null or chart_data.get_shape(shape_id) == null:
		return
	var beat := _free_beat(playhead(), "shape")
	if not chart_data.shape_key_at(beat).is_empty():
		_set_hint("附近没有空拍可插；先拖时间轴到别的拍。")
		return
	if not is_equal_approx(beat, playhead()):
		seek(beat)
	_app.mutate_ring(func() -> void:
		chart_data.shape_keys.append({"beat": beat, "shape_id": shape_id, "easing": "linear",
			"morph": 0.0, "id": chart_data.next_key_id()})
		_app.select_shape(shape_id)
	)
	var created := chart_data.shape_key_at(beat)
	if not created.is_empty() and _timeline != null:
		_timeline._select_only("shape", int(created.get("id", 0)))
	_refresh()


## 从当前选中的帧复制到下一个空吸附格：连点可连续铺帧，不覆盖已有帧。
func insert_next_shape() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var source: Dictionary = _timeline.primary_key() if _timeline != null else {}
	if source.is_empty():
		source = current_key()
	var beat := _free_beat(playhead(), "shape")
	if not chart_data.shape_key_at(beat).is_empty():
		_set_hint("附近没有空拍可插；先拖时间轴到别的拍。")
		return
	var shape_id := String(source.get("shape_id", chart_data.default_shape_id))
	if chart_data.get_shape(shape_id) == null:
		shape_id = chart_data.default_shape_id
	var key := {"beat": beat, "shape_id": shape_id,
		"easing": String(source.get("easing", "linear")),
		"morph": float(source.get("morph", 0.0)),
		"id": chart_data.next_key_id()}
	if source.has("curve"):
		key["curve"] = (source.get("curve", []) as Array).duplicate()
	_app.mutate_ring(func() -> void:
		chart_data.shape_keys.append(key)
		_app.select_shape(shape_id)
	)
	seek(beat)
	_timeline._select_only("shape", int(key.get("id", 0)))
	_refresh()
	_set_hint("已在 %.2f 拍插入形状帧 %s。" % [beat, shape_id])


func insert_next_view() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var source: ViewState = _timeline.primary_view() if _timeline != null else null
	if source == null:
		source = _app.get_selected_view()
	var at := _free_beat(playhead(), "view")
	if not is_equal_approx(at, playhead()):
		seek(at)
	var current := BoundaryRuntime.eval_view(chart_data, at)
	var state := ViewState.new(at,
		float(current.get("zoom", 1.0)), float(current.get("tilt_x", 0.0)),
		float(current.get("tilt_y", 0.0)), float(current.get("ellipse", 1.0)),
		float(current.get("rotation", 0.0)), "in-out", float(current.get("dolly", 1.0)))
	if source != null:
		state.zoom = source.zoom
		state.tilt_x = source.tilt_x
		state.tilt_y = source.tilt_y
		state.ellipse = source.ellipse
		state.rotation = source.rotation
		state.dolly = source.dolly
		state.easing = source.easing
		state.morph = source.morph
		state.curve = source.curve.duplicate()
	state.id = chart_data.next_key_id()
	_app.mutate_ring(func() -> void:
		chart_data.view_states.append(state)
		chart_data.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		_app.select_view(chart_data.view_states.find(state))
	)
	_timeline._select_only("view", state.id)
	_refresh()
	_set_hint("已在 %.2f 拍插入镜头帧。" % at)


func _delete_key() -> void:
	var chart_data := chart()
	var key := current_key()
	if chart_data == null or key.is_empty():
		return
	var shape_id := String(key.get("shape_id", ""))
	var still_used := false
	for other in chart_data.shape_keys:
		if other != key and String(other.get("shape_id", "")) == shape_id:
			still_used = true
			break
	_app.mutate_ring(func() -> void:
		chart_data.shape_keys.erase(key)
		if not still_used and shape_id != chart_data.default_shape_id and shape_id != "":
			chart_data.shapes.erase(shape_id)
	)
	_refresh()


func _toggle_gap() -> void:
	var shape := _current_shape()
	if shape == null:
		_set_hint("先选中一个形状关键帧。")
		return
	var chart_data := chart()
	if chart_data != null and shape.id == chart_data.default_shape_id:
		_set_hint("基础圆 S0 已锁定；复制一个形状再切缺口。")
		return
	var index: int = clampi(int(_app.selected_segment_index), 0, shape.vertex_count() - 1)
	_app.mutate_ring(func() -> void: shape.set_gap(index, not shape.segment_has_gap(index)))
	_refresh()


func _new_shape() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var id := _next_shape_id()
	_app.mutate_ring(func() -> void:
		chart_data.shapes[id] = BoundaryShape.circle(id, 330.0, BoundaryShape.DEFAULT_VERTICES)
	)
	_app.select_shape(id)
	_refresh()


func _duplicate_shape() -> void:
	var shape := _library_shape()
	var chart_data := chart()
	if shape == null or chart_data == null:
		return
	var copy := BoundaryShape.from_dict(shape.to_dict())
	copy.id = _next_shape_id()
	_app.mutate_ring(func() -> void:
		chart_data.shapes[copy.id] = copy
	)
	_app.select_shape(copy.id)
	_refresh()


func _delete_shape() -> void:
	var shape := _library_shape()
	var chart_data := chart()
	if shape == null or chart_data == null or chart_data.shapes.size() <= 1:
		return
	if shape.id == chart_data.default_shape_id:
		_set_hint("基础圆 S0 已锁定，不能删。")
		return
	for key in chart_data.shape_keys:
		if String(key.get("shape_id", "")) == shape.id:
			_set_hint("形状 %s 还被关键帧引用，先换掉那些帧再删。" % shape.id)
			return
	_app.mutate_ring(func() -> void:
		chart_data.shapes.erase(shape.id)
	)
	_refresh()


func _toggle_loop() -> void:
	_loop_on = not _loop_on
	var start := 0.0
	var end := 0.0
	var beats: Array[float] = []
	for key in chart().sorted_shape_keys():
		beats.append(float(key.get("beat", 0.0)))
	var beat := playhead()
	for b in beats:
		if b < beat - 0.0005:
			start = b
		elif b > beat + 0.0005:
			end = b
			break
	if end <= start:
		start = maxf(0.0, beat - 2.0)
		end = beat + 2.0
	loop_requested.emit(start, end, _loop_on)
	_loop_button.text = "循环中 %.1f–%.1f 拍" % [start, end] if _loop_on else "循环本段"


func _key_beats() -> Array[float]:
	var beats: Array[float] = []
	if chart() == null:
		return beats
	for key in chart().shape_keys:
		beats.append(float(key.get("beat", 0.0)))
	for state in chart().view_states:
		beats.append(state.beat)
	beats.sort()
	var result: Array[float] = []
	for beat in beats:
		if result.is_empty() or absf(beat - result[result.size() - 1]) > 0.001:
			result.append(beat)
	return result


func _prev_key() -> void:
	var target := -1.0
	for beat in _key_beats():
		if beat < playhead() - 0.0005:
			target = beat
	if target >= 0.0:
		seek(target)


func _next_key() -> void:
	for beat in _key_beats():
		if beat > playhead() + 0.0005:
			seek(beat)
			return


func open_pad_for_current() -> void:
	var primary: Dictionary = _timeline.primary_key() if _timeline != null else {}
	if not primary.is_empty():
		seek(float(primary.get("beat", 0.0)))
	var key := current_key()
	if key.is_empty():
		_insert_key_snapshot()
		key = current_key()
		if key.is_empty():
			return
	open_pad_for_shape(String(key.get("shape_id", "")))


func open_pad_for_shape(shape_id: String) -> void:
	if shape_id.is_empty():
		return
	var chart_data := chart()
	if chart_data != null and shape_id == chart_data.default_shape_id:
		_set_hint("基础圆 S0 已锁定；点「复制」建一个可编辑的形状。")
		return
	_app.select_shape(shape_id)
	_pad.open(shape_id)


# ---- 时间轴拖拽 -------------------------------------------------------------

func begin_key_drag(key: Dictionary) -> void:
	_drag_kind = "key"
	_drag_key = key
	begin_preview_drag()
	begin_content_freeze()
	_app.begin_edit()


func begin_view_drag(state: ViewState) -> void:
	_drag_kind = "view"
	_drag_view = state
	_app.select_view(chart().view_states.find(state))
	begin_preview_drag()
	begin_content_freeze()
	_app.begin_edit()


func drag_to(beat: float) -> void:
	var target: float = _app.snap_beat(beat, false)
	match _drag_kind:
		"key":
			_drag_key["beat"] = maxf(0.0, target)
		"view":
			_drag_view.beat = maxf(0.0, target)
	_app.touch_chart()
	_timeline.invalidate()


func end_drag() -> void:
	_drag_kind = ""
	_drag_key = {}
	_drag_view = null
	end_preview_drag()
	end_content_freeze()
	chart().shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	_app.finish_edit()
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 在输入框里打字时不要把 G / Delete 当成快捷键。
	var focus = get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	if _pad != null and _pad.visible:
		if event.keycode == KEY_ESCAPE:
			_pad.close_pad()
			get_viewport().set_input_as_handled()
		return
	if _timeline != null and _timeline.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE:
			close_workspace()
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_gap()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			if not current_key().is_empty():
				_delete_key()
				get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_RIGHT:
			var key := current_key()
			if not key.is_empty():
				var step := -0.25 if event.keycode == KEY_LEFT else 0.25
				var beat := maxf(0.0, float(key.get("beat", 0.0)) + step)
				_app.mutate_ring(func() -> void:
					key["beat"] = beat
					chart().shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
				)
				seek(beat)
				get_viewport().set_input_as_handled()


# ---- 小部件 ---------------------------------------------------------------

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	return button


func _set_hint(text: String) -> void:
	if _title != null:
		_title.text = text
