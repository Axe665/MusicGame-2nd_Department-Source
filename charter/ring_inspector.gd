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
		_editing = false
		refresh()
	)
	add_child(_gesture_timer)


func refresh(force: bool = false) -> void:
	if _building or (_editing and not force):
		return
	_building = true
	for child in get_children():
		if child == _gesture_timer:
			continue
		remove_child(child)
		child.queue_free()
	_curve = null
	_build()
	_building = false


func _build() -> void:
	var chart = workspace.chart() if workspace != null else null
	if chart == null:
		return
	_add_title("属性")
	if timeline == null:
		_add_hint("时间轴还没准备好。")
		return
	var shapes: Array = timeline.selected_shape_keys()
	var views: Array = timeline.selected_views()
	if shapes.is_empty() and views.is_empty():
		_build_empty(chart)
		return
	if not timeline.segment_shape_key().is_empty() or timeline.segment_view() != null:
		_build_segment(chart)
		return
	if shapes.size() == 1 and views.is_empty():
		_build_shape_key(chart, shapes[0])
		return
	if views.size() == 1 and shapes.is_empty():
		_build_camera_key(chart, views[0])
		return
	_build_multi(chart, shapes, views)


func _build_empty(chart: Chart) -> void:
	_add_hint("点关键帧选中；Ctrl/Shift 加选；拖空白框选。\n选中色带可编辑这一段；选中关键帧可改参数。")
	_add_sep()
	_add_info("播放头", "%.2f 拍" % workspace.playhead())
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
	_add_info("形状数", str(chart.shapes.size()))
	_add_info("形状帧", str(chart.shape_keys.size()))
	_add_info("镜头帧", str(chart.view_states.size()))


func _build_multi(chart: Chart, shapes: Array, views: Array) -> void:
	_add_info("已选", "%d 个形状帧 · %d 个镜头帧" % [shapes.size(), views.size()])
	_add_hint("多选按拍整体拖动；跨轨也会一起移动。")
	_add_sep()
	_add_button("复制 (Ctrl+C)", func() -> void: timeline.copy_selection())
	_add_button("粘贴 (Ctrl+V)", func() -> void: timeline.paste())
	_add_button("删除 / 清除选中帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("左移一拍", func() -> void: timeline.nudge_selection(-1.0))
	_add_button("右移一拍", func() -> void: timeline.nudge_selection(1.0))
	_add_button("插入 1 拍（当前轨）", func() -> void: timeline.insert_frames(1.0))
	_add_sep()
	_add_info("起点", "%.2f 拍" % _selection_start(shapes, views))


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
	var key: Dictionary = timeline.segment_shape_key()
	var view: ViewState = timeline.segment_view()
	var target_beat := 0.0
	var lane := ""
	var easing := "linear"
	var curve: Array = []
	var morph := 0.0
	if not key.is_empty():
		lane = "shape"
		target_beat = float(key.get("beat", 0.0))
		easing = String(key.get("easing", "in-out"))
		curve = key.get("curve", [])
	elif view != null:
		lane = "view"
		target_beat = view.beat
		easing = view.easing
		curve = view.curve
	var previous := _previous_key_beat(chart, lane, target_beat)
	var span := maxf(0.0, target_beat - previous)
	if lane == "shape" and not key.is_empty():
		morph = BoundaryRuntime.morph_beats(key, span)
	elif view != null:
		morph = view.morph_beats(span)
	_add_title("过渡段")
	_add_info("方向", "%.2f 拍 → %.2f 拍（目标帧）" % [previous, target_beat])
	if span <= 0.0001:
		_add_hint("目标帧在第 0 拍：没有入场过渡可调。")
		_add_sep()
		_add_button("选中目标帧", func() -> void:
			timeline._select_only(lane, int(key.get("id", 0) if lane == "shape" else (view.id if view != null else 0)))
		)
		return
	_add_info("段长", RingWorkspace.span_label(span, maxf(1.0, chart.timing.beats_per_bar_at(previous))))
	_add_sep()
	_add_slider("过渡时长（拍）", morph, 0.0, span, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			if lane == "shape":
				key["morph"] = clampf(value, 0.0, span)
			elif view != null:
				view.morph = clampf(value, 0.0, span)
		)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_small_button("硬切", func() -> void:
		_edit(func() -> void:
			if lane == "shape":
				key["morph"] = 0.0
			elif view != null:
				view.morph = 0.0
		)
	))
	row.add_child(_small_button("整段", func() -> void:
		_edit(func() -> void:
			if lane == "shape":
				key["morph"] = span
			elif view != null:
				view.morph = span
		)
	))
	add_child(row)
	_add_hint("过渡在目标帧前完成：0 拍 = 目标帧处硬切，整段 = 从头到尾一直在变。")
	_add_segment_easing(easing, curve, lane, key if lane == "shape" else view)
	_add_sep()
	_add_button("选中目标帧", func() -> void:
		timeline._select_only(lane, int(key.get("id", 0) if lane == "shape" else (view.id if view != null else 0)))
	)
	if lane == "shape":
		_add_button("＋ 在下一拍插入形状帧", func() -> void: workspace.insert_next_shape())
	elif view != null:
		_add_button("＋ 在下一拍插入镜头帧", func() -> void: workspace.insert_next_view())


func _build_shape_key(chart: Chart, key: Dictionary) -> void:
	var beat := float(key.get("beat", 0.0))
	var previous := _previous_key_beat(chart, "shape", beat)
	var span := maxf(0.0, beat - previous)
	_add_title("形状关键帧")
	_add_info("编号", str(int(key.get("id", 0))))
	_add_spin("拍", beat, 0.0, 100000.0, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			key["beat"] = value
			chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
		)
	)
	_add_sep()
	var ids: Array = chart.shapes.keys()
	ids.sort()
	var current := ids.find(String(key.get("shape_id", "")))
	_add_option("形状", ids, maxi(0, current), func(index: int) -> void:
		_edit(func() -> void: key["shape_id"] = String(ids[index]))
	)
	var locked_shape := String(key.get("shape_id", "")) == chart.default_shape_id
	_add_button("编辑形状（2D）", func() -> void:
		workspace.seek(beat)
		workspace.open_pad_for_current()
	)
	if locked_shape:
		_add_hint("这是基础圆 S0（锁定）；先「复制」一个形状再编辑。")
	_add_button("切断/恢复这一段 (G)", func() -> void:
		workspace.seek(beat)
		workspace._toggle_gap()
	)
	_add_button("删除这一帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("＋ 在下一拍插入形状帧", func() -> void: workspace.insert_next_shape())
	_add_sep()
	if span > 0.0001:
		var morph := BoundaryRuntime.morph_beats(key, span)
		_add_info("入场", "%.2f 拍 → 本帧" % previous)
		_add_slider("过渡时长（拍）", morph, 0.0, span, 0.05, func(value: float) -> void:
			_edit(func() -> void: key["morph"] = clampf(value, 0.0, span))
		)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_small_button("硬切", func() -> void: _edit(func() -> void: key["morph"] = 0.0)))
		row.add_child(_small_button("整段", func() -> void: _edit(func() -> void: key["morph"] = span)))
		add_child(row)
		_add_segment_easing(key.get("easing", "in-out"), key.get("curve", []), "shape", key)
	else:
		_add_hint("第 0 拍是起点：没有入场过渡。")


func _build_camera_key(chart: Chart, state: ViewState) -> void:
	_add_title("镜头关键帧")
	_add_info("编号", str(state.id))
	_add_spin("拍", state.beat, 0.0, 100000.0, 0.05, func(value: float) -> void:
		_edit(func() -> void:
			state.beat = value
			chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		)
	)
	_add_sep()
	_add_hint("环始终在画面中心，只做推拉和滚转。")
	_add_sep()
	_add_slider("推拉（1=标准）", state.dolly, 0.6, 1.6, 0.01, func(value: float) -> void:
		_edit(func() -> void: state.dolly = value)
	)
	_add_slider("滚转（度）", state.rotation, -180.0, 180.0, 1.0, func(value: float) -> void:
		_edit(func() -> void: state.rotation = value)
	)
	_add_button("删除选中镜头帧 (Del)", func() -> void: timeline.delete_selection())
	_add_button("＋ 在下一拍插入镜头帧", func() -> void: workspace.insert_next_view())
	_add_sep()
	var previous := _previous_key_beat(chart, "view", state.beat)
	var span := maxf(0.0, state.beat - previous)
	if span > 0.0001:
		var morph := state.morph_beats(span)
		_add_info("入场", "%.2f 拍 → 本帧" % previous)
		_add_slider("过渡时长（拍）", morph, 0.0, span, 0.05, func(value: float) -> void:
			_edit(func() -> void: state.morph = clampf(value, 0.0, span))
		)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_small_button("硬切", func() -> void: _edit(func() -> void: state.morph = 0.0)))
		row.add_child(_small_button("整段", func() -> void: _edit(func() -> void: state.morph = span)))
		add_child(row)
		_add_segment_easing(state.easing, state.curve, "view", state)
	else:
		_add_hint("第 0 拍是起点：镜头没有入场过渡。")


func _add_segment_easing(easing: String, curve: Array, lane: String, holder) -> void:
	var label_index := EASING_KEYS.find(easing)
	if curve.size() == 4:
		label_index = 4
	if label_index < 0:
		label_index = 0
	_add_option("进入目标帧的缓动", EASING_LABELS, label_index, func(index: int) -> void:
		var picked: String = String(EASING_KEYS[index])
		_edit(func() -> void:
			if lane == "shape":
				holder["easing"] = picked if picked != "custom" else "in-out"
				if picked == "custom":
					if (holder.get("curve", []) as Array).size() != 4:
						holder["curve"] = [0.42, 0.25, 0.58, 0.75]
				else:
					holder.erase("curve")
			else:
				holder.easing = picked if picked != "custom" else "in-out"
				if picked == "custom":
					if holder.curve.size() != 4:
						holder.curve = [0.42, 0.25, 0.58, 0.75]
				else:
					holder.curve = []
		)
	)
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
		if lane == "shape":
			holder["curve"] = [values[0], values[1], values[2], values[3]]
		else:
			holder.curve = [values[0], values[1], values[2], values[3]]
		workspace.touch_chart()
	)
	_curve.drag_finished.connect(func() -> void:
		_editing = false
		workspace.end_preview_drag()
		workspace.finish_edit()
		refresh()
	)
	add_child(_curve)
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


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	UITheme.style_section(label)
	add_child(label)


func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_mono(label, 10, UITheme.MUTED)
	add_child(label)


func _add_info(key: String, value: String) -> void:
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
	add_child(row)


func _add_sep() -> void:
	var line := HSeparator.new()
	add_child(line)


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(callback)
	add_child(button)


func _add_spin(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> void:
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
	add_child(row)


func _add_slider(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> void:
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
	add_child(box)


func _add_option(text: String, items: Array, selected: int, callback: Callable) -> void:
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
	add_child(row)


# ---------------------------------------------------------------- 编辑


func _edit(callback: Callable) -> void:
	if workspace == null:
		return
	# 连续拖动/步进合并为一条撤销；0.7s 后重建面板一次。
	_editing = true
	workspace.gesture_mutate_chart(callback)
	if _gesture_timer != null:
		_gesture_timer.start()
