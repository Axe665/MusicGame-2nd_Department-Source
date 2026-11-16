class_name StoryboardEditor
extends AcceptDialog

## 故事板编辑器：在制谱器里直接编辑 osu! storyboard（移植自 osu!lazer 的 Storyboard 数据模型）。
##
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


func _set_dirty(on: bool) -> void:
	_dirty = on
	title = "故事板编辑器 *" if on else "故事板编辑器"


## 有未保存改动时先问一句，别让人一键关掉半小时的活。
func _request_close() -> void:
	if not _dirty:
		hide()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "还有未保存的改动"
	dialog.dialog_text = "关闭会丢掉这次的修改。要保存吗？"
	dialog.ok_button_text = "保存并关闭"
	var discard := dialog.add_cancel_button("放弃修改")
	discard.pressed.connect(func() -> void:
		_set_dirty(false)
		dialog.queue_free()
		hide())
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		_on_save()
		dialog.queue_free()
		if not _dirty:
			hide())
	dialog.popup_centered()


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


func _init() -> void:
	title = "故事板编辑器"
	# 小屏（1366x768 / 1280x720）也要放得下：窗口本身可以缩到 640x420，
	# 内容超出时由 ScrollContainer 滚动，不再把底部按钮顶到屏幕外。
	min_size = Vector2i(640, 420)
	_app = get_node_or_null("/root/App")
	_build_ui()
	get_ok_button().hide()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "EditorScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2i(960, 640)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	var root := HSplitContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(root)

	# ── 左：对象列表 ────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2i(360, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	var left_title := Label.new()
	left_title.text = "对象（同图层里越靠下越晚画 = 越在上层）"
	left.add_child(left_title)
	var order_row := HBoxContainer.new()
	left.add_child(order_row)
	var raise_button := Button.new()
	raise_button.text = "▲ 上移"
	raise_button.tooltip_text = "同图层里往前挪一层（更晚画 = 盖住后面的）"
	raise_button.pressed.connect(func() -> void: _move_order(1))
	order_row.add_child(raise_button)
	var lower_button := Button.new()
	lower_button.text = "▼ 下移"
	lower_button.tooltip_text = "同图层里往后挪一层"
	lower_button.pressed.connect(func() -> void: _move_order(-1))
	order_row.add_child(lower_button)
	_objects = ItemList.new()
	_objects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objects.select_mode = ItemList.SELECT_MULTI
	_objects.item_selected.connect(_on_object_selected)
	left.add_child(_objects)
	var row := HBoxContainer.new()
	left.add_child(row)
	var add := Button.new()
	add.text = "添加 Sprite"
	add.pressed.connect(_on_add_sprite)
	row.add_child(add)
	var duplicate := Button.new()
	duplicate.text = "复制"
	duplicate.pressed.connect(_on_duplicate_sprite)
	row.add_child(duplicate)
	var remove := Button.new()
	remove.text = "删除"
	remove.pressed.connect(_on_remove_sprite)
	row.add_child(remove)
	var library_title := Label.new()
	library_title.text = "素材库（点两下加到画布）"
	library_title.add_theme_font_size_override("font_size", 11)
	left.add_child(library_title)
	_library = ItemList.new()
	_library.custom_minimum_size = Vector2i(0, 80)
	_library.item_activated.connect(_on_library_pick)
	left.add_child(_library)
	var library_row := HBoxContainer.new()
	left.add_child(library_row)
	var library_refresh := Button.new()
	library_refresh.text = "刷新素材"
	library_refresh.pressed.connect(_refresh_library)
	library_row.add_child(library_refresh)

	# ── 右：选中对象的属性 + 命令 ───────────────────────────────────
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	# ── 图层显隐（照 osu Design 的 Layer Toggles，纯显示过滤）─────────
	var layer_row := HBoxContainer.new()
	layer_row.add_theme_constant_override("separation", 4)
	right.add_child(layer_row)
	var layer_label := Label.new()
	layer_label.text = "图层"
	layer_label.add_theme_font_size_override("font_size", 11)
	layer_row.add_child(layer_label)
	var layer_titles := {"Background": "背景", "Fail": "Fail", "Pass": "Pass",
		"Foreground": "前景", "Overlay": "覆盖", "Video": "Video"}
	for layer_name in LAYERS:
		var toggle := CheckBox.new()
		toggle.text = String(layer_titles.get(layer_name, layer_name))
		toggle.button_pressed = true
		toggle.add_theme_font_size_override("font_size", 11)
		toggle.toggled.connect(func(on: bool) -> void: _canvas.set_layer_visible(layer_name, on))
		layer_row.add_child(toggle)

	# ── 画布：点选 / 拖动（osu Design 页的画布位）────────────────────
	_canvas = CanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 画布至少 320 高：之前被上下两个列表挤到 160，场只有 285×160，像一条缝。
	_canvas.custom_minimum_size = Vector2i(0, 320)
	_canvas.selection_changed.connect(_on_canvas_selection)
	_canvas.dragged.connect(_on_canvas_drag)
	_canvas._on_hover_changed = func() -> void: _update_readout()
	_canvas.released.connect(func() -> void:
		_drag_undo_pushed = false
		_drag_last_delta = Vector2.ZERO
		_refresh_commands()
	)
	right.add_child(_canvas)
	var props := GridContainer.new()
	props.columns = 4
	right.add_child(props)
	props.add_child(_label("图片路径"))
	_path_edit = LineEdit.new()
	_path_edit.custom_minimum_size = Vector2i(240, 0)
	props.add_child(_path_edit)
	props.add_child(_label("图层"))
	_layer_option = OptionButton.new()
	for name in LAYERS:
		_layer_option.add_item(name)
	props.add_child(_layer_option)
	props.add_child(_label("原点"))
	_origin_option = OptionButton.new()
	for name in ORIGINS:
		_origin_option.add_item(name)
	props.add_child(_origin_option)
	props.add_child(_label("位置 X / Y"))
	var pos_row := HBoxContainer.new()
	_pos_x = _spin(-2000.0, 4000.0, 1.0, 320.0)
	_pos_y = _spin(-2000.0, 4000.0, 1.0, 240.0)
	pos_row.add_child(_pos_x)
	pos_row.add_child(_pos_y)
	props.add_child(pos_row)
	var apply := Button.new()
	apply.text = "应用属性"
	apply.pressed.connect(_on_apply_props)
	props.add_child(apply)

	var cmd_title := Label.new()
	cmd_title.text = "命令（时间 ms；L/T 块只读）"
	right.add_child(cmd_title)
	_commands = ItemList.new()
	_commands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commands.custom_minimum_size = Vector2i(0, 64)
	_commands.item_selected.connect(_on_command_selected)
	right.add_child(_commands)
	_cmd_map.clear()
	_cmd_editing = -1

	var cmd_row := GridContainer.new()
	cmd_row.columns = 6
	right.add_child(cmd_row)
	cmd_row.add_child(_label("类型"))
	_kind_option = OptionButton.new()
	for pair in COMMANDS:
		_kind_option.add_item(String(pair[0]))
	_kind_option.item_selected.connect(func(_i: int) -> void: _update_value_fields(_current_kind()))
	cmd_row.add_child(_kind_option)
	cmd_row.add_child(_label("开始 ms"))
	_start_spin = _spin(0.0, 600000.0, 10.0, 0.0)
	cmd_row.add_child(_start_spin)
	cmd_row.add_child(_label("结束 ms"))
	_end_spin = _spin(0.0, 600000.0, 10.0, 1000.0)
	cmd_row.add_child(_end_spin)

	var ease_row := HBoxContainer.new()
	right.add_child(ease_row)
	ease_row.add_child(_label("缓动"))
	_easing_option = OptionButton.new()
	for id in 36:
		_easing_option.add_item("%d · %s" % [id, Storyboard.Easing.name_of(id)])
	_easing_option.item_selected.connect(func(_i: int) -> void: _easing_curve.queue_redraw())
	ease_row.add_child(_easing_option)
	_easing_curve = Control.new()
	_easing_curve.custom_minimum_size = Vector2i(140, 26)
	_easing_curve.tooltip_text = "这条曲线就是 0→1 的缓动形状"
	_easing_curve.draw.connect(_draw_easing_curve)
	ease_row.add_child(_easing_curve)

	var from_row := HBoxContainer.new()
	right.add_child(from_row)
	from_row.add_child(_label("from"))
	_from_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_from_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_from_c = _spin(-4000.0, 4000.0, 1.0, 0.0)
	from_row.add_child(_from_a)
	from_row.add_child(_from_b)
	from_row.add_child(_from_c)
	var to_row := HBoxContainer.new()
	right.add_child(to_row)
	to_row.add_child(_label("to  "))
	_to_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_to_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_to_c = _spin(-4000.0, 4000.0, 1.0, 0.0)
	to_row.add_child(_to_a)
	to_row.add_child(_to_b)
	to_row.add_child(_to_c)
	_value_row = from_row

	var cmd_buttons := HBoxContainer.new()
	right.add_child(cmd_buttons)
	_apply_button = Button.new()
	_apply_button.text = "添加命令"
	_apply_button.pressed.connect(_on_apply_command)
	cmd_buttons.add_child(_apply_button)
	var del_cmd := Button.new()
	del_cmd.text = "删除命令"
	del_cmd.pressed.connect(_on_remove_command)
	cmd_buttons.add_child(del_cmd)
	var anchor_row := HBoxContainer.new()
	right.add_child(anchor_row)
	var prev_anchor := Button.new()
	prev_anchor.text = "◀ 锚点"
	prev_anchor.tooltip_text = "跳到当前对象上一个关键帧"
	prev_anchor.pressed.connect(func() -> void: _jump_anchor(-1))
	anchor_row.add_child(prev_anchor)
	var add_anchor := Button.new()
	add_anchor.text = "+ 锚点"
	add_anchor.tooltip_text = "在播放头处给当前类型加一个关键帧（取当前值）"
	add_anchor.pressed.connect(_add_anchor)
	anchor_row.add_child(add_anchor)
	var del_anchor := Button.new()
	del_anchor.text = "− 锚点"
	del_anchor.tooltip_text = "删掉播放头处、当前类型的那个关键帧"
	del_anchor.pressed.connect(_remove_anchor)
	anchor_row.add_child(del_anchor)
	var next_anchor := Button.new()
	next_anchor.text = "锚点 ▶"
	next_anchor.tooltip_text = "跳到当前对象下一个关键帧"
	next_anchor.pressed.connect(func() -> void: _jump_anchor(1))
	anchor_row.add_child(next_anchor)
	var readout := Label.new()
	readout.add_theme_font_size_override("font_size", 11)
	anchor_row.add_child(readout)
	_readout = readout

	var tl_row := HBoxContainer.new()
	right.add_child(tl_row)
	_play_button = Button.new()
	_play_button.text = "▶ 播放"
	_play_button.tooltip_text = "从播放头开始播放（走主界面音频，编辑器画布跟着动画走）"
	_play_button.pressed.connect(_toggle_play)
	tl_row.add_child(_play_button)
	var loop_check := CheckBox.new()
	loop_check.text = "循环"
	loop_check.button_pressed = true
	loop_check.tooltip_text = "播到谱面末尾自动回到开头"
	loop_check.toggled.connect(func(on: bool) -> void: _loop = on)
	tl_row.add_child(loop_check)
	var mute_check := CheckBox.new()
	mute_check.text = "静音"
	mute_check.tooltip_text = "只关预览音频，不动设置里的音量"
	mute_check.toggled.connect(func(on: bool) -> void:
		_silent = on
		mute_changed.emit(on))
	tl_row.add_child(mute_check)
	var snap_label := Label.new()
	snap_label.text = "吸附"
	tl_row.add_child(snap_label)
	_snap_option = OptionButton.new()
	_snap_option.add_item("关")
	_snap_option.add_item("1/1 拍")
	_snap_option.add_item("1/2 拍")
	_snap_option.add_item("1/4 拍")
	_snap_option.add_item("1/8 拍")
	_snap_option.selected = 3
	_snap_option.item_selected.connect(func(index: int) -> void:
		var divisors := [0.0, 1.0, 2.0, 4.0, 8.0]
		_timeline.snap_divisor = float(divisors[clampi(index, 0, divisors.size() - 1)]))
	tl_row.add_child(_snap_option)
	var grid_check := CheckBox.new()
	grid_check.text = "网格"
	grid_check.button_pressed = true
	grid_check.tooltip_text = "画布上每 32 设计像素一条细线"
	grid_check.toggled.connect(func(on: bool) -> void:
		if _canvas != null:
			_canvas.show_grid = on
			_canvas.queue_redraw())
	tl_row.add_child(grid_check)
	var undo_button := Button.new()
	undo_button.text = "撤销"
	undo_button.pressed.connect(_on_undo)
	tl_row.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "重做"
	redo_button.pressed.connect(_on_redo)
	tl_row.add_child(redo_button)
	var hint := Label.new()
	hint.text = "画布：滚轮缩放 / 中键平移 · Ctrl+S 保存"
	hint.add_theme_font_size_override("font_size", 10)
	tl_row.add_child(hint)
	_timeline = TimelineScript.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2i(0, 80)
	_timeline.seek.connect(func(ms: float) -> void:
		_canvas.set_playhead(ms)
		seek_requested.emit(ms)
		_update_readout(ms)
	)
	_timeline.sprite_picked.connect(func(index: int) -> void:
		_selected = index
		_objects.select(index)
		_on_object_selected(index))
	_timeline.changed.connect(func() -> void:
		_refresh_commands()
		_canvas.queue_redraw()
		edited.emit())
	right.add_child(_timeline)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	cmd_buttons.add_child(_status)

	# ── 底部按钮 ────────────────────────────────────────────────────
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var save := Button.new()
	save.text = "保存并应用"
	save.custom_minimum_size = Vector2i(120, 32)
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(_on_save)
	buttons.add_child(save)
	var export := Button.new()
	export.text = "导出 .osb…"
	export.custom_minimum_size = Vector2i(110, 32)
	export.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	export.pressed.connect(_on_export)
	buttons.add_child(export)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2i(80, 32)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_request_close)
	buttons.add_child(close)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.osb ; osu! storyboard"])
	_export_dialog.file_selected.connect(_export_to)
	add_child(_export_dialog)


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


## 打开某个谱面的故事板（没有就新建一个空的）。
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
	_refresh_objects()
	_timeline.set_chart(chart)
	_timeline.set_board(_board)
	_timeline.set_zoom(0.0, 0.0)
	_canvas.set_board(_board, _canvas_dir())
	_canvas.set_playhead(float(_timeline.playhead_ms))
	_refresh_library()
	_undo.clear()
	_redo.clear()
	popup_centered(fit_size(get_tree().root.get_visible_rect().size))


## 对话框尺寸：不超出窗口，也不超出屏幕可用区域（含标题栏/面板余量）。
static func fit_size(viewport: Vector2) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect().size
	var width := mini(int(viewport.x), usable.x)
	var height := mini(int(viewport.y), usable.y)
	return Vector2i(clampi(width - 60, 640, 1100), clampi(height - 90, 420, 900))


func _refresh_objects() -> void:
	_objects.clear()
	for sprite in _board.sprites:
		var s := sprite as Storyboard.Sprite
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
	_selected = -1
	_commands.clear()
	_cmd_map.clear()
	_cmd_editing = -1
	if _timeline != null:
		_timeline.set_board(_board)
		_timeline.set_selected(-1)
	if _canvas != null:
		_canvas.set_board(_board, _canvas_dir())
		_canvas.set_selected(-1)
	_refresh_commands()


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
	_selected = index
	if index < 0 or index >= _board.sprites.size():
		return
	var sprite := _board.sprites[index] as Storyboard.Sprite
	_path_edit.text = sprite.path
	_layer_option.selected = maxi(0, LAYERS.find(sprite.layer))
	_origin_option.selected = clampi(sprite.origin, 0, ORIGINS.size() - 1)
	_pos_x.value = sprite.pos.x
	_pos_y.value = sprite.pos.y
	_timeline.set_selected(index)
	_timeline.queue_redraw()
	if _canvas != null:
		_canvas.ensure_selected(index)
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
	_update_readout()


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
var _thumb_cache: Dictionary = {}

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
	_objects.select(index_new)
	_on_object_selected(index_new)
	_canvas.queue_redraw()
	_status.text = "已添加 %s（Foreground · 居中 · %s 起淡入）" % [file_name, _fmt_ms(ms)]
	_dirty = true
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
	for index in indices:
		_objects.select(int(index), false)
		if _selected < 0:
			_selected = int(index)
	_syncing_selection = false
	if _selected >= 0:
		_on_object_selected(_selected)
	else:
		_commands.clear()
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
	_refresh_commands()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
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
	_dirty = true
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
	_refresh_objects()
	_objects.select(_board.sprites.size() - 1)
	_on_object_selected(_board.sprites.size() - 1)


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
	_refresh_objects()
	_objects.select(_board.sprites.size() - 1)
	_on_object_selected(_board.sprites.size() - 1)


func _on_remove_sprite() -> void:
	_push_undo()
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	_board.sprites.remove_at(_selected)
	_refresh_objects()


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
	_refresh_objects()
	_objects.select(_selected)
	_timeline.queue_redraw()
	edited.emit()
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
		_status.text = "已添加 %s" % kind
	_refresh_commands()
	_timeline.queue_redraw()
	_canvas.queue_redraw()
	_dirty = true
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
	_dirty = true
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
	_refresh_objects()
	_objects.select(target)
	_on_object_selected(target)
	_dirty = true
	_status.text = "已%s一层" % ("上移" if direction > 0 else "下移")
	edited.emit()

static func transport_action(ms: float, total_ms: float, loop: bool) -> int:
	if ms < total_ms:
		return TRANSPORT_KEEP
	return TRANSPORT_RESTART if loop else TRANSPORT_STOP


func _toggle_play() -> void:
	if _playing:
		_stop_playback()
		return
	if _chart == null:
		return
	_playing = true
	if _play_button != null:
		_play_button.text = "❚❚ 暂停"
	play_requested.emit(float(_timeline.playhead_ms), _silent)


func _stop_playback() -> void:
	if not _playing:
		return
	_playing = false
	if _play_button != null:
		_play_button.text = "▶ 播放"
	pause_requested.emit()


## 播放中：播放头跟着主界面的谱面时间走，时间轴和画布一起动。
## _init 里节点还没入树，/root/App 还没法解析；第一次用到时再取。
func _app_node() -> Node:
	if _app == null or not is_instance_valid(_app):
		_app = get_node_or_null("/root/App")
	return _app


func _process(_delta: float) -> void:
	if not _playing:
		return
	if _app_node() == null or _chart == null or not visible:
		_stop_playback()
		return
	var total := _chart.timing.beat_to_chart_ms(_chart.duration_beats())
	var ms := _chart.timing.beat_to_chart_ms(float(_app_node().playhead_beat))
	match transport_action(ms, total, _loop):
		TRANSPORT_RESTART:
			_timeline.set_playhead(0.0)
			_canvas.set_playhead(0.0)
			play_requested.emit(0.0, _silent)
		TRANSPORT_STOP:
			_timeline.set_playhead(total)
			_canvas.set_playhead(total)
			_stop_playback()
		_:
			_timeline.set_playhead(ms)
			_canvas.set_playhead(ms)


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
