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
## 每个标签页上次构建时的「结构签名」。中文 Label 进树要重新量最小尺寸（实测单个
## 标签 ~17ms），整页重建 0.2–2.3 秒；结构没变时直接复用已建好的页。
var _page_keys: Dictionary = {}
## 音符页的两种形态各建一次、之后只切可见性：中文 Label 进树要重新量尺寸，
## 每次多选/单选来回都重建会卡 1.5 秒。
var _note_single_host: VBoxContainer = null
var _note_multi_host: VBoxContainer = null
var _note_multi_count: Label = null
var _note_multi_types: Label = null
var _video_dialog: FileDialog
var _video_progress: AcceptDialog
var _video_progress_bar: ProgressBar
var _video_progress_label: Label
var _selected_timing: int = 0
var _selected_visual: int = 0
var _note_page_ready: bool = false
var _active_note: Note = null
var _note_groups: Dictionary = {}
var _note_rows: Dictionary = {}
var _note_widgets: Dictionary = {}
var _note_empty_label: Label = null
var _timing_base_spin: SpinBox
var _timing_list: ItemList
var _timing_chart: Chart
var _offset_spin: SpinBox
var _offset_strip: Control
var _offset_peaks: PackedFloat32Array = PackedFloat32Array()
var _offset_peaks_path: String = ""


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	set_process_input(true)
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
	for title in ["音符", "区域", "视图", "时间", "组", "谱面"]:
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
		page.set_meta("scroll", scroll)
		_page_list.append(page)


## 检查器里滚轮一律翻页（向上 = 页面上移），数字框/滑条/下拉不再把它吞掉。
static func wheel_delta(up: bool, step: float = 48.0) -> float:
	return -step if up else step


## 检查器里的滚轮只翻页：数字框/滑条/下拉不会再把它吞掉或偷偷改值。
## 在 _input（早于 GUI 分发）里处理，才抢得到这些控件自己的滚轮。
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var button := (event as InputEventMouseButton).button_index
	if button != MOUSE_BUTTON_WHEEL_UP and button != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not get_global_rect().has_point((event as InputEventMouseButton).position):
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or not is_ancestor_of(hovered):
		return
	# 这两个自己就要滚（BPM 点列表、可编辑文本），别抢。
	if hovered is ItemList or hovered is TextEdit or hovered is Tree:
		return
	var page: VBoxContainer = _page_list[clampi(current_tab, 0, _page_list.size() - 1)]
	var scroll: ScrollContainer = page.get_meta("scroll", null)
	if scroll == null:
		return
	scroll.scroll_vertical = int(float(scroll.scroll_vertical) + wheel_delta(button == MOUSE_BUTTON_WHEEL_UP))
	get_viewport().set_input_as_handled()


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
	if current_tab == 0:
		_rebuild_note_tab()
		refresh_tab_titles()
		_rebuilding = false
		return
	var current_page: VBoxContainer = _page_list[clampi(current_tab, 0, _page_list.size() - 1)]
	if _page_keys.get(current_tab, "") == _page_key(current_tab) and current_page.get_child_count() > 0:
		refresh_tab_titles()
		_rebuilding = false
		return
	for child in current_page.get_children():
		child.queue_free()
	# 先建在脱离场景树的容器里，最后一次性挂上去：否则每 add_child 都会重排整页，
	# 控件一多就是 O(n²)（实测 1.6 秒）。
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 8)
	match current_tab:
		1:
			_build_region_page(host)
		2:
			_build_view_page(host)
		3:
			_build_timing_page(host)
		4:
			_build_group_page(host)
		5:
			_build_chart_page(host)
	current_page.add_child(host)
	if current_tab != 0:
		_page_keys[current_tab] = _page_key(current_tab)
	refresh_tab_titles()
	_rebuilding = false


## Anchor 的伙伴：只比 pair_id + 同拍，不要求 180°（可用来做整对同步）。
func _anchor_partner(note: Note) -> Note:
	if note == null or note.type != "anchor" or _app == null or _app.chart == null:
		return null
	return _app.chart.anchor_partner(note)


## 音符页：单选/多选/空选三种形态各自复用，绝不在选择变化时重建整页。
func _rebuild_note_tab() -> void:
	var selected: int = _app.selected_notes.size()
	if selected == 0:
		_show_note_mode("empty")
		return
	if selected > 1:
		if _note_multi_host == null:
			_note_multi_host = _new_page_host()
			_build_multi_page(_note_multi_host)
			_pages["音符"].add_child(_note_multi_host)
		_update_multi_labels()
		_show_note_mode("multi")
		return
	if _app.get_selected_note() == null:
		_show_note_mode("empty")
		return
	if _note_single_host == null:
		_note_single_host = _new_page_host()
		_build_note_page_for(_note_single_host, _app.get_selected_note())
		_pages["音符"].add_child(_note_single_host)
		_note_page_ready = true
	_show_note_mode("single")
	_refresh_note_page()


func _new_page_host() -> VBoxContainer:
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 8)
	return host


func _show_note_mode(mode: String) -> void:
	_prepare_note_empty_label(_pages["音符"])
	_note_empty_label.visible = mode == "empty"
	if _note_single_host != null:
		_note_single_host.visible = mode == "single"
	if _note_multi_host != null:
		_note_multi_host.visible = mode == "multi"


## 页面结构只在这些东西变化时需要重建；数值变化由刷新/控件自身处理。
func _page_key(tab: int) -> String:
	if _app == null or _app.chart == null:
		return ""
	var chart_id := str(_app.chart.get_instance_id())
	match tab:
		2:
			# 视图页全是编辑器设置，和谱面对象无关；建一次就复用。
			return "view"
		1:
			return "%s|region:%d" % [chart_id, _app.selected_region_id]
		3:
			return "%s|timing:%d" % [chart_id, _app.chart.timing.points.size()]
		4:
			return "%s|palette:%d|shapes:%d|groups:%d|notes:%d|group:%d" % [
				chart_id, _app.chart.palette.size(), _app.chart.shapes.size(),
				_app.chart.groups.size(), _app.chart.notes.size(), _app.chart.current_group]
	return chart_id


func refresh_tab_titles() -> void:
	if _app == null:
		return
	var note_count: int = _app.selected_notes.size()
	# 环相关编辑都在「环编辑」工作区；这里保留音符/区域/视图/时间/谱面。
	set_tab_title(0, "音符")
	set_tab_title(1, "区域" if _app.selected_region_id < 0 else "区域 %d" % _app.selected_region_id)
	set_tab_title(2, "视图")
	set_tab_title(3, "时间")
	set_tab_title(4, "组")
	set_tab_title(5, "谱面")
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


## 多选页只建一次：数量/类型写在两个常驻 Label 里，之后只改文字。
func _build_multi_page(page: VBoxContainer) -> void:
	_section(page, "多选")
	_note_multi_count = _label(page, "", 12, UITheme.INK)
	_note_multi_types = _label(page, "", 12, UITheme.MUTED)
	_label(page, "快捷键：批量复制 Ctrl+C ｜ 批量粘贴 Ctrl+V ｜ 批量镜像粘贴 Ctrl+A", 11, UITheme.CYAN)
	_buttons(page, [
		{"text": "删除选中", "callback": _delete_selected},
		{"text": "解锁", "callback": _unlock_selected},
	])
	_update_multi_labels()


func _update_multi_labels() -> void:
	if _note_multi_count == null or not is_instance_valid(_note_multi_count):
		return
	_note_multi_count.text = "已选中 %d 个音符。拖动可整体移动；数值混合时不显示单一值。" % _app.selected_notes.size()
	var types := {}
	for item in _app.get_selected_notes():
		types[item.type] = true
	_note_multi_types.text = "类型：%s" % ",".join(types.keys())


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
	var group_names: Array[String] = []
	var group_selected := 0
	for group in _app.chart.groups:
		group_names.append("组 %d" % int(group.get("id", 0)))
		if int(group.get("id", 0)) == note.group_id:
			group_selected = group_names.size() - 1
	var group_option := _option(common, "所属组", group_names, group_selected, func(index: int) -> void:
		if _active_note == null or index < 0 or index >= _app.chart.groups.size():
			return
		_app.begin_edit()
		_active_note.group_id = int(_app.chart.groups[index].get("id", 0))
		_app.finish_edit())
	group_option.get_popup().max_size = Vector2i(260, 120)
	_note_widgets["group"] = group_option
	var note_state := CheckBox.new()
	note_state.text = "音符状态 True"
	note_state.button_pressed = note.enabled
	note_state.toggled.connect(func(value: bool) -> void:
		if _active_note == null:
			return
		_app.begin_edit()
		_active_note.enabled = value
		note_state.text = "音符状态 True" if value else "音符状态 False"
		_app.finish_edit())
	common.add_child(note_state)
	_note_widgets["enabled"] = note_state
	var start_edit := _beat(common, "开始拍", note.beat, func(value: float) -> void:
		var n := _active_note
		if n == null:
			return
		var delta := value - n.beat
		n.beat = value
		if n.type in ["hold", "path"]:
			n.end_beat = maxf(n.beat + 0.25, n.end_beat + delta)
		# Anchor 整对同拍：只改一颗会让 anchor_partner 找不到伙伴，配对直接断。
		var partner := _anchor_partner(n)
		if partner != null:
			partner.beat = value
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
		var target := fposmod(value, 360.0)
		var delta := JudgeMath.angle_delta(n.angle, target)
		n.angle = target
		if n.type == "bell":
			n.center_u = fposmod(n.angle / 360.0, 1.0)
		elif n.type == "path":
			n.generate_path_shape()
			_sync_path_chain(n)
		# Anchor 整对转：伙伴走同样的角度增量，夹角不变。
		var partner := _anchor_partner(n)
		if partner != null:
			partner.angle = fposmod(partner.angle + delta, 360.0)
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
	var seek_w := _spin(seek_body, "弧宽 °", note.seek_width(), Note.SEEK_MIN_WIDTH, 360.0, 1.0,
		func(value: float) -> void:
			if _active_note != null:
				_active_note.width = clampf(value, Note.SEEK_MIN_WIDTH, 360.0)
	)
	_note_widgets["seek_w"] = seek_w
	var seek_a := _spin(seek_body, "中心角 °", fposmod(note.angle, 360.0), 0.0, 360.0, 1.0,
		func(value: float) -> void:
			if _active_note != null:
				_active_note.angle = fposmod(value, 360.0)
	)
	_note_widgets["seek_a"] = seek_a
	_label(seek_body, "外 = 滚轮上滑；里 = 滚轮下滑。360° = 整圈，任意位置滚动即可；小于 360° 时滚轮那一刻光标必须站在这段弧上（±55px），环上会收一圈就位环。", 11, UITheme.MUTED)

	var mods_body := _note_group(page, "mods", "演出修饰")
	var hs_spin := _spin(mods_body, "下落速度 HS", note.hs, 0.2, 4.0, 0.05, func(value: float) -> void:
		if _active_note != null:
			_active_note.hs = clampf(value, 0.2, 4.0)
	)
	hs_spin.tooltip_text = "音符自身下落速度倍率；与原版一致，只在音符出生瞬间取一次。"
	_note_widgets["mod_hs"] = hs_spin
	_remember_row("mod_hs", hs_spin)
	hs_spin.get_parent().visible = false
	var sv_spin := _spin(mods_body, "时间流速 SV", note.sv, 0.25, 4.0, 0.05, func(value: float) -> void:
		if _active_note != null:
			_active_note.sv = clampf(value, 0.25, 4.0)
	)
	sv_spin.tooltip_text = "时间轴滚动倍率，影响音符与边界靠近判定环的速度。"
	_note_widgets["mod_sv"] = sv_spin
	_remember_row("mod_sv", sv_spin)
	sv_spin.get_parent().visible = false
	var head_spin := _spin(mods_body, "滑条头部速度", note.head_speed, 0.25, 4.0, 0.05, func(value: float) -> void:
		if _active_note != null:
			_active_note.head_speed = clampf(value, 0.25, 4.0)
	)
	head_spin.tooltip_text = "只作用于 Hold / Path 的头部（星星）落速；身体与尾巴仍按 SV 走。"
	_note_widgets["mod_head"] = head_spin
	_remember_row("mod_head", head_spin)
	var spawn_ctl := _spin_slider(mods_body, "出生半径 spawn", note.spawn, 0.0, 1.0, 0.01, func(value: float) -> void:
		if _active_note != null:
			_active_note.spawn = clampf(value, 0.0, 1.0)
	, true)
	_note_widgets["mod_spawn"] = spawn_ctl["spin"]
	_note_widgets["mod_spawn_slider"] = spawn_ctl["slider"]
	_remember_row("mod_spawn", spawn_ctl["spin"])
	var bounce_ctl := _spin_slider(mods_body, "弹跳幅度 bounce", note.bounce, 0.0, 2.0, 0.01, func(value: float) -> void:
		if _active_note != null:
			_active_note.bounce = clampf(value, 0.0, 2.0)
	, true)
	_note_widgets["mod_bounce"] = bounce_ctl["spin"]
	_note_widgets["mod_bounce_slider"] = bounce_ctl["slider"]
	_remember_row("mod_bounce", bounce_ctl["spin"])
	var bounce_dir := _option(mods_body, "弹跳方向", ["内凹", "外凸"], note.bounce_dir, func(index: int) -> void:
		if _active_note != null:
			_active_note.bounce_dir = 1 if index == 1 else 0
	)
	_note_widgets["mod_bounce_dir"] = bounce_dir
	_remember_row("mod_bounce_dir", bounce_dir)
	_buttons(mods_body, [{"text": "复位修饰", "callback": func() -> void:
		if _active_note == null:
			return
		var n := _active_note
		_apply(func() -> void:
			n.hs = 1.0
			n.sv = 1.0
			n.head_speed = 1.0
			n.spawn = 0.0
			n.bounce = 0.0
			n.bounce_dir = 0
			# 旧谱可能还带触摸区字段；虽然不再显示，复位时一并清掉。
			n.touch_start = ""
			n.touch_end = ""
		)
		_refresh_note_page()
	}])
	_label(mods_body, "HS/SV/spawn/bounce 是单音符修饰；判定线、文本与滤镜在「环编辑」工作区的时间轴编辑。", 11, UITheme.MUTED)

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


func _prebuild_note_page() -> void:
	# 启动时一次性构建静态页，之后选择音符只刷新数值，不再创建中文控件。
	# 和 _rebuild 一样先建在脱离场景树的容器里，避免每个 add_child 都重排整页。
	var page: VBoxContainer = _pages["音符"]
	for child in page.get_children():
		child.queue_free()
	var host := _new_page_host()
	var dummy := Note.new("tap", 0.0, 0.0, 60.0)
	dummy.id = -1
	_build_note_page_for(host, dummy)
	page.add_child(host)
	_note_single_host = host
	_note_page_ready = true
	_active_note = null
	_show_note_mode("empty")


func _refresh_note_page() -> void:
	var note: Note = _app.get_selected_note()
	if note == null or not _note_page_ready:
		return
	_active_note = note
	_app.chart.ensure_groups()
	if _note_empty_label != null and is_instance_valid(_note_empty_label):
		_note_empty_label.visible = false
	_applying = true
	_note_widgets["type"].text = note.type
	_note_widgets["id"].text = str(note.local_id if note.local_id > 0 else note.id)
	var group_option: OptionButton = _note_widgets["group"]
	group_option.clear()
	var selected_group := 0
	for i in _app.chart.groups.size():
		var gid := int(_app.chart.groups[i].get("id", 0))
		group_option.add_item("组 %d" % gid)
		if gid == note.group_id:
			selected_group = i
	group_option.selected = clampi(selected_group, 0, maxi(0, group_option.item_count - 1))
	_note_widgets["enabled"].button_pressed = note.enabled
	_note_widgets["enabled"].text = "音符状态 True" if note.enabled else "音符状态 False"
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
	var color_option: OptionButton = _note_widgets["color_group"]
	color_option.clear()
	color_option.add_item("默认")
	for index in range(_app.chart.palette.size()):
		color_option.add_item(_app.chart.palette_name(index + 1))
	color_option.selected = clampi(note.color, 0, maxi(0, color_option.item_count - 1))
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
	_note_groups["mods"].visible = true
	_note_widgets["mod_hs"].value = note.hs
	_note_widgets["mod_sv"].value = note.sv
	_note_widgets["mod_head"].value = note.head_speed
	_note_widgets["mod_spawn"].value = note.spawn
	_note_widgets["mod_spawn_slider"].value = note.spawn
	_note_widgets["mod_bounce"].value = note.bounce
	_note_widgets["mod_bounce_slider"].value = note.bounce
	_note_widgets["mod_bounce_dir"].selected = 1 if note.bounce_dir == 1 else 0
	_note_rows["mod_head"].visible = note.type in ["hold", "path"]
	_note_widgets["mod_bounce_dir"].get_parent().visible = note.bounce > 0.0001
	_note_widgets["seek_w"].value = note.seek_width()
	_note_widgets["seek_a"].value = fposmod(note.angle, 360.0)
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
	var width_spin := _spin(page, "逻辑宽度", region.width, 0.0, 360.0, 1.0, func(value: float) -> void: region.width = value)
	width_spin.get_parent().visible = true
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
	_check(page, "正对镜头（忽略倾斜）", bool(_app.chart.metadata.get("face_camera", true)), func(value: bool) -> void:
		_app.mutate(func() -> void: _app.chart.metadata["face_camera"] = value)
	)
	_check(page, "HUD（H）", _app.hud_visible, func(value: bool) -> void: _app.hud_visible = value)
	_check(page, "调试叠层", _app.debug_overlay, func(value: bool) -> void: _app.debug_overlay = value)
	_check(page, "3D 环网格（GPU）", _app.use_3d_ring, func(value: bool) -> void:
		_app.use_3d_ring = value
		_app.status_changed.emit()
	)
	_check(page, "鼠标倾斜", _app.mouse_tilt, func(value: bool) -> void:
		_app.mouse_tilt = value
		_app.status_changed.emit()
	)
	_section(page, "编辑")
	_check(page, "谱面从上往下", _app.time_flows_down, func(value: bool) -> void:
		_app.set_time_flows_down(value)
	)
	_label(page, "只影响显示方向：关闭后时间从下往上走（播放头在下方时音符从上方落下）。切换时播放头所在的屏幕位置保持不变。", 11, UITheme.MUTED)
	var scroll_keys: Array[String] = ["page", "pin"]
	var scroll_labels: Array[String] = ["翻页", "固定播放头"]
	_setting_option(page, "播放滚动", scroll_labels, maxi(0, scroll_keys.find(String(_app.playback_scroll))), func(index: int) -> void:
		_app.playback_scroll = scroll_keys[index]
		_app.save_settings()
		_app.status_changed.emit()
		_app.notice.emit("播放滚动：%s" % scroll_labels[index], "info")
	)
	_label(page, "固定播放头只在播放和拖进度条时生效：播放头停在流动方向的边缘 8%，谱面连续滚动；滚轮可临时脱离，1.2 秒后自动拉回。", 11, UITheme.MUTED)
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
	_spin(page, "不透明度", _app.chart.video_opacity, 0.0, 1.0, 0.01, func(value: float) -> void: _app.chart.video_opacity = value)
	_label(page, "RingState 关键帧在「视图 → 环编辑」里用滚轮/菱形调。", 11, UITheme.MUTED)


func _build_group_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	chart.ensure_groups()
	_section(page, "组")
	_label(page, "当前组：组 %d。编辑区只允许编辑当前组；其他组以 25% 标记显示。" % chart.current_group, 12, UITheme.MUTED)
	for group in chart.groups:
		var gid := int(group.get("id", 0))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		page.add_child(box)
		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", 6)
		var heading := Button.new()
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.text = "%s组 %d  ·  %d 音符%s" % ["▶ " if gid == chart.current_group else "", gid,
			chart.group_note_count(gid), "" if bool(group.get("enabled", true)) else "  [False]"]
		heading.pressed.connect(func() -> void:
			chart.current_group = gid
			_app.clear_selection()
			_app.chart_changed.emit()
		)
		head_row.add_child(heading)
		var remove_button := Button.new()
		remove_button.text = "－"
		remove_button.tooltip_text = "删除组 %d 及其全部音符" % gid
		remove_button.custom_minimum_size = Vector2(32, 0)
		remove_button.pressed.connect(_remove_group.bind(gid))
		head_row.add_child(remove_button)
		box.add_child(head_row)
		var bpm_spin := _spin(box, "基准 BPM", float(group.get("bpm", chart.timing.bpm_at(0.0))), 20.0, 1000.0, 0.001,
			func(value: float) -> void:
				_app.begin_edit()
				group["bpm"] = value
				var pts: Array[TimingPoint] = chart.group_bpm_points_for(gid)
				if not pts.is_empty():
					pts[0].bpm = value
					chart.group_bpm_points[gid] = pts
				_app.finish_edit())
		bpm_spin.editable = gid == chart.current_group
		var alpha_spin := _spin(box, "组透明度", float(group.get("alpha", 255)), 0.0, 255.0, 1.0,
			func(value: float) -> void:
				_app.begin_edit()
				group["alpha"] = clampi(int(value), 0, 255)
				_app.finish_edit())
		alpha_spin.editable = gid == chart.current_group
		var state := CheckBox.new()
		state.text = "音符状态 True"
		state.button_pressed = bool(group.get("enabled", true))
		state.disabled = gid != chart.current_group
		state.toggled.connect(func(value: bool) -> void:
			_app.begin_edit()
			group["enabled"] = value
			state.text = "音符状态 True" if value else "音符状态 False"
			_app.finish_edit())
		box.add_child(state)
		var spacer := HSeparator.new()
		page.add_child(spacer)
	_buttons(page, [{
		"text": "新建组",
		"callback": func() -> void:
			_app.begin_edit()
			var gid := chart.add_group()
			chart.current_group = gid
			_app.finish_edit()
			_app.clear_selection()
	}])


func _remove_group(group_id: int) -> void:
	if _app == null or _app.chart == null:
		return
	if _app.chart.groups.size() <= 1:
		_app.notice.emit("至少要保留一个组。", "warning")
		return
	_app.begin_edit()
	_app.chart.remove_group(group_id)
	_app.finish_edit()
	_app.clear_selection()


func _build_chart_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	_section(page, "曲目")
	_text(page, "标题", String(chart.metadata.get("title", "")), func(value: String) -> void: chart.metadata["title"] = value)
	_text(page, "曲师", String(chart.metadata.get("artist", "")), func(value: String) -> void: chart.metadata["artist"] = value)
	_text(page, "谱师", String(chart.metadata.get("creator", "")), func(value: String) -> void: chart.metadata["creator"] = value)
	_text(page, "难度", chart.difficulty, func(value: String) -> void: chart.difficulty = value)
	_text(page, "音频路径", chart.audio_path, func(value: String) -> void: chart.audio_path = value)
	_text(page, "视频路径", chart.video_path, func(value: String) -> void: chart.video_path = value)
	_text(page, "曲绘 / 背景图", String(chart.metadata.get("background", "")), func(value: String) -> void:
		chart.metadata["background"] = value.strip_edges()
	)
	_buttons(page, [{"text": "选择曲绘图片…", "callback": _pick_cover}])
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


## 选一张图当曲绘：复制到 user://covers/ 再写进 metadata.background，
## 这样换机器 / 打包时路径仍然有效（外部绝对路径会被打包进谱面包）。
func _pick_cover() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"])
	dialog.title = "选择曲绘 / 背景图"
	dialog.file_selected.connect(func(path: String) -> void:
		var name := path.get_file().validate_filename()
		var target := "user://covers/%s" % name
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://covers"))
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
		_app.mutate(func() -> void:
			var chart: Chart = _app.chart
			if chart != null:
				chart.metadata["background"] = target
		)
		_rebuild()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.file_selected.connect(func(_path: String) -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.55)


## 列表里的位置写成「小节:拍:分音」；format_beat 已经是 1 起的小节号。
func _timing_pos_text(chart: Chart, beat: float) -> String:
	return chart.timing.format_beat(beat)


func _timing_row_text(chart: Chart, index: int, point: TimingPoint) -> String:
	var prefix := "● " if index == 0 else "  "
	return "%s%-9s %7.1f  %d/4" % [prefix, _timing_pos_text(chart, point.beat), point.bpm, point.beats_per_bar]


func _build_timing_page(page: VBoxContainer) -> void:
	var chart: Chart = _app.chart
	chart.ensure_groups()
	var current_group_data: Dictionary = chart.group_data(chart.current_group)
	_section(page, "当前组 BPM")
	_label(page, ("组 0 是默认组，下落速度固定 1 秒；组 BPM 差速只对组 1 起生效。" if chart.current_group == 0
		else "组 %d 的基准 BPM。切换组时这里和音符速度会一起切换。" % chart.current_group), 11, UITheme.MUTED)
	_spin(page, "当前组 BPM", float(current_group_data.get("bpm", chart.timing.bpm_at(0.0))), 20.0, 600.0, 0.001,
		func(value: float) -> void:
			_app.begin_edit()
			current_group_data["bpm"] = value
			var pts: Array[TimingPoint] = chart.group_bpm_points_for(chart.current_group)
			if not pts.is_empty():
				pts[0].bpm = value
				chart.group_bpm_points[chart.current_group] = pts
			_app.finish_edit())
	_section(page, "速度与偏移")
	_label(page, "BPM 点按拍定位；offset = 第 0 拍对应的音频时刻（正数 = 音频整体延后）。", 11, UITheme.MUTED)
	var points: Array[TimingPoint] = chart.group_bpm_points_for(chart.current_group)
	if points.is_empty():
		_label(page, "没有 BPM 点，先添加一个。", 12, UITheme.RED)
		_buttons(page, [{"text": "在播放头添加 BPM", "callback": func() -> void: _add_timing_point()}])
		return
	_timing_chart = chart
	var base: TimingPoint = points[0]
	_timing_base_spin = _spin(page, "组基准 BPM", base.bpm, 0.01, 600.0, 0.01, func(value: float) -> void:
		var first: TimingPoint = points[0]
		first.bpm = value
		var group: Dictionary = chart.group_data(chart.current_group)
		group["bpm"] = value
		chart.group_bpm_points[chart.current_group] = points
		_refresh_timing_list_text()
	)
	_buttons(page, [
		{"text": "×2", "callback": func() -> void: _scale_timing_bpm(points[0], 2.0)},
		{"text": "÷2", "callback": func() -> void: _scale_timing_bpm(points[0], 0.5)},
	])
	_offset_spin = _spin(page, "音频 offset (ms)", chart.offset_ms, -10000.0, 10000.0, 1.0, func(value: float) -> void:
		_set_offset(value)
	)
	_offset_spin.tooltip_text = "正数：音频整体延后。改动只移动音频与拍线的对齐，不移动音符。"
	_build_offset_strip(page, chart)
	var lock := CheckButton.new()
	lock.text = "改 BPM 时保持后续内容的毫秒位置"
	lock.button_pressed = bool(_app.bpm_lock_ms)
	lock.tooltip_text = "开：换 BPM 后，后面的音符/事件仍落在原来的毫秒时刻（拍位会重新换算）。\n关：保持拍位不变，只有时间换算跟着变。"
	lock.toggled.connect(func(on: bool) -> void:
		_app.bpm_lock_ms = on
		_app.save_settings()
	)
	page.add_child(lock)
	if base.beat > 0.0001:
		_label(page, "第 1 个 BPM 点在第 1 小节之后：它之前的拍会用默认 120 BPM，请把第 1 个点放到 1:0:4 或更前。", 11, UITheme.RED)

	_section(page, "BPM 点")
	var header := Label.new()
	header.text = "  位置        BPM    拍号"
	header.add_theme_font_override("font", UITheme.mono_font())
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", UITheme.MUTED)
	page.add_child(header)
	var list := ItemList.new()
	_timing_list = list
	list.custom_minimum_size = Vector2(0, 132)
	list.add_theme_font_override("font", UITheme.mono_font())
	list.add_theme_font_size_override("font_size", 11)
	for i in points.size():
		list.add_item(_timing_row_text(chart, i, points[i]))
	_selected_timing = clampi(_selected_timing, 0, maxi(0, points.size() - 1))
	if _selected_timing < list.item_count:
		list.select(_selected_timing)
	var refresh_list := func() -> void:
		for i in points.size():
			if i >= list.item_count:
				break
			list.set_item_text(i, _timing_row_text(chart, i, points[i]))
	list.item_selected.connect(func(index: int) -> void:
		_selected_timing = index
		_rebuild()
	)
	list.item_activated.connect(func(index: int) -> void:
		if index >= 0 and index < points.size():
			_app.set_playhead(points[index].beat)
	)
	page.add_child(list)
	var sync_points := func() -> void:
		chart.group_bpm_points[chart.current_group] = points
	_buttons(page, [
		{"text": "在播放头添加", "callback": func() -> void: _add_timing_point()},
		{"text": "删除选中", "callback": func() -> void: _delete_timing_point()},
	])
	if _selected_timing >= 0 and _selected_timing < points.size():
		var point: TimingPoint = points[_selected_timing]
		var refresh_item := func() -> void:
			refresh_list.call()
		_beat(page, "生效位置（拍）", point.beat, func(value: float) -> void:
			point.beat = value
			points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
			sync_points.call()
			refresh_item.call()
		)
		var point_max := maxf(0.01, base.bpm * 10.0)
		_spin(page, "BPM", point.bpm, 0.01, point_max, 0.01, func(value: float) -> void:
			_apply_timing_bpm(point, value)
			refresh_item.call()
		)
		_buttons(page, [
			{"text": "BPM ×2", "callback": func() -> void: _scale_timing_bpm(point, 2.0)},
			{"text": "BPM ÷2", "callback": func() -> void: _scale_timing_bpm(point, 0.5)},
		])
		_spin(page, "每小节拍数 (x/4)", point.beats_per_bar, 1.0, 16.0, 1.0, func(value: float) -> void:
			point.beats_per_bar = int(value)
			points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
			sync_points.call()
			refresh_item.call()
		)
		_buttons(page, [
			{"text": "生效位置 = 播放头", "callback": func() -> void: _set_timing_beat(point)},
			{"text": "定位到该点", "callback": func() -> void: _app.set_playhead(point.beat)},
		])
	else:
		_label(page, "点一行 BPM 点来编辑位置、BPM、拍号。", 11, UITheme.MUTED)
	_label(page, "列表按拍排序；双击一行跳到该点。逐点改 BPM 不会移动已放置的音符（音符存的是拍位）。", 11, UITheme.MUTED)


func _set_offset(value: float) -> void:
	if _app == null or _app.chart == null:
		return
	_app.chart.offset_ms = value
	_app.chart.timing.offset_ms = value
	_app.touch_chart()
	if _offset_spin != null and not is_equal_approx(_offset_spin.value, value):
		_offset_spin.set_value_no_signal(value)
	_offset_redraw()


## 时间页里的迷你波形：拖它 = 改 offset（波形跟着鼠标走，拍线不动）。
func _build_offset_strip(page: VBoxContainer, chart: Chart) -> void:
	if chart.audio_path.is_empty():
		return
	if _offset_peaks.is_empty() or _offset_peaks_path != chart.audio_path:
		_offset_peaks = _offset_peaks_for(chart.audio_path)
		_offset_peaks_path = chart.audio_path
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(0, 64)
	strip.clip_contents = true
	strip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	strip.tooltip_text = "左右拖动波形：波形跟着鼠标走，拍线不动（等于改 offset）"
	strip.set_meta("dragging", false)
	strip.set_meta("start_x", 0.0)
	strip.set_meta("start_offset", 0.0)
	strip.draw.connect(func() -> void: _draw_offset_strip(strip, chart))
	strip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			strip.set_meta("dragging", event.pressed)
			if event.pressed:
				strip.set_meta("start_x", event.position.x)
				strip.set_meta("start_offset", chart.offset_ms)
			strip.accept_event()
		elif event is InputEventMouseMotion and bool(strip.get_meta("dragging")):
			var width := maxf(40.0, strip.size.x)
			var ms_per_px := OFFSET_STRIP_SEC * 1000.0 / width
			var dx: float = event.position.x - float(strip.get_meta("start_x"))
			_set_offset(clampf(float(strip.get_meta("start_offset")) - dx * ms_per_px, -10000.0, 10000.0))
			strip.accept_event()
	)
	page.add_child(strip)
	_offset_strip = strip


const OFFSET_STRIP_SEC := 20.0


func _offset_redraw() -> void:
	if _offset_strip != null:
		_offset_strip.queue_redraw()


## 波形峰值（0..1），按 OFFSET_STRIP_SEC 秒窗口取；解码走 AudioPCM 的缓存。
func _offset_peaks_for(path: String) -> PackedFloat32Array:
	var samples := AudioPCM.load_mono(path)
	if samples.is_empty():
		return PackedFloat32Array()
	var rate := float(AudioPCM.DEFAULT_RATE)
	var limit := mini(samples.size(), int(rate * OFFSET_STRIP_SEC))
	var bins := 320
	var step := maxi(1, limit / bins)
	var out := PackedFloat32Array()
	for i in range(0, limit, step):
		var peak := 0.0
		for j in range(i, mini(limit, i + step)):
			peak = maxf(peak, absf(samples[j]))
		out.append(peak)
	return out


func _draw_offset_strip(strip: Control, chart: Chart) -> void:
	var bounds := strip.size
	if bounds.x < 8.0 or bounds.y < 8.0:
		return
	strip.draw_rect(Rect2(Vector2.ZERO, bounds), Color(0.05, 0.06, 0.08, 0.9))
	var mid := bounds.y * 0.5
	var width := bounds.x
	var ms_per_px := OFFSET_STRIP_SEC * 1000.0 / width
	var px_per_ms := 1.0 / ms_per_px
	var offset := chart.offset_ms
	var zero_x := width * 0.4
	strip.draw_line(Vector2(zero_x, 0.0), Vector2(zero_x, bounds.y), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.85), 2.0)
	if not _offset_peaks.is_empty():
		var bins := _offset_peaks.size()
		var ms_per_bin := OFFSET_STRIP_SEC * 1000.0 / float(bins)
		for i in bins:
			var audio_ms := float(i) * ms_per_bin
			var x := zero_x + (audio_ms - offset) * px_per_ms
			if x < 0.0 or x > width:
				continue
			var amp := _offset_peaks[i] * bounds.y * 0.42
			strip.draw_line(Vector2(x, mid - amp), Vector2(x, mid + amp), Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.55), 1.0)
	strip.draw_string(UITheme.mono_font(), Vector2(6.0, bounds.y - 6.0), "offset %+.0f ms" % offset, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.MUTED)


## 改当前组某一拍上的 BPM；“保持毫秒位置”开着时，后面的内容按新旧 BPM 比例重排拍位。
func _apply_timing_bpm(point: TimingPoint, value: float) -> void:
	var chart: Chart = _app.chart
	var base_bpm := float(chart.group_data(chart.current_group).get("bpm", 120.0))
	var target := clampf(value, 0.01, maxf(0.01, base_bpm * 10.0))
	_apply(func() -> void:
		var old := point.bpm
		point.bpm = target
		if _app.bpm_lock_ms and old > 0.0 and not is_equal_approx(old, target):
			chart.scale_beats_after(point.beat, target / old)
		var points: Array[TimingPoint] = chart.group_bpm_points_for(chart.current_group)
		points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
		if not points.is_empty() and points[0] == point:
			chart.group_data(chart.current_group)["bpm"] = target
		chart.group_bpm_points[chart.current_group] = points
	)
	_refresh_timing_list_text()


func _scale_timing_bpm(point: TimingPoint, factor: float) -> void:
	_apply_timing_bpm(point, point.bpm * factor)


func _set_timing_beat(point: TimingPoint) -> void:
	var points: Array[TimingPoint] = _app.chart.group_bpm_points_for(_app.chart.current_group)
	_apply(func() -> void:
		point.beat = _app.snap_beat(_app.playhead_beat)
		points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
		_app.chart.group_bpm_points[_app.chart.current_group] = points
	)
	for i in points.size():
		if points[i] == point:
			_selected_timing = i
			break
	_rebuild()


func _add_timing_point() -> void:
	var chart: Chart = _app.chart
	var beat: float = _app.snap_beat(_app.playhead_beat)
	var points: Array[TimingPoint] = chart.group_bpm_points_for(chart.current_group)
	var bpm: float = chart.group_bpm_at(chart.current_group, beat)
	var bpb := chart.timing.beats_per_bar_at(beat)
	_app.begin_edit()
	var point := TimingPoint.new(beat, bpm, bpb)
	points.append(point)
	points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
	chart.group_bpm_points[chart.current_group] = points
	_app.finish_edit()
	_selected_timing = 0
	for i in points.size():
		if points[i] == point:
			_selected_timing = i
			break
	_rebuild()


func _refresh_timing_list_text() -> void:
	if _timing_list == null or _timing_chart == null:
		return
	var points: Array[TimingPoint] = _timing_chart.group_bpm_points_for(_timing_chart.current_group)
	var count := mini(_timing_list.item_count, points.size())
	for i in count:
		_timing_list.set_item_text(i, _timing_row_text(_timing_chart, i, points[i]))


func _delete_timing_point() -> void:
	var chart: Chart = _app.chart
	var points: Array[TimingPoint] = chart.group_bpm_points_for(chart.current_group)
	if points.size() <= 1:
		_app.notice.emit("至少要保留 1 个 BPM 点（它定义开头速度）。", "warning")
		return
	if _selected_timing < 0 or _selected_timing >= points.size():
		return
	_app.begin_edit()
	points.remove_at(_selected_timing)
	points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
	chart.group_bpm_points[chart.current_group] = points
	_app.finish_edit()
	_selected_timing = clampi(_selected_timing, 0, points.size() - 1)
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
	# Path 整链一起复制并重映射 id，否则新 part 会指向原链（预览/存盘会跳过它）。
	var sources: Array[Note] = []
	for item in _app.with_anchor_partners([note]):
		for part in _app.chart.path_chain(item):
			if not sources.has(part):
				sources.append(part)
	var id_map := {}
	var copies: Array[Note] = []
	for item in sources:
		var copy := Note.from_dict(item.to_dict())
		copy.id = _app.chart.next_note_id()
		copy.beat = item.beat + 1.0
		if copy.type in ["hold", "path"]:
			copy.end_beat = item.end_beat + 1.0
		id_map[item.id] = copy
		copies.append(copy)
	for copy in copies:
		if copy.type != "path":
			continue
		if id_map.has(copy.path_prev_id):
			copy.path_prev_id = (id_map[copy.path_prev_id] as Note).id
		else:
			copy.path_prev_id = -1
			copy.path_part = 0
		copy.path_next_id = (id_map[copy.path_next_id] as Note).id if id_map.has(copy.path_next_id) else -1
	if note.type == "anchor" and copies.size() > 1:
		var pair_id := "P%d" % copies[0].id
		for copy in copies:
			copy.pair_id = pair_id
	_app.begin_edit()
	for copy in copies:
		_app.chart.notes.append(copy)
	_app.chart.reassign_note_ids()
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
