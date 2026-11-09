extends SceneTree

const Tracker = preload("res://core/path_progress.gd")
var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)


func _run() -> void:
	_test_tracker()
	root.size = Vector2i(1600, 900)
	var app := root.get_node_or_null("App")
	if app != null:
		app.playtest_offset_ms = 0.0
	await _test_playtest()
	await _test_real_motion()
	print("Path judgement: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _tracker(points: Array[Vector2]) -> PathProgress:
	var tracker := Tracker.new()
	tracker.configure(PackedVector2Array(points))
	return tracker


func _feed(tracker: PathProgress, point: Vector2, ms: float, start_ms := 0.0) -> void:
	tracker.feed(point, ms, tracker.points, 0.025, start_ms)


func _test_tracker() -> void:
	var straight := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(straight, Vector2.ZERO, 1000.0)
	_feed(straight, Vector2.RIGHT, 2000.0)
	check(straight.coverage > 0.99, "one fast movement crosses all straight checkpoints")
	check(absf(straight.finish_contact(1700.0, 2250.0, 0.025) - 1875.0) < 0.1,
		"finish uses interpolated contact time, rather than rendered frame time")
	check(not is_finite(straight.finish_contact(2100.0, 2250.0, 0.025)), "leaving before the window cannot cause a later hit")
	_feed(straight, Vector2.RIGHT, 2200.0)
	check(is_finite(straight.finish_contact(2100.0, 2250.0, 0.025)), "remaining at the end supplies fresh contact")

	var bend := _tracker([Vector2.ZERO, Vector2(0, 1), Vector2.ONE, Vector2.RIGHT])
	_feed(bend, Vector2.ZERO, 1000.0)
	_feed(bend, Vector2.RIGHT, 2000.0)
	check(bend.coverage < 0.2, "direct head-to-tail shortcut cannot clear a U bend")
	check(not is_finite(bend.finish_contact(1700.0, 2250.0, 0.025)), "tail contact needs ordered body coverage")
	_feed(bend, Vector2.ZERO, 2100.0)
	_feed(bend, Vector2(0, 1), 2200.0)
	_feed(bend, Vector2.ONE, 2300.0)
	_feed(bend, Vector2.RIGHT, 2400.0)
	check(bend.coverage > 0.99, "returning to the missed region allows recovery")

	var retrace := _tracker([Vector2.ZERO, Vector2.RIGHT, Vector2(0.2, 0)])
	_feed(retrace, Vector2.ZERO, 0.0)
	_feed(retrace, Vector2(2, 0), 100.0)
	check(retrace.coverage < 0.8, "one outward sweep cannot also clear an earlier return intersection")
	_feed(retrace, Vector2(0.2, 0), 200.0)
	check(retrace.coverage > 0.99, "actual return movement clears a retraced path")

	var loop := _tracker([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.UP, Vector2.ZERO])
	for i in 20:
		_feed(loop, Vector2.ZERO, float(i * 100))
	check(loop.coverage < 0.1, "waiting at a closed loop's shared head and tail cannot finish it")
	for point in [Vector2.RIGHT, Vector2.ONE, Vector2.UP, Vector2.ZERO]:
		_feed(loop, point, loop.previous_ms + 100.0)
	check(loop.coverage > 0.99, "closed loop can be completed in order")

	var discontinuity := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(discontinuity, Vector2.ZERO, 0.0)
	discontinuity.reset_motion()
	_feed(discontinuity, Vector2.RIGHT, 1000.0)
	check(discontinuity.coverage < 0.2, "pause discontinuity does not invent a swept segment")
	check(discontinuity.previous == Vector2.RIGHT, "first movement after reset becomes a new origin")

	var waiting := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(waiting, Vector2.ZERO, 0.0, 900.0)
	_feed(waiting, Vector2.RIGHT, 1000.0, 900.0)
	check(waiting.next_index == 0, "pre-start movement is clipped rather than credited to the path")

	var off_track := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(off_track, Vector2(0, 0.2), 0.0)
	_feed(off_track, Vector2(1, 0.2), 1000.0)
	check(off_track.coverage == 0.0, "parallel movement outside the corridor gets no progress")

	var uneven := Tracker.new()
	uneven.configure(PackedVector2Array([Vector2.ZERO, Vector2(0.01, 0), Vector2.RIGHT]), PackedFloat32Array([0.0, 0.8, 1.0]))
	_feed(uneven, Vector2.ZERO, 0.0)
	_feed(uneven, Vector2(0.5, 0), 100.0)
	check(uneven.fraction > 0.8 and uneven.coverage < 0.6, "erasure maps arc coverage back to authored beat parameters")
	check(uneven.points.size() >= 8, "checkpoints are spaced geometrically even with uneven authored times")
	var invalid := _tracker([Vector2.ZERO, Vector2.INF, Vector2.RIGHT])
	check(invalid.points.is_empty(), "invalid geometry cannot be joined across a gap")
	var zero := _tracker([Vector2.ZERO, Vector2.ZERO])
	check(zero.points.is_empty(), "zero-length paths cannot auto-complete")
	var short_path := _tracker([Vector2.ZERO, Vector2(0.1, 0)])
	short_path.feed(Vector2.ZERO, 0.0, short_path.points, short_path.contact_radius, 0.0)
	check(short_path.coverage < 0.2, "short-path tolerance cannot swallow most of its body")
	short_path.feed(Vector2(0.1, 0), 100.0, short_path.points, short_path.contact_radius, 0.0)
	check(short_path.coverage > 0.99, "short paths still accept a fast ordered movement")
	check(Tracker.circle_interval(Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO, 1.0).x == 0.5, "tangent contact is accepted")
	var missed := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(missed, Vector2.ZERO, 0.0)
	missed.reset_motion()
	_feed(missed, Vector2(0.25, 0), 100.0)
	check(missed.coverage >= 0.24, "one missed ordinary checkpoint can recover at its immediate neighbour")
	var corner := _tracker([Vector2.ZERO, Vector2(0, 0.14), Vector2(1, 0.14)])
	_feed(corner, Vector2.ZERO, 0.0)
	corner.reset_motion()
	_feed(corner, Vector2(0.14, 0.14), 100.0)
	check(corner.coverage < 0.1, "lookahead cannot skip a direction-changing corner")


func _chart() -> Chart:
	var chart := DemoChart.make_empty({"title": "path judgement regression", "bpm": 120.0})
	chart.notes.clear()
	var note := Note.new("path", 2.0, 0.0, 60.0)
	note.id = 1
	note.end_beat = 6.0
	note.trace_pts = [
		{"db": 0.0, "x": 1.0, "y": 0.0},
		{"db": 2.0, "x": 0.0, "y": 0.8},
		{"db": 4.0, "x": -0.7, "y": 0.0},
	]
	note.tail_angle = 180.0
	chart.notes.append(note)
	return chart


func _reset(run: Playtest, chart: Chart) -> void:
	run.auto_play = false
	run.setup(chart, 0.0, "")
	run.set_process(false)
	run._preview.mouse_tilt = false
	run._preview.prepare_playtest_frame(2.0, 0.0)
	for state in run._states.values():
		state["head_judged"] = true
		state["head_hit"] = true


func _at(run: Playtest, ms: float, point: Vector2, visual_ms := -INF) -> void:
	var beat := run.chart.timing.chart_ms_to_beat(visual_ms if is_finite(visual_ms) else ms)
	run._preview.prepare_playtest_frame(beat, 0.0)
	run._judge_path(run.chart.notes[0], ms, beat, point)
	run._path_motion_samples.clear()


func _test_playtest() -> void:
	var chart := _chart()
	var note := chart.notes[0]
	var run := Playtest.new()
	run.path_input_logging = false
	root.add_child(run)
	await process_frame
	_reset(run, chart)
	var head := run._preview.path_point(note, 0.0, 2.0)
	var tail := run._preview.path_point(note, 4.0, 2.0)
	_at(run, 1000.0, head)
	_at(run, 2800.0, head)
	var tracker: PathProgress = run._states[1]["path_tracker"]
	check(tracker.coverage < 0.2, "playtest waiting at the head leaves the body unconfirmed")
	check(not run._preview.path_erased(note, 2.0), "music time alone does not erase the middle")
	_at(run, 3000.0, tail)
	check(not bool(run._states[1]["tail_hit"]), "playtest rejects jumping directly to the tail")
	_at(run, 3251.0, tail)
	check(bool(run._states[1]["tail_judged"]) and run._miss_count == 1, "incomplete path misses after its deadline")

	_reset(run, chart)
	head = run._preview.path_point(note, 0.0, 2.0)
	tail = run._preview.path_point(note, 4.0, 2.0)
	_at(run, 1000.0, head)
	var bend := run._preview.path_point(note, 2.0, 6.0)
	run._queue_path_motion(head, 2900.0)
	run._queue_path_motion(bend, 2950.0)
	run._queue_path_motion(tail, 3000.0)
	_at(run, 3300.0, tail + Vector2(400, 300))
	check(bool(run._states[1]["tail_hit"]), "input batch preserves a full fast slide between frames")
	check(int(run._tier_counts["PERFECT"]) == 1, "fast slide scores its actual contact time")
	check(float(run._states[1]["path_finish_ms"]) <= 3000.0, "a delayed frame still accepts contact recorded before the deadline")
	check(run._preview.path_erased(note, 2.0), "confirmed movement erases the actual middle")
	var hits := run._hit_count
	_at(run, 3120.0, tail)
	check(run._hit_count == hits, "tail is scored exactly once")

	_reset(run, chart)
	_at(run, 1000.0, head)
	run._queue_path_motion(bend, 2000.0)
	run._set_paused(true)
	check(run._path_motion_samples.is_empty(), "pause clears pending path input")
	tracker = run._states[1]["path_tracker"]
	check(not tracker.previous.is_finite(), "pause disconnects the previous position")
	var event := InputEventMouseMotion.new()
	event.position = Vector2(500, 500)
	run._input(event)
	check(run._path_motion_samples.is_empty(), "paused mouse movements are ignored")
	run._set_paused(false)
	_at(run, 3000.0, tail)
	check(not bool(run._states[1]["tail_hit"]), "resume cannot sweep from the pre-pause head to the tail")

	_reset(run, chart)
	var wanted := Vector2(220, 330)
	event.position = run._preview.get_global_transform_with_canvas() * wanted
	run._input(event)
	check(run._path_motion_samples.size() == 1, "actual mouse input is collected")
	check((run._path_motion_samples[0]["point"] as Vector2).distance_to(wanted) < 0.01, "mouse event uses preview-local coordinates")
	for i in Playtest.PATH_INPUT_CAPACITY + 1:
		run._queue_path_motion(Vector2(i, 0), 1000.0 + i)
	check(run._path_motion_samples.size() <= Playtest.PATH_INPUT_CAPACITY, "input memory is bounded during a stalled frame")
	check(bool(run._path_motion_samples[0].get("break", false)), "overflow cuts the movement across discarded samples")

	var second := Note.from_dict(note.to_dict())
	second.id = 2
	chart.notes.append(second)
	_reset(run, chart)
	run.auto_play = true
	for ms in [1000.0, 2000.0, 2800.0]:
		for path in chart.notes:
			run._judge_path(path, ms, chart.timing.chart_ms_to_beat(ms), Vector2.INF)
	check(not bool(run._states[1]["tail_hit"]) and not bool(run._states[2]["tail_hit"]), "AUTO does not finish simultaneous paths early")
	for path in chart.notes:
		run._judge_path(path, 2960.0, 5.92, Vector2.INF)
	check(bool(run._states[1]["tail_hit"]) and bool(run._states[2]["tail_hit"]), "AUTO completes simultaneous paths through ordered checks")
	check(int(run._tier_counts["PERFECT"]) == 2, "AUTO keeps both tails inside the perfect window")

	_reset(run, chart)
	run._queue_path_motion(head, 1000.0)
	run._queue_path_motion(bend, 2950.0)
	run._queue_path_motion(tail, 3000.0)
	for path in chart.notes:
		run._judge_path(path, 3000.0, 6.0, tail)
	check(bool(run._states[1]["tail_hit"]) and bool(run._states[2]["tail_hit"]), "one real movement can confirm two genuinely overlapping paths")
	check(run._preview.path_sector_cuts.is_empty(), "guide balls no longer erase unrelated path sectors")
	second.trace_pts[1]["y"] = -0.8
	_reset(run, chart)
	run._queue_path_motion(head, 1000.0)
	run._queue_path_motion(bend, 2950.0)
	run._queue_path_motion(tail, 3000.0)
	for path in chart.notes:
		run._judge_path(path, 3000.0, 6.0, tail)
	check(bool(run._states[1]["tail_hit"]) and not bool(run._states[2]["tail_hit"]), "sharing endpoints does not clear a different middle route")
	_reset(run, chart)
	tracker = run._states[1]["path_tracker"]
	check(tracker.coverage == 0.0 and run._preview.path_cuts.is_empty(), "restart resets judgement and visual progress")
	check(not run._preview.is_processing(), "preview geometry is advanced by the playtest once per frame")
	var short_chart := _chart()
	var short_note := short_chart.notes[0]
	short_note.end_beat = 2.4
	short_note.generate_path_shape()
	_reset(run, short_chart)
	var app := root.get_node_or_null("App")
	if app != null:
		app.playtest_offset_ms = -49.0
	for i in 21:
		var visual_ms := 1000.0 + float(i) * 10.0
		var beat := visual_ms / 500.0
		var point := run._preview.path_point(short_note, beat - short_note.beat, beat)
		_at(run, visual_ms - 49.0, point, visual_ms)
	check(bool(run._states[1]["tail_hit"]), "negative scoring offset cannot delay spatial tracking past a short path's head")
	if app != null:
		app.playtest_offset_ms = 0.0
	_reset(run, short_chart)
	run._states[1]["head_judged"] = false
	run._states[1]["head_hit"] = false
	var off_center_head := run._preview.path_point(short_note, short_note.duration() * 0.12, short_note.beat)
	run._key_presses.append(Playtest.auto_press_payload(1000.0, off_center_head, short_note.angle, KEY_A))
	_at(run, 1000.0, off_center_head)
	check(bool(run._states[1]["head_hit"]), "head accepts its normal hit-area tolerance")
	tracker = run._states[1]["path_tracker"]
	check(tracker.next_index > 1, "accepted off-centre head does not leave the body blocked at checkpoint zero")
	run.path_input_logging = true
	_reset(run, short_chart)
	var log_path := run._path_input_log_path
	_at(run, 1000.0, run._preview.path_point(short_note, 0.0, 2.0))
	run._close_path_input_log()
	var lines := FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
	var kinds: Array[String] = []
	var frame: Dictionary = {}
	for line in lines:
		var record: Dictionary = JSON.parse_string(line)
		kinds.append(String(record.get("kind", "")))
		if record.get("kind") == "frame":
			frame = record
	check(kinds.has("session") and kinds.has("geometry") and kinds.has("frame") and kinds.has("session_end"), "play log preserves metadata, geometry, contact and a closed session")
	check(frame.has("target") and frame.has("cursor") and frame.has("radius") and frame.has("coverage"), "play log contains evidence needed to distinguish coordinate and checkpoint failures")
	check(run._path_input_log == null, "closing capture releases its file handle")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F9
	toggle.pressed = true
	run._input(toggle)
	check(not run.path_input_logging, "F9 disables diagnostic capture")
	run._input(toggle)
	check(run.path_input_logging and run._path_input_log != null, "F9 can restart diagnostic capture during play")
	run.queue_free()
	await process_frame


## Real Input.parse_input_event delivery, including viewport stretch and GUI
## input, instead of calling _input or assigning the cached cursor directly.
func _test_real_motion() -> void:
	var app := root.get_node("App")
	app.playtest_offset_ms = -49.0
	var chart := _chart()
	var note := chart.notes[0]
	var run := Playtest.new()
	run.path_input_logging = false
	run.bench_mode = true
	root.add_child(run)
	await process_frame
	run.setup(chart, 0.0, "")
	run.set_process(false)
	run._preview.mouse_tilt = false
	var received := 0
	var max_error := 0.0
	for i in 25:
		var visual_ms := 1000.0 + 2000.0 * float(i) / 24.0
		var beat := visual_ms / 500.0
		run._preview.prepare_playtest_frame(beat, 0.0)
		var wanted := run._preview.path_point(note, beat - note.beat, beat)
		var motion := InputEventMouseMotion.new()
		motion.position = run._preview.get_screen_transform() * wanted
		motion.global_position = motion.position
		run._last_chart_ms = -INF
		run._clock_update_usec = 0
		run._start_usec = Time.get_ticks_usec() - int(visual_ms * 1000.0)
		Input.parse_input_event(motion)
		await process_frame
		if i == 0:
			var press := InputEventKey.new()
			press.keycode = KEY_A
			press.physical_keycode = KEY_A
			press.pressed = true
			Input.parse_input_event(press)
		var now := run._chart_ms()
		for sample in run._path_motion_samples:
			received += 1
			max_error = maxf(max_error, (sample["point"] as Vector2).distance_to(wanted))
		run._judge_path(note, now - 49.0, now / 500.0, run._preview.get_local_mouse_position())
		run._path_motion_samples.clear()
	check(received >= 25, "real mouse events reach the Path input buffer")
	check(max_error < 0.05, "real viewport input matches displayed path coordinates")
	check(bool(run._states[1]["head_hit"]), "real key input hits the Path head")
	check(bool(run._states[1]["tail_hit"]), "real mouse input completes the body with negative scoring offset")
	var release := InputEventKey.new()
	release.keycode = KEY_A
	release.physical_keycode = KEY_A
	release.pressed = false
	Input.parse_input_event(release)
	run.queue_free()
	await process_frame
	app.playtest_offset_ms = 0.0
