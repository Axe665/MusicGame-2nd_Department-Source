extends Control

const TOOL_ORDER := [
	["select", "选择 V"],
	["boundary", "边界 B"],
	["event", "事件 E"],
]

var _app: Node = null
var _preview: Preview3D
var _canvas: ChartCanvas
var _event_track: EventTrack
var _inspector: Inspector
var _palette: NotePalette
var _validation_label: Label
var _play_button: Button
var _time_label: Label
var _progress: ProgressBar
var _beat_label: Label
var _bpm_label: Label
var _save_label: Label
var _status_u: Label
var _status_beat: Label
var _status_snap: Label
var _status_sel: Label
var _status_shape: Label
var _status_error: Label
var _toast_label: Label
var _toast_timer: Timer
var _last_transport_msec: int = 0

var _tool_buttons: Dictionary = {}
var _tool_group: ButtonGroup
var _audio: AudioStreamPlayer
var _audio_path: String = ""
var _playing: bool = false
var _rate: float = 1.0
var _loop: bool = false
var _metronome: bool = true
var _play_start_usec: int = 0
var _play_start_chart_ms: float = 0.0
var _last_beat_int: int = -1

var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _import_dialog: FileDialog
var _audio_dialog: FileDialog
var _song_dialog: SongImportDialog
var _snap_option: OptionButton
var _lbp_dialog: FileDialog
var _report_dialog: AcceptDialog
var _difficulty_dialog: ConfirmationDialog
var _difficulty_list: ItemList
var _pending_osz: String = ""
var _new_dialog: NewChartDialog
var _playtest: Playtest
var _cursor_u: float = 0.0
var _issues: Array = []


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_audio()
	_build_dialogs()
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.selection_changed.connect(_update_status)
		_app.tool_changed.connect(_on_tool_changed)
		_app.status_changed.connect(_update_status)
		_app.save_state_changed.connect(_update_status)
		_app.notice.connect(_show_toast)
		_app.validation_changed.connect(_update_validation)
		_app.snap_changed.connect(_on_snap_changed)
		_app.audio_import_requested.connect(_on_audio_import_requested)
		_app.audio_detect_requested.connect(_on_audio_detect_requested)
		_app.chart_changed.emit()
	_sync_from_app()
	for intro_control in [_canvas, _inspector, _palette, _preview]:
		intro_control.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(intro_control, "modulate:a", 1.0, 0.45).set_delay(0.05)
	set_process(true)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top := PanelContainer.new()
	top.name = "TopBar"
	top.custom_minimum_size = Vector2(0, 82)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 2)
	top.add_child(top_box)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 12)
	top_box.add_child(brand_row)
	var brand := Label.new()
	brand.text = "TAMAKI₃"
	brand.add_theme_font_override("font", UITheme.bold_font())
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", UITheme.INK)
	brand_row.add_child(brand)
	var subtitle := Label.new()
	subtitle.text = "制谱器 / CHARTER"
	subtitle.add_theme_font_override("font", UITheme.mono_font())
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", UITheme.MUTED)
	brand_row.add_child(subtitle)
	var brand_spacer := Control.new()
	brand_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_row.add_child(brand_spacer)
	brand_row.add_child(_menu("文件", [
		["新建", 0], ["打开", 1], ["保存", 2], ["另存为", 3], ["-", 0], ["导入歌曲 / 识别 BPM…", 8], ["导入 osu! (.osz)", 6], ["导出 .lbp", 7], ["-", 0], ["恢复自动保存", 4], ["-", 0], ["退出", 5],
	]))
	brand_row.add_child(_menu("编辑", [
		["撤销", 10], ["重做", 11], ["-", 0], ["删除", 12], ["取消选择", 13], ["全选可见", 14],
	]))
	brand_row.add_child(_menu("视图", [
		["显示/隐藏 HUD", 20], ["调试叠层", 21], ["波形", 22], ["从上往下写入", 25], ["-", 0], ["边界状态轨", 23], ["时间 / BPM (F6)", 24],
	]))
	brand_row.add_child(_menu("插入", [
		["Tap", 30], ["Hold", 31], ["Path", 32], ["Trace", 33], ["Anchor", 34], ["Bell", 35], ["Red", 36], ["-", 0], ["BoundaryEvent", 37], ["RingState 关键帧", 38],
	]))
	brand_row.add_child(_menu("事件", [
		["新建 BoundaryEvent", 40], ["新建 Red", 41],
	]))
	brand_row.add_child(_menu("试玩", [
		["从播放头试玩（F5）", 50], ["从头试玩（Shift+F5）", 51],
	]))
	var playtest_button := Button.new()
	playtest_button.text = "试玩 F5"
	playtest_button.add_theme_color_override("font_color", UITheme.BG)
	playtest_button.add_theme_color_override("font_hover_color", UITheme.BG)
	playtest_button.add_theme_color_override("font_pressed_color", UITheme.BG)
	playtest_button.add_theme_stylebox_override("normal", UITheme._box(UITheme.ACCENT, UITheme.ACCENT, 3, 12, 5))
	playtest_button.add_theme_stylebox_override("hover", UITheme._box(UITheme.ACCENT, Color.WHITE, 3, 12, 5))
	playtest_button.add_theme_stylebox_override("pressed", UITheme._box(UITheme.ACCENT_DARK, UITheme.ACCENT_DARK, 3, 12, 5))
	playtest_button.pressed.connect(func() -> void: _start_playtest(false))
	brand_row.add_child(playtest_button)

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 4)
	top_box.add_child(tool_row)
	_tool_group = ButtonGroup.new()
	for spec in TOOL_ORDER:
		var button := Button.new()
		button.text = spec[1]
		button.toggle_mode = true
		button.button_group = _tool_group
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_set_tool.bind(spec[0]))
		tool_row.add_child(button)
		_tool_buttons[spec[0]] = button
	var tool_spacer := Control.new()
	tool_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_row.add_child(tool_spacer)
	var snap_text := Label.new()
	snap_text.text = "SNAP"
	snap_text.add_theme_font_override("font", UITheme.mono_font())
	snap_text.add_theme_font_size_override("font_size", 9)
	snap_text.add_theme_color_override("font_color", UITheme.MUTED)
	tool_row.add_child(snap_text)
	var snap_option := OptionButton.new()
	for item in GridDivisions.LABELS:
		snap_option.add_item(item)
	var initial_division: int = _app.snap_division if _app != null else GridDivisions.DEFAULT_DIVISION
	snap_option.selected = GridDivisions.index_of(initial_division)
	snap_option.item_selected.connect(func(index: int) -> void:
		if _app != null:
			_app.set_snap_division(GridDivisions.ITEMS[index])
		_update_status()
	)
	tool_row.add_child(snap_option)
	_snap_option = snap_option

	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 0)
	root.add_child(main_row)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(340, 0)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 29.0
	main_row.add_child(preview_panel)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 6)
	preview_panel.add_child(preview_box)
	var preview_header := HBoxContainer.new()
	preview_box.add_child(preview_header)
	var preview_title := Label.new()
	preview_title.text = "预览"
	UITheme.style_section(preview_title)
	preview_header.add_child(preview_title)
	var preview_tag := Label.new()
	preview_tag.text = "3D STAGE"
	preview_tag.add_theme_font_override("font", UITheme.mono_font())
	preview_tag.add_theme_font_size_override("font_size", 9)
	preview_tag.add_theme_color_override("font_color", UITheme.CYAN)
	preview_header.add_child(preview_tag)
	var preview_spacer := Control.new()
	preview_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_header.add_child(preview_spacer)
	var hud_toggle := Button.new()
	hud_toggle.text = "HUD"
	hud_toggle.toggle_mode = true
	hud_toggle.button_pressed = true
	hud_toggle.add_theme_font_size_override("font_size", 11)
	hud_toggle.toggled.connect(func(pressed: bool) -> void:
		_app.hud_visible = pressed
		_preview.show_hud = pressed
		_update_status()
	)
	preview_header.add_child(hud_toggle)
	var debug_toggle := Button.new()
	debug_toggle.text = "调试"
	debug_toggle.toggle_mode = true
	debug_toggle.add_theme_font_size_override("font_size", 11)
	debug_toggle.toggled.connect(func(pressed: bool) -> void:
		_app.debug_overlay = pressed
		_preview.show_debug = pressed
		_update_status()
	)
	preview_header.add_child(debug_toggle)
	_preview = Preview3D.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.cursor_changed.connect(_on_cursor_changed)
	_preview.notice.connect(_show_toast)
	preview_box.add_child(_preview)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(520, 0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 47.0
	center.add_theme_constant_override("separation", 0)
	main_row.add_child(center)
	_event_track = EventTrack.new()
	_event_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_event_track)
	_canvas = ChartCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.hover_changed.connect(_on_hover_changed)
	_canvas.notice.connect(_show_toast)
	center.add_child(_canvas)
	_event_track.canvas = _canvas

	var inspector_wrap := VBoxContainer.new()
	inspector_wrap.custom_minimum_size = Vector2(310, 0)
	inspector_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_wrap.size_flags_stretch_ratio = 24.0
	inspector_wrap.add_theme_constant_override("separation", 4)
	main_row.add_child(inspector_wrap)
	_palette = NotePalette.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.add_child(_palette)
	_validation_label = Label.new()
	_validation_label.add_theme_font_size_override("font_size", 11)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.custom_minimum_size = Vector2(0, 30)
	inspector_wrap.add_child(_validation_label)
	_inspector = Inspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_wrap.add_child(_inspector)
	main_row.move_child(center, 0)
	main_row.move_child(inspector_wrap, 1)
	main_row.move_child(preview_panel, 2)

	var transport := PanelContainer.new()
	transport.name = "Transport"
	transport.custom_minimum_size = Vector2(0, 52)
	transport.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 0, 8, 6))
	root.add_child(transport)
	var transport_row := HBoxContainer.new()
	transport_row.add_theme_constant_override("separation", 10)
	transport.add_child(transport_row)
	_play_button = Button.new()
	_play_button.text = "▶"
	_play_button.custom_minimum_size = Vector2(42, 30)
	_play_button.pressed.connect(_toggle_play)
	transport_row.add_child(_play_button)
	var stop_button := Button.new()
	stop_button.text = "■"
	stop_button.custom_minimum_size = Vector2(38, 30)
	stop_button.pressed.connect(_stop_play)
	transport_row.add_child(stop_button)
	_time_label = Label.new()
	UITheme.style_mono(_time_label, 12, UITheme.INK)
	_time_label.custom_minimum_size = Vector2(150, 0)
	transport_row.add_child(_time_label)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.custom_minimum_size = Vector2(120, 8)
	transport_row.add_child(_progress)
	_beat_label = Label.new()
	UITheme.style_mono(_beat_label, 12, UITheme.GOLD)
	_beat_label.custom_minimum_size = Vector2(92, 0)
	transport_row.add_child(_beat_label)
	_bpm_label = Label.new()
	UITheme.style_mono(_bpm_label, 12, UITheme.MUTED)
	transport_row.add_child(_bpm_label)
	var rate_option := OptionButton.new()
	for item in ["0.5×", "0.75×", "1.0×", "1.25×", "1.5×"]:
		rate_option.add_item(item)
	rate_option.selected = 2
	rate_option.item_selected.connect(func(index: int) -> void:
		_rate = [0.5, 0.75, 1.0, 1.25, 1.5][index]
		if _playing:
			var beat: float = _app.playhead_beat
			_stop_play()
			_start_play(beat)
	)
	transport_row.add_child(rate_option)
	var loop_check := CheckBox.new()
	loop_check.text = "循环"
	loop_check.toggled.connect(func(pressed: bool) -> void: _loop = pressed)
	transport_row.add_child(loop_check)
	var metro_check := CheckBox.new()
	metro_check.text = "节拍器"
	metro_check.button_pressed = true
	metro_check.toggled.connect(func(pressed: bool) -> void: _metronome = pressed)
	transport_row.add_child(metro_check)
	var transport_spacer := Control.new()
	transport_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transport_row.add_child(transport_spacer)
	_save_label = Label.new()
	UITheme.style_mono(_save_label, 11, UITheme.MUTED)
	transport_row.add_child(_save_label)

	var status := PanelContainer.new()
	status.name = "StatusBar"
	status.custom_minimum_size = Vector2(0, 24)
	status.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 0, 6, 2))
	root.add_child(status)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	status.add_child(status_row)
	_status_u = _status_label("u 0.0°")
	_status_beat = _status_label("bar 0:0:4")
	_status_snap = _status_label("吸附 1/4")
	_status_sel = _status_label("选中 0")
	_status_shape = _status_label("边界 S0")
	_status_error = _status_label("校验 —")
	for label in [_status_u, _status_beat, _status_snap, _status_sel, _status_shape, _status_error]:
		status_row.add_child(label)
	var status_spacer := Control.new()
	status_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_spacer)
	_toast_label = _status_label("")
	_toast_label.add_theme_color_override("font_color", UITheme.CYAN)
	status_row.add_child(_toast_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 3.0
	_toast_timer.timeout.connect(func() -> void: _toast_label.text = "")
	add_child(_toast_timer)



func _status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.mono_font())
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	return label


func _menu(title: String, items: Array) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = title
	menu.add_theme_font_size_override("font_size", 12)
	var popup := menu.get_popup()
	for item in items:
		if item[0] == "-":
			popup.add_separator()
		else:
			popup.add_item(item[0], int(item[1]))
	popup.id_pressed.connect(_on_menu)
	return menu


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "EditorAudio"
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.filters = PackedStringArray(["*.json ; Tamaki 谱面"])
	_open_dialog.title = "打开谱面"
	_open_dialog.file_selected.connect(func(path: String) -> void:
		_app.load_chart(path)
		_sync_from_app()
	)
	add_child(_open_dialog)
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.filters = PackedStringArray(["*.json ; Tamaki 谱面"])
	_save_dialog.title = "另存为"
	_save_dialog.current_file = "chart.json"
	_save_dialog.file_selected.connect(func(path: String) -> void:
		if not path.to_lower().ends_with(".json"):
			path += ".json"
		_app.save_chart_as(path)
		_sync_from_app()
	)
	add_child(_save_dialog)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.osz ; osu! 谱面包"])
	_import_dialog.title = "导入 osu!std / osu!taiko"
	_import_dialog.file_selected.connect(_on_import_osz_selected)
	add_child(_import_dialog)
	_audio_dialog = FileDialog.new()
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_dialog.filters = PackedStringArray([
		"*.wav, *.mp3, *.ogg, *.flac, *.m4a, *.aac, *.opus ; 音频文件",
		"*.* ; 全部文件",
	])
	_audio_dialog.title = "导入歌曲（自动识别 BPM 与 offset）"
	_audio_dialog.file_selected.connect(_on_audio_selected)
	add_child(_audio_dialog)
	_song_dialog = SongImportDialog.new()
	_song_dialog.applied.connect(_on_song_timing_applied)
	add_child(_song_dialog)
	_lbp_dialog = FileDialog.new()
	_lbp_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_lbp_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_lbp_dialog.filters = PackedStringArray(["*.lbp ; Tamaki LBP v2"])
	_lbp_dialog.title = "导出 .lbp"
	_lbp_dialog.current_file = "chart.lbp"
	_lbp_dialog.file_selected.connect(func(path: String) -> void:
		if not path.to_lower().ends_with(".lbp"):
			path += ".lbp"
		_app.export_lbp(path)
	)
	add_child(_lbp_dialog)
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = "osu! 导入报告"
	_report_dialog.dialog_autowrap = true
	add_child(_report_dialog)
	_difficulty_dialog = ConfirmationDialog.new()
	_difficulty_dialog.title = "选择 osu! 难度"
	_difficulty_dialog.dialog_text = "压缩包内有多个 .osu，请选择要导入的难度："
	_difficulty_dialog.ok_button_text = "导入"
	_difficulty_dialog.cancel_button_text = "取消"
	var diff_box := VBoxContainer.new()
	diff_box.add_theme_constant_override("separation", 6)
	_difficulty_list = ItemList.new()
	_difficulty_list.custom_minimum_size = Vector2(520, 240)
	diff_box.add_child(_difficulty_list)
	_difficulty_dialog.add_child(diff_box)
	_difficulty_dialog.confirmed.connect(func() -> void:
		var selected := _difficulty_list.get_selected_items()
		if selected.size() > 0 and not _pending_osz.is_empty():
			_import_osz(_pending_osz, selected[0])
	)
	add_child(_difficulty_dialog)
	_new_dialog = NewChartDialog.new()
	_new_dialog.created.connect(func(meta: Dictionary) -> void:
		_app.new_chart(meta)
		_new_dialog.hide()
		_sync_from_app()
	)
	add_child(_new_dialog)
	var charts_dir := ProjectSettings.globalize_path("user://charts")
	DirAccess.make_dir_recursive_absolute(charts_dir)


func _sync_from_app() -> void:
	if _app == null or _app.chart == null:
		return
	_preview.show_hud = _app.hud_visible
	_preview.use_3d_ring = _app.use_3d_ring
	_preview.mouse_tilt = _app.mouse_tilt
	_preview.show_debug = _app.debug_overlay
	_canvas.px_per_beat = _app.zoom_px_per_beat
	_ensure_audio()
	_sync_tools()
	_update_transport()
	_update_status()
	_update_validation(Validator.validate(_app.chart))


func _ensure_audio() -> void:
	if _app == null or _app.chart == null:
		return
	var path: String = _app.chart.audio_path
	if path == _audio_path:
		return
	_audio_path = path
	_audio.stop()
	_playing = false
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path() and not _app.chart_path.is_empty():
		resolved = ChartIO.resolve_path(_app.chart_path, path)
	var prepared := MediaIO.prepare_audio(resolved)
	if prepared.is_empty():
		_audio.stream = null
		_show_toast("音频不可用：%s" % MediaIO.last_error, "warning")
		return
	var stream := ChartIO.audio_stream_from_path(prepared)
	_audio.stream = stream if stream is AudioStream else null
	if _audio.stream == null:
		_show_toast("音频不可用：预览使用系统时钟。", "warning")


func _sync_tools() -> void:
	for key in _tool_buttons.keys():
		_tool_buttons[key].button_pressed = (_app.tool == key)


func _on_chart_changed() -> void:
	_ensure_audio()
	_update_transport()
	_update_status()


func _on_chart_live_changed() -> void:
	_update_transport()
	_update_status()


func _on_playhead_changed(_beat: float) -> void:
	_update_transport()


func _on_tool_changed(_tool: String) -> void:
	_sync_tools()
	_update_status()


func _on_cursor_changed(u: float, _valid: bool) -> void:
	_cursor_u = u
	_update_status()


func _on_hover_changed(_u: float, _beat: float) -> void:
	pass


func _set_tool(tool: String) -> void:
	_app.set_tool(tool)
	_sync_tools()
	if tool == "boundary":
		_show_toast("边界模式：在预览中拖动控制点；双击分段拆分。", "info")
	elif tool == "trace":
		_show_toast("Trace：在预览窗拖拽绘制二维擦带。", "info")
	elif tool == "red":
		_show_toast("Red：在预览窗按住横向拖角度、纵向拖时长（最多 4 拍）。", "info")


func _toggle_play() -> void:
	if _playing:
		_stop_play()
	else:
		_start_play(_app.playhead_beat)


func _start_play(beat: float) -> void:
	if _app == null or _app.chart == null:
		return
	_ensure_audio()
	_play_start_chart_ms = _app.chart.timing.beat_to_chart_ms(beat)
	_play_start_usec = Time.get_ticks_usec()
	_last_beat_int = -1
	if _audio.stream != null:
		_audio.pitch_scale = _rate
		var from_sec := maxf(0.0, (_play_start_chart_ms - _app.chart.offset_ms) / 1000.0)
		_audio.play(from_sec)
	_playing = true
	_preview.playing = true
	_play_button.text = "❚❚"
	_app.set_playhead(beat)


func _stop_play() -> void:
	if _audio != null:
		_audio.stop()
	_playing = false
	if _preview != null:
		_preview.playing = false
	if _play_button != null:
		_play_button.text = "▶"


func _on_audio_finished() -> void:
	if not _playing:
		return
	if _loop:
		_start_play(0.0)
	else:
		_stop_play()


func _process(_delta: float) -> void:
	if _app == null or _app.chart == null:
		return
	if _playing:
		var chart_ms := 0.0
		if _audio.stream != null and _audio.playing:
			chart_ms = (_audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0 + _app.chart.offset_ms
		else:
			chart_ms = _play_start_chart_ms + float(Time.get_ticks_usec() - _play_start_usec) / 1000.0 * _rate
		var beat: float = _app.chart.timing.chart_ms_to_beat(chart_ms)
		_app.set_playhead(beat)
		var beat_int := floori(beat)
		if _metronome and beat_int != _last_beat_int and _beat_label != null:
			_last_beat_int = beat_int
			_beat_label.add_theme_color_override("font_color", UITheme.CORAL)
			create_tween().tween_interval(0.08).finished.connect(func() -> void:
				if _beat_label != null:
					_beat_label.add_theme_color_override("font_color", UITheme.GOLD)
			)
		if beat >= _app.chart.duration_beats() + 2.0:
			_stop_play()


func _update_transport(force: bool = false) -> void:
	if _app == null or _app.chart == null or _time_label == null:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_transport_msec < 50:
		return
	_last_transport_msec = now
	var total_ms: float = _app.chart.timing.beat_to_chart_ms(_app.chart.duration_beats())
	var current_ms: float = _app.chart.timing.beat_to_chart_ms(_app.playhead_beat)
	_time_label.text = "%s / %s" % [_format_ms(current_ms), _format_ms(total_ms)]
	_progress.value = 100.0 * _app.playhead_beat / maxf(1.0, _app.chart.duration_beats())
	_beat_label.text = _app.chart.timing.format_beat(_app.playhead_beat)
	_bpm_label.text = "%.1f BPM" % _app.chart.timing.bpm_at(_app.playhead_beat)
	_save_label.text = ("● 未保存" if _app.dirty else "已保存") + ("  %s" % _app.chart_path.get_file() if not _app.chart_path.is_empty() else "")


func _update_status() -> void:
	if _app == null or _app.chart == null:
		return
	_preview.use_3d_ring = _app.use_3d_ring
	_preview.mouse_tilt = _app.mouse_tilt
	if _status_u != null:
		_status_u.text = "u %.1f°" % (_cursor_u * 360.0)
		_status_beat.text = "bar " + _app.chart.timing.format_beat(_app.playhead_beat)
		_status_snap.text = "吸附 " + GridDivisions.label(_app.snap_division) + ("" if _app.time_flows_down else " · 反向")
		_status_sel.text = "选中 %d" % _app.selected_notes.size()
		_status_shape.text = "边界 " + _app.chart.default_shape_id
		var errors: Array = Validator.errors(_issues)
		var warnings: Array = Validator.warnings(_issues)
		if not errors.is_empty():
			_status_error.text = "校验 %d 错误" % errors.size()
			_status_error.add_theme_color_override("font_color", UITheme.RED)
		elif not warnings.is_empty():
			_status_error.text = "校验 %d 警告" % warnings.size()
			_status_error.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			_status_error.text = "校验通过"
			_status_error.add_theme_color_override("font_color", UITheme.GREEN)
	_update_transport(true)


func _update_validation(issues: Array) -> void:
	_issues = issues
	if _validation_label == null:
		return
	var errors: Array = issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "error")
	var warnings: Array = issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "warning")
	if not errors.is_empty():
		_validation_label.text = "● %s" % errors[0].get("message", "")
		_validation_label.add_theme_color_override("font_color", UITheme.RED)
	elif not warnings.is_empty():
		_validation_label.text = "● %s" % warnings[0].get("message", "")
		_validation_label.add_theme_color_override("font_color", UITheme.GOLD)
	else:
		_validation_label.text = "● 校验通过"
		_validation_label.add_theme_color_override("font_color", UITheme.GREEN)
	_update_status()


func _on_snap_changed(division: int) -> void:
	if _snap_option == null:
		return
	var index := GridDivisions.index_of(division)
	if _snap_option.selected != index:
		_snap_option.select(index)


func _on_audio_import_requested() -> void:
	_audio_dialog.popup_centered_ratio(0.8)


func _on_audio_detect_requested(path: String) -> void:
	if path.strip_edges().is_empty():
		_audio_dialog.popup_centered_ratio(0.8)
		return
	_song_dialog.open_for(path)


func _on_audio_selected(path: String) -> void:
	_song_dialog.open_for(path)


func _on_song_timing_applied() -> void:
	_sync_from_app()
	_show_toast("已写入识别结果；可在“时间”页继续微调 BPM / offset。", "info")


func _on_import_osz_selected(path: String) -> void:
	var difficulties := OsuIO.list_osz_difficulties(path)
	if difficulties.is_empty():
		_show_toast("osu! 导入失败：%s" % OsuIO.last_error, "error")
		return
	if difficulties.size() == 1:
		_import_osz(path, 0)
		return
	_pending_osz = path
	_difficulty_list.clear()
	for item in difficulties:
		_difficulty_list.add_item("%s — %s  [%s]  %s" % [
			String(item.get("title", "")), String(item.get("version", "")),
			"taiko" if int(item.get("mode", 0)) == 1 else "std",
			String(item.get("creator", "")),
		])
	_difficulty_list.select(0)
	_difficulty_dialog.popup_centered_ratio(0.58)


func _import_osz(path: String, difficulty_index: int) -> void:
	if _app.import_osz(path, difficulty_index):
		_sync_from_app()
		_show_report(_app.last_import_report)


func _show_report(text: String) -> void:
	if _report_dialog == null or text.is_empty():
		return
	_report_dialog.dialog_text = text
	_report_dialog.popup_centered_ratio(0.62)


func _show_toast(message: String, level: String = "info") -> void:
	if _toast_label == null:
		return
	_toast_label.text = message
	_toast_label.add_theme_color_override("font_color", UITheme.RED if level == "error" else (UITheme.GOLD if level == "warning" else UITheme.CYAN))
	if _toast_timer != null:
		_toast_timer.start()


func _format_ms(ms: float) -> String:
	var value := maxi(0, int(ms))
	var minutes := value / 60000
	var seconds := (value % 60000) / 1000
	var millis := value % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, millis]


func _on_menu(id: int) -> void:
	match id:
		0:
			_new_dialog.popup_centered_ratio(0.62)
		1:
			_open_dialog.popup_centered_ratio(0.75)
		2:
			_save()
		3:
			_save_dialog.popup_centered_ratio(0.75)
		4:
			_app.load_autosave()
			_sync_from_app()
		6:
			_import_dialog.popup_centered_ratio(0.75)
		7:
			_lbp_dialog.popup_centered_ratio(0.75)
		8:
			_audio_dialog.popup_centered_ratio(0.8)
		5:
			get_tree().quit()
		10:
			_app.undo_chart()
			_sync_from_app()
		11:
			_app.redo_chart()
			_sync_from_app()
		12:
			_canvas._delete_selection()
		13:
			_app.clear_selection()
		14:
			_canvas._select_visible()
		20:
			_app.hud_visible = not _app.hud_visible
			_preview.show_hud = _app.hud_visible
		21:
			_app.debug_overlay = not _app.debug_overlay
			_preview.show_debug = _app.debug_overlay
		22:
			_app.waveform_visible = not _app.waveform_visible
		25:
			_app.set_time_flows_down(not _app.time_flows_down)
		23:
			_show_toast("边界状态轨：RingState 关键帧在视图页编辑。", "info")
		24:
			_inspector.current_tab = 5
		30, 31, 32, 33, 34, 35, 36:
			_set_tool(["tap", "hold", "path", "trace", "anchor", "bell", "red"][id - 30])
		37:
			_inspector._add_event()
		38:
			_inspector._add_view_state()
		40:
			_inspector._add_event()
		41:
			_set_tool("red")
		50:
			_start_playtest(false)
		51:
			_start_playtest(true)
	_update_status()


func _save() -> void:
	if _app.chart_path.is_empty():
		_save_dialog.popup_centered_ratio(0.75)
	else:
		_app.save_chart()
		_sync_from_app()


func _start_playtest(from_start: bool) -> void:
	if _app == null or _app.chart == null or _playtest != null:
		return
	var errors := Validator.errors(Validator.validate(_app.chart))
	if not errors.is_empty():
		_show_toast("先修复 %d 个校验错误再试玩：%s" % [errors.size(), errors[0].get("message", "")], "error")
		return
	_stop_play()
	# The full-screen playtest covers the editor. Suspend its preview and input
	# rather than continuing to render a second 3D scene underneath it.
	var editor_root := get_node("Root") as Control
	editor_root.hide()
	editor_root.process_mode = Node.PROCESS_MODE_DISABLED
	_preview.set_suspended(true)
	_playtest = Playtest.new()
	add_child(_playtest)
	_playtest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_playtest.setup(_app.chart, 0.0 if from_start else _app.playhead_beat, _app.chart_path)
	_playtest.exit_requested.connect(_end_playtest)


func _end_playtest() -> void:
	if _playtest != null:
		_playtest.queue_free()
		_playtest = null
	var editor_root := get_node("Root") as Control
	editor_root.process_mode = Node.PROCESS_MODE_INHERIT
	editor_root.show()
	_preview.set_suspended(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sync_from_app()


func _unhandled_input(event: InputEvent) -> void:
	if _playtest != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is SpinBox or focus is TextEdit:
			if event.keycode != KEY_F5 and event.keycode != KEY_F6:
				return
		match event.keycode:
			KEY_SPACE:
				if event.ctrl_pressed:
					_loop = not _loop
					_show_toast("循环 %s" % ("开" if _loop else "关"), "info")
				elif event.shift_pressed:
					_start_play(0.0)
				else:
					_toggle_play()
				accept_event()
			KEY_S:
				if event.ctrl_pressed:
					if event.shift_pressed:
						_save_dialog.popup_centered_ratio(0.75)
					else:
						_save()
					accept_event()
			KEY_O:
				if event.ctrl_pressed:
					_open_dialog.popup_centered_ratio(0.75)
					accept_event()
			KEY_N:
				if event.ctrl_pressed:
					_new_dialog.popup_centered_ratio(0.62)
					accept_event()
			KEY_Z:
				if event.ctrl_pressed:
					_app.undo_chart()
					_sync_from_app()
					accept_event()
			KEY_Y:
				if event.ctrl_pressed:
					_app.redo_chart()
					_sync_from_app()
					accept_event()
			KEY_F5:
				_start_playtest(event.shift_pressed)
				accept_event()
			KEY_F6:
				_inspector.current_tab = 5
				accept_event()
			KEY_H:
				_app.hud_visible = not _app.hud_visible
				_preview.show_hud = _app.hud_visible
				_update_status()
				accept_event()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				_set_tool(["tap", "hold", "path", "trace", "anchor", "bell", "red"][event.keycode - KEY_1])
				accept_event()
			KEY_B:
				_set_tool("boundary")
				accept_event()
			KEY_E:
				_set_tool("event")
				accept_event()
			KEY_DELETE:
				_canvas._delete_selection()
				accept_event()
			KEY_ESCAPE:
				if _playing:
					_stop_play()
				else:
					_app.clear_selection()
				accept_event()
