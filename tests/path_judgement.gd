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


func _at(run: Playtest, ms: float, point: Vector2) -> void:
	var beat := run.chart.timing.chart_ms_to_beat(ms)
	run._preview.prepare_playtest_frame(beat, 0.0)
	run._judge_path(run.chart.notes[0], ms, beat, point)
	run._path_motion_samples.clear()


func _test_playtest() -> void:
	var chart := _chart()
	var note := chart.notes[0]
	var run := Playtest.new()
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
	run.queue_free()
	await process_frame
