extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	var tests := [
		"test_timing",
		"test_boundary_circle",
		"test_boundary_batch",
		"test_boundary_frame",
		"test_live_edit_notifications",
		"test_self_intersection",
		"test_star_path",
		"test_nearest_u",
		"test_pre_read",
		"test_shrink_example",
		"test_event_restore",
		"test_playability_validator",
		"test_media_formats",
		"test_lbp_export",
		"test_osu_std_import",
		"test_osu_taiko_import",
		"test_osu_bpm_change",
		"test_osu_multi_difficulty",
		"test_json_roundtrip",
		"test_validation_demo",
		"test_angle_math",
		"test_trace_distance",
		"test_grid_divisions",
		"test_canvas_flow_mapping",
		"test_wav_decode",
		"test_bpm_detect_128",
		"test_bpm_detect_87",
		"test_bpm_detect_silence",
	]
	for test_name in tests:
		if call(test_name) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % test_name)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func ok(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s" % label)


func eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


func near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %.4f ± %.4f, got %.4f" % [label, expected, tolerance, actual])


func test_timing() -> bool:
	var map := TimingMap.new()
	map.points = [TimingPoint.new(0.0, 120.0, 4)]
	near(map.beat_to_chart_ms(4.0), 2000.0, 0.001, "timing 4 beats @120")
	near(map.chart_ms_to_beat(2000.0), 4.0, 0.001, "timing inverse 2000ms")
	map.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(8.0, 60.0, 4)]
	near(map.beat_to_chart_ms(12.0), 8000.0, 0.001, "timing bpm change")
	near(map.chart_ms_to_beat(8000.0), 12.0, 0.001, "timing bpm change inverse")
	map.offset_ms = -18.0
	near(map.beat_to_audio_ms(0.0), 18.0, 0.001, "timing offset")
	eq(map.format_beat(16.0), "4:0:4", "timing format beat")
	near(map.parse_beat("4:0:4"), 16.0, 0.001, "timing parse beat")
	near(map.parse_beat("4:2:4"), 18.0, 0.001, "timing parse half bar")
	return true


func test_boundary_circle() -> bool:
	var shape := BoundaryShape.circle("S0", 330.0, 32)
	near(shape.point_at(0.0).point.x, 330.0, 0.1, "circle u0 x")
	near(shape.point_at(0.0).point.y, 0.0, 0.1, "circle u0 y")
	near(shape.point_at(0.25).point.x, 0.0, 0.1, "circle u.25 x")
	near(shape.point_at(0.25).point.y, 330.0, 0.1, "circle u.25 y")
	eq(shape.validate().size(), 0, "circle validates")
	return true


func test_boundary_batch() -> bool:
	var chart := DemoChart.make_demo()
	# Cover unordered segments, gaps, both morph directions and exact seams.
	chart.get_shape("S1").segments[0].gap = true
	for shape in chart.sorted_shapes():
		shape.segments.reverse()
	var matches := true
	for beat in [0.0, 7.999, 8.0, 9.0, 10.0, 12.0, 12.125, 12.25, 12.5, 13.0, 20.0, 21.0, 24.25, 25.0]:
		var points := BoundaryRuntime.eval_shape(chart, beat, 128)
		for i in points.size():
			var expected := BoundaryRuntime.eval_point(chart, float(i) / 128.0, beat)
			if (points[i].point as Vector2).distance_to(expected.point) > 0.00001 or points[i].gap != expected.gap:
				matches = false
	ok(matches, "batch boundary samples match point evaluation through morph and restore")
	chart.events[0].target_u0 = 0.25
	chart.events[0].target_u1 = 0.75
	chart.events[0].end_behavior = "hold"
	matches = true
	for beat in [8.0, 9.0, 12.0, 12.5]:
		var points := BoundaryRuntime.eval_shape(chart, beat, 128)
		for i in points.size():
			var expected := BoundaryRuntime.eval_point(chart, float(i) / 128.0, beat)
			if (points[i].point as Vector2).distance_to(expected.point) > 0.00001 or points[i].gap != expected.gap:
				matches = false
	ok(matches, "batch boundary samples preserve partial event and hold behavior")
	var shape := chart.get_default_shape()
	var segment := shape.segment_at(0.125)
	segment.p1 += Vector2(10, 0)
	near(shape.point_at(0.125).point.distance_to(segment.p1), 0.0, 0.00001, "point lookup sees live geometry edits")
	return true


func test_boundary_frame() -> bool:
	var chart := DemoChart.make_demo()
	chart.get_shape("S1").segments[0].gap = true
	for shape in chart.sorted_shapes():
		shape.segments.reverse()
	var previous: BoundaryFrame = null
	var matches := true
	for beat in [0.0, 7.999, 8.0, 9.0, 10.0, 12.0, 12.125, 12.25, 12.5, 13.0, 20.0, 21.0, 24.25, 25.0]:
		var frame := BoundaryFrame.new(chart, beat, previous)
		var points := frame.sample_points(128)
		for i in points.size():
			var expected := BoundaryRuntime.eval_point(chart, float(i) / 128.0, beat)
			if (points[i].point as Vector2).distance_to(expected.point) > 0.00001 or points[i].gap != expected.gap:
				matches = false
		for u in [-0.25, 0.0, 0.03125, 0.12345, 0.50789, 1.0]:
			var actual := frame.point_at(u)
			var expected := BoundaryRuntime.eval_point(chart, u, beat)
			if (actual.point as Vector2).distance_to(expected.point) > 0.00001 or actual.gap != expected.gap:
				matches = false
		previous = frame
	ok(matches, "prepared frames match exact boundary evaluation across morph/restore and reused samples")
	var frame := BoundaryFrame.new(chart, 9.0)
	var projector := func(point: Vector2) -> Vector2: return point
	var mouse := Vector2(250, 100)
	var direct := BoundaryRuntime.nearest_u(chart, 9.0, mouse, projector, 96)
	var prepared := BoundaryRuntime.nearest_u(chart, 9.0, mouse, projector, 96, frame)
	near(prepared.u, direct.u, 0.000001, "prepared cursor preserves nearest u")
	near(prepared.distance, direct.distance, 0.00001, "prepared cursor preserves distance")
	var preview := Preview3D.new()
	var before := preview._boundary_point(chart, 0.0, 0.0)
	chart.get_default_shape().segment_at(0.0).p0 += Vector2(10, 0)
	preview._on_chart_live_changed()
	var after := preview._boundary_point(chart, 0.0, 0.0)
	near((after.point as Vector2).distance_to(before.point), 10.0, 0.0001, "live geometry edits invalidate prepared samples at unchanged time")
	preview.free()
	return true


func test_live_edit_notifications() -> bool:
	var app = load("res://charter/app.gd").new()
	var counts := {"live": 0, "validation": 0}
	app.set_chart(DemoChart.make_demo())
	app.chart_live_changed.connect(func() -> void: counts.live += 1)
	app.validation_changed.connect(func(_issues: Array) -> void: counts.validation += 1)
	app.begin_edit()
	for i in 30:
		app.chart.notes[0].angle = float(i)
		app.touch_chart()
	eq(counts.validation, 0, "drag does not run full validation per mouse event")
	app._process(0.016)
	eq(counts.live, 1, "drag updates coalesce into one live notification per frame")
	app.chart.notes[0].angle = 45.0
	app.touch_chart()
	app.finish_edit()
	eq(counts.live, 2, "release flushes the final mouse position")
	eq(counts.validation, 1, "release validates the committed chart")
	app.undo_chart()
	near(app.chart.notes[0].angle, 0.0, 0.001, "drag remains one undo step")
	app.redo_chart()
	near(app.chart.notes[0].angle, 45.0, 0.001, "drag redo restores final position")
	app.free()
	var preview := Preview3D.new()
	preview._mesh_dirty = false
	preview._on_chart_live_changed()
	ok(not preview._mesh_dirty, "note drag keeps the ring mesh valid")
	preview.free()
	return true


func test_self_intersection() -> bool:
	var circle := BoundaryShape.circle("C", 330.0, 32)
	eq(circle.validate().size(), 0, "circle is simple and convex")
	var star := BoundaryShape.star("STAR", 380.0, 190.0, 5)
	var star_issues := star.validate()
	var non_convex := false
	for message in star_issues:
		if String(message).contains("非凸"):
			non_convex = true
	if non_convex:
		passed += 1
	else:
		failed += 1
		push_error("non-convex star was not rejected")
	var bow := BoundaryShape.new()
	bow.id = "BOW"
	bow.closed = true
	var points: Array[Vector2] = [Vector2(-300, -300), Vector2(300, 300), Vector2(-300, 300), Vector2(300, -300)]
	for i in 4:
		bow.segments.append(BoundarySegment.new(float(i) / 4.0, float(i + 1) / 4.0, points[i], points[(i + 1) % 4], "l", "l"))
	var bow_issues := bow.validate()
	var crossed := false
	for message in bow_issues:
		if String(message).contains("自交"):
			crossed = true
	if crossed:
		passed += 1
	else:
		failed += 1
		push_error("self-intersecting bowtie was not rejected")
	return true


func test_star_path() -> bool:
	var note := Note.new("path", 0.0, 0.0, 120.0)
	note.end_beat = 4.0
	note.tail_angle = 180.0
	note.path_style = "star"
	var first := note.path_local_at(0.0)
	near(first.length(), 0.78, 0.01, "star tip radius")
	var inside := true
	for i in 41:
		var point := note.path_local_at(4.0 * float(i) / 40.0)
		if point.length() > 0.79:
			inside = false
	ok(inside, "star stays inside ring")
	ok(absf(note.path_local_at(0.8).x - note.path_local_at(1.6).x) > 0.001, "star bends across chords")
	near(absf(note.path_angle_at(2.0)), 90.0, 1.0, "star judgment stays on head-tail chord")
	var restored := Note.from_dict(note.to_dict())
	eq(restored.path_style, "star", "star style survives json")
	return true


func test_nearest_u() -> bool:
	var chart := Chart.new()
	var projector := func(point: Vector2) -> Vector2:
		return Vector2(point.x + 400.0, -point.y + 400.0)
	var right := BoundaryRuntime.nearest_u(chart, 0.0, Vector2(730.0, 400.0), projector, 512)
	near(float(right.u), 0.0, 0.01, "nearest u right")
	var top := BoundaryRuntime.nearest_u(chart, 0.0, Vector2(400.0, 70.0), projector, 512)
	near(float(top.u), 0.25, 0.01, "nearest u top")
	return true


func _preview_point(chart: Chart, u: float, target_beat: float, current_beat: float) -> Vector2:
	var c: Vector2 = BoundaryRuntime.eval_point(chart, u, current_beat).point
	var beats := chart.pre_read_ms / 60000.0 * chart.timing.bpm_at(current_beat)
	var q := clampf((current_beat - (target_beat - beats)) / maxf(0.001, beats), 0.0, 1.0)
	return c * q


func test_pre_read() -> bool:
	var chart := Chart.new()
	chart.shapes["S1"] = BoundaryShape.ellipse("S1", 410.0, 245.0, 32)
	var event := BoundaryEvent.new("E0", 8.0, 12.0, 0.0, 1.0, "S0", "S1")
	event.end_behavior = "hold"
	chart.events.append(event)
	for u in [0.0, 0.2, 0.5, 0.85]:
		for target in [4.0, 10.0, 14.0]:
			var p := _preview_point(chart, u, target, target)
			var c: Vector2 = BoundaryRuntime.eval_point(chart, u, target).point
			near(p.distance_to(c), 0.0, 0.01, "P(T)=C at u=%.2f T=%.1f" % [u, target])
	return true


func test_shrink_example() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 60.0, 4)]
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 64)
	chart.shapes["S1"] = BoundaryShape.circle("S1", 180.0, 64)
	var event := BoundaryEvent.new("E0", 0.0, 1.0, 0.0, 1.0, "S0", "S1")
	event.easing = "linear"
	event.end_behavior = "hold"
	chart.events.append(event)
	chart.pre_read_ms = 1000.0
	var u := 0.0
	var p_mid := _preview_point(chart, u, 1.0, 0.5)
	near(p_mid.x, 127.5, 0.5, "1s shrink midpoint 127.5px")
	var p_end := _preview_point(chart, u, 1.0, 1.0)
	near(p_end.x, 180.0, 0.5, "1s shrink end 180px")
	return true


func test_event_restore() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 60.0, 4)]
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 64)
	chart.shapes["S1"] = BoundaryShape.circle("S1", 180.0, 64)
	var event := BoundaryEvent.new("E0", 0.0, 1.0, 0.0, 1.0, "S0", "S1")
	event.easing = "linear"
	event.end_behavior = "restore"
	event.restore_duration = 1.0
	event.restore_easing = "linear"
	chart.events.append(event)
	var mid: Vector2 = BoundaryRuntime.eval_point(chart, 0.0, 0.5).point
	near(mid.x, 255.0, 0.5, "event mid 255px")
	var restoring: Vector2 = BoundaryRuntime.eval_point(chart, 0.0, 1.5).point
	near(restoring.x, 255.0, 0.5, "event restore mid 255px")
	var restored: Vector2 = BoundaryRuntime.eval_point(chart, 0.0, 2.0).point
	near(restored.x, 330.0, 0.5, "event restored 330px")
	return true


func test_playability_validator() -> bool:
	var chart := Chart.new()
	var a := Note.new("tap", 0.0, 0.0, 120.0)
	a.id = 1
	var b := Note.new("tap", 0.0, 90.0, 120.0)
	b.id = 2
	chart.notes = [a, b]
	var issues := Validator.validate(chart)
	if Validator.errors(issues).is_empty():
		passed += 1
	else:
		failed += 1
		for issue in Validator.errors(issues):
			push_error("PLAYABILITY unexpected: %s" % issue["message"])
	var red := Region.new(1, 0.0, 0.5)
	red.angle = 45.0
	red.width = 30.0
	chart.regions.append(red)
	var blocked := Validator.validate(chart)
	var found := false
	for issue in Validator.errors(blocked):
		if String(issue["message"]).contains("安全落脚点"):
			found = true
	if found:
		passed += 1
	else:
		failed += 1
		push_error("PLAYABILITY red-covered intersection was not rejected")
	return true


func test_media_formats() -> bool:
	ok(MediaIO.is_native_audio("a.wav"), "wav is native audio")
	ok(MediaIO.is_native_audio("a.mp3"), "mp3 is native audio")
	ok(MediaIO.is_native_video("a.ogv"), "ogv is native video")
	eq(MediaIO.prepare_audio("res://audio/demo_click.wav"), "res://audio/demo_click.wav", "native audio passes through")
	return true


func test_lbp_export() -> bool:
	var chart := DemoChart.make_demo()
	var text := LBPIO.export_chart(chart)
	ok(text.begins_with("lbp file format v2"), "lbp header")
	ok(text.contains("[TimingPoints]"), "lbp timing section")
	ok(text.contains("[BoundaryShapes]"), "lbp shapes section")
	ok(text.contains("[Notes]"), "lbp notes section")
	ok(text.contains("style=star"), "lbp keeps star path")
	ok(not text.contains("\r"), "lbp uses LF")
	var path := "user://test_export.lbp"
	eq(LBPIO.export_to_file(chart, path), OK, "lbp write")
	var read := FileAccess.get_file_as_string(path)
	eq(read, text, "lbp file matches string")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_osu_std_import() -> bool:
	var text := """osu file format v14

[General]
AudioFilename: audio.mp3
Mode: 0

[Metadata]
Title: Test
Artist: A
Creator: C
Version: Hard

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
1000,500,4,2,0,100,1,0

[HitObjects]
256,192,2000,1,0,0:0:0:0:
100,192,3000,2,0,B|200:100|300:192,1,100,0|0,0:0|0:0,0:0:0:0:
256,192,4000,8,0,5000,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "test.osu")
	ok(not result.is_empty(), "osu std parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	near(chart.offset_ms, -1000.0, 0.001, "osu offset")
	near(chart.timing.points[0].bpm, 120.0, 0.001, "osu bpm")
	eq(chart.notes.size(), 2, "osu std note count")
	var tap: Note = chart.notes[0]
	eq(tap.type, "tap", "osu circle -> tap")
	near(tap.beat, 2.0, 0.001, "osu circle beat")
	var path: Note = chart.notes[1]
	eq(path.type, "path", "osu slider -> path")
	near(path.beat, 4.0, 0.001, "osu slider beat")
	near(path.end_beat, 4.7142857, 0.001, "osu slider duration")
	eq(path.visual_pts.size(), 2, "osu slider visual points")
	return true


func test_osu_taiko_import() -> bool:
	var text := """osu file format v14

[General]
AudioFilename: audio.ogg
Mode: 1

[Metadata]
Title: T
Artist: A
Creator: C
Version: Oni

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,1000,1,0,0:0:0:0:
256,192,1500,1,2,0:0:0:0:
256,192,2000,1,4,0:0:0:0:
256,192,2500,2,0,B|300:192,1,100,0|0,0:0|0:0,0:0:0:0:
256,192,3000,8,0,4000,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "taiko.osu")
	ok(not result.is_empty(), "osu taiko parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 4, "taiko spinner skipped")
	eq(chart.notes[0].type, "tap", "taiko don tap")
	near(chart.notes[0].angle, 0.0, 0.001, "taiko quadrant 0")
	near(chart.notes[1].angle, 90.0, 0.001, "taiko quadrant 90")
	near(chart.notes[2].angle, 180.0, 0.001, "taiko quadrant 180")
	near(chart.notes[3].angle, 270.0, 0.001, "taiko quadrant 270")
	eq(chart.notes[3].type, "hold", "taiko drumroll hold")
	near(chart.notes[3].end_beat, 5.7142857, 0.001, "taiko drumroll duration")
	return true


func test_osu_bpm_change() -> bool:
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: BPM
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
1000,500,4,2,0,100,1,0
2000,400,4,2,0,100,1,0

[HitObjects]
256,192,3000,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "bpm.osu")
	ok(not result.is_empty(), "osu bpm change parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.timing.points.size(), 2, "osu two bpm points")
	near(chart.timing.points[1].beat, 2.0, 0.001, "osu bpm change beat")
	near(chart.timing.points[1].bpm, 150.0, 0.001, "osu bpm change value")
	near(chart.notes[0].beat, 4.5, 0.001, "osu object after bpm change")
	return true


func test_osu_multi_difficulty() -> bool:
	var first := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: First
Artist: A
Creator: C
Version: Easy

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,0,1,0,0:0:0:0:
"""
	var second := """osu file format v14

[General]
Mode: 1

[Metadata]
Title: Second
Artist: A
Creator: C
Version: Oni

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,0,1,0,0:0:0:0:
"""
	var path := "user://test_multi.osz"
	var packer := ZIPPacker.new()
	eq(packer.open(path), OK, "zip open")
	packer.start_file("a.osu")
	packer.write_file(first.to_utf8_buffer())
	packer.close_file()
	packer.start_file("b.osu")
	packer.write_file(second.to_utf8_buffer())
	packer.close_file()
	packer.close()
	var list := OsuIO.list_osz_difficulties(path)
	eq(list.size(), 2, "multi difficulty list")
	var result := OsuIO.import_osz(path, 1)
	ok(not result.is_empty(), "multi difficulty import")
	if not result.is_empty():
		var chart: Chart = result["chart"]
		eq(chart.metadata["title"], "Second", "second difficulty picked")
		eq(chart.notes[0].type, "tap", "second difficulty note")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_json_roundtrip() -> bool:
	var chart := DemoChart.make_demo()
	var text_a := ChartIO.to_json(chart)
	var loaded := ChartIO.from_json(text_a)
	ok(loaded != null, "json loads")
	if loaded == null:
		return true
	var text_b := ChartIO.to_json(loaded)
	eq(text_b, text_a, "json save/load/save is byte-stable")
	var path := "user://test_roundtrip.json"
	eq(ChartIO.save_chart(chart, path), OK, "json file save")
	var from_file := ChartIO.load_chart(path)
	ok(from_file != null, "json file load")
	if from_file != null:
		eq(ChartIO.to_json(from_file), text_a, "json file roundtrip stable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_validation_demo() -> bool:
	var chart := DemoChart.make_demo()
	var issues := Validator.validate(chart)
	var errors := Validator.errors(issues)
	if errors.is_empty():
		passed += 1
	else:
		failed += 1
		for issue in errors:
			push_error("VALIDATION: %s" % issue["message"])
	return true


func test_angle_math() -> bool:
	var a := JudgeMath.interval(0.0, 60.0)
	var b := JudgeMath.interval(90.0, 60.0)
	eq(JudgeMath.total_length(JudgeMath.intersect(a, b)), 0.0, "60/0 vs 60/90 no intersection")
	var c := JudgeMath.interval(0.0, 120.0)
	var d := JudgeMath.interval(90.0, 120.0)
	var common := JudgeMath.intersect(c, d)
	near(JudgeMath.total_length(common), 30.0, 0.001, "120/0 vs 120/90 common 30deg")
	var safe := JudgeMath.subtract(common, JudgeMath.interval(90.0, 60.0))
	near(JudgeMath.total_length(safe), 30.0, 0.001, "subtract red leaves 30deg")
	var empty_result := JudgeMath.subtract(common, JudgeMath.interval(45.0, 90.0))
	eq(JudgeMath.total_length(empty_result), 0.0, "red covers all")
	return true


func test_trace_distance() -> bool:
	var line: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	near(JudgeMath.trace_distance(Vector2(0.5, 0.25), line), 0.25, 0.001, "trace distance")
	return true


func test_grid_divisions() -> bool:
	eq(GridDivisions.label(4), "1/4", "grid label 1/4")
	eq(GridDivisions.label(12), "1/12", "grid label 1/12")
	eq(GridDivisions.label(13), "1/4", "grid label falls back to default")
	near(GridDivisions.step_beats(4), 0.25, 0.000001, "grid step 1/4")
	near(GridDivisions.step_beats(6), 1.0 / 6.0, 0.000001, "grid step 1/6")
	near(GridDivisions.snap(0.31, 4), 0.25, 0.000001, "grid snap quarter")
	near(GridDivisions.snap(0.31, 8), 0.25, 0.000001, "grid snap eighth rounds down")
	near(GridDivisions.snap(0.33, 8), 0.375, 0.000001, "grid snap eighth rounds up")
	near(GridDivisions.snap(0.34, 3), 1.0 / 3.0, 0.000001, "grid snap triplet")
	eq(GridDivisions.snap(0.31, 4, true), 0.31, "grid snap bypass")
	eq(GridDivisions.normalize(5), 4, "grid normalize keeps only listed divisions")
	eq(GridDivisions.index_of(12), 5, "grid index of 1/12")
	return true


func test_canvas_flow_mapping() -> bool:
	var canvas := ChartCanvas.new()
	canvas.size = Vector2(800.0, 600.0)
	canvas.px_per_beat = 20.0
	canvas.scroll_beat = 0.0
	canvas.flow_down = true
	near(canvas._beat_to_y(4.0) - canvas._beat_to_y(0.0), 80.0, 0.001, "canvas flow down: later beats are lower")
	near(canvas._y_to_beat(canvas._beat_to_y(7.0)), 7.0, 0.0001, "canvas flow down round trip")
	canvas.flow_down = false
	near(canvas._beat_to_y(4.0) - canvas._beat_to_y(0.0), -80.0, 0.001, "canvas flow up: later beats are higher")
	near(canvas._y_to_beat(canvas._beat_to_y(7.0)), 7.0, 0.0001, "canvas flow up round trip")
	canvas.free()
	return true


func test_wav_decode() -> bool:
	var path := "user://test_tone.wav"
	_write_test_wav(path, 22050, 1.0, 441.0)
	var samples := AudioPCM.load_mono(path, 11025)
	ok(samples.size() > 9000 and samples.size() < 12000, "wav decode frame count: %d" % samples.size())
	if samples.size() > 100:
		var peak := 0.0
		for value in samples:
			peak = maxf(peak, absf(value))
		near(peak, 0.5, 0.06, "wav decode amplitude")
		var zero_crossings := 0
		for i in samples.size() - 1:
			if samples[i] <= 0.0 and samples[i + 1] > 0.0:
				zero_crossings += 1
		var frequency := float(zero_crossings) / (float(samples.size()) / 11025.0)
		near(frequency, 441.0, 12.0, "wav decode resampled frequency")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_bpm_detect_128() -> bool:
	var samples := _click_track(128.0, 350.0, 24.0, 11025.0)
	var result := BpmDetect.analyze(samples, 11025.0)
	ok(bool(result["ok"]), "bpm detect 128 ok (%s)" % String(result.get("error", "")))
	near(float(result["bpm"]), 128.0, 0.2, "bpm detect 128 tempo")
	near(float(result["offset_ms"]), 350.0, 8.0, "bpm detect 128 offset")
	ok(float(result["confidence"]) > 0.6, "bpm detect 128 confidence")
	return true


func test_bpm_detect_87() -> bool:
	var samples := _click_track(87.0, 120.0, 24.0, 11025.0)
	var result := BpmDetect.analyze(samples, 11025.0)
	ok(bool(result["ok"]), "bpm detect 87 ok (%s)" % String(result.get("error", "")))
	near(float(result["bpm"]), 87.0, 0.2, "bpm detect 87 tempo")
	near(float(result["offset_ms"]), 120.0, 8.0, "bpm detect 87 offset")
	return true


func test_bpm_detect_silence() -> bool:
	var samples := PackedFloat32Array()
	samples.resize(11025 * 4)
	var result := BpmDetect.analyze(samples, 11025.0)
	ok(not bool(result["ok"]), "bpm detect rejects silence")
	return true


func _write_test_wav(path: String, rate: int, seconds: float, frequency: float) -> void:
	var frames := int(float(rate) * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var value := int(round(sin(TAU * frequency * float(i) / float(rate)) * 0.5 * 32767.0))
		data.encode_s16(i * 2, value)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data.size())
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(rate)
	file.store_32(rate * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data.size())
	file.store_buffer(data)
	file.close()


func _click_track(bpm: float, offset_ms: float, seconds: float, rate: float) -> PackedFloat32Array:
	var frames := int(rate * seconds)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	for i in frames:
		samples[i] = (rng.randf() * 2.0 - 1.0) * 0.015
	var period := 60.0 / bpm
	var beat := 0
	while true:
		var start := int(round((offset_ms / 1000.0 + float(beat) * period) * rate))
		if start >= frames:
			break
		var click_length := int(0.04 * rate)
		for i in click_length:
			var index := start + i
			if index >= frames:
				break
			var decay := exp(-float(i) / (0.009 * rate))
			samples[index] += sin(TAU * 170.0 * float(i) / rate) * decay * 0.5
			samples[index] += sin(TAU * 1200.0 * float(i) / rate) * decay * 0.22
		beat += 1
	return samples
