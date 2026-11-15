extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _run() -> void:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var note := Note.new("path", 4.0, 0.0, 60.0)
	note.end_beat = 8.0
	note.wait_beat = 1.5
	note.tail_angle = 180.0
	note.generate_path_shape()
	chart.notes.append(note)
	var loaded := ChartIO.from_json(ChartIO.to_json(chart))
	check(is_equal_approx(loaded.notes[0].wait_beat, 1.5), "single Path wait survives actual chart save/load")
	check(is_equal_approx(Playtest.slide_start_ms(loaded, loaded.notes[0], 0.0), 2750.0), "restored wait drives slide cue")
	var old := Note.path_parts_from_code("[5]path{(part0,4,0,8,180,1,0)}")
	check(old.size() == 1 and old[0].wait_beat == 0.0, "old Path code defaults to immediate movement")
	var invalid := Note.path_parts_from_code("[5]path{(part0,4,0,8,180,1,0,99)}")
	check(invalid[0].wait_beat < 4.0, "invalid wait cannot consume the entire duration")
	var child := Note.new("path", 8.0, 180.0, 60.0)
	child.id = 2
	child.end_beat = 12.0
	child.wait_beat = 0.5
	child.path_part = 1
	child.path_prev_id = note.id
	note.path_next_id = child.id
	child.generate_path_shape()
	chart.notes.append(child)
	loaded = ChartIO.from_json(ChartIO.to_json(chart))
	check(loaded.notes.size() == 2 and is_equal_approx(loaded.notes[0].wait_beat, 1.5) and is_equal_approx(loaded.notes[1].wait_beat, 0.5), "each chain part preserves its wait")
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 3.9) == Vector2.ZERO, "no countdown before landing")
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 4.0) == Vector2(0, 1), "countdown starts at landing")
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 4.75) == Vector2(0.5, 1), "half wait fills half circle")
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 5.5) == Vector2.ONE, "circle completes exactly at start")
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 6.0).y == 0.0, "indicator fades after start")
	var imported := Note.new("path", 4.0, 0.0, 60.0)
	imported.end_beat = 8.0
	imported.wait_beat = 1.5
	imported.trace_pts = [{"x": 1.0, "y": 0.0, "db": 0.0}, {"x": 1.0, "y": 0.0, "db": 1.5}, {"x": -1.0, "y": 0.0, "db": 4.0}]
	check(is_equal_approx(imported.path_motion_beat(0.0), 1.5), "imported stationary prefix is not waited twice")
	check(imported.path_local_at(imported.path_motion_beat(0.5)).distance_to(Vector2.ZERO) < 0.001, "imported star reaches midpoint halfway through movement")
	check(is_equal_approx(note.path_motion_beat(0.5), 2.0), "authored geometry without a wait prefix keeps its motion mapping")
	note.wait_beat = 0.0
	check(Preview3D.path_wait_indicator_state(chart.timing, note, 4.0) == Vector2.ZERO, "zero wait has no persistent indicator")
	note.wait_beat = 2.0
	chart.timing.points = [TimingPoint.new(0, 120, 4), TimingPoint.new(5, 60, 4)]
	check(absf(Preview3D.path_wait_indicator_state(chart.timing, note, 5.0).x - 1.0 / 3.0) < 0.001, "BPM changes use elapsed milliseconds")
	var app := root.get_node("App")
	app.chart = chart
	app.selected_notes.clear()
	var inspector := Inspector.new()
	root.add_child(inspector)
	await process_frame
	app.select_note(note.id)
	await process_frame
	var spin: SpinBox = inspector._note_widgets["path_wait"]
	check(spin.is_visible_in_tree(), "wait control is visible in active Path inspector")
	spin.value = 1.25
	check(is_equal_approx(note.wait_beat, 1.25), "editing control updates wait")
	app.undo_chart()
	note = app.chart.notes[0]
	check(is_equal_approx(note.wait_beat, 2.0), "wait edits support undo")
	app.redo_chart()
	note = app.chart.notes[0]
	check(is_equal_approx(note.wait_beat, 1.25), "wait edits support redo")
	app.path_wait_indicator = "shrink"
	app.save_settings()
	app.path_wait_indicator = "off"
	app._load_settings()
	check(app.path_wait_indicator == "shrink", "indicator choice survives settings reload")
	app.path_wait_indicator = "combined"
	app.save_settings()
	app._load_settings()
	check(app.path_wait_indicator == "progress", "removed modes fall back to progress on settings reload")
	var preview := Preview3D.new()
	preview.follow_app = false
	preview.chart_override = app.chart
	preview.size = Vector2(900, 760)
	root.add_child(preview)
	await process_frame
	for mode in app.PATH_WAIT_MODES:
		app.path_wait_indicator = mode
		for beat in [3.9, 4.0, 4.625, 5.25, 5.5]:
			preview.prepare_playtest_frame(beat, 0.016)
			preview.queue_redraw()
			await process_frame
			if "--capture" in OS.get_cmdline_user_args() and is_equal_approx(beat, 4.625):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://wait_" + mode + ".png")
		check(true, "rendered mode: " + mode)
	preview.queue_free()
	inspector.queue_free()
	await process_frame
	print("Path wait: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
