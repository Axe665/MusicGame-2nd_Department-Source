class_name RingWorkspace
extends Control

## 环编辑工作区：形状关键帧 + 形变时间轴 + 镜头，一屏直操作。
## 形状关键帧是唯一真源；BoundaryEvent 只在存盘时双写给旧版本。

signal closed
signal play_toggled
signal loop_requested(start: float, end: float, enabled: bool)

const ZOOM_LEVELS := [8.0, 16.0, 32.0, 64.0]
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
var _zoom_index := 1
## 播放时时间轴是否跟着播放头滚（时间轴选项里可关）。
var follow_playhead_view := true
var _view_start := 0.0
var onion_skin := false
var onion_range := 2
var _play_button: Button = null
var _loop_button: Button = null
var _loop_on := false
var _pad: ShapePadOverlay = null

var _thumb_signature := ""
var _drag_kind := ""
var _drag_key: Dictionary = {}
var _drag_view: ViewState = null
var _last_key_beat: float = -999.0
var _sync_last_msec: int = 0
var _sync_last_beat: float = -99999.0
var _sync_last_spin: float = -99999.0


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
		var center := size * 0.5
		var scale := minf(size.x, size.y) * 0.42 / 400.0
		var points := PackedVector2Array()
		for i in 73:
			var data := shape.point_at(float(i) / 72.0)
			if bool(data.get("gap", false)):
				continue
			points.append(center + (data.point as Vector2) * scale)
		if points.size() > 1:
			draw_polyline(points, UITheme.CORAL if selected else UITheme.CYAN, 2.0, true)
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.CORAL, false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
						workspace._app.mutate(func() -> void: shape.insert_vertex(index))
						_canvas.queue_redraw()
					return
				_drag_vertex = _pick(event.position)
				if _drag_vertex >= 0:
					workspace._app.select_segment(_drag_vertex)
					workspace._app.begin_edit()
					_canvas.queue_redraw()
			else:
				if _drag_vertex >= 0:
					_drag_vertex = -1
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
		workspace._app.mutate(func() -> void:
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
		workspace._app.mutate(func() -> void:
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
		workspace._app.mutate(func() -> void:
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
		workspace._app.mutate(func() -> void:
			shape.segments = replacement.segments
			shape.closed = replacement.closed
		)
		_canvas.queue_redraw()

	func _add_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate(func() -> void:
			shape.insert_vertex(index)
			workspace._app.select_segment(mini(index + 1, shape.vertex_count() - 1))
		)
		_canvas.queue_redraw()

	func _delete_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate(func() -> void:
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
	if _app != null:
		_app.chart_live_changed.connect(func() -> void:
			_timeline.on_live_change()
			if _pad.visible:
				_pad._canvas.queue_redraw()
		)
		_app.chart_changed.connect(func() -> void:
			if visible:
				_timeline.on_chart_changed()
				_rebuild_thumbs()
				_sync_time_tool()
		)
		_app.playhead_changed.connect(func(_beat: float) -> void:
			var window_moved := _follow_playhead()
			_sync_time_tool()
			if window_moved:
				_timeline.invalidate()
			else:
				_timeline.on_playhead_changed()
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
	var zoom_option := OptionButton.new()
	for value in ["8 拍", "16 拍", "32 拍", "64 拍", "全部"]:
		zoom_option.add_item(value)
	zoom_option.selected = _zoom_index
	zoom_option.add_theme_font_size_override("font_size", 11)
	zoom_option.item_selected.connect(func(index: int) -> void:
		_zoom_index = clampi(index, 0, ZOOM_LEVELS.size())
		_follow_playhead(true)
		_timeline.invalidate()
	)
	time_row.add_child(zoom_option)
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
	var fps_label := Label.new()
	fps_label.text = "帧率"
	UITheme.style_mono(fps_label, 11, UITheme.MUTED)
	time_row.add_child(fps_label)
	var fps_keys: Array[String] = ["vsync", "60", "120", "144", "240", "unlimited"]
	var fps_labels: Array[String] = ["跟随屏幕", "60", "120", "144", "240", "不限"]
	var fps_option := OptionButton.new()
	for item in fps_labels:
		fps_option.add_item(item)
	fps_option.selected = maxi(0, fps_keys.find(String(_app.frame_cap)))
	fps_option.add_theme_font_size_override("font_size", 11)
	fps_option.item_selected.connect(func(index: int) -> void:
		_app.frame_cap = fps_keys[index]
		_app.apply_frame_cap()
		_app.save_settings()
	)
	time_row.add_child(fps_option)
	_time_label = Label.new()
	UITheme.style_mono(_time_label, 12, UITheme.CYAN)
	_time_label.add_theme_font_override("font", UITheme.FONT_REGULAR)
	time_row.add_child(_time_label)
	_fps_label = Label.new()
	UITheme.style_mono(_fps_label, 12, UITheme.MUTED)
	time_row.add_child(_fps_label)
	var hint := Label.new()
	hint.text = "拖动方块改时间，双击画形状"
	UITheme.style_mono(hint, 11, UITheme.MUTED)
	time_row.add_child(hint)

	_timeline = RingTimeline.new(self)
	root.add_child(_timeline)
	if _inspector != null:
		_inspector.timeline = _timeline
		_timeline.selection_changed.connect(func() -> void: _inspector.refresh(true))
	# 选中变化时标题也要立刻跟着变（镜头帧/形状帧），不能等下一次跨拍。
	_timeline.selection_changed.connect(func() -> void: _sync_time_tool(true))
	var explain := Label.new()
	explain.text = "块=这一帧保持到下一帧，块越长隔得越久；半透明段=形变已完成、在原地保持（检查器「形变时长」）；拖方块改时间，拖块右缘改下一帧；滚轮滚动，Ctrl+滚轮缩放。"
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_mono(explain, 11, UITheme.MUTED)
	root.add_child(explain)


## 复用主预览：把同一个 Preview3D 挪进来，省掉第二个 3D 视口。
func open_workspace(preview: Preview3D = null, restore: Callable = Callable()) -> void:
	visible = true
	# 每次打开都要把预览搬进来并重新记下恢复回调：关闭时预览会回到主界面，
	# 只搬第一次的话，第二次打开预览槽是空的，关闭时也没人把主界面显示回来。
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
	_refresh()


func close_workspace() -> void:
	if _pad != null and _pad.visible:
		_pad.close_pad()
		return
	visible = false
	if _preview != null and _preview.get_parent() == _preview_slot:
		_preview_slot.remove_child(_preview)
	if _restore_preview.is_valid():
		_restore_preview.call(_preview)
		_restore_preview = Callable()
	closed.emit()


func chart() -> Chart:
	return _app.chart if _app != null else null


func playhead() -> float:
	return float(_app.playhead_beat) if _app != null else 0.0


func view_beats() -> float:
	if _zoom_index >= ZOOM_LEVELS.size():
		# 「全部」：按内容长度铺满，再留 1 小节给最后一段的端帽。
		if chart() == null:
			return 16.0
		return maxf(8.0, chart().content_end_beat() + chart().bar_length())
	return float(ZOOM_LEVELS[clampi(_zoom_index, 0, ZOOM_LEVELS.size() - 1)])


func window_start() -> float:
	return _view_start


## 「适配关键帧」：只框住形状/镜头关键帧，不按整首歌压缩。
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
	var span := maxf(1.0, high - low)
	for i in ZOOM_LEVELS.size():
		if float(ZOOM_LEVELS[i]) >= span + 2.0:
			_zoom_index = i
			_view_start = maxf(0.0, low - 1.0)
			_timeline.invalidate()
			return
	_zoom_index = ZOOM_LEVELS.size()
	_view_start = 0.0
	_timeline.invalidate()


## 「适配全部」：缩放到能看到整张谱。
func fit_all_timeline() -> void:
	_zoom_index = ZOOM_LEVELS.size()
	_view_start = 0.0
	_timeline.invalidate()


func zoom_timeline(step: int) -> void:
	_zoom_index = clampi(_zoom_index + step, 0, ZOOM_LEVELS.size())
	_follow_playhead(true)
	_timeline.invalidate()


func scroll_timeline(direction: float) -> void:
	var ahead := view_beats() * 0.15 * direction
	var end := chart().content_end_beat() + chart().bar_length() if chart() != null else 0.0
	_view_start = clampf(_view_start + ahead, 0.0, maxf(0.0, end - view_beats()))
	_timeline.invalidate()


func _follow_playhead(force: bool = false) -> bool:
	if not force and not follow_playhead_view:
		return false
	var before := _view_start
	var span := view_beats()
	if chart() != null and span >= chart().content_end_beat() + chart().bar_length():
		# 「全部」能看到整张谱：播放头走动时不要把它重新滚走。
		_view_start = 0.0
		return not is_equal_approx(before, _view_start)
	var beat := playhead()
	# 按页跳而不是每帧连续滚：静态内容层不用每帧重绘。
	if force or beat < _view_start or beat > _view_start + span * 0.9:
		_view_start = maxf(0.0, beat - span * 0.3)
	return not is_equal_approx(before, _view_start)


func seek(beat: float) -> void:
	if _app != null:
		_app.seek(beat)


func dragging() -> bool:
	return not _drag_kind.is_empty() or scrubbing()


## 正在拖时间轴的播放头。拖过关键帧时不要重建面板：一次重建 ≈70–80 个控件，
## 拖动时每跨一帧都要付两遍（进/出各一次），这就是「经过关键帧极卡」的来源。
func scrubbing() -> bool:
	return _timeline != null and _timeline._drag_kind == "playhead"


## 拖动播放头结束：面板与洋葱皮补一次，拖动过程中全部跳过。
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
	_timeline.invalidate()


func snap(beat: float) -> float:
	return float(_app.snap_beat(beat, false)) if _app != null else beat


# ---- RingTimeline 的回调：把手势/撤销细节留在 App --------------------------

func begin_edit() -> void:
	if _app != null:
		_app.begin_edit()


func touch_chart() -> void:
	if _app != null:
		_app.touch_chart()


func finish_edit() -> void:
	if _app != null:
		_app.finish_edit()


func mutate_chart(callback: Callable) -> void:
	if _app != null:
		_app.mutate(callback)


func gesture_mutate_chart(callback: Callable) -> void:
	if _app != null:
		_app.gesture_mutate(callback)


## 按当前吸附细分步进播放头：1/4、1/8… 没有吸附时退 1/4 拍。
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
	# 每帧写 Label / SpinBox 会让整页 UI 重新排版（实测 78ms/帧）；
	# 只在显示值变化时写，并且限到 ~12Hz。播放头位置本身仍然是逐帧的。
	var now := Time.get_ticks_msec()
	if not force and now - _sync_last_msec < 80:
		return
	_sync_last_msec = now
	var beat := playhead()
	if not is_equal_approx(beat, _sync_last_beat):
		_sync_last_beat = beat
		# SpinBox / Label 的文本一变就会触发整页重新排版（实测 ~40ms），
		# 所以只在显示值真的变了才写：拍数按 1/4 拍、时间按 0.1 拍。
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
		var suffix := "无关键帧"
		if view != null:
			suffix = "镜头帧 %d" % view.id
		elif not key.is_empty():
			suffix = "形状帧 " + String(key.get("shape_id", ""))
		var text := "拍 %.1f，%s" % [beat, suffix]
		if _title.text != text:
			_title.text = text
	# 播放/拖时间跨过关键帧时，右侧按钮跟着换。
	var key_beat := float(key.get("beat", -999.0)) if not key.is_empty() else -999.0
	if not is_equal_approx(key_beat, _last_key_beat) and not dragging():
		_last_key_beat = key_beat
		# 新面板按选中重建，不按播放头；跨关键帧只更新洋葱皮。
		_update_onion()


func _current_shape() -> BoundaryShape:
	var key := current_key()
	if not key.is_empty():
		return chart().get_shape(String(key.get("shape_id", "")))
	return null


func _rebuild_thumbs() -> void:
	var chart_data := chart()
	if chart_data == null:
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
		"rotation":
			state.rotation = value
		"tilt_x":
			state.tilt_x = value
		"tilt_y":
			state.tilt_y = value
		"ellipse":
			state.ellipse = value


func _on_ring_zoom(delta: float) -> void:
	var view := _active_view()
	var target := clampf(float(view.get("zoom", 1.0)) + delta, 0.75, 1.4)
	_app.gesture_mutate(func() -> void: _apply_view("zoom", target))


func _on_ring_rotate(degrees: float) -> void:
	var view := _active_view()
	var target := clampf(float(view.get("rotation", 0.0)) + degrees, -180.0, 180.0)
	# 旋转是拖动出来的连续量：整段拖动合成一条撤销。
	_app.gesture_mutate(func() -> void: _apply_view("rotation", target))
	_preview.queue_redraw()


func _add_view_keyframe() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var at := playhead()
	for existing in chart_data.view_states:
		if absf(existing.beat - at) < 0.001:
			_app.select_view(chart_data.view_states.find(existing))
			if _timeline != null:
				_timeline._select_only("view", existing.id)
			return
	var current := BoundaryRuntime.eval_view(chart_data, at)
	var state := ViewState.new(at, float(current.get("zoom", 1.0)), float(current.get("tilt_x", 0.0)),
		float(current.get("tilt_y", 0.0)), float(current.get("ellipse", 1.0)), float(current.get("rotation", 0.0)))
	state.id = chart_data.next_key_id()
	_app.mutate(func() -> void:
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
	_app.mutate(func() -> void:
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


## 把当前拍实际显示的轮廓定型成一个新形状。
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


func _add_key() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	if not current_key().is_empty():
		_set_hint("播放头已经在关键帧上了。")
		return
	var beat := playhead()
	var shape := _snapshot_shape(beat)
	_app.mutate(func() -> void:
		chart_data.shapes[shape.id] = shape
		chart_data.shape_keys.append({"beat": beat, "shape_id": shape.id, "easing": "in-out",
			"id": chart_data.next_key_id()})
		_app.select_shape(shape.id)
		_app.select_segment(0)
	)
	var created := chart_data.shape_key_at(beat)
	if not created.is_empty() and _timeline != null:
		_timeline._select_only("shape", int(created.get("id", 0)))
	_refresh()
	_set_hint("已加关键帧 %s；点「编辑形状（2D）」开始画。" % shape.id)


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
	_app.mutate(func() -> void:
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
	var index: int = clampi(int(_app.selected_segment_index), 0, shape.vertex_count() - 1)
	_app.mutate(func() -> void: shape.set_gap(index, not shape.segment_has_gap(index)))
	_refresh()


func _new_shape() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var id := _next_shape_id()
	_app.mutate(func() -> void:
		chart_data.shapes[id] = BoundaryShape.circle(id, 330.0, BoundaryShape.DEFAULT_VERTICES)
	)
	_app.select_shape(id)
	_refresh()


func _duplicate_shape() -> void:
	var shape := _current_shape()
	var chart_data := chart()
	if shape == null or chart_data == null:
		return
	var copy := BoundaryShape.from_dict(shape.to_dict())
	copy.id = _next_shape_id()
	_app.mutate(func() -> void:
		chart_data.shapes[copy.id] = copy
	)
	_app.select_shape(copy.id)
	_refresh()


func _delete_shape() -> void:
	var shape := _current_shape()
	var chart_data := chart()
	if shape == null or chart_data == null or chart_data.shapes.size() <= 1:
		return
	if shape.id == chart_data.default_shape_id:
		_set_hint("默认形状不能删。")
		return
	_app.mutate(func() -> void:
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
		_add_key()
		key = current_key()
		if key.is_empty():
			return
	open_pad_for_shape(String(key.get("shape_id", "")))


func open_pad_for_shape(shape_id: String) -> void:
	if shape_id.is_empty():
		return
	_app.select_shape(shape_id)
	_pad.open(shape_id)


# ---- 时间轴拖拽 -------------------------------------------------------------

func begin_key_drag(key: Dictionary) -> void:
	_drag_kind = "key"
	_drag_key = key
	_app.begin_edit()


func begin_view_drag(state: ViewState) -> void:
	_drag_kind = "view"
	_drag_view = state
	_app.select_view(chart().view_states.find(state))
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
				_app.mutate(func() -> void:
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
