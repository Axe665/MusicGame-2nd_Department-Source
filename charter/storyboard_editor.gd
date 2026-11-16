class_name StoryboardEditor
extends Control

## 故事板编辑器：全屏工作区（预览 / 对象 / 属性 / 时间轴），不再用受限的弹窗。
## 支持：新建 / 编辑对象（Sprite、Layer、Origin、位置）、给对象加命令
## （F 淡入淡出 / M 移动 / MX / MY / S 缩放 / V 矢量缩放 / R 旋转 / C 颜色 / P,A 加色），
## 保存成 .osb 并挂到当前谱面，或导出到任意路径。

signal saved(path: String)
## 时间轴拖动播放头时发出，主界面据此跳转预览。
signal seek_requested(ms: float)
## 编辑过程中（拖动时间轴、加删命令/对象）发出，主界面据此实时刷新预览。
signal edited()
## 播放/暂停：主界面负责起停音频。silent = 只在预览里放画面。
signal play_requested(ms: float, silent: bool)
signal pause_requested()
## 播放中切换「静音」，主界面立刻改音量。
signal mute_changed(silent: bool)
## 打开/关闭（主界面据此隐藏/恢复主编辑区）。
signal opened()
signal closed()

## 播放到末尾时的动作。
const TRANSPORT_KEEP := 0
const TRANSPORT_RESTART := 1
const TRANSPORT_STOP := 2

const LAYERS := ["Background", "Fail", "Pass", "Foreground", "Overlay", "Video"]
const ORIGINS := ["左上", "上中", "右上", "左中", "居中", "右中", "左下", "下中", "右下"]
const COMMANDS := [
	["F 淡入淡出 (alpha)", "alpha"],
	["M 移动 (x,y)", "move"],
	["MX 横向移动", "x"],
	["MY 纵向移动", "y"],
	["S 缩放", "scale"],
	["V 矢量缩放 (x,y)", "vector"],
	["R 旋转（度）", "rotation"],
	["C 颜色 (0-255)", "colour"],
	["P,A 加色", "additive"],
]

var _app: Node = null
var _board: Storyboard = null
var _chart: Chart = null
var _dir := ""
var _selected := -1

var _objects: ItemList = null
var _commands: ItemList = null
var _path_edit: LineEdit = null
var _layer_option: OptionButton = null
var _origin_option: OptionButton = null
var _pos_x: SpinBox = null
var _pos_y: SpinBox = null
var _kind_option: OptionButton = null
var _start_spin: SpinBox = null
var _end_spin: SpinBox = null
var _from_a: SpinBox = null
var _from_b: SpinBox = null
var _from_c: SpinBox = null
var _to_a: SpinBox = null
var _to_b: SpinBox = null
var _to_c: SpinBox = null
var _easing: SpinBox = null
var _easing_option: OptionButton = null
var _easing_curve: Control = null
var _apply_button: Button = null
var _value_row: Control = null
var _readout: Label = null
## 命令列表显示下标 → sprite.commands 下标（块内命令不列出）。
var _cmd_map: Array[int] = []
## 正在编辑的命令在 sprite.commands 里的下标；-1 = 新增模式。
var _cmd_editing := -1
var _dirty := false

var _status: Label = null
var _export_dialog: FileDialog = null
const TimelineScript := preload("res://charter/storyboard_timeline.gd")
const CanvasScript := preload("res://charter/storyboard_canvas.gd")
var _timeline = null
## 可视化画布：点选 / 拖动 sprite。
var _canvas = null
var _drag_undo_pushed := false
var _drag_last_delta := Vector2.ZERO
var _syncing_selection := false
var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap_option: OptionButton = null
## 素材库：故事板目录里的图片，点两下加一个 Sprite。
var _library: ItemList = null
## 预览播放：播放头由主界面的音频时间驱动（不再自己数拍）。
var _playing := false
var _loop := true
var _silent := false
var _play_button: Button = null

var _title_label: Label = null
var _time_label: Label = null
var _fps_label: Label = null
var _inspector: Control = null
var _filter_edit: LineEdit = null
## 对象列表显示下标 → sprite 下标（有筛选时两者不同）。
var _obj_map: Array[int] = []
var _thumb_cache: Dictionary = {}
var _last_readout_msec := 0


func _init() -> void:
	_app = null
	_build_ui()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()


func _set_dirty(on: bool) -> void:
	_dirty = on
	if _title_label != null:
		_title_label.text = "故事板编辑器 *" if on else "故事板编辑器"


## 有未保存改动时先问一句，别让人一键关掉半小时的活。
func _request_close() -> void:
	if not _dirty:
		_close()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "还有未保存的改动"
	dialog.dialog_text = "关闭会丢掉这次的修改。要保存吗？"
	dialog.ok_button_text = "保存并关闭"
	var discard := dialog.add_cancel_button("放弃修改")
	discard.pressed.connect(func() -> void:
		_set_dirty(false)
		dialog.queue_free()
		_close())
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		_on_save()
		dialog.queue_free()
		if not _dirty:
			_close())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _close() -> void:
	if not visible:
		return
	_stop_playback()
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# 输入框里打字时不要抢键。
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is SpinBox
	if key.keycode == KEY_S and key.ctrl_pressed:
		_on_save()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_Z and key.ctrl_pressed:
		if key.shift_pressed:
			_on_redo()
		else:
			_on_undo()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_ESCAPE:
		_request_close()
		get_viewport().set_input_as_handled()
		return
	if typing:
		return
	if key.keycode == KEY_SPACE:
		_toggle_play()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DELETE:
		if _commands.has_focus():
			_on_remove_command()
		else:
			_on_remove_sprite()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT:
		var step := 1000.0 / maxf(1.0, Engine.get_frames_per_second())
		_seek_to(maxf(0.0, _timeline.playhead_ms + (-step if key.keycode == KEY_LEFT else step)))
		get_viewport().set_input_as_handled()


## 列表 / 时间轴 / 画布选中同一个 sprite 时走这里。
func _select_sprite(index: int) -> void:
	if _board == null or index < 0 or index >= _board.sprites.size():
		return
	var list_index := _obj_map.find(index)
	if list_index >= 0:
		_syncing_selection = true
		_objects.deselect_all()
		_objects.select(list_index, false)
		_syncing_selection = false
	_on_object_selected(list_index)


func _on_timeline_command(index: int, command: Storyboard.Command) -> void:
	_select_sprite(index)
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var command_index := sprite.commands.find(command)
	var display_index := _cmd_map.find(command_index)
	if display_index >= 0:
		_commands.select(display_index)
		_on_command_selected(display_index)


func _main_node() -> Node:
	var parent := get_parent()
	return parent if parent != null and parent.has_method("is_playing") else null


func _main_is_playing() -> bool:
	var main := _main_node()
	return main != null and bool(main.is_playing())


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.045, 0.05, 0.065, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	# ── 顶部：标题 / 传送 / 保存 ─────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)
	_title_label = Label.new()
	_title_label.text = "故事板编辑器"
	_title_label.add_theme_font_size_override("font_size", 15)
	header.add_child(_title_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.text = "0:00.000 / 0:00.000"
	header.add_child(_time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_play_button = Button.new()
	_play_button.text = "▶ 播放"
	_play_button.tooltip_text = "从播放头开始播放（走主界面音频，时间轴和画布跟着动画走）"
	_play_button.pressed.connect(_toggle_play)
	header.add_child(_play_button)
	header.add_child(_transport_button("⏮", "回到开头", func() -> void: _seek_to(0.0)))
	header.add_child(_transport_button("◀ 关键帧", "跳到当前对象上一个关键帧", func() -> void: _jump_anchor(-1)))
	header.add_child(_transport_button("关键帧 ▶", "跳到当前对象下一个关键帧", func() -> void: _jump_anchor(1)))
	header.add_child(_transport_button("⏭", "跳到结尾", func() -> void: _seek_to(_timeline.span_ms if _timeline != null else 0.0)))
	var loop_check := CheckBox.new()
	loop_check.text = "循环"
	loop_check.button_pressed = true
	loop_check.tooltip_text = "播到故事板末尾自动回到开头"
	loop_check.toggled.connect(func(on: bool) -> void: _loop = on)
	header.add_child(loop_check)
	var snap_label := Label.new()
	snap_label.text = "吸附"
	snap_label.add_theme_font_size_override("font_size", 10)
	header.add_child(snap_label)
	_snap_option = OptionButton.new()
	_snap_option.add_item("关")
	_snap_option.add_item("1/1 拍")
	_snap_option.add_item("1/2 拍")
	_snap_option.add_item("1/4 拍")
	_snap_option.add_item("1/8 拍")
	_snap_option.selected = 3
	_snap_option.add_theme_font_size_override("font_size", 10)
	_snap_option.item_selected.connect(func(index: int) -> void:
		var divisors := [0.0, 1.0, 2.0, 4.0, 8.0]
		if _timeline != null:
			_timeline.snap_divisor = float(divisors[clampi(index, 0, divisors.size() - 1)]))
	header.add_child(_snap_option)
	var mute_check := CheckBox.new()
	mute_check.text = "静音"
	mute_check.tooltip_text = "只关预览音频，不动设置里的音量"
	mute_check.toggled.connect(func(on: bool) -> void:
		_silent = on
		mute_changed.emit(on))
	header.add_child(mute_check)
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 10)
	header.add_child(_fps_label)
	header.add_child(_button("保存并应用", _on_save, 110))
	header.add_child(_button("导出 .osb…", _on_export, 100))
	header.add_child(_button("关闭", _request_close, 64))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 10)
	_status.modulate = Color(1, 1, 1, 0.75)
	column.add_child(_status)

	# ── 主体：对象 / 预览 / 属性 ─────────────────────────────────────
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# 左：对象列表 + 素材库
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2i(330, 0)
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	var left_title := Label.new()
	left_title.text = "对象"
	left.add_child(left_title)
	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "按文件名 / 图层筛选"
	_filter_edit.text_changed.connect(func(_text: String) -> void: _refresh_objects())
	left.add_child(_filter_edit)
	_objects = ItemList.new()
	_objects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objects.select_mode = ItemList.SELECT_MULTI
	_objects.item_selected.connect(_on_object_selected)
	left.add_child(_objects)
	var obj_row := HBoxContainer.new()
	left.add_child(obj_row)
	obj_row.add_child(_button("添加", _on_add_sprite, 0))
	obj_row.add_child(_button("复制", _on_duplicate_sprite, 0))
	obj_row.add_child(_button("删除", _on_remove_sprite, 0))
	obj_row.add_child(_button("▲", func() -> void: _move_order(1), 30))
	obj_row.add_child(_button("▼", func() -> void: _move_order(-1), 30))
	var library_title := Label.new()
	library_title.text = "素材库（双击加到画布）"
	library_title.add_theme_font_size_override("font_size", 10)
	left.add_child(library_title)
	_library = ItemList.new()
	_library.custom_minimum_size = Vector2i(0, 92)
	_library.size_flags_vertical = Control.SIZE_SHRINK_END
	_library.item_activated.connect(_on_library_pick)
	left.add_child(_library)
	var library_row := HBoxContainer.new()
	left.add_child(library_row)
	library_row.add_child(_button("刷新素材", _refresh_library, 0))

	# 中：画布
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	body.add_child(center)
	var canvas_tools := HBoxContainer.new()
	center.add_child(canvas_tools)
	canvas_tools.add_child(_button("适配安全框", func() -> void: _canvas.fit_field(), 0))
	canvas_tools.add_child(_button("适配内容", func() -> void: _canvas.fit_content(), 0))
	var grid_check := CheckBox.new()
	grid_check.text = "网格"
	grid_check.button_pressed = true
	grid_check.tooltip_text = "安全框内每 32 设计像素一条细线"
	grid_check.toggled.connect(func(on: bool) -> void:
		if _canvas != null:
			_canvas.show_grid = on
			_canvas.queue_redraw())
	canvas_tools.add_child(grid_check)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 10)
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_tools.add_child(_readout)
	_canvas = CanvasScript.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.selection_changed.connect(_on_canvas_selection)
	_canvas.dragged.connect(_on_canvas_drag)
	_canvas.released.connect(func() -> void:
		_drag_undo_pushed = false
		_drag_last_delta = Vector2.ZERO)
	_canvas._on_hover_changed = func() -> void: _update_readout()
	center.add_child(_canvas)

	# 右：属性（选中才显示）
	_inspector = VBoxContainer.new()
	_inspector.custom_minimum_size = Vector2i(360, 0)
	_inspector.visible = false
	body.add_child(_inspector)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.add_child(inspector_scroll)
	var props := VBoxContainer.new()
	props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props.add_theme_constant_override("separation", 4)
	inspector_scroll.add_child(props)
	var prop_title := Label.new()
	prop_title.text = "属性"
	props.add_child(prop_title)
	var grid := GridContainer.new()
	grid.columns = 2
	props.add_child(grid)
	grid.add_child(_label("图片路径"))
	_path_edit = LineEdit.new()
	_path_edit.custom_minimum_size = Vector2i(220, 0)
	grid.add_child(_path_edit)
	grid.add_child(_label("图层"))
	_layer_option = OptionButton.new()
	for layer in LAYERS:
		_layer_option.add_item(layer)
	grid.add_child(_layer_option)
	grid.add_child(_label("原点"))
	_origin_option = OptionButton.new()
	for origin in ORIGINS:
		_origin_option.add_item(origin)
	grid.add_child(_origin_option)
	grid.add_child(_label("位置 X / Y"))
	var pos_row := HBoxContainer.new()
	_pos_x = _spin(-4000.0, 4000.0, 1.0, 320.0)
	_pos_y = _spin(-4000.0, 4000.0, 1.0, 240.0)
	pos_row.add_child(_pos_x)
	pos_row.add_child(_pos_y)
	grid.add_child(pos_row)
	grid.add_child(_button("应用属性", _on_apply_props, 0))

	var cmd_title := Label.new()
	cmd_title.text = "命令（时间 ms；L/T 块只读）"
	props.add_child(cmd_title)
	_commands = ItemList.new()
	_commands.custom_minimum_size = Vector2i(0, 120)
	_commands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commands.item_selected.connect(_on_command_selected)
	props.add_child(_commands)

	var cmd_grid := GridContainer.new()
	cmd_grid.columns = 4
	props.add_child(cmd_grid)
	cmd_grid.add_child(_label("类型"))
	_kind_option = OptionButton.new()
	for pair in COMMANDS:
		_kind_option.add_item(String(pair[0]))
	_kind_option.item_selected.connect(func(_i: int) -> void: _update_value_fields(_current_kind()))
	cmd_grid.add_child(_kind_option)
	cmd_grid.add_child(_label("开始 ms"))
	_start_spin = _spin(0.0, 600000.0, 10.0, 0.0)
	cmd_grid.add_child(_start_spin)
	cmd_grid.add_child(_label("结束 ms"))
	_end_spin = _spin(0.0, 600000.0, 10.0, 1000.0)
	cmd_grid.add_child(_end_spin)

	var ease_row := HBoxContainer.new()
	props.add_child(ease_row)
	ease_row.add_child(_label("缓动"))
	_easing_option = OptionButton.new()
	for id in 36:
		_easing_option.add_item("%d · %s" % [id, Storyboard.Easing.name_of(id)])
	_easing_option.item_selected.connect(func(_i: int) -> void: _easing_curve.queue_redraw())
	ease_row.add_child(_easing_option)
	_easing_curve = Control.new()
	_easing_curve.custom_minimum_size = Vector2i(120, 24)
	_easing_curve.tooltip_text = "这条曲线就是 0→1 的缓动形状"
	_easing_curve.draw.connect(_draw_easing_curve)
	ease_row.add_child(_easing_curve)

	var from_row := HBoxContainer.new()
	props.add_child(from_row)
	from_row.add_child(_label("from"))
	_from_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_from_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_from_c = _spin(-4000.0, 4000.0, 1.0, 0.0)
	from_row.add_child(_from_a)
	from_row.add_child(_from_b)
	from_row.add_child(_from_c)
	var to_row := HBoxContainer.new()
	props.add_child(to_row)
	to_row.add_child(_label("to  "))
	_to_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_to_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_to_c = _spin(-4000.0, 4000.0, 1.0, 0.0)
	to_row.add_child(_to_a)
	to_row.add_child(_to_b)
	to_row.add_child(_to_c)
	_value_row = from_row

	var cmd_buttons := HBoxContainer.new()
	props.add_child(cmd_buttons)
	_apply_button = Button.new()
	_apply_button.text = "添加命令"
	_apply_button.pressed.connect(_on_apply_command)
	cmd_buttons.add_child(_apply_button)
	cmd_buttons.add_child(_button("删除命令", _on_remove_command, 0))
	var anchor_row := HBoxContainer.new()
	props.add_child(anchor_row)
	anchor_row.add_child(_button("◀ 锚点", func() -> void: _jump_anchor(-1), 0))
	anchor_row.add_child(_button("+ 锚点", _add_anchor, 0))
	anchor_row.add_child(_button("− 锚点", _remove_anchor, 0))
	anchor_row.add_child(_button("锚点 ▶", func() -> void: _jump_anchor(1), 0))

	# ── 底部：时间轴 ────────────────────────────────────────────────
	_timeline = TimelineScript.new()
	_timeline.custom_minimum_size = Vector2i(0, 250)
	_timeline.size_flags_vertical = Control.SIZE_SHRINK_END
	_timeline.seek.connect(func(ms: float) -> void:
		_canvas.set_playhead(ms)
		seek_requested.emit(ms)
		_update_readout(ms))
	_timeline.sprite_picked.connect(func(index: int) -> void: _select_sprite(index))
	_timeline.command_picked.connect(_on_timeline_command)
	_timeline.layer_visibility_changed.connect(func(layer: String, visible: bool) -> void:
		_canvas.set_layer_visible(layer, visible)
		_update_readout())
	_timeline.layer_lock_changed.connect(func(layer: String, locked: bool) -> void:
		_canvas.set_layer_locked(layer, locked)
		_update_readout())
	_timeline.drag_started.connect(func() -> void: _push_undo())
	_timeline.drag_finished.connect(func() -> void:
		_board.invalidate()
		_set_dirty(true)
		edited.emit())
	_timeline.changed.connect(func() -> void:
		if _board != null:
			_board.invalidate()
		_refresh_commands()
		_canvas.queue_redraw()
		_set_dirty(true)
		edited.emit()
		_update_readout())
	column.add_child(_timeline)

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.osb ; osu! storyboard"])
	_export_dialog.file_selected.connect(_export_to)
	add_child(_export_dialog)


func _button(text: String, target: Callable, width: int = 0) -> Button:
	var button := Button.new()
	button.text = text
	if width > 0:
		button.custom_minimum_size = Vector2i(width, 0)
	button.pressed.connect(target)
	return button


func _transport_button(text: String, tip: String, target: Callable) -> Button:
	var button := _button(text, target)
	button.tooltip_text = tip
	button.add_theme_font_size_override("font_size", 10)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _spin(low: float, high: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2i(96, 0)
	return spin

func open_for(chart: Chart) -> void:
	_chart = chart
	_dir = String(chart.metadata.get("storyboard", ""))
	_board = null
	if not _dir.is_empty():
		var text := FileAccess.get_file_as_string(_dir + "/storyboard.osb")
		if not text.is_empty():
			_board = Storyboard.parse(text, "storyboard.osb")
	if _board == null:
		_board = Storyboard.create_blank()
	_selected = -1
	_timeline.hidden_layers.clear()
	_timeline.locked_layers.clear()
	_timeline.expanded.clear()
	_canvas.hidden_layers.clear()
	_canvas.locked_layers.clear()
	_refresh_objects()
	_timeline.set_chart(chart)
	_timeline.set_board(_board)
	_timeline.set_zoom(0.0, 0.0)
	_canvas.set_board(_board, _canvas_dir())
	_inspector.visible = false
	_undo.clear()
	_redo.clear()
	_set_dirty(false)
	show()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var osb_ms := 0.0
	var app := _app_node()
	if app != null:
		osb_ms = chart.beat_to_ms(float(app.playhead_beat)) - chart.offset_ms
	_timeline.set_playhead(osb_ms)
	_canvas.set_playhead(osb_ms)
	_canvas.fit_content()
	# 打开时不要打断正在播放的音频；只有暂停时才让主预览跟过来。
	if not _main_is_playing():
		seek_requested.emit(osb_ms)
	_update_readout(osb_ms)
	if _time_label != null:
		_time_label.text = "%s / %s" % [_fmt_time_ms(osb_ms), _fmt_time_ms(_timeline.span_ms)]
	call_deferred("_refresh_library")
	opened.emit()


## 对话框尺寸：不超出窗口，也不超出屏幕可用区域（含标题栏/面板余量）。
static func fit_size(viewport: Vector2) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect().size
	var width := mini(int(viewport.x), usable.x)
	var height := mini(int(viewport.y), usable.y)
	return Vector2i(clampi(width - 60, 640, 1100), clampi(height - 90, 420, 900))


func _refresh_objects(rebuild_timeline: bool = true) -> void:
	var keep := _selected
	var filter := _filter_edit.text.strip_edges().to_lower() if _filter_edit != null else ""
	_objects.clear()
	_obj_map.clear()
	for i in _board.sprites.size():
		var s := _board.sprites[i] as Storyboard.Sprite
		if not filter.is_empty() and not ("%s %s" % [s.path, s.layer]).to_lower().contains(filter):
			continue
		var visible_commands := 0
		for command in s.commands:
			if not (command as Storyboard.Command).in_block:
				visible_commands += 1
		var line := "%s  [%s]  %s ~ %s  · %d 条命令" % [
			s.path.get_file() if not s.path.is_empty() else "(未填路径)", s.layer,
			_fmt_ms(s.start_time), _fmt_ms(s.end_time), visible_commands]
		if s.commands.is_empty():
			line += "  ⚠ 无命令（不会显示）"
		_objects.add_item(line)
		_obj_map.append(i)
	if rebuild_timeline:
		if _timeline != null:
			_timeline.set_board(_board)
			_timeline.set_selected(-1)
		if _canvas != null:
			_canvas.set_board(_board, _canvas_dir())
			_canvas.set_selected(-1)
	_selected = -1
	if keep >= 0:
		var list_index := _obj_map.find(keep)
		if list_index >= 0:
			_objects.select(list_index, false)
			_selected = keep
			if _timeline != null:
				_timeline.set_selected(keep)
			if _canvas != null:
				_canvas.ensure_selected(keep)
	_refresh_commands()
	_inspector.visible = _selected >= 0


static func _fmt_time_ms(ms: float) -> String:
	var total := maxf(0.0, ms)
	var minutes := int(total / 60000.0)
	var seconds := int(fmod(total, 60000.0) / 1000.0)
	var millis := int(fmod(total, 1000.0))
	return "%d:%02d.%03d" % [minutes, seconds, millis]


static func _fmt_ms(ms: float) -> String:
	if ms < 0.0:
		return "—"
	return "%.1fs" % (ms / 1000.0)

func _refresh_commands() -> void:
	_commands.clear()
	_cmd_map.clear()
	_cmd_editing = -1
	if _apply_button != null:
		_apply_button.text = "添加命令"
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	for i in sprite.commands.size():
		var command := sprite.commands[i] as Storyboard.Command
		# L 展开出来的副本不单独列出（它们在时间轴上仍然参与绘制）。
		if command.in_block:
			continue
		_cmd_map.append(i)
		_commands.add_item(_describe(command))
	var blocks := sprite.loops.size()
	if blocks > 0:
		_status.text = "这个对象还有 %d 个 L 循环块（只读，原样保存）" % blocks

static func _describe(command: Storyboard.Command) -> String:
	var kind := command.kind_name
	var pair := "%s → %s" % [_fmt_values(command.from), _fmt_values(command.to)]
	return "%s  %dms~%dms  %s  %s" % [kind, int(command.start), int(command.end), pair,
		Storyboard.Easing.name_of(command.easing)]

static func _fmt_values(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append("%.2f" % float(value))
	return ",".join(parts)


func _on_object_selected(index: int) -> void:
	if _syncing_selection:
		return
	if index < 0 or index >= _obj_map.size():
		_selected = -1
		_inspector.visible = false
		return
	_selected = int(_obj_map[index])
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	_inspector.visible = true
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	_path_edit.text = sprite.path
	_layer_option.selected = maxi(0, LAYERS.find(sprite.layer))
	_origin_option.selected = clampi(sprite.origin, 0, ORIGINS.size() - 1)
	_pos_x.value = sprite.pos.x
	_pos_y.value = sprite.pos.y
	_timeline.set_selected(_selected)
	_timeline.queue_redraw()
	if _canvas != null:
		_canvas.ensure_selected(_selected)
	_refresh_commands()
	# 官方编辑器点名字就跳到对象出现的位置；否则对象被播放头甩出生命周期时
	# 画布一片空白，作者只会以为图丢了。
	var ms := float(_timeline.playhead_ms)
	if sprite.commands.size() > 0 and (ms < sprite.start_time - 1.0 or ms > sprite.end_time + 1.0):
		_seek_to(sprite.start_time)
	_update_readout()


func _seek_to(ms: float) -> void:
	_timeline.set_playhead(ms)
	_canvas.set_playhead(ms)
	seek_requested.emit(ms)
	_update_readout(ms)
	if _time_label != null:
		_time_label.text = "%s / %s" % [_fmt_time_ms(ms), _fmt_time_ms(_timeline.span_ms)]


func _update_readout(ms: float = -1.0) -> void:
	if _readout == null:
		return
	var at := float(_timeline.playhead_ms) if ms < 0.0 else ms
	var count := 0
	var total := 0
	if _board != null:
		for item in _board.sample(at):
			if _canvas == null or not _canvas.hidden_layers.has(String(item["layer"])):
				count += 1
			total += 1
	var zoom: float = _canvas.zoom if _canvas != null else 1.0
	var mouse_text := "x — y —"
	if _canvas != null and _canvas.mouse_design.x >= 0.0:
		mouse_text = "x %d  y %d" % [roundi(_canvas.mouse_design.x), roundi(_canvas.mouse_design.y)]
	_readout.text = "  %s  ·  %s  ·  可见 %d / %d  ·  缩放 %d%%" % [
		_fmt_ms(at), mouse_text, count, total, roundi(zoom * 100.0)]

func _refresh_library() -> void:
	if _library == null:
		return
	_library.clear()
	var dir := _canvas_dir()
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for file_name in names:
		if not (file_name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]):
			continue
		_library.add_item(file_name)
		_library.set_item_metadata(_library.item_count - 1, file_name)
		if _library.item_count <= 200:
			_library.set_item_icon(_library.item_count - 1, _thumb(dir + "/" + file_name))


## 素材缩略图（官方 Sprite Library 也是带图的）。32px 足够认图。

func _thumb(path: String) -> Texture2D:
	if _thumb_cache.has(path):
		return _thumb_cache[path]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	var texture: Texture2D = null
	if image != null and not image.is_empty():
		image.resize(32, maxi(1, roundi(32.0 * float(image.get_height()) / float(maxi(1, image.get_width())))),
			Image.INTERPOLATE_BILINEAR)
		texture = ImageTexture.create_from_image(image)
	_thumb_cache[path] = texture
	return texture


func _on_library_pick(index: int) -> void:
	if _board == null or _library == null:
		return
	var file_name := String(_library.get_item_metadata(index))
	if file_name.is_empty():
		return
	_push_undo()
	var ms := float(_timeline.playhead_ms)
	var sprite := _board.add_sprite(file_name, "Foreground", 4, Vector2(320, 240))
	# 没有 alpha 命令的对象在 osu 和本编辑器里都不画；双击素材就该立刻看见。
	_board.add_command(sprite, "alpha", 0, ms, ms + 400.0, [0.0], [1.0])
	_refresh_objects()
	var index_new := _board.sprites.size() - 1
	var list_new := _obj_map.find(index_new)
	if list_new >= 0:
		_objects.select(list_new)
		_on_object_selected(list_new)
	_canvas.queue_redraw()
	_status.text = "已添加 %s（Foreground · 居中 · %s 起淡入）" % [file_name, _fmt_ms(ms)]
	_set_dirty(true)
	edited.emit()

func _canvas_dir() -> String:
	if not _dir.is_empty():
		return _dir
	return String(_chart.audio_path).get_base_dir() if _chart != null else ""


## 画布框选 / Ctrl 点选后同步列表与属性面板。
func _on_canvas_selection(indices: Array) -> void:
	_syncing_selection = true
	_objects.deselect_all()
	_selected = -1
	var first_list := -1
	for sprite_index in indices:
		var list_index := _obj_map.find(int(sprite_index))
		if list_index < 0:
			continue
		_objects.select(list_index, false)
		if first_list < 0:
			first_list = list_index
			_selected = int(sprite_index)
	_syncing_selection = false
	if first_list >= 0:
		_on_object_selected(first_list)
	else:
		_commands.clear()
		_inspector.visible = false
		_refresh_commands()
	_status.text = "已选 %d 个对象" % indices.size()
	_update_readout()


## 画布拖动：所有选中对象一起动，改当前时刻生效的移动关键帧；没有就改默认位置。
## delta 是「相对按下点的总位移」，这里只应用增量，否则每帧都会累加。
func _on_canvas_drag(indices: Array, _bases: Array, delta: Vector2) -> void:
	if _board == null or indices.is_empty():
		return
	if not _drag_undo_pushed:
		_push_undo()
		_drag_undo_pushed = true
	var step := delta - _drag_last_delta
	_drag_last_delta = delta
	if step == Vector2.ZERO:
		return
	for raw in indices:
		var index := int(raw)
		if index < 0 or index >= _board.sprites.size():
			continue
		_shift_sprite(_board.sprites[index] as Storyboard.Sprite, step)
	_board.invalidate()
	var primary := _board.sprites[int(indices[0])] as Storyboard.Sprite
	_pos_x.value = primary.pos.x
	_pos_y.value = primary.pos.y
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_update_readout()
	edited.emit()


func _shift_sprite(sprite: Storyboard.Sprite, delta: Vector2) -> void:
	var ms := float(_timeline.playhead_ms)
	var touched := false
	for command in sprite.commands:
		var c := command as Storyboard.Command
		# 解析器写入的是 "move"/"x"/"y"，不是文件名里的大写命令字母。
		if not (c.kind_name in ["move", "x", "y"]):
			continue
		if ms < c.start - 0.5 or ms > c.end + 0.5:
			continue
		c.from = _shift_values(c.from, delta, c.kind_name)
		c.to = _shift_values(c.to, delta, c.kind_name)
		touched = true
	if not touched:
		# 播放头处没有移动关键帧：就地补一条零时长 M，否则改了 pos 也会被 M 覆盖、画面不动。
		var pos := sprite.pos
		if sprite.timeline.has("move"):
			pos = sprite.sample_vec2("move", ms, pos)
		_board.add_command(sprite, "move", 0, ms, ms,
			[pos.x, pos.y], [pos.x + delta.x, pos.y + delta.y])
	sprite.build()

func _add_anchor() -> void:
	if _board == null or _selected < 0 or _selected >= _board.sprites.size():
		_status.text = "先选一个对象"
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var kind := _current_kind()
	var ms := float(_timeline.playhead_ms)
	var values := _kind_values(sprite, kind, ms)
	_push_undo()
	_board.add_command(sprite, kind, 0, ms, ms, values, values)
	_board.invalidate()
	_refresh_commands()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()
	_status.text = "%.0fms 加了 %s 锚点" % [ms, kind]


func _remove_anchor() -> void:
	if _board == null or _selected < 0 or _selected >= _board.sprites.size():
		_status.text = "先选一个对象"
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var ms := float(_timeline.playhead_ms)
	var kind := _current_kind()
	var best := -1
	var best_distance := 2.0
	for i in sprite.commands.size():
		var command := sprite.commands[i] as Storyboard.Command
		if command.in_block or command.kind_name != kind:
			continue
		var distance := absf(command.start - ms)
		if distance <= best_distance:
			best_distance = distance
			best = i
	if best < 0:
		_status.text = "%.0fms 附近没有 %s 锚点" % [ms, kind]
		return
	_push_undo()
	sprite.commands.remove_at(best)
	sprite.build()
	_board.invalidate()
	_refresh_commands()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()
	_status.text = "删掉了 %.0fms 的 %s 锚点" % [ms, kind]

func _jump_anchor(direction: int) -> void:
	if _board == null or _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var starts: Array[float] = []
	for command in sprite.commands:
		starts.append((command as Storyboard.Command).start)
	starts.sort()
	var ms := float(_timeline.playhead_ms)
	var target := -1.0
	if direction > 0:
		for value in starts:
			if value > ms + 0.5:
				target = value
				break
	else:
		for i in range(starts.size() - 1, -1, -1):
			if starts[i] < ms - 0.5:
				target = starts[i]
				break
	if target < 0.0:
		return
	_timeline.set_playhead(target)
	_canvas.set_playhead(target)
	seek_requested.emit(target)


static func _kind_values(sprite: Storyboard.Sprite, kind: String, ms: float) -> Array:
	var state := Storyboard.object_state(sprite, ms, 1.0)
	var pos: Vector2 = state["pos"]
	var scale: Vector2 = state["scale"]
	var colour: Color = state["colour"]
	match kind:
		"alpha":
			return [sprite.sample_float("alpha", ms, 1.0)]
		"move":
			return [pos.x, pos.y]
		"x":
			return [pos.x]
		"y":
			return [pos.y]
		"scale":
			return [(scale.x + scale.y) * 0.5]
		"vector":
			return [scale.x, scale.y]
		"rotation":
			return [float(state["rotation"])]
		"colour":
			return [colour.r * 255.0, colour.g * 255.0, colour.b * 255.0]
		"additive":
			return [1.0 if bool(state["additive"]) else 0.0]
	return [0.0]


static func _shift_values(values: Array, delta: Vector2, kind: String) -> Array:
	var out := values.duplicate()
	if kind != "y" and out.size() > 0:
		out[0] = float(out[0]) + delta.x
	if kind != "x" and out.size() > 1:
		out[1] = float(out[1]) + delta.y
	return out

func _push_undo() -> void:
	if _board == null:
		return
	_set_dirty(true)
	_undo.append(_board.to_osb_text())
	if _undo.size() > 50:
		_undo.pop_front()
	_redo.clear()


func _on_undo() -> void:
	if _undo.is_empty():
		_status.text = "没有可撤销的操作"
		return
	_redo.append(_board.to_osb_text())
	_board = Storyboard.parse(_undo.pop_back(), "undo.osb")
	_refresh_objects()
	_timeline.set_board(_board)
	_set_dirty(true)
	edited.emit()
	_status.text = "已撤销"


func _on_redo() -> void:
	if _redo.is_empty():
		_status.text = "没有可重做的操作"
		return
	_undo.append(_board.to_osb_text())
	_board = Storyboard.parse(_redo.pop_back(), "redo.osb")
	_refresh_objects()
	_timeline.set_board(_board)
	_set_dirty(true)
	edited.emit()
	_status.text = "已重做"


func _on_add_sprite() -> void:
	_push_undo()
	_board.add_sprite("sb/new.png", "Background", 4, Vector2(320, 240))
	_board.invalidate()
	_selected = _board.sprites.size() - 1
	_refresh_objects()
	_select_sprite(_selected)
	_set_dirty(true)
	edited.emit()


func _on_duplicate_sprite() -> void:
	_push_undo()
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	var source := _board.sprites[_selected] as Storyboard.Sprite
	var copy := _board.add_sprite(source.path, source.layer, source.origin, source.pos)
	for command in source.commands:
		var c := command as Storyboard.Command
		copy.add(c.duplicate())
	copy.build()
	_board.invalidate()
	_selected = _board.sprites.size() - 1
	_refresh_objects()
	_select_sprite(_selected)
	_set_dirty(true)
	edited.emit()


func _on_remove_sprite() -> void:
	_push_undo()
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	_board.sprites.remove_at(_selected)
	for i in _board.sprites.size():
		(_board.sprites[i] as Storyboard.Sprite).order = i
	_board.invalidate()
	_selected = -1
	_refresh_objects()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()
	_status.text = "已删除对象"


func _on_apply_props() -> void:
	_push_undo()
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	sprite.path = _path_edit.text.strip_edges()
	sprite.layer = LAYERS[clampi(_layer_option.selected, 0, LAYERS.size() - 1)]
	sprite.origin = clampi(_origin_option.selected, 0, ORIGINS.size() - 1)
	sprite.pos = Vector2(_pos_x.value, _pos_y.value)
	sprite.build()
	_board.invalidate()
	_refresh_objects()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()
	_update_readout()
	_status.text = "属性已更新"


func _current_kind() -> String:
	return String(COMMANDS[clampi(_kind_option.selected, 0, COMMANDS.size() - 1)][1])


## 按命令类型显示/隐藏参数框：C 要 6 个分量，M/V 要 2+2，开关型不要数值。
func _update_value_fields(kind: String) -> void:
	var two := kind in ["move", "vector"]
	var three := kind == "colour"
	var none := kind in ["additive", "flip_h", "flip_v"]
	_from_b.visible = two or three
	_to_b.visible = two or three
	_from_c.visible = three
	_to_c.visible = three
	_from_a.visible = not none
	_to_a.visible = not none


func _draw_easing_curve() -> void:
	if _easing_curve == null:
		return
	var box := _easing_curve.size
	_easing_curve.draw_rect(Rect2(Vector2.ZERO, box), Color(0, 0, 0, 0.35))
	var id := clampi(_easing_option.selected, 0, 35) if _easing_option != null else 0
	var points := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		points.append(Vector2(t * box.x, box.y - clampf(Storyboard.Easing.apply(id, t), 0.0, 1.0) * box.y))
	_easing_curve.draw_polyline(points, Color(0.45, 0.95, 0.85), 1.5)


## 点命令行：把所有字段回填，按钮变成「更新命令」。
func _on_command_selected(display_index: int) -> void:
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	if display_index < 0 or display_index >= _cmd_map.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var real := _cmd_map[display_index]
	var command := sprite.commands[real] as Storyboard.Command
	_cmd_editing = real
	_kind_option.selected = 0
	for i in COMMANDS.size():
		if String(COMMANDS[i][1]) == command.kind_name:
			_kind_option.selected = i
			break
	_easing_option.selected = clampi(command.easing, 0, 35)
	_start_spin.value = command.start
	_end_spin.value = command.end
	var kind := command.kind_name
	var from := command.from
	var to := command.to
	_from_a.value = 0.0
	_from_b.value = 0.0
	_from_c.value = 0.0
	_to_a.value = 0.0
	_to_b.value = 0.0
	_to_c.value = 0.0
	match kind:
		"move", "vector":
			if from.size() >= 2:
				_from_a.value = float(from[0])
				_from_b.value = float(from[1])
			if to.size() >= 2:
				_to_a.value = float(to[0])
				_to_b.value = float(to[1])
		"colour":
			if from.size() >= 3:
				_from_a.value = float(from[0]) * 255.0
				_from_b.value = float(from[1]) * 255.0
				_from_c.value = float(from[2]) * 255.0
			if to.size() >= 3:
				_to_a.value = float(to[0]) * 255.0
				_to_b.value = float(to[1]) * 255.0
				_to_c.value = float(to[2]) * 255.0
		"additive", "flip_h", "flip_v":
			pass
		_:
			if from.size() >= 1:
				_from_a.value = float(from[0])
			if to.size() >= 1:
				_to_a.value = float(to[0])
	_update_value_fields(kind)
	_apply_button.text = "更新命令"
	_easing_curve.queue_redraw()
	_status.text = "正在编辑：%s（改完点「更新命令」）" % kind


func _on_apply_command() -> void:
	if _selected < 0 or _selected >= _board.sprites.size():
		_status.text = "先选一个对象"
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var kind := _current_kind()
	var start := _start_spin.value
	var end := maxf(start, _end_spin.value)
	var easing := clampi(_easing_option.selected, 0, 35)
	var from_values: Array = [0.0]
	var to_values: Array = [0.0]
	match kind:
		"move", "vector":
			from_values = [_from_a.value, _from_b.value]
			to_values = [_to_a.value, _to_b.value]
		"colour":
			from_values = [clampf(_from_a.value / 255.0, 0.0, 1.0), clampf(_from_b.value / 255.0, 0.0, 1.0), clampf(_from_c.value / 255.0, 0.0, 1.0)]
			to_values = [clampf(_to_a.value / 255.0, 0.0, 1.0), clampf(_to_b.value / 255.0, 0.0, 1.0), clampf(_to_c.value / 255.0, 0.0, 1.0)]
		"additive", "flip_h", "flip_v":
			from_values = [1.0]
			to_values = [1.0]
		_:
			from_values = [_from_a.value]
			to_values = [_to_a.value]
	_push_undo()
	if _cmd_editing >= 0 and _cmd_editing < sprite.commands.size():
		var command := sprite.commands[_cmd_editing] as Storyboard.Command
		command.kind_name = kind
		command.easing = easing
		command.start = start
		command.end = end
		command.from = from_values
		command.to = to_values
		sprite.build()
		_board.invalidate()
		_status.text = "已更新 %s" % kind
	else:
		_board.add_command(sprite, kind, easing, start, end, from_values, to_values)
		_board.invalidate()
		_status.text = "已添加 %s" % kind
	_refresh_commands()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()

func _on_remove_command() -> void:
	var picked := _commands.get_selected_items()
	if picked.is_empty() or _selected < 0 or _selected >= _board.sprites.size():
		return
	if picked[0] >= _cmd_map.size():
		return
	_push_undo()
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	sprite.commands.remove_at(_cmd_map[picked[0]])
	sprite.build()
	_board.invalidate()
	_refresh_commands()
	if _timeline != null:
		_timeline.queue_redraw()
	_canvas.queue_redraw()
	_set_dirty(true)
	edited.emit()


## 同图层内调整绘制顺序：+1 = 往前（更晚画 = 盖住别人）。
func _move_order(direction: int) -> void:
	if _selected < 0 or _selected >= _board.sprites.size():
		_status.text = "先选一个对象"
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var target := -1
	if direction > 0:
		for i in range(_selected + 1, _board.sprites.size()):
			if (_board.sprites[i] as Storyboard.Sprite).layer == sprite.layer:
				target = i
				break
	else:
		for i in range(_selected - 1, -1, -1):
			if (_board.sprites[i] as Storyboard.Sprite).layer == sprite.layer:
				target = i
				break
	if target < 0:
		_status.text = "同图层里已经到头了"
		return
	_push_undo()
	_board.sprites.remove_at(_selected)
	_board.sprites.insert(target, sprite)
	for i in _board.sprites.size():
		(_board.sprites[i] as Storyboard.Sprite).order = i
	_board.invalidate()
	_selected = target
	_refresh_objects()
	var list_target := _obj_map.find(target)
	if list_target >= 0:
		_objects.select(list_target)
		_on_object_selected(list_target)
	_set_dirty(true)
	_status.text = "已%s一层" % ("上移" if direction > 0 else "下移")
	edited.emit()

static func transport_action(ms: float, total_ms: float, loop: bool) -> int:
	if ms < total_ms:
		return TRANSPORT_KEEP
	return TRANSPORT_RESTART if loop else TRANSPORT_STOP


func _toggle_play() -> void:
	if _main_is_playing():
		pause_requested.emit()
		return
	if _chart == null:
		return
	# 状态由主界面回传，按钮文字在 _process 里改；这里只负责发请求。
	play_requested.emit(float(_timeline.playhead_ms), _silent)


func _stop_playback() -> void:
	if _main_is_playing():
		pause_requested.emit()
	_playing = false
	if _play_button != null:
		_play_button.text = "▶ 播放"


## 播放中：播放头跟着主界面的谱面时间走，时间轴和画布一起动。
## _init 里节点还没入树，/root/App 还没法解析；第一次用到时再取。
func _app_node() -> Node:
	if _app == null or not is_instance_valid(_app):
		_app = get_node_or_null("/root/App")
	return _app


func _process(_delta: float) -> void:
	if not visible or _chart == null or _app_node() == null:
		return
	var playing := _main_is_playing()
	if _play_button != null:
		_play_button.text = "❚❚ 暂停" if playing else "▶ 播放"
	if not playing:
		_playing = false
		if _fps_label != null:
			_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())
		return
	_playing = true
	# osb 时间和 chart 时间差一个 offset；主界面播放时 playhead_beat 是 chart 拍。
	var osb_ms := _chart.beat_to_ms(float(_app_node().playhead_beat)) - _chart.offset_ms
	var total := _chart.beat_to_ms(_chart.content_end_beat()) - _chart.offset_ms
	if _timeline != null and _timeline.span_ms > total:
		total = _timeline.span_ms
	match transport_action(osb_ms, total, _loop):
		TRANSPORT_RESTART:
			_seek_to(0.0)
			play_requested.emit(0.0, _silent)
		TRANSPORT_STOP:
			_timeline.set_playhead(total)
			_canvas.set_playhead(total)
			pause_requested.emit()
			_playing = false
		_:
			_timeline.set_playhead(osb_ms)
			_canvas.set_playhead(osb_ms)
			# 读数里要 sample 一次整张故事板，别每帧都做。
			var now := Time.get_ticks_msec()
			if now - _last_readout_msec >= 100:
				_last_readout_msec = now
				_update_readout(osb_ms)
	if _time_label != null:
		_time_label.text = "%s / %s" % [_fmt_time_ms(osb_ms), _fmt_time_ms(total)]
	if _fps_label != null:
		_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())


func _on_save() -> void:
	if _board == null or _board.sprites.is_empty():
		_status.text = "还没有对象"
		return
	# 导入目录只读：第一次保存时把素材复制到我们自己的编辑目录，不动原谱
	if _dir.is_empty() or _dir.begins_with("user://imports/"):
		var key := "untitled"
		if _chart != null:
			key = (String(_chart.metadata.get("title", "")) + "|" + String(_chart.metadata.get("version", ""))).md5_text().substr(0, 10)
		var target := "user://storyboards/edit_%s" % key
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
		if not _dir.is_empty():
			for file_name in DirAccess.get_files_at(_dir):
				if file_name == "storyboard.osb":
					continue
				var source := _dir + "/" + file_name
				var destination := target + "/" + file_name
				if not FileAccess.file_exists(destination):
					var content := FileAccess.get_file_as_bytes(source)
					var out := FileAccess.open(destination, FileAccess.WRITE)
					if out != null:
						out.store_buffer(content)
						out.close()
		_dir = target
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var path := _dir + "/storyboard.osb"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "写不了 %s" % path
		return
	file.store_string(_board.to_osb_text())
	file.close()
	if _chart != null:
		_chart.metadata["storyboard"] = _dir
	_set_dirty(false)
	saved.emit(path)
	_refresh_library()
	_status.text = "已保存：%d 个对象 → %s" % [_board.sprites.size(), path]


func _on_export() -> void:
	_export_dialog.current_file = "storyboard.osb"
	_export_dialog.popup_centered(Vector2i(800, 600))


func _export_to(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "写不了 %s" % path
		return
	file.store_string(_board.to_osb_text())
	file.close()
	_status.text = "已导出 %s" % path
