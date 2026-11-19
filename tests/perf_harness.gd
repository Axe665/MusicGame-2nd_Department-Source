extends Control

## 性能基线：一条命令打出编辑器 / 环编辑器 / 游玩的帧时间与结构指标。
##
## 参数必须放在独立的 `--` 之后（Godot 会吃掉之前的参数）：
##   godot --headless --path . res://tests/perf_harness.tscn -- \
##       --scenario=all --notes=10000 --keys=200 --frames=120 --warmup=30
##
## 可选：
##   --chart=res://charts/demo.json   用真实谱面代替合成压力谱（编辑器场景）
##   --baseline=res://tests/perf_baseline.json   回退判定，超容差退出码 1
##   --budget-ms=16.7                 交互场景 frame_p95 的绝对预算
##
## 输出稳定、可 grep：`PERF <scenario>.<metric>=<number>`，末尾 `PERF_TOTAL ok=`。
## headless 下没有光栅化，测的是「我们要改的那部分 CPU」；draw call 计数需要
## 有渲染器（xvfb / 真机），此时额外打印 draw_calls_2d。

const PerfChart = preload("res://tests/perf_chart.gd")


## 在 _draw 里把 5 个 storyboard 图层各画一遍并计时（draw_* 只能在 _draw 内调）。
class StoryboardProbe:
	extends Control
	var preview: Preview3D
	var total_us := 0
	var draws := 0

	func _draw() -> void:
		var started := Time.get_ticks_usec()
		preview.draw_storyboard_background(self)
		preview.draw_storyboard_additive_background(self)
		preview.draw_storyboard_front(self)
		preview.draw_storyboard_overlay(self)
		preview.draw_storyboard_additive_front(self)
		total_us += Time.get_ticks_usec() - started
		draws += 1

var _notes := 10000
var _keys := 200
var _sample_frames := 120
var _warmup := 30
var _chart_path := ""
var _baseline_path := ""
var _budget_ms := 0.0
var _main: Control = null
var _failures: Array[String] = []
var _metrics: Dictionary = {}
## headless 主循环本身有个固定地板（与场景无关），扣掉它才是我们代码的开销。
var _floor_ms := 0.0
## 本机算力标定：同一份固定工作量的耗时，用来把基线和当前机器对齐。
var _calibration_ms := 0.0


func _ready() -> void:
	_parse_args()
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _measure_floor()
	_measure_calibration()
	_print_meta()
	for scenario in _scenario_list():
		await _run(scenario)
	if not _baseline_path.is_empty():
		_compare_baseline()
	var failed := _failures.size()
	for failure in _failures:
		print("PERF_FAIL %s" % failure)
	print("PERF_TOTAL ok=%d scenarios=%d failed=%d" % [1 if failed == 0 else 0, _scenario_list().size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if not text.begins_with("--"):
			continue
		var pair := text.substr(2).split("=", true, 1)
		var key := pair[0]
		var value := pair[1] if pair.size() > 1 else ""
		match key:
			"notes":
				_notes = int(value)
			"keys":
				_keys = int(value)
			"frames":
				_sample_frames = int(value)
			"warmup":
				_warmup = int(value)
			"chart":
				_chart_path = value
			"baseline":
				_baseline_path = value
			"budget-ms":
				_budget_ms = float(value)


func _scenario_list() -> Array[String]:
	var requested := "all"
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--scenario="):
			requested = text.split("=", true, 1)[1]
	if requested == "all":
		return ["editor_idle", "ring_idle", "ring_scrub", "playtest"]
	var result: Array[String] = []
	for name in requested.split(",", false):
		result.append(name)
	return result


func _print_meta() -> void:
	print("PERF_META godot=%s renderer=%s display=%s max_fps=%d floor_ms=%.2f calibration_ms=%.2f chart=%s notes=%d keys=%d" % [
		Engine.get_version_info()["string"], RenderingServer.get_video_adapter_name(),
		DisplayServer.get_name(), Engine.max_fps, _floor_ms, _calibration_ms,
		_chart_path if not _chart_path.is_empty() else "synthetic",
		_notes, _keys])


## 固定工作量的耗时（2000 音符谱面序列化）：用来校正不同机器的算力差异，
## 否则在慢 runner 上基线永远超，门禁就成了摆设。
func _measure_calibration() -> void:
	var probe := PerfChart.make(2000, 20)
	var samples: Array[float] = []
	for i in 3:
		var started := Time.get_ticks_usec()
		var size := JSON.stringify(ChartIO.chart_to_dict(probe)).length()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0 + float(size) * 0.0)
	samples.sort()
	_calibration_ms = samples[1]


## 空场景的帧间隔 = 引擎/平台地板，各场景扣掉它。
func _measure_floor() -> void:
	Engine.max_fps = 0
	var probe := Control.new()
	add_child(probe)
	await _frames(6)
	var times: Array[float] = []
	var prev := Time.get_ticks_usec()
	for i in 20:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - prev) / 1000.0)
		prev = now
	times.sort()
	_floor_ms = times[times.size() / 2]
	probe.queue_free()
	await _frames(2)


func _run(scenario: String) -> void:
	match scenario:
		"editor_idle":
			await _with_editor(func() -> String: return "editor_idle")
		"ring_idle":
			await _with_ring(false)
		"ring_scrub":
			await _with_ring(true)
		"playtest":
			await _with_playtest()
		_:
			print("PERF_SKIP unknown scenario %s" % scenario)


func _chart() -> Chart:
	if not _chart_path.is_empty() and FileAccess.file_exists(_chart_path):
		var loaded := ChartIO.load_chart(_chart_path)
		if loaded != null:
			return loaded
	return PerfChart.make(_notes, _keys)


## 编辑器整树：建一次，跑 idle 与（可选的）拖动。
func _with_editor(scrub: Callable) -> void:
	var app := get_node_or_null("/root/App")
	var chart := _chart()
	app.chart = chart
	app.chart_path = ""
	_main = load("res://charter/main.tscn").instantiate()
	add_child(_main)
	await _frames(_warmup)
	await _sample(String(scrub.call()))
	if _main != null:
		_main.queue_free()
		_main = null
	await _frames(4)


func _with_ring(scrub: bool) -> void:
	var app := get_node_or_null("/root/App")
	var chart := _chart()
	app.chart = chart
	app.chart_path = ""
	_main = load("res://charter/main.tscn").instantiate()
	add_child(_main)
	await _frames(_warmup)
	_main._open_ring_workspace()
	var workspace: RingWorkspace = _main._ring_workspace
	workspace.seek(float(chart.shape_keys[0].get("beat", 0.0)) if not chart.shape_keys.is_empty() else 0.0)
	await _frames(_warmup)
	if scrub:
		workspace._timeline._drag_kind = "playhead"
		var key_count := chart.shape_keys.size()
		var steps := float(_sample_frames)
		var beats_per_step := 0.25
		await _sample("ring_scrub", func(index: int) -> void:
			var beat := float(index) * beats_per_step
			if key_count > 1:
				beat = fposmod(beat, float(key_count) * 4.0 - 0.5)
			workspace.seek(beat))
		workspace._timeline._drag_kind = ""
		workspace.finish_scrub()
	else:
		await _sample("ring_idle")
	_main.queue_free()
	_main = null
	await _frames(4)


func _with_playtest() -> void:
	var chart := _chart()
	var sb_dir := ""
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--storyboard="):
			sb_dir = text.split("=", true, 1)[1]
	if not sb_dir.is_empty():
		chart.metadata["storyboard"] = sb_dir
	var preview: Preview3D = load("res://tests/bench_preview.gd").new()
	add_child(preview)
	preview.position = Vector2.ZERO
	preview.size = Vector2(1280, 720)
	preview.chart_override = chart
	preview.follow_app = false
	preview.playtest_mode = true
	preview.show_hud = true
	preview.show_notes = true
	preview.show_storyboard = not sb_dir.is_empty()
	preview.show_storyboard_background = true
	# 落在密集段：0 拍附近只有一两颗音符，测不出每帧成本。
	preview.time_beat = 400.0
	await _frames(_warmup)
	var beat := 400.0
	var probe: StoryboardProbe = null
	if not sb_dir.is_empty():
		probe = StoryboardProbe.new()
		probe.preview = preview
		probe.size = Vector2(1280, 720)
		add_child(probe)
	await _sample("playtest", func(_index: int) -> void:
		beat += 1.0 / 60.0
		preview.time_beat = beat
		if probe != null:
			probe.queue_redraw())
	if probe != null:
		print("PERF playtest.storyboard_textures=%d" % preview._tex_cache.size())
		var sb_ms := float(probe.total_us) / float(maxi(1, probe.draws)) / 1000.0
		_metrics["playtest.storyboard_ms"] = sb_ms
		print("PERF playtest.storyboard_ms=%.2f" % sb_ms)
		print("PERF playtest.storyboard_draws=%d" % probe.draws)
		probe.queue_free()
	# 覆盖层每帧重建的纯 CPU 成本（和帧间隔分开：帧间隔有引擎地板）。
	var draws := maxi(1, int(preview.draw_count))
	var overlay_ms := float(preview.total_us) / float(draws) / 1000.0
	_metrics["playtest.overlay_ms"] = overlay_ms
	_metrics["playtest.overlay_draws"] = float(preview.draw_count)
	print("PERF playtest.overlay_ms=%.2f" % overlay_ms)
	print("PERF playtest.overlay_draws=%d" % int(preview.draw_count))
	print("PERF playtest.sections %s" % preview.summary())
	preview.queue_free()
	await _frames(4)


## 采样：每帧先执行 step（可选），再记一次帧间隔与结构计数。
func _sample(tag: String, step: Callable = Callable()) -> void:
	# main.tscn/_apply_visual_options 会按用户设置重设帧率上限与垂直同步，采样前再钉一次。
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var times: Array[float] = []
	var prev := Time.get_ticks_usec()
	for i in _sample_frames:
		if step.is_valid():
			step.call(i)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - prev) / 1000.0)
		prev = now
	times.sort()
	var p50: float = times[times.size() / 2]
	var p95: float = times[mini(times.size() - 1, int(float(times.size()) * 0.95))]
	var worst: float = times[times.size() - 1]
	var rows := {
		"frames": float(_sample_frames),
		"frame_p50_ms": p50,
		"frame_p95_ms": p95,
		"frame_max_ms": worst,
		"work_p50_ms": maxf(0.0, p50 - _floor_ms),
		"work_p95_ms": maxf(0.0, p95 - _floor_ms),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"draw_calls_2d": float(_canvas_draw_calls()),
	}
	for key in rows:
		_metrics["%s.%s" % [tag, key]] = rows[key]
		print("PERF %s.%s=%s" % [tag, key, _fmt(rows[key])])
	if _budget_ms > 0.0 and p95 > _budget_ms:
		_failures.append("%s.frame_p95_ms=%.2f > budget %.2f" % [tag, p95, _budget_ms])


func _canvas_draw_calls() -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	return get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,
		Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)


func _compare_baseline() -> void:
	if not FileAccess.file_exists(_baseline_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_baseline_path))
	if parsed is not Dictionary:
		return
	var baseline: Dictionary = parsed
	# 基线是在某台机上量的；按算力标定把容差一起缩放，慢机器不会假红。
	var scale := 1.0
	var base_calibration := float(baseline.get("calibration_ms", 0.0))
	if base_calibration > 0.0 and _calibration_ms > 0.0:
		scale = clampf(_calibration_ms / base_calibration, 0.5, 10.0)
	var rows: Dictionary = baseline.get("metrics", {})
	var overrides: Dictionary = baseline.get("tolerances", {})
	for key in rows:
		if not _metrics.has(key):
			continue
		var base := float(rows[key])
		if base <= 0.0:
			continue
		# 单指标可覆盖容差：UI 帧时间在 CI 上的抖动远大于 JSON 序列化标定。
		var tolerance := float(overrides.get(key, baseline.get("tolerance", 1.5)))
		var limit := base * tolerance * scale
		if float(_metrics[key]) > limit:
			_failures.append("%s=%.2f > baseline %.2f × %.2f" % [key, float(_metrics[key]), base, tolerance])


func _fmt(value: float) -> String:
	return "%.2f" % value


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
