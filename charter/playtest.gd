class_name Playtest
extends Control

signal exit_requested
signal settings_requested

const PERFECT_MS := 65.0
const GREAT_MS := 115.0
const GOOD_MS := 170.0
## Estella 式 BAD 档：超出 GOOD 但在这一档内算 BAD（不断连、不计命中）。
const BAD_MS := 250.0
const HIT_WINDOW_MS := BAD_MS
const BELL_WINDOW_MS := 300.0
const RED_LIMIT_SEC := 0.2
# 鼠标判定半径：非 Tap 音符统一放大，避免要求像素级瞄准。
const PATH_HEAD_RADIUS := 138.0
const PATH_TAIL_RADIUS := 192.0
## 尾判半径最多占“头到尾直线距离”的多少（短滑条要跟着缩）。
const PATH_TAIL_RADIUS_RATIO := 0.42
## 尾判还要求光标滑到轨迹的多少进度，防止站在中段就提前算完成。
## 星尾：鼠标投影到轨迹这个比例就算完成，不再要求贴着尾点。
const PATH_TAIL_MIN_FRACTION := 0.90
## 星尾自己的档位窗口（连续滑动有鼠标延迟，比 Tap 宽）。
const TAIL_PERFECT_MS := 80.0
const TAIL_GREAT_MS := 140.0
const TAIL_GOOD_MS := 220.0
const TRACE_HEAD_RADIUS := 72.0
const TRACE_CONTACT_PX := 56.0
const BELL_COLLECT_RADIUS := 72.0
## 位置判定：鼠标到音符图形边缘外还有这么多像素也算命中。
const POSITION_TOLERANCE_PX := 90.0
## Hold 头比 Tap 窄，额外再放宽一点，避免擦边。
const HOLD_HEAD_EXTRA_PX := 40.0
const HOLD_ARC_PAD := 10.0
## Hold 中途短暂松手不算断：这个时间内补按回来就继续按住。
const HOLD_RELEASE_GRACE_MS := 200.0
## 动态 offset：至少这么多次命中才开始自动校准。
const DYNAMIC_SAMPLE_MIN := 8
## 每次命中把偏移往消除偏差的方向挪这么多。
const DYNAMIC_STEP := 0.05
## 自动校准最多把偏移推离开局值多少毫秒。
const DYNAMIC_LIMIT_MS := 50.0
## 判定循环的时间窗：只需看未来 1.5 秒内、过去 6 秒内的音符。
const JUDGE_LOOKAHEAD_MS := 1500.0
const JUDGE_LOOKBEHIND_MS := 6000.0

var _app: Node = null
var chart: Chart = null
var chart_path: String = ""
var start_beat: float = 0.0

var _preview: Preview3D
var _audio: AudioStreamPlayer
var _running: bool = false
var _finished: bool = false
var _audio_available: bool = false
var _start_usec: int = 0
var _start_chart_ms: float = 0.0
var _last_chart_ms: float = -INF
var _ordered_notes: Array[Note] = []
var _ui_accum: float = 0.0

var _states: Dictionary = {}
var _key_presses: Array[Dictionary] = []
var _keys_held: Dictionary = {}
var _red_states: Dictionary = {}

var _hit_count: int = 0
var _miss_count: int = 0
var _accuracy_sum: float = 0.0
var _judged_total: int = 0
var _tier_counts: Dictionary = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "BAD": 0, "MISS": 0}
var _bell_total: int = 0
var _bell_hits: int = 0
var _red_breaks: int = 0
var _errors: Array[float] = []
var _error_sum: float = 0.0
var _auto_origin_ms: float = 0.0
var _offset_dirty: bool = false
## 自动基准模式：不进音频、按谱面自动出判定，用于无人值守测帧率。
var bench_mode: bool = false
## AUTO 自动演示：把「完美演奏」合成成真实输入（按键 / 鼠标位置），
## 走的是同一条判定管线，所以打击特效、音效、连击、结算都和真人一样。
var auto_play: bool = false
var _auto_index: int = 0
var _auto_cursor: Vector2 = Vector2.ZERO
var _auto_hold_keys: Dictionary = {}   # note_id -> {"key": int, "end_ms": float}
var _auto_key_phase: int = 0
## 环分区擦除：每颗活跃星星当前所在分区与停留帧数。
var _sector_now: Dictionary = {}
var _sector_frames: Dictionary = {}
const AUTO_LEAD_MS := 8.0              # 比判定时间早这么多就按下（吃掉帧量化误差）
const AUTO_RELEASE_MS := 60.0          # Hold 尾判之后再松手，避免被判成提前松开
const AUTO_PREVIEW_MS := 900.0         # 光标提前多久开始预判下一个要点
const AUTO_KEY_A := 65                 # 'A'
const AUTO_KEY_B := 66                 # 'B'
var _judge_from: int = 0
## 帧时间采样（基准模式诊断卡顿）：每帧间隔 + 2 秒统计。
var _frame_last_usec: int = 0
var _frame_samples: Array[int] = []
var _frame_since_usec: int = 0
var _smooth_ms: float = 0.0
var _clock_update_usec: int = 0
var _frame_last_beat: float = -1.0
var _beat_stalls: int = 0
var _dense_ids: Dictionary = {}
var _near_miss_logs: int = 0
var _near_miss_stamp: float = 0.0
var _near_miss_logged_stamp: float = -INF
var _log: Array[String] = []
var _combo: int = 0
var _max_combo: int = 0
var _sfx: HitSfx

var _top_time: Label
var _top_stats: Label
var _style_label: Label
var _results: PanelContainer
var _results_text: RichTextLabel
var _results_button: Button
var _timing_chart: TimingChart
var _bias_label: Label
## 暂停菜单（ESC）。
var _pause_overlay: Control = null
var _paused: bool = false
var _pause_usec: int = 0


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sfx = HitSfx.new()
	_sfx.name = "PlaytestHitSfx"
	add_child(_sfx)
	_sync_sfx_style()
	if _app != null:
		_app.appearance_changed.connect(_sync_sfx_style)
	_build_ui()
	_build_pause_overlay()


func _sync_sfx_style() -> void:
	_sfx.set_style(String(_app.hit_sfx_style) if _app != null else "default")


func setup(p_chart: Chart, p_start_beat: float, p_chart_path: String) -> void:
	chart = p_chart
	start_beat = p_start_beat
	chart_path = p_chart_path
	_finished = false
	if _results != null:
		_results.visible = false
	_init_states()
	_last_chart_ms = -INF
	_preview.chart_override = chart
	_preview.reset_path_cuts()
	_preview.follow_app = false
	_preview.playtest_mode = true
	_preview.custom_cursor_visible = true
	_preview.show_hud = true
	_preview.use_3d_ring = true
	_preview.mouse_tilt = true
	_preview.show_debug = false
	_preview.flow_scale = float(_app.flow_scale if _app != null else 1.0)
	_preview.star_speed = float(_app.star_speed if _app != null else 1.0)
	_preview.note_skin = String(_app.note_skin if _app != null else "candy")
	_preview.hit_fx_style = String(_app.hit_fx_style if _app != null else "burst")
	# AUTO 关掉时 auto_cursor 保持 INF，等于用真实鼠标。
	_preview.auto_cursor = Vector2.INF
	if auto_play:
		_preview.auto_cursor = _preview.project_design(Vector2.ZERO)
	# 鼠标移动不再按帧累积，瞄准反馈早一帧到达。
	Input.set_use_accumulated_input(false)
	_paused = false
	if _pause_overlay != null:
		_pause_overlay.visible = false
	_preview.time_beat = start_beat
	_preview.playing = true
	_preview.visible = true
	# 进场 / 重开时整体淡入，避免音符和轨迹直接蹦出来。
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_start_audio()
	_running = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _build_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pause_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_overlay.add_child(box)
	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_section(title)
	box.add_child(title)
	_add_pause_button(box, "继续游玩", func() -> void: _set_paused(false))
	_add_pause_button(box, "重新开始", func() -> void:
		_set_paused(false)
		setup(chart, 0.0, chart_path)
	)
	_add_pause_button(box, "退出游玩", func() -> void: _exit())
	_add_pause_button(box, "设置", func() -> void: settings_requested.emit())


func _add_pause_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 46)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _set_paused(value: bool) -> void:
	if _finished:
		return
	_paused = value
	if _pause_overlay != null:
		_pause_overlay.visible = value
	if _audio_available and _audio != null:
		_audio.stream_paused = value
	if value:
		_pause_usec = Time.get_ticks_usec()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if _pause_usec > 0:
			_start_usec += Time.get_ticks_usec() - _pause_usec
			_pause_usec = 0
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "PlaytestBackground"
	background.color = UITheme.BG
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview = Preview3D.new()
	_preview.name = "PlaytestPreview"
	add_child(_preview)
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.notice.connect(func(message: String, level: String) -> void: _add_log("[%s] %s" % [level, message]))

	var top := PanelContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 16
	top.offset_top = 14
	top.offset_right = 560
	top.offset_bottom = 58
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	var brand := Label.new()
	brand.text = "试玩 · 预览/非正式"
	UITheme.style_label(brand, 14, UITheme.CYAN)
	row.add_child(brand)
	_top_time = Label.new()
	UITheme.style_mono(_top_time, 12, UITheme.MUTED)
	row.add_child(_top_time)
	var hint := Label.new()
	hint.text = "Esc 暂停"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(hint)
	_style_label = Label.new()
	_style_label.add_theme_font_size_override("font_size", 11)
	_style_label.add_theme_color_override("font_color", UITheme.ACCENT)
	row.add_child(_style_label)

	var stats_panel := PanelContainer.new()
	stats_panel.name = "StatsBar"
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stats_panel)
	stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_panel.offset_left = -620
	stats_panel.offset_top = 14
	stats_panel.offset_right = -16
	stats_panel.offset_bottom = 58
	_top_stats = Label.new()
	UITheme.style_mono(_top_stats, 12, UITheme.INK)
	stats_panel.add_child(_top_stats)

	_results = PanelContainer.new()
	_results.visible = false
	_results.custom_minimum_size = Vector2(640, 500)
	add_child(_results)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -320
	_results.offset_top = -250
	_results.offset_right = 320
	_results.offset_bottom = 250
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_results.add_child(box)
	var title := Label.new()
	title.text = "试玩结束"
	UITheme.style_section(title)
	box.add_child(title)
	var chart_title := Label.new()
	chart_title.text = "Timing Distribution（判定偏差分布）"
	UITheme.style_mono(chart_title, 12, UITheme.MUTED)
	box.add_child(chart_title)
	_timing_chart = TimingChart.new()
	_timing_chart.custom_minimum_size = Vector2(600, 180)
	box.add_child(_timing_chart)
	_bias_label = Label.new()
	UITheme.style_mono(_bias_label, 12, UITheme.CYAN)
	box.add_child(_bias_label)
	_results_text = RichTextLabel.new()
	_results_text.bbcode_enabled = false
	_results_text.fit_content = false
	_results_text.scroll_active = true
	_results_text.custom_minimum_size = Vector2(600, 150)
	_results_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results_text)
	var result_buttons := HBoxContainer.new()
	result_buttons.add_theme_constant_override("separation", 12)
	box.add_child(result_buttons)
	var retry_button := Button.new()
	retry_button.text = "重试"
	retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_button.pressed.connect(_retry)
	result_buttons.add_child(retry_button)
	_results_button = Button.new()
	_results_button.text = "返回编辑器（Esc）"
	_results_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_button.pressed.connect(func() -> void: _exit())
	result_buttons.add_child(_results_button)

	var bottom := Label.new()
	bottom.text = "任意有效键：Tap / Hold / Anchor；Path / Bell / Trace 用鼠标定位；Red 停留 200ms 断连；[ / ] 判定偏移；F6 换音符外观；F7 换打击特效。"
	bottom.add_theme_font_size_override("font_size", 11)
	bottom.add_theme_color_override("font_color", Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.8))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -30
	bottom.offset_bottom = -10
	add_child(bottom)


func _init_states() -> void:
	_states.clear()
	_red_states.clear()
	_key_presses.clear()
	_keys_held.clear()
	_hit_count = 0
	_miss_count = 0
	_accuracy_sum = 0.0
	_judged_total = 0
	_tier_counts = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "BAD": 0, "MISS": 0}
	_bell_total = 0
	_bell_hits = 0
	_red_breaks = 0
	_errors.clear()
	_error_sum = 0.0
	_near_miss_logs = 0
	_near_miss_logged_stamp = -INF
	_auto_origin_ms = float(_app.playtest_offset_ms if _app != null else 0.0)
	_log.clear()
	_combo = 0
	_max_combo = 0
	_ordered_notes = chart.sorted_notes()
	_dense_ids.clear()
	for i in _ordered_notes.size():
		var note := _ordered_notes[i]
		for j in [i - 1, i + 1]:
			if j < 0 or j >= _ordered_notes.size():
				continue
			if absf(_ordered_notes[j].beat - note.beat) <= 0.25:
				_dense_ids[note.id] = true
				break
	for note in _ordered_notes:
		_states[note.id] = {
			"target_ms": chart.timing.beat_to_chart_ms(note.beat),
			"end_ms": chart.timing.beat_to_chart_ms(note.end_beat),
			"done": false,
			"head": false,
			"started": false,
			"head_judged": false,
			"tail_judged": false,
			"head_hit": false,
			"tail_hit": false,
			"path_last_mouse": Vector2.ZERO,
			"trace_started": false,
			"trace_distance": 0.0,
			"trace_last": Vector2.ZERO,
			"trace_contact": false,
			"trace_frac": 0.0,
			"trace_away": 0.0,
			"trace_reset": false,
		}
		if note.type == "bell":
			_bell_total += 1
	_judge_from = 0
	_auto_index = 0
	_auto_cursor = Vector2.ZERO
	_auto_hold_keys.clear()
	_sector_now.clear()
	_sector_frames.clear()
	for region in chart.regions:
		_red_states[region.id] = {"time": 0.0, "broken": false}


func _start_audio() -> void:
	_last_chart_ms = -INF
	_smooth_ms = 0.0
	_clock_update_usec = 0
	var bench_audio := bench_mode and "--bench-audio" in OS.get_cmdline_user_args()
	if bench_mode and not bench_audio:
		_audio_available = false
		_start_chart_ms = chart.timing.beat_to_chart_ms(start_beat)
		_start_usec = Time.get_ticks_usec()
		return
	# 重开/重进时先停掉旧播放器，避免音频叠加。
	if _audio != null:
		_audio.stop()
		remove_child(_audio)
		_audio.queue_free()
		_audio = null
	_audio = AudioStreamPlayer.new()
	_audio.name = "PlaytestAudio"
	_audio.bus = "Music"
	add_child(_audio)
	var path := chart.audio_path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path() and not chart_path.is_empty():
		path = ChartIO.resolve_path(chart_path, path)
	var stream := ChartIO.audio_stream_from_path(path)
	_start_usec = Time.get_ticks_usec()
	_start_chart_ms = chart.timing.beat_to_chart_ms(start_beat)
	if stream == null:
		_audio_available = false
		_add_log("音频不可用，使用系统时钟继续试玩。")
		return
	_audio_available = true
	_audio.stream = stream
	if bench_audio:
		# 基准模式带音频时可以静音，只测解码开销。
		var music_bus := AudioServer.get_bus_index("Music")
		if music_bus >= 0:
			AudioServer.set_bus_volume_db(music_bus, -60.0)
	print("[audio] playtest ", path, " -> ", stream, " bus=", _audio.bus)
	_audio.finished.connect(_finish)
	var from_sec := maxf(0.0, (_start_chart_ms - chart.offset_ms) / 1000.0)
	_audio.play(from_sec)


func _process(delta: float) -> void:
	if not _running or chart == null or _paused:
		return
	var chart_ms := _chart_ms()
	var judge_ms := chart_ms + float(_app.playtest_offset_ms if _app != null else 0.0)
	var beat := chart.timing.chart_ms_to_beat(chart_ms)
	_preview.time_beat = beat
	_preview.playing = true
	if auto_play:
		_auto_step(judge_ms, beat, delta)
	_judge_all(judge_ms, beat, delta)
	if bench_mode:
		_bench_tick(judge_ms, beat)
		_bench_mouse(beat)
		if "--bench-tilt" in OS.get_cmdline_user_args():
			# 模拟鼠标持续移动带来的镜头视差（get_local_mouse_position 无法在基准里伪造）。
			_preview._tilt_target = Vector2(sin(beat * 3.0), cos(beat * 2.3)) * 7.0
	_probe_frame_time()
	if _frame_last_beat >= 0.0:
		if absf(beat - _frame_last_beat) < 0.000001:
			_beat_stalls += 1
	_frame_last_beat = beat
	_ui_accum += delta
	if _ui_accum >= 0.05:
		_ui_accum = 0.0
		_update_top_bar(chart_ms, beat)
		_update_hud()
	if beat > chart.duration_beats() + 2.0:
		_finish()
	var keep_ms := HIT_WINDOW_MS + 60.0
	while not _key_presses.is_empty() and float(_key_presses[0].get("time", -INF)) < judge_ms - keep_ms:
		_key_presses.pop_front()


func _chart_ms() -> float:
	if _paused:
		return _last_chart_ms
	var now_usec := Time.get_ticks_usec()
	var dt := 0.0
	if _clock_update_usec != 0:
		dt = float(now_usec - _clock_update_usec) / 1000.0
	_clock_update_usec = now_usec
	var candidate := _last_chart_ms
	if _audio_available and _audio != null and _audio.playing:
		var stream_ms := (_audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0
		candidate = stream_ms + chart.offset_ms
		# 音频时钟只做小步校正。设备重连、VBR MP3 的播放位置估算跳变都可能一次偏几秒，
		# 直接接受会把整段音符甩到身后（表现就是“这段完全没判定/没输入响应”）。
		if _last_chart_ms > -INF and absf(candidate - _last_chart_ms) > 250.0:
			candidate = _last_chart_ms + dt
	elif _last_chart_ms > -INF:
		# 音频不可用时沿用当前时钟按墙钟推进，绝不能跳回起点。
		candidate = _last_chart_ms + dt
	else:
		candidate = _start_chart_ms + float(now_usec - _start_usec) / 1000.0
	if not is_finite(candidate) or candidate > 1.0e9:
		candidate = _last_chart_ms if _last_chart_ms > -INF else _start_chart_ms
	if _last_chart_ms <= -INF:
		_smooth_ms = candidate
	else:
		# 音频仍是主时钟，两帧之间用墙钟补间，最多领先 30ms；绝不后退。
		_smooth_ms = maxf(_smooth_ms + dt, candidate)
		_smooth_ms = minf(_smooth_ms, candidate + 30.0)
	_last_chart_ms = maxf(_last_chart_ms, _smooth_ms)
	return _last_chart_ms


## ── AUTO 自动演示 ────────────────────────────────────────────────────────
## 把「完美演奏」翻译成真实输入，判定管线完全不知道这是 AUTO：
##   · Tap / Anchor / Path 头 / Trace 头 → 判定时间塞一次按键
##   · Hold → 判定时按下、尾判之后再松
##   · Path / Trace → 合成光标贴着轨迹走，轨迹按进度擦除
##   · Bell → 合成光标停在金币上
##   · Red → 合成光标躲到红区外
## 所以打击特效、音效、连击、结算都和真人打出来的一样。

## AUTO 的按键长这样：时间就用判定时间，位置用音符当时的屏幕位置。
static func auto_press_payload(target_ms: float, point: Vector2, angle: float, key: int) -> Dictionary:
	return {
		"time": target_ms,
		"mouse": point,
		"angle": angle,
		"u": fposmod(angle, 360.0) / 360.0,
		"valid": true,
		"key": key,
	}

## 到点了没：比判定时间早 lead_ms 就把按键推进队列。
static func auto_due(target_ms: float, ms: float, lead_ms: float = 8.0) -> bool:
	return ms >= target_ms - lead_ms


## 松手后是否还在补按窗口里（在窗口内 Hold 继续，不算断）。
static func hold_release_grace_alive(released_ms: float, now_ms: float) -> bool:
	return now_ms - released_ms < HOLD_RELEASE_GRACE_MS


func _auto_step(ms: float, beat: float, _delta: float) -> void:
	if chart == null or _preview == null:
		return
	_auto_cursor = _auto_cursor_target(ms, beat)
	_preview.auto_cursor = _auto_cursor
	while _auto_index < _ordered_notes.size():
		var note := _ordered_notes[_auto_index]
		var state: Dictionary = _states[note.id]
		if not auto_due(float(state["target_ms"]), ms, AUTO_LEAD_MS):
			break
		_auto_press_note(note, state, beat)
		_auto_index += 1
	_auto_feed_trace(ms)
	_auto_release_holds(ms)


func _auto_press_note(note: Note, state: Dictionary, beat: float) -> void:
	var key := AUTO_KEY_A if _auto_key_phase % 2 == 0 else AUTO_KEY_B
	_auto_key_phase += 1
	if note.type == "bell":
		# 金币只认光标位置，不需要按键。
		return
	var point := _preview.note_head_screen(note, beat)
	if not point.is_finite():
		point = _auto_cursor
	_key_presses.append(auto_press_payload(float(state["target_ms"]), point, note.angle, key))
	if note.type == "hold":
		_keys_held[key] = true
		_auto_hold_keys[note.id] = {"key": key, "end_ms": float(state["end_ms"])}


## Trace 判定的是「鼠标走过的总距离」。轨迹比 move_px 短时真人也会来回蹭，
## AUTO 直接把差的距离补上，保证演示一定打得完。
func _auto_feed_trace(ms: float) -> void:
	var star_speed := float(_app.star_speed if _app != null else 1.0)
	var last := mini(_ordered_notes.size(), _judge_from + 64)
	for i in range(maxi(0, _judge_from), last):
		var note := _ordered_notes[i]
		if note.type != "trace":
			continue
		var state: Dictionary = _states[note.id]
		if bool(state.get("done", false)) or not bool(state.get("trace_started", false)):
			continue
		if ms > float(state["end_ms"]) + 200.0:
			continue
		var required := note.move_px * star_speed
		if float(state["trace_distance"]) < required:
			state["trace_distance"] = required
		return


func _auto_release_holds(ms: float) -> void:
	for note_id in _auto_hold_keys.keys():
		var info: Dictionary = _auto_hold_keys[note_id]
		if ms < float(info["end_ms"]) + AUTO_RELEASE_MS:
			continue
		_keys_held.erase(int(info["key"]))
		_auto_hold_keys.erase(note_id)


## AUTO 光标往哪放：Bell 的窗口很短先满足它，其次 Path/Trace 的身体期，否则待机。
func _auto_cursor_target(ms: float, beat: float) -> Vector2:
	var center: Vector2 = _preview.project_design(Vector2.ZERO)
	if not center.is_finite():
		center = Vector2.ZERO
	var body := Vector2.INF
	var bell_point := Vector2.INF
	var last := mini(_ordered_notes.size(), _judge_from + 64)
	for i in range(maxi(0, _judge_from - 4), last):
		var note := _ordered_notes[i]
		var state: Dictionary = _states.get(note.id, {})
		if state.is_empty() or bool(state.get("done", false)):
			continue
		var target := float(state["target_ms"])
		var end_ms := float(state["end_ms"])
		if ms > end_ms + 200.0:
			continue
		match note.type:
			"bell":
				if not bell_point.is_finite() and ms >= target - BELL_WINDOW_MS and ms <= target + BELL_WINDOW_MS:
					var bell: Dictionary = _preview.bell_screen(note, beat)
					if not bell.is_empty():
						bell_point = bell["center"]
			"path", "trace":
				if not body.is_finite() and ms >= target - AUTO_PREVIEW_MS and ms <= end_ms + 120.0:
					body = _auto_body_point(note, ms, beat, end_ms)
	if bell_point.is_finite():
		return _auto_avoid_red(bell_point, beat, center)
	if body.is_finite():
		return _auto_avoid_red(body, beat, center)
	# 待机：圆心稍微偏一点，别挡住判定环上的东西。
	var idle := center
	var rim: Vector2 = _preview.project_u(0.0, beat)
	if rim.is_finite():
		idle = center.lerp(rim, 0.18)
	return _auto_avoid_red(idle, beat, center)


## Path 的进度点 / Trace 的进度采样点。
func _auto_body_point(note: Note, ms: float, beat: float, end_ms: float) -> Vector2:
	if note.type == "path":
		return _auto_path_point(note, ms, beat, end_ms)
	var points: PackedVector2Array = _preview.trace_screen_points(note, beat)
	if points.size() < 2:
		return _preview.note_head_screen(note, beat)
	var q := clampf((beat - note.beat) / maxf(0.001, note.duration()), 0.0, 1.0)
	var index := clampi(int(round(q * float(points.size() - 1))), 0, points.size() - 1)
	return points[index]


## Path 的尾巴是「光标靠近就算」，半径 192px 很大：离判定时间还远时，
## 光标要沿着轨迹往回退一点，否则尾巴会被提前判成 BAD。
func _auto_path_point(note: Note, ms: float, beat: float, end_ms: float) -> Vector2:
	var total := note.duration()
	var tail: Vector2 = _preview.path_point(note, total, beat)
	if ms >= end_ms - 40.0:
		return tail
	var rel := clampf(beat - note.beat, 0.0, total)
	var point: Vector2 = _preview.path_point(note, rel, beat)
	if not point.is_finite() or not tail.is_finite():
		return point
	var guard := PATH_TAIL_RADIUS + 36.0
	if point.distance_to(tail) > guard:
		return point
	var steps := 16
	for k in steps:
		var candidate: Vector2 = _preview.path_point(note, maxf(0.0, rel - total * float(k + 1) / float(steps)), beat)
		if candidate.is_finite() and candidate.distance_to(tail) > guard:
			return candidate
	return point


## 光标落进红区就换一个安全点：沿环内一圈找第一个不在红区里的位置。
func _auto_avoid_red(point: Vector2, beat: float, center: Vector2) -> Vector2:
	if not point.is_finite() or not _inside_red(point, beat):
		return point
	var rim: Vector2 = _preview.project_u(0.0, beat)
	var radius := center.distance_to(rim) if rim.is_finite() else 120.0
	if radius <= 1.0:
		radius = 120.0
	for k in 8:
		var angle := TAU * float(k) / 8.0
		var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * 0.66
		if not _inside_red(candidate, beat):
			return candidate
	return center


func _inside_red(point: Vector2, beat: float) -> bool:
	if chart == null or _preview == null:
		return false
	for region in chart.regions:
		if not region.active_at(beat):
			continue
		var polygon: PackedVector2Array = _preview.red_region_polygon(region, beat)
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _toggle_auto() -> void:
	auto_play = not auto_play
	if _preview != null:
		_preview.auto_cursor = Vector2.INF if not auto_play else _preview.mouse_screen
	if not auto_play:
		for info in _auto_hold_keys.values():
			_keys_held.erase(int(info["key"]))
		_auto_hold_keys.clear()
	else:
		# 中途打开时不要补打已经过去的音符。
		var now_ms := _chart_ms()
		_auto_index = 0
		while _auto_index < _ordered_notes.size():
			var note := _ordered_notes[_auto_index]
			if float(_states[note.id]["target_ms"]) >= now_ms - 100.0:
				break
			_auto_index += 1
	_auto_key_phase = 0
	_add_log("AUTO %s" % ("ON" if auto_play else "OFF"))
	if chart != null:
		_update_top_bar(_chart_ms(), chart.timing.chart_ms_to_beat(_chart_ms()))


func _judge_all(ms: float, beat: float, delta: float) -> void:
	var mouse: Vector2 = _preview.mouse_screen
	for i in range(_judge_from, _ordered_notes.size()):
		var note := _ordered_notes[i]
		var note_state: Dictionary = _states[note.id]
		if note_state["done"]:
			if i == _judge_from:
				_judge_from += 1
			continue
		# 只看离当前时间足够近的音符，跳过整段已经过去/还没到的谱面。
		if float(note_state["target_ms"]) > ms + JUDGE_LOOKAHEAD_MS:
			break
		# end_ms 绝不能小于 target_ms：单点音符的结束时间就是它自己。
		# 老数据里 tap 的 end_beat 可能是 0，这里兜底，避免整段音符被判成“过期”跳过。
		var live_end_ms := maxf(float(note_state["end_ms"]), float(note_state["target_ms"]))
		if live_end_ms < ms - JUDGE_LOOKBEHIND_MS:
			# 主线程停顿/时钟跳变会把整段音符甩到身后。这里绝不能静默跳过，
			# 否则玩家看到的就是“这段 Tap 完全没反应”。
			_miss_count += 1
			_add_judgement("MISS")
			_combo = 0
			note_state["done"] = true
			if i == _judge_from:
				_judge_from += 1
			continue
		match note.type:
			"tap":
				_judge_tap(note, ms, beat)
			"hold":
				_judge_hold(note, ms, beat)
			"path":
				_judge_path(note, ms, beat, mouse)
			"trace":
				_judge_trace(note, ms, beat, delta, mouse)
			"anchor":
				_judge_anchor(note, ms, beat)
			"bell":
				_judge_bell(note, ms, beat, mouse)
	_judge_red(ms, beat, delta, mouse)


func _judge_tap(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - HIT_WINDOW_MS:
		return
	var press := _take_press_for_note(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, note, beat, 0.0)
	if not press.is_empty():
		var error := float(press["time"]) - target
		var tier := _tier_for(error)
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_register_hit(tier)
		_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "tap", _timing_detail(error, tier))
		_sfx.play(HitSfx.kind_for_note(note), randf_range(0.98, 1.02))
		_record_error(float(press["time"]) - target, "Tap #%d %s" % [note.id, tier])
		return
	if ms > target + HIT_WINDOW_MS:
		state["done"] = true
		_preview.set_note_state(note.id, "miss")
		_miss_count += 1
		_add_judgement("MISS")
		_combo = 0
		_pulse_at(note.angle, beat, UITheme.RED, "MISS", note.arc_width())
		_add_log("MISS Tap #%d @ %.0fms" % [note.id, target])


func _judge_hold(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	var end_ms := float(state["end_ms"])
	if not state["started"]:
		if ms < target - HIT_WINDOW_MS:
			return
		var press := _take_press_for_note(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, note, beat, HOLD_ARC_PAD, HOLD_HEAD_EXTRA_PX)
		if not press.is_empty():
			var head_error := float(press["time"]) - target
			var head_tier := _tier_for(head_error)
			state["started"] = true
			state["head"] = true
			state["key"] = int(press.get("key", 0))
			state["head_tier"] = head_tier
			_preview.set_note_state(note.id, "holding")
			_pulse_at(note.angle, beat, _tier_color(head_tier), head_tier, note.arc_width(), "hold", _timing_detail(head_error, head_tier))
			_sfx.play("don")
			_add_log("HOLD #%d HEAD %s" % [note.id, head_tier])
			return
		if ms > target + HIT_WINDOW_MS:
			state["done"] = true
			_preview.set_note_state(note.id, "miss", beat)
			_miss_count += 1
			_add_judgement("MISS")
			_combo = 0
			_pulse_at(note.angle, beat, UITheme.RED, "MISS", note.arc_width())
			_add_log("MISS Hold #%d (head)" % note.id)
		return
	# Hold 绑定起手键：松开起手键才算断，换成另一个键点 Tap 不会误续。
	var hold_key := int(state.get("key", 0))
	if hold_key != 0 and not _keys_held.has(hold_key):
		# 短暂松手不算断：补按窗口内继续按住；超时才按已按住的比例结算。
		if not state.has("release_ms"):
			state["release_ms"] = ms
			# 变暗提示玩家：手松了，但还有时间按回来。
			_preview.set_note_state(note.id, "slip")
		var release_ms := float(state["release_ms"])
		if hold_release_grace_alive(release_ms, ms):
			return
		# 最后 1/2 拍内松手算 PERFECT；更早松手按已按住的比例降级，不断连。
		var release_window := 60000.0 / maxf(1.0, chart.timing.bpm_at(note.beat)) * 0.5
		var held_tier := "PERFECT"
		if release_ms < end_ms - release_window:
			var head_ms := float(state["target_ms"])
			var held := clampf((release_ms - head_ms) / maxf(1.0, end_ms - head_ms), 0.0, 1.0)
			held_tier = "GREAT" if held >= 0.5 else "GOOD"
		state["done"] = true
		_preview.set_note_state(note.id, "hit", beat)
		_register_hit(held_tier)
		_pulse_at(note.angle, beat, _tier_color(held_tier), held_tier, note.arc_width(), "tap")
		_sfx.play("hold_end")
		# 提前松手不算时机样本，避免污染平均偏差和动态 offset。
		if held_tier == "PERFECT":
			_record_error(release_ms - end_ms, "HOLD #%d COMPLETE PERFECT" % note.id)
		else:
			_add_log("HOLD #%d EARLY RELEASE %s" % [note.id, held_tier])
		return
	state.erase("release_ms")
	if _preview.note_state(note.id) == "slip":
		_preview.set_note_state(note.id, "holding")
	if ms >= end_ms:
		var tier := String(state.get("head_tier", "PERFECT"))
		state["done"] = true
		_preview.set_note_state(note.id, "hit", beat)
		_register_hit(tier)
		_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "tap")
		_sfx.play("hold_end")
		_record_error(ms - end_ms, "HOLD #%d COMPLETE %s" % [note.id, tier])


func _judge_path(note: Note, ms: float, beat: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var head_ms := float(state["target_ms"])
	var tail_ms := float(state["end_ms"])
	var head_point: Vector2 = _preview.note_head_screen(note, beat)
	if not state["head_judged"]:
		if ms >= head_ms - HIT_WINDOW_MS:
			# 头部：鼠标实际位置贴近判定时刻的星头（不再用角度条带兜底）。
			var press := _take_press_for_shape(head_ms - HIT_WINDOW_MS, head_ms + HIT_WINDOW_MS, head_ms, note,
				PackedVector2Array([head_point]), PATH_HEAD_RADIUS)
			if not press.is_empty():
				var head_error := float(press["time"]) - head_ms
				var tier := _tier_for(head_error)
				state["head_hit"] = true
				_register_hit(tier)
				# 星头用实际的星头屏幕位置，平面星星（V / 折线）也能炸在正确的位置。
				_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "path", _timing_detail(head_error, tier), head_point)
				_sfx.play("path", randf_range(0.98, 1.02))
				_add_log("PATH #%d HEAD %s" % [note.id, tier])
				_preview.set_path_head_state(note.id, true, beat)
				state["head_judged"] = true
			elif ms > head_ms + HIT_WINDOW_MS:
				state["head_hit"] = false
				_miss_count += 1
				_add_judgement("MISS")
				_combo = 0
				_pulse_at(note.angle, beat, UITheme.RED, "MISS", note.arc_width())
				_add_log("PATH #%d HEAD MISS" % note.id)
				_preview.set_path_head_state(note.id, false, beat)
				state["head_judged"] = true
	if not state["tail_judged"] and ms >= tail_ms - HIT_WINDOW_MS:
		var tail_point: Vector2 = _preview.path_point(note, note.duration(), beat)
		# 尾判半径跟着滑条长度缩：45° 的短滑条头尾只隔 0.48R（≈330px），
		# 固定 192px 会让“刚摸到头”就被当成“已经滑到尾巴”，直接判成 BAD。
		var chord := PATH_TAIL_RADIUS
		var start_point: Vector2 = _preview.path_point(note, 0.0, beat)
		if start_point.is_finite() and tail_point.is_finite():
			chord = start_point.distance_to(tail_point)
		var tail_radius := clampf(minf(PATH_TAIL_RADIUS, chord * PATH_TAIL_RADIUS_RATIO), 56.0, PATH_TAIL_RADIUS)
		var tail_info: Dictionary = _preview.path_fraction(note, mouse, beat)
		var tail_fraction := float(tail_info.get("fraction", 0.0))
		var tail_distance := float(tail_info.get("distance", INF))
		var near_tail := mouse.is_finite() and tail_point.is_finite() and mouse.distance_to(tail_point) <= tail_radius
		# 两种完成方式：
		#   1) 鼠标沿轨迹扫到 90%（离轨迹别太远即可），不再要求贴着尾点；
		#   2) 手已经贴到尾点，且时间在 GREAT 内（防止路过尾点就吃个早期 BAD）。
		var swept := tail_fraction >= PATH_TAIL_MIN_FRACTION and tail_distance <= PATH_TAIL_RADIUS
		var touched := near_tail and absf(ms - tail_ms) <= TAIL_GREAT_MS
		if swept or touched:
			var tier := tail_tier(ms - tail_ms)
			state["tail_hit"] = true
			_register_hit(tier)
			_pulse_at(note.tail_angle, beat, _tier_color(tier), tier, note.tail_width, "path", _timing_detail(ms - tail_ms, tier))
			_sfx.play("tail", randf_range(0.98, 1.02))
			_add_log("PATH #%d TAIL %s" % [note.id, tier])
			state["tail_judged"] = true
		elif ms > tail_ms + HIT_WINDOW_MS:
			state["tail_hit"] = false
			_miss_count += 1
			_add_judgement("MISS")
			_combo = 0
			_pulse_at(note.tail_angle, beat, UITheme.RED, "MISS", note.tail_width)
			_add_log("PATH #%d TAIL MISS" % note.id)
			state["tail_judged"] = true
	if state["tail_judged"] and not state["done"]:
		var head_ok := bool(state["head_hit"])
		var tail_ok := bool(state["tail_hit"])
		var status := "FULL" if head_ok and tail_ok else ("FRAY" if head_ok or tail_ok else "LOST")
		_add_log("PATH #%d %s" % [note.id, status])
		var status_color := UITheme.MINT if status == "FULL" else (UITheme.AMBER if status == "FRAY" else UITheme.RED)
		_pulse_at(note.tail_angle, beat, status_color, status, note.tail_width, "path")
		state["done"] = true
	if ms < head_ms or ms > tail_ms:
		return
	# 中段只看“滑到了没有”：不逐点扣分；轨迹按时间进度连续消失。
	if bool(state.get("head_hit", false)):
		var total := note.duration()
		var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
		var q := clampf((beat - note.beat - wait) / maxf(0.001, total - wait), 0.0, 1.0)
		var progress := 1.0 - pow(1.0 - q, maxf(0.05, note.path_speed))
		var target := progress
		var info: Dictionary = _preview.path_fraction(note, mouse, beat)
		var fraction := float(info.get("fraction", 0.0))
		# 鼠标只允许领先当前进度一小段；避免停在远处把整条轨迹提前削光。
		if float(info.get("distance", INF)) <= 128.0 and fraction > progress and fraction <= progress + 0.20:
			target = fraction
		_preview.set_path_erased_to(note, target)
		_track_sector_erase(note, progress)
		state["path_last_mouse"] = mouse


## 星星扫到哪个 45° 分区，就把该分区里所有「已经开始」的星星中段擦掉。
## 停留 2 帧才算进入，避免正好压在分区边界时来回抖。
func _track_sector_erase(note: Note, progress: float) -> void:
	if _preview == null:
		return
	var local := note.path_local_at(note.duration() * clampf(progress, 0.0, 1.0))
	if local.length_squared() <= 0.000001:
		return
	var angle := fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
	var sector := _preview.ring_sector(angle)
	if int(_sector_now.get(note.id, -1)) != sector:
		_sector_now[note.id] = sector
		_sector_frames[note.id] = 0
		return
	var frames := int(_sector_frames.get(note.id, 0)) + 1
	_sector_frames[note.id] = frames
	if frames != 2:
		return
	for other in _ordered_notes:
		if other.type != "path" or other == note:
			continue
		var other_state: Dictionary = _states.get(other.id, {})
		if not bool(other_state.get("head_hit", false)) or bool(other_state.get("tail_judged", false)):
			continue
		_preview.cut_path_sector(other, sector)


func _judge_trace(note: Note, ms: float, beat: float, delta: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var start_ms := float(_states[note.id]["target_ms"])
	var end_ms := float(_states[note.id]["end_ms"])
	var contact := _trace_contact(note, mouse, beat)
	if not state["trace_started"]:
		if ms < start_ms - HIT_WINDOW_MS:
			return
		var started := false
		if note.trace_style == "slider":
			var points := _preview.trace_screen_points(note, beat)
			var head: Vector2 = points[0] if not points.is_empty() else mouse
			var press := _take_key_for_point(start_ms - HIT_WINDOW_MS, start_ms + HIT_WINDOW_MS, head, TRACE_HEAD_RADIUS, start_ms)
			if not press.is_empty():
				started = true
				_sfx.play("path", 0.94)
		elif contact:
			started = true
		if started:
			state["trace_started"] = true
			state["trace_contact"] = true
			state["trace_last"] = mouse
			_add_log("TRACE #%d CONTACT" % note.id)
			return
		if ms > start_ms + HIT_WINDOW_MS:
			state["done"] = true
			_miss_count += 1
			_combo = 0
			_add_log("MISS Trace #%d (no contact)" % note.id)
		return
	if String(chart.metadata.get("slide_mode", "follow")) == "maimai":
		# 舞萌扫圈：鼠标经过的轨迹抹掉，头部按键后只要结束窗口内仍碰到轨迹就完成。
		if contact:
			var sweep := _preview.trace_fraction(note, mouse, beat)
			var sweep_frac := float(sweep.get("fraction", 0.0))
			var sweep_prev := float(state.get("trace_frac", 0.0))
			if sweep_frac > sweep_prev + 0.02:
				_preview.cut_trace(note, sweep_prev, sweep_frac)
				state["trace_frac"] = sweep_frac
		if contact and ms >= end_ms - HIT_WINDOW_MS:
			state["done"] = true
			_hit_count += 1
			_combo += 1
			_max_combo = maxi(_max_combo, _combo)
			_add_judgement("PERFECT")
			_preview.add_hit_pulse(mouse, UITheme.MINT, "PERFECT", "trace")
			_sfx.play("trace", randf_range(0.97, 1.03))
			_add_log("TRACE #%d SWEEP HIT" % note.id)
			return
		if ms > end_ms + HIT_WINDOW_MS:
			state["done"] = true
			_miss_count += 1
			_add_judgement("MISS")
			_combo = 0
			_preview.add_hit_pulse(mouse, UITheme.RED, "MISS", "trace")
			_add_log("MISS Trace #%d (sweep)" % note.id)
		return
	if contact:
		var info: Dictionary = _preview.trace_fraction(note, mouse, beat)
		var fraction := float(info.get("fraction", 0.0))
		var distance_to_path := float(info.get("distance", INF))
		if state["trace_contact"]:
			var last: Vector2 = state["trace_last"]
			var step := last.distance_to(mouse)
			var previous_fraction := float(state.get("trace_frac", 0.0))
			var jumped := fraction >= previous_fraction + 0.02 and step > 60.0 and distance_to_path <= TRACE_CONTACT_PX
			if jumped:
				# 鼠标向前跳区：跳过的段落从画面削掉，且不累计移动距离。
				_preview.cut_trace(note, previous_fraction, fraction)
			elif fraction + 0.02 >= previous_fraction:
				state["trace_distance"] = float(state["trace_distance"]) + step
			state["trace_frac"] = maxf(previous_fraction, fraction)
		state["trace_contact"] = true
		state["trace_last"] = mouse
	else:
		state["trace_contact"] = false
		state["trace_away"] = float(state.get("trace_away", 0.0)) + delta
		if float(state["trace_away"]) > 0.25 and not bool(state.get("trace_reset", false)):
			# 离开轨迹超过 250ms：保留宽限后重置已累计距离，需要重新跟一遍。
			state["trace_reset"] = true
			state["trace_distance"] = 0.0
			_add_log("TRACE #%d FRAY (left path >250ms)" % note.id)
	if contact:
		state["trace_away"] = 0.0
		state["trace_reset"] = false
	var required := note.move_px * float(_app.star_speed if _app != null else 1.0)
	if float(state["trace_distance"]) >= required:
		state["done"] = true
		_hit_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_add_judgement("PERFECT")
		_preview.add_hit_pulse(mouse, UITheme.MINT, "PERFECT", "trace")
		_sfx.play("trace", randf_range(0.97, 1.03))
		_add_log("TRACE #%d HIT (%.0f/%.0f px)" % [note.id, float(state["trace_distance"]), required])
		return
	if ms > end_ms + HIT_WINDOW_MS:
		state["done"] = true
		_miss_count += 1
		_add_judgement("MISS")
		_combo = 0
		if _preview != null:
			_preview.add_hit_pulse(mouse, UITheme.RED, "MISS", "trace")
		_add_log("MISS Trace #%d (distance %.0f/%.0f)" % [note.id, float(state["trace_distance"]), required])


func _trace_contact(note: Note, mouse: Vector2, beat: float) -> bool:
	if note.trace_pts.size() < 2:
		return false
	var polyline: Array[Vector2] = []
	for point in _preview.trace_screen_points(note, beat):
		polyline.append(point)
	return JudgeMath.trace_distance(mouse, polyline) <= TRACE_CONTACT_PX


func _judge_bell(note: Note, ms: float, beat: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - BELL_WINDOW_MS:
		return
	if ms <= target + BELL_WINDOW_MS:
		var bell: Dictionary = _preview.bell_screen(note, beat)
		# 鼠标瞄准有误差：Bell 收取半径与吸附范围对齐，靠近就算收到。
		if not bell.is_empty() and mouse.distance_to(bell["center"]) <= maxf(BELL_COLLECT_RADIUS, float(bell["radius"])):
			state["done"] = true
			_bell_hits += 1
			_preview.set_note_state(note.id, "hit")
			_preview.add_hit_pulse(bell["center"], UITheme.GOLD, "BELL", "bell")
			_sfx.play("bell", randf_range(0.99, 1.01))
			_add_log("BELL #%d COLLECTED" % note.id)
			return
	if ms > target + BELL_WINDOW_MS:
		state["done"] = true
		_preview.set_note_state(note.id, "miss")
		var missed: Dictionary = _preview.bell_screen(note, beat)
		if not missed.is_empty():
			_preview.add_hit_pulse(missed["center"], UITheme.MUTED, "漏", "miss")
		_add_log("BELL #%d MISSED" % note.id)


func _judge_anchor(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - HIT_WINDOW_MS:
		return
	var anchor_point := _preview.note_head_screen(note, beat)
	var anchor_tolerance := POSITION_TOLERANCE_PX + float(_preview.note_graphic_radius(note.type))
	var press := _take_press_for_shape(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, target, note,
		PackedVector2Array([anchor_point]), anchor_tolerance)
	if not press.is_empty():
		var anchor_error := float(press["time"]) - target
		var tier := _tier_for(anchor_error)
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_register_hit(tier)
		_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "tap", _timing_detail(anchor_error, tier))
		_sfx.play("anchor", 1.0)
		_record_error(float(press["time"]) - target, "ANCHOR #%d %s" % [note.id, tier])
		return
	if ms > target + HIT_WINDOW_MS:
		state["done"] = true
		_preview.set_note_state(note.id, "miss")
		_miss_count += 1
		_add_judgement("MISS")
		_combo = 0
		_pulse_at(note.angle, beat, UITheme.RED, "MISS", 70.0)
		_add_log("MISS Anchor #%d" % note.id)


func _judge_red(ms: float, beat: float, delta: float, mouse: Vector2) -> void:
	for region in chart.regions:
		var state: Dictionary = _red_states[region.id]
		if not region.active_at(beat):
			state["time"] = 0.0
			state["broken"] = false
			continue
		# 红区按可见多边形判定：鼠标实际落在红区里才算。
		var polygon := _preview.red_region_polygon(region, beat)
		var inside := polygon.size() >= 3 and Geometry2D.is_point_in_polygon(mouse, polygon)
		if inside:
			state["time"] = float(state["time"]) + delta
			if float(state["time"]) >= RED_LIMIT_SEC and not bool(state["broken"]):
				state["broken"] = true
				_red_breaks += 1
				_miss_count += 1
				_add_judgement("MISS")
				# 红区断连：真的清空连击，并在红区中心炸一次红色反馈。
				_combo = 0
				var center := Vector2.ZERO
				for point in polygon:
					center += point
				if not polygon.is_empty():
					_preview.add_hit_pulse(center / float(polygon.size()), UITheme.RED, "RED", "tap")
				_add_log("RED #%d BREAK @ %.0fms" % [region.id, ms])
		else:
			state["time"] = 0.0
			state["broken"] = false


func _pulse_at(angle_degrees: float, beat: float, color: Color, label: String, width: float = 60.0, kind: String = "tap", detail: String = "", screen_point: Vector2 = Vector2.INF) -> void:
	if _preview == null:
		return
	var p := screen_point
	if not (p.is_finite() and p.x < 1.0e9):
		p = _preview.project_u(fposmod(angle_degrees, 360.0) / 360.0, beat)
	if p.is_finite() and p.x < 1.0e9:
		_preview.add_hit_pulse(p, color, label, kind, detail)
		_preview.add_arc_flash(angle_degrees, width, beat, color)


## 光标贴近某个点（Path/Trace 头）。命中里挑离 target 最近的。
func _take_key_for_point(lo: float, hi: float, point: Vector2, radius: float, target: float = NAN) -> Dictionary:
	var best_index := -1
	var best_distance := INF
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		var press_mouse: Vector2 = press.get("mouse", Vector2.ZERO)
		if press_mouse.distance_to(point) > radius:
			continue
		var distance := absf(stamp - target) if is_finite(target) else 0.0
		if distance < best_distance:
			best_distance = distance
			best_index = i
	if best_index < 0:
		return {}
	var result: Dictionary = _key_presses[best_index]
	_key_presses.remove_at(best_index)
	return result


## 密集流（相邻音符 ≤ 0.25 拍）用角度扇区区分：鼠标角度落在条带内即可。
func _take_key_for_sector(lo: float, hi: float, angle: float, width: float, target: float = NAN) -> Dictionary:
	var half := maxf(24.0, width * 0.5)
	var best_index := -1
	var best_distance := INF
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		var press_angle := float(press.get("angle", NAN))
		if is_nan(press_angle):
			continue
		if absf(JudgeMath.angle_delta(press_angle, angle)) > half:
			continue
		var distance := absf(stamp - target) if is_finite(target) else 0.0
		if distance < best_distance:
			best_distance = distance
			best_index = i
	if best_index < 0:
		return {}
	var result: Dictionary = _key_presses[best_index]
	_key_presses.remove_at(best_index)
	return result


## 一组候选图形的取键（Path 头 / Anchor / Trace 头）。
## 密集流（相邻 ≤0.25 拍）按环平面角度扇区；其余按鼠标实际位置（90px + 图形半宽）。
func _take_press_for_shape(lo: float, hi: float, target: float, note: Note, points: PackedVector2Array, tolerance: float, pad: float = 0.0) -> Dictionary:
	if _key_presses.is_empty():
		return {}
	if _dense_ids.has(note.id):
		return _take_key_for_sector(lo, hi, note.angle, note.arc_width() + pad, target)
	return _take_key_near(lo, hi, points, tolerance, target)


## Tap / Hold 头：密集流走角度扇区，其余按鼠标实际位置。
func _take_press_for_note(lo: float, hi: float, note: Note, beat: float, pad: float = 0.0, extra_px: float = 0.0) -> Dictionary:
	if _key_presses.is_empty():
		return {}
	var target := float(_states[note.id]["target_ms"]) if _states.has(note.id) else (lo + hi) * 0.5
	var points := _preview.note_live_band(note, beat, pad)
	var tolerance := POSITION_TOLERANCE_PX + extra_px + float(_preview.note_graphic_radius(note.type))
	return _take_press_for_shape(lo, hi, target, note, points, tolerance, pad)


func _take_key_near(lo: float, hi: float, points: PackedVector2Array, tolerance: float, target: float = NAN) -> Dictionary:
	if points.is_empty():
		return {}
	var best := INF
	var best_mouse := Vector2.ZERO
	var best_index := -1
	var best_time_distance := INF
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		var press_mouse: Vector2 = press.get("mouse", Vector2.ZERO)
		var distance := _distance_to_polyline(press_mouse, points)
		if distance <= tolerance:
			var time_distance := absf(stamp - target) if is_finite(target) else 0.0
			if time_distance < best_time_distance:
				best_time_distance = time_distance
				best_index = i
			continue
		if distance < best:
			best = distance
			best_mouse = press_mouse
			_near_miss_stamp = stamp
	if best_index >= 0:
		var picked: Dictionary = _key_presses[best_index]
		_key_presses.remove_at(best_index)
		return picked
	if best < INF and _near_miss_logs < 40 and _near_miss_stamp != _near_miss_logged_stamp:
		_near_miss_logs += 1
		_near_miss_logged_stamp = _near_miss_stamp
		var mid: Vector2 = points[points.size() / 2]
		print("[judge] 位置未命中 d=%.0f toll=%.0f mouse=(%.0f,%.0f) note=(%.0f,%.0f)" % [best, tolerance, best_mouse.x, best_mouse.y, mid.x, mid.y])
	return {}


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.is_empty():
		return INF
	if points.size() == 1:
		return point.distance_to(points[0])
	var best := INF
	for i in points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
		best = minf(best, point.distance_to(closest))
	return best



func _record_error(error_ms: float, label: String) -> void:
	_errors.append(error_ms)
	_error_sum += error_ms
	_add_log("%s  %+.0fms" % [label, error_ms])
	if _app == null or not bool(_app.dynamic_offset) or _errors.size() < DYNAMIC_SAMPLE_MIN:
		return
	# 动态 offset：每次命中往消除当前偏差的方向挪 5%，自动部分最多 ±50ms。
	var next := float(_app.playtest_offset_ms) - error_ms * DYNAMIC_STEP
	_app.playtest_offset_ms = clampf(next, _auto_origin_ms - DYNAMIC_LIMIT_MS, _auto_origin_ms + DYNAMIC_LIMIT_MS)
	_offset_dirty = true


func _mean_error() -> float:
	return _error_sum / float(_errors.size()) if not _errors.is_empty() else 0.0


## 不稳定率：误差标准差的 10 倍（osu 口径）。
func _unstable_rate() -> float:
	if _errors.size() < 2:
		return 0.0
	var mean := _mean_error()
	var variance := 0.0
	for error in _errors:
		variance += (error - mean) * (error - mean)
	return sqrt(variance / float(_errors.size() - 1)) * 10.0


## 退出/结算时把自动调过的偏移写回设置。
func _flush_offset() -> void:
	if _app == null:
		return
	_app.last_bias_ms = _mean_error()
	_app.save_settings()
	_offset_dirty = false


func _add_log(line: String) -> void:
	_log.append(line)
	if _log.size() > 120:
		_log.pop_front()
	print("[playtest] %s" % line)


func _update_top_bar(ms: float, beat: float) -> void:
	var total := chart.timing.beat_to_chart_ms(chart.duration_beats())
	_top_time.text = "%s / %s" % [_format_ms(ms), _format_ms(total)]
	var accuracy := _accuracy()
	var offset := float(_app.playtest_offset_ms if _app != null else 0.0)
	var skin_label := String(Preview3D.skin_presets().get(_preview.note_skin, {}).get("label", _preview.note_skin))
	var fx_label := String(Preview3D.hit_fx_presets().get(_preview.hit_fx_style, _preview.hit_fx_style))
	if _style_label != null:
		_style_label.text = "%s · %s" % [skin_label, fx_label]
	_top_stats.text = "%sHIT %d  MISS %d  ACC %s  COMBO %d  |  BELL %d/%d  RED %d  |  BIA %+.1fms  OFF %+.0fms" % [
		"[AUTO] " if auto_play else "",
		_hit_count,
		_miss_count,
		"—" if accuracy < 0.0 else "%.1f%%" % accuracy,
		_combo,
		_bell_hits,
		_bell_total,
		_red_breaks,
		_mean_error(),
		offset,
	]


func _update_hud() -> void:
	var accuracy := _accuracy()
	_preview.hud_accuracy = accuracy
	_preview.hud_rating = _rating(accuracy)
	_preview.hud_errors = _errors.slice(maxi(0, _errors.size() - 64))


func _accuracy() -> float:
	if _judged_total <= 0:
		return -1.0
	return 100.0 * _accuracy_sum / float(_judged_total)


## 基准模式：给每颗接近判定时间的 Tap 塞一个“完美”按键，制造真实特效负载。
func _bench_tick(ms: float, beat: float) -> void:
	for note in _ordered_notes:
		var st: Dictionary = _states[note.id]
		var target := float(st["target_ms"])
		if target > ms + 50.0:
			break
		if note.type != "tap" or st["done"]:
			continue
		if ms < target - 10.0 or ms > target + 20.0:
			continue
		_key_presses.append({
			"time": ms,
			"mouse": _preview.note_head_screen(note, beat),
			"angle": note.angle,
			"u": note.angle / 360.0,
			"valid": true,
			"key": 65,
		})


## 基准模式：模拟真实鼠标（每帧注入多枚移动事件），复现高回报率鼠标的输入压力。
func _bench_mouse(beat: float) -> void:
	if not "--bench-mouse" in OS.get_cmdline_user_args():
		return
	var center := Vector2(800, 450)
	for k in 6:
		var a := beat * 4.0 + float(k) * 0.02
		var ev := InputEventMouseMotion.new()
		ev.position = center + Vector2(cos(a), sin(a)) * 260.0
		ev.relative = Vector2(-sin(a), cos(a)) * 6.0
		Input.parse_input_event(ev)


## 基准模式：统计帧间隔的 p50/p95/最大值，找出平均帧率看不出的卡顿尖峰。
func _probe_frame_time() -> void:
	var now := Time.get_ticks_usec()
	if _frame_last_usec > 0:
		_frame_samples.append(now - _frame_last_usec)
	_frame_last_usec = now
	if _frame_since_usec == 0:
		_frame_since_usec = now
		return
	if now - _frame_since_usec < 2000000 or _frame_samples.size() < 10:
		return
	var sorted := _frame_samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	var median := float(sorted[n / 2]) / 1000.0
	var p95 := float(sorted[int(n * 0.95)]) / 1000.0
	var worst := float(sorted[n - 1]) / 1000.0
	var spikes := 0
	for value in sorted:
		if float(value) > float(sorted[n / 2]) * 2.0:
			spikes += 1
	# 只在出现明显卡顿时打印，正常游玩不会刷屏。
	if worst > 8.0 or spikes > 20:
		print("[frame] t=%.1fs n=%d med=%.1fms p95=%.1fms max=%.1fms spikes=%d notes=%d" % [
			_chart_ms() / 1000.0, n, median, p95, worst, spikes, _ordered_notes.size(),
		])
		print("[frame] beat_stalls=%d / %d frames" % [_beat_stalls, n])
		_beat_stalls = 0
	_frame_samples.clear()
	_frame_since_usec = now


func _tier_for(error_ms: float) -> String:
	var error := absf(error_ms)
	if error <= PERFECT_MS:
		return "PERFECT"
	if error <= GREAT_MS:
		return "GREAT"
	if error <= GOOD_MS:
		return "GOOD"
	if error <= BAD_MS:
		return "BAD"
	return "MISS"


## 星尾档位：连续滑动有鼠标延迟，窗口比 Tap 宽一档。
static func tail_tier(error_ms: float) -> String:
	var error := absf(error_ms)
	if error <= TAIL_PERFECT_MS:
		return "PERFECT"
	if error <= TAIL_GREAT_MS:
		return "GREAT"
	if error <= TAIL_GOOD_MS:
		return "GOOD"
	if error <= BAD_MS:
		return "BAD"
	return "MISS"


## 命中登记：BAD 只扣准确率，不计命中也不断连。
## 判定字下面那行：早了还是晚了、差多少毫秒。
func _timing_detail(error_ms: float, tier: String) -> String:
	if tier == "PERFECT":
		return ""
	return ("早 %.0fms" if error_ms < 0.0 else "晚 %.0fms") % absf(error_ms)


func _register_hit(tier: String) -> void:
	if tier == "BAD":
		_add_judgement("BAD")
		return
	_hit_count += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	_add_judgement(tier)


func _tier_color(tier: String) -> Color:
	match tier:
		"PERFECT": return UITheme.GOLD
		"GREAT": return UITheme.CYAN
		"GOOD": return UITheme.MUTED
		"BAD": return Color(0.52, 0.58, 0.68)
		"MISS": return UITheme.RED
	return UITheme.INK


func _add_judgement(tier: String) -> void:
	var weight := 1.0 if tier == "PERFECT" else (0.7 if tier == "GREAT" else (0.3 if tier == "GOOD" else 0.0))
	_accuracy_sum += weight
	_judged_total += 1
	_tier_counts[tier] = int(_tier_counts.get(tier, 0)) + 1


func _rating(accuracy: float) -> String:
	if accuracy < 0.0:
		return "—"
	if accuracy >= 95.0:
		return "AAA"
	if accuracy >= 90.0:
		return "AA"
	if accuracy >= 80.0:
		return "A"
	if accuracy >= 70.0:
		return "B"
	return "C"


func _format_ms(ms: float) -> String:
	var value := maxi(0, int(ms))
	var minutes := value / 60000
	var seconds := (value % 60000) / 1000
	var millis := value % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, millis]


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if event.pressed and event.echo:
		return
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			if _finished:
				_exit()
			elif _paused:
				_set_paused(false)
			else:
				_set_paused(true)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and not event.echo:
			if event.keycode == KEY_F6:
				_cycle_note_skin(1)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_F7:
				_cycle_hit_fx(1)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_F8:
				_toggle_auto()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT:
				var delta := 5.0 if event.keycode == KEY_BRACKETRIGHT else -5.0
				if _app != null:
					_app.playtest_offset_ms = clampf(float(_app.playtest_offset_ms) + delta, -200.0, 200.0)
				var now_ms := _chart_ms()
				_update_top_bar(now_ms, chart.timing.chart_ms_to_beat(now_ms))
				get_viewport().set_input_as_handled()
				return
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var stamp := _chart_ms() + float(_app.playtest_offset_ms if _app != null else 0.0)
			_key_presses.append({
				"time": stamp,
				"mouse": _preview.mouse_screen,
				"angle": _preview.screen_angle_deg(_preview.mouse_screen),
				"u": _preview.cursor_u,
				"valid": _preview.cursor_valid,
				"key": key,
			})
			_keys_held[key] = true
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			_keys_held.erase(key)
			get_viewport().set_input_as_handled()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_running = false
	if _audio != null:
		_audio.stop()
	_preview.playing = false
	_preview.custom_cursor_visible = false
	var lines: Array[String] = []
	if auto_play:
		lines.append("AUTO 自动演示（成绩不计入）")
	elif _judged_total > 0 and _miss_count == 0:
		if int(_tier_counts.get("PERFECT", 0)) == _judged_total:
			lines.append("★ ALL PERFECT")
		else:
			lines.append("★ FULL COMBO")
	lines.append("命中 %d / 失误 %d" % [_hit_count, _miss_count])
	lines.append("调试准确率：%s" % ("—" if _accuracy() < 0.0 else "%.2f%%" % _accuracy()))
	lines.append("评级：%s（预览/非正式）" % _rating(_accuracy()))
	lines.append("最大连击：%d" % _max_combo)
	lines.append("判定：PERFECT %d / GREAT %d / GOOD %d / BAD %d / MISS %d" % [
		int(_tier_counts.get("PERFECT", 0)), int(_tier_counts.get("GREAT", 0)),
		int(_tier_counts.get("GOOD", 0)), int(_tier_counts.get("BAD", 0)),
		int(_tier_counts.get("MISS", 0)),
	])
	lines.append("Bell 收集：%d / %d" % [_bell_hits, _bell_total])
	lines.append("Red 断连：%d 次" % _red_breaks)
	var average_error := _mean_error()
	# AUTO 的“误差”恒为 0，不能让它把动态 offset 带偏。
	if not auto_play:
		_flush_offset()
	if _timing_chart != null:
		_timing_chart.set_errors(_errors)
	if _bias_label != null:
		_bias_label.text = "平均判定偏差 %+.2f 毫秒   ·   不稳定率 (UR) %.2f   ·   样本 %d   ·   当前 offset %+.0fms" % [
			average_error,
			_unstable_rate(),
			_errors.size(),
			float(_app.playtest_offset_ms if _app != null else 0.0),
		]
	lines.append("")
	lines.append("事件日志（最近 24 条）：")
	for i in range(maxi(0, _log.size() - 24), _log.size()):
		lines.append("  %s" % _log[i])
	_results_text.text = "\n".join(lines)
	_results.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _cycle_note_skin(step: int) -> void:
	var keys := Preview3D.skin_presets().keys()
	var index := keys.find(_preview.note_skin)
	_preview.note_skin = String(keys[posmod(index + step, keys.size())])
	if _app != null:
		_app.note_skin = _preview.note_skin
		_app.save_settings()
	_update_top_bar(_chart_ms(), chart.timing.chart_ms_to_beat(_chart_ms()))


func _cycle_hit_fx(step: int) -> void:
	var keys := Preview3D.hit_fx_presets().keys()
	var index := keys.find(_preview.hit_fx_style)
	_preview.hit_fx_style = String(keys[posmod(index + step, keys.size())])
	if _app != null:
		_app.hit_fx_style = _preview.hit_fx_style
		_app.save_settings()
	_update_top_bar(_chart_ms(), chart.timing.chart_ms_to_beat(_chart_ms()))


func _retry() -> void:
	if chart == null:
		_exit()
		return
	setup(chart, 0.0, chart_path)


func _exit() -> void:
	if _audio != null:
		_audio.stop()
	_flush_offset()
	Input.set_use_accumulated_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	exit_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.set_use_accumulated_input(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 切出窗口时自动暂停，避免切走的几秒把谱面打空。
		if _running and not _paused and not _finished:
			_set_paused(true)
