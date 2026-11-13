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
		"test_seek_and_limit_code",
		"test_note_width_code",
		"test_note_flags_code",
		"test_plane_tap_dropped",
		"test_compact_chart_code",
		"test_path_judgement_label_pos",
		"test_judge_label_geometry",
		"test_note_glyph_geometry",
		"test_note_width_controls",
		"test_path_chain_code",
		"test_path_chain_judgement",
		"test_path_erase_overlap",
		"test_path_erase_merge",
		"test_path_run_split",
		"test_style_presets",
		"test_position_judgement",
		"test_press_assignment",
		"test_press_space_priority",
		"test_timing_stats",
		"test_nearest_u",
		"test_pre_read",
		"test_bar_lines",
		"test_shrink_example",
		"test_event_restore",
		"test_playability_validator",
		"test_media_formats",
		"test_lbp_export",
		"test_note_color_palette",
		"test_note_color_contrast",
		"test_note_color_round_trip",
		"test_note_color_lbp",
		"test_osu_std_import",
		"test_osu_std_curves",
		"test_osu_std_slider_kinds",
		"test_osu_std_negative_shift",
		"test_osu_std_readability",
		"test_osu_std_chain_no_conflict",
		"test_note_span_defaults",
		"test_judgement_text_font",
		"test_playtest_countdown",
		"test_background_layering",
		"test_video_direct_decode",
		"test_osu_browser_alignment",
		"test_hold_stack_alpha",
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
		"test_sweep_runs_to_bells",
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
		"test_small_angle_stack",
		"test_bell_snap_to_press_notes",
		"test_note_pop_scale",
		"test_background_cache",
		"test_maimai_hold_clamp",
		"test_import_window_set",
		"test_bpm_change_approach",
		"test_osu_std_filter",
		"test_chart_browser_helpers",
		"test_path_slide_start",
		"test_hold_seam_interval",
		"test_judge_scatter",
		"test_mouse_button_input",
		"test_osu_star_color",
		"test_osu_filters",
		"test_storyboard_parse",
		"test_storyboard_loops_and_easing",
	"test_storyboard_serialize",
	"test_storyboard_editor_model",
		"test_storyboard_layers",
		"test_osu_pill_rows",
		"test_path_chevron_spacing",
		"test_audio_clock",
		"test_audio_clock_rate",
		"test_calibration_offset",
		"test_chart_offset_for_bias",
		"test_audio_buffer_override",
		"test_bell_center_merges",
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
	var notes_data: Array = []
	notes_data.assign(data.get("notes", []))
	for i in notes_data.size():
		if notes_data[i] is String and String(notes_data[i]).contains("path{"):
			notes_data[i] = {
				"id": 999, "type": "path", "beat": 8.0, "end_beat": 12.0,
				"angle": 0.0, "tail_angle": 180.0, "width": 120.0,
				"tail_width": 120.0, "tolerance": 0.24, "samples": 4.0,
				"visual": [{"db": 0.5, "da": 12.0}],
			}
			break
	data["notes"] = notes_data
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


func test_seek_and_limit_code() -> bool:
	var seek := Note.new("seek", 3.5, 0.0, 360.0)
	seek.id = 7
	seek.seek_orien = 1
	eq(seek.to_code(), "[7]seek(3.5,1)", "seek code")
	var restored := Note.from_code(seek.to_code())
	eq(restored.type, "seek", "seek code type")
	eq(restored.seek_orien, 1, "seek code orientation")
	near(restored.beat, 3.5, 0.001, "seek code beat")
	ok(Note.TYPES.has("seek"), "seek is a note type")
	ok(not Note.TYPES.has("trace"), "trace is removed")
	var region := Region.from_dict({"id": 1, "kind": "red", "start_beat": 1.0, "end_beat": 2.0})
	eq(region.kind, "limit", "legacy red region becomes limit")
	eq(String(region.to_dict()["kind"]), "limit", "limit region kind serialized")
	var limit := Region.from_code("[4]red(1.0,2.0,90.0)")
	ok(limit != null, "limit code parses")
	if limit != null:
		eq(limit.kind, "limit", "limit code kind")
		near(limit.width, 90.0, 0.001, "limit code width")
		eq(limit.to_code(), "[4]red(1.0,2.0,90.0)", "limit code roundtrip")
	var angled := Region.from_code("[5]red(26.0,28.0,100.0,270.0)")
	ok(angled != null, "angled limit code parses")
	if angled != null:
		near(angled.angle, 270.0, 0.001, "limit code keeps angle")
		eq(angled.to_code(), "[5]red(26.0,28.0,100.0,270.0)", "angled limit code roundtrip")
	return true


func test_note_width_code() -> bool:
	var sized_tap := Note.new("tap", 1.0, 90.0, 80.0)
	sized_tap.id = 3
	sized_tap.set_size_ratio(0.75)
	eq(sized_tap.to_code(), "[3]tap(1.0,90.0,80.0,1,0.75)", "sized tap writes width and size")
	var sized_back := Note.from_code(sized_tap.to_code())
	ok(sized_back != null, "sized tap parses")
	if sized_back != null:
		near(sized_back.width, 80.0, 0.001, "sized tap keeps base width")
		ok(sized_back.sized, "sized tap keeps sized flag")
		near(sized_back.size_ratio, 0.75, 0.001, "sized tap keeps size ratio")
		near(sized_back.arc_width(), 60.0, 0.001, "sized tap arc width is width x size")

	var normal := Note.new("tap", 1.0, 90.0, 60.0)
	normal.id = 4
	eq(normal.to_code(), "[4]tap(1.0,90.0)", "normal tap stays compact")
	var wide := Note.new("tap", 1.0, 90.0, 72.0)
	wide.id = 5
	eq(wide.to_code(), "[5]tap(1.0,90.0,72.0)", "width-only tap writes one extra field")
	var wide_back := Note.from_code(wide.to_code())
	if wide_back != null:
		near(wide_back.width, 72.0, 0.001, "width-only tap keeps width")
		ok(not wide_back.sized, "width-only tap stays unsized")

	var hold := Note.new("hold", 2.0, 0.0, 48.0)
	hold.id = 6
	hold.end_beat = 4.0
	eq(hold.to_code(), "[6]hold(2.0,4.0,0.0,48.0)", "wide hold writes width")
	var hold_back := Note.from_code(hold.to_code())
	if hold_back != null:
		near(hold_back.width, 48.0, 0.001, "wide hold keeps width")

	var bell := Note.new("bell", 3.0, 0.0, 27.0)
	bell.id = 7
	eq(bell.to_code(), "[7]bell(3.0,0.0,27.0,44.0)", "narrow bell writes width and radius")
	var bell_back := Note.from_code(bell.to_code())
	if bell_back != null:
		near(bell_back.bell_width(), 27.0, 0.001, "narrow bell keeps width")
		near(bell_back.radius, 44.0, 0.001, "narrow bell keeps radius")
	var default_bell := Note.new("bell", 3.0, 0.0, 30.0)
	default_bell.id = 8
	default_bell.radius = 26.0
	eq(default_bell.to_code(), "[8]bell(3.0,0.0)", "default bell stays compact")
	var default_bell_back := Note.from_code(default_bell.to_code())
	if default_bell_back != null:
		near(default_bell_back.bell_width(), 30.0, 0.001, "default bell loads 30 degrees")
	var radius_only_bell := Note.new("bell", 3.0, 0.0, 30.0)
	radius_only_bell.id = 9
	radius_only_bell.radius = 44.0
	eq(radius_only_bell.to_code(), "[9]bell(3.0,0.0,30.0,44.0)", "radius-only bell uses a width placeholder")

	var anchor := Note.new("anchor", 2.0, 90.0, 0.0)
	anchor.id = 10
	anchor.pair_id = "p1"
	anchor.anchor_pair = 45
	eq(anchor.to_code(), "[10]anchor(2.0,90.0,p1,45)", "anchor writes pair angle")
	var anchor_back := Note.from_code(anchor.to_code())
	if anchor_back != null:
		eq(anchor_back.pair_id, "p1", "anchor keeps pair id")
		eq(anchor_back.anchor_pair, 45, "anchor keeps pair angle")

	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	sized_tap.id = 1
	hold.id = 2
	bell.id = 3
	chart.notes = [sized_tap, hold, bell]
	var loaded := ChartIO.from_json(ChartIO.to_json(chart))
	ok(loaded != null, "compact chart with widths loads")
	if loaded != null:
		var by_id := {}
		for note in loaded.notes:
			by_id[note.id] = note
		if by_id.has(1):
			near(by_id[1].arc_width(), 60.0, 0.001, "json keeps sized tap arc width")
		if by_id.has(2):
			near(by_id[2].width, 48.0, 0.001, "json keeps hold width")
		if by_id.has(3):
			near(by_id[3].bell_width(), 27.0, 0.001, "json keeps bell width")
			near(by_id[3].radius, 44.0, 0.001, "json keeps bell radius")
	return true


func test_path_judgement_label_pos() -> bool:
	var bounds := Vector2(1600, 900)
	var center := Vector2(800, 450)
	var block := Vector2(120, 50)
	var ascent := 25.0
	var outside := Preview3D.path_label_pos(Vector2(1250, 450), center, bounds, block, ascent)
	near(outside.x, 1382.0, 0.5, "star label is pushed past the burst ring")
	near(outside.y, 450.0, 0.5, "star label keeps its radial line")
	# 贴右边缘时外侧放不下，改画到环内侧。
	var inward := Preview3D.path_label_pos(Vector2(1580, 450), center, bounds, block, ascent)
	near(inward.x, 1448.0, 0.5, "star label flips inward near the edge")
	# 两侧都放不下时仍夹在画面里。
	var tight := Preview3D.path_label_pos(Vector2(1590, 450), center, Vector2(300, 200), block, ascent)
	ok(tight.x >= 10.0 and tight.x + block.x <= 290.0, "star label stays inside a tight viewport")
	ok(tight.y - ascent >= 10.0 and tight.y + block.y <= 190.0, "star label stays above the bottom edge")
	return true


func test_judge_label_geometry() -> bool:
	var center := Vector2(800, 450)
	var ring := Vector2(1250, 450)
	var outer := Preview3D.judge_label_anchor(ring, center, 450.0, 30.0, true)
	var inner := Preview3D.judge_label_anchor(ring, center, 450.0, 30.0, false)
	near(outer.x, 1280.0, 0.5, "ring-out label sits outside the note")
	near(inner.x, 1220.0, 0.5, "ring-in label sits inside the note")
	near(outer.y, 450.0, 0.5, "ring label keeps the note angle")
	# 同角度的第二条判定沿半径继续外推，不叠在第一条上。
	var stacked := Preview3D.judge_label_anchor(ring, center, 450.0, 30.0, true, 22.0)
	near(stacked.x, 1302.0, 0.5, "stacked ring label moves outward")
	# 落点在圆心时退回环半径，不把字画到中心。
	var fallback := Preview3D.judge_label_anchor(center, center, 100.0, 20.0, true)
	near(fallback.x, 800.0, 0.5, "center fallback keeps x")
	near(fallback.y, 330.0, 0.5, "center fallback uses ring radius and points up")
	return true


func test_note_glyph_geometry() -> bool:
	var center := Vector2(50, 50)
	var top := NoteGlyph.ellipse_point(center, 20, 10, 0)
	near(top.x, 50.0, 0.01, "0deg sits at the top")
	near(top.y, 40.0, 0.01, "0deg is above the center")
	var right := NoteGlyph.ellipse_point(center, 20, 10, 90)
	near(right.x, 70.0, 0.01, "90deg sits on the right")
	near(right.y, 50.0, 0.01, "90deg keeps the center height")
	var arc := NoteGlyph.ring_points(center, 20, 10, -20, 20, 8)
	eq(arc.size(), 9, "arc points include both ends")
	var sector := NoteGlyph.sector_polygon(center, 20, 10, -30, 30, 8)
	eq(sector.size(), 10, "sector starts at the center plus the arc")
	ok(sector[0] == center, "sector polygon starts at the ring center")
	var annular := NoteGlyph.annular_sector_polygon(center, 20, 10, 0.5, -30, 30, 8)
	eq(annular.size(), 18, "annular sector joins outer and inner arcs")
	var normal := NoteGlyph.ring_normal(center, 20, 10, 0)
	near(normal.y, -1.0, 0.01, "top normal points up")
	eq(NotePalette.CARDS.size(), 7, "palette keeps seven note cards")
	eq(String(NotePalette.CARDS[5].get("type", "")), "bell", "bell card stays in the palette")
	return true


func test_note_width_controls() -> bool:
	ok(Inspector.shows_width_row("tap"), "tap shows the common width row")
	ok(Inspector.shows_width_row("hold"), "hold shows the common width row")
	ok(not Inspector.shows_width_row("bell"), "bell uses its own arc width row")
	ok(Inspector.shows_length_row("tap"), "tap shows the length row")
	ok(not Inspector.shows_length_row("hold"), "hold has no sized length")
	return true


func test_note_flags_code() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var tap := Note.new("tap", 1.0, 90.0, 60.0)
	tap.id = 1
	tap.lock = true
	chart.notes = [tap]
	var data := ChartIO.chart_to_dict(chart)
	ok(data.has("note_flags"), "locked notes use the note_flags side map")
	var loaded := ChartIO.from_json(ChartIO.to_json(chart))
	ok(loaded != null, "locked chart loads")
	if loaded != null and not loaded.notes.is_empty():
		ok(loaded.notes[0].lock, "lock survives the compact chart roundtrip")
	return true


func test_plane_tap_dropped() -> bool:
	var data := {
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"notes": [
			{"id": 1, "type": "tap", "beat": 1.0, "angle": 0.0, "width": 60.0, "space": "plane", "plane_x": 0.5, "plane_y": 0.5, "plane_radius": 0.1},
			{"id": 2, "type": "tap", "beat": 2.0, "angle": 90.0, "width": 60.0},
		],
	}
	var chart := ChartIO.chart_from_dict(data)
	ok(chart != null, "legacy plane tap chart loads")
	if chart != null:
		eq(chart.notes.size(), 1, "legacy plane tap is dropped")
		if not chart.notes.is_empty():
			eq(chart.notes[0].id, 2, "ring tap survives")
	return true


func test_compact_chart_code() -> bool:
	var chart := DemoChart.make_demo()
	var data := ChartIO.chart_to_dict(chart)
	var notes: Array = data["notes"]
	var shapes: Variant = data["shapes"]
	ok(notes.size() > 0 and notes[0] is String, "notes are compact code strings")
	ok(shapes is String, "shapes are one compact code block")
	ok(String(notes[0]).begins_with("["), "note code starts with id")
	ok(String(shapes).begins_with("shape{"), "shape code starts with shape")
	var loaded := ChartIO.from_json(ChartIO.to_json(chart))
	ok(loaded != null, "compact code chart loads")
	if loaded != null:
		eq(loaded.notes.size(), chart.notes.size(), "compact code note count")
		eq(loaded.shapes.size(), chart.shapes.size(), "compact code shape count")
		for note in loaded.notes:
			ok(note.type != "trace", "compact chart has no trace")
	return true


func test_path_chain_code() -> bool:
	var code := "[1]path{(part0,1.0,0.0,2.0,180.0,0.7,0.5);(part1,2.0,0.0,3.0,90.0,0.6,-0.5)}"
	var parts := Note.path_parts_from_code(code)
	eq(parts.size(), 2, "path chain parts")
	if parts.size() == 2:
		eq(parts[0].path_part, 0, "path root part 0")
		eq(parts[1].path_part, 1, "path child part 1")
		eq(parts[0].path_next_id, parts[1].id, "path root next link")
		eq(parts[1].path_prev_id, parts[0].id, "path child previous link")
		near(parts[1].path_head_point().distance_to(parts[0].path_tail_local()), 0.0, 0.001, "path chain head meets tail")
	return true


## 画面把链式 Path 画成一条（一个头一个尾），判定也必须是一条；否则子段会
## 要求一个画面上不存在的隐形头判。
func test_path_chain_judgement() -> bool:
	var code := "[1]path{(part0,1.0,0.0,2.0,180.0,0.7,0.5);(part1,2.0,0.0,3.0,90.0,0.6,-0.5)}"
	var parts := Note.path_parts_from_code(code)
	eq(parts.size(), 2, "chain parts parse for judgement")
	if parts.size() != 2:
		return true
	var chart := Chart.new()
	chart.notes = parts
	chart.refresh_ids()
	var run := Playtest.new()
	run.chart = chart
	run._init_states()
	var paths: Array[Note] = []
	for note in run._ordered_notes:
		if note.type == "path":
			paths.append(note)
	eq(paths.size(), 1, "a chain is one judgement path")
	ok(run._states.has(parts[0].id), "chain state lives on the root id")
	ok(not run._states.has(parts[1].id), "child parts do not get an invisible head/tail")
	if paths.size() == 1:
		eq(paths[0].id, parts[0].id, "the synthetic chain keeps the root id")
		near(paths[0].end_beat, 3.0, 0.001, "the chain keeps the final tail time")
		ok(paths[0].trace_pts.size() > 4, "the chain carries the combined trace")
	run.free()
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
	eq(Playtest.BELL_WINDOW_MS, 130.0, "a gold note keeps a forgiving drag window")
	eq(Preview3D.BELL_RADIAL_TOLERANCE, 55.0, "gold note presence keeps a 55px band")
	eq(Playtest.PERFECT_MS, 65.0, "perfect window tightened")
	eq(Playtest.GREAT_MS, 115.0, "great window tightened")
	eq(Playtest.GOOD_MS, 170.0, "good window tightened")
	eq(Playtest.POSITION_TOLERANCE_PX, 120.0, "one head tolerance for every note type")
	eq(Playtest.EARLY_MS, 115.0, "early presses stop at the GREAT boundary")
	ok(Playtest.PRESS_KEEP_MS < 100.0, "a press only lives for about one frame")
	eq(Playtest.KEY_DEBOUNCE_MS, 50.0, "the same key is debounced for 50ms")
	ok(Playtest.EARLY_MS < Playtest.HIT_WINDOW_MS, "early presses are stricter than late ones")
	eq(Playtest.PATH_TAIL_SWEEP_EARLY_MS, Playtest.TAIL_GOOD_MS, "finishing a slide early stops at the GOOD window")
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


## 匹配逻辑现在是纯函数：全局分配和测试共用同一把尺子。
func test_press_assignment() -> bool:
	var run := Playtest.new()
	var line := PackedVector2Array([Vector2(48, 0), Vector2(52, 0)])
	var note := Note.new("tap", 0.0, 88.0, 60.0)
	var near_target := {"note": note, "points": line, "tolerance": 10.0, "pad": 0.0,
		"dense": false, "ring_radius": 100.0}
	ok(bool(run._match_press({"time": 1000.0, "mouse": Vector2(50, 0)}, near_target).get("ok", false)),
		"a press on the shape matches")
	ok(not bool(run._match_press({"time": 1000.0, "mouse": Vector2(50, 30)}, near_target).get("ok", false)),
		"a press outside the tolerance does not match")
	var sector_target := {"note": note, "points": PackedVector2Array([Vector2(0, 0)]),
		"tolerance": 10.0, "pad": 0.0, "dense": true, "ring_radius": 330.0}
	ok(bool(run._match_press({"time": 1000.0, "angle": 89.0, "valid": true}, sector_target).get("ok", false)),
		"a press inside the dense sector matches")
	ok(not bool(run._match_press({"time": 1000.0, "angle": 20.0, "valid": true}, sector_target).get("ok", false)),
		"a press outside the dense sector does not match")
	ok(not bool(run._match_press({"time": 1000.0, "angle": 89.0, "valid": false}, sector_target).get("ok", false)),
		"a press made off the ring cannot take a dense sector")
	run.free()
	# 全局分配：同一帧的两颗 Tap 各拿一颗按键，不再由先判到的音符抢走。
	var chart := DemoChart.make_empty({"bpm": 120.0})
	chart.notes.clear()
	var first := Note.new("tap", 4.0, 0.0, 60.0)
	first.id = 1
	var second := Note.new("tap", 4.0, 180.0, 60.0)
	second.id = 2
	chart.notes = [first, second]
	var live := Playtest.new()
	var preview := Preview3D.new()
	preview._ready()
	preview.chart_override = chart
	preview.playtest_mode = true
	preview.time_beat = 4.0
	preview.prepare_playtest_frame(4.0, 0.0)
	live._preview = preview
	live.chart = chart
	live._init_states()
	var ms := 2000.0
	var first_point := live._preview.note_head_screen(first, 4.0)
	var second_point := live._preview.note_head_screen(second, 4.0)
	live._key_presses = [
		{"time": ms, "mouse": first_point, "angle": 0.0, "valid": true, "key": 65},
		{"time": ms, "mouse": second_point, "angle": 180.0, "valid": true, "key": 66},
	]
	live._assign_presses(ms, 4.0)
	ok(live._press_assignments.has(1) and live._press_assignments.has(2),
		"simultaneous taps receive separate presses")
	live._key_presses = [{"time": ms, "mouse": first_point, "angle": 0.0, "valid": true, "key": 65}]
	live._assign_presses(ms, 4.0)
	ok(live._press_assignments.size() == 1, "one press cannot be spent twice in a frame")
	live.free()
	preview.free()
	return true


func test_press_space_priority() -> bool:
	# 光标压在图形上的那颗优先：时间更近的邻键不能把它抢走（防蹭）。
	var on_shape := {"on_shape": true, "error": 40.0, "distance": 3.0}
	var neighbour := {"on_shape": false, "error": 5.0, "distance": 110.0}
	ok(Playtest.prefer_press_pair(on_shape, neighbour), "the note under the cursor ranks first")
	ok(not Playtest.prefer_press_pair(neighbour, on_shape), "the neighbour never outranks it")
	var earlier := {"on_shape": false, "error": 10.0, "distance": 80.0}
	var later := {"on_shape": false, "error": 30.0, "distance": 20.0}
	ok(Playtest.prefer_press_pair(earlier, later), "off the shape, timing still decides")
	ok(not Playtest.prefer_press_pair(later, earlier), "off the shape, the later press loses")
	var closer := {"on_shape": false, "error": 20.0, "distance": 10.0}
	var farther := {"on_shape": false, "error": 20.0, "distance": 90.0}
	ok(Playtest.prefer_press_pair(closer, farther), "equal timing falls back to distance")
	# 晚到的匹配加一点代价：漏掉前一颗后，下一按优先给后面那颗。
	var late_steal := {"on_shape": false, "error": 35.0, "rank": 47.0, "distance": 0.0}
	var upcoming := {"on_shape": false, "error": 40.0, "rank": 40.0, "distance": 0.0}
	ok(Playtest.prefer_press_pair(upcoming, late_steal), "an upcoming note beats a late steal")
	# 刚命中后的额外按键不能提前吃下一颗。
	ok(Playtest.press_is_stray(2020.0, 2095.0, 2000.0), "a stray press right after a hit is ignored")
	ok(not Playtest.press_is_stray(2020.0, 2095.0, -1.0e9), "a normal press is not treated as stray")
	ok(not Playtest.press_is_stray(2060.0, 2095.0, 2000.0), "a press inside the perfect window is kept")
	ok(not Playtest.press_is_stray(2095.0, 2095.0, 2000.0), "an on-time press is kept")
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
	ok(MediaIO.is_supported_video("a.mp4"), "mp4 is accepted through the video cache")
	ok(not MediaIO.is_native_video("a.mp4"), "mp4 is not a native stream class")
	ok(not MediaIO.is_supported_video("a.txt"), "text is not a video")
	ok(MediaIO.video_cache_path("a.mp4").ends_with(".ogv"), "video cache is ogv")
	var cache_file := "user://test_video_cache.mp4"
	var cache_write := FileAccess.open(cache_file, FileAccess.WRITE)
	if cache_write != null:
		cache_write.store_string("x")
		cache_write.close()
	var cache_a := MediaIO.video_cache_path(cache_file)
	cache_write = FileAccess.open(cache_file, FileAccess.WRITE)
	if cache_write != null:
		cache_write.store_string("xx")
		cache_write.close()
	var cache_b := MediaIO.video_cache_path(cache_file)
	ok(cache_a != cache_b, "video cache key follows source size")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_file))
	near(MediaIO.progress_seconds("out_time_us=2500000\nprogress=continue\n"), 2.5, 0.01, "ffmpeg progress microseconds")
	near(MediaIO.progress_seconds("out_time=00:00:03.500000\n"), 3.5, 0.01, "ffmpeg progress timecode")
	eq(MediaIO.prepare_audio("res://audio/demo_click.wav"), "res://audio/demo_click.wav", "native audio passes through")
	var rate2 := MediaIO.rate_audio_cache_path("res://audio/demo_click.wav", 2.0)
	ok(rate2.ends_with(".ogg"), "rate cache is ogg")
	ok(rate2 != MediaIO.rate_audio_cache_path("res://audio/demo_click.wav", 0.5), "rate cache key includes the rate")
	eq(MediaIO.prepare_audio_at_rate("res://audio/demo_click.wav", 1.0), "res://audio/demo_click.wav",
		"1x rate passes the original audio through")
	if MediaIO.has_ffmpeg():
		var rendered := MediaIO.prepare_audio_at_rate("res://audio/demo_click.wav", 2.0)
		ok(FileAccess.file_exists(rendered), "atempo renders a rate cache")
		var rendered_stream := ChartIO.audio_stream_from_path(rendered)
		ok(rendered_stream != null, "rate cache loads as an audio stream")
		if rendered_stream != null:
			near(rendered_stream.get_length(), 9.0, 0.6, "2x atempo halves the duration")
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
	var width_chart := Chart.new()
	width_chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var lbp_tap := Note.new("tap", 0.0, 90.0, 60.0)
	lbp_tap.id = 1
	lbp_tap.set_size_ratio(0.5)
	var lbp_hold := Note.new("hold", 0.0, 90.0, 60.0)
	lbp_hold.id = 2
	lbp_hold.end_beat = 2.0
	var lbp_bell := Note.new("bell", 0.0, 0.0, 27.0)
	lbp_bell.id = 3
	lbp_bell.center_u = 0.25
	lbp_bell.radius = 26.0
	width_chart.notes = [lbp_tap, lbp_hold, lbp_bell]
	var width_text := LBPIO.export_chart(width_chart)
	ok(width_text.contains("tap,"), "lbp keeps taps")
	ok(width_text.contains("hold,"), "lbp keeps holds")
	ok(width_text.contains("90.000,30.000"), "lbp writes visible arc width")
	ok(width_text.contains("width=27.000"), "lbp bell exports width option")
	var path := "user://test_export.lbp"
	eq(LBPIO.export_to_file(chart, path), OK, "lbp write")
	var read := FileAccess.get_file_as_string(path)
	eq(read, text, "lbp file matches string")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_note_color_palette() -> bool:
	var chart := DemoChart.make_demo()
	eq(chart.palette_count(), 0, "palette starts empty")
	var index := chart.add_palette_group()
	eq(index, 1, "palette group is one based")
	eq(chart.palette_count(), 1, "palette count grows")
	eq(chart.palette_name(index), "配色 1", "palette fallback name")
	chart.palette_group(index)["name"] = "冷色"
	eq(chart.palette_name(index), "冷色", "palette keeps custom name")
	eq(chart.palette_color(index, "tap"), Color("#ff6fae"), "palette default tap color")
	eq(chart.palette_color(0, "tap").a, 0.0, "palette lookup misses cleanly")

	var note := Note.new("tap", 4.0, 90.0, 60.0)
	note.id = chart.next_note_id()
	chart.notes.append(note)
	eq(note.resolved_color(chart, UITheme.PINK), UITheme.PINK, "no group falls back to skin")
	note.color = index
	eq(note.resolved_color(chart, UITheme.PINK), Color("#ff6fae"), "group color wins over skin")
	eq(chart.palette_usage(index), 1, "palette usage counts notes")

	note.has_custom_color = true
	note.custom_color = Color("#00ff00")
	eq(note.resolved_color(chart, UITheme.PINK), Color("#00ff00"), "single note override wins")
	note.has_custom_color = false

	chart.remove_palette_group(index)
	eq(chart.palette_count(), 0, "palette group removed")
	eq(note.color, 0, "removing a group clears references")
	eq(note.resolved_color(chart, UITheme.PINK), UITheme.PINK, "removed group falls back")
	return true


func test_note_color_contrast() -> bool:
	eq(Note.contrast_ratio(Color.BLACK, Color.BLACK), 1.0, "same colors have ratio one")
	ok(Note.contrast_ratio(Color.WHITE, Color.BLACK) > 20.0, "white on black is high contrast")
	ok(Note.contrast_ratio(Color.BLACK, Color.WHITE) > 20.0, "contrast is symmetric")
	ok(absf(Note.relative_luminance(Color.WHITE) - 1.0) < 0.001, "white luminance is one")
	ok(Note.MIN_CONTRAST > 1.0, "minimum contrast above identity")

	var note := Note.new("tap", 0.0, 0.0, 60.0)
	ok(note.supports_custom_color(), "tap supports custom color")
	ok(not Note.new("bell", 0.0, 0.0, 60.0).supports_custom_color(), "bell keeps fixed color")
	ok(not Note.new("seek", 0.0, 0.0, 60.0).supports_custom_color(), "seek keeps fixed color")
	return true


func test_note_color_round_trip() -> bool:
	var chart := DemoChart.make_demo()
	var index := chart.add_palette_group("舞台冷色")
	chart.palette_group(index)["tap"] = "#102030"
	var note := chart.notes[0]
	note.color = index

	var plain := ChartIO.chart_to_dict(DemoChart.make_demo())
	ok(not plain.has("palette"), "legacy chart writes no palette key")
	ok(not plain.has("note_colors"), "legacy chart writes no note_colors key")

	var restored := ChartIO.chart_from_dict(ChartIO.chart_to_dict(chart))
	eq(restored.palette_count(), 1, "palette survives save")
	eq(restored.palette_name(1), "舞台冷色", "palette name survives save")
	eq(restored.palette_color(1, "tap"), Color("#102030"), "palette color survives save")
	eq(restored.notes[0].color, index, "note group survives save")
	eq(restored.notes[0].resolved_color(restored, UITheme.PINK), Color("#102030"), "resolved color survives save")

	note.has_custom_color = true
	note.custom_color = Color("#c0ffee")
	var overridden := ChartIO.chart_from_dict(ChartIO.chart_to_dict(chart))
	ok(overridden.notes[0].has_custom_color, "override survives save")
	eq(overridden.notes[0].custom_color, Color("#c0ffee"), "override rgb survives save")
	eq(overridden.notes[0].color, index, "group assignment survives alongside override")

	var json := ChartIO.to_json(chart)
	var parsed := ChartIO.from_json(json)
	eq(parsed.palette_count(), 1, "palette survives json text")
	return true


func test_note_color_lbp() -> bool:
	var chart := DemoChart.make_demo()
	var index := chart.add_palette_group("冷色")
	chart.palette_group(index)["path"] = "#123456"
	var note := chart.notes[0]
	note.has_custom_color = true
	note.custom_color = Color("#abcdef")
	var text := LBPIO.export_chart(chart)
	ok(text.contains("[Palette]"), "lbp writes palette section")
	ok(text.contains("group,1,冷色"), "lbp writes palette group row")
	ok(text.contains("path=#123456"), "lbp writes palette colors")
	ok(text.contains("rgb=#abcdef"), "lbp writes per note rgb")

	chart.notes[0].has_custom_color = false
	var plain := LBPIO.export_chart(chart)
	ok(not plain.contains("[Palette]") or not plain.contains("rgb=#abcdef"), "lbp omits unused rgb")
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


func test_playtest_countdown() -> bool:
	eq(Playtest.countdown_number(2.0, 2.0), 3, "countdown starts at 3")
	eq(Playtest.countdown_number(1.34, 2.0), 3, "the first third still shows 3")
	eq(Playtest.countdown_number(1.33, 2.0), 2, "the second third shows 2")
	eq(Playtest.countdown_number(0.5, 2.0), 1, "the last third shows 1")
	eq(Playtest.countdown_number(0.0, 2.0), 0, "zero means GO")
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.pre_read_ms = 1000.0
	near(Playtest.timeline_start_beat(chart, 8.0, 1000.0), 5.0, 0.26,
		"a mid-chart start rewinds one pre-read plus half a second")
	near(Playtest.timeline_start_beat(chart, 0.0, 1000.0), -3.0, 0.001,
		"the chart start now keeps the lead-in as negative beats")
	eq(Playtest.audio_delay_ms(-3000.0, -500.0), 2500.0, "negative beats delay the audio")
	eq(Playtest.audio_delay_ms(0.0, -500.0), 0.0, "audio ahead of the timeline starts at once")
	return true


func test_video_direct_decode() -> bool:
	var mp4 := "user://test_direct_decode.mp4"
	ok(ChartIO.can_decode_video_directly("a.ogv"), "ogv is always decodable")
	var has_ffmpeg := ChartIO.ffmpeg_video_available()
	eq(ChartIO.can_decode_video_directly(mp4), has_ffmpeg, "mp4 decodes directly once gdffmpeg is loaded")
	eq(ChartIO.can_decode_video_directly("x.m4v"), has_ffmpeg, "osu BGA (m4v) decodes directly too")
	ok(MediaIO.SUPPORTED_VIDEO.has("m4v"), "m4v is in the supported video list")
	ok(not ChartIO.can_decode_video_directly(""), "empty paths never decode")
	# 没装扩展时必须返回 null，让预览退回转码而不是崩。
	if has_ffmpeg:
		var stream := ChartIO.video_stream_from_path("res://icon.svg")
		ok(stream == null, "non-video files do not become streams")
	else:
		ok(ChartIO.video_stream_from_path(mp4) == null, "no extension means no direct stream")
	return true


func test_osu_browser_alignment() -> bool:
	eq(OsuBrowser.PAGE_SIZE, 30, "osu browser pages 30 at a time")
	eq(OsuBrowser._thousands(168089), "168,089", "play counts get thousands separators")
	eq(OsuBrowser._thousands(999), "999", "short counts stay as-is")
	eq(OsuBrowser._thousands(0), "0", "zero stays zero")
	return true


func test_background_layering() -> bool:
	near(Preview3D.background_alpha(1.0), 0.32, 0.001, "default background keeps 32% alpha")
	near(Preview3D.background_alpha(0.5), 0.16, 0.001, "brightness scales the still image")
	near(Preview3D.background_alpha(0.0), 0.0, 0.001, "zero brightness hides the image")
	ok(not Preview3D.background_image_visible(true, true), "BGA hides the chart background image")
	ok(Preview3D.background_image_visible(true, false), "still image returns without BGA")
	ok(not Preview3D.background_image_visible(false, false), "no image without a texture")
	near(Preview3D.video_alpha(0.35, 1.0), 0.35, 0.001, "BGA keeps the chart opacity")
	near(Preview3D.video_alpha(0.35, 2.0), 0.70, 0.001, "global brightness multiplies the BGA")
	return true


func test_hold_stack_alpha() -> bool:
	near(Preview3D.hold_stack_alpha(0.0, 1.0), 1.0, 0.001, "the next hold stays fully opaque")
	near(Preview3D.hold_stack_alpha(-2.0, 1.0), 1.0, 0.001, "a held hold does not fade")
	near(Preview3D.hold_stack_alpha(2.0, 1.0), 0.65, 0.001, "a hold two pre-reads away reaches the floor")
	var mid := Preview3D.hold_stack_alpha(1.0, 1.0)
	ok(mid < 1.0 and mid > 0.65, "mid-distance holds fade between the two bounds")
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
	# 星尾独立档位：PERFECT ±150 / GREAT ±220 / GOOD ±350；早到不 Miss。
	eq(Playtest.tail_tier(-149.0), "PERFECT", "tail within 150ms is perfect")
	eq(Playtest.tail_tier(151.0), "GREAT", "tail 151ms is great")
	eq(Playtest.tail_tier(-221.0), "GOOD", "tail 221ms is good")
	eq(Playtest.tail_tier(351.0), "MISS", "late tail beyond 350ms is a miss")
	eq(Playtest.tail_tier(-360.0), "GOOD", "early tail never falls to miss")
	eq(Playtest.tail_tier(-203.6), "GREAT", "the one real-log outlier stays a great")
	# 星星入尾区参考：入口 0ms / 终点 dwell 都算 PERFECT；
	# 早到用 dwell/4 扩展，晚到仍按终点。
	eq(Playtest.tail_tier(0.0, 472.0), "PERFECT", "tail at the zone entry is perfect")
	eq(Playtest.tail_tier(472.0, 472.0), "PERFECT", "tail at the slide end is still perfect")
	eq(Playtest.tail_tier(-268.0, 472.0), "PERFECT", "early tail uses the dwell extension")
	eq(Playtest.tail_tier(-300.0, 472.0), "GREAT", "early tail just outside the extended perfect is great")
	eq(Playtest.tail_tier(-400.0, 472.0), "GOOD", "very early tail stays good")
	eq(Playtest.tail_tier(472.0 + 151.0, 472.0), "GREAT", "late tail is measured from the end")
	eq(Playtest.tail_tier(472.0 + 351.0, 472.0), "MISS", "late tail beyond end + 350 is a miss")
	eq(Playtest.tail_tier(472.0 + 100.0, 472.0), "PERFECT", "completion after the end but inside the window")
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


## 32 分扫键段：按键按不过来，一对一转 Bell 用鼠标扫；同角度连打和慢串保持 Tap。
func test_sweep_runs_to_bells() -> bool:
	var chart := DemoChart.make_empty({"bpm": 257.0})
	chart.notes.clear()
	var angles := [0.0, 45.0, 90.0, 135.0]
	for i in 4:
		var note := Note.new("tap", 0.125 * float(i), angles[i], 60.0)
		note.id = i + 1
		chart.notes.append(note)
	var stats := ConvertOptimizer.optimize_maimai(chart, {"tap": 4, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(int(stats.get("swept", 0)), 4, "the 32nd sweep is reported")
	var ordered := chart.sorted_notes()
	eq(ordered.size(), 4, "the sweep keeps its note count")
	for i in ordered.size():
		eq(ordered[i].type, "bell", "each swept tap becomes a bell")
		near(ordered[i].angle, angles[i], 0.01, "the sweep keeps its angle")

	var same := DemoChart.make_empty({"bpm": 257.0})
	same.notes.clear()
	for i in 4:
		var note := Note.new("tap", 0.125 * float(i), 90.0, 60.0)
		note.id = i + 1
		same.notes.append(note)
	ConvertOptimizer.optimize_maimai(same, {"tap": 4, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	for note in same.notes:
		eq(note.type, "tap", "a same-angle 32nd burst stays a tap")

	var slow := DemoChart.make_empty({"bpm": 120.0})
	slow.notes.clear()
	for i in 4:
		var note := Note.new("tap", 0.5 * float(i), 45.0 * float(i), 60.0)
		note.id = i + 1
		slow.notes.append(note)
	ConvertOptimizer.optimize_maimai(slow, {"tap": 4, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	for note in slow.notes:
		eq(note.type, "tap", "a slow ring run still needs key presses")

	# 240BPM 的 24 分 = 41.7ms：这次游玩里最集中的漏点，也要转。
	var sext := DemoChart.make_empty({"bpm": 240.0})
	sext.notes.clear()
	for i in 4:
		var note := Note.new("tap", float(i) / 6.0, 45.0 * float(i), 60.0)
		note.id = i + 1
		sext.notes.append(note)
	ConvertOptimizer.optimize_maimai(sext, {"tap": 4, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	for note in sext.notes:
		eq(note.type, "bell", "a 41.7ms sweep becomes bells")

	# 同角度 19/s 连爆隔一颗删一颗，保持 Tap；角度在动的串不删。
	var burst := DemoChart.make_empty({"bpm": 240.0})
	burst.notes.clear()
	for i in 6:
		var note := Note.new("tap", 0.2 * float(i), 270.0, 60.0)
		note.id = i + 1
		burst.notes.append(note)
	var burst_stats := ConvertOptimizer.optimize_maimai(burst, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(burst.notes.size(), 3, "a 19/s same-angle burst is thinned to half")
	eq(int(burst_stats.get("thinned", 0)), 3, "thinning is reported")
	for note in burst.notes:
		eq(note.type, "tap", "thinning keeps taps")
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
		near(bells[2].bell_radius, 1.0, 0.001, "C also joins the outer ring")
		near(bells[3].bell_radius, 1.0, 0.001, "D is on the outer gap")
		near(bells[4].bell_radius, 1.0, 0.001, "E joins the outer ring for mouse sweeps")
		near(bells[0].angle, 90.0, 0.01, "A1 sits on button 1")
		near(bells[3].angle, 67.5, 0.01, "D1 sits between button 1 and 2")
		var restored := Note.from_dict(bells[2].to_dict())
		near(restored.bell_radius, 1.0, 0.001, "legacy center bells roundtrip as outer ring bells")
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
	# 83ms 的 90° 来回：锁到 45° 后仍然是 3031px/s，超过鼠标上限，整段收成一个位置。
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 180.0, 4)]
	var angles := [90.0, 0.0, 90.0, 0.0, 90.0, 0.0]
	for i in angles.size():
		chart.notes.append(Note.new("tap", float(i) * 0.25, angles[i], 62.0))
	var stats := ConvertOptimizer.optimize_maimai(chart, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(int(stats.get("stacked", 0)), 1, "a run that is too fast even at 45 degrees collapses to one spot")
	for i in chart.notes.size():
		near(chart.notes[i].angle, 90.0, 0.01, "collapsed run note %d" % i)
	# 166ms 的 90° 来回：锁到 45° 之后是 1520px/s，鼠标追得上，保留一对位置。
	var medium := Chart.new()
	medium.timing.points = [TimingPoint.new(0.0, 180.0, 4)]
	for i in angles.size():
		medium.notes.append(Note.new("tap", float(i) * 0.5, angles[i], 62.0))
	var medium_stats := ConvertOptimizer.optimize_maimai(medium, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(int(medium_stats.get("locked", 0)), 1, "a medium A-B-A-B run is locked as one")
	for i in medium.notes.size():
		var expect := 90.0 if i % 2 == 0 else 45.0
		near(medium.notes[i].angle, expect, 0.01, "locked run note %d" % i)
	var slow := Chart.new()
	slow.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	for i in angles.size():
		slow.notes.append(Note.new("tap", float(i), angles[i], 62.0))
	ConvertOptimizer.optimize_maimai(slow, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	near(slow.notes[1].angle, 0.0, 0.01, "a slow run keeps its 90-degree positions")
	return true


## 45° 快速 A-B-A-B：整段收到第一颗角度，变成叠键；慢速段保留两个位置。
func test_small_angle_stack() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 200.0, 4)]
	var angles := [0.0, 45.0, 0.0, 45.0, 0.0]
	for i in angles.size():
		chart.notes.append(Note.new("tap", float(i) * 0.25, angles[i], 62.0))
	var stats := ConvertOptimizer.optimize_maimai(chart, {"tap": 5, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	eq(int(stats.get("stacked", 0)), 1, "a fast 45-degree run is stacked")
	for i in chart.notes.size():
		near(chart.notes[i].angle, 0.0, 0.01, "stacked run note %d" % i)
	# 三颗 A-B-A（舞萌邻键双手交互）也叠。
	var three := Chart.new()
	three.timing.points = [TimingPoint.new(0.0, 200.0, 4)]
	var tri := [0.0, 45.0, 0.0]
	for i in tri.size():
		three.notes.append(Note.new("tap", float(i) * 0.25, tri[i], 62.0))
	ConvertOptimizer.optimize_maimai(three, {"tap": 3, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	for i in three.notes.size():
		near(three.notes[i].angle, 0.0, 0.01, "three-note trill stacks note %d" % i)
	# 前面一段大跳失败后，断点处的邻键子段仍要能叠。
	var embedded := Chart.new()
	embedded.timing.points = [TimingPoint.new(0.0, 200.0, 4)]
	var mix := [0.0, 90.0, 0.0, 45.0, 0.0, 45.0]
	for i in mix.size():
		embedded.notes.append(Note.new("tap", float(i) * 0.25, mix[i], 62.0))
	ConvertOptimizer.optimize_maimai(embedded, {"tap": 6, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	near(embedded.notes[2].angle, 0.0, 0.01, "an embedded trill after a failed run stacks")
	near(embedded.notes[3].angle, 0.0, 0.01, "embedded trill second")
	near(embedded.notes[4].angle, 0.0, 0.01, "embedded trill middle")
	near(embedded.notes[5].angle, 0.0, 0.01, "embedded trill end")
	var slow := Chart.new()
	slow.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	for i in angles.size():
		slow.notes.append(Note.new("tap", float(i), angles[i], 62.0))
	ConvertOptimizer.optimize_maimai(slow, {"tap": 5, "hold": 0, "path": 0, "bell": 0, "dropped": 0})
	near(slow.notes[1].angle, 45.0, 0.01, "a slow 45-degree run keeps both positions")
	return true


func test_bell_snap_to_press_notes() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 200.0, 4)]
	var tap := Note.new("tap", 0.0, 0.0, 62.0)
	var near_bell := Note.new("bell", 0.25, 180.0, 45.0)
	near_bell.center_u = 0.5
	near_bell.bell_radius = 1.0
	var far_bell := Note.new("bell", 4.0, 180.0, 45.0)
	far_bell.center_u = 0.5
	far_bell.bell_radius = 1.0
	chart.notes = [tap, near_bell, far_bell]
	ConvertOptimizer.optimize_maimai(chart, {"tap": 1, "hold": 0, "path": 0, "bell": 2, "dropped": 0})
	near(near_bell.center_u, 0.0, 0.01, "a bell within 100ms snaps onto the tap angle")
	near(far_bell.center_u, 0.5, 0.01, "a far bell keeps its own angle")
	return true


func test_note_pop_scale() -> bool:
	near(Preview3D.note_pop_scale(0.0), 1.0, 0.001, "note pop starts at its own size")
	near(Preview3D.note_pop_scale(Preview3D.NOTE_POP_SEC), Preview3D.NOTE_POP_SCALE, 0.001, "note pop reaches its full scale")
	near(Preview3D.note_pop_scale(1.0), Preview3D.NOTE_POP_SCALE, 0.001, "note pop clamps after its lifetime")
	return true


func test_background_cache() -> bool:
	var preview := Preview3D.new()
	preview._background_image = TextureRect.new()
	preview.add_child(preview._background_image)
	preview._background_image.texture = GradientTexture2D.new()
	preview._background_image.visible = true
	preview._last_background_path = "user://old.png"
	preview._update_background(Chart.new())
	ok(preview._background_image.texture == null, "a chart without a background clears the old texture")
	ok(not preview._background_image.visible, "a chart without a background hides the background layer")
	var chart := Chart.new()
	var valid_path := "user://test_bg_valid.png"
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(ProjectSettings.globalize_path(valid_path))
	chart.metadata["background"] = valid_path
	preview._update_background(chart)
	ok(preview._background_image.texture != null, "a valid background image loads")
	ok(preview._background_image.visible, "a valid background image is visible")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(valid_path))
	preview.free()
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
	ok(PathProgress.SKIP_TOLERANCE >= 1, "slides allow skipping one judgement group")
	ok(PathProgress.NO_SKIP_GROUP_LIMIT == 3, "short slides protect their middle group")
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

## 变 BPM：音符的“起飞拍号”按毫秒反推，不能跟着当前 BPM 走。
## 旧实现用 bpm_at(t) 现算预读拍数，跨 BPM 段时音符会晚落地/忽然消失再出现。
func test_bpm_change_approach() -> bool:
	var chart := Chart.new()
	# 前 8 拍 60BPM，之后 240BPM。
	chart.timing.points = [TimingPoint.new(0.0, 60.0, 4), TimingPoint.new(8.0, 240.0, 4)]
	near(chart.timing.beat_to_chart_ms(8.0), 8000.0, 0.5, "beat 8 sits at 8000 ms")
	near(chart.timing.beat_to_chart_ms(9.0), 8250.0, 0.5, "beat 9 sits at 8250 ms")
	# 9 拍处的音符、预读 1000ms → 起飞拍号 7.25（7250ms），落在慢速段里。
	near(chart.timing.spawn_beat(9.0, 1000.0), 7.25, 0.01, "spawn beat is derived from milliseconds")
	# 在 7.5 拍（7500ms）时应该已经飞了 25%：(7500-7250)/1000。
	near(chart.timing.approach(9.0, 7.5, 1000.0), 0.25, 0.01, "approach follows milliseconds, not the current BPM")
	# 旧实现会在 8.0 拍（8000ms）才让音符出现，且一出现就是 75%。
	var at_change := chart.timing.approach(9.0, 8.0, 1000.0)
	ok(at_change > 0.5, "the note is already mid-flight when the BPM change hits")
	# 端点与单调性。
	near(chart.timing.approach(9.0, 7.25, 1000.0), 0.0, 0.001, "approach starts at the spawn beat")
	near(chart.timing.approach(9.0, 9.0, 1000.0), 1.0, 0.001, "approach ends on the note beat")
	var previous := -999.0
	for i in range(0, 200):
		var beat := 5.0 + float(i) * 0.02
		var spawn := chart.timing.spawn_beat(12.0, 1000.0)
		ok(is_equal_approx(spawn, spawn), "spawn beat is stable for a fixed note")
		if i == 0:
			previous = spawn
	# 同一音符的起飞点与时间无关；不同音符之间单调递增。
	var a := chart.timing.spawn_beat(9.0, 1000.0)
	var b := chart.timing.spawn_beat(10.0, 1000.0)
	ok(b > a, "later notes spawn later")
	# 慢速段里的音符：预读 1000ms = 1 拍，起飞点就是 beat-1。
	near(chart.timing.spawn_beat(4.0, 1000.0), 3.0, 0.001, "slow section keeps a one-beat pre-read")
	# 不含 BPM 变化时，和旧公式等价。
	var flat := Chart.new()
	flat.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	near(flat.timing.spawn_beat(10.0, 1000.0), 8.0, 0.001, "flat BPM keeps the old two-beat pre-read")
	return true
func test_chart_browser_helpers() -> bool:
	var items: Array = []
	for i in 65:
		items.append(i)
	eq(ChartBrowser.paginate(items, 0, 30).size(), 30, "first page holds 30")
	eq(int(ChartBrowser.paginate(items, 2, 30)[0]), 60, "third page starts at 60")
	eq(ChartBrowser.paginate(items, 3, 30).size(), 0, "past the end is empty")

	var levels := ChartBrowser.maj_levels(["", "5", "7+", "", "12", "13+", ""])
	eq(levels.size(), 4, "majdata levels skip empty slots")
	eq(int(levels[0].get("index", 0)), 1, "majdata keeps the difficulty index")
	eq(String(levels[3].get("level", "")), "13+", "majdata keeps Re:Master")

	var path := "user://test_maidata_levels.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("&title=T\n&artist=A\n&lv_1=4\n&des_1=x\n&inote_1=(120){1},1,\n&lv_4=12+\n&des_4=y\n&inote_4=(120){1},2,\n")
	file.close()
	var parsed := ChartBrowser.levels_from_maidata(path)
	eq(parsed.size(), 2, "maidata parses only real difficulties")
	eq(String(parsed[0].get("level", "")), "4", "maidata level is read")
	eq(String(parsed[1].get("creator", "")), "y", "maidata designer is read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var spec := {
		"files": [
			{"name": "maidata.txt", "url": "/adxcs/11/maidata.txt", "bytes": 100},
			{"name": "track.mp3", "url": "https://x/11/track.mp3", "bytes": 200},
			{"name": "bg.png", "url": "https://x/11/bg.png", "bytes": 300},
			{"name": "pv.mp4", "url": "https://x/11/pv.mp4", "bytes": 400},
		],
	}
	var covers := ChartBrowser.adx_cover_urls(spec)
	eq(covers.size(), 2, "adx cover tries webp then png")
	ok(String(covers[0]).ends_with(".webp"), "adx cover prefers webp")
	var bga := ChartBrowser.adx_bga_info(spec)
	eq(String(bga.get("state", "")), "yes", "adx spec reports BGA")
	eq(int(bga.get("size", 0)), 400, "adx BGA size comes from the catalog")
	var with_bga := ChartBrowser.download_files(spec, true)
	var without_bga := ChartBrowser.download_files(spec, false)
	eq(with_bga.size(), 4, "BGA download keeps all files")
	eq(without_bga.size(), 3, "non-BGA download drops the video")
	eq(ChartBrowser.download_size(with_bga), 1000, "BGA download size includes the video")
	eq(ChartBrowser.download_size(without_bga), 600, "non-BGA download size skips the video")
	var mp4 := PackedByteArray([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0])
	var webm := PackedByteArray([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0, 0, 0, 0, 0])
	ok(ChartBrowser.is_video(mp4), "mp4 header is accepted")
	ok(ChartBrowser.is_video(webm), "webm header is accepted")
	ok(not ChartBrowser.is_video("<!DOCTYPE html>".to_utf8_buffer()), "HTML error page is not a video")
	eq(ChartBrowser.favorite_key("adx", "11"), "adx:11", "favorite key is source-scoped")
	return true


## 在线 osu!：只列 osu!std，链接 / 纯 ID 能被识别成直接下载。
func test_osu_std_filter() -> bool:
	var only_taps := {"title": "A", "artist": "a", "id": 1, "beatmaps": [{"mode_int": 0}, {"mode_int": 0}]}
	var taiko_only := {"title": "B", "artist": "b", "id": 2, "beatmaps": [{"mode_int": 1}, {"mode_int": 3}]}
	var mixed := {"title": "C", "artist": "c", "id": 3, "beatmaps": [{"mode_int": 1}, {"mode_int": 0}]}
	eq(OsuBrowser.osu_std_count(only_taps), 2, "std count on a std set")
	eq(OsuBrowser.osu_std_count(taiko_only), 0, "taiko/mania sets have no std difficulty")
	eq(OsuBrowser.osu_std_count(mixed), 1, "mixed set counts only the std difficulty")

	var set_link := OsuBrowser.parse_osu_input("https://osu.ppy.sh/beatmapsets/2356114#osu/5073664")
	eq(String(set_link.get("kind", "")), "set", "beatmapset link is a set download")
	eq(int(set_link.get("id", 0)), 2356114, "beatmapset id parsed")
	var map_link := OsuBrowser.parse_osu_input("https://osu.ppy.sh/beatmaps/5073664")
	eq(String(map_link.get("kind", "")), "beatmap", "beatmap link needs resolving")
	eq(int(map_link.get("id", 0)), 5073664, "beatmap id parsed")
	var short_link := OsuBrowser.parse_osu_input("https://osu.ppy.sh/s/2356114")
	eq(int(short_link.get("id", 0)), 2356114, "short /s/ link parsed")
	var bare := OsuBrowser.parse_osu_input("5073664")
	eq(String(bare.get("kind", "")), "set", "bare number is tried as a set id")
	eq(int(bare.get("id", 0)), 5073664, "bare number parsed")
	ok(OsuBrowser.parse_osu_input("camellia").is_empty(), "plain text stays a search query")
	ok(OsuBrowser.parse_osu_input("").is_empty(), "empty input is a no-op")
	return true
## “起划”音效的时刻 = 星星开始沿轨迹移动的拍（note.beat + wait），不是头部接住的时刻。
func test_path_slide_start() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var note := Note.new("path", 4.0, 90.0, 62.0)
	note.end_beat = 6.0
	note.wait_beat = 0.5
	near(Playtest.slide_start_ms(chart, note, 0.0), 2250.0, 0.5, "slide starts at beat + wait")
	near(Playtest.slide_start_ms(chart, note, 30.0), 2280.0, 0.5, "judgement offset shifts the cue")
	ok(Playtest.slide_start_ms(chart, note, 0.0) > chart.timing.beat_to_chart_ms(note.beat), "cue is after the head beat")
	note.wait_beat = 0.0
	near(Playtest.slide_start_ms(chart, note, 0.0), 2000.0, 0.5, "no wait means the cue lands on the beat")
	note.wait_beat = 99.0
	near(Playtest.slide_start_ms(chart, note, 0.0), 2999.5, 6.0, "wait is clamped inside the note")
	return true
## 编辑器时间轴上“角度 = x”的映射：弧宽压在 0°/360° 接缝时必须拆成两段，
## 否则画 Hold / Tap 时会退化成满屏长条（之前 Hold 就是这么坏的）。
func test_hold_seam_interval() -> bool:
	var centered := JudgeMath.interval(0.0, 60.0)
	eq(centered.size(), 2, "hold centered on the seam splits in two")
	near(JudgeMath.total_length(centered), 60.0, 0.001, "split hold keeps its width")
	var left_edge := JudgeMath.interval(350.0, 80.0)
	eq(left_edge.size(), 2, "hold crossing the seam splits in two")
	near(JudgeMath.total_length(left_edge), 80.0, 0.001, "split hold keeps its width at 350deg")
	var normal := JudgeMath.interval(90.0, 60.0)
	eq(normal.size(), 1, "a hold away from the seam stays one piece")
	near(normal[0].x, 60.0, 0.001, "normal hold start")
	near(normal[0].y, 120.0, 0.001, "normal hold end")
	var full := JudgeMath.interval(0.0, 360.0)
	eq(full.size(), 1, "a full circle stays one span")
	near(JudgeMath.total_length(full), 360.0, 0.001, "full circle covers the ring")
	return true
## 结算页散布图：只收合法样本，等级颜色互不相同。
func test_audio_clock_rate() -> bool:
	var wall := AudioClock.new()
	wall.start(0.0, 0)
	near(wall.update(16000, false, 0.0, 0.0, 0.0, 0.0, 2.0), 32.0, 0.01,
		"the wall clock advances at the playback rate")
	var fast := AudioClock.new()
	fast.start(0.0, 0)
	var now := 0
	for i in 40:
		now += 16000
		fast.update(now, true, float(now) / 1000000.0 * 2.0, 0.0, 0.0, 0.0, 2.0)
	near(fast.clock_ms, float(now) / 1000.0 * 2.0, 8.0,
		"the clock follows 2x audio without falling behind")
	# 延迟和混音间隔是真实秒数，2× 下换算成流位置要翻倍。
	var latency := AudioClock.new()
	latency.start(380.0, 0)
	near(latency.update(16000, true, 0.5, 0.0, 0.05, 0.0, 2.0), 400.0, 0.01,
		"output latency is scaled by the playback rate")
	# 预拉伸的 2× 流：流里 0.5s 对应谱面 1s，延迟 50ms 也按 2× 换成谱面 100ms。
	var stretched := AudioClock.new()
	stretched.start(900.0, 0)
	near(stretched.update(16000, true, 0.5, 0.0, 0.05, 0.0, 2.0, 2.0), 900.0, 0.01,
		"a pre-stretched stream maps stream time and latency back to chart time")
	return true


func test_calibration_offset() -> bool:
	var samples: Array[float] = [-40.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0]
	near(CalibrationDialog.offset_for_errors(samples), -10.0, 0.01, "late taps produce a negative offset")
	var early: Array[float] = [-40.0, -30.0, -20.0, -10.0]
	near(CalibrationDialog.offset_for_errors(early), 20.0, 0.01, "early taps produce a positive offset")
	near(CalibrationDialog.offset_for_errors([1.0, 2.0]), 0.0, 0.01, "too few taps keep the offset unchanged")
	# 听声音和看脉冲写同一个字段：晚点 → 负 offset（判定往后挪）。
	near(CalibrationDialog.offset_for_errors([30.0, 40.0, 50.0, 60.0]), -50.0, 0.01,
		"late audio taps write the same judgement offset")
	near(CalibrationDialog.offset_for_errors([-60.0, -50.0, -40.0, -30.0]), 40.0, 0.01,
		"early audio taps write a positive judgement offset")
	return true


## 旧谱的圆心 Bell（bell_radius = 0）读进来也归到外环，和所有 Bell 统一。
func test_bell_center_merges() -> bool:
	var chart := Chart.new()
	var lead := Note.new("tap", 1.0, 90.0, 60.0)
	lead.id = 1
	var center := Note.new("bell", 2.0, 0.0, 45.0)
	center.id = 2
	center.bell_radius = 0.0
	var tail := Note.new("tap", 3.0, 180.0, 60.0)
	tail.id = 3
	chart.notes = [lead, center, tail]
	chart.merge_center_bells()
	eq(center.bell_radius, 1.0, "legacy center bells merge into the outer ring")
	eq(center.center_u, 0.25, "a legacy center bell inherits the previous note angle")
	# 前面没有音符时继承后一个。
	var only := Chart.new()
	var first := Note.new("bell", 1.0, 0.0, 45.0)
	first.id = 4
	first.bell_radius = 0.0
	var later := Note.new("tap", 2.0, 270.0, 60.0)
	later.id = 5
	only.notes = [first, later]
	only.merge_center_bells()
	eq(first.center_u, 0.75, "a leading center bell inherits the next note angle")
	var flat := Note.new("bell", 2.0, 0.0, 0.0)
	eq(flat.width, Note.BELL_MAX_WIDTH, "a bell without an arc width gets the standard 30 degree width")
	eq(center.width, Note.BELL_MAX_WIDTH, "a legacy 45-degree bell clamps to the new standard")
	var loaded := Note.from_dict({"type": "bell", "beat": 1.0, "width": 45.0, "id": 9})
	eq(loaded.width, Note.BELL_MAX_WIDTH, "a loaded 45-degree bell is normalized")
	return true


## 音频缓冲只能启动期生效，所以写 override.cfg；这里验证能写、能改、不重复追加。
func test_audio_buffer_override() -> bool:
	var path := "user://test_override.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app_script := load("res://charter/app.gd")
	ok(app_script.write_buffer_override(path, 10), "buffer override writes a config file")
	var config := ConfigFile.new()
	eq(config.load(path), OK, "buffer override is a config file")
	eq(int(config.get_value("audio", "driver/output_latency", 0)), 10, "buffer override stores the value")
	ok(app_script.write_buffer_override(path, 3), "buffer override can be rewritten")
	config = ConfigFile.new()
	config.load(path)
	eq(int(config.get_value("audio", "driver/output_latency", 0)), 3, "buffer override replaces the old value")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## 谱面 offset 的方向：按得早（bias<0）→ offset 变大，音符相对音频提前。
func test_chart_offset_for_bias() -> bool:
	near(Playtest.chart_offset_for_bias(0.0, -30.0), 30.0, 0.001, "early bias pushes the chart offset up")
	near(Playtest.chart_offset_for_bias(0.0, 25.0), -25.0, 0.001, "late bias pulls the chart offset down")
	near(Playtest.chart_offset_for_bias(-210.0, -10.0), -200.0, 0.001, "existing offset is kept as the base")
	near(Playtest.chart_offset_for_bias(0.0, 0.0), 0.0, 0.001, "no bias leaves the offset alone")
	return true


func test_audio_clock() -> bool:
	var clock := AudioClock.new()
	clock.start(1000.0, 0)
	near(clock.update(16000, false, 0.0, 0.0, 0.0, 0.0), 1016.0, 0.01, "wall clock advances without audio")
	var before := clock.clock_ms
	clock.update(32000, true, 9.0, 0.0, 0.0, 0.0)
	ok(clock.clock_ms - before < 20.0, "a bad forward playback sample cannot teleport the clock")
	before = clock.clock_ms
	clock.update(48000, true, 0.0, 0.0, 0.0, 0.0)
	ok(before - clock.clock_ms < 20.0, "a bad backward playback sample cannot rewind the clock")
	# 起播：音频没出声时停在起点，出声后用播放位置锚定（不再预测下一次 mix）。
	var waiting := AudioClock.new()
	waiting.start(500.0, 0)
	near(waiting.update(16000, true, 0.0, 0.0, 0.04, 0.0), 500.0, 0.01,
		"the clock waits for the first audible sample")
	var latency_clock := AudioClock.new()
	latency_clock.start(1000.0, 0)
	var with_latency := latency_clock.update(16000, true, 1.0, 100.0, 0.05, 0.0)
	near(with_latency, 1050.0, 0.01, "the first audio sample anchors the clock to the stream")
	ok(latency_clock.consume_anchor_jump(), "the anchor reports its one allowed backward jump")
	ok(not latency_clock.consume_anchor_jump(), "the anchor jump is reported only once")
	# 驱动延迟在 29–58ms 之间抖：冻结后不能再推着时钟走。
	var steady := AudioClock.new()
	steady.start(0.0, 0)
	var steady_now := 0
	for i in 40:
		steady_now += 16000
		steady.update(steady_now, true, float(steady_now) / 1000000.0, 0.0,
			0.045 if i % 2 == 0 else 0.035, 0.0)
	near(steady.clock_ms, float(steady_now) / 1000.0 - 40.0, 8.0,
		"latency noise stays inside the deadband after the estimate freezes")
	var drift := AudioClock.new()
	drift.start(0.0, 0)
	var now := 0
	for i in 120:
		now += 16000
		drift.update(now, true, float(now) / 1000000.0 + 0.050, 0.0, 0.0, 0.0)
	ok(absf(drift.clock_ms - (float(now) / 1000.0 + 50.0)) < 3.0,
		"the clock follows the audio stream once anchored")
	var hitch := AudioClock.new()
	hitch.start(0.0, 0)
	var after_hitch := hitch.update(500000, true, 0.5, 0.0, 0.0, 0.0)
	near(after_hitch, 500.0, 5.0, "a half-second hitch advances the clock instead of latching behind")
	return true


func test_judge_scatter() -> bool:
	var chart := JudgeScatter.new()
	chart.set_hits([
		{"offset": -30.0, "tier": "GREAT"},
		{"offset": 20.0, "tier": "PERFECT"},
		{"offset": 900.0, "tier": "BAD"},
		"junk",
	])
	eq(chart.hits.size(), 3, "only dictionary samples are kept")
	ok(JudgeScatter.tier_color("PERFECT") != JudgeScatter.tier_color("GREAT"), "perfect/great colours differ")
	ok(JudgeScatter.tier_color("GREAT") != JudgeScatter.tier_color("GOOD"), "great/good colours differ")
	ok(JudgeScatter.tier_color("BAD") != JudgeScatter.tier_color("MISS"), "bad/miss colours differ")
	chart.set_hits([])
	eq(chart.hits.size(), 0, "clearing the plot works")
	chart.free()
	return true

## 鼠标左右键当成两个独立键位，且不会和真实 Key 枚举相撞。
func test_mouse_button_input() -> bool:
	eq(Playtest.mouse_button_key(MOUSE_BUTTON_LEFT), Playtest.MOUSE_KEY_LEFT, "left button maps to its own key")
	eq(Playtest.mouse_button_key(MOUSE_BUTTON_RIGHT), Playtest.MOUSE_KEY_RIGHT, "right button maps to its own key")
	ok(Playtest.MOUSE_KEY_LEFT != Playtest.MOUSE_KEY_RIGHT, "left and right are distinct keys")
	ok(Playtest.MOUSE_KEY_LEFT < 0 and Playtest.MOUSE_KEY_RIGHT < 0, "synthetic keys stay out of the Key enum")
	eq(Playtest.mouse_button_key(MOUSE_BUTTON_MIDDLE), 0, "other buttons are not judgement input")
	eq(Playtest.mouse_button_key(MOUSE_BUTTON_WHEEL_UP), 0, "wheel stays a seek input")
	return true


## osu 卡片药丸颜色：按星数分五档。
func test_osu_star_color() -> bool:
	var green := OsuBrowser.star_color(1.4)
	var yellow := OsuBrowser.star_color(3.2)
	var orange := OsuBrowser.star_color(4.4)
	var red := OsuBrowser.star_color(6.0)
	var violet := OsuBrowser.star_color(7.5)
	ok(green == OsuBrowser.star_color(2.4), "green bucket is stable")
	ok(green != yellow and yellow != orange and orange != red and red != violet, "each bucket has its own colour")
	ok(violet == OsuBrowser.star_color(9.9), "purple bucket is stable")
	return true


## osu 官方筛选：类型 / 语言 / 标签（tags 是 AND）。
func test_osu_filters() -> bool:
	var tokens := OsuBrowser.tag_tokens("anime, JPop  Anime")
	eq(tokens.size(), 2, "tokens are lowercased and deduped")
	ok(tokens.has("anime") and tokens.has("jpop"), "both words are kept")
	ok(OsuBrowser.tag_tokens("").is_empty(), "empty text has no tokens")
	eq(OsuBrowser.tag_tokens("动画，电子").size(), 2, "full-width comma splits too")

	var anime := {"genre_id": 2, "language_id": 3, "tags": "anime j-pop vocaloid", "title": "X", "artist": "Y"}
	var rock := {"genre_id": 9, "language_id": 5, "tags": "rock guitar", "title": "Z", "artist": "W"}
	ok(OsuBrowser.matches_filters(anime, 0, 0, []), "no filter keeps everything")
	ok(OsuBrowser.matches_filters(anime, 2, 0, []), "genre matches")
	ok(not OsuBrowser.matches_filters(rock, 2, 0, []), "genre mismatch drops")
	ok(OsuBrowser.matches_filters(anime, 0, 3, []), "language matches")
	ok(not OsuBrowser.matches_filters(rock, 0, 3, []), "language mismatch drops")
	ok(not OsuBrowser.matches_filters(anime, 0, OsuBrowser.LANGUAGE_OTHER, []), "known language is not the other bucket")
	ok(not OsuBrowser.matches_filters(rock, 0, OsuBrowser.LANGUAGE_OTHER, []), "known languages are not 'other'")
	ok(OsuBrowser.matches_filters(anime, 0, 0, ["anime"]), "tag matches")
	ok(not OsuBrowser.matches_filters(rock, 0, 0, ["anime"]), "tag mismatch drops")
	ok(OsuBrowser.matches_filters(anime, 0, 0, ["anime", "vocaloid"]), "tags are AND")
	ok(not OsuBrowser.matches_filters(anime, 0, 0, ["anime", "guitar"]), "AND fails on a missing tag")
	ok(OsuBrowser.matches_filters(anime, 0, 0, ["J-POP"]), "tag matching ignores case")
	return true


## 展开后药丸的行数：宽卡片行数少，窄卡片行数多。
func test_osu_pill_rows() -> bool:
	eq(OsuBrowser.pill_rows(3, 1200), 1, "few difficulties stay on one row")
	eq(OsuBrowser.pill_rows(19, 1300), 2, "wide card fits 19 on two rows")
	ok(OsuBrowser.pill_rows(19, 700) > OsuBrowser.pill_rows(19, 1300), "narrower card needs more rows")
	eq(OsuBrowser.pill_rows(0, 900), 1, "no difficulties still one row (the toggle chip)")
	return true


## Path 方向箭头：固定弧长间距；锯齿状轨迹再按屏幕距离去重。
func test_path_chevron_spacing() -> bool:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	var fractions := Preview3D.chevron_fractions(line, 60.0, 40.0)
	eq(fractions.size(), 5, "300px with 60px spacing gives 5 arrows")
	for i in range(1, fractions.size()):
		var gap := (fractions[i] - fractions[i - 1]) * 300.0
		ok(absf(gap - 60.0) < 0.01, "arrow spacing is uniform (%.2f)" % gap)

	# 短于间距的一条线：一只箭头都不画
	ok(Preview3D.chevron_fractions(PackedVector2Array([Vector2(0, 0), Vector2(20, 0)]), 60.0, 40.0).is_empty(),
		"short stub gets no arrow")

	# 锯齿：弧长够长，但同一片区域反复折返 → 去重后数量明显变少
	var zig := PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(20, 12), Vector2(130, 24), Vector2(30, 36)])
	var zig_fractions := Preview3D.chevron_fractions(zig, 40.0, 70.0)
	var zig_arc := 0.0
	for i in zig.size() - 1:
		zig_arc += zig[i].distance_to(zig[i + 1])
	ok(zig_fractions.size() < int(zig_arc / 40.0), "crowded zigzag drops overlapping arrows")
	ok(zig_fractions.size() >= 2, "zigzag still gets some arrows")

	# 超长轨迹：箭头上限 48 只时必须整体拉开间距、铺到终点，不能在 48 * spacing 处截断
	var long_line := PackedVector2Array([Vector2(0, 0), Vector2(4000, 0)])
	var long_fractions := Preview3D.chevron_fractions(long_line, 60.0, 30.0)
	eq(long_fractions.size(), 48, "long path caps at 48 arrows")
	ok(float(long_fractions[long_fractions.size() - 1]) > 0.9, "arrows still reach the end of a long path")
	var long_gap := (float(long_fractions[1]) - float(long_fractions[0])) * 4000.0
	var last_gap := (float(long_fractions[long_fractions.size() - 1]) - float(long_fractions[long_fractions.size() - 2])) * 4000.0
	ok(absf(long_gap - last_gap) < 0.5, "capped long path keeps uniform spacing")
	return true


## osu! storyboard：静态 sprite + 单条命令插值。
func test_storyboard_parse() -> bool:
	var text := """[Events]
Sprite,Background,Centre,"bg.jpg",320,240
 F,0,0,1000,0,1
 M,0,0,1000,100,200,300,400
"""
	var board := Storyboard.parse(text)
	eq(board.sprites.size(), 1, "one sprite parsed")
	var sprite: Storyboard.Sprite = board.sprites[0]
	eq(sprite.layer, "Background", "layer")
	eq(sprite.origin, 4, "centre origin")
	eq(sprite.path, "bg.jpg", "path")

	# 起始 alpha = 0 的 sprite 不参与绘制（osu 也是这样）
	ok(board.sample(0.0).is_empty(), "alpha 0 sprite is culled")

	var quarter := board.sample(250.0)
	eq(quarter.size(), 1, "visible once faded in")
	ok(absf(float(quarter[0]["alpha"]) - 0.25) < 0.01, "alpha starts at 0 and fades in")
	var start_pos: Vector2 = quarter[0]["pos"]
	ok(start_pos.distance_to(Vector2(150, 250)) < 0.5, "move start")

	var mid := board.sample(500.0)
	ok(absf(float(mid[0]["alpha"]) - 0.5) < 0.01, "alpha interpolates linearly")
	var mid_pos: Vector2 = mid[0]["pos"]
	ok(mid_pos.distance_to(Vector2(200, 300)) < 0.01, "move interpolates")

	var end := board.sample(1000.0)
	ok(absf(float(end[0]["alpha"]) - 1.0) < 0.001, "alpha ends at 1")

	# lazer 的 EndTimeForDisplay：命令全部结束后对象就不存在了
	ok(board.sample(1500.0).is_empty(), "sprite is gone after its last command")
	return true


## 故事板写回 .osb 后再解析，对象和命令数量要一致（覆盖编辑器的保存/导出）。
func test_storyboard_serialize() -> bool:
	var text := """[Events]
Sprite,Background,Centre,"sb/a.png",320,240
 F,0,0,1000,0,1
 M,17,1000,2000,320,240,400,300
Sprite,Foreground,TopCentre,"sb/b.png",320,0
 S,0,0,,0.5
 V,0,0,,2,3
 R,0,0,90,0
 C,0,0,,255,0,0
"""
	var board := Storyboard.parse(text, "test.osb")
	eq(board.sprites.size(), 2, "serialize: 2 sprites")
	eq(board.sprites[0].commands.size(), 2, "serialize: first sprite commands")
	var written := board.to_osb_text()
	var again := Storyboard.parse(written, "again.osb")
	eq(again.sprites.size(), 2, "round-trip: sprite count")
	eq(again.sprites[0].commands.size(), 2, "round-trip: first sprite commands")
	eq(again.sprites[1].commands.size(), 4, "round-trip: second sprite commands")
	ok(written.contains("Sprite,Background,Centre"), "writes sprite header")
	ok(written.contains(" F,"), "writes alpha command")
	return true


## 编辑器新建对象 + 加命令后能保存并解析回来。
func test_storyboard_editor_model() -> bool:
	var board := Storyboard.create_blank()
	var sprite := board.add_sprite("sb/x.png", "Foreground", 4, Vector2(320, 240))
	board.add_command(sprite, "alpha", 0, 1000.0, 2000.0, [0.0], [1.0])
	board.add_command(sprite, "move", 0, 0.0, 1000.0, [0.0, 0.0], [320.0, 240.0])
	eq(board.sprites.size(), 1, "editor: sprite added")
	eq(sprite.commands.size(), 2, "editor: commands added")
	# 首条 alpha 是 0→1：按 lazer 的 StartTime 规则，生命周期从「第一个可见的 alpha」开始
	ok(absf(sprite.start_time - 1000.0) < 0.001, "editor: start time follows lazer StartTime")
	var text := board.to_osb_text()
	var parsed := Storyboard.parse(text, "edit.osb")
	eq(parsed.sprites.size(), 1, "editor: saved board parses back")
	eq(parsed.sprites[0].commands.size(), 2, "editor: saved commands parse back")
	return true


## loop 展开 + 缓动。
func test_storyboard_loops_and_easing() -> bool:
	var text := """[Events]
Sprite,Foreground,TopLeft,"p.png",0,0
 L,1000,2
  F,0,0,500,1,0
 S,0,0,500,2,1
"""
	var board := Storyboard.parse(text)
	eq(board.sprites.size(), 1, "sprite parsed")
	var sprite: Storyboard.Sprite = board.sprites[0]
	# 两轮 × 一条 F/S 命令 = 每条命令 2 段
	eq((sprite.timeline.get("alpha", []) as Array).size(), 2, "loop expanded alpha into two commands")
	eq((sprite.timeline.get("scale", []) as Array).size(), 2, "loop expanded scale into two commands")

	var first := board.sample(1250.0)
	ok(absf(float(first[0]["alpha"]) - 0.5) < 0.01, "first loop iteration fades")
	ok(absf(float(first[0]["scale"].x) - 1.5) < 0.01, "first loop iteration scales")

	var second := board.sample(1750.0)
	ok(absf(float(second[0]["alpha"]) - 0.5) < 0.01, "second loop iteration repeats")

	# 第二轮结束后 alpha 终值是 0，对象被剔除（osu 里也就是看不见）
	ok(board.sample(2500.0).is_empty(), "loop ends at alpha 0 (culled)")

	# 缓动：OutQuad（id=4）在 25% 处应大于线性
	var eased := """[Events]
Sprite,Background,Centre,"a.png",0,0
 F,4,0,1000,0,1
"""
	var board2 := Storyboard.parse(eased)
	var quarter := board2.sample(250.0)
	ok(float(quarter[0]["alpha"]) > 0.4, "ease-out is ahead of linear at 25%")
	eq(Storyboard.Easing.apply(0, 0.25), 0.25, "linear easing")
	eq(Storyboard.Easing.apply(4, 0.5), 0.75, "out-quad at half")
	eq(Storyboard.Easing.apply(35, 1.0), 1.0, "out-pow10 ends at 1")
	return true


## 图层 / 原点 / 动画帧。
func test_storyboard_layers() -> bool:
	var text := """[Events]
Sprite,Background,Centre,"bg.png",320,240
Sprite,Foreground,BottomRight,"fg.png",640,480
Sprite,Overlay,TopLeft,"over.png",0,0
Animation,Foreground,Centre,"anim.png",10,10,4,120,1
"""
	var board := Storyboard.parse(text)
	eq(board.sprites.size(), 4, "four objects")
	eq((board.sprites[1] as Storyboard.Sprite).layer, "Foreground", "foreground layer")
	eq((board.sprites[2] as Storyboard.Sprite).origin, 0, "top-left origin")
	var anim: Storyboard.Sprite = board.sprites[3]
	eq(anim.frames, 4, "animation frames")
	ok(absf(anim.frame_delay - 120.0) < 0.001, "frame delay")
	eq(anim.loop_type, 1, "loop once")
	return true
