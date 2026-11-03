class_name Playtest
extends Control

signal exit_requested

const HIT_WINDOW_MS := 40.0
const BELL_WINDOW_MS := 100.0
const RED_LIMIT_SEC := 0.2

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
var _bell_total: int = 0
var _bell_hits: int = 0
var _red_breaks: int = 0
var _errors: Array[float] = []
var _log: Array[String] = []
var _combo: int = 0
var _max_combo: int = 0
var _sfx: HitSfx

var _top_time: Label
var _top_stats: Label
var _results: PanelContainer
var _results_text: RichTextLabel
var _results_button: Button


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sfx = HitSfx.new()
	_sfx.name = "PlaytestHitSfx"
	add_child(_sfx)
	_build_ui()


func setup(p_chart: Chart, p_start_beat: float, p_chart_path: String) -> void:
	chart = p_chart
	start_beat = p_start_beat
	chart_path = p_chart_path
	_init_states()
	_last_chart_ms = -INF
	_preview.chart_override = chart
	_preview.follow_app = false
	_preview.playtest_mode = true
	_preview.custom_cursor_visible = true
	_preview.show_hud = true
	_preview.use_3d_ring = true
	_preview.mouse_tilt = true
	_preview.show_debug = false
	_preview.flow_scale = float(_app.flow_scale if _app != null else 1.0)
	_preview.time_beat = start_beat
	_preview.playing = true
	_preview.visible = true
	_start_audio()
	_running = true
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
	hint.text = "Esc 结束试玩"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.MUTED)
	row.add_child(hint)

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
	_results.custom_minimum_size = Vector2(520, 320)
	add_child(_results)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -260
	_results.offset_top = -160
	_results.offset_right = 260
	_results.offset_bottom = 160
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_results.add_child(box)
	var title := Label.new()
	title.text = "试玩结束"
	UITheme.style_section(title)
	box.add_child(title)
	_results_text = RichTextLabel.new()
	_results_text.bbcode_enabled = false
	_results_text.fit_content = false
	_results_text.scroll_active = true
	_results_text.custom_minimum_size = Vector2(480, 230)
	_results_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results_text)
	_results_button = Button.new()
	_results_button.text = "返回编辑器（Esc）"
	_results_button.pressed.connect(func() -> void: _exit())
	box.add_child(_results_button)

	var bottom := Label.new()
	bottom.text = "任意有效键：Tap / Hold / Anchor；Path / Bell / Trace 用鼠标定位；Red 停留 200ms 断连；[ / ] 调整判定偏移。"
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
	_bell_total = 0
	_bell_hits = 0
	_red_breaks = 0
	_errors.clear()
	_log.clear()
	_combo = 0
	_max_combo = 0
	_ordered_notes = chart.sorted_notes()
	for note in _ordered_notes:
		_states[note.id] = {
			"done": false,
			"head": false,
			"started": false,
			"head_judged": false,
			"tail_judged": false,
			"head_hit": false,
			"tail_hit": false,
			"next_sample": 0,
			"samples": [],
			"trace_started": false,
			"trace_distance": 0.0,
			"trace_last": Vector2.ZERO,
			"trace_contact": false,
		}
		if note.type == "bell":
			_bell_total += 1
	for region in chart.regions:
		_red_states[region.id] = {"time": 0.0, "broken": false}


func _start_audio() -> void:
	_last_chart_ms = -INF
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
	_audio.finished.connect(_finish)
	var from_sec := maxf(0.0, (_start_chart_ms - chart.offset_ms) / 1000.0)
	_audio.play(from_sec)


func _process(delta: float) -> void:
	if not _running or chart == null:
		return
	var chart_ms := _chart_ms()
	var judge_ms := chart_ms + float(_app.playtest_offset_ms if _app != null else 0.0)
	var beat := chart.timing.chart_ms_to_beat(chart_ms)
	_preview.time_beat = beat
	_preview.playing = true
	_judge_all(judge_ms, beat, delta)
	_ui_accum += delta
	if _ui_accum >= 0.05:
		_ui_accum = 0.0
		_update_top_bar(chart_ms, beat)
		_update_hud()
	if beat > chart.duration_beats() + 2.0:
		_finish()
	while not _key_presses.is_empty() and float(_key_presses[0].get("time", -INF)) < judge_ms - 300.0:
		_key_presses.pop_front()


func _chart_ms() -> float:
	if _audio_available and _audio.playing:
		var stream_ms := (_audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0
		var candidate := stream_ms + chart.offset_ms
		if not is_finite(candidate) or candidate > 1.0e9:
			candidate = _last_chart_ms
		elif _last_chart_ms > -INF:
			if candidate < _last_chart_ms - 250.0:
				_last_chart_ms = candidate
			elif candidate < _last_chart_ms:
				candidate = _last_chart_ms
		_last_chart_ms = maxf(_last_chart_ms, candidate)
		return _last_chart_ms
	var elapsed := float(Time.get_ticks_usec() - _start_usec) / 1000.0
	var fallback := _start_chart_ms + elapsed
	if _last_chart_ms > -INF and fallback < _last_chart_ms:
		fallback = _last_chart_ms
	_last_chart_ms = fallback
	return fallback


func _judge_all(ms: float, beat: float, delta: float) -> void:
	var cursor_u: float = _preview.cursor_u
	var valid: bool = _preview.cursor_valid
	var mouse: Vector2 = _preview.mouse_screen
	for note in _ordered_notes:
		if _states[note.id]["done"]:
			continue
		match note.type:
			"tap":
				_judge_tap(note, ms, beat)
			"hold":
				_judge_hold(note, ms, beat)
			"path":
				_judge_path(note, ms, beat, cursor_u, valid, mouse)
			"trace":
				_judge_trace(note, ms, delta, mouse)
			"anchor":
				_judge_anchor(note, ms, beat)
			"bell":
				_judge_bell(note, ms, beat, mouse)
	_judge_red(ms, beat, delta, cursor_u, valid)


func _judge_tap(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := chart.timing.beat_to_chart_ms(note.beat)
	if note.space == "plane":
		if ms < target - HIT_WINDOW_MS:
			return
		var point := _preview.plane_screen(note.plane_x, note.plane_y)
		var press := _take_key_for_plane(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, point, _preview.plane_note_judge_radius(note))
		if not press.is_empty():
			state["done"] = true
			_hit_count += 1
			_combo += 1
			_max_combo = maxi(_max_combo, _combo)
			_preview.add_hit_pulse(point, UITheme.CORAL, "HIT")
			_sfx.play("don", randf_range(0.98, 1.02))
			_record_error(float(press["time"]) - target, "PLANE TAP #%d HIT" % note.id)
			return
		if ms > target + HIT_WINDOW_MS:
			state["done"] = true
			_miss_count += 1
			_combo = 0
			_add_log("MISS Plane Tap #%d @ %.0fms" % [note.id, target])
		return
	if ms < target - HIT_WINDOW_MS:
		return
	var press := _take_key_for_arc(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, note.angle, note.width)
	if not press.is_empty():
		state["done"] = true
		_hit_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_pulse_at(note.angle, beat, UITheme.CORAL, "HIT")
		_sfx.play(HitSfx.kind_for_note(note), randf_range(0.98, 1.02))
		_record_error(float(press["time"]) - target, "Tap #%d HIT" % note.id)
		return
	if ms > target + HIT_WINDOW_MS:
		state["done"] = true
		_miss_count += 1
		_combo = 0
		_add_log("MISS Tap #%d @ %.0fms" % [note.id, target])


func _judge_hold(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := chart.timing.beat_to_chart_ms(note.beat)
	var end_ms := chart.timing.beat_to_chart_ms(note.end_beat)
	if not state["started"]:
		if ms < target - HIT_WINDOW_MS:
			return
		var press := _take_key_for_arc(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS, note.angle, note.width)
		if not press.is_empty():
			state["started"] = true
			state["head"] = true
			_pulse_at(note.angle, beat, UITheme.AMBER, "HOLD")
			_sfx.play("don", 0.82)
			_add_log("HOLD #%d HEAD" % note.id)
			return
		if ms > target + HIT_WINDOW_MS:
			state["done"] = true
			_miss_count += 1
			_combo = 0
			_add_log("MISS Hold #%d (head)" % note.id)
		return
	if _keys_held.is_empty():
		state["done"] = true
		_miss_count += 1
		_combo = 0
		_add_log("MISS Hold #%d (released)" % note.id)
		return
	if ms >= end_ms:
		state["done"] = true
		_hit_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_pulse_at(note.angle, beat, UITheme.AMBER, "HOLD")
		_sfx.play("don", 1.18)
		_record_error(ms - end_ms, "HOLD #%d COMPLETE" % note.id)


func _judge_path(note: Note, ms: float, beat: float, cursor_u: float, valid: bool, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var head_ms := chart.timing.beat_to_chart_ms(note.beat)
	var tail_ms := chart.timing.beat_to_chart_ms(note.end_beat)
	if not state["head_judged"]:
		if ms >= head_ms - HIT_WINDOW_MS and valid and JudgeMath.in_arc(cursor_u * 360.0, note.angle, note.width):
			state["head_hit"] = true
			_hit_count += 1
			_combo += 1
			_max_combo = maxi(_max_combo, _combo)
			_pulse_at(note.angle, beat, UITheme.CORAL, "HIT")
			_sfx.play("don", 1.10)
			_add_log("PATH #%d HEAD HIT" % note.id)
			state["head_judged"] = true
		elif ms > head_ms + HIT_WINDOW_MS:
			state["head_hit"] = false
			_miss_count += 1
			_combo = 0
			_add_log("PATH #%d HEAD MISS" % note.id)
			state["head_judged"] = true
	if not state["tail_judged"] and ms >= tail_ms - HIT_WINDOW_MS:
		if valid and JudgeMath.in_arc(cursor_u * 360.0, note.tail_angle, note.tail_width):
			state["tail_hit"] = true
			_hit_count += 1
			_combo += 1
			_max_combo = maxi(_max_combo, _combo)
			_pulse_at(note.tail_angle, beat, UITheme.GOLD, "HIT")
			_sfx.play("tail", randf_range(0.98, 1.02))
			_add_log("PATH #%d TAIL HIT" % note.id)
			state["tail_judged"] = true
		elif ms > tail_ms + HIT_WINDOW_MS:
			state["tail_hit"] = false
			_miss_count += 1
			_combo = 0
			_add_log("PATH #%d TAIL MISS" % note.id)
			state["tail_judged"] = true
	if state["tail_judged"] and not state["done"]:
		var samples: Array = state["samples"]
		var status := "FULL"
		if not samples.is_empty() and not bool(samples[-1]):
			status = "LOST"
		elif samples.has(false):
			status = "FRAY"
		_add_log("PATH #%d %s" % [note.id, status])
		state["done"] = true
	# Mid-section samples, one per frame.
	if ms >= head_ms and ms <= tail_ms:
		var sample_beats := note.path_sample_beats()
		var index: int = state["next_sample"]
		while index < sample_beats.size():
			var sample_beat := sample_beats[index]
			var sample_ms := chart.timing.beat_to_chart_ms(sample_beat)
			if sample_ms > ms:
				break
			var rel := clampf(sample_beat - note.beat, 0.0, note.duration())
			var tolerance_px := clampf(24.0 * (note.tolerance / 0.24), 8.0, 64.0)
			var distance := _preview.path_distance(note, rel, beat, mouse)
			var inside := valid and distance <= tolerance_px
			var samples: Array = state["samples"]
			samples.append(inside)
			state["samples"] = samples
			index += 1
		state["next_sample"] = index


func _judge_trace(note: Note, ms: float, delta: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var start_ms := chart.timing.beat_to_chart_ms(note.beat)
	var end_ms := chart.timing.beat_to_chart_ms(note.end_beat)
	var contact := _trace_contact(note, mouse)
	if not state["trace_started"]:
		if ms >= start_ms - HIT_WINDOW_MS and ms <= start_ms + HIT_WINDOW_MS and contact:
			state["trace_started"] = true
			state["trace_contact"] = true
			state["trace_last"] = mouse
			_add_log("TRACE #%d CONTACT" % note.id)
		elif ms > start_ms + HIT_WINDOW_MS:
			state["done"] = true
			_miss_count += 1
			_combo = 0
			_add_log("MISS Trace #%d (no contact)" % note.id)
		return
	if contact:
		if state["trace_contact"]:
			var last: Vector2 = state["trace_last"]
			state["trace_distance"] = float(state["trace_distance"]) + last.distance_to(mouse)
		state["trace_contact"] = true
		state["trace_last"] = mouse
	else:
		state["trace_contact"] = false
	if float(state["trace_distance"]) >= note.move_px:
		state["done"] = true
		_hit_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_preview.add_hit_pulse(mouse, UITheme.MINT, "TRACE")
		_sfx.play("trace", randf_range(0.97, 1.03))
		_add_log("TRACE #%d HIT (%.0f/%.0f px)" % [note.id, float(state["trace_distance"]), note.move_px])
		return
	if ms > end_ms + HIT_WINDOW_MS:
		state["done"] = true
		_miss_count += 1
		_combo = 0
		_add_log("MISS Trace #%d (distance %.0f/%.0f)" % [note.id, float(state["trace_distance"]), note.move_px])


func _trace_contact(note: Note, mouse: Vector2) -> bool:
	if note.trace_pts.size() < 2:
		return false
	var polyline: Array[Vector2] = []
	for point in _preview.trace_screen_points(note):
		polyline.append(point)
	return JudgeMath.trace_distance(mouse, polyline) <= 34.0


func _judge_bell(note: Note, ms: float, beat: float, mouse: Vector2) -> void:
	var state: Dictionary = _states[note.id]
	var target := chart.timing.beat_to_chart_ms(note.beat)
	if ms < target - BELL_WINDOW_MS:
		return
	if ms <= target + BELL_WINDOW_MS:
		var bell: Dictionary = _preview.bell_screen(note, beat)
		if not bell.is_empty() and mouse.distance_to(bell["center"]) <= float(bell["radius"]):
			state["done"] = true
			_bell_hits += 1
			_preview.add_hit_pulse(bell["center"], UITheme.GOLD, "BELL")
			_sfx.play("bell", randf_range(0.99, 1.01))
			_add_log("BELL #%d COLLECTED" % note.id)
			return
	if ms > target + BELL_WINDOW_MS:
		state["done"] = true
		_add_log("BELL #%d MISSED" % note.id)


func _judge_anchor(note: Note, ms: float, beat: float) -> void:
	var state: Dictionary = _states[note.id]
	var target := chart.timing.beat_to_chart_ms(note.beat)
	if ms < target - HIT_WINDOW_MS:
		return
	var press := _take_key_in_window(target - HIT_WINDOW_MS, target + HIT_WINDOW_MS)
	if not press.is_empty():
		state["done"] = true
		_hit_count += 1
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		_pulse_at(note.angle, beat, UITheme.VIOLET, "HIT")
		_sfx.play("don", 1.22)
		_record_error(float(press["time"]) - target, "ANCHOR #%d HIT" % note.id)
		return
	if ms > target + HIT_WINDOW_MS:
		state["done"] = true
		_miss_count += 1
		_combo = 0
		_add_log("MISS Anchor #%d" % note.id)


func _judge_red(ms: float, beat: float, delta: float, cursor_u: float, valid: bool) -> void:
	for region in chart.regions:
		var state: Dictionary = _red_states[region.id]
		if not region.active_at(beat):
			state["time"] = 0.0
			state["broken"] = false
			continue
		var inside := valid and JudgeMath.in_arc(cursor_u * 360.0, region.angle, region.width)
		if inside:
			state["time"] = float(state["time"]) + delta
			if float(state["time"]) >= RED_LIMIT_SEC and not bool(state["broken"]):
				state["broken"] = true
				_red_breaks += 1
				_miss_count += 1
				_add_log("RED #%d BREAK @ %.0fms" % [region.id, ms])
		else:
			state["time"] = 0.0
			state["broken"] = false


func _pulse_at(angle_degrees: float, beat: float, color: Color, label: String) -> void:
	if _preview == null:
		return
	var p: Vector2 = _preview.project_u(fposmod(angle_degrees, 360.0) / 360.0, beat)
	if p.is_finite() and p.x < 1.0e9:
		_preview.add_hit_pulse(p, color, label)


func _take_key_in_window(lo: float, hi: float) -> Dictionary:
	# 早按可以跨帧保留：只取落在窗口内的一枚，过旧的不阻塞后面的按键。
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		_key_presses.remove_at(i)
		return press
	return {}


func _take_key_for_arc(lo: float, hi: float, angle: float, width: float) -> Dictionary:
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		var press_u := float(press.get("u", 0.0)) * 360.0
		if bool(press.get("valid", false)) and JudgeMath.in_arc(press_u, angle, width):
			_key_presses.remove_at(i)
			return press
	return {}


func _take_key_for_plane(lo: float, hi: float, point: Vector2, radius: float) -> Dictionary:
	for i in _key_presses.size():
		var press: Dictionary = _key_presses[i]
		var stamp := float(press.get("time", -INF))
		if stamp < lo:
			continue
		if stamp > hi:
			break
		var press_mouse: Vector2 = press.get("mouse", Vector2.ZERO)
		if press_mouse.distance_to(point) <= radius:
			_key_presses.remove_at(i)
			return press
	return {}


func _record_error(error_ms: float, label: String) -> void:
	_errors.append(error_ms)
	if _errors.size() > 20:
		_errors.pop_front()
	_add_log("%s  %+.0fms" % [label, error_ms])


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
	_top_stats.text = "HIT %d  MISS %d  ACC %s  COMBO %d  |  BELL %d/%d  RED %d  |  OFF %+.0fms" % [
		_hit_count,
		_miss_count,
		"—" if accuracy < 0.0 else "%.1f%%" % accuracy,
		_combo,
		_bell_hits,
		_bell_total,
		_red_breaks,
		offset,
	]


func _update_hud() -> void:
	var accuracy := _accuracy()
	_preview.hud_accuracy = accuracy
	_preview.hud_rating = _rating(accuracy)
	_preview.hud_errors = _errors.duplicate()


func _accuracy() -> float:
	var total := _hit_count + _miss_count
	if total <= 0:
		return -1.0
	return 100.0 * float(_hit_count) / float(total)


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
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			if _finished:
				_exit()
			else:
				_finish()
			get_viewport().set_input_as_handled()
			return
		if event.pressed and not event.echo:
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
				"u": _preview.cursor_u,
				"valid": _preview.cursor_valid,
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
	lines.append("命中 %d / 失误 %d" % [_hit_count, _miss_count])
	lines.append("调试准确率：%s" % ("—" if _accuracy() < 0.0 else "%.2f%%" % _accuracy()))
	lines.append("评级：%s（预览/非正式）" % _rating(_accuracy()))
	lines.append("最大连击：%d" % _max_combo)
	lines.append("Bell 收集：%d / %d" % [_bell_hits, _bell_total])
	lines.append("Red 断连：%d 次" % _red_breaks)
	lines.append("")
	lines.append("事件日志（最近 24 条）：")
	for i in range(maxi(0, _log.size() - 24), _log.size()):
		lines.append("  %s" % _log[i])
	_results_text.text = "\n".join(lines)
	_results.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _exit() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	exit_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
