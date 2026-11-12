class_name Playtest
extends Control

signal exit_requested
signal settings_requested
## 结算页点「回放本局」时把本局录制发出去，由主场景重开一局回放。
signal replay_requested(data: Replay)

const PERFECT_MS := 65.0
const GREAT_MS := 115.0
const GOOD_MS := 170.0
## Estella 式 BAD 档：超出 GOOD 但在这一档内算 BAD（不断连、不计命中）。
const BAD_MS := 250.0
const HIT_WINDOW_MS := BAD_MS
## 早按只认这么多：更早的按键不消耗音符，可以再按一次。
## 收到 GREAT 边界，误按早一点点不会把音符判成 GOOD。
const EARLY_MS := 115.0
## 按键只在按下这一帧参与判定：误按不会隔半秒被后面的音符捡走。
const PRESS_KEEP_MS := 34.0
## 同一个键 50ms 内的重复按下只算一次（手抖双击）。
const KEY_DEBOUNCE_MS := 50.0
## Godot 4 的 InputEvent 不带时间戳：按键只可能在“上次输入刷新 → 现在”之间按下。
## 这段时间就是判定时的不确定度，区间长度上限取这一值（≈17fps，更慢就不再加长）。
const INPUT_SPAN_MAX_MS := 60.0
## 金键（黄键式）：判定线前后各 100ms 内光标在场就算，到线才结算。
const BELL_WINDOW_MS := 130.0
## 扫键串：相邻 Bell 间隔在这个范围内、角度还在动，就算同一条链，共享提前量。
const BELL_CHAIN_GAP_MS := 45.0
const BELL_CHAIN_STEP_DEG := 10.0

const RED_LIMIT_SEC := 0.2
const PATH_TAIL_RADIUS := 192.0
## 尾判半径最多占“头到尾直线距离”的多少（短滑条要跟着缩）。
const PATH_TAIL_RADIUS_RATIO := 0.42
const PathTracker = preload("res://core/path_progress.gd")
const PATH_INPUT_CAPACITY := 2048
const PATH_LOG_LIMIT_BYTES := 4 * 1024 * 1024
## 尾区早到 GOOD 的基础窗口；实际早到窗口取 max(这个, Perfect 扩展值)。
const PATH_TAIL_SWEEP_EARLY_MS := 350.0
## 星尾自己的档位窗口（连续滑动有鼠标延迟，比 Tap 宽）。
## 150/220/350 是 maimai ±233/366/600 的收紧版：真实日志里 83 条尾判
## 全部落在 ±233 内，±150 已能覆盖绝大多数，同时保留本作的准度感。
const TAIL_PERFECT_MS := 150.0
const TAIL_GREAT_MS := 220.0
const TAIL_GOOD_MS := 350.0
## maimai 的尾区停留最多把 Perfect/Great 的早到窗口扩到 22 帧（366.7ms）。
const TAIL_EXT_MAX_MS := 366.6667
const TRACE_HEAD_RADIUS := 72.0
const TRACE_CONTACT_PX := 56.0
## 位置判定：鼠标到音符图形边缘外还有这么多像素也算命中。
## Tap / Hold 头 / Path 头 / Anchor 共用这一把尺子（再各自加上图形半径）。
const POSITION_TOLERANCE_PX := 120.0
## 光标离图形中线这么近就算“指着这颗”：分配按键时优先于时间更近的邻键。
const ON_SHAPE_PX := 20.0
## 比较按键归属时给“晚于音符”的匹配加一点代价：漏掉前一颗后，
## 下一按不会立刻被前一颗补判走（那是“蹭”的另一半）。
const LATE_PENALTY_MS := 10.0
## 刚命中一颗后这么短时间内的额外按键，不再允许提前吃下一颗（防手指蹭键）。
const STRAY_GUARD_MS := 50.0
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
var _start_chart_ms: float = 0.0
var _last_chart_ms: float = -INF
var _clock := AudioClock.new()
var _ordered_notes: Array[Note] = []
var _ui_accum: float = 0.0

var _states: Dictionary = {}
var _key_presses: Array[Dictionary] = []
## 最近一次真正被按键命中的时间：用来识别“刚打完又蹭一下”的额外按键。
var _last_hit_press_ms: float = -1.0e9
var _seek_presses: Array[Dictionary] = []
## 上一帧的实际间隔（ms）：输入每帧刷新一次，按键只可能落在这段时间里。
var _last_frame_ms: float = 16.7
## 连续多少个统计窗口装不下目标帧：用来给弱机自动降画质。
var _slow_windows: int = 0
## 每个键上一次按下的时间，用来吃掉手抖双击。
var _last_press_ms: Dictionary = {}
var _keys_held: Dictionary = {}
var _red_states: Dictionary = {}

var _hit_count: int = 0
var _miss_count: int = 0
var _accuracy_sum: float = 0.0
var _judged_total: int = 0
var _tier_counts: Dictionary = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "BAD": 0, "MISS": 0}
var _red_breaks: int = 0
var _errors: Array[float] = []
var _error_sum: float = 0.0
var _auto_origin_ms: float = 0.0
var _offset_dirty: bool = false
## 自动基准模式：不进音频、按谱面自动出判定，用于无人值守测帧率。
var bench_mode: bool = false
## AUTO 自动演示合成按键和轨迹采样，共用命中、特效、音效和结算逻辑。
var auto_play: bool = false
var _auto_index: int = 0
var _auto_cursor: Vector2 = Vector2.ZERO
var _auto_hold_keys: Dictionary = {}   # note_id -> {"key": int, "end_ms": float}
var _auto_key_phase: int = 0
## One bounded batch is shared by all active paths; consuming one never steals
## a real movement from another path that overlaps it.
var _path_motion_samples: Array[Dictionary] = []
## Diagnostic capture for the current input investigation; F9 toggles capture.
var path_input_logging := true
var _path_input_log: FileAccess
var _path_input_log_path := ""
## 回放：录制本局输入；播放时把录制的事件按时间喂回同一套判定。
var _record: Replay = null
var _recording: bool = false
var replay_source: Replay = null
var replay_mode: bool = false
var _replay_events: Array = []
var _replay_index: int = 0
var _replay_ms: float = 0.0
var _replay_cursor: Vector2 = Vector2.INF
var _record_offset: float = 0.0
## 回放用录制里的 offset 序列，不去动用户的设置。
var _offset_override: float = NAN
## 回放快慢（1.0 = 原速）。只影响画面，不影响判定。
var replay_rate: float = 1.0
## seek 重算的时间步长：太小慢，太大会让路径判定丢采样。
const SEEK_STEP_MS := 16.0
## 回放的起点/终点（chart ms），进度条按这个区间算比例。
var _replay_start_ms: float = 0.0
var _replay_start_offset: float = 0.0
var _replay_total_ms: float = 0.0
## seek 会重跑几千步判定，期间静音。
var _sim_silent: bool = false
var _replay_seeking: bool = false
var _replay_bar: Control = null
var _replay_slider: HSlider = null
var _replay_play_button: Button = null
var _replay_time_label: Label = null
const AUTO_LEAD_MS := 8.0              # 比判定时间早这么多就按下（吃掉帧量化误差）
const AUTO_RELEASE_MS := 60.0          # Hold 尾判之后再松手，避免被判成提前松开
const AUTO_PREVIEW_MS := 900.0         # 光标提前多久开始预判下一个要点
const AUTO_KEY_A := 65                 # 'A'
const AUTO_KEY_B := 66                 # 'B'
var _judge_from: int = 0
## One frame-wide press assignment: a press belongs to the note it fits best,
## not to whichever note happens to be judged first.
var _press_assignments: Dictionary = {}
## 帧时间采样（基准模式诊断卡顿）：每帧间隔 + 2 秒统计。
var _frame_last_usec: int = 0
var _frame_samples: Array[int] = []
var _frame_since_usec: int = 0
var _frame_last_beat: float = -1.0
var _beat_stalls: int = 0
var _dense_ids: Dictionary = {}
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
## 结算页的判定散布图（Etterna 风格）。
var _scatter_chart: JudgeScatter
var _scatter: Array[Dictionary] = []
## 当前帧的判定时刻（_record_error 没显式给时间时用它）。
var _judge_ms_now: float = 0.0
var _bias_label: Label
## 结算页：把本局平均偏差写进这张谱面的 offset（一次修一张，别的谱面不受影响）。
var _apply_bias_button: Button
## 结算页：重放本局录制。
var _replay_button: Button
## 结算页：把本局回放另存到本地。
var _save_replay_button: Button
var _save_replay_dialog: FileDialog = null
## 导出视频：先让子进程用 Movie Maker 渲染 AVI，再用 ffmpeg 转 mp4。
## export_mode 只在子进程里为 true：放完自动退出，不录结算画面。
var export_mode: bool = false
var _export_button: Button
var _export_dialog: FileDialog = null
var _export_stage: int = 0
var _export_pid: int = -1
var _export_avi: String = ""
var _export_mp4: String = ""
var _export_timer: float = 0.0
var _export_ffmpeg: String = "ffmpeg"
var _toast_label: Label = null
var _toast_tween: Tween = null
## 暂停菜单（ESC）。
var _pause_overlay: Control = null
var _path_judgement_toggle: CheckButton
var _paused: bool = false


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
	_close_path_input_log()
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
	_preview.path_judgement_states = _states
	_preview.custom_cursor_visible = true
	_preview.show_hud = true
	_preview.use_3d_ring = true
	_preview.mouse_tilt = true
	_preview.show_debug = false
	_preview.flow_scale = float(_app.flow_scale if _app != null else 1.0)
	_preview.star_speed = float(_app.star_speed if _app != null else 1.0)
	_preview.note_skin = String(_app.note_skin if _app != null else "candy")
	_preview.hit_fx_style = String(_app.hit_fx_style if _app != null else "burst")
	_preview.cursor_scale = float(_app.cursor_scale if _app != null else 1.0)
	# AUTO 关掉时 auto_cursor 保持 INF，等于用真实鼠标。
	_preview.auto_cursor = Vector2.INF
	if auto_play:
		_preview.auto_cursor = _preview.project_design(Vector2.ZERO)
	if replay_source != null:
		_enter_replay(replay_source)
	elif _app != null:
		_start_recording()
	# 鼠标移动不再按帧累积，瞄准反馈早一帧到达。
	Input.set_use_accumulated_input(false)
	_paused = false
	if _pause_overlay != null:
		_pause_overlay.visible = false
	_preview.time_beat = start_beat
	_preview.playing = true
	_preview.visible = true
	_preview.set_process(false)
	_preview.prepare_playtest_frame(start_beat, 0.0)
	# 进场 / 重开时整体淡入，避免音符和轨迹直接蹦出来。
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_start_audio()
	_running = true
	_open_path_input_log()
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
	_path_judgement_toggle = CheckButton.new()
	_path_judgement_toggle.text = "显示 Path 判定区域（F10）"
	_path_judgement_toggle.focus_mode = Control.FOCUS_NONE
	_path_judgement_toggle.toggled.connect(_set_path_judgement_visible)
	box.add_child(_path_judgement_toggle)
	var wait_indicator := OptionButton.new()
	for label in App.PATH_WAIT_LABELS:
		wait_indicator.add_item("Path 启动指示：" + label)
	wait_indicator.select(maxi(0, App.PATH_WAIT_MODES.find(_app.path_wait_indicator)))
	wait_indicator.focus_mode = Control.FOCUS_NONE
	wait_indicator.item_selected.connect(func(index: int) -> void:
		_app.path_wait_indicator = App.PATH_WAIT_MODES[index]
		_app.save_settings()
		_app.appearance_changed.emit()
	)
	box.add_child(wait_indicator)
	_add_pause_button(box, "继续游玩", func() -> void: _set_paused(false))
	_add_pause_button(box, "重新开始", func() -> void:
		_set_paused(false)
		if replay_mode:
			_seek_replay(0.0)
		else:
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


## 回放控制条：回到开头 / 暂停 / 进度条 / 时间。只在回放模式下出现。
func _build_replay_bar() -> void:
	_replay_bar = PanelContainer.new()
	_replay_bar.name = "ReplayBar"
	_replay_bar.visible = false
	_replay_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_replay_bar)
	_replay_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_replay_bar.offset_left = 72
	_replay_bar.offset_right = -72
	_replay_bar.offset_top = -66
	_replay_bar.offset_bottom = -18

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_replay_bar.add_child(row)

	var rewind := Button.new()
	rewind.text = "回到开头"
	rewind.tooltip_text = "回到开头（Home）"
	rewind.focus_mode = Control.FOCUS_NONE
	rewind.pressed.connect(func() -> void: _seek_replay(0.0))
	row.add_child(rewind)

	_replay_play_button = Button.new()
	_replay_play_button.text = "暂停"
	_replay_play_button.tooltip_text = "暂停 / 继续（空格）"
	_replay_play_button.focus_mode = Control.FOCUS_NONE
	_replay_play_button.custom_minimum_size = Vector2(64, 0)
	_replay_play_button.pressed.connect(func() -> void: _set_paused(not _paused))
	row.add_child(_replay_play_button)

	_replay_slider = HSlider.new()
	_replay_slider.min_value = 0.0
	_replay_slider.max_value = 1.0
	_replay_slider.step = 0.0005
	_replay_slider.focus_mode = Control.FOCUS_NONE
	_replay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_slider.custom_minimum_size = Vector2(320, 0)
	# 拖动中只更新时间文字，松手才真正重算，否则每像素都要跑一遍模拟。
	_replay_slider.drag_started.connect(func() -> void: _replay_seeking = true)
	_replay_slider.drag_ended.connect(func(_changed: bool) -> void:
		_replay_seeking = false
		_seek_replay(_replay_slider.value))
	_replay_slider.value_changed.connect(func(value: float) -> void:
		if _replay_seeking:
			if _replay_time_label != null:
				_replay_time_label.text = "%s / %s" % [
					_format_ms(_replay_start_ms + value * maxf(0.0, _replay_total_ms - _replay_start_ms)),
					_format_ms(_replay_total_ms)]
		else:
			_seek_replay(value))
	row.add_child(_replay_slider)

	_replay_time_label = Label.new()
	UITheme.style_mono(_replay_time_label, 12, UITheme.MUTED)
	_replay_time_label.custom_minimum_size = Vector2(130, 0)
	row.add_child(_replay_time_label)


func _update_replay_bar() -> void:
	if _replay_bar == null or not replay_mode:
		return
	if _replay_play_button != null:
		_replay_play_button.text = "继续" if _paused else "暂停"
	if _replay_seeking:
		return
	if _replay_slider != null:
		_replay_slider.set_value_no_signal(_replay_fraction())
	if _replay_time_label != null:
		_replay_time_label.text = "%s / %s" % [_format_ms(_replay_ms), _format_ms(_replay_total_ms)]


func _replay_fraction() -> float:
	var span := maxf(1.0, _replay_total_ms - _replay_start_ms)
	return clampf((_replay_ms - _replay_start_ms) / span, 0.0, 1.0)


func _seek_relative(delta_ms: float) -> void:
	if not replay_mode:
		return
	var span := maxf(1.0, _replay_total_ms - _replay_start_ms)
	_seek_replay(clampf((_replay_ms + delta_ms - _replay_start_ms) / span, 0.0, 1.0))


func _set_path_judgement_visible(value: bool) -> void:
	_preview.set_path_judgement_visible(value)
	_path_judgement_toggle.set_pressed_no_signal(value)
	_write_path_input_log({"kind": "judgement_overlay", "enabled": value})


func _set_paused(value: bool) -> void:
	if _finished:
		return
	_paused = value
	if not replay_mode:
		# 回放里清空队列会丢掉「已分派、还没被判定消费」的按键，判定就漂了。
		_key_presses.clear()
		_last_hit_press_ms = -1.0e9
	_reset_path_motion()
	if _replay_play_button != null:
		_replay_play_button.text = "继续" if _paused else "暂停"
	if _pause_overlay != null:
		_pause_overlay.visible = value
	if _audio_available and _audio != null:
		_audio.stream_paused = value
	if value:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_clock.resume(Time.get_ticks_usec())
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
	hint.text = "Esc / 空格 暂停"
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

	_build_replay_bar()

	_results = PanelContainer.new()
	_results.visible = false
	_results.custom_minimum_size = Vector2(720, 760)
	add_child(_results)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -360
	_results.offset_top = -380
	_results.offset_right = 360
	_results.offset_bottom = 380
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
	_timing_chart.custom_minimum_size = Vector2(600, 150)
	box.add_child(_timing_chart)
	_scatter_chart = JudgeScatter.new()
	_scatter_chart.custom_minimum_size = Vector2(600, 170)
	box.add_child(_scatter_chart)
	_bias_label = Label.new()
	UITheme.style_mono(_bias_label, 12, UITheme.CYAN)
	box.add_child(_bias_label)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	box.add_child(action_row)
	_apply_bias_button = Button.new()
	_apply_bias_button.text = "把本局偏差写进本谱面"
	_apply_bias_button.tooltip_text = "把平均判定偏差加进这张谱面的 offset 并存盘；只影响这一张，别的谱面不动"
	_apply_bias_button.pressed.connect(_apply_bias_to_chart)
	_apply_bias_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_bias_button.clip_text = true
	_apply_bias_button.size_flags_stretch_ratio = 2.0
	action_row.add_child(_apply_bias_button)
	_replay_button = Button.new()
	_replay_button.text = "回放本局"
	_replay_button.tooltip_text = "用刚录下的输入重放这一局；判定结果与刚才一致（回放中再点 = 从头再放一遍）"
	_replay_button.pressed.connect(_request_replay)
	_replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_button.size_flags_stretch_ratio = 1.0
	action_row.add_child(_replay_button)
	_save_replay_button = Button.new()
	_save_replay_button.text = "保存回放"
	_save_replay_button.tooltip_text = "把这一局的输入存成 .tmkrpl 文件，可以留着以后重看"
	_save_replay_button.pressed.connect(_save_replay)
	_save_replay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_replay_button.size_flags_stretch_ratio = 1.0
	action_row.add_child(_save_replay_button)
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
	_export_button = Button.new()
	_export_button.text = "导出视频…"
	_export_button.tooltip_text = "把这一局渲染成 mp4（需要电脑上装了 ffmpeg）"
	_export_button.pressed.connect(_export_video)
	_export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_buttons.add_child(_export_button)
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
	bottom.text = "任意有效键：Tap / Hold / Anchor；Path / Bell 用鼠标定位；Seek 用滚轮上/下接住；Limit 停留 200ms 断连；[ / ] 判定偏移；F9 日志 / F10 判定区域。"
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
	_last_hit_press_ms = -1.0e9
	_seek_presses.clear()
	_last_frame_ms = 16.7
	_slow_windows = 0
	_last_press_ms.clear()
	_keys_held.clear()
	_hit_count = 0
	_miss_count = 0
	_accuracy_sum = 0.0
	_judged_total = 0
	_tier_counts = {"PERFECT": 0, "GREAT": 0, "GOOD": 0, "BAD": 0, "MISS": 0}
	_red_breaks = 0
	_errors.clear()
	_scatter.clear()
	_error_sum = 0.0
	_auto_origin_ms = _active_offset()
	_press_assignments.clear()
	_log.clear()
	_combo = 0
	_max_combo = 0
	_ordered_notes = _judgement_notes()
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
		var end_chart := chart.timing.beat_to_chart_ms(note.end_beat)
		_states[note.id] = {
			"target_ms": chart.timing.beat_to_chart_ms(note.beat),
			"end_ms": end_chart,
			"done": false,
			"head": false,
			"started": false,
			"head_judged": false,
			"tail_judged": false,
			"head_hit": false,
			"tail_hit": false,
			"path_tracker": PathTracker.for_note(note) if note.type == "path" else null,
			"path_finish_ms": INF,
			"path_tail_ref_chart_ms": end_chart,
			"path_tail_ref_ms": end_chart,
			"path_tail_end_ms": end_chart,
			"path_tail_dwell_ms": 0.0,
			"path_tail_perfect_early_ms": TAIL_PERFECT_MS,
			"slide_cued": false,
			"path_auto_index": 0,
			"trace_started": false,
			"trace_distance": 0.0,
			"trace_last": Vector2.ZERO,
			"trace_contact": false,
			"trace_frac": 0.0,
			"trace_away": 0.0,
			"trace_reset": false,
			"armed": false,
		}
	_judge_from = 0
	_auto_index = 0
	_auto_cursor = Vector2.ZERO
	_auto_hold_keys.clear()
	_path_motion_samples.clear()
	# 扫键串：连续 Bell（≤45ms、角度在动）共用整条链的提前量。一次扫过去时
	# 先经过的铃能提前锁上，到各自判定线再结算，不会因为“扫得太快”漏掉后半段。
	var previous_bell: Note = null
	for note in _ordered_notes:
		if note.type != "bell":
			previous_bell = null
			continue
		if previous_bell != null:
			var state: Dictionary = _states[note.id]
			var previous: Dictionary = _states[previous_bell.id]
			var gap := float(state["target_ms"]) - float(previous["target_ms"])
			var step := absf(JudgeMath.angle_delta(note.angle, previous_bell.angle))
			if gap <= BELL_CHAIN_GAP_MS and step >= BELL_CHAIN_STEP_DEG:
				state["sweep_chain"] = true
				previous["sweep_chain"] = true
				state["arm_from"] = float(previous.get("arm_from", float(previous["target_ms"]) - BELL_WINDOW_MS))
		previous_bell = note
	for region in chart.regions:
		_red_states[region.id] = {"time": 0.0, "broken": false}


## Chains are drawn as one Path (one head, one guide ball, one tail), so they
## are judged as one too. Child parts are folded into a synthetic root note;
## otherwise each part would demand an invisible extra head press.
func _judgement_notes() -> Array[Note]:
	var by_id := {}
	for note in chart.notes:
		by_id[note.id] = note
	var result: Array[Note] = []
	for note in chart.sorted_notes():
		if note.type == "path" and note.path_part > 0:
			continue
		if note.type != "path":
			result.append(note)
			continue
		var chain: Array[Note] = [note]
		var cursor: Note = note
		var guard := 0
		while cursor.path_next_id >= 0 and by_id.has(cursor.path_next_id) and guard < 64:
			cursor = by_id[cursor.path_next_id]
			chain.append(cursor)
			guard += 1
		result.append(Preview3D.build_path_chain_note(note, chain) if chain.size() > 1 else note)
	result.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	return result


func _start_audio() -> void:
	_last_chart_ms = -INF
	_clock = AudioClock.new()
	var bench_audio := bench_mode and "--bench-audio" in OS.get_cmdline_user_args()
	if bench_mode and not bench_audio:
		_audio_available = false
		_start_chart_ms = chart.timing.beat_to_chart_ms(start_beat)
		_clock.start(_start_chart_ms, Time.get_ticks_usec())
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
	_start_chart_ms = chart.timing.beat_to_chart_ms(start_beat)
	if stream == null:
		_audio_available = false
		_clock.start(_start_chart_ms, Time.get_ticks_usec())
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
	var lead_sec := (_start_chart_ms - chart.offset_ms) / 1000.0
	_audio.play(maxf(0.0, lead_sec))
	# 起播时刻交给 AudioClock：等音频真的出声后，用它自己的播放位置锚定，
	# 不再预测「下一次 mix + 驱动延迟」（那个值一次采样就能偏 40ms）。
	_clock.start(_start_chart_ms, Time.get_ticks_usec())


func _process(delta: float) -> void:
	_tick_export(delta)
	if not _running or chart == null or _paused:
		return
	if replay_mode:
		# 虚拟时钟：倍速只改画面快慢；判定只认事件时间戳，所以结果不变。
		_replay_ms += clampf(delta, 0.0, 0.25) * 1000.0 * maxf(0.05, replay_rate)
	var chart_ms := _chart_ms()
	_last_frame_ms = clampf(delta * 1000.0, 1.0, 200.0)
	var judge_ms := chart_ms + _active_offset()
	_judge_ms_now = judge_ms
	var beat := chart.timing.chart_ms_to_beat(chart_ms)
	_preview.playing = true
	_preview.prepare_playtest_frame(beat, delta)
	if replay_mode:
		_apply_replay_input(judge_ms)
	elif auto_play:
		_auto_step(judge_ms, beat, delta)
		_preview.mouse_screen = _auto_cursor
		_preview._update_cursor()
	_judge_all(judge_ms, beat, delta)
	_path_motion_samples.clear()
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
		_update_replay_bar()
	if beat > chart.duration_beats() + 2.0:
		_finish()
	_prune_input_queues(judge_ms)
	if _recording and _record != null:
		var offset_now := _active_offset()
		if absf(offset_now - _record_offset) > 0.01:
			_record_offset = offset_now
			_record.add_offset(judge_ms, offset_now)


## 开始录制本局输入。
func _start_recording() -> void:
	if auto_play:
		# AUTO 不需要输入，回放也就是再跑一遍 AUTO，不必录。
		_record = null
		return
	_record = Replay.new()
	_record.chart_path = chart_path
	_record.chart_hash = Replay.hash_chart(chart)
	_record.start_beat = start_beat
	_record.settings = {
		"offset_ms": _active_offset(),
		"flow": _preview.flow_scale,
		"star_speed": _preview.star_speed,
		"cursor_scale": _preview.cursor_scale,
		"note_skin": _preview.note_skin,
		"hit_fx": _preview.hit_fx_style,
		"rate": 1.0,
	}
	_record_offset = _active_offset()
	_recording = true


## 进入回放：视觉参数用录制时的值，判定偏移也跟着录制走。
func _enter_replay(data: Replay) -> void:
	replay_mode = true
	_recording = false
	_record = null
	_replay_events = data.events
	_replay_index = 0
	_replay_ms = chart.timing.beat_to_chart_ms(start_beat)
	_replay_start_ms = _replay_ms
	_offset_override = float(data.settings.get("offset_ms", 0.0))
	_replay_start_offset = _offset_override
	_replay_total_ms = chart.timing.beat_to_chart_ms(chart.duration_beats())
	_replay_cursor = Vector2.INF
	_preview.flow_scale = float(data.settings.get("flow", _preview.flow_scale))
	_preview.star_speed = float(data.settings.get("star_speed", _preview.star_speed))
	_preview.cursor_scale = float(data.settings.get("cursor_scale", _preview.cursor_scale))
	if data.settings.has("note_skin"):
		_preview.note_skin = String(data.settings["note_skin"])
	if data.settings.has("hit_fx"):
		_preview.hit_fx_style = String(data.settings["hit_fx"])
	for event in _replay_events:
		if String(event.get("k", "")) == "move":
			_replay_cursor = Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
			break
	if _replay_bar != null:
		_replay_bar.visible = true
	_update_replay_bar()
	_add_log("REPLAY 载入 %d 个事件" % _replay_events.size())


## 把到时间的事件全部重放；判定拿到的时间戳就是录制时的那个。
func _dispatch_replay(judge_ms: float) -> void:
	while _replay_index < _replay_events.size():
		var event: Dictionary = _replay_events[_replay_index]
		if float(event.get("t", 0.0)) > judge_ms:
			break
		_replay_index += 1
		_apply_replay_event(event)


func _apply_replay_event(event: Dictionary) -> void:
	var stamp := float(event.get("t", 0.0))
	match String(event.get("k", "")):
		"move":
			var point := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
			_replay_cursor = point
			_queue_path_motion(point, stamp)
		"press":
			var key := int(event.get("key", 0))
			_key_presses.append({
				"time": stamp,
				"lo": float(event.get("lo", stamp)),
				"hi": float(event.get("hi", stamp)),
				"mouse": Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))),
				"angle": float(event.get("a", 0.0)),
				"u": float(event.get("u", 0.0)),
				"valid": bool(event.get("v", false)),
				"key": key,
			})
			_keys_held[key] = true
		"release":
			_keys_held.erase(int(event.get("key", 0)))
		"seek":
			_seek_presses.append({
				"time": stamp,
				"lo": float(event.get("lo", stamp)),
				"hi": float(event.get("hi", stamp)),
				"orien": int(event.get("dir", 0)),
			})
		"offset":
			_offset_override = float(event.get("v", 0.0))


## 丢掉已经过了判定窗口的按键/滚轮事件，_process 和 seek 共用。
func _prune_input_queues(judge_ms: float) -> void:
	var keep_ms := PRESS_KEEP_MS
	while not _key_presses.is_empty() and float(_key_presses[0].get("hi", _key_presses[0].get("time", -INF))) < judge_ms - keep_ms:
		_key_presses.pop_front()
	while not _seek_presses.is_empty() and float(_seek_presses[0].get("hi", _seek_presses[0].get("time", -INF))) < judge_ms - keep_ms:
		_seek_presses.pop_front()


## 喂事件 + 把光标摆到录制位置。_process 和 seek 共用。
func _apply_replay_input(judge_ms: float) -> void:
	_dispatch_replay(judge_ms)
	if _replay_cursor.is_finite():
		_preview.mouse_screen = _replay_cursor
		_preview._update_cursor()


## 拖动进度条：回放是确定性的，所以「跳到某处」= 从头快进重算到那里。
## 2 分钟的谱约 7500 步，实测几百毫秒；判定结果与慢放时完全一致。
func _seek_replay(fraction: float) -> void:
	if not replay_mode or chart == null or not _running or _finished:
		return
	var span := maxf(1.0, _replay_total_ms - _replay_start_ms)
	var target := _replay_start_ms + clampf(fraction, 0.0, 1.0) * span
	if absf(target - _replay_ms) < 2.0:
		return
	_sim_silent = true
	_replay_index = 0
	_replay_cursor = Vector2.INF
	_offset_override = _replay_start_offset
	_init_states()
	_replay_ms = _replay_start_ms
	var guard := 0
	while _replay_ms < target and guard < 400000:
		guard += 1
		_replay_ms = minf(_replay_ms + SEEK_STEP_MS, target)
		var judge_ms := _replay_ms + _active_offset()
		_apply_replay_input(judge_ms)
		_judge_all(judge_ms, chart.timing.chart_ms_to_beat(_replay_ms), 0.0)
		_path_motion_samples.clear()
		_prune_input_queues(judge_ms)
	_sim_silent = false
	_last_chart_ms = _replay_ms
	_judge_ms_now = _replay_ms + _active_offset()
	var beat_now := chart.timing.chart_ms_to_beat(_replay_ms)
	# 暂停中拖动时 _process 不跑，这里手动把画面刷新到目标时刻。
	_preview.playing = true
	_preview.time_beat = beat_now
	_preview.prepare_playtest_frame(beat_now, 0.0)
	_update_top_bar(_replay_ms, beat_now)
	_update_hud()
	_update_replay_bar()
	_seek_audio_to(_replay_ms)
	if target >= _replay_total_ms - 1.0:
		_finish()


## 快进后把音频也挪到同一位置，否则画面对了、声音还在原地。
func _seek_audio_to(ms: float) -> void:
	if not _audio_available or _audio == null or _paused:
		return
	_audio.play(maxf(0.0, (ms - float(chart.offset_ms)) / 1000.0))


## 快进模拟时静音：seek 会重跑几千步，不能把音效全放出来。
func _play_hit(kind: String, pitch: float = 1.0) -> void:
	if _sim_silent or _sfx == null:
		return
	_sfx.play(kind, pitch)


## 回放时用录制里的 offset，不去改用户设置。
func _active_offset() -> float:
	if not is_nan(_offset_override):
		return _offset_override
	return float(_app.playtest_offset_ms if _app != null else 0.0)


## 导出视频：弹保存框 → 子进程渲染 AVI → ffmpeg 转 mp4 → 删 AVI。
## 渲染走 Godot 的 Movie Maker（--write-movie），逐帧输出，和回放的虚拟时钟天然同步。
func _export_video() -> void:
	var data := _current_replay()
	if data == null or _export_stage != 0:
		return
	if _ffmpeg_path().is_empty():
		_show_toast("没找到 ffmpeg，先装一个：winget install Gyan.FFmpeg")
		return
	if _export_dialog == null:
		_export_dialog = FileDialog.new()
		_export_dialog.use_native_dialog = true
		_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_export_dialog.title = "导出回放视频"
		_export_dialog.add_filter("*.mp4", "MP4 视频")
		_export_dialog.file_selected.connect(_start_video_export)
		add_child(_export_dialog)
	_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_export_dialog.current_file = _replay_file_name().get_basename() + ".mp4"
	_export_dialog.popup_centered()


## 找 ffmpeg：先看 PATH；winget 装完要重开终端才进 PATH，所以再兜一下它的安装位置。
func _ffmpeg_path() -> String:
	var out: Array = []
	var tool := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(tool, ["ffmpeg"], out, true) == 0:
		return "ffmpeg"
	if OS.get_name() == "Windows":
		var local := OS.get_environment("LOCALAPPDATA")
		var links := local.path_join("Microsoft/WinGet/Links/ffmpeg.exe")
		if FileAccess.file_exists(links):
			return links
		# winget 的包目录：.../WinGet/Packages/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe
		var pkgs := local.path_join("Microsoft/WinGet/Packages")
		for dir in DirAccess.get_directories_at(pkgs):
			if not dir.begins_with("Gyan.FFmpeg"):
				continue
			var root := pkgs.path_join(dir)
			for sub in DirAccess.get_directories_at(root):
				var candidate := root.path_join(sub).path_join("bin/ffmpeg.exe")
				if FileAccess.file_exists(candidate):
					return candidate
	return ""


func _start_video_export(path: String) -> void:
	var data := _current_replay()
	if data == null:
		return
	if not path.to_lower().ends_with(".mp4"):
		path += ".mp4"
	var tmp := ProjectSettings.globalize_path("user://export_replay.tmkrpl")
	if data.save_to(tmp) != OK:
		_show_toast("临时回放写不进去，导出取消")
		return
	_export_mp4 = path
	_export_avi = path.get_basename() + ".avi"
	_export_ffmpeg = _ffmpeg_path()
	var args: Array[String] = []
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array([
		"--write-movie", _export_avi,
		"--fixed-fps", "60",
		"--", "--replay=" + tmp, "--export-quit",
	])
	_export_pid = OS.create_process(OS.get_executable_path(), args)
	if _export_pid <= 0:
		_show_toast("渲染进程没起来")
		return
	_export_stage = 1
	_export_timer = 0.0
	_show_toast("正在渲染（中间文件很大，转完自动删）")


## 每 0.5 秒看一眼子进程：渲染完 → 转码，转码完 → 删 AVI。
func _tick_export(delta: float) -> void:
	if _export_stage == 0:
		return
	_export_timer += delta
	if _export_timer < 0.5:
		return
	_export_timer = 0.0
	if _export_stage == 1:
		if OS.is_process_running(_export_pid):
			return
		if not FileAccess.file_exists(_export_avi):
			_export_stage = 0
			_show_toast("渲染失败：没有生成视频文件")
			return
		var args := PackedStringArray([
			"-y", "-i", _export_avi,
			"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23",
			"-c:a", "aac", "-b:a", "192k",
			_export_mp4,
		])
		_export_pid = OS.create_process(_export_ffmpeg, args)
		if _export_pid <= 0:
			_export_stage = 0
			_show_toast("ffmpeg 启动失败，AVI 留在 %s" % _export_avi)
			return
		_export_stage = 2
		_show_toast("转码中…")
		return
	if OS.is_process_running(_export_pid):
		return
	if FileAccess.file_exists(_export_avi):
		DirAccess.remove_absolute(_export_avi)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://export_replay.tmkrpl"))
	_export_stage = 0
	_show_toast("视频已保存：%s" % _export_mp4.get_file())


## 当前可保存的回放：回放中看的是 replay_source，刚打完看的是本局录制。
func _current_replay() -> Replay:
	if replay_mode:
		return replay_source
	return _record


## 手动另存为：只有点了才写文件，平时磁盘上不会多出任何东西。
func _save_replay() -> void:
	var data := _current_replay()
	if data == null:
		return
	if _save_replay_dialog == null:
		_save_replay_dialog = FileDialog.new()
		_save_replay_dialog.use_native_dialog = true
		_save_replay_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_save_replay_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_save_replay_dialog.title = "保存回放"
		_save_replay_dialog.add_filter("*.tmkrpl", "Tamaki 回放")
		_save_replay_dialog.file_selected.connect(_on_replay_saved_to)
		add_child(_save_replay_dialog)
	_save_replay_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_save_replay_dialog.current_file = _replay_file_name()
	_save_replay_dialog.popup_centered()


func _on_replay_saved_to(path: String) -> void:
	var data := _current_replay()
	if data == null:
		return
	if not path.to_lower().ends_with(".tmkrpl"):
		path += ".tmkrpl"
	var err := data.save_to(path)
	if err == OK:
		_add_log("回放已保存：%s" % path)
		_show_toast("已保存回放：%s" % path.get_file())
	else:
		_show_toast("保存失败（错误码 %d）" % err)


func _replay_file_name() -> String:
	var title := "回放"
	if chart != null:
		var meta_title := String(chart.metadata.get("title", ""))
		if not meta_title.is_empty():
			title = meta_title
	var version := String(chart.metadata.get("version", "")) if chart != null else ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var name := title
	if not version.is_empty():
		name += "_" + version
	return _sanitize_file_name(name + "_" + stamp) + ".tmkrpl"


## Windows 不允许这几个字符出现在文件名里。
func _sanitize_file_name(text: String) -> String:
	var out := ""
	for ch in text:
		out += "_" if ch in "/\\:*?\"<>|" else ch
	out = out.strip_edges()
	return out if not out.is_empty() else "replay"


func _show_toast(message: String) -> void:
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 13)
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_toast_label)
		_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_toast_label.offset_left = -420
		_toast_label.offset_right = 420
		_toast_label.offset_top = -96
		_toast_label.offset_bottom = -66
	_toast_label.text = message
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)


func _request_replay() -> void:
	if replay_mode:
		# 回放结束后再点一次 = 用同一份录制重头再放一遍。
		if replay_source != null:
			replay_requested.emit(replay_source)
		return
	if _record == null or _record.event_count() == 0:
		return
	replay_requested.emit(_record)


## 驱动报告 0 的平台上用设置里的回退值（Android/Web 常见）。
func _effective_latency() -> float:
	if _app != null:
		return _app.effective_latency_sec()
	return maxf(0.0, AudioServer.get_output_latency())


func _chart_ms() -> float:
	var clock_start := Time.get_ticks_usec() if OS.is_debug_build() else 0
	var value := _chart_ms_inner()
	if clock_start > 0 and _preview != null:
		_preview.note_audio_usec(Time.get_ticks_usec() - clock_start)
	return value


func _chart_ms_inner() -> float:
	if replay_mode:
		# 回放走虚拟时钟：判定只认事件自带的时间戳，音频漂移不影响结果。
		_last_chart_ms = _replay_ms
		return _replay_ms
	if _paused:
		return _last_chart_ms
	var now_usec := Time.get_ticks_usec()
	var playing := _audio_available and _audio != null and _audio.playing
	var playback := _audio.get_playback_position() if playing else 0.0
	var mix := AudioServer.get_time_since_last_mix() if playing else 0.0
	var latency := _effective_latency() if playing else 0.0
	var ms := _clock.update(now_usec, playing, playback, chart.offset_ms, latency, mix)
	# 起播锚定要把驱动延迟减掉，是一次真实的回跳；只允许这一帧不单调。
	if _clock.consume_anchor_jump():
		_last_chart_ms = -INF
		_add_log("AUDIO ANCHOR @%.0fms（延迟 %.0fms，%.0fms 后冻结）" % [
			ms, _clock.latency_ms, AudioClock.LATENCY_WINDOW_MS])
	if not is_finite(ms) or ms > 1.0e9:
		ms = _last_chart_ms if _last_chart_ms > -INF else _start_chart_ms
	# Judge time must never run backwards: a tiny drift correction otherwise makes
	# PathProgress treat every frame as a new motion segment.
	if _last_chart_ms > -INF:
		ms = maxf(ms, _last_chart_ms)
	_last_chart_ms = ms
	return ms


## ── AUTO 自动演示 ────────────────────────────────────────────────────────
## 把「完美演奏」翻译成按键与轨迹采样，共用空间及时间判定：
##   · Tap / Anchor / Path 头 / Trace 头 → 判定时间塞一次按键
##   · Hold → 判定时按下、尾判之后再松
##   · Path / Trace → 合成光标贴着轨迹走，轨迹按进度擦除
##   · Bell（金键）→ 合成光标停在金色弧带上
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
	if note.type == "seek":
		_seek_presses.append({
			"time": float(state["target_ms"]),
			"orien": note.seek_orien,
		})
		return
	var key := AUTO_KEY_A if _auto_key_phase % 2 == 0 else AUTO_KEY_B
	_auto_key_phase += 1
	if note.type == "bell":
		# 金键只认光标位置，不需要按键。
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
	_reset_path_motion()
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
	_assign_presses(ms, beat)
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
			"seek":
				_judge_seek(note, ms, beat)
			"trace":
				_judge_trace(note, ms, beat, delta, mouse)
			"anchor":
				_judge_anchor(note, ms, beat)
			"bell":
				_judge_bell(note, ms, beat, mouse)
	_judge_red(ms, beat, delta, mouse)
	_press_assignments.clear()


func _judge_seek(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - HIT_WINDOW_MS:
		return
	var picked := -1
	var best := INF
	for i in _seek_presses.size():
		var press: Dictionary = _seek_presses[i]
		var stamp := float(press.get("time", -INF))
		var span_hi := float(press.get("hi", stamp))
		var span_lo := float(press.get("lo", stamp))
		if span_hi < target - HIT_WINDOW_MS or span_lo > target + HIT_WINDOW_MS:
			continue
		if int(press.get("orien", -1)) != note.seek_orien:
			continue
		var distance := absf(press_error(press, target))
		if distance < best:
			best = distance
			picked = i
	if picked >= 0:
		var press: Dictionary = _seek_presses[picked]
		_seek_presses.remove_at(picked)
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_register_hit("PERFECT")
		var color := UITheme.SEEK_IN if note.seek_orien == 0 else UITheme.SEEK_OUT
		_pulse_at(0.0, beat, color, "PERFECT", 360.0, "seek", "SEEK", _preview.project_design(Vector2.ZERO))
		_play_hit("bell", randf_range(0.98, 1.02))
		_record_error(float(press["time"]) - target, "Seek #%d PERFECT" % note.id, "PERFECT", float(press["time"]))
		return
	if ms > target + HIT_WINDOW_MS:
		state["done"] = true
		_preview.set_note_state(note.id, "miss")
		_miss_count += 1
		_add_judgement("MISS")
		_combo = 0
		_pulse_at(0.0, beat, UITheme.RED, "MISS", 360.0, "seek", "", _preview.project_design(Vector2.ZERO))
		_add_log("MISS Seek #%d @ %.0fms" % [note.id, target])


func _judge_tap(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - EARLY_MS:
		return
	var press := _take_assigned_press(note.id)
	if not press.is_empty():
		var error := press_error(press, target)
		var tier := _tier_for(error)
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_preview.add_note_pop("tap", note, beat)
		_register_hit(tier)
		_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "tap", _timing_detail(error, tier))
		_play_hit(HitSfx.kind_for_note(note), randf_range(0.98, 1.02))
		_record_error(float(press["time"]) - target, "Tap #%d %s" % [note.id, tier], tier, float(press["time"]))
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
		if ms < target - EARLY_MS:
			return
		var press := _take_assigned_press(note.id)
		if not press.is_empty():
			var head_error := press_error(press, target)
			var head_tier := _tier_for(head_error)
			state["started"] = true
			state["head"] = true
			state["key"] = int(press.get("key", 0))
			state["head_tier"] = head_tier
			_preview.set_note_state(note.id, "holding")
			_preview.add_note_pop("hold", note, beat)
			_pulse_at(note.angle, beat, _tier_color(head_tier), head_tier, note.arc_width(), "hold", _timing_detail(head_error, head_tier))
			_play_hit("don")
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
		# 提前松手不算时机样本，避免污染平均偏差和动态 offset。
		if held_tier == "PERFECT":
			_record_error(release_ms - end_ms, "HOLD #%d COMPLETE PERFECT" % note.id, "PERFECT")
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
		_record_error(ms - end_ms, "HOLD #%d COMPLETE %s" % [note.id, tier], tier, ms)


## 星星开始沿轨迹移动的时刻：note.beat + wait（wait 夹在 duration 内），再加判定偏移。
static func slide_start_ms(chart: Chart, note: Note, offset_ms: float) -> float:
	var total := maxf(0.0, note.duration())
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
	return chart.timing.beat_to_chart_ms(note.beat + wait) + offset_ms


func _judge_path(note: Note, ms: float, beat: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var tracker: PathProgress = state["path_tracker"]
	var head_ms := float(state["target_ms"])
	var tail_ms := float(state["end_ms"])
	var head_point: Vector2 = _preview.note_head_screen(note, beat)
	# 星星头开始沿轨迹移动的那一刻（beat + wait）才是“起划”，在这里响提示音。
	if not bool(state.get("slide_cued", false)):
		var slide_ms := slide_start_ms(chart, note, _active_offset())
		if ms >= slide_ms:
			state["slide_cued"] = true
			# 错过太久（跳转/卡帧）就不再补播。
			if ms - slide_ms <= 400.0:
				_play_hit("slide", randf_range(0.99, 1.01))
				_add_log("PATH #%d SLIDE START @%.0fms (expect %.0fms)" % [note.id, ms, slide_ms])
	if not state["head_judged"]:
		if ms >= head_ms - EARLY_MS:
			# 头部：鼠标实际位置贴近判定时刻的星头（不再用角度条带兜底）。
			var press := _take_assigned_press(note.id)
			if not press.is_empty():
				var head_error := press_error(press, head_ms)
				var tier := _tier_for(head_error)
				state["head_hit"] = true
				tracker.confirm_head()
				_write_path_input_log({"kind": "head", "note": note.id, "time_ms": ms,
					"error_ms": head_error, "mouse": _path_log_point(press.get("mouse", Vector2.INF))})
				_register_hit(tier)
				_play_hit(HitSfx.kind_for_note(note), randf_range(0.98, 1.02))
				# 星头用实际的星头屏幕位置，平面星星（V / 折线）也能炸在正确的位置。
				_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "path", _timing_detail(head_error, tier), head_point)
				# 星头是按键时机，和 Tap 同源，可以喂给动态校准与散布图。
				# 星尾不算：tail_error 量的是“进尾区”相对星星的时刻，早到是设计内行为。
				_record_error(head_error, "PATH #%d HEAD %s" % [note.id, tier], tier, float(press["time"]))
				_preview.set_path_head_state(note.id, true, beat)
				_preview.add_note_pop("path", note, beat)
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
	if not state["tail_judged"]:
		var tail_point: Vector2 = _preview.path_point(note, note.duration(), beat)
		var chord := PATH_TAIL_RADIUS
		var start_point: Vector2 = _preview.path_point(note, 0.0, beat)
		if start_point.is_finite() and tail_point.is_finite():
			chord = start_point.distance_to(tail_point)
		var tail_radius := clampf(minf(PATH_TAIL_RADIUS, chord * PATH_TAIL_RADIUS_RATIO), 56.0, PATH_TAIL_RADIUS)
		state["path_tail_radius"] = tail_radius
		_update_path_progress(note, state, tracker, ms, beat, mouse, tail_radius)
		var entry_chart := float(state.get("path_tail_ref_chart_ms", tail_ms))
		var dwell := float(state.get("path_tail_dwell_ms", 0.0))
		var end_sample := float(state.get("path_tail_end_ms", tail_ms))
		var finish_ms := float(state["path_finish_ms"])
		if is_finite(finish_ms):
			var tail_error := finish_ms - entry_chart
			var tier := tail_tier(tail_error, dwell)
			state["tail_hit"] = true
			_register_hit(tier)
			_pulse_at(note.tail_angle, beat, _tier_color(tier), tier, note.tail_width, "path", _timing_detail(tail_error, tier))
			_play_hit("tail", randf_range(0.98, 1.02))
			_add_log("PATH #%d TAIL %s" % [note.id, tier])
			state["tail_judged"] = true
			tracker.mark_complete()
			_write_path_input_log({"kind": "tail", "note": note.id, "tier": tier,
				"error_ms": tail_error, "end_error_ms": finish_ms - tail_ms,
				"dwell_ms": dwell, "coverage": tracker.coverage})
		elif ms > end_sample + TAIL_GOOD_MS:
			# 只剩最后一组没消：给 GOOD，避免“差一点白划”；差更多仍判 MISS。
			var remaining := tracker.remaining_groups()
			var near_complete := bool(state["head_hit"]) and remaining <= 1 and tracker.next_gate > 1
			state["tail_hit"] = false
			if near_complete:
				_register_hit("GOOD")
				_pulse_at(note.tail_angle, beat, _tier_color("GOOD"), "GOOD", note.tail_width, "path")
				_add_log("PATH #%d TAIL GOOD (remaining %d)" % [note.id, remaining])
			else:
				_miss_count += 1
				_add_judgement("MISS")
				_combo = 0
				_pulse_at(note.tail_angle, beat, UITheme.RED, "MISS", note.tail_width)
				_add_log("PATH #%d TAIL MISS (remaining %d)" % [note.id, remaining])
			state["tail_judged"] = true
			_write_path_input_log({"kind": "tail", "note": note.id,
				"tier": "GOOD" if near_complete else "MISS",
				"coverage": tracker.coverage, "next": tracker.next_index,
				"remaining": remaining})
	if state["tail_judged"] and not state["done"]:
		var head_ok := bool(state["head_hit"])
		var tail_ok := bool(state["tail_hit"])
		var status := "FULL" if head_ok and tail_ok else ("FRAY" if head_ok or tail_ok else "LOST")
		_add_log("PATH #%d %s" % [note.id, status])
		var status_color := UITheme.MINT if status == "FULL" else (UITheme.AMBER if status == "FRAY" else UITheme.RED)
		_pulse_at(note.tail_angle, beat, status_color, status, note.tail_width, "path")
		state["done"] = true
	# The guide ball follows music time; confirmed input alone erases arrows.
	_preview.set_path_erased_to(note, tracker.fraction)


func _update_path_progress(note: Note, state: Dictionary, tracker: PathProgress, ms: float, beat: float, mouse: Vector2, tail_radius: float) -> void:
	# Samples carry scoring-adjusted timestamps. Transform the visual start into
	# that same clock; a negative offset must not discard the start of a slide.
	var offset_ms := _active_offset()
	var head_start := chart.timing.beat_to_chart_ms(note.beat) + offset_ms
	var start_ms := maxf(head_start, chart.timing.beat_to_chart_ms(note.beat + clampf(note.wait_beat, 0.0, note.duration())) + offset_ms - 120.0)
	var tail_ms := float(state["end_ms"])
	if ms < start_ms - HIT_WINDOW_MS or tracker.points.size() < 2:
		return
	var projected := _preview.path_judgement_points(tracker.points, beat)
	var radius := tracker.contact_radius * _preview.path_judgement_scale()
	# maimai 的尾判参考：星星进入尾区的那一刻，而不是 Slide 结束。
	# 停留时间 dwell 用来扩展早到窗口；晚到仍按终点算，避免“跟星星走到
	# 终点”被反判成晚。所有时间都换算到包含判定偏移的采样时钟。
	var entry_param := tracker.tail_entry_parameter(projected, tail_radius)
	var entry_chart := chart.timing.beat_to_chart_ms(note.beat + note.duration() * entry_param)
	var dwell := maxf(0.0, tail_ms - entry_chart)
	state["path_tail_ref_chart_ms"] = entry_chart
	state["path_tail_ref_ms"] = entry_chart + offset_ms
	state["path_tail_end_ms"] = tail_ms + offset_ms
	state["path_tail_dwell_ms"] = dwell
	state["path_tail_perfect_early_ms"] = TAIL_PERFECT_MS + minf(dwell * 0.25, TAIL_EXT_MAX_MS)
	if auto_play:
		# AUTO feeds each path separately through the same checkpoint tracker.
		var total := maxf(0.001, note.duration())
		var wait := clampf(note.wait_beat, 0.0, total - 0.001)
		var q := clampf((beat - note.beat - wait) / (total - wait), 0.0, 1.0)
		var progress := 1.0 - pow(1.0 - q, maxf(0.05, note.path_speed))
		progress = note.path_motion_beat(progress) / total
		var finishing := ms >= tail_ms - 40.0
		var index := int(state["path_auto_index"])
		while ms >= start_ms and index < projected.size():
			if not finishing and float(tracker.parameters[index]) > progress:
				break
			_feed_path_sample(state, tracker, projected[index], ms, projected, radius, start_ms, tail_radius)
			index += 1
		state["path_auto_index"] = index
	else:
		for sample in _path_motion_samples:
			if bool(sample.get("break", false)):
				tracker.reset_motion()
			var sample_ms := float(sample["time"])
			if sample_ms <= ms:
				_feed_path_sample(state, tracker, sample["point"], sample_ms, projected, radius, start_ms, tail_radius)
		# A stationary cursor supplies contact without skipping unchecked regions.
		_feed_path_sample(state, tracker, mouse, ms, projected, radius, start_ms, tail_radius)
	_record_path_input_frame(note, state, tracker, ms, beat, mouse, start_ms, projected, radius)


func _feed_path_sample(state: Dictionary, tracker: PathProgress, point: Vector2, ms: float, projected: PackedVector2Array, radius: float, start_ms: float, tail_radius: float) -> void:
	tracker.feed(point, ms, projected, radius, start_ms, radius / tracker.contact_radius)
	if is_finite(float(state["path_finish_ms"])):
		return
	var ref := float(state.get("path_tail_ref_ms", float(state["end_ms"])))
	var end_sample := float(state.get("path_tail_end_ms", float(state["end_ms"])))
	var perfect := float(state.get("path_tail_perfect_early_ms", TAIL_PERFECT_MS))
	state["path_finish_ms"] = tracker.finish_contact(ref - maxf(PATH_TAIL_SWEEP_EARLY_MS, perfect),
		end_sample + TAIL_GOOD_MS, tail_radius, ref, perfect)


func _reset_path_motion() -> void:
	_write_path_input_log({"kind": "motion_reset", "paused": _paused, "auto": auto_play})
	_path_motion_samples.clear()
	for state in _states.values():
		var tracker: PathProgress = state.get("path_tracker")
		if tracker != null:
			tracker.reset_motion()


func _queue_path_motion(point: Vector2, ms: float) -> void:
	var discontinuity := _path_motion_samples.size() >= PATH_INPUT_CAPACITY
	if discontinuity:
		# Bound stalled-frame memory without joining across discarded movements.
		_path_motion_samples.clear()
	_path_motion_samples.append({"point": point, "time": ms, "break": discontinuity})


func _open_path_input_log() -> void:
	if not path_input_logging or chart == null or replay_mode:
		return
	_close_path_input_log()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_path_input_log_path = "user://logs/path_input_%s_%d.jsonl" % [stamp, Time.get_ticks_usec()]
	_path_input_log = FileAccess.open(_path_input_log_path, FileAccess.WRITE)
	if _path_input_log == null:
		return
	_write_path_input_log({"kind": "session", "schema": 2, "chart": chart_path,
		"title": chart.metadata.get("title", ""), "difficulty": chart.metadata.get("version", ""),
		"offset_ms": _active_offset(),
		"preview_size": _path_log_point(_preview.size), "start_beat": start_beat, "auto": auto_play})
	print("[path-input-log] ", ProjectSettings.globalize_path(_path_input_log_path))


func _write_path_input_log(record: Dictionary) -> void:
	if _path_input_log == null:
		return
	_path_input_log.store_line(JSON.stringify(record))
	if _path_input_log.get_position() >= PATH_LOG_LIMIT_BYTES:
		_path_input_log.store_line(JSON.stringify({"kind": "capture_limit", "bytes": PATH_LOG_LIMIT_BYTES}))
		_path_input_log.close()
		_path_input_log = null
	else:
		_path_input_log.flush()


func _close_path_input_log() -> void:
	if _path_input_log == null:
		return
	_write_path_input_log({"kind": "session_end", "hits": _hit_count, "misses": _miss_count})
	if _path_input_log != null:
		_path_input_log.close()
		_path_input_log = null


static func _path_log_point(point: Vector2) -> Array:
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01)] if point.is_finite() else []


func _record_path_input_frame(note: Note, state: Dictionary, tracker: PathProgress, ms: float, beat: float, mouse: Vector2, start_ms: float, projected: PackedVector2Array, radius: float) -> void:
	if _path_input_log == null or ms < float(state.get("path_log_next_ms", -INF)):
		return
	state["path_log_next_ms"] = ms + 200.0
	if not bool(state.get("path_log_geometry", false)):
		state["path_log_geometry"] = true
		var geometry: Array = []
		for point in tracker.points:
			geometry.append(_path_log_point(point))
		_write_path_input_log({"kind": "geometry", "note": note.id, "beat": note.beat,
			"end_beat": note.end_beat, "wait": note.wait_beat, "points": geometry,
			"gates": Array(tracker.gates), "contact_radius": tracker.contact_radius})
	var gate := mini(tracker.next_gate, tracker.gates.size() - 1)
	var next := int(tracker.gates[gate]) if gate >= 0 else -1
	var target := projected[next] if next >= 0 else Vector2.INF
	var target_radius := float(tracker.gate_radii[gate]) * _preview.path_judgement_scale() if gate >= 0 else radius
	var distance := mouse.distance_to(target)
	var reason := "before_body_start" if ms < start_ms else ("approaching_region" if distance > target_radius else "inside_region")
	var record := {"kind": "frame", "note": note.id, "time_ms": snappedf(ms, 0.01),
		"beat": beat, "start_ms": start_ms, "offset_ms": _active_offset(),
		"head_hit": state["head_hit"], "coverage": tracker.coverage, "progress": tracker.progress,
		"next": tracker.next_index, "next_gate": tracker.next_gate, "gate_count": tracker.group_count,
		"tolerance": tracker.tolerance, "remaining": tracker.remaining_groups(), "body_ready": tracker.body_ready(),
		"count": projected.size(), "cursor": _path_log_point(mouse), "target": _path_log_point(target),
		"distance": snappedf(distance, 0.01) if is_finite(distance) else -1.0,
		"radius": radius, "target_radius": target_radius, "target_index": next,
		"reason": reason, "sample_count": _path_motion_samples.size()}
	if not _path_motion_samples.is_empty():
		var first: Dictionary = _path_motion_samples[0]
		var last: Dictionary = _path_motion_samples[-1]
		record["sample_from"] = {"time": first["time"], "point": _path_log_point(first["point"])}
		record["sample_to"] = {"time": last["time"], "point": _path_log_point(last["point"])}
	_write_path_input_log(record)


func _judge_trace(note: Note, ms: float, beat: float, delta: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var start_ms := float(_states[note.id]["target_ms"])
	var end_ms := float(_states[note.id]["end_ms"])
	var contact := _trace_contact(note, mouse, beat)
	if not state["trace_started"]:
		if ms < start_ms - EARLY_MS:
			return
		var started := false
		if note.trace_style == "slider":
			var press := _take_assigned_press(note.id)
			if not press.is_empty():
				started = true
				_play_hit("path", 0.94)
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
			_play_hit("trace", randf_range(0.97, 1.03))
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
		_play_hit("trace", randf_range(0.97, 1.03))
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
	if ms < float(state.get("arm_from", target - BELL_WINDOW_MS)):
		return
	# 黄键式：窗口内光标在场只是“预备”，不提前结算，音符不会提前消失。
	# 判定用这一帧光标扫过的线段，进入即收：设计文档 §5.2 的示例就是沿线扫过
	# 一串 Bell，快速扫过时只要按点采样会整帧跨过金键、把整条路线判成漏。
	var previous: Vector2 = state.get("last_mouse", mouse)
	state["last_mouse"] = mouse
	var tolerance := Preview3D.BELL_CHAIN_TOLERANCE if bool(state.get("sweep_chain", false)) else Preview3D.BELL_RADIAL_TOLERANCE
	if not bool(state.get("armed", false)):
		if _preview.bell_swept_contains(note, beat, previous, mouse, tolerance):
			state["armed"] = true
			var lock: Dictionary = _preview.bell_screen(note, beat)
			if not lock.is_empty():
				_preview.add_hit_pulse(lock["center"], UITheme.KEY_YELLOW, "", "lock")
	if ms < target:
		return
	if bool(state.get("armed", false)):
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_register_hit("PERFECT")
		var bell: Dictionary = _preview.bell_screen(note, beat)
		if not bell.is_empty():
			_preview.add_hit_pulse(bell["center"], UITheme.KEY_YELLOW, "PERFECT", "bell")
		# 结算发生在判定线上，声音天然和音乐对齐。
		_play_hit("bell", randf_range(0.99, 1.01))
		_add_log("BELL #%d PERFECT" % note.id)
		return
	if ms > target + BELL_WINDOW_MS:
		state["done"] = true
		_preview.set_note_state(note.id, "miss")
		_miss_count += 1
		_add_judgement("MISS")
		_combo = 0
		var missed: Dictionary = _preview.bell_screen(note, beat)
		if not missed.is_empty():
			_preview.add_hit_pulse(missed["center"], UITheme.MUTED, "漏", "miss")
		_add_log("MISS Bell #%d @%.0fms" % [note.id, target])


func _judge_anchor(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := float(state["target_ms"])
	if ms < target - EARLY_MS:
		return
	var press := _take_assigned_press(note.id)
	if not press.is_empty():
		var anchor_error := press_error(press, target)
		var tier := _tier_for(anchor_error)
		state["done"] = true
		_preview.set_note_state(note.id, "hit")
		_register_hit(tier)
		_pulse_at(note.angle, beat, _tier_color(tier), tier, note.arc_width(), "tap", _timing_detail(anchor_error, tier))
		_play_hit("anchor", 1.0)
		_record_error(float(press["time"]) - target, "ANCHOR #%d %s" % [note.id, tier], tier, float(press["time"]))
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
					_preview.add_hit_pulse(center / float(polygon.size()), UITheme.RED, "LIMIT", "tap")
				_add_log("LIMIT #%d BREAK @ %.0fms" % [region.id, ms])
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


## One press belongs to the note whose timing/position fits it best. This runs
## once per frame before any note is judged, so a tap can no longer steal the
## press that belongs to a simultaneous slide head.
func _assign_presses(ms: float, beat: float) -> void:
	_press_assignments.clear()
	if _key_presses.is_empty():
		return
	var targets: Array[Dictionary] = []
	var last := mini(_ordered_notes.size(), _judge_from + 96)
	for i in range(maxi(0, _judge_from), last):
		var note := _ordered_notes[i]
		var target := _press_target(note, ms, beat)
		if not target.is_empty():
			targets.append(target)
	if targets.is_empty():
		return
	var pairs: Array[Dictionary] = []
	for press_index in _key_presses.size():
		var press: Dictionary = _key_presses[press_index]
		var stamp := float(press.get("time", -INF))
		var press_lo := float(press.get("lo", stamp))
		var press_hi := float(press.get("hi", stamp))
		for target in targets:
			if press_hi < float(target["lo"]) or press_lo > float(target["hi"]):
				continue
			var match := _match_press(press, target)
			if not bool(match.get("ok", false)):
				continue
			var distance := float(match["distance"])
			var note_target := float(target["target"])
			var error := absf(press_error(press, note_target))
			# 刚命中一颗后 50ms 内的额外按键：不许提前吃下一颗，避免手指蹭键把下一颗判成 GREAT。
			if press_is_stray(stamp, note_target, _last_hit_press_ms):
				continue
			# 光标已经压在图形上的那颗优先：按住时长再近，也不能把玩家指着的音符抢走。
			var on_shape := distance <= ON_SHAPE_PX
			if bool(target.get("dense", false)):
				var ring := maxf(1.0, float(target.get("ring_radius", 330.0)))
				on_shape = distance <= rad_to_deg(ON_SHAPE_PX / ring)
			var late := stamp > note_target
			pairs.append({
				"press": press_index,
				"note": int(target["id"]),
				"error": error,
				"rank": error + (LATE_PENALTY_MS if late else 0.0),
				"distance": distance,
				"on_shape": on_shape,
			})
	if pairs.is_empty():
		return
	pairs.sort_custom(prefer_press_pair)
	var used: Dictionary = {}
	for pair in pairs:
		var press_index := int(pair["press"])
		var note_id := int(pair["note"])
		if used.has(press_index) or _press_assignments.has(note_id):
			continue
		used[press_index] = true
		_press_assignments[note_id] = _key_presses[press_index]
		_last_hit_press_ms = float(_key_presses[press_index].get("time", _last_hit_press_ms))
	if used.is_empty():
		return
	var kept: Array[Dictionary] = []
	for i in _key_presses.size():
		if not used.has(i):
			kept.append(_key_presses[i])
	_key_presses = kept


## 刚命中后紧跟着的额外按键，不允许提前吃下一颗（防手指蹭键）。
static func press_is_stray(stamp: float, target: float, last_hit: float) -> bool:
	return stamp < target - PERFECT_MS and stamp > last_hit + 0.1 and stamp - last_hit < STRAY_GUARD_MS


## 按键分配排序：光标压在图形上的那颗优先；否则按“时间误差 + 晚到代价”，再按距离。
static func prefer_press_pair(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["on_shape"]) != bool(b["on_shape"]):
		return bool(a["on_shape"])
	var rank_a := float(a.get("rank", a.get("error", 0.0)))
	var rank_b := float(b.get("rank", b.get("error", 0.0)))
	if absf(rank_a - rank_b) > 0.001:
		return rank_a < rank_b
	return float(a["distance"]) < float(b["distance"])


## What press a note is waiting for this frame, or {} when it needs none.
func _press_target(note: Note, ms: float, beat: float) -> Dictionary:
	if not _states.has(note.id):
		return {}
	var state: Dictionary = _states[note.id]
	if bool(state.get("done", false)):
		return {}
	var target := float(state["target_ms"])
	# A press is only assigned once the note is actually judgeable; otherwise an
	# early press would be consumed while the note is still outside its window.
	if ms < target - EARLY_MS:
		return {}
	# Skip notes far outside the current press pool before projecting anything.
	if target + HIT_WINDOW_MS < ms - 60.0 or target - EARLY_MS > ms + 60.0:
		return {}
	match note.type:
		"tap":
			return _shape_target(note, target - EARLY_MS, target + HIT_WINDOW_MS, target,
				_preview.note_live_band(note, beat, 0.0),
				POSITION_TOLERANCE_PX + float(_preview.note_graphic_radius(note.type)), 0.0)
		"hold":
			if bool(state.get("started", false)):
				return {}
			return _shape_target(note, target - EARLY_MS, target + HIT_WINDOW_MS, target,
				_preview.note_live_band(note, beat, HOLD_ARC_PAD),
				POSITION_TOLERANCE_PX + float(_preview.note_graphic_radius(note.type)), HOLD_ARC_PAD)
		"path":
			if bool(state.get("head_judged", false)) or ms < target - EARLY_MS:
				return {}
			return _shape_target(note, target - EARLY_MS, target + HIT_WINDOW_MS, target,
				PackedVector2Array([_preview.note_head_screen(note, beat)]),
				POSITION_TOLERANCE_PX + float(_preview.note_graphic_radius("path")), 0.0)
		"anchor":
			return _shape_target(note, target - EARLY_MS, target + HIT_WINDOW_MS, target,
				PackedVector2Array([_preview.note_head_screen(note, beat)]),
				POSITION_TOLERANCE_PX + float(_preview.note_graphic_radius(note.type)), 0.0)
		"trace":
			if bool(state.get("trace_started", false)) or note.trace_style != "slider":
				return {}
			var trace := _preview.trace_screen_points(note, beat)
			if trace.is_empty():
				return {}
			return {"id": note.id, "note": note, "lo": target - EARLY_MS, "hi": target + HIT_WINDOW_MS,
				"target": target, "points": PackedVector2Array([trace[0]]),
				"tolerance": TRACE_HEAD_RADIUS, "pad": 0.0, "dense": false}
	return {}


func _shape_target(note: Note, lo: float, hi: float, target: float, points: PackedVector2Array,
		tolerance: float, pad: float) -> Dictionary:
	var dense := _dense_ids.has(note.id)
	var ring_radius := 1.0
	if dense and not points.is_empty():
		ring_radius = maxf(1.0, _preview.project_design(Vector2.ZERO).distance_to(points[points.size() / 2]))
	return {"id": note.id, "note": note, "lo": lo, "hi": hi, "target": target,
		"points": points, "tolerance": tolerance, "pad": pad, "dense": dense,
		"ring_radius": ring_radius}


## Pure match used both by the assignment pass and by diagnostics.
func _match_press(press: Dictionary, target: Dictionary) -> Dictionary:
	var note: Note = target["note"]
	var points: PackedVector2Array = target["points"]
	if points.is_empty():
		return {}
	var tolerance := float(target["tolerance"])
	var pad := float(target["pad"])
	if bool(target["dense"]):
		var slack := rad_to_deg(tolerance / maxf(1.0, float(target.get("ring_radius", 1.0))))
		var half := maxf(24.0, (0.0 if points.size() <= 1 else note.arc_width() + pad + 2.0 * slack) * 0.5)
		if not bool(press.get("valid", true)):
			return {}
		var press_angle := float(press.get("angle", NAN))
		if is_nan(press_angle):
			return {}
		var delta := absf(JudgeMath.angle_delta(press_angle, note.angle))
		if delta > half:
			return {}
		return {"ok": true, "distance": delta}
	var mouse: Vector2 = press.get("mouse", Vector2.ZERO)
	var distance := _distance_to_polyline(mouse, points)
	if distance > tolerance:
		return {}
	return {"ok": true, "distance": distance}


func _take_assigned_press(note_id: int) -> Dictionary:
	var press: Variant = _press_assignments.get(note_id)
	if press == null:
		return {}
	_press_assignments.erase(note_id)
	return press


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



func _record_error(error_ms: float, label: String, tier: String = "", time_ms: float = -1.0) -> void:
	_errors.append(error_ms)
	if not tier.is_empty():
		_scatter.append({
			"offset": error_ms,
			"tier": tier,
			"time": time_ms if time_ms >= 0.0 else _judge_ms_now,
		})
	_error_sum += error_ms
	_add_log("%s  %+.0fms" % [label, error_ms])
	if _app == null or replay_mode or not bool(_app.dynamic_offset) or _errors.size() < DYNAMIC_SAMPLE_MIN:
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
	if _app == null or replay_mode:
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
	var offset := _active_offset()
	var skin_label := String(Preview3D.skin_presets().get(_preview.note_skin, {}).get("label", _preview.note_skin))
	var fx_label := String(Preview3D.hit_fx_presets().get(_preview.hit_fx_style, _preview.hit_fx_style))
	if _style_label != null:
		_style_label.text = "%s · %s" % [skin_label, fx_label]
	_top_stats.text = "%sHIT %d  MISS %d  ACC %s  COMBO %d  |  LIMIT %d  |  BIA %+.1fms  OFF %+.0fms" % [
		"[REPLAY] " if replay_mode else ("[AUTO] " if auto_play else ""),
		_hit_count,
		_miss_count,
		"—" if accuracy < 0.0 else "%.1f%%" % accuracy,
		_combo,
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
## 目标帧时：设置的上限和屏幕刷新率里更严的那个（刷新率读不到就按 60）。
## 返回 0 表示「不限帧」——玩家自己选了不限帧，就别替他降画质。
func _frame_budget_ms() -> float:
	var cap := int(Engine.max_fps)
	var refresh := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	if cap <= 0 and not refresh:
		return 0.0
	var hz := DisplayServer.screen_get_refresh_rate()
	var limit := float(cap) if cap > 0 else 1.0e9
	if hz > 1.0:
		limit = minf(limit, hz)
	if limit > 1.0e8:
		limit = 60.0
	return 1000.0 / maxf(30.0, limit)


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
	# 弱机保护：连续两个统计窗口都装不下目标帧时降一档画质（只降不升，避免来回抖）。
	var budget := _frame_budget_ms()
	# 导出视频时不要降档：渲染慢是因为在写视频，不是机器带不动。
	if not export_mode and budget > 0.0 and median > budget * 1.12:
		_slow_windows += 1
		if _slow_windows >= 2 and _preview.quality_level == 0:
			_preview.set_quality_level(1)
			_add_log("画质降档：中位帧 %.1fms，超预算 %.1fms" % [median, budget])
	else:
		_slow_windows = 0
	# 只在出现明显卡顿时打印，正常游玩不会刷屏。
	if (worst > 8.0 or spikes > 20) and OS.is_debug_build():
		print("[frame] t=%.1fs n=%d med=%.1fms p95=%.1fms max=%.1fms spikes=%d notes=%d" % [
			_chart_ms() / 1000.0, n, median, p95, worst, spikes, _ordered_notes.size(),
		])
		print("[frame] beat_stalls=%d / %d frames" % [_beat_stalls, n])
		_beat_stalls = 0
	_frame_samples.clear()
	_frame_since_usec = now


## 按键真实时刻只知道落在一帧的区间里。判定取区间内最靠近判定线的点：
## 60fps 最多差 8ms，30fps 17ms，卡顿帧自动覆盖——低帧率不会白掉一档。
static func press_error(press: Dictionary, target: float) -> float:
	var mid := float(press.get("time", target))
	var lo := float(press.get("lo", mid))
	var hi := float(press.get("hi", mid))
	if lo > hi:
		var swap := lo
		lo = hi
		hi = swap
	return clampf(target, lo, hi) - target


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
## 尾判档位。参考点是「星星进入尾区」：
## - 早到按 entry 算，Perfect/Great 用尾区停留/4 扩展（maimai 的 dwell 补偿）；
## - 晚到按 end 算，避免“跟着星星走到终点”反而被判晚。
## 这样尾区入口和终点都会落在 PERFECT，符合 maimai
## “贴着星星划”和“等星星进最后区再划”判得一样”的设计。
static func tail_tier(error_ms: float, dwell_ms := 0.0) -> String:
	var dwell := maxf(0.0, dwell_ms)
	var extension := minf(dwell * 0.25, TAIL_EXT_MAX_MS)
	var perfect_early := TAIL_PERFECT_MS + extension
	var great_early := maxf(TAIL_GREAT_MS + extension, perfect_early)
	if error_ms < 0.0:
		var early := -error_ms
		if early <= perfect_early:
			return "PERFECT"
		if early <= great_early:
			return "GREAT"
		# maimai 的滑条早到永远不会 Miss（Fast Good）。
		return "GOOD"
	var late := error_ms - dwell
	if late <= TAIL_PERFECT_MS:
		return "PERFECT"
	if late <= TAIL_GREAT_MS:
		return "GREAT"
	if late <= TAIL_GOOD_MS:
		return "GOOD"
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


## Godot 4 的 InputEvent 没有时间戳，按键只能在“上一次输入刷新 → 现在”之间按下。
## 判定时用这个区间取对玩家最有利的落点：帧越长（低帧率、卡顿帧）不确定度越大，
## 但最多只放宽 INPUT_SPAN_MAX_MS，不会变成白送。
func _input_interval(now_ms: float) -> Vector2:
	var span := minf(_last_frame_ms, INPUT_SPAN_MAX_MS)
	return Vector2(now_ms - span, now_ms)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _running and not _paused and not _finished and not auto_play and not replay_mode:
			var point: Vector2 = _preview.get_global_transform_with_canvas().affine_inverse() * event.position
			var move_ms := _chart_ms() + _active_offset()
			_queue_path_motion(point, move_ms)
			if _recording and _record != null:
				_record.add_move(move_ms, point)
		return
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var span := _input_interval(_chart_ms() + _active_offset())
		var direction := 0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if not replay_mode:
			_seek_presses.append({
				"time": (span.x + span.y) * 0.5,
				"lo": span.x,
				"hi": span.y,
				"orien": direction,
			})
			if _recording and _record != null:
				_record.add_seek((span.x + span.y) * 0.5, span.x, span.y, direction)
		get_viewport().set_input_as_handled()
		return
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
		if event.keycode == KEY_SPACE and event.pressed and not event.echo:
			if not _finished:
				_set_paused(not _paused)
			get_viewport().set_input_as_handled()
			return
		if replay_mode:
			if event.pressed and not event.echo and not _paused and not _finished:
				match event.keycode:
					KEY_HOME:
						_seek_replay(0.0)
					KEY_LEFT:
						_seek_relative(-5000.0)
					KEY_RIGHT:
						_seek_relative(5000.0)
					_:
						return
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
			if event.keycode == KEY_F9:
				path_input_logging = not path_input_logging
				if path_input_logging:
					_open_path_input_log()
				else:
					_close_path_input_log()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_F10:
				_set_path_judgement_visible(not _preview.show_path_judgement)
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
			if not _running or _paused or _finished:
				return
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var span := _input_interval(_chart_ms() + _active_offset())
			var stamp := (span.x + span.y) * 0.5
			# 同一个键的手抖双击只算一次；和弦用不同键，不受影响。
			var repeated := stamp - float(_last_press_ms.get(key, -INF)) < KEY_DEBOUNCE_MS
			_last_press_ms[key] = stamp
			if not repeated:
				_key_presses.append({
					"time": stamp,
					"lo": span.x,
					"hi": span.y,
					"mouse": _preview.mouse_screen,
					"angle": _preview.screen_angle_deg(_preview.mouse_screen),
					"u": _preview.cursor_u,
					"valid": _preview.cursor_valid,
					"key": key,
				})
				if _recording and _record != null:
					_record.add_press(stamp, span.x, span.y, key, _preview.mouse_screen,
						_preview.screen_angle_deg(_preview.mouse_screen), _preview.cursor_u, _preview.cursor_valid)
			_keys_held[key] = true
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			_keys_held.erase(key)
			if _recording and _record != null:
				var release_span := _input_interval(_chart_ms() + _active_offset())
				_record.add_release((release_span.x + release_span.y) * 0.5, key)
			get_viewport().set_input_as_handled()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _replay_bar != null:
		_replay_bar.visible = false
	if _record != null and not replay_mode:
		_record.result = {
			"hit": _hit_count,
			"miss": _miss_count,
			"max_combo": _max_combo,
			"tiers": _tier_counts.duplicate(),
		}
	_close_path_input_log()
	_running = false
	if _audio != null:
		_audio.stop()
	_preview.playing = false
	_preview.set_process(true)
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
	lines.append("Limit 断连：%d 次" % _red_breaks)
	var average_error := _mean_error()
	# AUTO 的“误差”恒为 0，不能让它把动态 offset 带偏。
	if not auto_play:
		_flush_offset()
	if _timing_chart != null:
		_timing_chart.set_errors(_errors)
	if _scatter_chart != null:
		var span := 0.0
		if chart != null:
			span = chart.timing.beat_to_chart_ms(chart.duration_beats()) + _active_offset()
		_scatter_chart.set_hits(_scatter, span)
	if _bias_label != null:
		_bias_label.text = "平均判定偏差 %+.2f 毫秒   ·   不稳定率 (UR) %.2f   ·   样本 %d   ·   当前 offset %+.0fms" % [
			average_error,
			_unstable_rate(),
			_errors.size(),
			_active_offset(),
		]
	if _replay_button != null:
		var can_replay := false
		if replay_mode:
			can_replay = replay_source != null
		else:
			can_replay = _record != null and _record.event_count() > 0
		_replay_button.disabled = not can_replay
	if _save_replay_button != null:
		_save_replay_button.disabled = _current_replay() == null
	if _apply_bias_button != null:
		var delta := -average_error
		var can_apply: bool = not auto_play and not replay_mode and _errors.size() >= 8 and absf(delta) >= 1.0 \
			and _app != null and (not _app.set_path.is_empty() or not _app.chart_path.is_empty())
		_apply_bias_button.disabled = not can_apply
		_apply_bias_button.text = ("把本局偏差写进本谱面（offset %+.0fms）" % delta) if can_apply else "把本局偏差写进本谱面"
		_apply_bias_button.tooltip_text = ("本局样本不足或偏差 <1ms，不需要改谱面" if not can_apply
			else "这是「本局平均偏差」的反向值：谱面 offset 会从 %+.0f 变成 %+.0f；只改这一张" % [
				float(chart.offset_ms), clampf(float(chart.offset_ms) + delta, -10000.0, 10000.0)])
	lines.append("")
	lines.append("事件日志（最近 24 条）：")
	for i in range(maxi(0, _log.size() - 24), _log.size()):
		lines.append("  %s" % _log[i])
	_results_text.text = "\n".join(lines)
	_results.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if export_mode:
		# 录视频时不要把结算页录进去：藏起来，喘 0.4 秒让最后几帧写盘，然后退出。
		_results.visible = false
		get_tree().create_timer(0.4).timeout.connect(func() -> void: get_tree().quit(0))


## 一次修一张：把「本局平均偏差」反向加到这张谱面的 offset 并存盘。
## 玩家普遍按得偏早（bias < 0）时 offset 变大，音符相对音频提前，下次就能贴着拍子按。
func _apply_bias_to_chart() -> void:
	if _app == null or chart == null or _errors.size() < 8:
		return
	if _app.chart != chart:
		_notify_result("谱面已换掉，未写回 offset")
		return
	var bias := _mean_error()
	var offset := chart_offset_for_bias(float(chart.offset_ms), bias)
	chart.offset_ms = offset
	chart.timing.offset_ms = offset
	if not _app.save_chart():
		_notify_result("写回 offset 失败（保存被拒绝）")
		return
	_notify_result("谱面 offset → %+.1fms（本局偏差 %+.1fms，已保存）" % [offset, bias])
	if _apply_bias_button != null:
		_apply_bias_button.disabled = true
		_apply_bias_button.text = "已写入 offset %+.0fms" % offset
		_apply_bias_button.tooltip_text = "这一张谱面的 offset 已保存；想撤销就重新打开谱面改回去"


## 把本局偏差换算成谱面 offset（纯函数，符号有回归测试）。
static func chart_offset_for_bias(current_offset_ms: float, bias_ms: float) -> float:
	return clampf(current_offset_ms - bias_ms, -10000.0, 10000.0)


## 结算页已经在显示，往上补一行，而不是只写进看不到的 _log。
func _notify_result(message: String) -> void:
	_add_log(message)
	if _results_text != null:
		_results_text.text += "\n" + message


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
	_close_path_input_log()
	if _audio != null:
		_audio.stop()
	_flush_offset()
	Input.set_use_accumulated_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	exit_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_path_input_log()
		Input.set_use_accumulated_input(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 切出窗口时自动暂停，避免切走的几秒把谱面打空。
		if _running and not _paused and not _finished:
			_set_paused(true)
