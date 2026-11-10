class_name CalibrationDialog
extends Control

## Two-pass calibration. The audio pass taps along with the bundled 120 BPM
## click and writes the output latency; the visual pass taps when the pulse
## peaks and writes the judgement offset. Keeping them apart avoids the common
## mistake of folding display latency into the audio clock.
signal closed

const CLICK_MS := 500.0
const TAP_FROM_MS := 1000.0
const TAP_COUNT := 8
const MAX_TAP_ERROR_MS := 180.0
const MODE_AUDIO := "audio"
const MODE_VISUAL := "visual"

var _app: Node
var _player: AudioStreamPlayer
var _panel: PanelContainer
var _title: Label
var _hint: Label
var _status: Label
var _beat: Panel
var _audio_button: Button
var _visual_button: Button
var _close_button: Button
var _retry_button: Button
var _taps: Array[float] = []
var _last_tap_ms := -INF
var _mode := MODE_AUDIO
var _running := false
var _start_usec := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -240.0
	_panel.offset_top = -178.0
	_panel.offset_right = 240.0
	_panel.offset_bottom = 178.0
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = Label.new()
	_title.text = "音频延迟校准"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_mono(_title, 18, UITheme.INK)
	box.add_child(_title)
	_hint = Label.new()
	_hint.text = "跟着听到的节拍点击 8 次\n不要看画面，只听声音"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_mono(_hint, 12, UITheme.MUTED)
	box.add_child(_hint)
	_beat = Panel.new()
	_beat.custom_minimum_size = Vector2(56, 56)
	_beat.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_beat.pivot_offset = Vector2(28, 28)
	var beat_style := StyleBoxFlat.new()
	beat_style.bg_color = Color(0.30, 0.90, 0.82, 0.9)
	beat_style.set_corner_radius_all(28)
	_beat.add_theme_stylebox_override("panel", beat_style)
	_beat.visible = false
	box.add_child(_beat)
	_status = Label.new()
	_status.text = "按空格或鼠标左键开始"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_mono(_status, 22, UITheme.CYAN)
	box.add_child(_status)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(modes)
	_audio_button = Button.new()
	_audio_button.text = "① 听声音"
	_audio_button.tooltip_text = "跟节拍点击；结果写入「输出延迟」"
	_audio_button.pressed.connect(_start.bind(MODE_AUDIO))
	modes.add_child(_audio_button)
	_visual_button = Button.new()
	_visual_button.text = "② 看脉冲"
	_visual_button.tooltip_text = "看圆环闪到最大时点击；结果写入「判定偏移」"
	_visual_button.pressed.connect(_start.bind(MODE_VISUAL))
	modes.add_child(_visual_button)
	_retry_button = Button.new()
	_retry_button.text = "重新开始"
	_retry_button.pressed.connect(func() -> void: _start(_mode))
	box.add_child(_retry_button)
	_close_button = Button.new()
	_close_button.text = "关闭"
	_close_button.pressed.connect(close)
	box.add_child(_close_button)
	set_process(true)


func setup(app: Node) -> void:
	_app = app


func open() -> void:
	visible = true
	_start(MODE_AUDIO)


func close() -> void:
	_stop_player()
	visible = false
	closed.emit()


func _start(mode: String) -> void:
	_stop_player()
	_mode = mode
	_taps.clear()
	_last_tap_ms = -INF
	_running = true
	_start_usec = Time.get_ticks_usec()
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.stream = load("res://audio/demo_click.wav") as AudioStream
	add_child(_player)
	_player.play(0.0)
	_beats_visible(mode == MODE_VISUAL)
	_title.text = "音频延迟校准" if mode == MODE_AUDIO else "判定偏移校准"
	_status.text = "0 / %d" % TAP_COUNT
	_hint.text = ("跟着听到的节拍点击（空格 / 鼠标左键）\n不要看画面，只听声音" if mode == MODE_AUDIO
		else "看圆环闪到最大时点击（空格 / 鼠标左键）")
	_retry_button.visible = false


func _beats_visible(value: bool) -> void:
	if _beat != null:
		_beat.visible = value
		_beat.scale = Vector2.ONE
		_beat.modulate.a = 0.3


func _stop_player() -> void:
	_running = false
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	_retry_button.visible = true
	_beats_visible(_mode == MODE_VISUAL and visible)


func _now_ms() -> float:
	if _player != null and _player.playing:
		var latency: float = _app.effective_latency_sec() if _app != null else maxf(0.0, AudioServer.get_output_latency())
		return (_player.get_playback_position() + AudioServer.get_time_since_last_mix() - latency) * 1000.0
	return float(Time.get_ticks_usec() - _start_usec) / 1000.0


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if not _running:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			_start(_mode)
			get_viewport().set_input_as_handled()
		return
	var tapped: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not tapped:
		return
	if event is InputEventMouseButton and get_viewport().gui_get_hovered_control() is BaseButton:
		return
	get_viewport().set_input_as_handled()
	var now := _now_ms()
	if now < TAP_FROM_MS or now - _last_tap_ms < 250.0:
		return
	var expected := roundf(now / CLICK_MS) * CLICK_MS
	var error := now - expected
	if absf(error) > MAX_TAP_ERROR_MS:
		return
	_taps.append(error)
	_last_tap_ms = now
	_status.text = "%d / %d" % [_taps.size(), TAP_COUNT]
	_hint.text = "上一拍 %+.0fms" % error
	if _taps.size() >= TAP_COUNT:
		_finish()


func _process(_delta: float) -> void:
	if not _running:
		return
	var now := _now_ms()
	if _mode == MODE_VISUAL:
		var phase := fposmod(now, CLICK_MS) / CLICK_MS
		var pulse := 1.0 - 0.45 * phase
		_beat.scale = Vector2(pulse, pulse)
		_beat.modulate.a = 0.45 + 0.55 * (1.0 - phase)
	if now > 7000.0:
		_finish()


## Median of visual tap errors, inverted so it can be applied as the judgement
## offset. Kept pure so the sign convention has a regression test.
static func offset_for_errors(values: Array[float]) -> float:
	if values.size() < 4:
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var median: float = float(sorted[sorted.size() / 2])
	return clampf(-median, -200.0, 200.0)


## The audio tap error is (true latency - assumed latency); adding it to the
## current assumption is the fix. Kept pure for the same reason as above.
static func latency_for_errors(values: Array[float], current_ms: float) -> float:
	if values.size() < 4:
		return clampf(current_ms, 0.0, 250.0)
	var sorted := values.duplicate()
	sorted.sort()
	var median: float = float(sorted[sorted.size() / 2])
	return clampf(current_ms + median, 0.0, 250.0)


func _finish() -> void:
	_running = false
	if _taps.size() < 4:
		_status.text = "样本不足"
		_hint.text = "重新开始后再试一次"
		_stop_player()
		return
	if _mode == MODE_AUDIO:
		var current: float = (_app.effective_latency_sec() * 1000.0) if _app != null else 0.0
		var latency := latency_for_errors(_taps, current)
		# 0 means "trust the driver"; if the calibrated value lands on ~0 but
		# the driver reports a non-zero latency, keep a tiny override so the
		# correction is not silently undone.
		if latency < 0.5 and current >= 1.0:
			latency = 0.1
		if _app != null:
			_app.audio_latency_ms = snappedf(latency, 0.1)
			_app.save_settings()
		_status.text = "音频延迟 %.1fms" % latency
		_hint.text = "已保存；点「看脉冲」继续校准判定偏移"
	else:
		var offset := offset_for_errors(_taps)
		if _app != null:
			_app.playtest_offset_ms = snappedf(offset, 0.1)
			_app.save_settings()
		_status.text = "判定偏移 %+.1fms" % offset
		_hint.text = "已保存；点关闭回到试玩设置"
	_stop_player()
