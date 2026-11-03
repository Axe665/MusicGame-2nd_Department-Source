class_name Inspector
extends TabContainer

var _app: Node = null
var _pages: Dictionary = {}
var _page_list: Array[VBoxContainer] = []
var _applying: bool = false
var _rebuilding: bool = false
var _video_dialog: FileDialog
var _selected_timing: int = 0
var _selected_visual: int = 0
var _tap_times: Array[int] = []
var _tap_label: Label
var _timing_base_spin: SpinBox
var _timing_list: ItemList
var _timing_chart: Chart


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_tabs()
	if _app != null:
		_app.selection_changed.connect(_on_selection_changed)
		_app.chart_changed.connect(_on_chart_changed)
		_app.tool_changed.connect(_on_tool_changed)
		tab_changed.connect(_on_tab_changed)
	_rebuild()


func _build_tabs() -> void:
	for title in ["音符", "区域", "边界", "事件", "视图", "时间", "谱面"]:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var page := VBoxContainer.new()
		page.name = "Page"
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 8)
		scroll.add_child(page)
		add_child(scroll)
		_pages[title] = page
		_page_list.append(page)


func _on_selection_changed() -> void:
	queue_redraw()
	if _app == null or _applying:
		return
	if not _app.selected_notes.is_empty():
		current_tab = 0
	elif _app.selected_region_id >= 0:
		current_tab = 1
	elif not _app.selected_event_id.is_empty():
		current_tab = 3
	_rebuild()


func _on_chart_changed() -> void:
	if not _applying:
		_rebuild()


func _on_tool_changed(tool: String) -> void:
	if tool == "boundary":
		current_tab = 2
	elif tool == "event":
		current_tab = 3
	elif tool == "red":
		current_tab = 1
	_rebuild()


func _on_tab_changed(_tab: int) -> void:
	if not _rebuilding:
		_rebuild()


func _rebuild() -> void:
	if _app == null or _rebuilding:
		return
	_rebuilding = true
	for page in _page_list:
		for child in page.get_children():
			child.queue_free()
	match current_tab:
		0:
			_build_note_page(_pages["音符"])
		1:
			_build_region_page(_pages["区域"])
		2:
			_build_boundary_page(_pages["边界"])
		3:
			_build_event_page(_pages["事件"])
		4:
			_build_view_page(_pages["视图"])
		5:
			_build_timing_page(_pages["时间"])
		6:
			_build_chart_page(_pages["谱面"])
	refresh_tab_titles()
	_rebuilding = false


func refresh_tab_titles() -> void:
	if _app == null:
		return
	var note_count: int = _app.selected_notes.size()
	set_tab_title(0, "音符" if note_count == 0 else "音符 · %d" % note_count)
	set_tab_title(1, "区域" if _app.selected_region_id < 0 else "区域 · %d" % _app.selected_region_id)
	set_tab_title(2, "边界")
	set_tab_title(3, "事件" if _app.selected_event_id.is_empty() else "事件 · %s" % _app.selected_event_id)
	set_tab_title(4, "视图")
	set_tab_title(5, "时间")
	set_tab_title(6, "谱面")


func _empty(title: String, hint: String) -> void:
	var page: VBoxContainer = _pages[title]
	_section(page, title)
	_label(page, hint, 12, UITheme.MUTED)


func _section(page: VBoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	UITheme.style_section(label)
	page.add_child(label)


func _label(page: VBoxContainer, text: String, size: int = 12, color: Color = UITheme.MUTED, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	page.add_child(label)
	return label


func _row(page: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	page.add_child(row)


func _spin(page: VBoxContainer, label_text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value_changed.connect(func(new_value: float) -> void:
		if not _applying:
			_apply(func() -> void: callback.call(new_value))
	)
	_row(page, label_text, spin)
	return spin


func _int(page: VBoxContainer, label_text: String, value: int, min_value: int, max_value: int, callback: Callable) -> SpinBox:
	return _spin(page, label_text, float(value), float(min_value), float(max_value), 1.0, func(new_value: float) -> void: callback.call(int(new_value)))


func _text(page: VBoxContainer, label_text: String, value: String, callback: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(new_text: String) -> void:
		if not _applying:
			_apply(func() -> void: callback.call(new_text))
	)
	edit.focus_exited.connect(func() -> void:
		if not _applying:
			_apply(func() -> void: callback.call(edit.text))
	)
	_row(page, label_text, edit)
	return edit


func _beat(page: VBoxContainer, label_text: String, beat: float, callback: Callable) -> LineEdit:
	var edit := _text(page, label_text, _app.chart.timing.format_beat(beat), func(text: String) -> void:
		var parsed: float = _app.chart.timing.parse_beat(text)
		callback.call(parsed)
	)
	edit.tooltip_text = "格式：小节:分音:分母（例如 4:0:4）"
	return edit


func _option(page: VBoxContainer, label_text: String, items: Array[String], selected: int, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	option.item_selected.connect(func(index: int) -> void:
		if not _applying:
			_apply(func() -> void: callback.call(index))
	)
	_row(page, label_text, option)
	return option


func _check(page: VBoxContainer, label_text: String, value: bool, callback: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	check.button_pressed = value
	check.toggled.connect(func(pressed: bool) -> void:
		if not _applying:
			_apply(func() -> void: callback.call(pressed))
	)
	page.add_child(check)
	return check


func _buttons(page: VBoxContainer, specs: Array[Dictionary]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for spec in specs:
		var button := Button.new()
		button.text = String(spec.get("text", "按钮"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var callback: Callable = spec.get("callback")
		button.pressed.connect(callback)
		row.add_child(button)
	page.add_child(row)


func _apply(callback: Callable) -> void:
	if _app == null:
		return
	_applying = true
	_app.mutate(callback)
	_applying = false


func _build_note_page(page: VBoxContainer) -> void:
	if _app.selected_notes.size() > 1:
		_section(page, "多选")
		_label(page, "已选中 %d 个音符。拖动可整体移动；数值混合时不显示单一值。" % _app.selected_notes.size(), 12, UITheme.INK)
		var types := {}
		for note in _app.get_selected_notes():
			types[note.type] = true
		_label(page, "类型：%s" % ",".join(types.keys()), 12, UITheme.MUTED)
		_buttons(page, [
			{"text": "删除选中", "callback": _delete_selected},
			{"text": "解锁", "callback": _unlock_selected},
		])
		return
	var note: Note = _app.get_selected_note()
	if note == null:
		_empty("音符", "在上方类型卡片（或 1–7 快捷键）选择工具；点击画布放置，预览窗可点边界放置。")
		return
	_section(page, "%s · #%d" % [note.type.to_upper(), note.id])
	_row(page, "类型", _readonly(note.type))
	_row(page, "id", _readonly(str(note.id)))
	_beat(page, "开始拍", note.beat, func(value: float) -> void:
		var delta := value - note.beat
		note.beat = value
		if note.type in ["hold", "path", "trace"]:
			note.end_beat = maxf(note.beat + 0.25, note.end_beat + delta)
	)
	if note.type in ["hold", "path", "trace"]:
		_beat(page, "结束拍", note.end_beat, func(value: float) -> void:
			note.end_beat = maxf(note.beat + 0.25, value)
		)
	if note.type == "bell":
		_spin(page, "中心 u", note.center_u, 0.0, 0.9999, 0.001, func(value: float) -> void: note.center_u = value)
		_spin(page, "半径 px", note.radius, 4.0, 200.0, 1.0, func(value: float) -> void: note.radius = value)
	elif note.space == "plane" and note.type not in ["path", "trace"]:
		_spin(page, "平面 x", note.plane_x, 0.0, 1.0, 0.001, func(value: float) -> void: note.plane_x = value)
		_spin(page, "平面 y", note.plane_y, 0.0, 1.0, 0.001, func(value: float) -> void: note.plane_y = value)
		_spin(page, "判定半径", note.plane_radius, 0.02, 0.3, 0.005, func(value: float) -> void: note.plane_radius = value)
		_label(page, "平面 Tap：按 osu 原 2D 坐标；鼠标进入半径 + 按键判定，不占用环上角度。", 11, UITheme.MUTED)
	else:
		_spin(page, "逻辑角度", note.angle, 0.0, 360.0, 0.5, func(value: float) -> void: note.angle = fposmod(value, 360.0))
		_spin(page, "宽度", note.width, 0.0, 360.0, 1.0, func(value: float) -> void: note.width = value)
	if note.type == "path":
		var tail_local := note.path_tail_local()
		var tail_radius := tail_local.length()
		var tail_degrees := rad_to_deg(atan2(tail_local.y, tail_local.x))
		_spin(page, "尾半径 R", tail_radius, 0.05, 1.0, 0.01, func(value: float) -> void:
			_set_path_tail(note, value, tail_degrees)
		)
		_spin(page, "尾角度", tail_degrees, 0.0, 360.0, 0.5, func(value: float) -> void:
			_set_path_tail(note, tail_radius, value)
		)
		_spin(page, "尾宽度", note.tail_width, 0.0, 360.0, 1.0, func(value: float) -> void: note.tail_width = value)
		_spin(page, "容差比例", note.tolerance, 0.0, 1.0, 0.01, func(value: float) -> void: note.tolerance = value)
		_spin(page, "采样/拍", note.samples_per_beat, 0.25, 32.0, 0.25, func(value: float) -> void: note.samples_per_beat = value)
		_label(page, "平面 Path：星头在环上按键，身体/尾在平面内跟随；尾默认 0.65–0.75R。", 11, UITheme.CYAN)
		_label(page, "中段采样点：%d；平面点：%d 个（在预览里拖青色节点改形状）" % [note.path_sample_beats().size(), note.trace_pts.size()], 11, UITheme.MUTED)
		_buttons(page, [
			{"text": "重画 Path", "callback": func() -> void: _app.set_tool("path")},
		])
		_section(page, "跳区 / 擦除")
		_spin(page, "中段擦除 %", _path_erase_width(note) * 100.0, 0.0, 80.0, 5.0, func(value: float) -> void:
			_set_path_erase_width(note, value / 100.0)
		)
		_buttons(page, [{"text": "清除擦除", "callback": func() -> void:
			_apply(func() -> void: _set_path_erase_width(note, 0.0))
			_rebuild()
		}])
		_label(page, "擦除段不渲染、不生成中段检查点；头尾仍各自判定。", 11, UITheme.MUTED)
	if note.type == "trace":
		_spin(page, "移动距离 px", note.move_px, 0.0, 1000.0, 1.0, func(value: float) -> void: note.move_px = value)
		_label(page, "二维点：%d 个；在预览窗用 Trace 工具拖拽重画。" % note.trace_pts.size(), 11, UITheme.MUTED)
		if note.trace_style == "slider":
			_label(page, "平面滑条：std 导入的 B/L/C/P 二维轨迹，起始接触 + 沿带移动判定；不再占用环上角度。", 11, UITheme.CYAN)
		_buttons(page, [
			{"text": "重画 Trace", "callback": func() -> void: _app.set_tool("trace")},
		])
	if note.type == "anchor":
		_spin(page, "配对角度", note.anchor_pair, -1.0, 90.0, 90.0, func(value: float) -> void: note.anchor_pair = int(value))
		_text(page, "pairId", note.pair_id, func(value: String) -> void: note.pair_id = value)
		_label(page, "Anchor 只判时间；配对需同拍反向。", 11, UITheme.MUTED)
	_spin(page, "颜色槽", note.color, 0.0, 15.0, 1.0, func(value: float) -> void: note.color = int(value))
	_check(page, "锁定（不可拖动）", note.lock, func(value: bool) -> void: note.lock = value)
	_buttons(page, [
		{"text": "定位播放头", "callback": func() -> void: _app.set_playhead(note.beat)},
		{"text": "复制", "callback": func() -> void: _duplicate_note(note)},
		{"text": "删除", "callback": func() -> void: _delete_note(note)},
	])


func _path_erase_width(note: Note) -> float:
	if note.path_gaps.is_empty():
		return 0.0
	var gap: Dictionary = note.path_gaps[0]
	return maxf(0.0, minf(0.8, absf(float(gap.get("to", 0.0)) - float(gap.get("from", 0.0)))))


func _set_path_erase_width(note: Note, width: float) -> void:
	var half := clampf(width, 0.0, 0.8) * 0.5
	if half <= 0.001:
		note.path_gaps.clear()
		return
	note.path_gaps.clear()
	note.path_gaps.append({"from": 0.5 - half, "to": 0.5 + half})


func _set_path_tail(note: Note, radius: float, degrees: float) -> void:
	_apply(func() -> void:
		if note.trace_pts.size() < 2:
			note.trace_pts = [
				{"x": cos(deg_to_rad(note.angle)), "y": sin(deg_to_rad(note.angle)), "db": 0.0},
				{"x": cos(deg_to_rad(degrees)) * radius, "y": sin(deg_to_rad(degrees)) * radius, "db": note.duration()},
			]
		else:
			var point: Dictionary = note.trace_pts[-1]
			point["x"] = cos(deg_to_rad(degrees)) * radius
			point["y"] = sin(deg_to_rad(degrees)) * radius
		note.tail_angle = fposmod(degrees, 360.0)
	)
	_rebuild()


func _add_visual_point(note: Note) -> void:
	_apply(func() -> void:
		note.visual_pts.append({"db": note.duration() * 0.5, "da": 0.0})
	)
	_selected_visual = note.visual_pts.size() - 1
	_rebuild()


func _delete_visual_point(note: Note) -> void:
	if note.visual_pts.is_empty():
		return
	_apply(func() -> void: note.visual_pts.remove_at(clampi(_selected_visual, 0, note.visual_pts.size() - 1)))
	_selected_visual = clampi(_selected_visual, 0, maxi(0, note.visual_pts.size() - 1))
	_rebuild()


func _build_region_page(page: VBoxContainer) -> void:
	var region: Region = _app.get_selected_region()
	if region == null:
		_empty("区域", "用 Red 工具（7）在画布拖拽创建红区；长度上限 4 拍。")
		_buttons(page, [{"text": "Red 工具", "callback": func() -> void: _app.set_tool("red")}])
		return
	_section(page, "Red · #%d" % region.id)
	_row(page, "类型", _readonly(region.kind))
	_beat(page, "开始拍", region.start_beat, func(value: float) -> void: region.start_beat = value)
	_beat(page, "结束拍", region.end_beat, func(value: float) -> void: region.end_beat = value)
	_spin(page, "逻辑角度", region.angle, 0.0, 360.0, 0.5, func(value: float) -> void: region.angle = fposmod(value, 360.0))
	_spin(page, "逻辑宽度", region.width, 0.0, 360.0, 1.0, func(value: float) -> void: region.width = value)
	_spin(page, "极性", region.polarity, -1.0, 1.0, 2.0, func(value: float) -> void: region.polarity = int(value))
	var shapes: Array[String] = [""]
	for shape in _app.chart.sorted_shapes():
		shapes.append(shape.id)
	_option(page, "形状引用", shapes, maxi(0, shapes.find(region.shape)), func(index: int) -> void: region.shape = shapes[index])
	_label(page, "时长 %.2f 拍 / 上限 4.00 拍；同刻公共角度减去红区后必须非空。" % region.duration(), 11, UITheme.MUTED)
	_buttons(page, [
		{"text": "定位播放头", "callback": func() -> void: _app.set_playhead(region.start_beat)},
		{"text": "删除", "callback": func() -> void: _delete_region(region)},
	])


func _build_boundary_page(page: VBoxContainer) -> void:
	var shape: BoundaryShape = _app.get_selected_shape()
	if shape == null:
		_empty("边界", "选择或新建一个 BoundaryShape。")
		_buttons(page, [{"text": "新建圆形", "callback": func() -> void: _add_shape()}])
		return
	var shape_ids: Array[String] = []
	for item in _app.chart.sorted_shapes():
		shape_ids.append(item.id)
	_option(page, "形状", shape_ids, maxi(0, shape_ids.find(shape.id)), func(index: int) -> void:
		_app.select_shape(shape_ids[index])
	)
	_check(page, "闭合 closed", shape.closed, func(value: bool) -> void: shape.closed = value)
	_row(page, "默认形状", _readonly(_app.chart.default_shape_id))
	_buttons(page, [
		{"text": "设为默认", "callback": func() -> void: _app.chart.default_shape_id = shape.id},
		{"text": "新建", "callback": func() -> void: _add_shape()},
		{"text": "删除", "callback": func() -> void: _delete_shape(shape)},
	])
	_section(page, "分段")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 126)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sorted := shape.sorted_segments()
	for i in sorted.size():
		var segment: BoundarySegment = sorted[i]
		list.add_item("%02d  %.3f–%.3f%s" % [i, segment.u0, segment.u1, "  GAP" if segment.gap else ""])
	if _app.selected_segment_index >= 0 and _app.selected_segment_index < list.item_count:
		list.select(_app.selected_segment_index)
	list.item_selected.connect(func(index: int) -> void: _app.select_segment(index))
	page.add_child(list)
	_buttons(page, [
		{"text": "加段", "callback": func() -> void: _add_segment(shape)},
		{"text": "删段", "callback": func() -> void: _delete_segment(shape)},
		{"text": "在 u 中点分割", "callback": func() -> void: _split_segment_mid(shape)},
	])
	_section(page, "预设")
	_buttons(page, [
		{"text": "圆", "callback": func() -> void: _preset(shape, "circle")},
		{"text": "椭圆", "callback": func() -> void: _preset(shape, "ellipse")},
		{"text": "竖椭圆", "callback": func() -> void: _preset(shape, "tall")},
		{"text": "切一刀", "callback": func() -> void: _preset(shape, "gap")},
	])
	var segment: BoundarySegment = _app.get_selected_segment()
	if segment != null:
		_section(page, "段 %d" % _app.selected_segment_index)
		_spin(page, "u0", segment.u0, 0.0, 1.0, 0.001, func(value: float) -> void: segment.u0 = value)
		_spin(page, "u1", segment.u1, 0.0, 1.0, 0.001, func(value: float) -> void: segment.u1 = value)
		_spin(page, "x0", segment.p0.x, -2000.0, 2000.0, 1.0, func(value: float) -> void: segment.p0 = Vector2(value, segment.p0.y))
		_spin(page, "y0", segment.p0.y, -2000.0, 2000.0, 1.0, func(value: float) -> void: segment.p0 = Vector2(segment.p0.x, value))
		_spin(page, "x1", segment.p1.x, -2000.0, 2000.0, 1.0, func(value: float) -> void: segment.p1 = Vector2(value, segment.p1.y))
		_spin(page, "y1", segment.p1.y, -2000.0, 2000.0, 1.0, func(value: float) -> void: segment.p1 = Vector2(segment.p1.x, value))
		var curves: Array[String] = ["l", "s", "si", "so", "b"]
		_option(page, "X 插值", curves, maxi(0, curves.find(segment.ix)), func(index: int) -> void: segment.ix = curves[index])
		_option(page, "Y 插值", curves, maxi(0, curves.find(segment.iy)), func(index: int) -> void: segment.iy = curves[index])
		_check(page, "缺口 gap（不渲染/不判定）", segment.gap, func(value: bool) -> void: segment.gap = value)
		_label(page, "提示：在预览窗直接拖拽控制点；双击分段可在点击处拆分。", 11, UITheme.MUTED)


func _build_event_page(page: VBoxContainer) -> void:
	var event: BoundaryEvent = _app.get_selected_event()
	if event == null:
		_empty("事件", "E 或下方按钮新建 BoundaryEvent；同一时刻 target 不得相交。")
		_buttons(page, [{"text": "新建事件", "callback": func() -> void: _add_event()}])
		return
	_section(page, "BoundaryEvent · %s" % event.id)
	_beat(page, "开始拍", event.start_beat, func(value: float) -> void: event.start_beat = value)
	_beat(page, "结束拍", event.end_beat, func(value: float) -> void: event.end_beat = value)
	_spin(page, "target u0", event.target_u0, 0.0, 1.0, 0.001, func(value: float) -> void: event.target_u0 = value)
	_spin(page, "target u1", event.target_u1, 0.0, 1.0, 0.001, func(value: float) -> void: event.target_u1 = value)
	var shape_ids: Array[String] = []
	for shape in _app.chart.sorted_shapes():
		shape_ids.append(shape.id)
	_option(page, "fromShape", shape_ids, maxi(0, shape_ids.find(event.from_shape)), func(index: int) -> void: event.from_shape = shape_ids[index])
	_option(page, "toShape", shape_ids, maxi(0, shape_ids.find(event.to_shape)), func(index: int) -> void: event.to_shape = shape_ids[index])
	var easings: Array[String] = ["linear", "in-out", "cubic-bezier"]
	_option(page, "缓动", easings, maxi(0, easings.find(event.easing)), func(index: int) -> void: event.easing = easings[index])
	var behaviors: Array[String] = ["restore", "hold"]
	_option(page, "结束行为", behaviors, maxi(0, behaviors.find(event.end_behavior)), func(index: int) -> void: event.end_behavior = behaviors[index])
	_spin(page, "恢复拍数", event.restore_duration, 0.0, 8.0, 0.25, func(value: float) -> void: event.restore_duration = value)
	_option(page, "恢复缓动", easings, maxi(0, easings.find(event.restore_easing)), func(index: int) -> void: event.restore_easing = easings[index])
	_label(page, "事件只改 C(u,t)，不改音符的 u/角度/宽度/时间。", 11, UITheme.MUTED)
	_buttons(page, [
		{"text": "定位播放头", "callback": func() -> void: _app.set_playhead(event.start_beat)},
		{"text": "复制", "callback": func() -> void: _duplicate_event(event)},
		{"text": "删除", "callback": func() -> void: _delete_event(event)},
	])


func _build_view_page(page: VBoxContainer) -> void:
	_section(page, "显示")
	_check(page, "正对镜头（忽略倾斜）", bool(_app.chart.metadata.get("face_camera", true)), func(value: bool) -> void:
		_app.mutate(func() -> void: _app.chart.metadata["face_camera"] = value)
	)
	_check(page, "HUD（H）", _app.hud_visible, func(value: bool) -> void: _app.hud_visible = value)
	_check(page, "调试叠层", _app.debug_overlay, func(value: bool) -> void: _app.debug_overlay = value)
	_check(page, "波形", _app.waveform_visible, func(value: bool) -> void: _app.waveform_visible = value)
	_check(page, "幽灵红区", _app.ghost_regions, func(value: bool) -> void: _app.ghost_regions = value)
	_check(page, "3D 环网格（GPU）", _app.use_3d_ring, func(value: bool) -> void:
		_app.use_3d_ring = value
		_app.status_changed.emit()
	)
	_check(page, "鼠标倾斜", _app.mouse_tilt, func(value: bool) -> void:
		_app.mouse_tilt = value
		_app.status_changed.emit()
	)
	_section(page, "吸附")
	_option(page, "网格", ["1/1", "1/2", "1/4", "1/8", "1/16", "1/32"], [1, 2, 4, 8, 16, 32].find(_app.snap_denominator), func(index: int) -> void:
		_app.snap_denominator = [1, 2, 4, 8, 16, 32][index]
	)
	_check(page, "三连", _app.snap_triplet, func(value: bool) -> void: _app.snap_triplet = value)
	_check(page, "五连", _app.snap_quint, func(value: bool) -> void: _app.snap_quint = value)
	_section(page, "视频")
	var video_path := LineEdit.new()
	video_path.text = _app.chart.video_path
	video_path.editable = false
	video_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(page, "路径", video_path)
	_buttons(page, [
		{"text": "选择 .ogv", "callback": func() -> void: _pick_video()},
		{"text": "移除", "callback": func() -> void: _app.mutate(func() -> void: _app.chart.video_path = "")},
	])
	_spin(page, "videoOffset ms", _app.chart.video_offset_ms, -10000.0, 10000.0, 1.0, func(value: float) -> void: _app.chart.video_offset_ms = value)
	_spin(page, "FPS 提示", _app.chart.video_fps, 1.0, 240.0, 1.0, func(value: float) -> void: _app.chart.video_fps = value)
	_spin(page, "不透明度", _app.chart.video_opacity, 0.0, 1.0, 0.01, func(value: float) -> void: _app.chart.video_opacity = value)
	_section(page, "RingState 关键帧")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 100)
	for i in _app.chart.view_states.size():
		var state: ViewState = _app.chart.view_states[i]
		list.add_item("%02d  beat %.2f  zoom %.2f" % [i, state.beat, state.zoom])
	if _app.selected_view_index >= 0 and _app.selected_view_index < list.item_count:
		list.select(_app.selected_view_index)
	list.item_selected.connect(func(index: int) -> void: _app.select_view(index))
	page.add_child(list)
	var state: ViewState = _app.get_selected_view()
	if state != null:
		_beat(page, "关键帧拍", state.beat, func(value: float) -> void: state.beat = value)
		_spin(page, "zoom", state.zoom, 0.75, 1.4, 0.01, func(value: float) -> void: state.zoom = value)
		_spin(page, "tiltX", state.tilt_x, -60.0, 60.0, 1.0, func(value: float) -> void: state.tilt_x = value)
		_spin(page, "tiltY", state.tilt_y, -60.0, 60.0, 1.0, func(value: float) -> void: state.tilt_y = value)
		_spin(page, "ellipse", state.ellipse, 0.5, 1.5, 0.01, func(value: float) -> void: state.ellipse = value)
		_spin(page, "rotation", state.rotation, -180.0, 180.0, 1.0, func(value: float) -> void: state.rotation = value)
		var easings: Array[String] = ["linear", "in-out", "cubic-bezier"]
		_option(page, "缓动", easings, maxi(0, easings.find(state.easing)), func(index: int) -> void: state.easing = easings[index])
		_buttons(page, [{"text": "删除关键帧", "callback": func() -> void: _delete_view_state(state)}])
	_buttons(page, [
		{"text": "添加关键帧", "callback": func() -> void: _add_view_state()},
		{"text": "定位播放头", "callback": func() -> void: _app.set_playhead(_app.playhead_beat)},
	])


func _build_chart_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	_section(page, "曲目")
	_text(page, "标题", String(chart.metadata.get("title", "")), func(value: String) -> void: chart.metadata["title"] = value)
	_text(page, "曲师", String(chart.metadata.get("artist", "")), func(value: String) -> void: chart.metadata["artist"] = value)
	_text(page, "谱师", String(chart.metadata.get("creator", "")), func(value: String) -> void: chart.metadata["creator"] = value)
	_text(page, "难度", chart.difficulty, func(value: String) -> void: chart.difficulty = value)
	_option(page, "滑条判定", ["连续跟随", "舞萌扫圈"], 1 if String(chart.metadata.get("slide_mode", "follow")) == "maimai" else 0, func(index: int) -> void:
		_app.mutate(func() -> void: chart.metadata["slide_mode"] = "maimai" if index == 1 else "follow")
	)
	_text(page, "音频路径", chart.audio_path, func(value: String) -> void: chart.audio_path = value)
	_text(page, "视频路径", chart.video_path, func(value: String) -> void: chart.video_path = value)
	_label(page, "时间/BPM/offset 已统一移到“时间”页。", 11, UITheme.MUTED)
	_buttons(page, [
		{"text": "保存谱面", "callback": func() -> void: _app.save_chart()},
	])


func _build_timing_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	_section(page, "Timing Setup")
	_label(page, "参考 osu! editor：基准 BPM、offset、BPM 列表在同一页；改动只影响拍↔毫秒换算。", 11, UITheme.MUTED)
	var points := chart.timing.points
	if points.is_empty():
		_label(page, "没有 BPM 点，先添加一个。", 12, UITheme.RED)
		_buttons(page, [{"text": "播放头加 BPM", "callback": func() -> void: _add_timing_point()}])
		return
	var base: TimingPoint = points[0]
	_timing_chart = chart
	var list := ItemList.new()
	_timing_list = list
	list.custom_minimum_size = Vector2(0, 152)
	for i in points.size():
		var point: TimingPoint = points[i]
		var prefix := "基准  " if i == 0 else "      "
		list.add_item("%s%02d  %s  %.1f BPM  %d/4" % [prefix, i, chart.timing.format_beat(point.beat), point.bpm, point.beats_per_bar])
	_selected_timing = clampi(_selected_timing, 0, maxi(0, points.size() - 1))
	if _selected_timing < list.item_count:
		list.select(_selected_timing)
	var refresh_list := func() -> void:
		for i in chart.timing.points.size():
			if i >= list.item_count:
				break
			var item: TimingPoint = chart.timing.points[i]
			var prefix := "基准  " if i == 0 else "      "
			list.set_item_text(i, "%s%02d  %s  %.1f BPM  %d/4" % [prefix, i, chart.timing.format_beat(item.beat), item.bpm, item.beats_per_bar])
	list.item_selected.connect(func(index: int) -> void:
		_selected_timing = index
		_rebuild()
	)
	list.item_activated.connect(func(index: int) -> void:
		if index >= 0 and index < chart.timing.points.size():
			_app.set_playhead(chart.timing.points[index].beat)
	)
	_timing_base_spin = _spin(page, "基准 BPM", base.bpm, 20.0, 600.0, 0.1, func(value: float) -> void:
		base.bpm = value
		chart.timing.sort_points()
		refresh_list.call()
	)
	_buttons(page, [{"text": "Tap Tempo", "callback": _tap_tempo}])
	_tap_label = _label(page, "Tap Tempo：连点至少 2 次，按平均间隔设置基准 BPM。", 11, UITheme.MUTED)
	_spin(page, "offset ms", chart.offset_ms, -10000.0, 10000.0, 1.0, func(value: float) -> void:
		chart.offset_ms = value
		chart.timing.offset_ms = value
	)
	_spin(page, "固定预读 ms", chart.pre_read_ms, 100.0, 3000.0, 10.0, func(value: float) -> void: chart.pre_read_ms = value)
	_label(page, "基准 BPM = 第 1 个 BPM 点；offset 同时写入 timing.offset。", 11, UITheme.MUTED)
	page.add_child(list)
	_section(page, "BPM 点")
	_buttons(page, [
		{"text": "播放头加 BPM", "callback": func() -> void: _add_timing_point()},
		{"text": "删除选中", "callback": func() -> void: _delete_timing_point()},
	])
	if _selected_timing >= 0 and _selected_timing < points.size():
		var point: TimingPoint = points[_selected_timing]
		var refresh_item := func() -> void:
			refresh_list.call()
		_beat(page, "起始拍", point.beat, func(value: float) -> void:
			point.beat = value
			chart.timing.sort_points()
			refresh_item.call()
		)
		_spin(page, "BPM", point.bpm, 20.0, 600.0, 0.1, func(value: float) -> void:
			point.bpm = value
			chart.timing.sort_points()
			refresh_item.call()
		)
		_spin(page, "拍号分子", point.beats_per_bar, 1.0, 16.0, 1.0, func(value: float) -> void:
			point.beats_per_bar = int(value)
			chart.timing.sort_points()
			refresh_item.call()
		)
		_buttons(page, [
			{"text": "播放头设为起始拍", "callback": func() -> void: _set_timing_beat(point)},
			{"text": "定位到该点", "callback": func() -> void: _app.set_playhead(point.beat)},
		])
	_label(page, "第一个 BPM 点必须不晚于第 0 小节；列表双击可跳转。", 11, UITheme.MUTED)


func _tap_tempo() -> void:
	var now := Time.get_ticks_msec()
	if not _tap_times.is_empty() and now - _tap_times[-1] > 2500:
		_tap_times.clear()
	_tap_times.append(now)
	if _tap_times.size() > 8:
		_tap_times.remove_at(0)
	if _tap_times.size() < 2:
		if _tap_label != null:
			_tap_label.text = "Tap Tempo：再点 1 次。"
		return
	var total := 0.0
	for i in range(1, _tap_times.size()):
		total += float(_tap_times[i] - _tap_times[i - 1])
	var bpm := clampf(60000.0 / maxf(1.0, total / float(_tap_times.size() - 1)), 20.0, 600.0)
	if _timing_chart != null and not _timing_chart.timing.points.is_empty():
		_apply(func() -> void:
			_timing_chart.timing.points[0].bpm = bpm
			_timing_chart.timing.sort_points()
		)
		if _timing_base_spin != null:
			_timing_base_spin.set_value_no_signal(bpm)
		if _timing_list != null and _timing_list.item_count > 0:
			var point: TimingPoint = _timing_chart.timing.points[0]
			_timing_list.set_item_text(0, "基准  %02d  %s  %.1f BPM  %d/4" % [0, _timing_chart.timing.format_beat(point.beat), point.bpm, point.beats_per_bar])
	if _tap_label != null:
		_tap_label.text = "Tap Tempo：%.1f BPM（%d 次）" % [bpm, _tap_times.size()]


func _set_timing_beat(point: TimingPoint) -> void:
	_apply(func() -> void:
		point.beat = _app.snap_beat(_app.playhead_beat)
		_app.chart.timing.sort_points()
	)
	for i in _app.chart.timing.points.size():
		if _app.chart.timing.points[i] == point:
			_selected_timing = i
			break
	_rebuild()


func _add_timing_point() -> void:
	var chart: Chart = _app.chart
	var beat: float = _app.snap_beat(_app.playhead_beat)
	var bpm := chart.timing.bpm_at(beat)
	var bpb := chart.timing.beats_per_bar_at(beat)
	_app.begin_edit()
	chart.timing.points.append(TimingPoint.new(beat, bpm, bpb))
	chart.timing.sort_points()
	_app.finish_edit()
	_selected_timing = 0
	for i in chart.timing.points.size():
		if is_equal_approx(chart.timing.points[i].beat, beat):
			_selected_timing = i
			break
	_rebuild()


func _delete_timing_point() -> void:
	var chart: Chart = _app.chart
	if chart.timing.points.size() <= 1:
		return
	if _selected_timing < 0 or _selected_timing >= chart.timing.points.size():
		return
	_app.begin_edit()
	chart.timing.points.remove_at(_selected_timing)
	chart.timing.sort_points()
	_app.finish_edit()
	_selected_timing = clampi(_selected_timing, 0, chart.timing.points.size() - 1)
	_rebuild()


func _readonly(text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.editable = false
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _delete_selected() -> void:
	_app.begin_edit()
	for note in _app.chart.notes.duplicate():
		if _app.selected_notes.has(note.id):
			_app.chart.notes.erase(note)
	_app.finish_edit()
	_app.clear_selection()


func _unlock_selected() -> void:
	_apply(func() -> void:
		for note in _app.get_selected_notes():
			note.lock = false
	)


func _delete_note(note: Note) -> void:
	_app.begin_edit()
	_app.chart.notes.erase(note)
	_app.finish_edit()
	_app.clear_selection()


func _duplicate_note(note: Note) -> void:
	var copy := Note.from_dict(note.to_dict())
	copy.id = _app.chart.next_note_id()
	copy.beat = note.beat + 1.0
	if copy.type in ["hold", "path", "trace"]:
		copy.end_beat = note.end_beat + 1.0
	_app.begin_edit()
	_app.chart.notes.append(copy)
	_app.finish_edit()
	_app.select_note(copy.id)


func _delete_region(region: Region) -> void:
	_app.begin_edit()
	_app.chart.regions.erase(region)
	_app.finish_edit()
	_app.clear_selection()


func _add_shape() -> void:
	var index := 1
	var id := "S%d" % index
	while _app.chart.shapes.has(id):
		index += 1
		id = "S%d" % index
	_app.begin_edit()
	_app.chart.shapes[id] = BoundaryShape.circle(id, 330.0, 32)
	_app.finish_edit()
	_app.select_shape(id)


func _delete_shape(shape: BoundaryShape) -> void:
	if _app.chart.shapes.size() <= 1:
		return
	_app.begin_edit()
	_app.chart.shapes.erase(shape.id)
	if _app.chart.default_shape_id == shape.id:
		_app.chart.default_shape_id = _app.chart.shapes.keys()[0]
	_app.finish_edit()
	_app.select_shape(_app.chart.default_shape_id)


func _add_segment(shape: BoundaryShape) -> void:
	var sorted := shape.sorted_segments()
	var last: BoundarySegment = sorted[-1]
	var mid := (last.u0 + last.u1) * 0.5
	var point: Vector2 = last.point_at(0.5)
	_app.begin_edit()
	shape.segments.append(BoundarySegment.new(mid, last.u1, point, last.p1, last.ix, last.iy, last.gap))
	last.u1 = mid
	last.p1 = point
	_app.finish_edit()
	_app.select_segment(shape.sorted_segments().find(last))


func _delete_segment(shape: BoundaryShape) -> void:
	var sorted := shape.sorted_segments()
	if sorted.size() <= 1 or _app.selected_segment_index < 0:
		return
	var index: int = _app.selected_segment_index
	var segment: BoundarySegment = sorted[index]
	_app.begin_edit()
	if index > 0:
		var previous := sorted[index - 1]
		previous.u1 = segment.u1
		previous.p1 = segment.p1
	else:
		var next := sorted[1]
		next.u0 = segment.u0
		next.p0 = segment.p0
	shape.segments.erase(segment)
	_app.finish_edit()
	_app.select_segment(0)


func _split_segment_mid(shape: BoundaryShape) -> void:
	var segment: BoundarySegment = _app.get_selected_segment()
	if segment == null:
		return
	var u: float = (segment.u0 + segment.u1) * 0.5
	var point: Vector2 = segment.point_at(0.5)
	var first := BoundarySegment.new(segment.u0, u, segment.p0, point, segment.ix, segment.iy, segment.gap)
	var second := BoundarySegment.new(u, segment.u1, point, segment.p1, segment.ix, segment.iy, segment.gap)
	_app.begin_edit()
	shape.segments.erase(segment)
	shape.segments.append(first)
	shape.segments.append(second)
	shape.segments.sort_custom(func(a: BoundarySegment, b: BoundarySegment) -> bool: return a.u0 < b.u0)
	_app.finish_edit()
	_app.select_segment(shape.sorted_segments().find(first))


func _preset(shape: BoundaryShape, kind: String) -> void:
	var replacement: BoundaryShape
	match kind:
		"circle":
			replacement = BoundaryShape.circle(shape.id, 330.0, 32)
		"ellipse":
			replacement = BoundaryShape.ellipse(shape.id, 410.0, 245.0, 32)
		"tall":
			replacement = BoundaryShape.ellipse(shape.id, 300.0, 400.0, 32)
		"gap":
			replacement = BoundaryShape.circle(shape.id, 330.0, 32)
			if not replacement.segments.is_empty():
				replacement.segments[0].gap = true
		_:
			return
	_app.begin_edit()
	shape.segments = replacement.segments
	shape.closed = replacement.closed
	_app.finish_edit()


func _add_event() -> void:
	var event := BoundaryEvent.new(_app.chart.next_event_id(), _app.playhead_beat, _app.playhead_beat + 4.0, 0.0, 1.0, _app.chart.default_shape_id, _app.chart.default_shape_id)
	_app.begin_edit()
	_app.chart.events.append(event)
	_app.finish_edit()
	_app.select_event(event.id)


func _duplicate_event(event: BoundaryEvent) -> void:
	var copy := BoundaryEvent.from_dict(event.to_dict())
	copy.id = _app.chart.next_event_id()
	copy.start_beat += 4.0
	copy.end_beat += 4.0
	_app.begin_edit()
	_app.chart.events.append(copy)
	_app.finish_edit()
	_app.select_event(copy.id)


func _delete_event(event: BoundaryEvent) -> void:
	_app.begin_edit()
	_app.chart.events.erase(event)
	_app.finish_edit()
	_app.clear_selection()


func _add_view_state() -> void:
	var state := ViewState.new(_app.playhead_beat, 1.0, 0.0, 0.0, 1.0, 0.0, "in-out")
	_app.begin_edit()
	_app.chart.view_states.append(state)
	_app.finish_edit()
	_app.select_view(_app.chart.view_states.size() - 1)


func _delete_view_state(state: ViewState) -> void:
	_app.begin_edit()
	_app.chart.view_states.erase(state)
	_app.finish_edit()
	_app.selected_view_index = -1


func _pick_video() -> void:
	if _video_dialog != null:
		return
	_video_dialog = FileDialog.new()
	_video_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_video_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_video_dialog.filters = PackedStringArray(["*.ogv ; Ogg Theora", "*.mp4 ; MP4", "*.webm ; WebM", "*.mov ; MOV", "*.mkv ; MKV", "*.avi ; AVI"])
	_video_dialog.title = "选择 Ogg Theora 视频"
	_video_dialog.file_selected.connect(func(path: String) -> void:
		_app.mutate(func() -> void:
			_app.chart.video_path = path
		)
		_video_dialog.queue_free()
		_video_dialog = null
	)
	_video_dialog.canceled.connect(func() -> void:
		_video_dialog.queue_free()
		_video_dialog = null
	)
	add_child(_video_dialog)
	_video_dialog.popup_centered_ratio(0.6)
