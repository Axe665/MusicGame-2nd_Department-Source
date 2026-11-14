class_name Inspector
extends TabContainer

const BellPreviewScript = preload("res://charter/bell_preview.gd")
const HoldPreviewScript = preload("res://charter/hold_preview.gd")


## 通用「宽度」行：Tap/Hold 的环上弧宽由它 × 长度比例决定。
## 通用「宽度」行：Tap/Hold 的环上弧宽由它 × 长度比例决定。
## Bell 用专属「弧宽」；Limit 在区域页。
static func shows_width_row(note_type: String) -> bool:
	return note_type in ["tap", "hold"]


## 通用「长度 ×l」行只给 Tap；改了就变成大小 Tap。
static func shows_length_row(note_type: String) -> bool:
	return note_type == "tap"

var _app: Node = null
var _pages: Dictionary = {}
var _page_list: Array[VBoxContainer] = []
var _applying: bool = false
var _rebuilding: bool = false
var _video_dialog: FileDialog
var _video_progress: AcceptDialog
var _video_progress_bar: ProgressBar
var _video_progress_label: Label
var _selected_timing: int = 0
var _selected_visual: int = 0
var _note_page_ready: bool = false
var _note_page_chart: Chart = null
var _active_note: Note = null
var _note_groups: Dictionary = {}
var _note_rows: Dictionary = {}
var _note_widgets: Dictionary = {}
var _note_empty_label: Label = null
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
	if _app != null:
		_prebuild_note_page()


func _build_tabs() -> void:
	for title in ["音符", "区域", "视图", "时间", "谱面"]:
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
	_rebuild()


func _on_chart_changed() -> void:
	if _app != null and _app.ring_editor_open:
		return
	if not _applying:
		_rebuild()


func _on_tool_changed(tool: String) -> void:
	if tool == "limit":
		current_tab = 1
	_rebuild()


func _on_tab_changed(_tab: int) -> void:
	if not _rebuilding:
		_rebuild()


func _rebuild() -> void:
	if _app == null or _rebuilding:
		return
	_rebuilding = true
	if current_tab == 0 and _note_page_ready and _note_page_chart == _app.chart and _app.selected_notes.size() == 1 and _app.get_selected_note() != null:
		_refresh_note_page()
		refresh_tab_titles()
		_rebuilding = false
		return
	if current_tab == 0 and _note_page_ready and _note_page_chart == _app.chart and _app.selected_notes.is_empty():
		_show_note_empty()
		refresh_tab_titles()
		_rebuilding = false
		return
	var current_page: VBoxContainer = _page_list[clampi(current_tab, 0, _page_list.size() - 1)]
	for child in current_page.get_children():
		child.queue_free()
	if current_tab == 0:
		_note_page_ready = false
	match current_tab:
		0:
			_build_note_page(_pages["音符"])
		1:
			_build_region_page(_pages["区域"])
		2:
			_build_view_page(_pages["视图"])
		3:
			_build_timing_page(_pages["时间"])
		4:
			_build_chart_page(_pages["谱面"])
	refresh_tab_titles()
	_rebuilding = false


func refresh_tab_titles() -> void:
	if _app == null:
		return
	var note_count: int = _app.selected_notes.size()
	# 环相关编辑都在「环编辑」工作区；这里保留音符/区域/视图/时间/谱面。
	set_tab_title(0, "音符")
	set_tab_title(1, "区域" if _app.selected_region_id < 0 else "区域 %d" % _app.selected_region_id)
	set_tab_title(2, "视图")
	set_tab_title(3, "时间")
	set_tab_title(4, "谱面")
	if note_count > 0:
		set_tab_title(0, "音符 %d" % note_count)


func _empty(title: String, hint: String) -> void:
	var page: VBoxContainer = _pages[title]
	_section(page, title)
	_label(page, hint, 12, UITheme.MUTED)


func _section(page: VBoxContainer, title: String) -> Label:
	var label := Label.new()
	label.text = title
	UITheme.style_section(label)
	page.add_child(label)
	return label


func _label(page: VBoxContainer, text: String, size: int = 12, color: Color = UITheme.MUTED, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	page.add_child(label)
	return label


func _row(page: VBoxContainer, label_text: String, control: Control) -> HBoxContainer:
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
	return row


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


func _spin_slider(page: VBoxContainer, label_text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable, refresh_after: bool = false) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.size_flags_stretch_ratio = 3.0
	row.add_child(spin)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_stretch_ratio = 2.0
	slider.custom_minimum_size = Vector2(72, 18)
	row.add_child(slider)
	page.add_child(row)
	var commit := func(new_value: float) -> void:
		if _applying:
			return
		_apply(func() -> void: callback.call(new_value))
		spin.set_value_no_signal(new_value)
		slider.set_value_no_signal(new_value)
		if refresh_after:
			_refresh_note_page()
	spin.value_changed.connect(commit)
	slider.value_changed.connect(commit)
	return {"spin": spin, "slider": slider}


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


func _setting_option(page: VBoxContainer, label_text: String, items: Array[String], selected: int, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	option.item_selected.connect(func(index: int) -> void:
		if not _applying:
			callback.call(index)
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


func _buttons(page: VBoxContainer, specs: Array[Dictionary]) -> HBoxContainer:
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
	return row


func _quality_changed() -> void:
	_app.quality_preset = "custom"
	_app.save_settings()
	_app.apply_visual_quality()
	_app.appearance_changed.emit()
	call_deferred("_rebuild")


func _apply(callback: Callable) -> void:
	if _app == null:
		return
	_applying = true
	_app.mutate(callback)
	_applying = false


func _note_group(page: VBoxContainer, key: String, title: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = title
	UITheme.style_section(label)
	group.add_child(label)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	group.add_child(body)
	page.add_child(group)
	_note_groups[key] = group
	return body


func _remember_row(key: String, control: Control) -> void:
	_note_rows[key] = control.get_parent()


func _build_note_page(page: VBoxContainer) -> void:
	if _app.selected_notes.size() > 1:
		_note_page_ready = false
		_section(page, "多选")
		_label(page, "已选中 %d 个音符。拖动可整体移动；数值混合时不显示单一值。" % _app.selected_notes.size(), 12, UITheme.INK)
		var types := {}
		for item in _app.get_selected_notes():
			types[item.type] = true
		_label(page, "类型：%s" % ",".join(types.keys()), 12, UITheme.MUTED)
		_label(page, "快捷键：批量复制 Ctrl+C ｜ 批量粘贴 Ctrl+V ｜ 批量镜像粘贴 Ctrl+A", 11, UITheme.CYAN)
		_buttons(page, [
			{"text": "删除选中", "callback": _delete_selected},
			{"text": "解锁", "callback": _unlock_selected},
		])
		return
	var note: Note = _app.get_selected_note()
	if note == null:
		_note_page_ready = false
		_empty("音符", "在上方类型卡片（或 1–7 快捷键）选择工具；点击画布放置，预览窗可点边界放置。")
		return
	if _note_page_ready and _note_page_chart == _app.chart:
		_refresh_note_page()
		return
	_note_page_ready = true
	_note_page_chart = _app.chart
	_active_note = note
	_build_note_page_for(page, note)
	_refresh_note_page()


func _build_note_page_for(page: VBoxContainer, note: Note) -> void:
	_note_groups.clear()
	_note_rows.clear()
	_note_widgets.clear()

	var common := _note_group(page, "common", "音符")
	var type_value := _readonly("")
	_note_rows["type"] = _row(common, "类型", type_value)
	_note_widgets["type"] = type_value
	var id_value := _readonly("")
	_note_rows["id"] = _row(common, "id", id_value)
	_note_widgets["id"] = id_value
	var start_edit := _beat(common, "开始拍", note.beat, func(value: float) -> void:
		var n := _active_note
		if n == null:
			return
		var delta := value - n.beat
		n.beat = value
		if n.type in ["hold", "path"]:
			n.end_beat = maxf(n.beat + 0.25, n.end_beat + delta)
	)
	_note_widgets["start"] = start_edit
	_remember_row("start", start_edit)
	var end_edit := _beat(common, "结束拍", note.end_beat, func(value: float) -> void:
		var n := _active_note
		if n != null:
			n.end_beat = maxf(n.beat + 0.25, value)
			if n.type == "path":
				n.wait_beat = clampf(n.wait_beat, 0.0, maxf(0.0, n.duration() - 0.001))
	)
	_note_widgets["end"] = end_edit
	_remember_row("end", end_edit)
	var angle_spin := _spin(common, "逻辑角度", note.angle, 0.0, 360.0, 0.5, func(value: float) -> void:
		var n := _active_note
		if n == null:
			return
		n.angle = fposmod(value, 360.0)
		if n.type == "bell":
			n.center_u = fposmod(n.angle / 360.0, 1.0)
		elif n.type == "path":
			n.generate_path_shape()
			_sync_path_chain(n)
	)
	_note_widgets["angle"] = angle_spin
	_remember_row("angle", angle_spin)
	var width_spin := _spin(common, "基础宽度 °", note.width, 0.0, 360.0, 1.0, func(value: float) -> void:
		if _active_note != null:
			_active_note.width = value
			if _active_note.type == "hold" and _note_widgets.has("hold_preview"):
				_note_widgets["hold_preview"].set_state(_active_note.arc_width(), _active_note.duration())
			_update_tap_formula()
	)
	width_spin.tooltip_text = "基础宽度：实际弧宽 = 基础宽度 × 长度倍率；普通 Tap/Hold 60° × 0.50 = 30°"
	_note_widgets["width"] = width_spin
	_remember_row("width", width_spin)
	# 大小 Tap：到判定环的长度，单位是 l（旧版 tap 的长度）。0.00–1.50，两位小数。
	var length_spin := _spin(common, "长度倍率 ×l", note.length_ratio(), Note.SIZED_TAP_MIN, Note.SIZED_TAP_MAX, 0.01, func(value: float) -> void:
		if _active_note != null and _active_note.type == "tap":
			_active_note.set_size_ratio(value)
			_update_tap_formula()
	)
	length_spin.tooltip_text = "0.50 = 普通 Tap；1.00 = 与基础宽度相同；1.50 = 1.5 倍。改离 0.50 会变成大小 Tap"
	_note_widgets["length"] = length_spin
	_remember_row("length", length_spin)
	var tap_group := _note_group(page, "tapsize", "Tap 长度（大小 Tap）")
	_label(tap_group, "实际弧宽 = 基础宽度 × 长度倍率。普通 Tap 固定 0.50 l；改长度倍率会变成「大小 Tap」，谱面会记住自定义长度。环心出现时是 1/6 l。", 11, UITheme.MUTED)
	var tap_formula := _label(tap_group, "", 11, UITheme.CYAN)
	_note_widgets["tap_formula"] = tap_formula
	_buttons(tap_group, [
		{"text": "恢复普通 Tap（0.50 l）", "callback": func() -> void:
			if _active_note != null and _active_note.type == "tap":
				_apply(func() -> void:
					_active_note.sized = false
					_active_note.size_ratio = 0.5
				)
				_refresh_note_page()},
	])

	var bell := _note_group(page, "bell", "金键 Bell")
	var bu := _spin(bell, "中心 u", note.center_u, 0.0, 0.9999, 0.001, func(value: float) -> void:
		if _active_note != null:
			_active_note.center_u = value
	)
	_note_widgets["bell_u"] = bu
	var bw := _spin(bell, "弧宽 °", note.bell_width(), Note.BELL_MIN_WIDTH, Note.BELL_MAX_WIDTH, 1.0, func(value: float) -> void:
		if _active_note != null:
			_active_note.width = value
		if _note_widgets.has("bell_preview"):
			_note_widgets["bell_preview"].set_arc_width(value)
	)
	_note_widgets["bell_w"] = bw
	var br := _spin(bell, "半径 px", note.radius, 4.0, 200.0, 1.0, func(value: float) -> void:
		if _active_note != null:
			_active_note.radius = value
	)
	_note_widgets["bell_r"] = br
	_label(bell, "金键：白描边 + 金色核心 + 圆头；光标贴住即算在场（±100ms，触碰会立刻锁定），不用点。「弧宽」和 Tap 到环时的 31° 同级（24–30°），决定可见与判定长度。", 11, UITheme.MUTED)
	var bell_preview := BellPreviewScript.new()
	bell_preview.name = "BellShapePreview"
	bell_preview.set_arc_width(note.bell_width())
	bell.add_child(bell_preview)
	_note_widgets["bell_preview"] = bell_preview

	if note.type == "path":
		note.derive_path_controls()
	var path_body := _note_group(page, "path", "Path")
	# 星星颜色：不设时用统一绿色；有重叠时预览会自动分配互不相同的颜色。
	var color_row := HBoxContainer.new()
	path_body.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "星星颜色"
	UITheme.style_mono(color_label, 11, UITheme.MUTED)
	color_row.add_child(color_label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(96, 22)
	picker.edit_alpha = false
	picker.color = note.custom_color if note.has_custom_color else Note.DEFAULT_PATH_COLOR
	picker.color_changed.connect(func(chosen: Color) -> void:
		if _active_note == null:
			return
		_apply(func() -> void:
			_active_note.has_custom_color = true
			_active_note.custom_color = chosen
		)
		_refresh_note_page()
	)
	color_row.add_child(picker)
	var color_reset := Button.new()
	color_reset.text = "默认绿"
	color_reset.pressed.connect(func() -> void:
		if _active_note == null:
			return
		_apply(func() -> void: _active_note.has_custom_color = false)
		_refresh_note_page()
	)
	color_row.add_child(color_reset)
	var tail_display := _path_tail_display(note)
	var tail_radius := tail_display.x
	var tail_degrees := tail_display.y
	var tr := _spin(path_body, "尾半径 R", tail_radius, -1.0, 1.0, 0.01, func(value: float) -> void:
		var n := _active_note
		if n == null:
			return
		_set_path_tail(n, value, _path_tail_display(n).y)
	)
	_note_widgets["path_tail_r"] = tr
	var ta := _spin(path_body, "尾角度", tail_degrees, 0.0, 360.0, 0.5, func(value: float) -> void:
		var n := _active_note
		if n == null:
			return
		_set_path_tail(n, _path_tail_display(n).x, value)
	)
	_note_widgets["path_tail_a"] = ta
	var tw := _spin(path_body, "尾宽度", note.tail_width, 0.0, 360.0, 1.0, func(value: float) -> void:
		if _active_note != null:
			_active_note.tail_width = value
	)
	_note_widgets["path_tail_w"] = tw
	var tol := _spin(path_body, "容差比例", note.tolerance, 0.0, 1.0, 0.01, func(value: float) -> void:
		if _active_note != null:
			_active_note.tolerance = value
	)
	_note_widgets["path_tol"] = tol
	var samples := _spin(path_body, "采样/拍", note.samples_per_beat, 0.25, 32.0, 0.25, func(value: float) -> void:
		if _active_note != null:
			_active_note.samples_per_beat = value
	)
	_note_widgets["path_samples"] = samples
	var speed := _spin(path_body, "滑动速度", note.path_speed, 0.5, 3.0, 0.05, func(value: float) -> void:
		if _active_note != null:
			_active_note.path_speed = value
	)
	_note_widgets["path_speed"] = speed
	var path_counts := _label(path_body, "", 11, UITheme.MUTED)
	_note_widgets["path_counts"] = path_counts
	_buttons(path_body, [{"text": "重画 Path", "callback": func() -> void: _app.set_tool("path")}])
	_label(path_body, "中间判定点（设计）", 12, UITheme.INK)
	var path_list := ItemList.new()
	path_list.custom_minimum_size = Vector2(0, 96)
	path_list.item_selected.connect(func(index: int) -> void:
		_selected_visual = index
		_refresh_note_page()
	)
	path_body.add_child(path_list)
	_note_widgets["path_list"] = path_list
	_buttons(path_body, [
		{"text": "加判定点", "callback": func() -> void: _add_visual_point(_active_note)},
		{"text": "删判定点", "callback": func() -> void: _delete_visual_point(_active_note)},
	])
	var pdb := _spin(path_body, "Δbeat", 0.0, 0.0, 1.0, 0.01, func(value: float) -> void:
		var n := _active_note
		if n != null and _selected_visual >= 0 and _selected_visual < n.visual_pts.size():
			n.visual_pts[_selected_visual]["db"] = value
	)
	_note_widgets["path_db"] = pdb
	_remember_row("path_db", pdb)
	var pda := _spin(path_body, "Δangle", 0.0, -720.0, 720.0, 0.5, func(value: float) -> void:
		var n := _active_note
		if n != null and _selected_visual >= 0 and _selected_visual < n.visual_pts.size():
			n.visual_pts[_selected_visual]["da"] = value
	)
	_note_widgets["path_da"] = pda
	_remember_row("path_da", pda)
	_label(path_body, "判定点只做编辑器标记；中段仍是滑到即可，不逐点扣分。", 11, UITheme.MUTED)
	_label(path_body, "跳区 / 擦除", 12, UITheme.INK)
	var erase := _spin(path_body, "中段擦除 %", 0.0, 0.0, 80.0, 5.0, func(value: float) -> void:
		if _active_note != null:
			_set_path_erase_width(_active_note, value / 100.0)
	)
	_note_widgets["path_erase"] = erase
	_buttons(path_body, [{"text": "清除擦除", "callback": func() -> void:
		if _active_note != null:
			_apply(func() -> void: _set_path_erase_width(_active_note, 0.0))
			_refresh_note_page()
	}])
	_label(path_body, "擦除段不渲染、不生成中段检查点；头尾仍各自判定。", 11, UITheme.MUTED)

	# New, minimal Path editor. The legacy controls above stay built for data
	# compatibility but are hidden; authors now edit centrifuge + axis + parts.
	var path_edit := _note_group(page, "path_edit", "Path")
	var wait_edit := _spin(path_edit, "等待拍数", note.wait_beat, 0.0, maxf(0.0, note.duration() - 0.001), 0.125, func(value: float) -> void:
		if _active_note != null:
			_active_note.wait_beat = clampf(value, 0.0, maxf(0.0, _active_note.duration() - 0.001))
	)
	wait_edit.allow_greater = false
	wait_edit.tooltip_text = "从头部落点到星星起划的拍数；包含在总时长内。0 表示立即起划。"
	_note_widgets["path_wait"] = wait_edit
	_label(path_edit, "等待包含在总时长内；增加等待会缩短滑动时间。链式 Path 的启动提示使用 part0 的等待。", 10, UITheme.MUTED)
	var centrifuge := _spin_slider(path_edit, "尾部离心 centrifuge", note.path_centrifuge, 0.0, 1.0, 0.01, func(value: float) -> void:
		var n := _active_note
		if n != null:
			n.set_path_centrifuge(value)
			_sync_path_chain(n)
	, true)
	_note_widgets["path_centrifuge"] = centrifuge["spin"]
	_note_widgets["path_centrifuge_slider"] = centrifuge["slider"]
	var axis := _spin_slider(path_edit, "轨迹轴长 axis", note.path_axis, -2.0, 2.0, 0.01, func(value: float) -> void:
		var n := _active_note
		if n != null:
			n.set_path_axis(value)
			_sync_path_chain(n)
	, true)
	_note_widgets["path_axis"] = axis["spin"]
	_note_widgets["path_axis_slider"] = axis["slider"]
	var axis_bar := Control.new()
	axis_bar.custom_minimum_size = Vector2(0, 36)
	axis_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	axis_bar.draw.connect(func() -> void:
		var font := UITheme.mono_font()
		var line_y := 24.0
		axis_bar.draw_line(Vector2(0, line_y), Vector2(axis_bar.size.x, line_y), Color(1, 1, 1, 0.22), 1.0, true)
		for pair in [{"value": -1.0, "text": "-R"}, {"value": 0.0, "text": "L"}, {"value": 1.0, "text": "R"}]:
			var x: float = axis_bar.size.x * (float(pair["value"]) + 2.0) / 4.0
			var hot: bool = absf(float(_active_note.path_axis) - float(pair["value"])) < 0.06 if _active_note != null else false
			axis_bar.draw_line(Vector2(x, 17), Vector2(x, 31), UITheme.CYAN if hot else Color(1, 1, 1, 0.42), 2.0 if hot else 1.0, true)
			var text := String(pair["text"])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			axis_bar.draw_string(font, Vector2(x - width * 0.5, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
	)
	axis_bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if axis_bar.size.x <= 1.0:
				return
			for anchor in [-1.0, 0.0, 1.0]:
				var x: float = axis_bar.size.x * (anchor + 2.0) / 4.0
				if absf(event.position.x - x) <= 10.0:
					var n := _active_note
					if n != null and not _applying:
						_apply(func() -> void:
							n.set_path_axis(anchor)
							_sync_path_chain(n)
						)
						_refresh_note_page()
					break
	)
	path_edit.add_child(axis_bar)
	_note_widgets["path_axis_bar"] = axis_bar
	var end_angle := _spin(path_edit, "尾部角度", note.tail_angle, 0.0, 360.0, 0.5, func(value: float) -> void:
		var n := _active_note
		if n != null:
			n.tail_angle = fposmod(value, 360.0)
			n.generate_path_shape()
			_sync_path_chain(n)
	)
	_note_widgets["path_end_angle"] = end_angle
	var part_label := _label(path_edit, "", 11, UITheme.MUTED)
	_note_widgets["path_part_label"] = part_label
	_label(path_edit, "右键单击 Path 尾部可在该处新建 part；各 part 可分别编辑，预览中整条链共用 part0 的星星。", 10, UITheme.MUTED)

	var hold_body := _note_group(page, "hold", "Hold")
	_label(hold_body, "实际弧宽 = 基础宽度 × 0.50（Hold 头固定）；预览按 1 拍身体展示，改上面的「基础宽度」会实时变。", 11, UITheme.MUTED)
	var hold_preview := HoldPreviewScript.new()
	hold_preview.name = "HoldShapePreview"
	hold_preview.set_state(note.arc_width(), note.duration())
	hold_body.add_child(hold_preview)
	_note_widgets["hold_preview"] = hold_preview

	var anchor_body := _note_group(page, "anchor", "Anchor")
	var pair_id := _text(anchor_body, "pairId", note.pair_id, func(value: String) -> void:
		if _active_note != null:
			var partner: Note = _app.chart.anchor_partner(_active_note) if _app != null and _app.chart != null else null
			_active_note.pair_id = value
			if partner != null:
				partner.pair_id = value
	)
	_note_widgets["anchor_pair_id"] = pair_id
	_buttons(anchor_body, [{"text": "创建反向配对", "callback": func() -> void:
		if _active_note != null:
			_add_anchor_pair(_active_note)
	}])
	_label(anchor_body, "双押配置：同拍两颗、180° 反向；试玩时瞄准任一锚点、同时按两个键。", 11, UITheme.MUTED)

	var seek_body := _note_group(page, "seek", "Seek")
	var seek_orien := _option(seek_body, "朝向", ["外", "里"], note.seek_orien, func(index: int) -> void:
		if _active_note != null:
			_active_note.seek_orien = 1 if index == 1 else 0
			_active_note.seek_pending = false
	)
	_note_widgets["seek_orien"] = seek_orien
	_label(seek_body, "外 = 滚轮上滑；里 = 滚轮下滑。", 11, UITheme.MUTED)

	var misc := _note_group(page, "misc", "通用")
	var color_group := _option(misc, "配色组", ["默认"], 0, func(index: int) -> void:
		if _active_note != null:
			_active_note.color = index
	)
	_note_widgets["color_group"] = color_group
	var custom := ColorPickerButton.new()
	custom.edit_alpha = false
	custom.custom_minimum_size = Vector2(64, 24)
	custom.color_changed.connect(func(value: Color) -> void:
		if _applying or _active_note == null:
			return
		_apply(func() -> void:
			_active_note.custom_color = value
			_active_note.has_custom_color = true
		)
	)
	_note_widgets["custom_color"] = custom
	_note_rows["custom_color"] = _row(misc, "自定义色", custom)
	var lock := _check(misc, "锁定（不可拖动）", note.lock, func(value: bool) -> void:
		if _active_note != null:
			_active_note.lock = value
	)
	_note_widgets["lock"] = lock
	_buttons(misc, [
		{"text": "清除自定义色", "callback": func() -> void:
			if _active_note != null:
				_apply(func() -> void: _active_note.has_custom_color = false)},
		{"text": "管理配色…", "callback": func() -> void:
			current_tab = 4},
		{"text": "定位播放头", "callback": func() -> void:
			if _active_note != null:
				_app.set_playhead(_active_note.beat)},
		{"text": "复制", "callback": func() -> void:
			if _active_note != null:
				_duplicate_note(_active_note)},
		{"text": "删除", "callback": func() -> void:
			if _active_note != null:
				_delete_note(_active_note)},
	])


func _prepare_note_empty_label(page: VBoxContainer) -> void:
	if _note_empty_label != null and is_instance_valid(_note_empty_label):
		return
	_note_empty_label = Label.new()
	_note_empty_label.text = "选择一个音符开始编辑；画布单击或预览边界可放置。"
	_note_empty_label.add_theme_font_size_override("font_size", 12)
	_note_empty_label.add_theme_color_override("font_color", UITheme.MUTED)
	page.add_child(_note_empty_label)


func _show_note_empty() -> void:
	var page: VBoxContainer = _pages["音符"]
	_prepare_note_empty_label(page)
	for group in _note_groups.values():
		if group is Control:
			group.visible = false
	_note_empty_label.visible = true


func _prebuild_note_page() -> void:
	# 启动时一次性构建静态页，之后选择音符只刷新数值，不再创建中文控件。
	var page: VBoxContainer = _pages["音符"]
	for child in page.get_children():
		child.queue_free()
	var dummy := Note.new("tap", 0.0, 0.0, 60.0)
	dummy.id = -1
	_build_note_page_for(page, dummy)
	_note_page_ready = true
	_note_page_chart = _app.chart
	_active_note = null
	_show_note_empty()


func _refresh_note_page() -> void:
	var note: Note = _app.get_selected_note()
	if note == null or not _note_page_ready:
		return
	_active_note = note
	if _note_empty_label != null and is_instance_valid(_note_empty_label):
		_note_empty_label.visible = false
	_applying = true
	_note_widgets["type"].text = note.type
	_note_widgets["id"].text = str(note.id)
	_note_widgets["start"].text = _app.chart.timing.format_beat(note.beat)
	_note_widgets["end"].text = _app.chart.timing.format_beat(note.end_beat)
	_note_widgets["angle"].value = note.angle
	_note_widgets["width"].value = note.width
	_note_widgets["length"].value = note.length_ratio()
	_update_tap_formula()
	var is_bell := note.type == "bell"
	_note_rows["end"].visible = note.type in ["hold", "path"]
	_note_rows["angle"].visible = note.type in ["tap", "hold", "path", "anchor", "bell"]
	_note_rows["width"].visible = shows_width_row(note.type)
	_note_rows["length"].visible = shows_length_row(note.type)
	_note_groups["common"].visible = true
	_note_groups["misc"].visible = true
	var can_color := note.supports_custom_color()
	var group_option: OptionButton = _note_widgets["color_group"]
	group_option.clear()
	group_option.add_item("默认")
	for index in range(_app.chart.palette.size()):
		group_option.add_item(_app.chart.palette_name(index + 1))
	group_option.selected = clampi(note.color, 0, maxi(0, group_option.item_count - 1))
	_note_widgets["color_group"].get_parent().visible = can_color
	_note_rows["custom_color"].visible = can_color
	var fallback := UITheme.PINK if note.type == "tap" else (UITheme.GOLD if note.type == "hold" else Note.DEFAULT_PATH_COLOR)
	_note_widgets["custom_color"].color = note.resolved_color(_app.chart, fallback)
	# 锁定是 _check 直接挂在组体上的；恢复显示，不改组体。
	_note_widgets["lock"].visible = true
	_note_groups["tapsize"].visible = shows_length_row(note.type)
	_note_groups["bell"].visible = is_bell
	_note_groups["path"].visible = false
	_note_groups["path_edit"].visible = note.type == "path"
	_note_groups["hold"].visible = note.type == "hold"
	_note_groups["seek"].visible = note.type == "seek"
	_note_groups["anchor"].visible = note.type == "anchor"
	_note_widgets["bell_u"].value = note.center_u
	_note_widgets["bell_w"].value = note.bell_width()
	_note_widgets["bell_preview"].set_arc_width(note.bell_width())
	_note_widgets["bell_r"].value = note.radius
	if note.type == "path":
		note.derive_path_controls()
		var tail_display := _path_tail_display(note)
		_note_widgets["path_tail_r"].value = tail_display.x
		_note_widgets["path_tail_a"].value = tail_display.y
		_note_widgets["path_tail_w"].value = note.tail_width
		_note_widgets["path_tol"].value = note.tolerance
		_note_widgets["path_samples"].value = note.samples_per_beat
		_note_widgets["path_speed"].value = note.path_speed
		_note_widgets["path_counts"].text = "中间判定点：%d 个；平面点：%d 个" % [note.path_sample_beats().size(), note.trace_pts.size()]
		_fill_visual_list(_note_widgets["path_list"], note)
		_note_widgets["path_erase"].value = _path_erase_width(note) * 100.0
		_note_widgets["path_wait"].max_value = maxf(0.0, note.duration() - 0.001)
		_note_widgets["path_wait"].value = note.wait_beat
		_note_widgets["path_centrifuge"].value = note.path_centrifuge
		_note_widgets["path_centrifuge_slider"].value = note.path_centrifuge
		_note_widgets["path_axis"].value = note.path_axis
		_note_widgets["path_axis_slider"].value = note.path_axis
		_note_widgets["path_axis_bar"].queue_redraw()
		_note_widgets["path_end_angle"].value = note.tail_angle
		var relation := ""
		if note.path_prev_id >= 0:
			relation += " ｜ 上一段 #%d" % note.path_prev_id
		if note.path_next_id >= 0:
			relation += " ｜ 下一段 #%d" % note.path_next_id
		_note_widgets["path_part_label"].text = "段落 part%d%s" % [note.path_part, relation]
	if note.type == "seek":
		_note_widgets["seek_orien"].selected = 1 if note.seek_orien == 1 else 0
	if note.type == "hold":
		_note_widgets["hold_preview"].set_state(note.arc_width(), note.duration())
	if note.type == "anchor":
		_note_widgets["anchor_pair_id"].text = note.pair_id
	_note_widgets["lock"].button_pressed = note.lock
	_applying = false


func _update_tap_formula() -> void:
	if _active_note == null or _active_note.type != "tap":
		return
	var label: Label = _note_widgets.get("tap_formula")
	if not is_instance_valid(label):
		return
	label.text = "实际弧宽 %.1f° = 基础 %.1f° × %.2f l" % [
		_active_note.arc_width(),
		_active_note.width,
		_active_note.length_ratio(),
	]


func _fill_visual_list(list: ItemList, note: Note) -> void:
	list.clear()
	for i in note.visual_pts.size():
		var point: Dictionary = note.visual_pts[i]
		list.add_item("%02d  Δbeat %.2f  Δangle %.1f" % [i, float(point.get("db", 0.0)), float(point.get("da", 0.0))])
	_selected_visual = clampi(_selected_visual, 0, maxi(0, note.visual_pts.size() - 1))
	if _selected_visual < list.item_count:
		list.select(_selected_visual)
	var has_point := _selected_visual >= 0 and _selected_visual < note.visual_pts.size()
	if _note_rows.has("path_db"):
		_note_rows["path_db"].visible = has_point and note.type == "path"
		_note_rows["path_da"].visible = has_point and note.type == "path"
	if has_point:
		var point: Dictionary = note.visual_pts[_selected_visual]
		if note.type == "path":
			_note_widgets["path_db"].value = float(point.get("db", 0.0))
			_note_widgets["path_da"].value = float(point.get("da", 0.0))


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


func _set_hold_style(note: Note, style: String) -> void:
	_apply(func() -> void:
		note.hold_style = style
	)
	_rebuild()


func _path_tail_display(note: Note) -> Vector2:
	## The tail is stored as a point. Keep a negative R meaningful by comparing
	## the point direction with the author-facing tail angle: an opposite point
	## means R is negative (the tail crossed the ring centre).
	var local := note.path_tail_local()
	var radius := local.length()
	if radius <= 0.0001:
		return Vector2(0.0, fposmod(note.tail_angle, 360.0))
	var actual := rad_to_deg(atan2(local.y, local.x))
	var delta := absf(fposmod(actual - note.tail_angle + 180.0, 360.0) - 180.0)
	if delta >= 179.0:
		return Vector2(-radius, fposmod(note.tail_angle, 360.0))
	return Vector2(radius, actual)


func _sync_path_chain(parent: Note) -> void:
	if _app == null or _app.chart == null or parent == null:
		return
	var next_id := parent.path_next_id
	var guard := 0
	while next_id >= 0 and guard < 64:
		var child: Note = null
		for item in _app.chart.notes:
			if item.id == next_id:
				child = item
				break
		if child == null or child.type != "path":
			break
		var head := parent.path_tail_local()
		child.path_head_local = head
		child.path_prev_id = parent.id
		child.angle = rad_to_deg(atan2(head.y, head.x))
		child.generate_path_shape()
		parent = child
		next_id = child.path_next_id
		guard += 1


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
		_empty("区域", "用 Limit 工具（7）在画布拖拽创建限制区；长度上限 4 拍。")
		_buttons(page, [{"text": "Limit 工具", "callback": func() -> void: _app.set_tool("limit")}])
		return
	_section(page, "Limit #%d" % region.id)
	_row(page, "类型", _readonly(region.kind))
	_beat(page, "开始拍", region.start_beat, func(value: float) -> void: region.start_beat = value)
	_beat(page, "结束拍", region.end_beat, func(value: float) -> void: region.end_beat = value)
	var angle_row := _spin(page, "逻辑角度", region.angle, 0.0, 360.0, 0.5, func(value: float) -> void: region.angle = fposmod(value, 360.0))
	angle_row.get_parent().visible = false
	var width_spin := _spin(page, "逻辑宽度", region.width, 0.0, 360.0, 1.0, func(value: float) -> void: region.width = value)
	width_spin.get_parent().visible = true
	var polarity_row := _spin(page, "极性", region.polarity, -1.0, 1.0, 2.0, func(value: float) -> void: region.polarity = int(value))
	polarity_row.get_parent().visible = false
	var shapes: Array[String] = [""]
	for shape in _app.chart.sorted_shapes():
		shapes.append(shape.id)
	var shape_option := _option(page, "形状引用", shapes, maxi(0, shapes.find(region.shape)), func(index: int) -> void: region.shape = shapes[index])
	shape_option.get_parent().visible = false
	_label(page, "时长 %.2f 拍 / 上限 4.00 拍；同刻公共角度减去限制区后必须非空。" % region.duration(), 11, UITheme.MUTED)
	_buttons(page, [
		{"text": "定位播放头", "callback": func() -> void: _app.set_playhead(region.start_beat)},
		{"text": "删除", "callback": func() -> void: _delete_region(region)},
	])


func _build_view_page(page: VBoxContainer) -> void:
	_section(page, "音符与音效")
	var skin_presets := Preview3D.skin_presets()
	var skin_keys: Array = skin_presets.keys()
	var skin_labels: Array[String] = []
	for key in skin_keys:
		skin_labels.append(String(skin_presets[key].get("label", key)))
	_setting_option(page, "音符皮肤", skin_labels, maxi(0, skin_keys.find(_app.note_skin)), func(index: int) -> void:
		_app.note_skin = String(skin_keys[index])
		_app.save_settings()
		_app.appearance_changed.emit()
		_app.notice.emit("音符皮肤：%s" % skin_labels[index], "info")
	)
	var fx_presets := Preview3D.hit_fx_presets()
	var fx_keys: Array = fx_presets.keys()
	var fx_labels: Array[String] = []
	for key in fx_keys:
		fx_labels.append(String(fx_presets[key]))
	_setting_option(page, "打击特效", fx_labels, maxi(0, fx_keys.find(_app.hit_fx_style)), func(index: int) -> void:
		_app.hit_fx_style = String(fx_keys[index])
		_app.save_settings()
		_app.appearance_changed.emit()
		_app.notice.emit("打击特效：%s" % fx_labels[index], "info")
	)
	var sfx_keys: Array[String] = ["default", "crisp", "deep", "mute"]
	var sfx_labels: Array[String] = ["原声", "清脆", "厚重", "静音"]
	_setting_option(page, "打击音效", sfx_labels, maxi(0, sfx_keys.find(_app.hit_sfx_style)), func(index: int) -> void:
		_app.hit_sfx_style = sfx_keys[index]
		_app.save_settings()
		_app.appearance_changed.emit()
		_app.preview_sfx.emit()
		_app.notice.emit("打击音效：%s" % sfx_labels[index], "info")
	)
	_label(page, "试玩中 F6 换皮肤、F7 换特效；音效只改打击音色，不改判定。", 11, UITheme.MUTED)
	_section(page, "显示")
	_setting_option(page, "Path 启动指示", App.PATH_WAIT_LABELS, maxi(0, App.PATH_WAIT_MODES.find(_app.path_wait_indicator)), func(index: int) -> void:
		_app.path_wait_indicator = App.PATH_WAIT_MODES[index]
		_app.save_settings()
		_app.appearance_changed.emit()
	)
	_label(page, "从星星落点到等待结束计时；预览和试玩共用，试玩暂停菜单也可切换。", 11, UITheme.MUTED)
	var cap_keys: Array[String] = ["60", "120", "vsync", "unlimited"]
	var cap_labels: Array[String] = ["60 FPS", "120 FPS", "跟随显示器（vsync）", "无限制"]
	_setting_option(page, "帧率上限", cap_labels, maxi(0, cap_keys.find(_app.frame_cap)), func(index: int) -> void:
		_app.frame_cap = cap_keys[index]
		_app.apply_frame_cap()
		_app.save_settings()
		_app.notice.emit("帧率上限：%s" % cap_labels[index], "info")
	)
	# Godot 只在启动时读音频缓冲；这里写 override.cfg，重启后生效。
	var buffer_values: Array[int] = [3, 10, 20]
	var buffer_labels: Array[String] = ["低延迟 3ms", "标准 10ms", "安全 20ms"]
	_setting_option(page, "音频缓冲", buffer_labels, maxi(0, buffer_values.find(int(_app.audio_buffer_ms))),
		func(index: int) -> void: _app.set_audio_buffer(buffer_values[index]))
	_label(page, "音频缓冲改动写进 override.cfg，重启游戏后生效（3ms ≈ 12ms 总延迟，爆音就换标准）。", 11, UITheme.MUTED)
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
	_section(page, "编辑")
	_check(page, "从上往下写入", _app.time_flows_down, func(value: bool) -> void:
		_app.set_time_flows_down(value)
	)
	_section(page, "视频")
	var video_path := LineEdit.new()
	video_path.text = _app.chart.video_path
	video_path.editable = false
	video_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(page, "路径", video_path)
	_buttons(page, [
		{"text": "选择视频…", "callback": func() -> void: _pick_video()},
		{"text": "移除", "callback": func() -> void: _app.mutate(func() -> void: _app.chart.video_path = "")},
	])
	_label(page, "支持 OGV / MP4 / M4V / WebM / MOV / MKV / AVI；mp4 等默认直接解码（不转码），只有缺少解码库时才转码到 user://media 缓存。", 11, UITheme.MUTED)
	_spin(page, "videoOffset ms", _app.chart.video_offset_ms, -10000.0, 10000.0, 1.0, func(value: float) -> void: _app.chart.video_offset_ms = value)
	_spin(page, "FPS 提示", _app.chart.video_fps, 1.0, 240.0, 1.0, func(value: float) -> void: _app.chart.video_fps = value)
	_spin(page, "不透明度", _app.chart.video_opacity, 0.0, 1.0, 0.01, func(value: float) -> void: _app.chart.video_opacity = value)
	_label(page, "RingState 关键帧在「视图 → 环编辑」里用滚轮/菱形调。", 11, UITheme.MUTED)


func _build_chart_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	_section(page, "曲目")
	_text(page, "标题", String(chart.metadata.get("title", "")), func(value: String) -> void: chart.metadata["title"] = value)
	_text(page, "曲师", String(chart.metadata.get("artist", "")), func(value: String) -> void: chart.metadata["artist"] = value)
	_text(page, "谱师", String(chart.metadata.get("creator", "")), func(value: String) -> void: chart.metadata["creator"] = value)
	_text(page, "难度", chart.difficulty, func(value: String) -> void: chart.difficulty = value)
	_text(page, "音频路径", chart.audio_path, func(value: String) -> void: chart.audio_path = value)
	_text(page, "视频路径", chart.video_path, func(value: String) -> void: chart.video_path = value)
	_label(page, "时间/BPM/offset 已统一移到“时间”页。", 11, UITheme.MUTED)
	_buttons(page, [
		{"text": "选择音频并识别 BPM", "callback": func() -> void: _app.request_audio_import()},
		{"text": "重新识别当前音频", "callback": func() -> void: _app.request_audio_detect()},
	])
	_buttons(page, [
		{"text": "保存谱面", "callback": func() -> void: _app.save_chart()},
	])

	_section(page, "配色分组")
	_label(page, "Tap / Hold / Path 共用一组配色；单音符还能在“音符”页覆盖成任意颜色。选“默认”即回到皮肤色。", 11, UITheme.MUTED)
	if chart.palette.is_empty():
		_label(page, "还没有配色组，点下面的按钮新建一组。", 11, UITheme.MUTED)
	for index in range(chart.palette.size()):
		var group_index := index + 1
		var group := chart.palette_group(group_index)
		_text(page, "配色 %d 名称" % group_index, String(group.get("name", "")), func(value: String) -> void:
			var target := chart.palette_group(group_index)
			if not target.is_empty():
				target["name"] = value.strip_edges()
		)
		for key in Chart.PALETTE_TYPES:
			var picker := ColorPickerButton.new()
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(56, 24)
			picker.color = Color(String(group.get(key, String(Chart.PALETTE_DEFAULTS[key]))))
			var type_key := key
			picker.color_changed.connect(func(value: Color) -> void:
				_app.mutate(func() -> void:
					var target := chart.palette_group(group_index)
					if not target.is_empty():
						target[type_key] = "#" + value.to_html(false)
				)
			)
			_row(page, type_key.capitalize(), picker)
		_label(page, "使用该组的音符：%d 个" % chart.palette_usage(group_index), 11, UITheme.MUTED)
		_buttons(page, [{"text": "删除这组", "callback": func() -> void:
			_app.mutate(func() -> void: chart.remove_palette_group(group_index))
			_rebuild()
		}])
	_buttons(page, [{"text": "新增配色组", "callback": func() -> void:
		_app.mutate(func() -> void: chart.add_palette_group())
		_rebuild()
	}])


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
	var ids: Array = []
	for note in _app.selection_with_partners():
		ids.append(note.id)
	_app.begin_edit()
	for note in _app.chart.notes.duplicate():
		if ids.has(note.id):
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
	for item in _app.with_anchor_partners([note]):
		_app.chart.notes.erase(item)
	_app.finish_edit()
	_app.clear_selection()


func _add_anchor_pair(note: Note) -> void:
	if note.type != "anchor":
		return
	if _app != null and _app.chart != null and _app.chart.anchor_partner(note) != null:
		return
	_apply(func() -> void:
		var pair_id := note.pair_id if not note.pair_id.is_empty() else "P%d" % note.id
		note.anchor_pair = 0
		note.pair_id = pair_id
		var partner := Note.new("anchor", note.beat, fposmod(note.angle + 180.0, 360.0), note.width)
		partner.id = _app.chart.next_note_id()
		partner.anchor_pair = 0
		partner.pair_id = pair_id
		_app.chart.notes.append(partner)
	)
	_rebuild()


func _duplicate_note(note: Note) -> void:
	var copies: Array[Note] = []
	for item in _app.with_anchor_partners([note]):
		var copy := Note.from_dict(item.to_dict())
		copy.id = _app.chart.next_note_id()
		copy.beat = item.beat + 1.0
		if copy.type in ["hold", "path"]:
			copy.end_beat = item.end_beat + 1.0
		copies.append(copy)
	if note.type == "anchor" and copies.size() > 1:
		var pair_id := "P%d" % copies[0].id
		for copy in copies:
			copy.pair_id = pair_id
	_app.begin_edit()
	for copy in copies:
		_app.chart.notes.append(copy)
	_app.finish_edit()
	_app.select_note(copies[0].id)


func _delete_region(region: Region) -> void:
	_app.begin_edit()
	_app.chart.regions.erase(region)
	_app.finish_edit()
	_app.clear_selection()


func open_video_picker() -> void:
	_pick_video()


func _pick_video() -> void:
	if _video_dialog != null:
		return
	if _app == null or _app.chart == null:
		if _app != null:
			_app.notice.emit("先打开或新建谱面再导入视频", "warning")
		return
	_video_dialog = FileDialog.new()
	_video_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_video_dialog.access = FileDialog.ACCESS_FILESYSTEM
	var filters := PackedStringArray()
	for extension in MediaIO.SUPPORTED_VIDEO:
		filters.append("*.%s ; %s" % [extension, String(extension).to_upper()])
	_video_dialog.filters = filters
	_video_dialog.title = "选择视频（OGV / MP4 / WebM / MOV / MKV / AVI）"
	_video_dialog.file_selected.connect(func(path: String) -> void:
		_start_video_import(path)
		_video_dialog.queue_free()
		_video_dialog = null
	)
	_video_dialog.canceled.connect(func() -> void:
		_video_dialog.queue_free()
		_video_dialog = null
	)
	add_child(_video_dialog)
	_video_dialog.popup_centered_ratio(0.6)


func _start_video_import(path: String) -> void:
	if _app == null or _app.chart == null:
		_app.notice.emit("先打开或新建谱面再导入视频", "warning")
		return
	if not MediaIO.is_supported_video(path):
		_app.notice.emit("不支持的视频格式：.%s" % path.get_extension(), "error")
		return
	# 有 gdffmpeg 就直接解码，不转码、不弹进度；只有缺解码库/格式不支持才走兜底转码。
	if ChartIO.can_decode_video_directly(path):
		_apply_video_path(path)
		_app.notice.emit("视频已导入（直接解码，不转码）", "info")
		return
	if FileAccess.file_exists(MediaIO.video_cache_path(path)):
		_apply_video_path(path)
		_app.notice.emit("视频已导入（使用已有转码缓存）", "info")
		return
	var target_chart: Chart = _app.chart
	_show_video_progress()
	var result := await MediaIO.prepare_video_async(path, get_tree(), _on_video_progress)
	_hide_video_progress()
	if result.is_empty():
		_app.notice.emit("视频导入失败：%s" % MediaIO.last_error, "error")
		return
	if _app.chart != target_chart:
		_app.notice.emit("视频已转码缓存；谱面已切换，请在目标谱面重新选择同一个视频（缓存已就绪）", "warning")
		return
	_apply_video_path(path)
	_app.notice.emit("视频已导入（没有直解库，已转码缓存）", "info")


func _apply_video_path(path: String) -> void:
	_app.mutate(func() -> void:
		_app.chart.video_path = path
	)


func _show_video_progress() -> void:
	if _video_progress == null:
		_video_progress = AcceptDialog.new()
		_video_progress.title = "导入视频"
		_video_progress.min_size = Vector2i(460, 150)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		_video_progress.add_child(box)
		_video_progress_label = Label.new()
		_video_progress_label.text = "没有直解库，正在转码视频…"
		box.add_child(_video_progress_label)
		_video_progress_bar = ProgressBar.new()
		_video_progress_bar.max_value = 100.0
		_video_progress_bar.show_percentage = true
		_video_progress_bar.custom_minimum_size = Vector2(420, 24)
		box.add_child(_video_progress_bar)
		add_child(_video_progress)
		var ok := _video_progress.get_ok_button()
		if ok != null:
			ok.visible = false
	_video_progress_bar.value = 0.0
	_video_progress_label.text = "没有直解库，正在转码视频…"
	_video_progress.popup_centered(Vector2i(500, 170))


func _hide_video_progress() -> void:
	if _video_progress != null:
		_video_progress.hide()


func _on_video_progress(ratio: float, seconds: float) -> void:
	if _video_progress_bar == null or _video_progress_label == null:
		return
	if ratio >= 0.0:
		_video_progress_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
		_video_progress_label.text = "没有直解库，正在转码… %d%%（已转 %.0f 秒）" % [roundi(ratio * 100.0), seconds]
	else:
		_video_progress_bar.value = fmod(float(Time.get_ticks_msec()) * 0.05, 100.0)
		_video_progress_label.text = "没有直解库，正在转码… 已转 %.0f 秒" % seconds
