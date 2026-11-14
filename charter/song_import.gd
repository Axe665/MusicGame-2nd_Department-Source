class_name SongImportDialog
extends AcceptDialog

## Import-a-song dialog: sets the chart audio path, decodes the track in a
## worker thread, shows the detected BPM / offset / confidence, and writes the
## result only when the chart author confirms it.
##
## The detected numbers are a starting point, never an automatic edit: half /
## double-time songs, a pickup intro or a drum-less verse all produce plausible
## but wrong answers, so the dialog keeps BPM and offset editable, offers x2 / /2
## shortcuts and a re-run button.

signal applied

var _app: Node = null
var _path: String = ""
var _thread: Thread = null
var _running: bool = false
var _restart_pending: bool = false
var _result: Dictionary = {}
var _status: Label
var _detail: Label
var _bpm_spin: SpinBox
var _offset_spin: SpinBox
var _ffmpeg_edit: LineEdit
var _apply_button: Button
var _browse_dialog: FileDialog
var _cancel_button: Button
var _stream_ms: float = -1.0
var _stream_error: String = ""
var _read_ok: bool = false


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	title = "导入歌曲：自动识别 BPM / offset"
	ok_button_text = "应用"
	min_size = Vector2i(520, 300)
	exclusive = true
	_build()
	confirmed.connect(_commit_all)
	set_process(true)


func _build() -> void:
	_apply_button = get_ok_button()
	_apply_button.disabled = true
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(480, 0)
	add_child(content)

	_status = Label.new()
	UITheme.style_label(_status, 13, UITheme.INK)
	_status.text = "选择音频后自动分析"
	content.add_child(_status)

	_detail = Label.new()
	UITheme.style_mono(_detail, 11, UITheme.MUTED)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 32)
	content.add_child(_detail)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)

	grid.add_child(_grid_label("基准 BPM"))
	_bpm_spin = SpinBox.new()
	_bpm_spin.min_value = 20.0
	_bpm_spin.max_value = 600.0
	_bpm_spin.step = 0.1
	_bpm_spin.value = 120.0
	_bpm_spin.custom_minimum_size = Vector2(160, 0)
	_bpm_spin.value_changed.connect(func(_value: float) -> void: _refresh_checks())
	grid.add_child(_bpm_spin)

	grid.add_child(_grid_label("offset ms"))
	_offset_spin = SpinBox.new()
	_offset_spin.min_value = -10000.0
	_offset_spin.max_value = 10000.0
	_offset_spin.step = 1.0
	_offset_spin.value = 0.0
	_offset_spin.custom_minimum_size = Vector2(160, 0)
	_offset_spin.value_changed.connect(func(_value: float) -> void: _refresh_checks())
	grid.add_child(_offset_spin)

	var tempo_row := HBoxContainer.new()
	tempo_row.add_theme_constant_override("separation", 6)
	content.add_child(tempo_row)
	var double_button := Button.new()
	double_button.text = "×2"
	double_button.tooltip_text = "检测结果偏慢时把 BPM 翻倍"
	double_button.pressed.connect(func() -> void: _scale_tempo(2.0))
	tempo_row.add_child(double_button)
	var half_button := Button.new()
	half_button.text = "÷2"
	half_button.tooltip_text = "检测结果偏快时把 BPM 减半"
	half_button.pressed.connect(func() -> void: _scale_tempo(0.5))
	tempo_row.add_child(half_button)
	var rerun_button := Button.new()
	rerun_button.text = "重新检测"
	rerun_button.pressed.connect(_restart)
	tempo_row.add_child(rerun_button)
	var bpm_only_button := Button.new()
	bpm_only_button.text = "只取 BPM"
	bpm_only_button.tooltip_text = "只写入基准 BPM，保留现有 offset"
	bpm_only_button.pressed.connect(func() -> void: _commit(false))
	tempo_row.add_child(bpm_only_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tempo_row.add_child(spacer)
	_cancel_button = Button.new()
	_cancel_button.text = "取消"
	_cancel_button.pressed.connect(func() -> void: hide())
	tempo_row.add_child(_cancel_button)

	var ffmpeg_row := HBoxContainer.new()
	ffmpeg_row.add_theme_constant_override("separation", 6)
	content.add_child(ffmpeg_row)
	ffmpeg_row.add_child(_grid_label("ffmpeg"))
	_ffmpeg_edit = LineEdit.new()
	_ffmpeg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ffmpeg_edit.placeholder_text = "ffmpeg（PATH 中或完整路径）"
	_ffmpeg_edit.text = String(_app.ffmpeg_path) if _app != null else "ffmpeg"
	_ffmpeg_edit.text_submitted.connect(_on_ffmpeg_submitted)
	ffmpeg_row.add_child(_ffmpeg_edit)
	var browse_button := Button.new()
	browse_button.text = "浏览"
	browse_button.pressed.connect(_browse_ffmpeg)
	ffmpeg_row.add_child(browse_button)

	var hint := Label.new()
	UITheme.style_label(hint, 11, UITheme.FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "支持 WAV / OGG / MP3 / FLAC；FLAC 等压缩格式通过 ffmpeg 解码一次并缓存。应用条件：BPM 检测成功、offset 校准成功、播放流时长与解码音频时长一致。"
	content.add_child(hint)


func _grid_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	UITheme.style_label(label, 12, UITheme.MUTED)
	label.custom_minimum_size = Vector2(78, 0)
	return label


func open_for(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	_path = path
	_result = {}
	_stream_ms = -1.0
	_stream_error = ""
	_read_ok = false
	if _apply_button != null:
		_apply_button.disabled = true
	_status.text = "分析中：%s" % path.get_file()
	_status.add_theme_color_override("font_color", UITheme.INK)
	_detail.text = "解码音频 → 起始包络 → 自相关 → 拍点跟踪"
	popup_centered()
	if _running:
		# A previous song is still being analysed; queue this one behind it.
		_restart_pending = true
		return
	_start()


func _start() -> void:
	if _running:
		return
	if _thread != null:
		return
	_running = true
	_thread = Thread.new()
	var error := _thread.start(Callable(self, "_worker").bind(_path))
	if error != OK:
		_running = false
		_thread = null
		_status.text = "无法启动分析线程（错误 %d）" % error


func _worker(path: String) -> Dictionary:
	var samples := AudioPCM.load_mono(path)
	if samples.is_empty():
		return {"ok": false, "error": AudioPCM.last_error, "bpm": 0.0, "offset_ms": 0.0, "confidence": 0.0}
	return BpmDetect.analyze(samples, float(AudioPCM.DEFAULT_RATE))


func _process(_delta: float) -> void:
	if _thread == null:
		return
	if _thread.is_alive():
		return
	_result = _thread.wait_to_finish()
	_thread = null
	_running = false
	if _restart_pending:
		_restart_pending = false
		_result = {}
		_start()
		return
	_populate()


func _populate() -> void:
	var ok := bool(_result.get("ok", false))
	if ok:
		_bpm_spin.set_value_no_signal(float(_result.get("bpm", 120.0)))
		_offset_spin.set_value_no_signal(float(_result.get("offset_ms", 0.0)))
	else:
		if _app != null and _app.chart != null:
			_bpm_spin.set_value_no_signal(_app.chart.timing.bpm_at(0.0))
			_offset_spin.set_value_no_signal(_app.chart.offset_ms)
	await _measure_playback()
	_refresh_checks()


func _measure_playback() -> void:
	_stream_ms = -1.0
	_stream_error = ""
	var prepared := _path
	if not MediaIO.is_native_audio(_path) and not FileAccess.file_exists(MediaIO.audio_cache_path(_path)):
		# 非原生格式先带状态栏异步转码，别把主线程压在 ffmpeg 上。
		_status.text = "转码音频：%s" % _path.get_file()
		prepared = await MediaIO.prepare_audio_async(_path, get_tree())
	else:
		prepared = MediaIO.prepare_audio(_path)
	if prepared.is_empty():
		_stream_error = MediaIO.last_error
		return
	var stream := ChartIO.audio_stream_from_path(prepared)
	if stream == null:
		_stream_error = "无法加载播放流：%s" % _path.get_file()
		return
	_stream_ms = stream.get_length() * 1000.0


func _refresh_checks() -> void:
	if _bpm_spin == null or _offset_spin == null:
		return
	if _result.is_empty():
		_apply_button.disabled = true
		return
	var detected := bool(_result.get("ok", false))
	var bpm := _bpm_spin.value
	var offset := _offset_spin.value
	var period_ms := 60000.0 / maxf(1.0, bpm)
	var bpm_ok := detected and bpm > 0.0
	var offset_ok := detected and is_finite(offset) and absf(offset) <= period_ms + 1.0
	var decoded_ms := float(_result.get("duration_ms", 0.0))
	var duration_ok := (decoded_ms > 0.0 and _stream_ms > 0.0
		and absf(_stream_ms - decoded_ms) <= maxf(200.0, decoded_ms * 0.01))
	_read_ok = bpm_ok and offset_ok and duration_ok
	var checks := "BPM %s，offset %s，时长 %s" % [
		"通过" if bpm_ok else "失败",
		"通过" if offset_ok else "失败",
		"通过" if duration_ok else "失败",
	]
	var confidence := int(round(float(_result.get("confidence", 0.0)) * 100.0))
	var detail := "置信度 %d%%，匹配 %d 拍，解码 %.2fs / 播放 %.2fs\n%s" % [
		confidence, int(_result.get("beats", 0)),
		decoded_ms / 1000.0, maxf(0.0, _stream_ms) / 1000.0, checks,
	]
	if not _stream_error.is_empty():
		detail += "\n播放流：%s" % _stream_error
	_detail.text = detail
	if _read_ok:
		_status.text = "读取成功：BPM / offset / 时长校验通过"
		_status.add_theme_color_override("font_color", UITheme.GREEN)
	elif not detected:
		_status.text = "读取失败：BPM 自动测量未成功（%s）" % String(_result.get("error", "未知原因"))
		_status.add_theme_color_override("font_color", UITheme.RED)
	else:
		_status.text = "读取失败：%s" % checks
		_status.add_theme_color_override("font_color", UITheme.RED)
	_apply_button.disabled = not _read_ok


func _restart() -> void:
	if _running or _path.is_empty():
		return
	_thread = Thread.new()
	_running = true
	_status.text = "重新分析：%s" % _path.get_file()
	var error := _thread.start(Callable(self, "_worker").bind(_path))
	if error != OK:
		_running = false
		_thread = null


func _scale_tempo(factor: float) -> void:
	_bpm_spin.value = clampf(_bpm_spin.value * factor, 20.0, 600.0)


func _on_ffmpeg_submitted(text: String) -> void:
	if _app != null:
		_app.set_ffmpeg_path(text)
	_restart()


func _browse_ffmpeg() -> void:
	if _browse_dialog == null:
		_browse_dialog = FileDialog.new()
		_browse_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_browse_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_browse_dialog.filters = PackedStringArray(["ffmpeg.exe ; ffmpeg", "*.* ; 全部文件"])
		_browse_dialog.title = "选择 ffmpeg 可执行文件"
		_browse_dialog.file_selected.connect(func(path: String) -> void:
			_ffmpeg_edit.text = path
			_on_ffmpeg_submitted(path)
		)
		add_child(_browse_dialog)
	_browse_dialog.popup_centered_ratio(0.7)


func _commit_all() -> void:
	_commit(true)


func _commit(apply_offset: bool) -> void:
	if _app == null or _path.is_empty():
		hide()
		return
	_refresh_checks()
	if not _read_ok:
		_status.text = "读取未通过，未写入谱面：请先修复 BPM / offset / 时长校验。"
		return
	if not _app.apply_detected_timing(_bpm_spin.value, _offset_spin.value, apply_offset, _path):
		return
	applied.emit()
	hide()
