extends Control

var NOTE_COUNT := 10000
var SEGMENTS := 200


func _ready() -> void:
	var env_count := OS.get_environment("BENCH_NOTES")
	if not env_count.is_empty():
		NOTE_COUNT = int(env_count)
	var env_segments := OS.get_environment("BENCH_SEGMENTS")
	if not env_segments.is_empty():
		SEGMENTS = int(env_segments)
	var app := get_node_or_null("/root/App")
	var chart := _make_chart(NOTE_COUNT, SEGMENTS)
	app.chart = chart
	app.chart_path = ""
	var canvas: ChartCanvas = load("res://tests/bench_canvas.gd").new() as ChartCanvas
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	canvas.scroll_beat = 400.0
	canvas.px_per_beat = 28.0
	canvas.queue_redraw()
	await _frames(12)
	for i in 60:
		canvas.queue_redraw()
		await get_tree().process_frame
	var canvas_ms := float(canvas.total_us) / float(maxi(1, canvas.draw_count)) / 1000.0
	print("BENCH canvas_draw_ms=%.2f frames=%d" % [canvas_ms, canvas.draw_count])
	canvas.queue_free()
	await _frames(2)

	var preview: Preview3D = load("res://tests/bench_preview.gd").new() as Preview3D
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	preview.chart_override = chart
	preview.follow_app = false
	preview.playtest_mode = false
	preview.show_hud = true
	preview.time_beat = 400.0
	await _frames(12)
	for i in 60:
		preview.time_beat = 400.0 + float(i) * 0.016
		await get_tree().process_frame
	var preview_ms := float(preview.total_us) / float(maxi(1, preview.draw_count)) / 1000.0
	print("BENCH preview_overlay_ms=%.2f frames=%d" % [preview_ms, preview.draw_count])
	print("BENCH preview_sections_ms ", preview.summary())
	var counts := {"path": 0, "hold": 0, "tap": 0}
	for note in chart.notes:
		if note.type in ["path", "hold"]:
			if 400.0 >= note.beat - 2.0 and 400.0 <= note.end_beat + 0.5:
				counts[note.type] += 1
		elif absf(note.beat - 400.0) <= 2.0:
			counts["tap"] += 1
	print("BENCH visible_counts ", counts)
	preview.queue_free()
	await _frames(2)

	var inspector := Inspector.new()
	inspector.theme = UITheme.build()
	var inspector_add_t := Time.get_ticks_usec()
	add_child(inspector)
	print("BENCH inspector_startup_ms=%.2f" % (float(Time.get_ticks_usec() - inspector_add_t) / 1000.0))
	await _frames(2)
	var first_select_t := Time.get_ticks_usec()
	app.select_note(chart.notes[0].id)
	print("BENCH inspector_first_select_ms=%.2f" % (float(Time.get_ticks_usec() - first_select_t) / 1000.0))
	var next_select_t := Time.get_ticks_usec()
	app.select_note(chart.notes[1].id)
	print("BENCH inspector_next_select_ms=%.2f" % (float(Time.get_ticks_usec() - next_select_t) / 1000.0))
	inspector.current_tab = 0
	await _frames(2)
	var rebuild_times: Array[float] = []
	for k in 5:
		var t := Time.get_ticks_usec()
		inspector._rebuild()
		rebuild_times.append(float(Time.get_ticks_usec() - t) / 1000.0)
	print("BENCH inspector_rebuild_ms=%.2f first=%.2f" % [rebuild_times[rebuild_times.size() - 1], rebuild_times[0]])
	inspector.queue_free()
	await _frames(2)

	var dict := ChartIO.chart_to_dict(chart)
	var t := Time.get_ticks_usec()
	var text := ChartIO.to_json(chart)
	print("BENCH save_ms=%.2f bytes=%d" % [float(Time.get_ticks_usec() - t) / 1000.0, text.length()])
	t = Time.get_ticks_usec()
	var restored := ChartIO.chart_from_dict(dict)
	print("BENCH open_ms=%.2f notes=%d" % [float(Time.get_ticks_usec() - t) / 1000.0, restored.notes.size()])
	t = Time.get_ticks_usec()
	var issues := Validator.validate(chart)
	print("BENCH validate_ms=%.2f issues=%d" % [float(Time.get_ticks_usec() - t) / 1000.0, issues.size()])
	t = Time.get_ticks_usec()
	var shape_issues := chart.get_shape("S0").validate()
	print("BENCH shape_validate_ms=%.2f issues=%d" % [float(Time.get_ticks_usec() - t) / 1000.0, shape_issues.size()])
	t = Time.get_ticks_usec()
	for i in 5:
		app.mutate(func() -> void: chart.notes[0].angle = fposmod(chart.notes[0].angle + 1.0, 360.0))
	print("BENCH mutate_ms=%.2f" % [float(Time.get_ticks_usec() - t) / 5000.0])
	print("BENCH memory_mb=%.1f" % (float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0))
	print("BENCH notes=%d segments=%d" % [chart.notes.size(), chart.get_shape("S0").segments.size()])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _make_chart(count: int, segments: int) -> Chart:
	var chart := Chart.new()
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, segments)
	chart.default_shape_id = "S0"
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(1000.0, 180.0, 4)]
	chart.timing.sort_points()
	var types: Array[String] = ["tap", "hold", "path", "anchor", "bell"]
	for i in count:
		var type := types[i % types.size()]
		var beat := float(i) * 0.2
		var angle := fposmod(float(i) * 37.0, 360.0)
		var note := Note.new(type, beat, angle, 60.0)
		note.id = chart.next_note_id()
		if type == "hold":
			note.end_beat = beat + 2.0
			note.hold_style = "straight"
		elif type == "path":
			note.end_beat = beat + 2.0
			note.tail_angle = fposmod(angle + 90.0, 360.0)
			note.trace_pts = [
				{"x": cos(deg_to_rad(angle)), "y": sin(deg_to_rad(angle)), "db": 0.0},
				{"x": cos(deg_to_rad(angle + 60.0)) * 0.7, "y": sin(deg_to_rad(angle + 60.0)) * 0.7, "db": 1.0},
				{"x": cos(deg_to_rad(angle + 90.0)), "y": sin(deg_to_rad(angle + 90.0)), "db": 2.0},
			]
		elif type == "bell":
			note.center_u = angle / 360.0
			note.radius = 40.0
		chart.notes.append(note)
	return chart
