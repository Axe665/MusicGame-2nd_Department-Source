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
var _to_a: SpinBox = null
var _to_b: SpinBox = null
var _easing: SpinBox = null
var _status: Label = null
var _export_dialog: FileDialog = null
const TimelineScript := preload("res://charter/storyboard_timeline.gd")
var _timeline = null
var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap_option: OptionButton = null


func _init() -> void:
	title = "故事板编辑器"
	min_size = Vector2i(980, 640)
	_app = get_node_or_null("/root/App")
	_build_ui()


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2i(1000, 620)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
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
	_objects = ItemList.new()
	_objects.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# ── 右：选中对象的属性 + 命令 ───────────────────────────────────
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
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
	cmd_title.text = "命令（时间单位 ms，离屏用 from/to）"
	right.add_child(cmd_title)
	_commands = ItemList.new()
	_commands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_commands)
	var cmd_row := GridContainer.new()
	cmd_row.columns = 4
	right.add_child(cmd_row)
	cmd_row.add_child(_label("类型"))
	_kind_option = OptionButton.new()
	for pair in COMMANDS:
		_kind_option.add_item(String(pair[0]))
	cmd_row.add_child(_kind_option)
	cmd_row.add_child(_label("缓动 0-35"))
	_easing = _spin(0.0, 35.0, 1.0, 0.0)
	cmd_row.add_child(_easing)
	cmd_row.add_child(_label("开始 ms"))
	_start_spin = _spin(0.0, 600000.0, 10.0, 0.0)
	cmd_row.add_child(_start_spin)
	cmd_row.add_child(_label("结束 ms"))
	_end_spin = _spin(0.0, 600000.0, 10.0, 1000.0)
	cmd_row.add_child(_end_spin)
	cmd_row.add_child(_label("from a / b"))
	var from_row := HBoxContainer.new()
	_from_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_from_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	from_row.add_child(_from_a)
	from_row.add_child(_from_b)
	cmd_row.add_child(from_row)
	cmd_row.add_child(_label("to a / b"))
	var to_row := HBoxContainer.new()
	_to_a = _spin(-4000.0, 4000.0, 1.0, 0.0)
	_to_b = _spin(-4000.0, 4000.0, 1.0, 0.0)
	to_row.add_child(_to_a)
	to_row.add_child(_to_b)
	cmd_row.add_child(to_row)
	var cmd_buttons := HBoxContainer.new()
	right.add_child(cmd_buttons)
	var add_cmd := Button.new()
	add_cmd.text = "添加命令"
	add_cmd.pressed.connect(_on_add_command)
	cmd_buttons.add_child(add_cmd)
	var del_cmd := Button.new()
	del_cmd.text = "删除命令"
	del_cmd.pressed.connect(_on_remove_command)
	cmd_buttons.add_child(del_cmd)
	var tl_row := HBoxContainer.new()
	right.add_child(tl_row)
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
	var undo_button := Button.new()
	undo_button.text = "撤销"
	undo_button.pressed.connect(_on_undo)
	tl_row.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "重做"
	redo_button.pressed.connect(_on_redo)
	tl_row.add_child(redo_button)
	var hint := Label.new()
	hint.text = "滚轮上下滚动 · Ctrl+滚轮缩放时间轴"
	hint.add_theme_font_size_override("font_size", 10)
	tl_row.add_child(hint)
	_timeline = TimelineScript.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2i(0, 170)
	_timeline.seek.connect(func(ms: float) -> void: seek_requested.emit(ms))
	_timeline.sprite_picked.connect(func(index: int) -> void:
		_selected = index
		_objects.select(index)
		_on_object_selected(index))
	_timeline.changed.connect(func() -> void:
		_refresh_commands()
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
	close.pressed.connect(func() -> void: hide())
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
	_undo.clear()
	_redo.clear()
	popup_centered(Vector2i(1040, 760))
	position = Vector2i(60, 40)


func _refresh_objects() -> void:
	_objects.clear()
	for sprite in _board.sprites:
		var s := sprite as Storyboard.Sprite
		_objects.add_item("%s  [%s]  %d 条命令" % [s.path.get_file() if not s.path.is_empty() else "(未填路径)", s.layer, s.commands.size()])
	_selected = -1
	_commands.clear()
	if _timeline != null:
		_timeline.set_board(_board)
		_timeline.set_selected(-1)
	_refresh_commands()


func _refresh_commands() -> void:
	_commands.clear()
	if _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	for command in sprite.commands:
		_commands.add_item(_describe(command as Storyboard.Command))


static func _describe(command: Storyboard.Command) -> String:
	var kind := command.kind_name
	var pair := "%s→%s" % [_fmt_values(command.from), _fmt_values(command.to)]
	return "%s  %dms~%dms  %s  ease%d" % [kind, int(command.start), int(command.end), pair, command.easing]


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
	_refresh_commands()


## 记录一步撤销快照（存 .osb 文本）。
func _push_undo() -> void:
	if _board == null:
		return
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


func _on_add_command() -> void:
	_push_undo()
	if _selected < 0 or _selected >= _board.sprites.size():
		_status.text = "先选一个对象"
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	var kind := String(COMMANDS[clampi(_kind_option.selected, 0, COMMANDS.size() - 1)][1])
	var start := _start_spin.value
	var end := maxf(start, _end_spin.value)
	var easing := int(_easing.value)
	var zero: Array = [0.0]
	var from_values: Array = zero
	var to_values: Array = zero
	match kind:
		"move", "vector":
			from_values = [_from_a.value, _from_b.value]
			to_values = [_to_a.value, _to_b.value]
		"colour":
			from_values = [clampf(_from_a.value / 255.0, 0.0, 1.0), clampf(_from_b.value / 255.0, 0.0, 1.0), clampf(_to_a.value / 255.0, 0.0, 1.0)]
			to_values = [clampf(_from_b.value / 255.0, 0.0, 1.0), clampf(_to_a.value / 255.0, 0.0, 1.0), clampf(_to_b.value / 255.0, 0.0, 1.0)]
		"additive":
			from_values = [1.0]
			to_values = [0.0]
		_:
			from_values = [_from_a.value]
			to_values = [_to_a.value]
	_board.add_command(sprite, kind, easing, start, end, from_values, to_values)
	_commands.add_item(_describe(sprite.commands[sprite.commands.size() - 1] as Storyboard.Command))
	_timeline.queue_redraw()
	edited.emit()
	_status.text = "已添加 %s" % kind


func _on_remove_command() -> void:
	_push_undo()
	var picked := _commands.get_selected_items()
	if picked.is_empty() or _selected < 0 or _selected >= _board.sprites.size():
		return
	var sprite := _board.sprites[_selected] as Storyboard.Sprite
	sprite.commands.remove_at(picked[0])
	sprite.build()
	_refresh_commands()
	if _timeline != null:
		_timeline.queue_redraw()
	edited.emit()


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
	saved.emit(path)
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
