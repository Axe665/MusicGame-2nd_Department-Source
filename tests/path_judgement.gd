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
	_test_tail_visual()
	_test_tail_entry()
	_test_scan_model()
	_test_forgiving_corridor()
	root.size = Vector2i(1600, 900)
	var app := root.get_node_or_null("App")
	if app != null:
		app.playtest_offset_ms = 0.0
	await _test_playtest()
	await _test_bell_judgement()
	await _test_real_motion()
	print("Path judgement: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _tracker(points: Array[Vector2]) -> PathProgress:
	var tracker := Tracker.new()
	tracker.configure(PackedVector2Array(points))
	return tracker


func _feed(tracker: PathProgress, point: Vector2, ms: float, start_ms := 0.0) -> void:
	tracker.feed(point, ms, tracker.points, 0.025, start_ms)


## Clearing the last judgement group must not erase the visual tail; the player
## still has to reach the tail ring.
func _test_tail_visual() -> void:
	var straight := _tracker([Vector2.ZERO, Vector2.RIGHT])
	straight.confirm_head()
	_feed(straight, Vector2(0.5, 0), 1000.0)
	_feed(straight, Vector2(0.8, 0), 1100.0)
	check(straight.body_ready(), "the last group clears before the tail")
	check(straight.fraction < 0.95, "clearing the last group keeps the tail visible")
	straight.mark_complete()
	check(straight.fraction > 0.99, "the tail is erased only after completion")


## 尾判参考是“星星进入尾区”：直线路径上应从末端往前一个尾区半径处进入。
func _test_tail_entry() -> void:
	var straight := _tracker([Vector2.ZERO, Vector2.RIGHT])
	var entry := straight.tail_entry_parameter(straight.points, 0.2)
	check(entry >= 0.75 and entry <= 0.85, "tail entry sits one tail radius before the end")
	check(straight.tail_entry_parameter(straight.points, 0.0) == 1.0, "zero tail radius falls back to the end")
	check(straight.tail_entry_parameter(PackedVector2Array(), 0.2) == 1.0, "missing projection falls back to the end")


func _test_tracker() -> void:
	var straight := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_feed(straight, Vector2.ZERO, 1000.0)
	_feed(straight, Vector2.RIGHT, 2000.0)
	check(straight.coverage > 0.99, "one fast movement crosses all straight checkpoints")
	check(straight.finish_contact(1700.0, 2250.0, 0.025) >= 1950.0 and straight.finish_contact(1700.0, 2250.0, 0.025) <= 2000.0,
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
	check(retrace.progress < 0.95 and not retrace.body_ready(), "one outward sweep cannot also clear an earlier return intersection")
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
	check(uneven.fraction > 0.8 and uneven.progress <= 0.51, "erasure maps arc progress back to authored beat parameters")
	check(uneven.gates.size() <= 6, "short routes use few ordered regions despite fine corridor geometry")
	var sparse_long := _tracker([Vector2.ZERO, Vector2(2, 0)])
	check(sparse_long.gates.size() <= 6, "a two-radius straight route has only a few mandatory regions")
	check(uneven.points[0] == Vector2.ZERO and uneven.points[-1] == Vector2.RIGHT,
		"sparser regions preserve both endpoints")
	check(absf(float(uneven.distances[uneven.required_index]) / uneven.length - 0.8) < 0.0001,
		"corridor retains an 80-percent coverage marker")
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
	_feed(missed, Vector2(0.3, 0), 80.0)
	missed.reset_motion()
	_feed(missed, Vector2(0.45, 0), 100.0)
	check(missed.progress >= 0.44, "a small missing section can rejoin without returning to an old point")
	var corner := _tracker([Vector2.ZERO, Vector2(0, 0.14), Vector2(1, 0.14)])
	_feed(corner, Vector2.ZERO, 0.0)
	corner.reset_motion()
	_feed(corner, Vector2(0.14, 0.14), 100.0)
	check(corner.progress < 0.5, "a rounded small corner cannot skip the remaining route")


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


func _wide_feed(tracker: PathProgress, point: Vector2, ms: float, start_ms := 0.0) -> void:
	tracker.feed(point, ms, tracker.points, tracker.contact_radius, start_ms)


func _test_scan_model() -> void:
	var long_path := _tracker([Vector2.ZERO, Vector2(4, 0)])
	check(long_path.tolerance == Tracker.SKIP_TOLERANCE, "long slides allow one skipped group")
	var short_path := _tracker([Vector2.ZERO, Vector2.RIGHT])
	check(short_path.tolerance == 0, "three-group slides protect every group")
	var u_turn := _tracker([Vector2.ZERO, Vector2(0, 1), Vector2.ONE, Vector2.RIGHT])
	_wide_feed(u_turn, Vector2.ZERO, 0.0)
	_wide_feed(u_turn, Vector2.RIGHT, 100.0)
	check(not u_turn.body_ready() and u_turn.remaining_groups() > 1,
		"one jump cannot consume a whole U turn")
	var straight := _tracker([Vector2.ZERO, Vector2(4, 0)])
	_wide_feed(straight, Vector2.ZERO, 0.0)
	_wide_feed(straight, Vector2(4, 0), 1000.0)
	check(straight.body_ready(), "a continuous sweep clears every group")
	check(straight.coverage > 0.99, "a continuous sweep keeps full corridor coverage")


func _test_forgiving_corridor() -> void:
	var wide := _tracker([Vector2.ZERO, Vector2(2, 0)])
	for i in 21:
		_wide_feed(wide, Vector2(float(i) / 10.0, 0.18), float(i * 50))
	check(wide.body_ready() and wide.coverage > 0.9, "a naturally offset stroke inside the wide corridor completes")
	var outside := _tracker([Vector2.ZERO, Vector2(2, 0)])
	for i in 21:
		_wide_feed(outside, Vector2(float(i) / 10.0, 0.5), float(i * 50))
	check(outside.coverage == 0.0, "unrelated parallel movement outside the corridor gets no credit")
	var rounded := _tracker([Vector2.ZERO, Vector2(0, 1), Vector2.ONE, Vector2.RIGHT])
	var stroke := [Vector2.ZERO, Vector2(0, 0.6), Vector2(0.15, 0.85), Vector2(0.85, 0.85), Vector2(1, 0.6), Vector2.RIGHT]
	for i in stroke.size():
		_wide_feed(rounded, stroke[i], float(i * 100))
	check(rounded.body_ready(), "rounded U turns pass without touching exact vertices")
	var shortcut := _tracker([Vector2.ZERO, Vector2(0, 1), Vector2.ONE, Vector2.RIGHT])
	_wide_feed(shortcut, Vector2.ZERO, 0.0)
	_wide_feed(shortcut, Vector2.RIGHT, 100.0)
	check(not shortcut.body_ready(), "wide corridor still rejects skipping the whole U")
	var rejoin := _tracker([Vector2.ZERO, Vector2(3, 0)])
	_wide_feed(rejoin, Vector2.ZERO, 0.0)
	_wide_feed(rejoin, Vector2(0.9, 0), 100.0)
	_wide_feed(rejoin, Vector2(0.9, 0.6), 140.0)
	_wide_feed(rejoin, Vector2(1.2, 0.6), 180.0)
	_wide_feed(rejoin, Vector2(1.2, 0.05), 220.0)
	_wide_feed(rejoin, Vector2(3, 0.05), 500.0)
	check(rejoin.body_ready(), "briefly leaving and rejoining ahead does not freeze progress")
	var repeat := _tracker([Vector2.ZERO, Vector2(3, 0)])
	_wide_feed(repeat, Vector2.ZERO, 0.0)
	_wide_feed(repeat, Vector2(0.5, 0), 100.0)
	var once := repeat.coverage
	for i in 20:
		_wide_feed(repeat, Vector2(0.1 if i % 2 == 0 else 0.5, 0), 200.0 + float(i * 10))
	check(absf(repeat.coverage - once) < 0.0001, "repeating the same part cannot inflate actual coverage")
	var early := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_wide_feed(early, Vector2.ZERO, 1000.0)
	_wide_feed(early, Vector2.RIGHT, 1800.0)
	check(not is_finite(early.finish_contact(1780, 2250, 0.18, 2000)), "early arrival waits instead of forcing a GOOD")
	_wide_feed(early, Vector2.RIGHT, 2000.0)
	var completed := early.finish_contact(1780, 2250, 0.18, 2000)
	check(completed >= 1920 and completed <= 2000, "remaining at the tail earns a real contact in the perfect window")
	var left := _tracker([Vector2.ZERO, Vector2.RIGHT])
	_wide_feed(left, Vector2.ZERO, 1000.0)
	_wide_feed(left, Vector2.RIGHT, 1800.0)
	left.finish_contact(1780, 2250, 0.18, 2000)
	_wide_feed(left, Vector2(1, 1), 1850.0)
	check(left.finish_contact(1780, 2250, 0.18, 2000) < 1920, "leaving early cannot fabricate a perfect tail")
	var tiny_turn := _tracker([Vector2.ZERO, Vector2(0.8, 0), Vector2(0.7, 0)])
	_wide_feed(tiny_turn, Vector2.ZERO, 0.0)
	_wide_feed(tiny_turn, Vector2(0.8, 0), 1000.0)
	check(tiny_turn.body_ready() and is_finite(tiny_turn.finish_contact(900, 1100, tiny_turn.contact_radius)),
		"entering a short final turn's end region does not require exact endpoint projection")
	# Approximate local coordinates reconstructed from the real #289 play log,
	# sampled every 200ms. This deliberately includes inward cutting and a wait.
	var recorded := _tracker([Vector2(1,0),Vector2(0.96,0.28),Vector2(0.85,0.53),Vector2(0.67,0.74),Vector2(0.43,0.9),Vector2(0.17,0.98),Vector2(-0.11,0.99),Vector2(-0.38,0.92),Vector2(-0.62,0.78),Vector2(-0.81,0.58),Vector2(-0.94,0.33),Vector2(-0.95,0.31),Vector2(-1,0.06),Vector2(-1,0)])
	recorded.confirm_head()
	var human := [Vector2(1.098,0.003),Vector2(1.097,0.195),Vector2(0.62,0.769),Vector2(-0.127,0.809),Vector2(-0.706,0.732),Vector2(-0.862,0.268)]
	var times := [0.0,201.1,409.2,629.6,835.7,1050.2]
	for i in human.size():
		_wide_feed(recorded, human[i], times[i], 240.0)
	check(recorded.progress > 0.85 and recorded.body_ready(), "recorded inward-cutting arc can progress past the old 36-percent stall")


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
	run._assign_presses(ms, beat)
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
	check(not run._preview.show_path_judgement, "judgement regions are hidden by default")
	var display := InputEventKey.new()
	display.keycode = KEY_F10
	display.pressed = true
	run._input(display)
	check(run._preview.show_path_judgement and run._path_judgement_toggle.button_pressed, "F10 enables regions and synchronizes the pause switch")
	var debug := run._preview.path_judgement_debug(note, 2.0)
	var live: PathProgress = run._states[1]["path_tracker"]
	check(debug["points"] == run._preview.path_judgement_points(live.points, 2.0), "visible regions use the exact live judgement coordinates")
	check(absf(float(debug["radius"]) - live.contact_radius * run._preview.path_judgement_scale()) < 0.001, "visible radii match actual contact tolerance")
	check(debug["mandatory"] == live.mandatory and int(debug["required"]) == live.required_index, "overlay marks the live mandatory and completion checkpoints")
	check(int(debug["group_count"]) == live.group_count and int(debug["tolerance"]) == live.tolerance,
		"overlay reads the live group count and skip tolerance")
	run._path_judgement_toggle.button_pressed = false
	check(not run._preview.show_path_judgement, "pause switch can disable judgement regions")
	run._set_paused(true)
	run._input(display)
	check(run._preview.show_path_judgement, "F10 remains usable while paused")
	run._set_paused(false)
	run._set_path_judgement_visible(false)
	var head := run._preview.path_point(note, 0.0, 2.0)
	var tail := run._preview.path_point(note, 4.0, 2.0)
	_at(run, 1000.0, head)
	_at(run, 2800.0, head)
	var tracker: PathProgress = run._states[1]["path_tracker"]
	check(tracker.coverage < 0.2, "playtest waiting at the head leaves the body unconfirmed")
	check(not run._preview.path_erased(note, 2.0), "music time alone does not erase the middle")
	_at(run, 3000.0, tail)
	check(not bool(run._states[1]["tail_hit"]), "playtest rejects jumping directly to the tail")
	_at(run, 3351.0, tail)
	check(bool(run._states[1]["tail_judged"]) and run._miss_count == 1, "incomplete path misses after its deadline")

	_reset(run, chart)
	_at(run, 1000.0, head)
	tracker = run._states[1]["path_tracker"]
	for group in range(tracker.group_count - 1):
		tracker.cleared[group] = 1
	tracker.next_gate = tracker.group_count - 1
	_at(run, 3351.0, head)
	check(int(run._tier_counts["GOOD"]) == 1 and run._miss_count == 0,
		"missing only the last group earns GOOD instead of a miss")

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
	for ms in [1000.0, 2000.0]:
		for path in chart.notes:
			run._judge_path(path, ms, chart.timing.chart_ms_to_beat(ms), Vector2.INF)
	check(not bool(run._states[1]["tail_hit"]) and not bool(run._states[2]["tail_hit"]), "AUTO does not finish before the tail zone")
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


## 金键：窗口内光标在场只预备，到判定线才结算；越界才是 MISS，且不进 BIA。
func _test_bell_judgement() -> void:
	var chart := DemoChart.make_empty({"title": "bell judgement", "bpm": 120.0})
	chart.notes.clear()
	var band := Note.new("bell", 2.0, 90.0, 45.0)
	band.id = 1
	band.center_u = 0.25
	band.bell_radius = 1.0
	band.radius = 50.0
	var dot := Note.new("bell", 4.0, 0.0, 45.0)
	dot.id = 2
	dot.center_u = 0.0
	dot.bell_radius = 0.0
	dot.radius = 50.0
	chart.notes = [band, dot]
	var run := Playtest.new()
	run.path_input_logging = false
	root.add_child(run)
	await process_frame
	run.setup(chart, 0.0, "")
	run.set_process(false)
	var beat := 2.0
	run._preview.prepare_playtest_frame(beat, 0.0)
	var target := chart.timing.beat_to_chart_ms(beat)
	var screen: Dictionary = run._preview.bell_screen(band, beat)
	check(not screen.is_empty(), "a gold band has a screen shape")
	var point: Vector2 = screen["center"]
	var center: Vector2 = run._preview.project_design(Vector2.ZERO)
	var inward: Vector2 = (center - point).normalized()
	check(run._preview.bell_contains(band, beat, point + inward * 39.0), "39px off the band still counts")
	check(not run._preview.bell_contains(band, beat, point + inward * 41.0), "41px off the band is outside")
	check(run._preview.bell_contains(dot, 4.0, center + Vector2(47.0, 0.0)), "the center dot keeps a 48px radius")
	check(not run._preview.bell_contains(dot, 4.0, center + Vector2(49.0, 0.0)), "the center dot stops at 48px")
	run._judge_bell(band, target - 199.0, beat, point)
	check(bool(run._states[1]["armed"]) and not bool(run._states[1]["done"]),
		"an early sweep only arms the gold note")
	run._judge_bell(band, target, beat, point)
	check(bool(run._states[1]["done"]), "the gold note resolves on the judgement line")
	check(int(run._tier_counts["PERFECT"]) == 1, "presence scores a PERFECT")
	check(run._combo == 1, "a gold note adds combo")
	check(run._errors.is_empty(), "a gold note never feeds BIA")
	run.queue_free()
	await process_frame

	var miss := Playtest.new()
	miss.path_input_logging = false
	root.add_child(miss)
	await process_frame
	miss.setup(chart, 0.0, "")
	miss.set_process(false)
	miss._preview.prepare_playtest_frame(beat, 0.0)
	var far := point + (point - center) * 2.0
	miss._judge_bell(band, target - 201.0, beat, far)
	miss._judge_bell(band, target + 199.0, beat, far)
	check(not bool(miss._states[1]["done"]), "the late window is still open")
	miss._judge_bell(band, target + 201.0, beat, far)
	check(bool(miss._states[1]["done"]) and miss._miss_count == 1, "an absent gold note misses after the window")
	check(int(miss._tier_counts["MISS"]) == 1, "a missed gold note is judged")
	check(miss._combo == 0, "a missed gold note breaks combo")
	miss.queue_free()
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
		run._clock.start(visual_ms, Time.get_ticks_usec())
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
		run._assign_presses(now - 49.0, now / 500.0)
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
