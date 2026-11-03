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
		"test_plane_path",
		"test_nearest_u",
		"test_pre_read",
		"test_shrink_example",
		"test_event_restore",
		"test_playability_validator",
		"test_media_formats",
		"test_lbp_export",
		"test_osu_std_import",
		"test_osu_std_curves",
		"test_osu_std_slider_kinds",
		"test_osu_std_negative_shift",
		"test_osu_std_readability",
		"test_osu_taiko_import",
		"test_osu_taiko_flow",
		"test_osu_bpm_change",
		"test_osu_multi_difficulty",
		"test_json_roundtrip",
		"test_validation_demo",
		"test_angle_math",
		"test_trace_distance",
		"test_sfx_assets",
		"test_simai_import",
		"test_osu_std_sentakki_rules",
		"test_simai_directive_slot",
		"test_simai_bend_shapes",
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


func test_plane_path() -> bool:
	var note := Note.new("path", 0.0, 0.0, 120.0)
	note.end_beat = 4.0
	note.tail_angle = 180.0
	eq(note.space, "plane", "path defaults to the plane")
	near(note.path_local_at(0.0).length(), 1.0, 0.01, "path head on the ring")
	near(note.path_local_at(4.0).length(), 0.72, 0.01, "legacy path tail moves inside")
	var inside := true
	for i in 41:
		var point := note.path_local_at(4.0 * float(i) / 40.0)
		if point.length() > 1.01:
			inside = false
	ok(inside, "path body stays inside the ring")
	note.trace_pts = [
		{"x": 1.0, "y": 0.0, "db": 0.0},
		{"x": 0.5, "y": 0.5, "db": 2.0},
		{"x": 0.0, "y": 0.7, "db": 4.0},
	]
	near(note.path_local_at(2.0).x, 0.5, 0.001, "plane path follows explicit points")
	near(note.path_local_at(2.0).y, 0.5, 0.001, "plane path interpolates y")
	note.path_gaps = [{"from": 0.4, "to": 0.6}]
	ok(note.erased_at(2.0), "path erase range hits middle")
	ok(not note.erased_at(0.5), "path erase range leaves head")
	var erased_sample := false
	for sample_beat in note.path_sample_beats():
		if note.erased_at(sample_beat - note.beat):
			erased_sample = true
	ok(not erased_sample, "erased path section has no hidden checkpoints")
	var restored := Note.from_dict(note.to_dict())
	eq(restored.space, "plane", "plane path survives json")
	eq(restored.trace_pts.size(), 3, "plane path points survive json")
	eq(restored.path_gaps.size(), 1, "path gaps survive json")
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
	ok(not text.contains("style=star"), "lbp no longer writes ring star paths")
	ok(text.contains("path,"), "lbp keeps planar path notes")
	var gap_note := Note.new("path", 40.0, 0.0, 60.0)
	gap_note.id = chart.next_note_id()
	gap_note.end_beat = 44.0
	gap_note.path_gaps = [{"from": 0.4, "to": 0.6}]
	chart.notes.append(gap_note)
	var gap_text := LBPIO.export_chart(chart)
	ok(gap_text.contains("erase=0.400:0.600"), "lbp keeps path erase range")
	chart.notes.erase(gap_note)
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
	eq(tap.space, "ring", "osu circle stays on the ring")
	near(tap.beat, 2.0, 0.001, "osu circle beat")
	ok(tap.width >= 45.0 and tap.width <= 75.0, "osu tap has variable width")
	var slide: Note = chart.notes[1]
	eq(slide.type, "path", "osu slider -> planar path")
	eq(slide.space, "plane", "osu slider dives into the plane")
	near(slide.beat, 4.0, 0.001, "osu slider beat")
	near(slide.end_beat, 4.7142857, 0.001, "osu slider duration")
	ok(slide.trace_pts.size() > 8, "osu slider has a 2D slide path")
	var first: Dictionary = slide.trace_pts[0]
	var last: Dictionary = slide.trace_pts[-1]
	near(sqrt(pow(float(first["x"]), 2) + pow(float(first["y"]), 2)), 1.0, 0.02, "slide head on the ring")
	near(sqrt(pow(float(last["x"]), 2) + pow(float(last["y"]), 2)), 0.70, 0.02, "slide tail lands on the 0.70R circle")
	var inside := true
	for point in slide.trace_pts:
		if sqrt(pow(float(point["x"]), 2) + pow(float(point["y"]), 2)) > 1.02:
			inside = false
	ok(inside, "slide path stays inside the ring disk")
	var restored := Note.from_dict(slide.to_dict())
	eq(restored.type, "path", "slide path survives json")
	eq(restored.space, "plane", "slide plane survives json")
	return true


func test_osu_std_curves() -> bool:
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: Curves
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,1000,2,0,L|400:192,1,200,0|0,0:0|0:0,0:0:0:0:
256,192,2000,2,0,B|300:100|400:192,1,200,0|0,0:0|0:0,0:0:0:0:
256,192,3000,2,0,C|300:100|400:192,1,200,0|0,0:0|0:0,0:0:0:0:
256,192,4000,2,0,P|300:100|400:192,1,200,0|0,0:0|0:0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "curves.osu")
	ok(not result.is_empty(), "osu std curves parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 4, "four slider curves imported")
	for note in chart.notes:
		eq(note.type, "path", "curve %s is a plane path" % note.id)
		eq(note.space, "plane", "curve %s stays planar" % note.id)
		ok(note.trace_pts.size() >= 8, "curve %s has enough slide samples" % note.id)
		var previous_db := -1.0
		var monotonic := true
		var inside := true
		for point in note.trace_pts:
			var radius := sqrt(pow(float(point["x"]), 2) + pow(float(point["y"]), 2))
			var db := float(point.get("db", -1.0))
			if radius > 1.02:
				inside = false
			if db + 0.0001 < previous_db:
				monotonic = false
			previous_db = db
		ok(inside, "curve %s stays inside the ring disk" % note.id)
		ok(monotonic, "curve %s time is monotonic" % note.id)
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
256,192,1250,1,2,0:0:0:0:
256,192,1500,1,4,0:0:0:0:
256,192,1750,1,0,0:0:0:0:
256,192,2000,2,0,B|300:192,1,280,0|0,0:0|0:0,0:0:0:0:
256,192,4000,8,0,5000,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "taiko.osu")
	ok(not result.is_empty(), "osu taiko parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 5, "taiko spinner skipped, short objects kept")
	eq(chart.notes[0].type, "tap", "taiko don tap")
	near(chart.notes[0].angle, 0.0, 0.001, "taiko don lane")
	near(chart.notes[1].angle, 90.0, 0.001, "taiko kat lane")
	eq(chart.notes[1].width, 76.0, "taiko kat width")
	near(chart.notes[2].angle, 0.0, 0.001, "taiko finish stays don")
	eq(chart.notes[2].width, 90.0, "taiko finish width")
	near(chart.notes[3].angle, 0.0, 0.001, "taiko don returns to nearby lane")
	eq(chart.notes[4].type, "hold", "long taiko slider is a drumroll")
	near(chart.notes[4].end_beat, 6.0, 0.001, "taiko drumroll duration")
	return true


func test_osu_taiko_flow() -> bool:
	var text := """osu file format v14

[General]
Mode: 1

[Metadata]
Title: Flow
Artist: A
Creator: C
Version: Oni

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,1000,1,0,0:0:0:0:
256,192,1125,1,2,0:0:0:0:
256,192,1250,1,0,0:0:0:0:
256,192,1375,1,2,0:0:0:0:
256,192,1500,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "taiko_flow.osu")
	ok(not result.is_empty(), "taiko flow parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 5, "taiko flow note count")
	var stacked := true
	for i in range(1, chart.notes.size()):
		if absf(JudgeMath.angle_delta(chart.notes[0].angle, chart.notes[i].angle)) > 0.001:
			stacked = false
	ok(stacked, "dense taiko notes stack instead of rotating")
	return true


func test_osu_std_slider_kinds() -> bool:
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: SliderKinds
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,1000,2,0,L|300:192,1,50,0|0,0:0|0:0,0:0:0:0:
256,192,2000,2,0,L|400:192,2,200,0|0,0:0|0:0,0:0:0:0:
256,192,3000,2,0,L|400:192,1,280,0|0,0:0|0:0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "kinds.osu")
	ok(not result.is_empty(), "std slider kinds parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 3, "slider kinds note count")
	eq(chart.notes[0].type, "hold", "short slider -> hold")
	eq(chart.notes[1].type, "hold", "repeat slider -> hold")
	eq(chart.notes[2].type, "path", "long slider -> plane path")
	eq(chart.notes[2].space, "plane", "long slider stays planar")
	ok(chart.notes[2].end_beat > chart.notes[2].beat, "long slider slide has duration")
	return true


func test_osu_std_negative_shift() -> bool:
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: Shift
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
1000,500,4,2,0,100,1,0

[HitObjects]
256,192,500,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "shift.osu")
	ok(not result.is_empty(), "negative shift parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 1, "negative shift note count")
	near(chart.notes[0].beat, 0.0, 0.001, "earliest note shifted to beat 0")
	near(chart.offset_ms, -500.0, 0.001, "offset adjusted for shift")
	near(chart.timing.beat_to_chart_ms(0.0), 0.0, 0.001, "shifted beat 0 maps to chart 0")
	return true


func test_osu_std_readability() -> bool:
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: Read
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,0,1000,1,0,0:0:0:0:
512,192,1500,1,0,0:0:0:0:
256,384,2000,1,0,0:0:0:0:
0,192,2500,1,0,0:0:0:0:
256,0,3000,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "read.osu")
	ok(not result.is_empty(), "osu std readability parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	eq(chart.notes.size(), 5, "std readability note count")
	near(chart.notes[0].angle, 270.0, 0.001, "std first note keeps absolute angle")
	var max_step := 0.0
	var min_step := 360.0
	for i in range(1, chart.notes.size()):
		var step := absf(JudgeMath.angle_delta(chart.notes[i - 1].angle, chart.notes[i].angle))
		max_step = maxf(max_step, step)
		min_step = minf(min_step, step)
	ok(max_step <= 180.1, "std continuous step stays under speed cap (max %.1f)" % max_step)
	ok(min_step > 10.0, "std notes are not all stacked (min %.1f)" % min_step)
	for note in chart.notes:
		eq(note.space, "ring", "std readability stays on the ring")
		ok(note.width >= 45.0 and note.width <= 75.0, "std width is playable")
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


func test_sfx_assets() -> bool:
	for kind in HitSfx.PATHS:
		var stream: AudioStream = load(String(HitSfx.PATHS[kind]))
		ok(stream != null, "sfx loads %s" % kind)
	return true


func test_trace_distance() -> bool:
	var line: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	near(JudgeMath.trace_distance(Vector2(0.5, 0.25), line), 0.25, 0.001, "trace distance")
	return true


func test_simai_import() -> bool:
	var text := "&title=Simai Test\n&artist=Tester\n&first=1\n&wholebpm=120\n&lv_1=5\n&des_1=me\n&inote_1=(120){4}\n1,2h[4:1],1-5[4:1],E1,\nE\n"
	var path := "user://test_simai_maidata.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "simai fixture write")
		return true
	file.store_string(text)
	file.close()
	var diffs := SimaiIO.list_maidata(path)
	eq(diffs.size(), 1, "simai difficulty detected")
	if not diffs.is_empty():
		eq(String(diffs[0]["version"]), "Lv.5", "simai level label")
	var chart := SimaiIO.import_maidata(path, 1)
	ok(chart != null, "simai imports")
	if chart == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return true
	near(chart.offset_ms, -1000.0, 0.001, "simai first -> offset")
	eq(chart.notes.size(), 4, "simai keeps four notes")
	var types: Array[String] = []
	for note in chart.notes:
		types.append(note.type)
	eq(types, ["tap", "hold", "path", "bell"], "simai note types")
	eq(Validator.errors(Validator.validate(chart)).size(), 0, "simai import is playable without double-hand conflicts")
	if chart.notes.size() >= 3:
		near(chart.notes[0].angle, 90.0, 0.001, "simai button 1 is top")
		near(chart.notes[2].end_beat, 4.0, 0.001, "simai slide wait + duration")
		near(chart.notes[2].tail_angle, 270.0, 0.001, "simai slide tail button 5")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_osu_std_sentakki_rules() -> bool:
	eq(OsuIO.STD_STREAM_STEP, 45.0, "osu std stream step is 8-lane 45deg")
	var text := """osu file format v14

[General]
Mode: 0

[Difficulty]
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
256,192,1000,2,0,L|400:192,1,280,0|0,0:0|0:0,0:0:0:0:
256,192,1300,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "sentakki.osu")
	ok(not result.is_empty(), "sentakki rules chart parses")
	if result.is_empty():
		return true
	var chart: Chart = result["chart"]
	var trace: Note = chart.notes[0]
	eq(trace.type, "path", "long slider becomes plane path")
	ok(trace.wait_beat > 0.0, "slide has a wait phase before moving")
	near(trace.end_beat - trace.beat, 2.0, 0.001, "slide end beat stays on the osu timeline")
	return true


func test_simai_directive_slot() -> bool:
	# 带有逗号的纯指令 token 必须占一个空拍，否则整张谱会提前。
	var text := "&title=T\n&wholebpm=120\n&lv_1=1\n&inote_1=(120){4},1,2,\nE\n"
	var path := "user://test_simai_directive.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "simai directive fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 1)
	ok(chart != null, "simai directive chart imports")
	if chart != null:
		near(chart.notes[0].beat, 1.0, 0.001, "directive-only token occupies one slot")
		near(chart.notes[1].beat, 2.0, 0.001, "next note stays on the grid")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_simai_bend_shapes() -> bool:
	var text := "&title=T\n&wholebpm=120\n&lv_1=1\n&inote_1=(120){4},1v5[4:1],1p3[4:1],\nE\n"
	var path := "user://test_simai_bend.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "simai bend fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 1)
	ok(chart != null, "simai bend chart imports")
	if chart != null:
		var bent := 0
		for note in chart.notes:
			if note.type == "path" and note.trace_pts.size() >= 20:
				var tail: Dictionary = note.trace_pts[-1]
				if sqrt(pow(float(tail["x"]), 2) + pow(float(tail["y"]), 2)) < 0.75:
					bent += 1
		ok(bent >= 1, "v/p shapes become plane paths")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true
