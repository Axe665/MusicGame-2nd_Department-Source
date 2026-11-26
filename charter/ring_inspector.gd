class_name RingInspector
extends VBoxContainer

## 右侧属性面板：单键 / 多选 / 段三种状态；所有标签使用中文。
## 面板只在选中或谱面结构变化时重建；拖动滑块期间不重建。

const CURVE_PRESETS := {
	"linear": [0.0, 0.0, 1.0, 1.0],
	"in": [0.42, 0.0, 1.0, 1.0],
	"out": [0.0, 0.0, 0.58, 1.0],
	"in-out": [0.42, 0.0, 0.58, 1.0],
}
const EASING_LABELS := ["线性", "缓入", "缓出", "缓入缓出", "自定义曲线"]
const EASING_KEYS := ["linear", "in", "out", "in-out", "custom"]

var workspace
var timeline
var _editing := false
var _building := false
var _gesture_timer: Timer
var _curve: CurveEdit
## 面板按「选择类型 + 结构」缓存；同结构只更新数值，不再重建中文 Label。
var _panel_key := ""
var _widgets: Dictionary = {}
## 已建好的面板按结构签名缓存：切回同一类选择时只切可见性，不再量中文 Label。
var _page_box: VBoxContainer = null
var _pages: Dictionary = {}
var _page_widgets: Dictionary = {}
var _page_curves: Dictionary = {}
## 页面里的闭包会捕获 chart 对象；撤销/换谱后必须整批作废。
var _pages_chart: Chart = null
var _sel_shapes: Array = []
var _sel_views: Array = []
var _command: AlphaCommand = null
var _shape_key: Dictionary = {}
var _view_key: ViewState = null
var _segment_key: Dictionary = {}
var _segment_view: ViewState = null
var _segment_lane := ""
var _shape_span := 0.0
var _view_span := 0.0
var _segment_span := 0.0


class CurveEdit:
	extends Control

	signal curve_changed(values: Array)
	signal drag_started
	signal drag_finished

	var values: Array = [0.42, 0.0, 0.58, 1.0]
	var _dragging := -1

	func _init() -> void:
		custom_minimum_size = Vector2(250, 132)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_values(raw: Array) -> void:
		if raw.size() == 4:
			values = [float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3])]
		queue_redraw()

	func _box() -> Rect2:
		return Rect2(Vector2(12, 10), Vector2(size.x - 24, size.y - 32))

	func _to_px(x: float, y: float) -> Vector2:
		var box := _box()
		return Vector2(box.position.x + x * box.size.x, box.position.y + (1.0 - y) * box.size.y)

	func _to_value(point: Vector2) -> Vector2:
		var box := _box()
		return Vector2(
			clampf((point.x - box.position.x) / maxf(1.0, box.size.x), 0.0, 1.0),
			clampf(1.0 - (point.y - box.position.y) / maxf(1.0, box.size.y), 0.0, 1.0))

	func _draw() -> void:
		var box := _box()
		draw_rect(box, Color("#0A0C11"))
		for i in range(1, 4):
			var t := float(i) / 4.0
			draw_line(Vector2(box.position.x + box.size.x * t, box.position.y),
				Vector2(box.position.x + box.size.x * t, box.end.y), Color(1, 1, 1, 0.05), 1.0)
			draw_line(Vector2(box.position.x, box.position.y + box.size.y * t),
				Vector2(box.end.x, box.position.y + box.size.y * t), Color(1, 1, 1, 0.05), 1.0)
		var points := PackedVector2Array()
		for i in 33:
			var t := float(i) / 32.0
			points.append(_to_px(t, Ease.bezier(values, t)))
		draw_polyline(points, UITheme.CYAN, 2.0, true)
		# 控制手柄
		var p1 := _to_px(float(values[0]), float(values[1]))
		var p2 := _to_px(float(values[2]), float(values[3]))
		draw_line(_to_px(0.0, 0.0), p1, Color(1, 1, 1, 0.18), 1.0)
		draw_line(_to_px(1.0, 1.0), p2, Color(1, 1, 1, 0.18), 1.0)
		draw_circle(p1, 5.0, UITheme.CORAL)
		draw_circle(p2, 5.0, UITheme.AMBER)
		draw_string(UITheme.mono_font(), Vector2(box.position.x, box.end.y + 15),
			"x1 %.2f  y1 %.2f    x2 %.2f  y2 %.2f" % [values[0], values[1], values[2], values[3]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.55))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var p1 := _to_px(float(values[0]), float(values[1]))
				var p2 := _to_px(float(values[2]), float(values[3]))
				if event.position.distance_to(p1) <= 10.0:
					_dragging = 0
				elif event.position.distance_to(p2) <= 10.0:
					_dragging = 1
				if _dragging >= 0:
					drag_started.emit()
					accept_event()
			else:
				if _dragging >= 0:
					_dragging = -1
					drag_finished.emit()
					accept_event()
		elif event is InputEventMouseMotion and _dragging >= 0:
			var value := _to_value(event.position)
			values[_dragging * 2] = value.x
			values[_dragging * 2 + 1] = value.y
			queue_redraw()
			curve_changed.emit(values)
			accept_event()


func _init(p_workspace, p_timeline) -> void:
	workspace = p_workspace
	timeline = p_timeline
	add_theme_constant_override("separation", 7)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gesture_timer = Timer.new()
	_gesture_timer.one_shot = true
	_gesture_timer.wait_time = 0.7
	_gesture_timer.timeout.connect(func() -> void:
		# 属性控件自己已经显示新值；只同步派生字段，不重建整页。
		_editing = false
		if _page_box != null:
			_cache_targets()
			_sync_values()
	)
	add_child(_gesture_timer)


## 选中对象变了：即使属性手势还没结束，也要切到新对象的页面。
func refresh_selection() -> void:
	_editing = false
	refresh()


func refresh(force: bool = false) -> void:
	if _building:
		return
	var current_chart = workspace.chart() if workspace != null else null
	if current_chart != _pages_chart:
		_clear_pages()
		_pages_chart = current_chart
		_editing = false
	if _editing and not force:
		return
	# 拖关键帧/拖播放头时先不建新页面；松手后的 ring_changed 再补。
	if not force and workspace != null and workspace.dragging():
		return
	var key := _panel_key_for_current()
	if key == _panel_key and not force:
		_cache_targets()
		_sync_values()
		return
	_building = true
	if _page_box != null:
		_page_box.visible = false
	if force:
		_free_cached_page(key)
	_panel_key = key
	_cache_targets()
	if _restore_page(key):
		_building = false
		return
	_page_box = VBoxContainer.new()
	_page_box.add_theme_constant_override("separation", 7)
	add_child(_page_box)
	_curve = null
	_widgets = {}
	_build()
	_pages[key] = _page_box
	_page_widgets[key] = _widgets
	_page_curves[key] = _curve
	_building = false


func _add(node: Node) -> void:
	if _page_box != null:
		_page_box.add_child(node)
	else:
		add_child(node)


func _clear_pages() -> void:
	for key in _pages.keys():
		_free_cached_page(String(key))
	_page_box = null
	_panel_key = ""
	_widgets = {}
	_curve = null


func _free_cached_page(key: String) -> void:
	if not _pages.has(key):
		return
	var page = _pages[key]
	if is_instance_valid(page):
		page.queue_free()
	_pages.erase(key)
	_page_widgets.erase(key)
	_page_curves.erase(key)


func _exit_tree() -> void:
	for key in _pages.keys():
		_free_cached_page(String(key))


func _restore_page(key: String) -> bool:
	if not _pages.has(key):
		return false
	if _page_box != null:
		_page_box.visible = false
	_page_box = _pages[key]
	_page_box.visible = true
	_widgets = _page_widgets[key]
	_curve = _page_curves[key]
	_sync_values()
	return true


## 结构签名：选择类型、过渡段有无、形状库大小、指令条数。
## 同一签名只同步数值；改 beat/形状/过滤类型等会自然落到新签名并重建。
func _panel_key_for_current() -> String:
	var chart = workspace.chart() if workspace != null else null
	if chart == null or timeline == null:
		return ""
	var command: AlphaCommand = timeline.selected_command()
	if command != null:
		return "cmd:" + command.name
	var shapes: Array = timeline.selected_shape_keys()
	var views: Array = timeline.selected_views()
	if shapes.is_empty() and views.is_empty():
		var occupied: bool = not workspace.current_key().is_empty()
		if not occupied:
			for state in chart.view_states:
				if absf(state.beat - workspace.playhead()) < 0.001:
					occupied = true
					break
		return "empty:%d:%d:%d:%d:%d" % [chart.shapes.size(), chart.shape_keys.size(),
			chart.view_states.size(), chart.commands.size(), 1 if occupied else 0]
	var seg_key: Dictionary = timeline.segment_shape_key()
	var seg_view: ViewState = timeline.segment_view()
	if not seg_key.is_empty() or seg_view != null:
		var lane := "shape" if not seg_key.is_empty() else "view"
		return "seg:" + lane
	if shapes.size() == 1 and views.is_empty():
		return "shape:%d" % chart.shapes.size()
	if views.size() == 1 and shapes.is_empty():
		return "view"
	return "multi:%d:%d:%d" % [shapes.size(), views.size(), chart.commands.size()]


func _cache_targets() -> void:
	var chart = workspace.chart() if workspace != null else null
	if chart == null or timeline == null:
		_sel_shapes = []
		_sel_views = []
		_command = null
		_shape_key = {}
		_view_key = null
		_segment_key = {}
		_segment_view = null
		_segment_lane = ""
		return
	_command = timeline.selected_command()
	_sel_shapes = timeline.selected_shape_keys()
	_sel_views = timeline.selected_views()
	_shape_key = _sel_shapes[0] if _sel_shapes.size() == 1 else {}
	_view_key = _sel_views[0] if _sel_views.size() == 1 else null
	_segment_key = timeline.segment_shape_key()
	_segment_view = timeline.segment_view()
	_segment_lane = "shape" if not _segment_key.is_empty() else ("view" if _segment_view != null else "")
	if not _shape_key.is_empty():
		var beat := float(_shape_key.get("beat", 0.0))
		_shape_span = maxf(0.0, beat - _previous_key_beat(chart, "shape", beat))
	if _view_key != null:
		_view_span = maxf(0.0, _view_key.beat - _previous_key_beat(chart, "view", _view_key.beat))
	if _segment_lane == "shape":
		var beat := float(_segment_key.get("beat", 0.0))
		_segment_span = maxf(0.0, beat - _previous_key_beat(chart, "shape", beat))
	elif _segment_lane == "view" and _segment_view != null:
		_segment_span = maxf(0.0, _segment_view.beat - _previous_key_beat(chart, "view", _segment_view.beat))


func _build() -> void:
	var chart = workspace.chart() if workspace != null else null
	if chart == null:
		return
	_add_title("属性")
	if timeline == null:
		_add_hint("时间轴还没准备好。")
		return
	if _command != null:
		_build_command(chart, _command)
		return
	if _sel_shapes.is_empty() and _sel_views.is_empty():
		_build_empty(chart)
		return
	if not _segment_key.is_empty() or _segment_view != null:
		_build_segment(chart)
		return
	if _sel_shapes.size() == 1 and _sel_views.is_empty():
		_build_shape_key(chart, _shape_key)
		return
	if _sel_views.size() == 1 and _sel_shapes.is_empty():
		_build_camera_key(chart, _view_key)
		return
	_build_multi(chart, _sel_shapes, _sel_views)


## 同结构换选中对象：只把新值写回控件，不重建 Label/Container。
func _sync_values() -> void:
	if _panel_key.begins_with("shape:"):
		_sync_shape()
	elif _panel_key.begins_with("view:"):
		_sync_view()
	elif _panel_key.begins_with("seg:"):
		_sync_segment()
	elif _panel_key.begins_with("cmd:"):
		_sync_command()
	elif _panel_key.begins_with("empty:"):
		var chart = workspace.chart()
		if chart != null:
			_set_label("empty_playhead", "%.2f 拍" % workspace.playhead())
			_set_label("empty_shapes", str(chart.shapes.size()))
			_set_label("empty_keys", str(chart.shape_keys.size()))
			_set_label("empty_views", str(chart.view_states.size()))
	elif _panel_key.begins_with("multi:"):
		_set_label("multi_counts", "%d 个形状帧 · %d 个镜头帧" % [_sel_shapes.size(), _sel_views.size()])
		_set_label("multi_start", "%.2f 拍" % _selection_start(_sel_shapes, _sel_views))


func _set_label(key: String, text: String) -> void:
	var node: Label = _widgets.get(key)
	if node != null and node.text != text:
		node.text = text


func _set_visible(key: String, visible: bool) -> void:
	var node = _widgets.get(key)
	if node is CanvasItem and node.visible != visible:
		node.visible = visible


func _set_spin(key: String, value: float) -> void:
	var node = _widgets.get(key)
	if node is SpinBox and not is_equal_approx(node.value, value):
		node.set_value_no_signal(value)


func _set_slider(key: String, value: float, maximum: float = NAN) -> void:
	var slider = _widgets.get(key + ":slider")
	if slider is HSlider:
		if is_finite(maximum) and not is_equal_approx(slider.max_value, maximum):
			slider.max_value = maximum
			slider.set_value_no_signal(clampf(value, slider.min_value, maximum))
		elif not is_equal_approx(slider.value, value):
			slider.set_value_no_signal(value)
	var spin = _widgets.get(key + ":spin")
	if spin is SpinBox:
		if is_finite(maximum) and not is_equal_approx(spin.max_value, maximum):
			spin.max_value = maximum
		if not is_equal_approx(spin.value, value):
			spin.set_value_no_signal(value)


func _set_option(key: String, index: int) -> void:
	var option = _widgets.get(key)
	if option is OptionButton and option.selected != index:
		option.select(index)


func _set_check(key: String, value: bool) -> void:
	var check = _widgets.get(key)
	if check is CheckButton and check.button_pressed != value:
		check.set_pressed_no_signal(value)


func _sync_shape() -> void:
	if _shape_key.is_empty():
		return
	_set_label("shape_id", str(int(_shape_key.get("id", 0))))
	_set_spin("shape_beat", float(_shape_key.get("beat", 0.0)))
	var ids: Array = workspace.chart().shapes.keys()
	ids.sort()
	_set_option("shape_pick", maxi(0, ids.find(String(_shape_key.get("shape_id", "")))))
	var chart = workspace.chart()
	var locked: bool = chart != null and String(_shape_key.get("shape_id", "")) == chart.default_shape_id
	_set_visible("shape_locked", locked)
	var has_span := _shape_span > 0.0001
	_set_visible("shape_enter:row", has_span)
	_set_visible("shape_morph:box", has_span)
	_set_visible("shape_morph_row", has_span)
	_set_visible("eg_easing:row", has_span)
	_set_visible("shape_no_transition", not has_span)
	if _curve != null:
		_curve.visible = has_span
	if has_span:
		var beat := float(_shape_key.get("beat", 0.0))
		_set_label("shape_enter", "%.2f 拍 → 本帧" % (beat - _shape_span))
		_set_slider("shape_morph", BoundaryRuntime.morph_beats(_shape_key, _shape_span), _shape_span)
	_sync_curve()


func _sync_view() -> void:
	if _view_key == null:
		return
	_set_label("view_id", str(_view_key.id))
	_set_spin("view_beat", _view_key.beat)
	_set_slider("view_dolly", _view_key.dolly)
	_set_slider("view_rot", _view_key.rotation)
	var has_span := _view_span > 0.0001
	_set_visible("view_enter:row", has_span)
	_set_visible("view_morph:box", has_span)
	_set_visible("view_morph_row", has_span)
	_set_visible("eg_easing:row", has_span)
	_set_visible("view_no_transition", not has_span)
	if _curve != null:
		_curve.visible = has_span
	if has_span:
		_set_label("view_enter", "%.2f 拍 → 本帧" % (_view_key.beat - _view_span))
		_set_slider("view_morph", _view_key.morph_beats(_view_span), _view_span)
	_sync_curve()


func _sync_segment() -> void:
	var chart = workspace.chart()
	if chart == null:
		return
	var target := _segment_target_beat()
	var previous := target - _segment_span
	_set_label("seg_dir", "%.2f 拍 → %.2f 拍（目标帧）" % [previous, target])
	_set_label("seg_len", RingWorkspace.span_label(_segment_span, maxf(1.0, chart.timing.beats_per_bar_at(previous))))
	var has_span := _segment_span > 0.0001
	_set_visible("seg_morph:box", has_span)
	_set_visible("seg_morph_row", has_span)
	_set_visible("eg_easing:row", has_span)
	_set_visible("seg_no_transition", not has_span)
	if _curve != null:
		_curve.visible = has_span
	if has_span:
		_set_slider("seg_morph", _segment_morph(), _segment_span)
	_sync_curve()


func _sync_curve() -> void:
	if _curve == null:
		return
	var easing := _current_easing()
	var curve := _current_curve()
	var index := 4 if curve.size() == 4 else EASING_KEYS.find(easing)
	_set_option("eg_easing", maxi(0, index))
	var display: Array = curve
	if display.size() != 4:
		display = CURVE_PRESETS.get(easing, CURVE_PRESETS["in-out"])
	_curve.set_values(display)


func _sync_command() -> void:
	if _command == null:
		return
	_set_label("cmd_id", _command.id)
	_set_spin("cmd_beat", _command.beat)
	_set_spin("cmd_duration", _command.duration)
	_set_option("cmd_easing", maxi(0, ["linear", "ease_in", "ease_out", "ease_in_out"].find(_command.easing)))
	_set_check("cmd_enabled", _command.enabled)
	for entry in _command.spec().get("params", []):
		var param: Dictionary = entry
		var key := String(param.get("key", ""))
		var kind := String(param.get("type", "float"))
		var widget = _widgets.get("p:" + key)
		if widget == null:
			continue
		match kind:
			"bool":
				if widget is CheckButton:
					widget.set_pressed_no_signal(_command.flag(key))
			"text":
				if widget is LineEdit and widget.text != _command.text_value(key):
					widget.set_block_signals(true)
					widget.text = _command.text_value(key)
					widget.set_block_signals(false)
			"color":
				if widget is ColorPickerButton:
					widget.set_block_signals(true)
					widget.color = _command.color_value(key)
					widget.set_block_signals(false)
				_set_label("p:" + key + ":info", _command.text_value(key, "#ffffff"))
			"option":
				if widget is OptionButton:
					var options: Array = param.get("options", [])
					var current := String(_command.params.get(key, param.get("default", "")))
					var index := options.find(current)
					if index >= 0:
						widget.select(index)
			_:
				if widget is SpinBox:
					widget.set_value_no_signal(_command.number(key))
	for key in ["reg_on", "reg_angle", "reg_span", "reg_inner", "reg_outer", "reg_feather"]:
		var node = _widgets.get(key)
		if node == null:
			continue
		if key == "reg_on":
			if node is CheckButton:
				node.set_pressed_no_signal(_command.flag("region_on", false))
		elif key == "reg_angle":
			if node is SpinBox:
				node.set_value_no_signal(_command.number("region_angle", 0.0))
		elif key == "reg_span":
			if node is SpinBox:
				node.set_value_no_signal(_command.number("region_span", 360.0))
		elif key == "reg_inner":
			if node is SpinBox:
				node.set_value_no_signal(_command.number("region_inner", 0.0))
		elif key == "reg_outer":
			if node is SpinBox:
				node.set_value_no_signal(_command.number("region_outer", 1.0))
		elif key == "reg_feather" and node is SpinBox:
			node.set_value_no_signal(_command.number("region_feather", 0.1))


func _build_empty(chart: Chart) -> void:
	_add_hint("点关键帧选中；Ctrl/Shift 加选；拖空白框选。\n选中色带可编辑这一段；选中关键帧可改参数。")
	_add_sep()
	_add_info("播放头", "%.2f 拍" % workspace.playhead(), "empty_playhead")
	var occupied: bool = not workspace.current_key().is_empty()
	for state in chart.view_states:
		if absf(state.beat - workspace.playhead()) < 0.001:
			occupied = true
			break
	if occupied:
		_add_hint("播放头已经有帧了；再插入会自动放到下一拍，连点可以连续加。")
	_add_button("＋ 插入形状帧", func() -> void: workspace.open_insert_menu())
	_add_button("＋ 打镜头帧", func() -> void: workspace._add_view_keyframe())
	_add_sep()
	_add_info("形状数", str(chart.shapes.size()), "empty_shapes")
	_add_info("形状帧", str(chart.shape_keys.size()), "empty_keys")
	_add_info("镜头帧", str(chart.view_states.size()), "empty_views")
	_build_command_sections(chart)


func _build_multi(chart: Chart, shapes: Array, views: Array) -> void:
	_add_info("已选", "%d 个形状帧 · %d 个镜头帧" % [shapes.size(), views.size()], "multi_counts")
	_add_hint("多选按拍整体拖动；跨轨也会一起移动。")
	_add_sep()
	_add_button("复制 (Ctrl+C)", func() -> void: timeline.copy_selection())
	_add_button("粘贴 (Ctrl+V)", func() -> void: timeline.paste())
	_add_button("删除 / 清除选中帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("左移一拍", func() -> void: timeline.nudge_selection(-1.0))
	_add_button("右移一拍", func() -> void: timeline.nudge_selection(1.0))
	_add_button("插入 1 拍（当前轨）", func() -> void: timeline.insert_frames(1.0))
	_add_sep()
	_add_info("起点", "%.2f 拍" % _selection_start(shapes, views), "multi_start")
	_build_command_sections(chart)


## 演出指令参数页：起始拍、持续拍数、缓动、启用和各指令自己的参数。
func _build_command(chart: Chart, command: AlphaCommand) -> void:
	_add_title("演出指令 · " + command.label())
	_add_info("类别", command.category_label())
	_add_info("编号", command.id, "cmd_id")
	if not command.hint().is_empty():
		_add_hint(command.hint())
	_add_sep()
	_add_spin("起始拍", command.beat, 0.0, 100000.0, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.beat = maxf(0.0, value)
				chart.commands.sort_custom(func(a: AlphaCommand, b: AlphaCommand) -> bool: return a.beat < b.beat)
		)
	, "cmd_beat")
	_add_spin("持续拍数", command.duration, 0.0, 64.0, 0.25, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.duration = maxf(0.0, value)
		)
	, "cmd_duration")
	_add_hint("三段包络的起手/收尾各占 25%；持续拍数为 0 时按瞬时指令处理。")
	var easing_keys := ["linear", "ease_in", "ease_out", "ease_in_out"]
	var easing_labels := ["线性", "缓入", "缓出", "缓入缓出"]
	var easing_index := easing_keys.find(command.easing)
	_add_option("过渡曲线", easing_labels, maxi(0, easing_index), func(index: int) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.easing = easing_keys[clampi(index, 0, easing_keys.size() - 1)]
		)
	, "cmd_easing")
	_add_check("启用", command.enabled, func(value: bool) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.enabled = value
		)
	, "cmd_enabled")
	_add_sep()
	if command.category() == AlphaCommand.CATEGORY_FILTER:
		_build_filter_type(command)
	for entry in command.spec().get("params", []):
		_build_command_param(command, entry as Dictionary)
	if command.category() == AlphaCommand.CATEGORY_FILTER:
		_build_filter_envelope(command)
		_build_filter_region(command)
	_add_sep()
	_add_button("删除这条指令 (Del)", func() -> void:
		if _command != null:
			timeline.delete_command(_command)
	)
	_add_button("播放头跳到这里", func() -> void:
		if _command != null:
			workspace.seek(_command.beat)
	)


func _build_filter_type(command: AlphaCommand) -> void:
	var entries := AlphaCommand.catalog(AlphaCommand.CATEGORY_FILTER)
	var labels: Array[String] = []
	var names: Array[String] = []
	var selected := 0
	for i in entries.size():
		var entry := entries[i]
		labels.append(String(entry.get("label", entry.get("name", ""))))
		names.append(String(entry.get("name", "")))
		if names[i] == command.name:
			selected = i
	_add_option("滤镜类型", labels, selected, func(index: int) -> void:
		if _command != null:
			_change_filter_type(_command, names[clampi(index, 0, names.size() - 1)])
	)
	_add_hint("改类型会按新滤镜的默认参数重建；起始拍、时长和启用状态保留。")


func _change_filter_type(command: AlphaCommand, new_name: String) -> void:
	if command == null or new_name.is_empty() or command.name == new_name:
		return
	workspace.mutate_chart(func() -> void:
		command.name = new_name
		command.params = AlphaCommand.defaults(new_name)
	)


func _build_filter_envelope(command: AlphaCommand) -> void:
	_add_sep()
	_add_title("包络")
	_add_spin("进入比例", command.number("attack", 0.25), 0.0, 0.9, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["attack"] = clampf(value, 0.0, 0.9)
		)
	, "cmd_attack")
	_add_spin("退出比例", command.number("release", 0.25), 0.0, 0.9, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["release"] = clampf(value, 0.0, 0.9)
		)
	, "cmd_release")
	_add_hint("占整条指令时长的比例：0 = 硬切，0.25 = 前/后 1/4 时长做渐变。")


func _build_filter_region(command: AlphaCommand) -> void:
	_add_sep()
	_add_title("作用区域")
	_add_check("启用区域（只作用于环的一部分）", command.flag("region_on", false), func(value: bool) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_on"] = value
		)
	, "reg_on")
	_add_spin("起始角", command.number("region_angle", 0.0), 0.0, 360.0, 1.0, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_angle"] = fposmod(value, 360.0)
		)
	, "reg_angle")
	_add_spin("角度跨度", command.number("region_span", 360.0), 0.0, 360.0, 1.0, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_span"] = clampf(value, 0.0, 360.0)
		)
	, "reg_span")
	_add_spin("内半径", command.number("region_inner", 0.0), 0.0, 2.0, 0.01, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_inner"] = clampf(value, 0.0, 2.0)
		)
	, "reg_inner")
	_add_spin("外半径", command.number("region_outer", 1.0), 0.0, 2.0, 0.01, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_outer"] = clampf(value, 0.0, 2.0)
		)
	, "reg_outer")
	_add_spin("羽化", command.number("region_feather", 0.1), 0.0, 0.5, 0.01, func(value: float) -> void:
		_edit(func() -> void:
			if _command != null:
				_command.params["region_feather"] = clampf(value, 0.0, 0.5)
		)
	, "reg_feather")
	_add_hint("0=圆心，1=判定环；0°=右、90°=上。起点 0°、跨度 360° 就是整环。")


func _build_command_param(command: AlphaCommand, param: Dictionary) -> void:
	var key := String(param.get("key", ""))
	if key.is_empty():
		return
	var kind := String(param.get("type", "float"))
	var label := String(param.get("label", key))
	var widget := "p:" + key
	match kind:
		"bool":
			_add_check(label, command.flag(key), func(value: bool) -> void:
				_edit(func() -> void:
					if _command != null:
						_command.params[key] = value
				)
			, widget)
		"text":
			var edit := LineEdit.new()
			edit.text = command.text_value(key)
			edit.placeholder_text = label
			edit.add_theme_font_size_override("font_size", 11)
			edit.text_changed.connect(func(value: String) -> void:
				_edit(func() -> void:
					if _command != null:
						_command.params[key] = value
				)
			)
			_add(edit)
			_widgets[widget] = edit
		"color":
			_add_info(label, command.text_value(key, "#ffffff"), widget + ":info")
			var picker := ColorPickerButton.new()
			picker.edit_alpha = true
			picker.color = command.color_value(key)
			picker.custom_minimum_size = Vector2(0, 26)
			picker.color_changed.connect(func(value: Color) -> void:
				_edit(func() -> void:
					if _command != null:
						_command.params[key] = value.to_html(true)
				)
			)
			_add(picker)
			_widgets[widget] = picker
		"option":
			var options: Array = param.get("options", [])
			if options.is_empty():
				return
			var current := String(command.params.get(key, param.get("default", "")))
			var index := options.find(current)
			_add_option(label, options, maxi(0, index), func(picked: int) -> void:
				_edit(func() -> void:
					if _command != null:
						_command.params[key] = String(options[clampi(picked, 0, options.size() - 1)])
				)
			, widget)
		_:
			var step := float(param.get("step", 1.0))
			var minimum := float(param.get("min", 0.0))
			var maximum := float(param.get("max", 100.0))
			_add_spin(label, command.number(key), minimum, maximum, step, func(value: float) -> void:
				_edit(func() -> void:
					if _command != null:
						_command.params[key] = int(value) if kind == "int" else value
				)
			, widget)


## 没有选中指令时，在属性页底部给出三类指令的“添加”入口和已有列表。
func _build_command_sections(chart: Chart) -> void:
	_add_sep()
	_add_title("演出指令")
	_add_hint("双击时间轴「判定线 / 文本 / 滤镜」轨空白处也能新增；点指令块选中后在这里改参数。")
	for category in [AlphaCommand.CATEGORY_JLINE, AlphaCommand.CATEGORY_TEXT, AlphaCommand.CATEGORY_FILTER]:
		var entries := AlphaCommand.catalog(category)
		if entries.is_empty():
			continue
		var commands := chart.commands_in(category)
		_add_info(String(AlphaCommand.CATEGORY_LABELS.get(category, category)), "%d 条" % commands.size())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_theme_font_size_override("font_size", 11)
		for entry in entries:
			picker.add_item(String(entry.get("label", entry.get("name", ""))))
		row.add_child(picker)
		var chosen: Array = [0]
		picker.item_selected.connect(func(index: int) -> void: chosen[0] = index)
		row.add_child(_small_button("＋ 播放头", func() -> void:
			var index := clampi(int(chosen[0]), 0, entries.size() - 1)
			timeline.add_command_of(String(entries[index].get("name", "")), workspace.playhead())
		))
		_add(row)
		for entry in commands:
			var command := entry as AlphaCommand
			if command == null:
				continue
			var picked: AlphaCommand = command
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 4)
			var select := _small_button("%s  @%.2f" % [picked.label(), picked.beat],
				func() -> void: timeline.select_command(picked))
			select.alignment = HORIZONTAL_ALIGNMENT_LEFT
			line.add_child(select)
			line.add_child(_tiny_button("×", func() -> void: timeline.delete_command(picked)))
			_add(line)


func _selection_start(shapes: Array, views: Array) -> float:
	var low := INF
	for key in shapes:
		low = minf(low, float(key.get("beat", 0.0)))
	for state in views:
		low = minf(low, state.beat)
	return 0.0 if not is_finite(low) else low


## 目标帧的入场过渡从哪一拍开始：上一帧；第一帧则是 0 拍的基础圆。
func _previous_key_beat(chart: Chart, lane: String, beat: float) -> float:
	var previous := 0.0
	if lane == "shape":
		for key in chart.sorted_shape_keys():
			var value := float(key.get("beat", 0.0))
			if value < beat - 0.0001:
				previous = maxf(previous, value)
	else:
		for state in chart.sorted_view_states():
			if state.beat < beat - 0.0001:
				previous = maxf(previous, state.beat)
	return previous


func _build_segment(chart: Chart) -> void:
	var lane := _segment_lane
	var span := _segment_span
	var morph := _segment_morph()
	var previous := _segment_target_beat() - span
	_add_title("过渡段")
	_add_info("方向", "%.2f 拍 → %.2f 拍（目标帧）" % [previous, _segment_target_beat()], "seg_dir")
	_add_info("段长", RingWorkspace.span_label(span, maxf(1.0, chart.timing.beats_per_bar_at(previous))), "seg_len")
	_add_sep()
	_add_slider("过渡时长（拍）", morph, 0.0, maxf(span, 0.001), 0.05, func(value: float) -> void:
		_set_segment_morph(value)
	, "seg_morph")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_small_button("硬切", func() -> void: _set_segment_morph(0.0)))
	row.add_child(_small_button("整段", func() -> void: _set_segment_morph(_segment_span)))
	_add(row)
	_widgets["seg_morph_row"] = row
	_add_hint("过渡在目标帧前完成：0 拍 = 目标帧处硬切，整段 = 从头到尾一直在变。")
	_add_hint("目标帧在第 0 拍：没有入场过渡可调。", "seg_no_transition")
	_add_segment_easing(_segment_easing(), _segment_curve())
	_add_sep()
	_add_button("选中目标帧", func() -> void: _select_segment_target())
	if lane == "shape":
		_add_button("＋ 在下一拍插入形状帧", func() -> void: workspace.insert_next_shape())
	elif _segment_view != null:
		_add_button("＋ 在下一拍插入镜头帧", func() -> void: workspace.insert_next_view())


func _build_shape_key(chart: Chart, key: Dictionary) -> void:
	var beat := float(key.get("beat", 0.0))
	var previous := beat - _shape_span
	_add_title("形状关键帧")
	_add_info("编号", str(int(key.get("id", 0))), "shape_id")
	_add_spin("拍", beat, 0.0, 100000.0, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			_shape_key["beat"] = value
			chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
		)
	, "shape_beat")
	_add_sep()
	var ids: Array = chart.shapes.keys()
	ids.sort()
	var current := ids.find(String(key.get("shape_id", "")))
	_add_option("形状", ids, maxi(0, current), func(index: int) -> void:
		_edit(func() -> void:
			if not _shape_key.is_empty():
				_shape_key["shape_id"] = String(ids[index])
		)
	, "shape_pick")
	_add_button("编辑形状（2D）", func() -> void:
		workspace.seek(float(_shape_key.get("beat", 0.0)))
		workspace.open_pad_for_current()
	)
	_add_hint("这是基础圆 S0（锁定）；先「复制」一个形状再编辑。", "shape_locked")
	_add_button("切断/恢复这一段 (G)", func() -> void:
		workspace.seek(float(_shape_key.get("beat", 0.0)))
		workspace._toggle_gap()
	)
	_add_button("删除这一帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("＋ 在下一拍插入形状帧", func() -> void: workspace.insert_next_shape())
	_add_sep()
	var morph := BoundaryRuntime.morph_beats(key, _shape_span)
	_add_info("入场", "%.2f 拍 → 本帧" % previous, "shape_enter")
	_add_slider("过渡时长（拍）", morph, 0.0, maxf(_shape_span, 0.001), 0.05, func(value: float) -> void:
		_edit(func() -> void: _shape_key["morph"] = clampf(value, 0.0, _shape_span))
	, "shape_morph")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_small_button("硬切", func() -> void: _edit(func() -> void: _shape_key["morph"] = 0.0)))
	row.add_child(_small_button("整段", func() -> void: _edit(func() -> void: _shape_key["morph"] = _shape_span)))
	_add(row)
	_widgets["shape_morph_row"] = row
	_add_segment_easing(String(key.get("easing", "in-out")), key.get("curve", []))
	_add_hint("第 0 拍是起点：没有入场过渡。", "shape_no_transition")


func _build_camera_key(chart: Chart, state: ViewState) -> void:
	var previous := state.beat - _view_span
	_add_title("镜头关键帧")
	_add_info("编号", str(state.id), "view_id")
	_add_spin("拍", state.beat, 0.0, 100000.0, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			if _view_key != null:
				_view_key.beat = value
				chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		)
	, "view_beat")
	_add_sep()
	_add_hint("环始终在画面中心，只做推拉和滚转。")
	_add_sep()
	_add_slider("推拉（1=标准）", state.dolly, 0.6, 1.6, 0.01, func(value: float) -> void:
		if _view_key != null:
			_edit(func() -> void: _view_key.dolly = value)
	, "view_dolly")
	_add_slider("滚转（度）", state.rotation, -180.0, 180.0, 1.0, func(value: float) -> void:
		if _view_key != null:
			_edit(func() -> void: _view_key.rotation = value)
	, "view_rot")
	_add_button("删除选中镜头帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("＋ 在下一拍插入镜头帧", func() -> void: workspace.insert_next_view())
	_add_sep()
	var morph := state.morph_beats(_view_span)
	_add_info("入场", "%.2f 拍 → 本帧" % previous, "view_enter")
	_add_slider("过渡时长（拍）", morph, 0.0, maxf(_view_span, 0.001), 0.05, func(value: float) -> void:
		if _view_key != null:
			_edit(func() -> void: _view_key.morph = clampf(value, 0.0, _view_span))
	, "view_morph")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_small_button("硬切", func() -> void:
		if _view_key != null:
			_edit(func() -> void: _view_key.morph = 0.0)
	))
	row.add_child(_small_button("整段", func() -> void:
		if _view_key != null:
			_edit(func() -> void: _view_key.morph = _view_span)
	))
	_add(row)
	_widgets["view_morph_row"] = row
	_add_segment_easing(state.easing, state.curve)
	_add_hint("第 0 拍是起点：镜头没有入场过渡。", "view_no_transition")


func _segment_target_beat() -> float:
	if _segment_lane == "shape":
		return float(_segment_key.get("beat", 0.0))
	return _segment_view.beat if _segment_view != null else 0.0


func _segment_morph() -> float:
	var span := _segment_span
	if _segment_lane == "shape" and not _segment_key.is_empty():
		return BoundaryRuntime.morph_beats(_segment_key, span)
	if _segment_view != null:
		return _segment_view.morph_beats(span)
	return 0.0


func _set_segment_morph(value: float) -> void:
	_edit(func() -> void:
		if _segment_lane == "shape" and not _segment_key.is_empty():
			_segment_key["morph"] = clampf(value, 0.0, _segment_span)
		elif _segment_view != null:
			_segment_view.morph = clampf(value, 0.0, _segment_span)
	)


func _segment_easing() -> String:
	if _segment_lane == "shape":
		return String(_segment_key.get("easing", "in-out"))
	return _segment_view.easing if _segment_view != null else "linear"


func _segment_curve() -> Array:
	if _segment_lane == "shape":
		return _segment_key.get("curve", [])
	return _segment_view.curve if _segment_view != null else []


func _select_segment_target() -> void:
	if _segment_lane == "shape":
		timeline._select_only("shape", int(_segment_key.get("id", 0)))
	elif _segment_view != null:
		timeline._select_only("view", _segment_view.id)


func _current_easing() -> String:
	if _segment_lane != "":
		return _segment_easing()
	if not _shape_key.is_empty():
		return String(_shape_key.get("easing", "in-out"))
	return _view_key.easing if _view_key != null else "in-out"


func _current_curve() -> Array:
	if _segment_lane != "":
		return _segment_curve()
	if not _shape_key.is_empty():
		return _shape_key.get("curve", [])
	return _view_key.curve if _view_key != null else []


func _set_current_easing(picked: String) -> void:
	_edit(func() -> void:
		var target := picked if picked != "custom" else "in-out"
		if _segment_lane == "shape" and not _segment_key.is_empty():
			_segment_key["easing"] = target
			if picked == "custom":
				if (_segment_key.get("curve", []) as Array).size() != 4:
					_segment_key["curve"] = [0.42, 0.25, 0.58, 0.75]
			else:
				_segment_key.erase("curve")
		elif _segment_view != null:
			_segment_view.easing = target
			if picked == "custom":
				if _segment_view.curve.size() != 4:
					_segment_view.curve = [0.42, 0.25, 0.58, 0.75]
			else:
				_segment_view.curve = []
		elif not _shape_key.is_empty():
			_shape_key["easing"] = target
			if picked == "custom":
				if (_shape_key.get("curve", []) as Array).size() != 4:
					_shape_key["curve"] = [0.42, 0.25, 0.58, 0.75]
			else:
				_shape_key.erase("curve")
		elif _view_key != null:
			_view_key.easing = target
			if picked == "custom":
				if _view_key.curve.size() != 4:
					_view_key.curve = [0.42, 0.25, 0.58, 0.75]
			else:
				_view_key.curve = []
	)


func _set_current_curve(values: Array) -> void:
	var curve: Array = [values[0], values[1], values[2], values[3]]
	if _segment_lane == "shape" and not _segment_key.is_empty():
		_segment_key["curve"] = curve
	elif _segment_view != null:
		_segment_view.curve = curve
	elif not _shape_key.is_empty():
		_shape_key["curve"] = curve
	elif _view_key != null:
		_view_key.curve = curve


func _add_segment_easing(easing: String, curve: Array) -> void:
	var label_index := EASING_KEYS.find(easing)
	if curve.size() == 4:
		label_index = 4
	if label_index < 0:
		label_index = 0
	_add_option("进入目标帧的缓动", EASING_LABELS, label_index,
		func(index: int) -> void: _set_current_easing(String(EASING_KEYS[index])),
		"eg_easing")
	var display: Array = curve
	if display.size() != 4:
		display = CURVE_PRESETS.get(easing, CURVE_PRESETS["in-out"])
	_curve = CurveEdit.new()
	_curve.set_values(display)
	_curve.drag_started.connect(func() -> void:
		workspace.begin_preview_drag()
		workspace.begin_edit())
	_curve.curve_changed.connect(func(values: Array) -> void:
		_editing = true
		_set_current_curve(values)
		workspace.touch_chart()
	)
	_curve.drag_finished.connect(func() -> void:
		_editing = false
		workspace.end_preview_drag()
		workspace.finish_edit()
	)
	_add(_curve)
	_add_hint("拖两个手柄改曲线；x 是时间，y 是进度。只在过渡段生效。")


func _next_key_beat(chart: Chart, lane: String, beat: float) -> float:
	var low := INF
	if lane == "shape":
		for key in chart.sorted_shape_keys():
			var value := float(key.get("beat", 0.0))
			if value > beat + 0.0001:
				low = minf(low, value)
	else:
		for state in chart.sorted_view_states():
			if state.beat > beat + 0.0001:
				low = minf(low, state.beat)
	# 没有下一帧返回 -1，调用方据此隐藏形变/缓动。
	return -1.0 if not is_finite(low) else low


# ---------------------------------------------------------------- 小部件


func _small_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 10)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _tiny_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 10)
	button.custom_minimum_size.x = 26.0
	button.pressed.connect(callback)
	return button


func _add_check(text: String, value: bool, callback: Callable, widget_key: String = "") -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = value
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(callback)
	_add(check)
	if not widget_key.is_empty():
		_widgets[widget_key] = check
	return check


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	UITheme.style_section(label)
	_add(label)


func _add_hint(text: String, widget_key: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_mono(label, 10, UITheme.MUTED)
	_add(label)
	if not widget_key.is_empty():
		_widgets[widget_key] = label
	return label


func _add_info(key: String, value: String, widget_key: String = "") -> void:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = key
	left.custom_minimum_size.x = 70
	UITheme.style_mono(left, 11, UITheme.MUTED)
	row.add_child(left)
	var right := Label.new()
	right.text = value
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_mono(right, 11, Color(1, 1, 1, 0.82))
	row.add_child(right)
	_add(row)
	if not widget_key.is_empty():
		_widgets[widget_key] = right
		_widgets[widget_key + ":row"] = row


func _add_sep() -> void:
	var line := HSeparator.new()
	_add(line)


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(callback)
	_add(button)


func _add_spin(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable, widget_key: String = "") -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 70
	UITheme.style_mono(label, 11, UITheme.MUTED)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.add_theme_font_size_override("font_size", 11)
	spin.value_changed.connect(func(next: float) -> void:
		callback.call(next)
	)
	row.add_child(spin)
	_add(row)
	if not widget_key.is_empty():
		_widgets[widget_key] = spin
	return spin


func _add_slider(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable, widget_key: String = "") -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_mono(label, 11, Color(1, 1, 1, 0.72))
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 78
	spin.add_theme_font_size_override("font_size", 10)
	row.add_child(spin)
	box.add_child(row)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	box.add_child(slider)
	slider.value_changed.connect(func(next: float) -> void:
		spin.set_value_no_signal(next)
		callback.call(next)
	)
	spin.value_changed.connect(func(next: float) -> void:
		slider.set_value_no_signal(next)
		callback.call(next)
	)
	_add(box)
	if not widget_key.is_empty():
		_widgets[widget_key + ":slider"] = slider
		_widgets[widget_key + ":spin"] = spin
		_widgets[widget_key + ":box"] = box
	return slider


func _add_option(text: String, items: Array, selected: int, callback: Callable, widget_key: String = "") -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 88
	UITheme.style_mono(label, 11, UITheme.MUTED)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 11)
	for item in items:
		option.add_item(String(item))
	option.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	option.item_selected.connect(callback)
	row.add_child(option)
	_add(row)
	if not widget_key.is_empty():
		_widgets[widget_key] = option
		_widgets[widget_key + ":row"] = row
	return option


# ---------------------------------------------------------------- 编辑


func _edit(callback: Callable) -> void:
	if workspace == null:
		return
	# 连续拖动/步进合并为一条撤销；0.7s 后重建面板一次。
	_editing = true
	workspace.gesture_mutate_chart(callback)
	if _gesture_timer != null:
		_gesture_timer.start()
