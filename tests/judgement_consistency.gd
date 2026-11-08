extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)


func _run() -> void:
	var playtest := Playtest.new()
	root.add_child(playtest)
	var chart := DemoChart.make_empty({"bpm": 120.0})
	chart.notes.clear()
	for i in 2:
		var note := Note.new("tap", 4.0 + float(i) * 0.25, 90.0, 60.0)
		note.id = i + 1
		chart.notes.append(note)
	playtest.setup(chart, 0.0, "")
	playtest.set_process(false)
	check(not playtest._preview.is_processing(), "preview has no independent gameplay process")
	playtest._preview.prepare_playtest_frame(4.0, 0.016)
	check(playtest._preview.time_beat == 4.0, "preview geometry advances before judging")
	var note: Note = chart.notes[0]
	var band := playtest._preview.note_live_band(note, 4.0)
	var point := band[band.size() / 2]
	var center := playtest._preview.project_design(Vector2.ZERO)
	var far := center + (point - center).normalized() * 4000.0
	# A matching angle is insufficient, even for this dense pair.
	playtest._key_presses = [{"time": 2000.0, "mouse": far, "angle": 90.0}]
	var miss := playtest._take_press_for_note(1750.0, 2250.0, note, 4.0)
	check(miss.is_empty(), "dense notes reject a far cursor at the correct angle")
	playtest._key_presses = [{"time": 2000.0, "mouse": point, "angle": 270.0}]
	check(not playtest._take_press_for_note(1750.0, 2250.0, note, 4.0).is_empty(), "screen position determines dense hit")
	# Cache the actual geometry, then move the visible note to the ring centre.
	var geometry := playtest._press_geometry(2000.0, 4.0)
	check(geometry.has(note.id), "press captures candidate geometry")
	playtest._key_presses = [{"time": 2000.0, "mouse": point, "geometry": geometry}]
	playtest._preview.prepare_playtest_input(0.0, far)
	check(not playtest._take_press_for_note(1750.0, 2250.0, note, 0.0).is_empty(), "later geometry cannot reject an event-time hit")
	playtest._key_presses = [{"time": 2000.0, "mouse": center, "geometry": geometry}]
	check(playtest._take_press_for_note(1750.0, 2250.0, note, 0.0).is_empty(), "later geometry cannot create an event-time hit")
	# Actual event snapshot must ignore a deliberately stale preview position.
	var actual := playtest._preview.get_local_mouse_position()
	playtest._preview.mouse_screen = Vector2(9000, 9000)
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.pressed = true
	playtest._key_presses.clear()
	playtest._input(event)
	check(playtest._key_presses.size() == 1, "live key enters queue")
	check(playtest._key_presses[0]["mouse"].is_equal_approx(actual), "key captures fresh viewport mouse position")
	playtest._set_paused(true)
	playtest._input(event)
	check(playtest._key_presses.is_empty(), "pause clears and rejects queued presses")
	playtest._set_paused(false)
	playtest.auto_play = true
	playtest._start_chart_ms = 2000.0
	playtest._last_chart_ms = -INF
	playtest._start_usec = Time.get_ticks_usec()
	playtest._process(0.016)
	check(bool(playtest._states[note.id]["done"]), "AUTO still hits through spatial judgement")
	playtest.free()
	print("Judgement consistency: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
