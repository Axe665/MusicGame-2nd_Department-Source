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
		"test_path_axis_centrifuge",
		"test_demo_path_migration",
		"test_legacy_path_chart_migration",
		"test_path_erase_overlap",
		"test_path_erase_merge",
		"test_path_run_split",
		"test_style_presets",
		"test_position_judgement",
		"test_press_assignment",
		"test_timing_stats",
		"test_nearest_u",
		"test_pre_read",
		"test_bar_lines",
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
		"test_osu_std_chain_no_conflict",
		"test_note_span_defaults",
		"test_judgement_text_font",
		"test_osu_taiko_import",
		"test_osu_taiko_flow",
		"test_osu_bpm_change",
		"test_osu_multi_difficulty",
		"test_json_roundtrip",
		"test_validation_demo",
		"test_angle_math",
		"test_note_mirror",
		"test_trace_distance",
		"test_sfx_assets",
		"test_simai_import",
		"test_osu_std_sentakki_rules",
		"test_simai_directive_slot",
		"test_simai_bend_shapes",
		"test_simai_osu_friendly",
		"test_simai_dense_relax",
		"test_simai_relax_keeps_slow",
		"test_sentakki_slide_library",
		"test_editor_tabs",
		"test_convert_optimizer_fast_path",
		"test_simai_bpm_jump_star_speed",
		"test_ring_sector_and_tail_tier",
		"test_path_sector_erase",
		"test_note_length_system",
		"test_osu_std_lanes",
		"test_path_custom_color",
		"test_grid_divisions",
		"test_canvas_flow_mapping",
		"test_wav_decode",
		"test_bpm_detect_128",
		"test_bpm_detect_87",
		"test_bpm_detect_silence",
		"test_auto_play",
		"test_note_retire_state",
		"test_path_tail_judge",
		"test_slide_floor",
		"test_bell_path_clearance",
		"test_simai_same_head_and_chain",
		"test_simai_touch_layers",
		"test_simai_seconds_slot",
		"test_maimai_overlap_and_off_track",
		"test_maimai_interaction_compress",
		"test_interaction_run_lock",
		"test_note_pop_scale",
		"test_maimai_hold_clamp",
		"test_import_window_set",
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
	eq(TimingMap.parse_beat_subdivision("4"), 4, "beat subdivision parse 4")
	eq(TimingMap.parse_beat_subdivision(" 8 "), 8, "beat subdivision parse trims spaces")
	eq(TimingMap.parse_beat_subdivision("0"), 0, "beat subdivision rejects zero")
	eq(TimingMap.parse_beat_subdivision("-2"), 0, "beat subdivision rejects negative")
	eq(TimingMap.parse_beat_subdivision("3.5"), 0, "beat subdivision rejects fraction")
	eq(TimingMap.parse_beat_subdivision("abc"), 0, "beat subdivision rejects text")
	eq(TimingMap.parse_beat_subdivision(""), 0, "beat subdivision rejects empty")
	eq(TimingMap.parse_beat_subdivision("65"), 0, "beat subdivision rejects over max")
	var offsets := TimingMap.beat_subdivision_offsets(4)
	eq(offsets.size(), 3, "beat subdivision 4 has 3 thin lines")
	near(offsets[0], 0.25, 0.00001, "beat subdivision offset 0")
	near(offsets[1], 0.5, 0.00001, "beat subdivision offset 1")
	near(offsets[2], 0.75, 0.00001, "beat subdivision offset 2")
	eq(TimingMap.beat_subdivision_offsets(1).size(), 0, "beat subdivision 1 draws no thin line")
	eq(TimingMap.parse_vertical_lines("21"), 21, "vertical lines parse 21")
	eq(TimingMap.parse_vertical_lines("64"), 64, "vertical lines parse max 64")
	eq(TimingMap.parse_vertical_lines("65"), 0, "vertical lines reject over max")
	eq(TimingMap.parse_vertical_lines("0"), 0, "vertical lines reject zero")
	eq(TimingMap.parse_vertical_lines("2.5"), 0, "vertical lines reject fraction")
	eq(TimingMap.parse_vertical_lines("abc"), 0, "vertical lines reject text")
	var vlines := TimingMap.vertical_line_offsets(21)
	eq(vlines.size(), 21, "vertical lines 21 has 21 lines")
	near(vlines[0], 1.0 / 22.0, 0.00001, "vertical lines first at 1/22")
	near(vlines[20], 21.0 / 22.0, 0.00001, "vertical lines last at 21/22")
	near(vlines[1] - vlines[0], 1.0 / 22.0, 0.00001, "vertical lines are evenly spaced")
	near(TimingMap.nearest_vertical_line_u(0.51, 21), 11.0 / 22.0, 0.00001, "vertical lines snap to nearest interior line")
	eq(TimingMap.vertical_line_offsets(0).size(), 0, "vertical lines 0 draws nothing")
	near(TimingMap.nearest_beat_subdivision(1.13, 4), 1.25, 0.00001, "subdivision 4 snaps to 1.25")
	near(TimingMap.nearest_beat_subdivision(1.12, 4), 1.0, 0.00001, "subdivision 4 snaps to 1.0")
	near(TimingMap.nearest_beat_subdivision(2.4, 3), 7.0 / 3.0, 0.00001, "subdivision 3 snaps to 7/3")
	near(TimingMap.nearest_beat_subdivision(1.13, 5), 1.2, 0.00001, "subdivision 5 follows changed value")
	near(TimingMap.nearest_beat_subdivision(1.09, 5), 1.0, 0.00001, "subdivision 5 rounds down")
	near(TimingMap.normalize_bpm(120.0), 120.0, 0.0001, "bpm keeps integer")
	near(TimingMap.normalize_bpm(120.5), 121.0, 0.0001, "bpm one decimal rounds to integer")
	near(TimingMap.normalize_bpm(120.25), 120.25, 0.0001, "bpm keeps two decimals")
	near(TimingMap.normalize_bpm(120.255), 120.255, 0.0001, "bpm keeps three decimals")
	near(TimingMap.normalize_bpm(120.2554), 120.255, 0.0001, "bpm rounds to three decimals")
	near(TimingMap.normalize_offset_ms(500.0206), 500.021, 0.0001, "offset keeps three decimals")
	near(TimingMap.normalize_offset_ms(-18.0004), -18.0, 0.0001, "offset negative rounds to three decimals")
	near(TimingMap.normalize_offset_ms(0.0004), 0.0, 0.0001, "offset zero is normalized")
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
	note.path_speed = 1.35
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
	near(restored.path_speed, 1.35, 0.001, "path slide speed survives json")
	eq(restored.path_gaps.size(), 1, "path gaps survive json")
	return true


func test_path_axis_centrifuge() -> bool:
	var note := Note.new("path", 0.0, 0.0, 60.0)
	note.end_beat = 4.0
	note.tail_angle = 180.0
	note.path_centrifuge = 1.0
	note.path_axis = 0.0
	note.generate_path_shape()
	near(note.path_tail_local().length(), 1.0, 0.001, "centrifuge 1 tail on ring")
	var mid := note.path_local_at(2.0)
	near(mid.x, 0.0, 0.001, "axis 0 straight x")
	near(mid.y, 0.0, 0.001, "axis 0 straight y")
	note.set_path_axis(0.5)
	mid = note.path_local_at(2.0)
	near(mid.y, -1.0, 0.01, "positive axis bows one way")
	note.set_path_axis(-0.5)
	mid = note.path_local_at(2.0)
	near(mid.y, 1.0, 0.01, "negative axis mirrors across chord")
	note.set_path_axis(2.0)
	mid = note.path_local_at(2.0)
	ok(note.path_axis <= 0.501, "axis clamps before midpoint leaves ring")
	ok(mid.length() <= 1.001, "clamped midpoint stays inside ring")
	note.set_path_centrifuge(0.0)
	near(note.path_tail_local().length(), 0.0, 0.001, "centrifuge 0 at centre")
	note.path_part = 1
	note.path_prev_id = 3
	note.path_next_id = 5
	note.path_head_local = Vector2(0.5, 0.2)
	var restored := Note.from_dict(note.to_dict())
	eq(restored.path_part, 1, "path part survives json")
	eq(restored.path_prev_id, 3, "path previous link survives json")
	eq(restored.path_next_id, 5, "path next link survives json")
	near(restored.path_head_local.x, 0.5, 0.001, "path part head x survives json")
	return true


func test_demo_path_migration() -> bool:
	var chart := ChartIO.load_chart("res://charts/demo.json")
	ok(chart != null, "migrated demo loads")
	if chart == null:
		return true
	var paths := 0
	for note in chart.notes:
		if note.type != "path":
			continue
		paths += 1
		ok(note.path_controls_set, "demo path has controls")
		ok(note.trace_pts.size() > 1, "demo path has generated trace")
		ok(note.path_centrifuge >= 0.0 and note.path_centrifuge <= 1.0, "demo centrifuge in range")
		ok(note.path_axis >= -2.0 and note.path_axis <= 2.0, "demo axis in range")
	eq(paths, 6, "demo path count")
	return true


func test_legacy_path_chart_migration() -> bool:
	var chart := DemoChart.make_demo()
	var data := ChartIO.chart_to_dict(chart)
	for raw in data.get("notes", []):
		if raw.get("type") == "path":
			raw.erase("centrifuge")
			raw.erase("axis")
			raw.erase("trace")
			raw["visual"] = [{"db": 0.5, "da": 12.0}]
			break
	var loaded := ChartIO.chart_from_dict(data)
	var migrated := false
	for note in loaded.notes:
		if note.type != "path":
			continue
		migrated = true
		ok(note.path_controls_set, "legacy chart path gains controls")
		ok(note.trace_pts.size() > 1, "legacy chart path gains new trace")
		eq(note.visual_pts.size(), 0, "legacy chart path drops old visual points")
		break
	ok(migrated, "legacy chart path found after migration")
	return true


func test_path_erase_overlap() -> bool:
	var line := PackedVector2Array()
	for i in 101:
		line.append(Vector2(float(i), 0.0))
	var small := Preview3D.path_erase_ranges(line, Vector2(50, 0), Vector2(50, 0), 10.0)
	eq(small.size(), 1, "small overlap yields one erase range")
	if not small.is_empty():
		ok(small[0].x > 0.2 and small[0].y < 0.8, "small overlap does not erase the whole path")
	var far := Preview3D.path_erase_ranges(line, Vector2(50, 200), Vector2(50, 200), 10.0)
	eq(far.size(), 0, "far mouse erases nothing")
	var swept := Preview3D.path_erase_ranges(line, Vector2(30, -20), Vector2(70, 20), 8.0)
	eq(swept.size(), 1, "mouse sweep across the path erases a range")
	var loop := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100),
		Vector2(0, 100), Vector2(0, 50), Vector2(0, 0),
	])
	var overlapping := Preview3D.path_erase_ranges(loop, Vector2(0, 0), Vector2(0, 0), 8.0)
	eq(overlapping.size(), 2, "overlapping passes are erased separately, not as one huge span")
	if overlapping.size() == 2:
		ok(overlapping[0].x < 0.01 and overlapping[1].y > 0.99, "both overlapping passes are covered")
	return true


func test_path_erase_merge() -> bool:
	var local := Preview3D.merge_erase_ranges([], 0.47, 0.53)
	eq(local.size(), 1, "local touch creates one gap")
	if not local.is_empty():
		ok(float(local[0]["from"]) > 0.4, "local touch does not erase from the head")
	var followed := Preview3D.merge_erase_ranges(local, 0.51, 0.60)
	eq(followed.size(), 1, "following merges into one continuous gap")
	var separate := Preview3D.merge_erase_ranges(followed, 0.85, 0.90)
	eq(separate.size(), 2, "far touch stays a separate gap")
	var head := Preview3D.merge_erase_ranges([], 0.02, 0.10)
	eq(head.size(), 1, "head touch creates one gap")
	if not head.is_empty():
		near(float(head[0]["from"]), 0.0, 0.001, "head touch starts at the head")
	return true


func test_path_run_split() -> bool:
	var long_line := PackedVector2Array([
		Vector2(0, 0), Vector2(500, 0), Vector2(1000, 0), Vector2(1500, 0),
	])
	var none: Array[bool] = [false, false, false, false]
	var continuous := Preview3D.split_path_runs(long_line, none)
	eq(continuous.size(), 1, "long path is not split by pixel distance")
	if continuous.size() == 1:
		eq(continuous[0].size(), 4, "long path keeps every sample")
	var middle_line := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(200, 0),
		Vector2(300, 0), Vector2(400, 0), Vector2(500, 0),
	])
	var middle: Array[bool] = [false, false, true, true, false, false]
	var split := Preview3D.split_path_runs(middle_line, middle)
	eq(split.size(), 2, "erased middle splits into two visible runs")
	var gap := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF),
		Vector2(20, 0), Vector2(30, 0),
	])
	var gap_flags: Array[bool] = [false, false, false, false, false]
	eq(Preview3D.split_path_runs(gap, gap_flags).size(), 2, "invalid sample starts a new run")
	return true


func test_style_presets() -> bool:
	var skins := Preview3D.skin_presets()
	for key in ["candy", "neon", "glass", "sticker"]:
		ok(skins.has(key), "skin preset %s exists" % key)
		if skins.has(key):
			ok(float(skins[key].get("scale", 0.0)) > 1.0, "skin %s enlarges notes" % key)
	var effects := Preview3D.hit_fx_presets()
	for key in ["burst", "ring", "prism", "ink"]:
		ok(effects.has(key), "hit effect %s exists" % key)
	eq(Preview3D.tier_fx_scale("PERFECT"), 1.0, "a PERFECT keeps the full hit effect")
	ok(Preview3D.tier_fx_scale("BAD") < Preview3D.tier_fx_scale("GOOD"), "a BAD hit draws a smaller effect")
	eq(Preview3D.tier_fx_scale("MISS"), 1.0, "a MISS keeps the full hit effect")
	var cursor := Preview3D.new()
	near(cursor.cursor_scale, 1.0, 0.0001, "cursor scale defaults to 1x")
	cursor.free()
	ok(Playtest.PATH_TAIL_RADIUS >= 180.0, "path tail judgement is forgiving")
	ok(Playtest.TRACE_CONTACT_PX >= 50.0, "trace contact is forgiving")
	ok(Playtest.BELL_COLLECT_RADIUS >= 64.0 and Playtest.BELL_COLLECT_RADIUS <= 96.0, "bell collect stays tight but forgiving")
	ok(Preview3D.BELL_SNAP_RANGE <= Playtest.BELL_COLLECT_RADIUS, "bell snap never reaches farther than collect")
	eq(Playtest.PERFECT_MS, 65.0, "perfect window tightened")
	eq(Playtest.GREAT_MS, 115.0, "great window tightened")
	eq(Playtest.GOOD_MS, 170.0, "good window tightened")
	eq(Playtest.POSITION_TOLERANCE_PX, 120.0, "one head tolerance for every note type")
	eq(Playtest.EARLY_MS, 115.0, "early presses stop at the GREAT boundary")
	ok(Playtest.PRESS_KEEP_MS < 100.0, "a press only lives for about one frame")
	eq(Playtest.KEY_DEBOUNCE_MS, 50.0, "the same key is debounced for 50ms")
	ok(Playtest.EARLY_MS < Playtest.HIT_WINDOW_MS, "early presses are stricter than late ones")
	eq(Playtest.PATH_TAIL_SWEEP_EARLY_MS, 220.0, "finishing a slide early stops at the GOOD window")
	ok(Playtest.HOLD_RELEASE_GRACE_MS >= 100.0 and Playtest.HOLD_RELEASE_GRACE_MS <= 260.0,
		"the hold release grace is long enough to re-press")
	ok(Playtest.hold_release_grace_alive(1000.0, 1000.0 + Playtest.HOLD_RELEASE_GRACE_MS - 1.0),
		"a slip inside the grace keeps the hold alive")
	ok(not Playtest.hold_release_grace_alive(1000.0, 1000.0 + Playtest.HOLD_RELEASE_GRACE_MS),
		"a release past the grace ends the hold")
	near(Preview3D.end_fade_beats(120.0), 0.2, 0.0001, "0.1s of exit fade is 0.2 beats at 120 BPM")
	eq(Playtest.BAD_MS, 250.0, "bad tier extends to 250ms")
	return true


func test_timing_stats() -> bool:
	var run := Playtest.new()
	for error in [-10.0, -10.0, 10.0, 10.0]:
		run._record_error(error, "test")
	eq(run._mean_error(), 0.0, "mean timing error")
	ok(absf(run._unstable_rate() - 115.47) < 0.1, "unstable rate is stddev x10")
	run.free()
	var tiers := Playtest.new()
	eq(tiers._tier_for(150.0), "GOOD", "good tier stays at 170ms")
	eq(tiers._tier_for(200.0), "BAD", "200ms late lands in the bad tier")
	eq(tiers._tier_for(260.0), "MISS", "beyond 250ms is a miss")
	tiers.free()
	eq(Playtest.DYNAMIC_SAMPLE_MIN, 8, "dynamic offset waits for 8 hits")
	eq(Playtest.DYNAMIC_LIMIT_MS, 50.0, "dynamic offset is capped at 50ms")
	return true


func test_position_judgement() -> bool:
	var run := Playtest.new()
	var line := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	eq(run._distance_to_polyline(Vector2(50, 30), line), 30.0, "distance to a band segment")
	eq(run._distance_to_polyline(Vector2(130, 0), line), 30.0, "distance past the band end")
	eq(run._distance_to_polyline(Vector2(10, 20), PackedVector2Array([Vector2(10, 0)])), 20.0, "distance to a point note")
	# 早按只认 EARLY_MS：更早的按键不进判定，避免乱按把后面的音符打掉。
	eq(Playtest.HIT_WINDOW_MS, Playtest.BAD_MS, "late presses keep the BAD window")
	eq(run._tier_for(-60.0), "PERFECT", "a 60ms early press is PERFECT")
	eq(run._tier_for(-115.0), "GREAT", "the earliest accepted press is GREAT")
	eq(run._tier_for(-260.0), "MISS", "a 260ms early press is outside the window")
	run.free()
	return true


## 就近分配：多个按键同时在窗口里时，选离图形最近的，而不是时间最近的。
func test_press_assignment() -> bool:
	var run := Playtest.new()
	var line := PackedVector2Array([Vector2(48, 0), Vector2(52, 0)])
	run._key_presses = [
		{"time": 1000.0, "mouse": Vector2(0, 0)},
		{"time": 1012.0, "mouse": Vector2(50, 0)},
	]
	var picked := run._take_key_near(990.0, 1020.0, line, 10.0, 1000.0)
	eq(float(picked.get("time", -1.0)), 1012.0, "the press aimed at the shape wins over the earlier one")
	run._key_presses = [
		{"time": 1000.0, "angle": 20.0, "mouse": Vector2.ZERO},
		{"time": 1012.0, "angle": 89.0, "mouse": Vector2.ZERO},
	]
	var sector := run._take_key_for_sector(990.0, 1020.0, 88.0, 160.0, 1000.0)
	eq(float(sector.get("time", -1.0)), 1012.0, "the press nearest the sector centre wins")
	run._key_presses = [
		{"time": 1000.0, "mouse": Vector2(0, 0)},
		{"time": 1012.0, "mouse": Vector2(100, 0)},
	]
	var point := run._take_key_for_point(990.0, 1020.0, Vector2(100, 0), 120.0, 1000.0)
	eq(float(point.get("time", -1.0)), 1012.0, "the press nearest the point wins")
	# 光标在圈心/屏幕角落时按下的键没有方向意图，密集段不该吃它。
	run._key_presses = [{"time": 1000.0, "angle": 88.0, "valid": false}]
	ok(run._take_key_for_sector(990.0, 1010.0, 88.0, 100.0, 1000.0).is_empty(),
		"a press made off the ring cannot take a dense sector")
	run._key_presses = [{"time": 1000.0, "angle": 88.0, "valid": true}]
	ok(not run._take_key_for_sector(990.0, 1010.0, 88.0, 100.0, 1000.0).is_empty(),
		"a press made on the ring takes the sector")
	run.free()
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


func test_bar_lines() -> bool:
	var timing := TimingMap.new()
	eq(Preview3D.bar_line_beats(timing, 1.0, 8.0), [4.0, 8.0], "bar lines appear once per 4/4 measure")
	eq(Preview3D.bar_line_beats(timing, 4.0, 1.0), [4.0], "bar line reaches boundary on downbeat")
	eq(Preview3D.bar_line_beats(timing, 4.01, 1.0), [], "bar line disappears after downbeat")
	eq(Preview3D.bar_line_beats(timing, -2.0, 4.0), [0.0], "count-in includes first measure")
	eq(Preview3D.bar_line_beats(timing, 1.0, 0.0), [], "zero pre-read produces no bar lines")
	timing.points.append(TimingPoint.new(8.0, 180.0, 3))
	eq(Preview3D.bar_line_beats(timing, 4.0, 8.0), [4.0, 9.0, 12.0], "meter change matches timeline bar grid")
	return true


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
	# 普通 Tap 现在只有 0.5 l；这里用 1.0 l 的大小 Tap 保持 120° 的命中弧。
	a.set_size_ratio(1.0)
	var b := Note.new("tap", 0.0, 90.0, 120.0)
	b.id = 2
	b.set_size_ratio(1.0)
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
	ok(MediaIO.is_supported_audio("a.flac"), "flac is accepted through the decode cache")
	ok(not MediaIO.is_native_audio("a.flac"), "flac is not a native stream class")
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
	ok(absf(tap.width - 60.0) < 0.001, "osu tap uses a fixed 60° width")
	var slide: Note = chart.notes[1]
	eq(slide.type, "hold", "short osu slider falls back to Hold (Sentakki rule)")
	eq(slide.space, "ring", "hold stays on the ring")
	near(slide.beat, 4.0, 0.001, "osu slider beat")
	near(slide.end_beat, 4.7142857, 0.001, "osu slider duration")
	var restored := Note.from_dict(slide.to_dict())
	eq(restored.type, "hold", "hold survives json")
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
	eq(chart.notes[0].hold_style, "straight", "short slider hold is straight")
	eq(chart.notes[1].type, "path", "repeat slider -> sentakki slide")
	ok(chart.notes[1].end_beat > chart.notes[1].beat, "repeat slider slide has duration")
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
	near(chart.notes[0].angle, 67.5, 0.001, "std first note keeps the visual top angle")
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


func test_osu_std_chain_no_conflict() -> bool:
	# 四条首尾相接的滑条（2 拍一条，后一条正好落在前一条的尾判定拍上）。
	# 之前的转换器会让下一条星头和上一条尾判定点落在不相交的角度上，
	# 校验报“同刻目标没有公共角度”，试玩直接被拦住。
	var text := """osu file format v14

[General]
Mode: 0

[Metadata]
Title: Chain
Artist: A
Creator: C
Version: H

[Difficulty]
SliderMultiplier: 1.4
CircleSize: 4

[TimingPoints]
0,200,4,2,0,100,1,0

[HitObjects]
160,96,0,2,0,P|96:192|160:288,1,280
352,96,400,2,0,P|416:192|352:288,1,280
160,352,800,2,0,P|224:192|160:288,1,280
352,352,1200,2,0,P|288:192|352:288,1,280
256,192,1600,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "chain.osu")
	ok(not result.is_empty(), "osu std chain parsed")
	if result.is_empty():
		return false
	var chart: Chart = result["chart"]
	var errors := Validator.errors(Validator.validate(chart))
	eq(errors.size(), 0, "osu std chain has no validation errors")
	for issue in errors:
		print("  chain issue: ", issue.get("message"))
	return true


func test_note_span_defaults() -> bool:
	# 单点音符的 end_beat 必须等于自身 beat；默认 0 会让判定把它当成“0ms 就结束”，
	# 谱面播到 6 秒后所有 Tap 都被当作过期跳过（历史上“突然没判定”的根因）。
	var tap := Note.new("tap", 7.5, 90.0, 60.0)
	near(tap.end_beat, 7.5, 0.001, "tap end_beat defaults to its own beat")
	near(tap.duration(), 0.0, 0.001, "tap has zero duration")
	var hold := Note.new("hold", 2.0, 0.0, 60.0)
	near(hold.end_beat, 2.0, 0.001, "hold end_beat starts at its beat")
	hold.end_beat = 4.5
	near(hold.duration(), 2.5, 0.001, "hold duration uses explicit end_beat")
	return true


func test_judgement_text_font() -> bool:
	# 判定提示里的“早/晚”必须用含中文的字体：等宽字体缺中文字形，
	# 每个不同的提示串都会触发一次系统字体回退（单次 ~18ms），判定密集时卡顿。
	var regular := UITheme.FONT_REGULAR
	var mono := UITheme.FONT_MONO
	ok(regular.has_char("早".unicode_at(0)), "judgement detail font has CJK glyphs")
	ok(not mono.has_char("早".unicode_at(0)), "mono font still lacks CJK (do not use it for judgement text)")
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


func test_note_mirror() -> bool:
	var tap := Note.new("tap", 2.0, 90.0, 60.0)
	tap.mirror_u()
	near(tap.angle, 270.0, 0.001, "mirror tap angle")
	near(tap.beat, 2.0, 0.001, "mirror keeps beat")
	var wrap := Note.new("tap", 2.0, 270.0, 60.0)
	wrap.mirror_u()
	near(wrap.angle, 90.0, 0.001, "mirror wraps past 360")
	var bell := Note.new("bell", 4.0, 0.0, 0.0)
	bell.center_u = 0.25
	bell.mirror_u()
	near(bell.center_u, 0.75, 0.001, "mirror bell center_u")
	var path := Note.new("path", 1.0, 30.0, 60.0)
	path.tail_angle = 60.0
	path.trace_pts = [{"x": 0.2, "y": 0.3, "db": 0.0}, {"x": 0.8, "y": 0.6, "db": 1.0}]
	path.visual_pts = [{"db": 0.5, "da": 15.0}]
	path.mirror_u()
	near(path.angle, 210.0, 0.001, "mirror path head")
	near(path.tail_angle, 240.0, 0.001, "mirror path tail")
	near(float(path.trace_pts[0]["x"]), -0.2, 0.001, "mirror path trace x")
	near(float(path.trace_pts[0]["y"]), -0.3, 0.001, "mirror path trace y")
	near(float(path.visual_pts[0]["da"]), 15.0, 0.001, "mirror path visual delta stays relative")
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
	var text := "&title=Simai Test\n&artist=Tester\n&first=1\n&wholebpm=120\n&lv_1=5\n&des_1=me\n&inote_1=(120){4}\n1,2h[4:1],1-5[4:1],,,E1,\nE\n"
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
	eq(chart.notes[1].hold_style, "straight", "simai hold imports straight")
	eq(Validator.errors(Validator.validate(chart)).size(), 0, "simai import is playable without double-hand conflicts")
	if chart.notes.size() >= 3:
		near(chart.notes[0].angle, 90.0, 0.001, "simai button 1 is top")
		near(chart.notes[2].wait_beat, 1.0, 0.001, "maimai star waits one beat after the head tap")
		near(chart.notes[2].end_beat, 4.0, 0.001, "slide tail is head + 1 beat wait + slide length")
		var trace: Array = chart.notes[2].trace_pts
		ok(trace.size() >= 3, "slide trace has samples")
		if trace.size() >= 2:
			var head := Vector2(float(trace[0]["x"]), float(trace[0]["y"]))
			var held := Vector2(float(trace[1]["x"]), float(trace[1]["y"]))
			near(float(trace[1]["db"]), 1.0, 0.001, "trace keeps the star at the head for the wait beat")
			ok(held.distance_to(head) < 0.001, "star is parked during the wait beat")
		near(chart.notes[2].tail_angle, 270.0, 0.001, "simai slide tail button 5")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_simai_osu_friendly() -> bool:
	# 300BPM 的 1 拍 = 200ms；180° p 型星星弧太长，超速时必须压短轨迹，
	# 但形状仍然是 p，不再被拉成直线。
	var text := "&title=T\n&wholebpm=120\n&lv_1=1\n&inote_1=(300){4},1p5[4:1],,,,\nE\n"
	var path := "user://test_simai_friendly.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "simai friendly fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 1)
	ok(chart != null, "simai friendly chart imports")
	if chart != null and not chart.notes.is_empty():
		var note: Note = chart.notes[0]
		eq(note.type, "path", "short p slide still imports")
		ok(not ConvertOptimizer._trace_bad(note, chart), "over-fast star is compressed under the speed cap")
		ok(ConvertOptimizer._trace_length(note.trace_pts) < 2.4, "compressed star is shorter than the full p arc")
		var head := Vector2(float(note.trace_pts[0]["x"]), float(note.trace_pts[0]["y"]))
		var tail := Vector2(float(note.trace_pts[-1]["x"]), float(note.trace_pts[-1]["y"]))
		var max_deviation := 0.0
		for point in note.trace_pts:
			var p := Vector2(float(point["x"]), float(point["y"]))
			var q := clampf((p - head).dot(tail - head) / maxf(0.0001, (tail - head).length_squared()), 0.0, 1.0)
			max_deviation = maxf(max_deviation, p.distance_to(head.lerp(tail, q)))
		ok(max_deviation > 0.02, "compressed star keeps its p shape")
	var loop: Array[Vector2] = [
		Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1),
	]
	ok(SimaiIO._polyline_self_intersects(loop), "self-intersecting star is detected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_simai_dense_relax() -> bool:
	# 高 BPM + 高密度 + 大跳：导入后相邻 Tap 的角位移必须被压到 45° 以内。
	var text := "&title=Dense\n&artist=T\n&wholebpm=200\n&lv_1=12\n&inote_1=\n(200){16}1,5,2,6,3,7,4,8,\n"
	var path := "user://test_simai_dense.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "dense fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 0)
	ok(chart != null, "dense chart imports")
	if chart == null:
		return true
	var taps: Array[Note] = []
	for note in chart.notes:
		if note.type == "tap":
			taps.append(note)
	eq(taps.size(), 8, "dense run imports eight taps")
	var largest := 0.0
	for i in range(1, taps.size()):
		largest = maxf(largest, absf(JudgeMath.angle_delta(taps[i].angle, taps[i - 1].angle)))
	ok(largest <= 45.01, "dense run never jumps more than 45 degrees (got %.1f)" % largest)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_simai_relax_keeps_slow() -> bool:
	# 低 BPM / 慢速段落：鼠标跟得上，导入后角度必须原样保留。
	var text := "&title=Slow\n&artist=T\n&wholebpm=120\n&lv_1=8\n&inote_1=\n(120){4}1,2,3,4,\n"
	var path := "user://test_simai_slow.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "slow fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 0)
	ok(chart != null, "slow chart imports")
	if chart == null:
		return true
	var taps: Array[Note] = []
	for note in chart.notes:
		if note.type == "tap":
			taps.append(note)
	eq(taps.size(), 4, "slow run imports four taps")
	if taps.size() >= 4:
		for i in range(1, taps.size()):
			near(absf(JudgeMath.angle_delta(taps[i].angle, taps[i - 1].angle)), 45.0, 0.01, "slow run keeps its 45° steps")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true
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
	var text := "&title=T\n&wholebpm=120\n&lv_1=1\n&inote_1=(120){4},1v5[4:1],,,,,1p3[4:1],,,,,1q3[4:1],\nE\n"
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
		var paths: Array[Note] = []
		for note in chart.notes:
			if note.type == "path":
				paths.append(note)
		eq(paths.size(), 3, "v/p/q all import as paths")
		if paths.size() == 3:
			for note in paths:
				var tail: Dictionary = note.trace_pts[-1]
				near(sqrt(pow(float(tail["x"]), 2) + pow(float(tail["y"]), 2)), 1.0, 0.01, "star tail lands on the ring")
			var min_radius := 1.0
			for point in paths[0].trace_pts:
				min_radius = minf(min_radius, sqrt(pow(float(point["x"]), 2) + pow(float(point["y"]), 2)))
			ok(min_radius < 0.15, "v shape passes through the center")
			# p/q 是绕中心的旋转镜像：有向面积必须反号（不是简单的弦两侧）。
			var area_p := 0.0
			var area_q := 0.0
			for i in paths[1].trace_pts.size() - 1:
				var a := Vector2(float(paths[1].trace_pts[i]["x"]), float(paths[1].trace_pts[i]["y"]))
				var b := Vector2(float(paths[1].trace_pts[i + 1]["x"]), float(paths[1].trace_pts[i + 1]["y"]))
				area_p += a.cross(b)
			for i in paths[2].trace_pts.size() - 1:
				var a := Vector2(float(paths[2].trace_pts[i]["x"]), float(paths[2].trace_pts[i]["y"]))
				var b := Vector2(float(paths[2].trace_pts[i + 1]["x"]), float(paths[2].trace_pts[i + 1]["y"]))
				area_q += a.cross(b)
			ok(signf(area_p) != signf(area_q), "p and q wind around the center in opposite directions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_note_length_system() -> bool:
	# 长度体系：l = note.width；普通 Tap / Hold 头 = 0.5 l，大小 Tap = ratio × l。
	var tap := Note.new("tap", 0.0, 0.0, 60.0)
	near(tap.arc_width(), 30.0, 0.0001, "normal tap is 0.5 l")
	near(tap.length_ratio(), 0.5, 0.0001, "normal tap ratio is 0.5")
	tap.set_size_ratio(0.0)
	near(tap.arc_width(), 0.0, 0.0001, "sized tap can be 0 l")
	tap.set_size_ratio(1.5)
	near(tap.arc_width(), 90.0, 0.0001, "sized tap can reach 1.5 l")
	tap.set_size_ratio(0.735)
	near(tap.size_ratio, 0.74, 0.0001, "sized tap snaps to two decimals")
	near(tap.arc_width(), 44.4, 0.001, "sized tap length follows the ratio")
	var hold := Note.new("hold", 0.0, 0.0, 60.0)
	near(hold.arc_width(), 30.0, 0.0001, "hold head is 0.5 l")
	near(hold.length_ratio(), 0.5, 0.0001, "hold ignores the sized flag")
	var path := Note.new("path", 0.0, 0.0, 60.0)
	near(path.arc_width(), 60.0, 0.0001, "path keeps its head width")
	near(Note.SPAWN_LENGTH_RATIO, 1.0 / 6.0, 0.000001, "spawn length is 1/6 l")
	# 序列化：只有大小 Tap 写 sized/size，普通 Tap 不写。
	var sized := Note.new("tap", 1.0, 45.0, 60.0)
	sized.set_size_ratio(0.75)
	var data := sized.to_dict()
	ok(bool(data.get("sized", false)), "sized tap persists the flag")
	near(float(data.get("size", 0.0)), 0.75, 0.001, "sized tap persists the ratio")
	var loaded := Note.from_dict(data)
	ok(loaded.sized, "sized tap roundtrips the flag")
	near(loaded.arc_width(), 45.0, 0.001, "sized tap roundtrips the length")
	var plain := Note.new("tap", 2.0, 0.0, 60.0)
	ok(not plain.to_dict().has("sized"), "plain tap writes no size fields")
	return true


func test_osu_std_lanes() -> bool:
	# 落道照 Sentakki：角度只能落在 8 个 45° 道上。
	var text := """osu file format v14

[General]
AudioFilename: a.mp3
Mode: 0

[Metadata]
Title: Lane
Version: Test

[Difficulty]
CircleSize: 4
ApproachRate: 5
SliderMultiplier: 1.4

[TimingPoints]
0,500,4,2,0,100,1,0

[HitObjects]
128,192,1000,1,0,0:0:0:0:
256,192,1500,1,0,0:0:0:0:
384,192,2000,1,0,0:0:0:0:
256,64,2500,1,0,0:0:0:0:
64,64,3000,1,0,0:0:0:0:
"""
	var result := OsuIO.parse_osu(text, "lane.osu")
	ok(result.get("chart") != null, "lane chart imports")
	var chart: Chart = result.get("chart")
	if chart == null:
		return true
	var lanes: Array[int] = []
	for note in chart.notes:
		var lane := posmod(roundi((90.0 - note.angle - 22.5) / 45.0), 8)
		near(note.angle, fposmod(90.0 - (22.5 + float(lane) * 45.0), 360.0), 0.001, "std angle snaps to a Sentakki lane")
		lanes.append(lane)
	eq(lanes.size(), 5, "five circles import")
	if lanes.size() == 5:
		eq(lanes[0], 5, "left circle lands on Sentakki lane 5")
		eq(lanes[1], 1, "center circle follows the stream to lane 1")
		eq(lanes[2], 1, "right circle stays on lane 1")
		eq(lanes[3], 6, "top circle jumps to lane 6")
		eq(lanes[4], 4, "top-left circle jumps to lane 4")
	return true


func test_path_custom_color() -> bool:
	var path := Note.new("path", 1.0, 0.0, 60.0)
	ok(not path.to_dict().has("rgb"), "default path writes no rgb")
	path.has_custom_color = true
	path.custom_color = Color(1.0, 0.5, 0.0)
	var data := path.to_dict()
	ok(data.has("rgb"), "custom color is serialised")
	eq(int(data["rgb"][0]), 255, "red channel written")
	eq(int(data["rgb"][1]), 128, "green channel written")
	var loaded := Note.from_dict(data)
	ok(loaded.has_custom_color, "custom color roundtrips")
	near(loaded.custom_color.r, 1.0, 0.01, "red survives")
	near(loaded.custom_color.g, 128.0 / 255.0, 0.01, "green survives")
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


func test_sentakki_slide_library() -> bool:
	var parts := SentakkiSlide.valid_parts(false)
	ok(parts.size() > 20, "sentakki slide library has usable parts")
	var straight: Dictionary = {}
	for part in parts:
		if String(part["shape"]) == "straight" and int(part["lanes"]) == 3 and not bool(part["mirrored"]):
			straight = part
			break
	ok(not straight.is_empty(), "sentakki straight 3 exists")
	if not straight.is_empty():
		near(float(straight["min_ms"]), 109.6, 8.0, "sentakki straight 3 min duration")
		var trace := SentakkiSlide.trace_from_parts(90.0, [straight], 2.0, 0.5)
		ok(trace.size() >= 12, "sentakki trace is densified")
		var first := Vector2(float(trace[0]["x"]), float(trace[0]["y"]))
		near(first.distance_to(Vector2(cos(deg_to_rad(90.0)), sin(deg_to_rad(90.0)))), 0.0, 0.01, "sentakki trace starts at the head")
		var last := Vector2(float(trace[-1]["x"]), float(trace[-1]["y"]))
		var expected := Vector2(cos(deg_to_rad(90.0 - 3.0 * 45.0)), sin(deg_to_rad(90.0 - 3.0 * 45.0)))
		near(last.distance_to(expected), 0.0, 0.01, "sentakki trace ends at the relative end lane")
	var short_parts := SentakkiSlide.valid_parts(true)
	var has_short := false
	for part in short_parts:
		if String(part["shape"]) == "straight" and int(part["lanes"]) == 1:
			has_short = true
			break
	ok(has_short, "maimai allows a one-lane straight")
	return true


func test_editor_tabs() -> bool:
	# 标签页文档状态机：新建 / 切换 / 关闭都要保住各自的谱面与脏标记。
	var app = load("res://charter/app.gd").new()
	app.name = "TabTestApp"
	root.add_child(app)
	var a := DemoChart.make_empty({"bpm": 120.0})
	var b := DemoChart.make_empty({"bpm": 150.0})
	app.set_chart(a, "a.json", false)
	app.ensure_tab()
	eq(app.tabs.size(), 1, "first document opens one tab")
	app.set_chart(b, "b.json", true)
	app.add_tab_from_current("B")
	eq(app.tabs.size(), 2, "the second document opens a new tab")
	eq(app.active_tab, 1, "the new tab becomes active")
	app.activate_tab(0)
	ok(app.chart == a and not app.dirty, "switching back restores the first document")
	app.activate_tab(1)
	ok(app.chart == b and app.dirty, "switching forward restores the second document")
	app.close_tab(1)
	eq(app.tabs.size(), 1, "closing removes that tab")
	ok(app.chart == a, "closing the active tab falls back to the other one")
	app.queue_free()
	return true


func test_convert_optimizer_fast_path() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 240.0, 4)]
	var note := Note.new("path", 0.0, 90.0, 62.0)
	# 0.5 拍 @240BPM = 125ms：先被“压短轨迹”，再被滑条底线降级，两段都要测。
	note.end_beat = 0.5
	note.wait_beat = 0.0
	note.tail_angle = 270.0
	note.tail_width = 52.0
	note.space = "plane"
	note.trace_pts = _straight_trace(90.0, 270.0, 0.5, 9)
	chart.notes = [note]
	var counts := {"tap": 0, "hold": 0, "path": 1, "bell": 0, "dropped": 0}
	var stats := {"dropped": 0, "relaxed": 0, "rebuilt": 0, "degraded": 0, "bells_moved": 0}
	ok(ConvertOptimizer._fit_speed(note, chart), "fast path can be shortened")
	ok(not ConvertOptimizer._trace_bad(note, chart), "shortened trace stays under the speed cap")
	ok(note.trace_pts.size() >= 2, "shortened path keeps samples")
	# 125ms 仍然低于 MIN_SLIDE_MS：底线把它降级成 Hold。
	ConvertOptimizer.enforce_slide_floor(chart, counts, stats)
	ok(note.type != "path", "a 125ms slide is degraded by the floor")
	eq(int(stats["degraded"]), 1, "the floor reports one degradation")
	return true


func test_ring_sector_and_tail_tier() -> bool:
	# 8 分区边界在 22.5° + 45°k，和 8 个按键对齐。
	eq(Preview3D.ring_sector(0.0), 0, "sector 0 centred on up")
	eq(Preview3D.ring_sector(22.4), 0, "just before the boundary stays in sector 0")
	eq(Preview3D.ring_sector(22.6), 1, "just after the boundary moves to sector 1")
	eq(Preview3D.ring_sector(90.0), 2, "sector 2 centred on right")
	eq(Preview3D.ring_sector(337.6), 0, "wrap-around closes back into sector 0")
	# 星尾独立档位：PERFECT ±80 / GREAT ±140 / GOOD ±220。
	eq(Playtest.tail_tier(-79.0), "PERFECT", "tail within 80ms is perfect")
	eq(Playtest.tail_tier(81.0), "GREAT", "tail 81ms is great")
	eq(Playtest.tail_tier(-141.0), "GOOD", "tail 141ms is good")
	eq(Playtest.tail_tier(221.0), "BAD", "tail 221ms is bad")
	return true


func test_path_sector_erase() -> bool:
	var note := Note.new("path", 0.0, 90.0, 62.0)
	note.end_beat = 2.0
	note.space = "plane"
	var points: Array[Dictionary] = []
	for i in 9:
		var angle := deg_to_rad(90.0 - float(i) * 11.25)
		points.append({"x": cos(angle), "y": sin(angle), "db": float(i) * 0.25})
	note.trace_pts = points
	var preview := Preview3D.new()
	var ranges := preview.path_sector_ranges(note)
	eq(ranges.size(), 3, "trail crosses three 45-degree sectors")
	preview.cut_path_sector(note, 1)
	ok(preview.path_erased(note, 1.0), "sector erase removes the middle of the trail")
	ok(not preview.path_erased(note, 0.1), "head 10 percent stays visible")
	ok(not preview.path_erased(note, 1.9), "tail 15 percent stays visible")
	preview.free()
	return true


func test_simai_bpm_jump_star_speed() -> bool:
	# BPM 在星星滑动途中跳变时，按拍均分的轨迹仍会超速；重建后必须再检查一次。
	var text := "&title=T\n&wholebpm=220\n&lv_1=1\n&inote_1=(220){4}1-5[2:1],,(2020),,,,\nE\n"
	var path := "user://test_simai_bpm_star.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "simai bpm star fixture")
		return true
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 1)
	ok(chart != null, "simai bpm jump chart imports")
	if chart != null:
		var bad := 0
		for note in chart.notes:
			if note.type == "path" and ConvertOptimizer._trace_bad(note, chart):
				bad += 1
		eq(bad, 0, "rebuilt star stays under the trace speed cap across a BPM jump")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func _straight_trace(from_deg: float, to_deg: float, duration: float, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var from := Vector2(cos(deg_to_rad(from_deg)), sin(deg_to_rad(from_deg)))
	var to := Vector2(cos(deg_to_rad(to_deg)), sin(deg_to_rad(to_deg)))
	for i in count:
		var t := float(i) / float(count - 1)
		var point := from.lerp(to, t)
		result.append({"x": point.x, "y": point.y, "db": duration * t})
	return result


## 滑条底线：太短（<180ms）或太小（弦长 <0.6R）的 Path 应该降级。
func test_slide_floor() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var counts := {"tap": 0, "hold": 0, "path": 0, "bell": 0, "dropped": 0}
	# 1) 50ms 的滑条：来不及滑，降级成 Tap。
	var short_time := Note.new("path", 0.0, 0.0, 62.0)
	short_time.end_beat = 0.1
	short_time.space = "plane"
	short_time.trace_pts = _straight_trace(0.0, 90.0, 0.1, 6)
	# 2) 2 拍（1000ms）但弦长只有 0.2R：读不出“要滑”，也降级。
	var tiny := Note.new("path", 2.0, 0.0, 62.0)
	tiny.end_beat = 4.0
	tiny.space = "plane"
	for i in 6:
		var t := float(i) / 5.0
		tiny.trace_pts.append({"x": 1.0 - 0.2 * t, "y": 0.05 * t, "db": 2.0 * t})
	# 3) 正常滑条：2 拍 + 弦长 1.4R，必须留下。
	var good := Note.new("path", 6.0, 90.0, 62.0)
	good.end_beat = 8.0
	good.space = "plane"
	good.trace_pts = _straight_trace(90.0, 90.0, 2.0, 9)
	var tail_pt := Vector2(cos(deg_to_rad(-45.0)), sin(deg_to_rad(-45.0)))
	for i in good.trace_pts.size():
		var t := float(i) / float(good.trace_pts.size() - 1)
		var head_pt := Vector2(cos(deg_to_rad(90.0)), sin(deg_to_rad(90.0)))
		var p := head_pt.lerp(tail_pt, t)
		good.trace_pts[i] = {"x": p.x, "y": p.y, "db": 2.0 * t}
	chart.notes = [short_time, tiny, good]
	counts["path"] = 3
	var stats := ConvertOptimizer.optimize_maimai(chart, counts)
	eq(short_time.type, "tap", "50ms slide degrades to a tap")
	eq(tiny.type, "hold", "tiny chord slide degrades to a hold (it still has length)")
	eq(good.type, "path", "a normal slide survives the floor")
	ok(int(stats["degraded"]) >= 2, "the floor reports two degradations")
	return true


## Bell 压在同时段 Path 上、但不在星轨上时会被删掉：一个鼠标没法同时跟滑条又去接铃铛。
func test_bell_path_clearance() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	if chart.get_default_shape() == null:
		return true
	var path := Note.new("path", 2.0, 0.0, 62.0)
	path.end_beat = 4.0
	path.space = "plane"
	path.tail_angle = 90.0
	path.tail_width = 52.0
	path.trace_pts = _straight_trace(0.0, 90.0, 2.0, 9)
	var bell := Note.new("bell", 3.0, 0.0, 0.0)
	bell.center_u = 0.0
	chart.notes = [path, bell]
	var counts := {"tap": 0, "hold": 0, "path": 1, "bell": 1, "dropped": 0}
	var stats := ConvertOptimizer.optimize_maimai(chart, counts)
	ok(not chart.notes.has(bell), "off-track bell during a slide is dropped")
	ok(int(stats.get("off_track", 0)) >= 1, "off-track drop is reported")
	return true


func _import_inote(inote: String) -> Chart:
	var text := "&title=T\n&wholebpm=120\n&first=0\n&lv_1=1\n&inote_1=" + inote + "\nE\n"
	var path := "user://test_tmp_inote.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string(text)
	file.close()
	var chart := SimaiIO.import_maidata(path, 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return chart


func test_simai_same_head_and_chain() -> bool:
	var chart := _import_inote("(120){4}\n1-4[4:1]*-6[4:1],,,,,2,\n")
	ok(chart != null, "same-head chart imports")
	if chart != null:
		var paths: Array[Note] = []
		for note in chart.notes:
			if note.type == "path":
				paths.append(note)
		eq(paths.size(), 1, "same-head group keeps one track")
		if paths.size() == 1:
			near(paths[0].tail_angle, 315.0, 0.01, "same-head keeps the tail nearest the next note")
	var chain := _import_inote("(120){4}\n1-4q7-2[4:2],\n")
	ok(chain != null, "chain chart imports")
	if chain != null:
		var paths: Array[Note] = []
		for note in chain.notes:
			if note.type == "path":
				paths.append(note)
		eq(paths.size(), 1, "chain is one path")
		if paths.size() == 1:
			near(paths[0].tail_angle, 45.0, 0.01, "chain ends on its final button")
			near(paths[0].end_beat, 3.0, 0.01, "chain uses the final duration")
	return true


func test_simai_touch_layers() -> bool:
	var chart := _import_inote("(120){4}\nA1,B1,C,D1,E1,\n")
	ok(chart != null, "touch chart imports")
	if chart == null:
		return true
	var bells: Array[Note] = []
	for note in chart.notes:
		if note.type == "bell":
			bells.append(note)
	eq(bells.size(), 5, "five touch zones import")
	if bells.size() == 5:
		near(bells[0].bell_radius, 1.0, 0.001, "A is on the outer ring")
		near(bells[1].bell_radius, 1.0, 0.001, "B joins the outer ring for mouse sweeps")
		near(bells[2].bell_radius, 0.0, 0.001, "C is the center")
		near(bells[3].bell_radius, 1.0, 0.001, "D is on the outer gap")
		near(bells[4].bell_radius, 1.0, 0.001, "E joins the outer ring for mouse sweeps")
		near(bells[0].angle, 90.0, 0.01, "A1 sits on button 1")
		near(bells[3].angle, 67.5, 0.01, "D1 sits between button 1 and 2")
		var restored := Note.from_dict(bells[2].to_dict())
		near(restored.bell_radius, 0.0, 0.001, "center bell radius roundtrips")
	return true


func test_simai_seconds_slot() -> bool:
	var chart := _import_inote("(120){#0.25}1,2,3,\n")
	ok(chart != null, "seconds slot chart imports")
	if chart != null:
		var taps: Array[Note] = []
		for note in chart.notes:
			if note.type == "tap":
				taps.append(note)
		eq(taps.size(), 3, "seconds slot keeps three taps")
		if taps.size() == 3:
			near(taps[1].beat, 0.5, 0.001, "0.25s at 120BPM is half a beat")
			near(taps[2].beat, 1.0, 0.001, "seconds slot advances the grid")
	return true


func test_maimai_overlap_and_off_track() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var first := Note.new("path", 0.0, 90.0, 62.0)
	first.end_beat = 4.0
	first.wait_beat = 1.0
	first.space = "plane"
	first.tail_angle = 270.0
	first.trace_pts = _straight_trace(90.0, 270.0, 4.0, 12)
	var second := Note.new("path", 2.0, 90.0, 62.0)
	second.end_beat = 5.0
	second.wait_beat = 1.0
	second.space = "plane"
	second.tail_angle = 270.0
	second.trace_pts = _straight_trace(90.0, 270.0, 5.0, 12)
	var on_track := Note.new("tap", 3.0, 270.0, 60.0)
	var off_track := Note.new("tap", 3.5, 90.0, 60.0)
	chart.notes = [first, second, on_track, off_track]
	var counts := {"tap": 2, "hold": 0, "path": 2, "bell": 0, "dropped": 0}
	var stats := ConvertOptimizer.optimize_maimai(chart, counts)
	near(first.end_beat, 2.0, 0.001, "early slide is shortened to the next head")
	near(JudgeMath.angle_delta(second.angle, first.tail_angle), 0.0, 0.01, "next head snaps to the previous tail")
	ok(chart.notes.has(on_track), "tap on the slide track survives")
	ok(not chart.notes.has(off_track), "tap off the slide track is dropped")
	ok(int(stats["shortened"]) >= 1 and int(stats["snapped"]) >= 1, "shorten/snap are reported")
	ok(int(stats["off_track"]) >= 1, "off-track removal is reported")
	return true


func test_maimai_interaction_compress() -> bool:
	var slow := Chart.new()
	slow.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	slow.notes = [Note.new("tap", 0.0, 90.0, 60.0), Note.new("tap", 4.0, 270.0, 60.0)]
	ConvertOptimizer.optimize_maimai(slow, {"tap": 2, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	near(slow.notes[1].angle, 270.0, 0.01, "slow 180-degree jump keeps its position")
	var fast := Chart.new()
	fast.timing.points = [TimingPoint.new(0.0, 200.0, 4)]
	var angles := [90.0, 270.0, 90.0, 270.0]
	for i in angles.size():
		fast.notes.append(Note.new("tap", float(i) * 0.25, float(angles[i]), 60.0))
	ConvertOptimizer.optimize_maimai(fast, {"tap": 4, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	var largest := 0.0
	for i in range(1, fast.notes.size()):
		largest = maxf(largest, absf(JudgeMath.angle_delta(fast.notes[i - 1].angle, fast.notes[i].angle)))
	ok(largest <= 45.01, "fast 180-degree interaction is compressed to 45 degrees (got %.1f)" % largest)
	return true


func test_interaction_run_lock() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 180.0, 4)]
	var angles := [90.0, 0.0, 90.0, 0.0, 90.0, 0.0]
	for i in angles.size():
		chart.notes.append(Note.new("tap", float(i) * 0.25, angles[i], 62.0))
	var stats := ConvertOptimizer.optimize_maimai(chart, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(int(stats.get("locked", 0)), 1, "a fast A-B-A-B run is locked as one")
	for i in chart.notes.size():
		var expect := 90.0 if i % 2 == 0 else 45.0
		near(chart.notes[i].angle, expect, 0.01, "locked run note %d" % i)
	var slow := Chart.new()
	slow.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	for i in angles.size():
		slow.notes.append(Note.new("tap", float(i), angles[i], 62.0))
	ConvertOptimizer.optimize_maimai(slow, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	near(slow.notes[1].angle, 0.0, 0.01, "a slow run keeps its 90-degree positions")
	return true


func test_note_pop_scale() -> bool:
	near(Preview3D.note_pop_scale(0.0), 1.0, 0.001, "note pop starts at its own size")
	near(Preview3D.note_pop_scale(Preview3D.NOTE_POP_SEC), Preview3D.NOTE_POP_SCALE, 0.001, "note pop reaches 1.45x")
	near(Preview3D.note_pop_scale(1.0), Preview3D.NOTE_POP_SCALE, 0.001, "note pop clamps after its lifetime")
	return true


func test_maimai_hold_clamp() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var hold := Note.new("hold", 0.0, 90.0, 62.0)
	hold.end_beat = 4.0
	chart.notes = [hold, Note.new("tap", 2.0, 90.0, 60.0)]
	ConvertOptimizer.optimize_maimai(chart, {"tap": 1, "hold": 1, "path": 0, "bell": 0, "dropped": 0})
	near(hold.end_beat, 1.9375, 0.001, "hold is shortened just before the next press")
	var short := Chart.new()
	short.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var tiny := Note.new("hold", 0.0, 90.0, 62.0)
	tiny.end_beat = 4.0
	short.notes = [tiny, Note.new("tap", 0.25, 90.0, 60.0)]
	ConvertOptimizer.optimize_maimai(short, {"tap": 1, "hold": 1, "path": 0, "bell": 0, "dropped": 0})
	eq(tiny.type, "tap", "a hold shorter than half a beat becomes a tap")
	return true


## 判定一出来音符就退场；hold 头命中只收头部，长条继续画。
func test_note_retire_state() -> bool:
	var preview := Preview3D.new()
	root.add_child(preview)
	ok(not Preview3D.note_is_retired(preview.note_state(1)), "an unjudged note keeps drawing")
	preview.set_note_state(1, "hit")
	ok(Preview3D.note_is_retired(preview.note_state(1)), "a hit note is retired")
	preview.set_note_state(2, "holding")
	ok(not Preview3D.note_is_retired(preview.note_state(2)), "a held note keeps its body")
	preview.set_note_state(5, "slip")
	ok(not Preview3D.note_is_retired(preview.note_state(5)), "a slipped hold stays on screen while dimmed")
	preview.set_note_state(3, "miss", 12.0)
	ok(Preview3D.note_is_retired(preview.note_state(3)), "a missed note is retired")
	near(float(preview.note_state_beats.get(3, 0.0)), 12.0, 0.001, "the miss beat drives the hold fade")
	preview.set_note_state(4, "hit", 20.0)
	near(float(preview.note_state_beats.get(4, 0.0)), 20.0, 0.001, "the hit beat drives the hold exit fade")
	preview.clear_note_states()
	eq(preview.note_state(1), "", "clearing drops every state")
	preview.queue_free()
	return true


func test_auto_play() -> bool:
	# AUTO 的按键骨架：时间取判定时间，位置/角度取音符在屏幕上的位置。
	var payload := Playtest.auto_press_payload(2000.0, Vector2(120.0, 80.0), 90.0, Playtest.AUTO_KEY_A)
	near(float(payload["time"]), 2000.0, 0.001, "auto press time is the judgement time")
	near(float(payload["u"]), 0.25, 0.001, "auto press carries the ring u")
	eq(int(payload["key"]), Playtest.AUTO_KEY_A, "auto press carries a key code")
	eq(payload["mouse"], Vector2(120.0, 80.0), "auto press carries the note screen position")
	ok(bool(payload["valid"]), "auto press is a valid input")
	# 到点判断：比判定时间早 lead 就按下，早了不按。
	ok(Playtest.auto_due(2000.0, 1995.0), "auto presses a few ms early")
	ok(not Playtest.auto_due(2000.0, 1900.0), "auto does not press 100ms early")
	# 默认关闭，且切换到 AUTO 前不能用合成光标（INF = 用真鼠标）。
	var run := Playtest.new()
	ok(not run.auto_play, "autoplay is off by default")
	ok(not Vector2.INF.is_finite(), "INF cursor means the real mouse is used")
	run.free()
	ok(Playtest.AUTO_LEAD_MS < Playtest.PERFECT_MS, "auto lead is inside the perfect window")
	ok(Playtest.AUTO_RELEASE_MS > 0.0, "hold releases after the tail, not before")
	return true


## Path 尾判：短滑条的尾判半径必须跟着缩，而且要求真的滑到后段。
## 45° 的滑条头尾直线只有 0.765R，固定 192px 半径会让“刚摸到头”就被判成尾巴（BAD）。
func test_path_tail_judge() -> bool:
	ok(Playtest.PATH_TAIL_RADIUS_RATIO > 0.15 and Playtest.PATH_TAIL_RADIUS_RATIO < 0.75,
		"tail radius shrinks with the slide length")
	ok(Playtest.PATH_TAIL_MIN_FRACTION >= 0.8, "tail wants most of the slide to be covered")
	ok(Playtest.PATH_TAIL_MIN_FRACTION < 1.0, "tail still tolerates a small aiming error")
	var ring := 430.0
	var chord := 2.0 * ring * sin(deg_to_rad(22.5))
	var radius := clampf(minf(Playtest.PATH_TAIL_RADIUS, chord * Playtest.PATH_TAIL_RADIUS_RATIO), 56.0, Playtest.PATH_TAIL_RADIUS)
	ok(radius < chord * 0.5, "short slide tail radius stays under half the chord")
	ok(radius >= 56.0 - 0.01, "tail radius never collapses to nothing")
	# 长滑条（1.5R）仍然保留完整的 192px 容错。
	var long_chord := 1.5 * ring
	var long_radius := clampf(minf(Playtest.PATH_TAIL_RADIUS, long_chord * Playtest.PATH_TAIL_RADIUS_RATIO), 56.0, Playtest.PATH_TAIL_RADIUS)
	near(long_radius, Playtest.PATH_TAIL_RADIUS, 0.01, "long slides keep the full tail radius")
	return true


## 转谱窗口：一个来源里列出所有难度，能切换，且不碰当前窗口的谱面。
func test_import_window_set() -> bool:
	var path := "user://test_import_set.txt"
	var text := "&title=Two&wholebpm=120\n&lv_1=3\n&inote_1=(120){4},1,2,3,4,\n&lv_2=9\n&inote_2=(120){4},1,2,3,4,5,6,7,8,\nE\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ok(false, "import set fixture")
		return true
	file.store_string(text)
	file.close()
	var app = load("res://charter/app.gd").new()
	var ok_open: bool = app.open_import_source(ProjectSettings.globalize_path(path))
	ok(ok_open, "import source opens")
	eq(app.import_kind, "simai", "import source is detected as simai")
	eq(app.import_difficulties.size(), 2, "both difficulties are listed")
	ok(app.chart != null and app.chart.notes.size() > 0, "first difficulty is imported")
	var first_count: int = app.chart.notes.size()
	ok(not app.import_difficulty_label(0).is_empty(), "difficulty label is not empty")
	ok(app.import_difficulty_label(0) != app.import_difficulty_label(1), "labels differ per difficulty")
	ok(app.select_import_difficulty(1), "switching difficulty works")
	ok(app.chart.notes.size() != first_count, "the chart actually changes with the difficulty")
	eq(app.import_index, 1, "selected index is remembered")
	# 难度组：名字列表、复制新增、整套保存。
	eq(app.difficulty_names().size(), 2, "difficulty group has two names")
	ok(app.difficulty_name(0) != app.difficulty_name(1), "difficulty names differ")
	var before_add: int = app.difficulties.size()
	var added: int = app.add_difficulty_copy("我的难度")
	eq(added, before_add, "added difficulty is appended")
	eq(app.difficulties.size(), before_add + 1, "group grows by one")
	eq(app.difficulty_names()[added], "我的难度", "new difficulty keeps its name")
	ok(app.chart != null and app.chart.notes.size() > 0, "new difficulty starts as a copy of the chart")
	ok(app.save_set_file(), "saving the set writes every difficulty")
	var out_dir := "user://test_set_out"
	var written: int = app.save_all_difficulties(out_dir)
	eq(written, app.difficulties.size(), "every difficulty is written to disk")
	# 难度套组：一个文件装下所有难度，重新打开还在。
	ok(not app.set_path.is_empty(), "import writes a .set.json next to the import")
	var reopened: App = load("res://charter/app.gd").new()
	ok(reopened.open_set_file(app.set_path), "set file reopens")
	eq(reopened.difficulties.size(), app.difficulties.size(), "reopened set has every difficulty")
	eq(reopened.difficulty_names()[0], app.difficulty_names()[0], "difficulty names survive the round trip")
	ok(reopened.chart != null and reopened.chart.notes.size() > 0, "reopened set loads its first difficulty")
	ok(reopened.switch_difficulty(1), "reopened set can switch difficulty")
	ok(reopened.chart.notes.size() > 0, "switched difficulty has notes")
	# 静态小工具：命令行参数解析与标签拼装。
	eq(app.import_label("Lv.9", "Song", "me", "std"), "Lv.9  [std]  ·  Song  (me)", "import label format")
	eq(app.import_label("", "", "", ""), "未命名难度", "empty label falls back")
	reopened.free()
	app.free()
	if FileAccess.file_exists(ProjectSettings.globalize_path("user://sets")):
		for file_name in DirAccess.get_files_at(ProjectSettings.globalize_path("user://sets")):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sets").path_join(file_name))
	for file_name in DirAccess.get_files_at(ProjectSettings.globalize_path(out_dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir).path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true
