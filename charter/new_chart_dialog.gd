class_name NewChartDialog
extends ConfirmationDialog

signal created(meta: Dictionary)

var _title: LineEdit
var _artist: LineEdit
var _creator: LineEdit
var _difficulty: LineEdit
var _bpm: SpinBox
var _offset: SpinBox
var _beats_per_bar: SpinBox
var _audio: LineEdit
var _video: LineEdit
var _error: Label
var _audio_dialog: FileDialog
var _video_dialog: FileDialog


func _ready() -> void:
	title = "新建谱面"
	ok_button_text = "创建"
	cancel_button_text = "取消"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 460)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	var host := get_label().get_parent()
	host.add_child(scroll)
	host.move_child(scroll, 0)
	_title = _line(page, "标题", "未命名谱面")
	_artist = _line(page, "曲师", "")
	_creator = _line(page, "谱师", "")
	_difficulty = _line(page, "难度", "Normal")
	_bpm = _spin(page, "BPM", 120.0, 20.0, 600.0, 0.1)
	_offset = _spin(page, "offset ms", 0.0, -10000.0, 10000.0, 1.0)
	_beats_per_bar = _spin(page, "拍号分子", 4.0, 1.0, 16.0, 1.0)
	_audio = _line(page, "音频（必填）", "")
	var audio_button := Button.new()
	audio_button.text = "浏览"
	audio_button.pressed.connect(_pick_audio)
	_audio.get_parent().add_child(audio_button)
	_video = _line(page, "视频（可选 .ogv）", "")
	var video_button := Button.new()
	video_button.text = "浏览"
	video_button.pressed.connect(_pick_video)
	_video.get_parent().add_child(video_button)
	_error = Label.new()
	_error.add_theme_color_override("font_color", UITheme.RED)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_error)
	var hint := Label.new()
	hint.text = "音频是唯一判定时钟；主流音频直接读取或自动转码。视频支持 .ogv/.mp4/.webm/.mov/.mkv，自动转 Ogg Theora。"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(hide)
	actions.add_child(cancel_button)
	var create_button := Button.new()
	create_button.text = "创建"
	create_button.pressed.connect(_on_confirmed)
	actions.add_child(create_button)
	get_ok_button().visible = false
	get_cancel_button().visible = false


func _line(page: VBoxContainer, label_text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	page.add_child(row)
	return edit


func _spin(page: VBoxContainer, label_text: String, value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	page.add_child(row)
	return spin


func _pick_audio() -> void:
	_audio_dialog = FileDialog.new()
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_dialog.filters = PackedStringArray(["*.wav ; WAV", "*.ogg ; OGG", "*.mp3 ; MP3", "*.flac ; FLAC", "*.m4a ; M4A", "*.aac ; AAC", "*.opus ; OPUS", "*.webm ; WebM", "*.mp4 ; MP4"])
	_audio_dialog.file_selected.connect(func(path: String) -> void:
		var resolved := path
		if not path.begins_with("res://") and not path.begins_with("user://"):
			resolved = ChartIO.copy_audio_to_user(path)
		if resolved.is_empty():
			_error.text = "音频复制失败：请检查文件是否存在。"
		else:
			_audio.text = resolved
		_audio_dialog.queue_free()
		_audio_dialog = null
	)
	_audio_dialog.canceled.connect(func() -> void:
		_audio_dialog.queue_free()
		_audio_dialog = null
	)
	add_child(_audio_dialog)
	_audio_dialog.popup_centered_ratio(0.6)


func _pick_video() -> void:
	_video_dialog = FileDialog.new()
	_video_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_video_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_video_dialog.filters = PackedStringArray(["*.ogv ; Ogg Theora", "*.mp4 ; MP4", "*.webm ; WebM", "*.mov ; MOV", "*.mkv ; MKV", "*.avi ; AVI"])
	_video_dialog.file_selected.connect(func(path: String) -> void:
		_video.text = path
		_video_dialog.queue_free()
		_video_dialog = null
	)
	_video_dialog.canceled.connect(func() -> void:
		_video_dialog.queue_free()
		_video_dialog = null
	)
	add_child(_video_dialog)
	_video_dialog.popup_centered_ratio(0.6)


func _on_confirmed() -> void:
	if _audio.text.strip_edges().is_empty():
		_error.text = "音频为必填项。"
		return
	var prepared := MediaIO.prepare_audio(_audio.text.strip_edges())
	if prepared.is_empty():
		_error.text = "无法读取音频：%s（%s）" % [_audio.text, MediaIO.last_error]
		return
	var bpm := _bpm.value
	if bpm < 20.0 or bpm > 600.0:
		_error.text = "BPM 必须在 20–600 之间。"
		return
	created.emit({
		"title": _title.text.strip_edges(),
		"artist": _artist.text.strip_edges(),
		"creator": _creator.text.strip_edges(),
		"version": _difficulty.text.strip_edges(),
		"difficulty": _difficulty.text.strip_edges(),
		"bpm": bpm,
		"offset_ms": _offset.value,
		"beats_per_bar": int(_beats_per_bar.value),
		"audio": _audio.text.strip_edges(),
		"video": _video.text.strip_edges(),
	})
	hide()
