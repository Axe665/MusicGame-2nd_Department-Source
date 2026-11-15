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
var _analysis_label: Label
var _analysis_thread: Thread
var _analysis_pending: String = ""


func _ready() -> void:
	title = "新建谱面"
	ok_button_text = "创建"
	cancel_button_text = "取消"
	set_process(true)
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
	_bpm = _spin(page, "BPM", 120.0, 20.0, 600.0, 0.001)
	_offset = _spin(page, "offset ms", 0.0, -10000.0, 10000.0, 0.001)
	_beats_per_bar = _spin(page, "拍号分子", 4.0, 1.0, 16.0, 1.0)
	_audio = _line(page, "音频（必填）", "")
	var audio_button := Button.new()
	audio_button.text = "浏览"
	audio_button.pressed.connect(_pick_audio)
	_audio.get_parent().add_child(audio_button)
	_analysis_label = Label.new()
	_analysis_label.text = ""
	_analysis_label.add_theme_font_size_override("font_size", 11)
	_analysis_label.add_theme_color_override("font_color", UITheme.MUTED)
	_analysis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_analysis_label.custom_minimum_size = Vector2(0, 18)
	page.add_child(_analysis_label)
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
	hint.text = "选择音频后自动测量 BPM 与 offset：BPM 最多保留 3 位小数，只有 1 位小数时四舍五入取整；offset 保留 3 位小数。视频支持 .ogv/.mp4/.webm/.mov/.mkv，自动转 Ogg Theora。"
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
			_error.text = ""
			_start_analysis(resolved)
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


func _start_analysis(path: String) -> void:
	if _analysis_thread != null:
		_analysis_pending = path
		return
	_analysis_label.text = "正在分析 BPM / offset…"
	_analysis_label.add_theme_color_override("font_color", UITheme.MUTED)
	_analysis_thread = Thread.new()
	var error := _analysis_thread.start(Callable(self, "_analysis_worker").bind(path))
	if error != OK:
		_analysis_thread = null
		_analysis_label.text = "无法启动分析线程（错误 %d）" % error
		_analysis_label.add_theme_color_override("font_color", UITheme.RED)


func _analysis_worker(path: String) -> Dictionary:
	var samples := AudioPCM.load_mono(path)
	if samples.is_empty():
		return {
			"ok": false,
			"error": AudioPCM.last_error,
			"bpm": 0.0,
			"offset_ms": 0.0,
			"duration_ms": 0.0,
			"confidence": 0.0,
			"beats": 0,
		}
	return BpmDetect.analyze(samples, float(AudioPCM.DEFAULT_RATE))


func _process(_delta: float) -> void:
	if _analysis_thread == null:
		return
	if _analysis_thread.is_alive():
		return
	var result: Dictionary = _analysis_thread.wait_to_finish()
	_analysis_thread = null
	if not _analysis_pending.is_empty():
		var next := _analysis_pending
		_analysis_pending = ""
		_start_analysis(next)
		return
	_apply_analysis(result)


func _bpm_step(value: float) -> float:
	var fraction := absf(value - roundf(value))
	var thousandths := int(roundf(fraction * 1000.0))
	if thousandths == 0:
		return 1.0
	if thousandths % 10 == 0:
		return 0.01
	return 0.001


func _apply_analysis(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_analysis_label.text = "自动测量失败：%s；可手动填写 BPM / offset。" % String(result.get("error", "未知原因"))
		_analysis_label.add_theme_color_override("font_color", UITheme.RED)
		return
	var bpm := TimingMap.normalize_bpm(float(result.get("bpm", _bpm.value)))
	var offset := TimingMap.normalize_offset_ms(float(result.get("offset_ms", _offset.value)))
	_bpm.step = _bpm_step(bpm)
	_bpm.value = clampf(bpm, _bpm.min_value, _bpm.max_value)
	_offset.step = 0.001
	_offset.value = clampf(offset, _offset.min_value, _offset.max_value)
	var confidence := int(round(float(result.get("confidence", 0.0)) * 100.0))
	var duration := float(result.get("duration_ms", 0.0)) / 1000.0
	_analysis_label.text = "自动测量：BPM %.3f，offset %.3f ms，置信度 %d%%，时长 %.2fs" % [
		_bpm.value, _offset.value, confidence, duration,
	]
	_analysis_label.add_theme_color_override("font_color", UITheme.CYAN)


func _exit_tree() -> void:
	if _analysis_thread != null:
		_analysis_thread.wait_to_finish()
		_analysis_thread = null


func _on_confirmed() -> void:
	if _analysis_thread != null or not _analysis_pending.is_empty():
		_error.text = "正在分析音频，请稍候…"
		return
	if _audio.text.strip_edges().is_empty():
		_error.text = "音频为必填项。"
		return
	var audio_path := _audio.text.strip_edges()
	var prepared := audio_path
	if not MediaIO.is_native_audio(audio_path) and not FileAccess.file_exists(MediaIO.audio_cache_path(audio_path)):
		_error.text = "正在转码音频…"
		prepared = await MediaIO.prepare_audio_async(audio_path, get_tree())
	else:
		prepared = MediaIO.prepare_audio(audio_path)
	if not is_inside_tree():
		return
	if prepared.is_empty():
		_error.text = "无法读取音频：%s（%s）" % [_audio.text, MediaIO.last_error]
		return
	var bpm := TimingMap.normalize_bpm(_bpm.value)
	var offset := TimingMap.normalize_offset_ms(_offset.value)
	if bpm < 20.0 or bpm > 600.0:
		_error.text = "BPM 必须在 20–600 之间。"
		return
	_bpm.step = _bpm_step(bpm)
	_bpm.value = bpm
	_offset.step = 0.001
	_offset.value = offset
	created.emit({
		"title": _title.text.strip_edges(),
		"artist": _artist.text.strip_edges(),
		"creator": _creator.text.strip_edges(),
		"version": _difficulty.text.strip_edges(),
		"difficulty": _difficulty.text.strip_edges(),
		"bpm": bpm,
		"offset_ms": offset,
		"beats_per_bar": int(_beats_per_bar.value),
		"audio": _audio.text.strip_edges(),
		"video": _video.text.strip_edges(),
	})
	hide()
