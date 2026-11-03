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


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	title = "导入歌曲 · 自动识别 BPM / offset"
	ok_button_text = "应用"
	min_size = Vector2i(520, 300)
	exclusive = true
	_build()
	confirmed.connect(_commit_all)
	set_process(true)


func _build() -> void:
	_apply_button = get_ok_button()
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
	grid.add_child(_bpm_spin)

	grid.add_child(_grid_label("offset ms"))
	_offset_spin = SpinBox.new()
	_offset_spin.min_value = -10000.0
	_offset_spin.max_value = 10000.0
	_offset_spin.step = 1.0
	_offset_spin.value = 0.0
	_offset_spin.custom_minimum_size = Vector2(160, 0)
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
	hint.text = "WAV 直接读取；mp3 / ogg / flac / m4a 需要 ffmpeg 解码一次并缓存。识别结果只是初值，应用后仍可在“时间”页微调。"
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
	_status.text = "分析中：%s" % path.get_file()
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
		var bpm := float(_result.get("bpm", 120.0))
		var offset := float(_result.get("offset_ms", 0.0))
		_bpm_spin.value = bpm
		_offset_spin.value = offset
		var confidence := int(round(float(_result.get("confidence", 0.0)) * 100.0))
		_status.text = "识别完成：%.1f BPM · offset %.0f ms" % [bpm, offset]
		_detail.text = "置信度 %d%% · 匹配 %d 拍 · 半速 %.1f / 倍速 %.1f BPM" % [
			confidence, int(_result.get("beats", 0)),
			float(_result.get("half_bpm", 0.0)), float(_result.get("double_bpm", 0.0)),
		]
	else:
		var error := String(_result.get("error", "识别失败"))
		_status.text = "没能识别出节拍：%s" % error
		_detail.text = "下面是谱面当前的 BPM / offset，可直接改数值后应用。"
		if _app != null and _app.chart != null:
			_bpm_spin.value = _app.chart.timing.bpm_at(0.0)
			_offset_spin.value = _app.chart.offset_ms
	if _apply_button != null:
		_apply_button.disabled = false


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
	_app.apply_detected_timing(_bpm_spin.value, _offset_spin.value, apply_offset, _path)
	applied.emit()
	hide()
