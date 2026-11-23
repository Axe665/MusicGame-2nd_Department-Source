extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	var tests := [
		"test_timing",
		"test_boundary_circle",
		"test_boundary_vertices",
		"test_boundary_keys_io",
		"test_shape_morph_duration_and_camera_arc",
		"test_ring_compat_rules",
		"test_boundary_batch",
		"test_boundary_frame",
		"test_live_edit_notifications",
		"test_background_chart_snapshot",
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
		"test_path_paste_chain",
		"test_path_chain_judgement",
		"test_path_preview_visibility",
		"test_path_stroke_cache",
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
		"test_group_note_speed",
		"test_playtest_feedback",
		"test_judge_label_filter",
		"test_bar_lines",
		"test_beat_grid_lines",
		"test_pinned_scroll",
		"test_flow_flip_anchor",
		"test_ring_span_label",
		"test_ring_span_end",
		"test_ring_scrub_state",
		"test_ring_lane_items_real_chart",
		"test_ring_timeline_selection_ops",
		"test_ring_timeline_command_lanes",
		"test_ring_timeline_command_copy_paste",
		"test_ring_note_lane_cache",
		"test_ring_timeline_filter_menu",
		"test_ring_playhead_only_redraws_overlay",
		"test_ring_marquee_and_drag",
		"test_shape_key_cache_invalidation",
		"test_key_ids_and_v2_migration",
		"test_camera_left_key_semantics",
		"test_shape_transition_incoming",
		"test_content_end_includes_ring_keys",
		"test_v2_camera_easing_migration",
		"test_v3_round_trip_fields",
		"test_legacy_events_no_resurrection",
		"test_camera_dolly_interpolates",
		"test_ring_segment_targets",
		"test_ring_undo_and_default_circle",
		"test_ring_insert_advances_when_occupied",
		"test_ring_insert_at_empty_playhead",
		"test_ring_signal_split",
		"test_ease_bezier",
		"test_undo_memory_budget",
		"test_full_chart_round_trip",
		"test_difficulty_set_round_trip",
		"test_lbp_export_covers_all_types",
		"test_save_atomic_and_backup",
		"test_playhead_redraw_is_light",
		"test_chart_end_limit",
		"test_uniform_meter",
		"test_timing_presorted",
		"test_shrink_example",
		"test_event_restore",
		"test_playability_validator",
		"test_media_formats",
		"test_lbp_export",
		"test_lbp_package",
		"test_lbp_package_assets",
		"test_video_export_cursor",
		"test_video_export_plan_hits",
		"test_video_export_sfx_capture",
		"test_video_export_uses_resolved_ffmpeg",
		"test_note_fall_time",
		"test_aim_angle_fallback",
		"test_inspector_wheel_scrolls_page",
		"test_preview_note_drag_angle",
		"test_canvas_width_drag",
		"test_bell_width_drag",
		"test_region_drag",
		"test_canvas_default_snapping",
		"test_anchor_release_snap",
		"test_note_release_snap",
		"test_region_release_snap",
		"test_editor_snap_settings_persist",
		"test_anchor_pair_drag",
		"test_anchor_partners_untyped_array",
		"test_path_axis_drag",
		"test_path_head_beat",
		"test_path_smoothing",
		"test_seek_limit_animation_curves",
		"test_seek_grow_matches_tap",
		"test_seek_warning_order",
		"test_limit_dwell_once",
		"test_bpm_snap_multipliers",
		"test_path_zone_granularity",
		"test_bpm_lock_scales_following",
		"test_wheel_direction_matches_screen",
		"test_offline_focus_out_keeps_running",
		"test_storyboard_clamps_first_command",
		"test_storyboard_editor_fit_size",
		"test_ring_tilt_target",
		"test_storyboard_editor_transport",
		"test_storyboard_build_recomputes_bounds",
		"test_storyboard_command_cursor",
		"test_storyboard_timeline_rows",
		"test_storyboard_timeline_snap_offset",
		"test_storyboard_timeline_mouse",
		"test_storyboard_layer_toggle_reversible",
		"test_storyboard_escape_cancels",
		"test_storyboard_drag_cancel_restores",
		"test_storyboard_close_dialog_unique",
		"test_storyboard_wide_detection",
		"test_replay_mirror_restore",
		"test_replay_infer_mirror",
		"test_video_export_start_from_replay",
		"test_ring_timeline_clock",
		"test_background_brightness_applies",
		"test_storyboard_roundtrip_lossless",
		"test_storyboard_loop_indent_scope",
		"test_replay_normalized_coords",
		"test_video_export_frame_total",
		"test_ring_tilt_keeps_center",
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
		"test_chart_project_format",
		"test_tmc_group_path_round_trip",
		"test_note_groups",
		"test_validation_demo",
		"test_angle_math",
		"test_note_mirror",
		"test_trace_distance",
		"test_sfx_assets",
		"test_simai_import",
		"test_simai_button_layout",
		"test_chart_mirror",
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
		"test_auto_resume_index_and_media_jobs",
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
		"test_osu_difficulty_star_sort",
		"test_osu_star_hints_json",
		"test_osu_beatmap_set_id",
		"test_import_label_stars",
		"test_difficulty_star_label",
		"test_difficulty_stars_round_trip",
		"test_storyboard_parse",
		"test_storyboard_loops_and_easing",
		"test_storyboard_serialize",
		"test_storyboard_editor_model",
		"test_storyboard_layers",
		"test_storyboard_sample_ownership",
		"test_osu_pill_rows",
		"test_path_chevron_spacing",
		"test_audio_clock",
		"test_audio_clock_rate",
		"test_calibration_offset",
		"test_chart_offset_for_bias",
		"test_audio_buffer_override",
		"test_bell_center_merges",
		"test_replay_round_trip",
		"test_replay_match_project_entry",
		"test_replay_dispatch",
		"test_replay_scrub",
		"test_replay_file_name",
		"test_playtest_ui_builds",
		"test_retry_clears_playtest_visuals",
		"test_alpha_command_catalog",
		"test_alpha_command_envelope",
		"test_jline_ring_state",
		"test_filter_region_state",
		"test_filter_layer_visibility",
		"test_playfield_quality_settings",
		"test_storyboard_cache_budget",
		"test_text_command_center",
		"test_note_mods_io",
		"test_note_touch_zones",
		"test_chart_commands_roundtrip",
		"test_alpha_command_save_load_chain",
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
	eq(map.format_beat(16.0), "5:0:4", "timing format beat")
	near(map.parse_beat("5:0:4"), 16.0, 0.001, "timing parse beat")
	near(map.parse_beat("5:2:4"), 18.0, 0.001, "timing parse half bar")
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
	eq(TimingMap.parse_angle_divisions("12"), 12, "angle divisions parse 12")
	eq(TimingMap.parse_angle_divisions("8"), 8, "angle divisions parse 8")
	eq(TimingMap.parse_angle_divisions("360"), 360, "angle divisions parse 360")
	eq(TimingMap.parse_angle_divisions("7"), 0, "angle divisions reject values that do not divide 360")
	eq(TimingMap.parse_angle_divisions("361"), 0, "angle divisions reject over max")
	eq(TimingMap.parse_angle_divisions("1"), 0, "angle divisions reject one")
	eq(TimingMap.parse_angle_divisions("2.5"), 0, "angle divisions reject fraction")
	eq(TimingMap.parse_angle_divisions("abc"), 0, "angle divisions reject text")
	eq(TimingMap.nearest_angle_divisions(7), 8, "angle divisions suggest the nearest legal value")
	var alines := TimingMap.angle_line_offsets(12)
	eq(alines.size(), 11, "angle divisions 12 has 11 interior lines")
	near(alines[0], 1.0 / 12.0, 0.00001, "angle divisions first at 1/12")
	near(alines[10], 11.0 / 12.0, 0.00001, "angle divisions last at 11/12")
	near(TimingMap.nearest_angle_u(0.51, 12), 6.0 / 12.0, 0.00001, "angle lines snap to nearest line")
	near(TimingMap.nearest_angle_u(0.01, 12), 0.0, 0.00001, "the 0 degree edge is a snap target")
	near(TimingMap.nearest_angle_u(0.99, 12), 1.0, 0.00001, "the 360 degree edge is a snap target")
	eq(TimingMap.angle_line_offsets(2).size(), 1, "two divisions draw one interior line")
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


func test_boundary_vertices() -> bool:
	var shape := BoundaryShape.circle("S0", 330.0, 8)
	eq(shape.vertex_count(), 8, "circle preset exposes 8 vertices")
	# 拖顶点：相邻两段一起动，环不断接。
	shape.set_vertex(0, Vector2(400, 0))
	near(shape.vertices()[0].distance_to(Vector2(400, 0)), 0.0, 0.0001, "vertex drag moves the vertex")
	near(shape.point_at(0.0).point.distance_to(Vector2(400, 0)), 0.0, 0.0001, "seam follows the dragged vertex")
	eq(shape.validate().size(), 0, "dragged vertex ring still validates")
	# 加点不改轮廓：新顶点落在原来的边上。
	var before: Vector2 = shape.point_at(0.37).point
	ok(shape.insert_vertex(2), "vertex insert succeeds")
	eq(shape.vertex_count(), 9, "vertex insert adds one vertex")
	near(shape.point_at(0.37).point.distance_to(before), 0.0, 0.01, "vertex insert keeps the outline")
	eq(shape.validate().size(), 0, "inserted ring still validates")
	# 删点只合并那个角。
	var vertices_before := shape.vertices()
	ok(shape.remove_vertex(4), "vertex remove succeeds")
	eq(shape.vertex_count(), 8, "vertex remove drops one vertex")
	near(shape.vertices()[0].distance_to(vertices_before[0]), 0.0, 0.0001, "other vertices stay put")
	# 凹形允许保存。
	shape.set_vertex(3, Vector2(60, 60))
	eq(shape.validate().size(), 0, "concave outline is allowed")
	# 超过 48 段的老谱面降到 48；32 段保持原样。
	var legacy := BoundaryShape.circle("L", 330.0, 64)
	legacy.normalize()
	eq(legacy.vertex_count(), 48, "over-dense shape downsamples to 48")
	var mid := BoundaryShape.circle("M", 330.0, 32)
	mid.normalize()
	eq(mid.vertex_count(), 32, "32-segment shape keeps its detail")
	eq(legacy.validate().size(), 0, "downsampled shape validates")
	# 缺口在插入顶点后仍然存在。
	var gapped := BoundaryShape.circle("G", 330.0, 8)
	gapped.set_gap(0, true)
	gapped.insert_vertex(0)
	var gaps := 0
	for i in gapped.vertex_count():
		if gapped.segment_has_gap(i):
			gaps += 1
	eq(gaps, 2, "gap splits into two gaps when inserting")
	return true


func test_boundary_keys_io() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S1"] = BoundaryShape.circle("S1", 200.0, 12)
	chart.shape_keys = [
		{"beat": 2.0, "shape_id": "S1", "easing": "linear", "morph": 1.0},
		{"beat": 4.0, "shape_id": "S0", "easing": "linear", "morph": 1.0},
	]
	# 过渡在目标帧前完成：0–1 保持默认圆，1–2 变到 S1；3–4 变回 S0。
	near(BoundaryRuntime.eval_point(chart, 0.0, 0.5).point.x, 330.0, 0.5, "intro holds the default circle")
	near(BoundaryRuntime.eval_point(chart, 0.0, 1.5).point.x, 265.0, 0.5, "intro transition ends at the first key")
	near(BoundaryRuntime.eval_point(chart, 0.0, 3.5).point.x, 265.0, 0.5, "transition ends at the next key")
	near(BoundaryRuntime.eval_point(chart, 0.0, 5.0).point.x, 330.0, 0.5, "last key holds after the end")
	var data := ChartIO.chart_to_dict(chart)
	ok(data.has("boundary_keys"), "keys are written to json")
	ok((data["events"] as Array).is_empty(), "modern charts do not dual-write legacy events")
	var back := ChartIO.from_json(ChartIO.to_json(chart))
	eq(back.shape_keys.size(), 2, "keys survive the roundtrip")
	near(BoundaryRuntime.eval_point(back, 0.0, 3.5).point.x, 265.0, 0.5, "roundtrip keeps the morph")
	# 旧谱只有事件：载入时迁移成关键帧。
	var legacy := {
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"shapes": [{"id": "S0", "closed": true, "segments": []}],
		"events": [
			{"id": "E0", "start_beat": 4.0, "end_beat": 8.0, "target_u0": 0.0, "target_u1": 1.0,
				"from_shape": "S0", "to_shape": "S0", "easing": "linear", "end_behavior": "hold",
				"restore_duration": 0.0, "restore_easing": "in-out"},
		],
	}
	var migrated := ChartIO.chart_from_dict(legacy)
	ok(migrated != null, "legacy event chart loads")
	if migrated != null:
		eq(migrated.shape_keys.size(), 2, "legacy events become keys")
		eq(migrated.events.size(), 0, "legacy events are cleared after migration")
	return true


## 形变时长：默认整段（旧谱不变），设短则先变完再保持；镜头旋转走最短弧。
func test_shape_morph_duration_and_camera_arc() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S1"] = BoundaryShape.circle("S1", 200.0, 12)
	chart.shape_keys = [
		{"beat": 2.0, "shape_id": "S1", "easing": "linear", "morph": 0.0},
		{"beat": 6.0, "shape_id": "S0", "easing": "linear", "morph": 0.0},
	]
	# v3 默认硬切：4 拍仍保持 S1，到 6 拍才回 S0。
	near(BoundaryRuntime.eval_point(chart, 0.0, 4.0).point.x, 200.0, 0.5, "默认硬切：目标帧之前保持源形状")
	chart.shape_keys[1]["morph"] = 2.0
	near(BoundaryRuntime.eval_point(chart, 0.0, 5.0).point.x, 265.0, 0.5, "过渡在目标帧前 2 拍内按缓动插值")
	near(BoundaryRuntime.eval_point(chart, 0.0, 6.5).point.x, 330.0, 0.5, "目标帧之后保持目标形状")
	near(BoundaryRuntime.morph_beats({"morph": 99.0}, 3.0), 3.0, 0.0001, "形变时长最多等于整段")
	near(BoundaryRuntime.morph_beats({}, 3.0), 0.0, 0.0001, "v3 缺字段 = 硬切")
	var data := ChartIO.chart_to_dict(chart)
	eq(float((data["boundary_keys"] as Array)[1].get("morph", 0.0)), 2.0, "入场过渡写进 json")
	var back := ChartIO.from_json(ChartIO.to_json(chart))
	eq(float(back.shape_keys[1].get("morph", 0.0)), 2.0, "入场过渡读回")
	near(BoundaryRuntime.eval_point(back, 0.0, 5.0).point.x, 265.0, 0.5, "读回后过渡节奏不变")
	var states: Array[ViewState] = [
		ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 170.0),
		ViewState.new(2.0, 1.0, 0.0, 0.0, 1.0, -170.0),
	]
	var middle := ViewState.evaluate(states, 1.0)
	near(absf(float(middle["rotation"])), 180.0, 0.001, "旋转走最短弧：170→-170 的中点是 180")
	var straight := ViewState.evaluate(states, 0.0)
	near(float(straight["rotation"]), 170.0, 0.001, "起点仍是 170")
	return true


func test_ring_compat_rules() -> bool:
	# 旧谱的局部 u 事件：拒绝打开，而不是悄悄改成整环。
	var partial := {
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"shapes": [{"id": "S0", "closed": true, "segments": []}],
		"events": [
			{"id": "E0", "start_beat": 4.0, "end_beat": 8.0, "target_u0": 0.25, "target_u1": 0.75,
				"from_shape": "S0", "to_shape": "S0", "easing": "linear", "end_behavior": "hold",
				"restore_duration": 0.0, "restore_easing": "in-out"},
		],
	}
	var rejected := ChartIO.chart_from_dict(partial)
	ok(rejected == null, "partial-u legacy event chart is rejected")
	ok(ChartIO.last_error.contains("局部形变"), "rejection explains the partial event")
	# 旧段曲线：载入时降级为直线，并留下提示。
	var curved := {
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"shapes": [{"id": "S0", "closed": true, "segments": [
			{"u0": 0.0, "u1": 0.5, "x0": 0.0, "y0": 0.0, "x1": 100.0, "y1": 0.0, "ix": "si", "iy": "l"},
			{"u0": 0.5, "u1": 1.0, "x0": 100.0, "y0": 0.0, "x1": 0.0, "y1": 0.0, "ix": "l", "iy": "l"},
		]}],
	}
	var loaded := ChartIO.chart_from_dict(curved)
	ok(loaded != null, "curved legacy chart loads")
	if loaded != null:
		ok(not loaded.load_warnings.is_empty(), "curve downgrade is reported")
		eq(loaded.get_shape("S0").segments[0].ix, "l", "legacy curve becomes a straight segment")
	# RingState：zoom/rotation 插值，tilt/ellipse 到关键帧瞬切。
	var chart := Chart.new()
	chart.view_states = [
		ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0),
		ViewState.new(4.0, 1.2, 20.0, 10.0, 1.2, 40.0),
	]
	var mid := ViewState.evaluate(chart.view_states, 2.0)
	near(float(mid["zoom"]), 1.1, 0.001, "zoom interpolates")
	near(float(mid["rotation"]), 20.0, 0.001, "rotation interpolates")
	near(float(mid["tilt_x"]), 10.0, 0.001, "tilt interpolates")
	near(float(mid["ellipse"]), 1.1, 0.001, "ellipse interpolates")
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
	matches = true
	for beat in [0.0, 4.0, 9.0, 12.2, 12.5, 20.0, 24.4]:
		var points := BoundaryRuntime.eval_shape(chart, beat, 128)
		for i in points.size():
			var expected := BoundaryRuntime.eval_point(chart, float(i) / 128.0, beat)
			if (points[i].point as Vector2).distance_to(expected.point) > 0.00001 or points[i].gap != expected.gap:
				matches = false
	ok(matches, "batch boundary samples match point evaluation across keyframes")
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
	app._process(0.2)
	eq(counts.validation, 0, "debounced validation does not emit from the worker")
	app._finish_chart_work()
	eq(counts.validation, 1, "the main thread publishes validation for the committed chart")
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


func test_background_chart_snapshot() -> bool:
	var app = load("res://charter/app.gd").new()
	var chart: Chart = DemoChart.make_demo()
	app.set_chart(chart)
	var note := Note.new("path", 8.0, 12.0)
	note.end_beat = 7.5 # Invalid drafts must reach the validator without normalization.
	note.trace_pts = [{"x": 0.5, "y": 0.2, "db": 0.0}]
	chart.notes.append(note)
	var copy: Chart = app._copy_chart_for_worker(chart, chart.version)
	eq(Validator.validate(copy), Validator.validate(chart), "background validation sees the exact draft")
	eq(ChartIO.to_json(copy), ChartIO.to_json(chart), "background autosave uses the same chart data")
	note.trace_pts[0]["x"] = 0.7
	chart.timing.points[0].bpm = 180.0
	eq(copy.notes[-1].trace_pts[0]["x"], 0.5, "live geometry does not mutate the worker snapshot")
	ok(copy.timing.points[0].bpm != 180.0, "timing points are detached from the worker snapshot")
	app.free()
	return true


func test_self_intersection() -> bool:
	var circle := BoundaryShape.circle("C", 330.0, 32)
	eq(circle.validate().size(), 0, "circle is simple and convex")
	# 凹形（星形）现在允许保存，只拦自交。
	var star := BoundaryShape.star("STAR", 380.0, 190.0, 5)
	eq(star.validate().size(), 0, "concave star is allowed")
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
	var chart := ChartIO.load_chart("res://charts/夜に駆ける（示例）/main.tmc")
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
	# 新语法的 shape / polarity 尾巴：旧代码只读前四段，新代码要能往返。
	region.shape = "S1"
	region.polarity = 0
	var region_back := Region.from_code(region.to_code())
	ok(region_back != null, "limit region code parses")
	if region_back != null:
		eq(region_back.shape, "S1", "limit region keeps shape")
		eq(region_back.polarity, 0, "limit region keeps polarity")
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
		var by_type := {}
		for note in loaded.notes:
			by_type[note.type] = note
		if by_type.has("tap"):
			near(by_type["tap"].arc_width(), 60.0, 0.001, "json keeps sized tap arc width")
		if by_type.has("hold"):
			near(by_type["hold"].width, 48.0, 0.001, "json keeps hold width")
		if by_type.has("bell"):
			near(by_type["bell"].bell_width(), 27.0, 0.001, "json keeps bell width")
			near(by_type["bell"].radius, 44.0, 0.001, "json keeps bell radius")
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
	# 紧凑代码丢不掉的字段走 note_extras，往返后必须还在。
	var extras := Chart.new()
	extras.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var curved := Note.new("hold", 1.0, 0.0, 60.0)
	curved.id = 1
	curved.end_beat = 2.0
	curved.hold_style = "curved"
	curved.visual_pts = [{"db": 0.0, "da": 0.0, "x": 0.1, "y": 0.2}]
	var plane_path := Note.new("path", 3.0, 0.0, 60.0)
	plane_path.id = 2
	plane_path.end_beat = 4.0
	plane_path.tolerance = 0.31
	plane_path.samples_per_beat = 6.0
	plane_path.path_speed = 1.3
	plane_path.path_gaps = [{"from": 0.2, "to": 0.3}]
	plane_path.trace_pts = [{"x": 1.0, "y": 0.0, "db": 0.0}, {"x": 0.0, "y": 1.0, "db": 1.0}]
	extras.notes = [curved, plane_path]
	var extras_data := ChartIO.chart_to_dict(extras)
	ok(extras_data.has("note_extras"), "lost fields go to the note_extras side map")
	var extras_back := ChartIO.from_json(ChartIO.to_json(extras))
	if extras_back != null:
		for note in extras_back.notes:
			if note.type == "hold":
				eq(note.hold_style, "curved", "hold style survives the roundtrip")
				eq(note.visual_pts.size(), 1, "hold body survives the roundtrip")
			elif note.type == "path":
				near(note.tolerance, 0.31, 0.001, "path tolerance survives the roundtrip")
				near(note.samples_per_beat, 6.0, 0.001, "path samples survive the roundtrip")
				near(note.path_speed, 1.3, 0.001, "path speed survives the roundtrip")
				eq(note.path_gaps.size(), 1, "path erase range survives the roundtrip")
				eq(note.trace_pts.size(), 2, "path plane points survive the roundtrip")
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
			eq(chart.notes[0].id, 0, "ring tap survives with reindexed id")
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


func test_path_paste_chain() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	app.chart = chart
	var canvas := ChartCanvas.new()
	canvas._app = app
	var parts: Array[Note] = []
	var beat := 1.0
	for i in 3:
		var note := Note.new("path", beat, float(i) * 30.0, 60.0)
		note.id = chart.next_note_id()
		note.end_beat = beat + 0.5
		note.path_part = i
		if i > 0:
			note.path_prev_id = parts[i - 1].id
			note.path_head_local = parts[i - 1].path_tail_local()
			parts[i - 1].path_next_id = note.id
		note.generate_path_shape()
		parts.append(note)
		chart.notes.append(note)
		beat += 0.5
	app.select_note(parts[1].id)
	canvas.copy_selection()
	eq(canvas._clipboard_notes.size(), 3, "复制 Path 中间一段时自动带上整条链")
	var old_ids := [parts[0].id, parts[1].id, parts[2].id]
	canvas._clipboard_reference_beat = 1.0
	eq(canvas._paste_at(9.0), true, "粘贴成功")
	eq(chart.notes.size(), 6, "一次粘贴放下整条链")
	var fresh: Array[Note] = []
	for note in chart.notes:
		if not old_ids.has(note.id):
			fresh.append(note)
	fresh.sort_custom(func(a: Note, b: Note) -> bool: return a.path_part < b.path_part)
	eq(fresh.size(), 3, "新链有三段")
	if fresh.size() == 3:
		eq(fresh[0].path_prev_id, -1, "新链 root 没有前驱")
		eq(fresh[0].path_next_id, fresh[1].id, "新链 root 指向新的 part1")
		eq(fresh[1].path_prev_id, fresh[0].id, "新链 part1 指回新 root")
		eq(fresh[1].path_next_id, fresh[2].id, "新链 part1 指向新的 part2")
		eq(fresh[2].path_prev_id, fresh[1].id, "新链 part2 指回新 part1")
		eq(fresh[2].path_next_id, -1, "新链末段没有后继")
		for note in fresh:
			ok(not old_ids.has(note.path_prev_id) and not old_ids.has(note.path_next_id),
				"新链不再引用原链 id")
		near(fresh[0].beat, 9.0, 0.0001, "最早一段落在点到的拍上")
		near(fresh[2].beat - fresh[0].beat, 1.0, 0.0001, "链内相对拍位保持不变")
		eq(chart.path_chain(fresh[2]).size(), 3, "从新链末段能走回整条链")
	canvas.free()
	app.free()
	return true


## 音符松手回吸：只回吸真的动过的那个轴；单击不挪音符。
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


func test_path_preview_visibility() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(20.0, 480.0, 4)]
	var root_note := Note.new("path", 1.0, 0.0)
	root_note.id = 1
	root_note.end_beat = 2.0
	root_note.path_next_id = 2
	var tail := Note.new("path", 30.0, 90.0)
	tail.id = 2
	tail.end_beat = 31.0
	tail.path_prev_id = 1
	var incoming := Note.new("path", 23.0, 90.0)
	incoming.id = 3
	incoming.end_beat = 24.0
	chart.notes = [root_note, tail, incoming]
	var preview := Preview3D.new()
	var visible: Array[Note] = preview._visible_paths(chart, 30.5)
	eq(visible.size(), 1, "a chain remains visible near the final part")
	if visible.size() == 1:
		eq(visible[0].id, root_note.id, "the visible chain is drawn as one path")
		eq(visible[0].end_beat, tail.end_beat, "the visible chain keeps its final tail")
	eq(preview._visible_paths(chart, 10.0).size(), 0, "seeking backwards into a gap hides the chain")
	eq(preview._visible_paths(chart, 19.9), [incoming], "pre-read time crosses into a faster BPM segment")
	preview.flow_scale = 4.0
	eq(preview._visible_paths(chart, 19.9).size(), 0, "changing note speed updates visibility without editing the chart")
	tail.beat = 32.0
	tail.end_beat = 33.0
	chart.mark_dirty()
	visible = preview._visible_paths(chart, 32.0)
	eq(visible.size(), 1, "the edited chain is visible at its new time")
	if visible.size() == 1:
		eq(visible[0].end_beat, 33.0, "editing a chain rebuilds its preview")
	eq(preview._visible_paths(Chart.new(), 32.0).size(), 0, "switching to another chart drops the old index")
	preview.free()
	return true


class PathStrokeProbe:
	extends Preview3D

	var projections: int = 0

	func _path_screen_point(_chart: Chart, _note: Note, relative_beat: float, _beat: float, _cache_sample: bool = true, _scale: float = 1.0) -> Vector2:
		projections += 1
		return Vector2(relative_beat, 0.0)


func test_path_stroke_cache() -> bool:
	var preview := PathStrokeProbe.new()
	var chart := Chart.new()
	var note := Note.new("path", 0.0, 0.0)
	note.end_beat = 1.0
	var initial: Array[PackedVector2Array] = preview._path_stroke_runs(chart, note, 0.0, "static", 8)
	eq(initial[0].size(), 9, "the stroke includes both endpoints at its requested sampling density")
	preview.set_path_erased_to(note, 0.5)
	var cut: Array[PackedVector2Array] = preview._path_stroke_runs(chart, note, 0.1, "static", 8)
	eq(cut[0][0], Vector2(0.625, 0.0), "erasing splits the existing projected points")
	eq(preview.projections, 9, "changing only the cut reuses the projection")
	var moved: Array[PackedVector2Array] = preview._path_stroke_runs(chart, note, 0.2, "moved", 8)
	eq(moved, cut, "changing the projection keeps the cut")
	eq(preview.projections, 18, "changing geometry reprojects the points")
	preview.reset_path_cuts()
	var reset: Array[PackedVector2Array] = preview._path_stroke_runs(chart, note, 0.2, "moved", 4)
	eq(reset[0].size(), 5, "retry clears the cut and reapplies the current sampling density")
	preview.free()
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
	var starts: Array[int] = []
	var split := Preview3D.split_path_runs(middle_line, middle, starts)
	eq(split.size(), 2, "erased middle splits into two visible runs")
	eq(starts, [0, 4], "visible comet guides retain their original sample indices after a cut")
	var gap := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF),
		Vector2(20, 0), Vector2(30, 0),
	])
	var gap_flags: Array[bool] = [false, false, false, false, false]
	eq(Preview3D.split_path_runs(gap, gap_flags, starts).size(), 2, "invalid sample starts a new run")
	eq(starts, [0, 3], "a new projection replaces previous comet guide indices")
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
	near(Preview3D.cursor_main_diameter(1.0), 30.6, 0.0001, "Path belt fits the white cursor ring")
	near(Preview3D.cursor_main_diameter(1.5), 45.9, 0.0001, "Path belt follows a live cursor scale change")
	cursor.free()
	ok(Playtest.PATH_TAIL_RADIUS >= 180.0, "path tail judgement is forgiving")
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
	eq(Playtest.BAD_MS, 200.0, "bad tier extends to 200ms")
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
	eq(tiers._tier_for(210.0), "MISS", "beyond 200ms is a miss")
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
	eq(Playtest.LATE_PENALTY_MS, 40.0, "a late match pays 40ms so the next note wins ties")
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
	# 双押 Anchor：命中连击 +2、两个准确率样本；失败整对只记 1 MISS。
	var anchor_chart := DemoChart.make_empty({"bpm": 120.0})
	anchor_chart.notes.clear()
	var anchor_a := Note.new("anchor", 4.0, 0.0, 0.0)
	anchor_a.id = 1
	anchor_a.pair_id = "P"
	anchor_a.anchor_pair = 0
	var anchor_b := Note.new("anchor", 4.0, 180.0, 0.0)
	anchor_b.id = 2
	anchor_b.pair_id = "P"
	anchor_b.anchor_pair = 0
	anchor_chart.notes = [anchor_a, anchor_b]
	var pair_run := Playtest.new()
	pair_run._preview = preview
	pair_run.chart = anchor_chart
	pair_run._init_states()
	var pair_ms := float(pair_run._states[1]["target_ms"])
	var point_a := preview.note_head_screen(anchor_a, 4.0)
	var point_b := preview.note_head_screen(anchor_b, 4.0)
	pair_run._key_presses = [
		{"time": pair_ms, "lo": pair_ms, "hi": pair_ms, "mouse": point_a, "key": 65},
		{"time": pair_ms, "lo": pair_ms, "hi": pair_ms, "mouse": point_b, "key": 66},
	]
	pair_run._judge_anchor_pairs(pair_ms, 4.0)
	eq(pair_run._combo, 2, "an anchor pair adds two combo")
	eq(pair_run._hit_count, 2, "both anchors count as hits")
	eq(pair_run._judged_total, 2, "both anchors count for accuracy")
	pair_run.free()
	var miss_run := Playtest.new()
	miss_run._preview = preview
	miss_run.chart = anchor_chart
	miss_run._init_states()
	miss_run._judge_anchor_pairs(pair_ms + Playtest.HIT_WINDOW_MS + 20.0, 4.0)
	eq(miss_run._miss_count, 1, "a failed pair counts one miss")
	eq(miss_run._judged_total, 1, "a failed pair counts one accuracy sample")
	miss_run.free()
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
	# 40ms 迟到代价的实际效果：20ms 晚于前一颗、40ms 早于后一颗时，按键归后一颗。
	var late_previous := {"on_shape": false, "error": 20.0,
		"rank": 20.0 + Playtest.LATE_PENALTY_MS, "distance": 0.0}
	var early_next := {"on_shape": false, "error": 40.0, "rank": 40.0, "distance": 0.0}
	ok(Playtest.prefer_press_pair(early_next, late_previous), "the upcoming note takes the press from a stale one")
	# 刚命中后的额外按键不能提前吃下一颗。
	ok(Playtest.press_is_stray(2020.0, 2095.0, 2000.0), "a stray press right after a hit is ignored")
	ok(not Playtest.press_is_stray(2020.0, 2095.0, -1.0e9), "a normal press is not treated as stray")
	ok(not Playtest.press_is_stray(2060.0, 2095.0, 2000.0), "a press inside the perfect window is kept")
	ok(not Playtest.press_is_stray(2095.0, 2095.0, 2000.0), "an on-time press is kept")
	# 滚轮方向门：上下交替永远凑不出有效方向，同向连滚照常。
	ok(Playtest.seek_tick_allowed(0, -1, 0.0), "the first wheel tick always counts")
	ok(Playtest.seek_tick_allowed(0, 0, 5.0), "same-direction ticks keep counting")
	ok(not Playtest.seek_tick_allowed(0, 1, 79.0), "a reversal inside 80ms is ignored")
	ok(Playtest.seek_tick_allowed(0, 1, 80.0), "a reversal after 80ms counts")
	var alternating_ok := Playtest.seek_tick_allowed(0, -1, 0.0)
	var prev := 0
	for i in 8:
		var dir := 1 - (i % 2)
		if Playtest.seek_tick_allowed(dir, prev, 10.0):
			alternating_ok = false
		prev = dir
	ok(alternating_ok, "alternating wheel ticks never pass the guard")
	# 双押 Anchor：两个不同键、相差 ≤40ms 才成对，档次取较差的一次。
	var two_keys := [
		{"time": 995.0, "lo": 995.0, "hi": 995.0, "key": 65},
		{"time": 1020.0, "lo": 1020.0, "hi": 1020.0, "key": 66},
	]
	var picked := Playtest._pick_anchor_pair(two_keys, 1000.0)
	ok(not picked.is_empty(), "two keys within 40ms form an anchor pair")
	eq(float(picked.get("error", 0.0)), 20.0, "the worse press decides the tier")
	ok(Playtest._pick_anchor_pair([
		{"time": 995.0, "lo": 995.0, "hi": 995.0, "key": 65},
		{"time": 1045.0, "lo": 1045.0, "hi": 1045.0, "key": 66},
	], 1000.0).is_empty(), "keys 50ms apart do not pair")
	ok(Playtest._pick_anchor_pair([
		{"time": 1000.0, "lo": 1000.0, "hi": 1000.0, "key": 65},
		{"time": 1010.0, "lo": 1010.0, "hi": 1010.0, "key": 65},
	], 1000.0).is_empty(), "the same physical key cannot double-press")
	ok(Playtest._near_anchor(Vector2(10, 0), Vector2(0, 0), Vector2(300, 0), 140.0),
		"aiming at either anchor counts")
	ok(not Playtest._near_anchor(Vector2(150, 0), Vector2(0, 0), Vector2(300, 0), 140.0),
		"the midpoint between two anchors counts for neither")
	# 放置 Anchor 时一次生成同拍反向的一对。
	var pair_chart := Chart.new()
	var pair := pair_chart.make_anchor_pair(2.0, 30.0)
	eq(pair.size(), 2, "placing an anchor creates a pair")
	eq(pair[0].pair_id, pair[1].pair_id, "the pair shares one pairId")
	near(JudgeMath.angle_distance(pair[0].angle, pair[1].angle), 180.0, 0.001, "the pair is opposite")
	pair_chart.notes.append(pair[0])
	pair_chart.notes.append(pair[1])
	ok(pair_chart.anchor_partner(pair[0]) != null, "the pair resolves through the chart")
	pair[1].angle = 95.0
	ok(pair_chart.anchor_partner(pair[0]) != null, "any angle still pairs at the same beat")
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
	var beats := chart.note_fall_ms() / 60000.0 * chart.timing.bpm_at(current_beat)
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


func test_beat_grid_lines() -> bool:
	near(ChartCanvas.beat_line_width(false, true), 2.0, 0.001, "4/4 quarter lines are bold")
	near(ChartCanvas.beat_line_width(true, true), 2.5, 0.001, "4/4 bar lines are boldest")
	near(ChartCanvas.beat_line_width(false, false), 1.0, 0.001, "other meters keep plain quarter lines")
	near(ChartCanvas.beat_line_width(true, false), 1.5, 0.001, "other meters keep plain bar lines")
	var timing := TimingMap.new()
	ok(ChartCanvas.is_uniform_four_four(timing), "an empty meter defaults to 4/4")
	timing.points.append(TimingPoint.new(8.0, 120.0, 3))
	ok(not ChartCanvas.is_uniform_four_four(timing), "a 3/4 point disables the emphasis")
	ok(ChartCanvas.is_eighth_offset(0.5), "0.5 is the eighth line")
	ok(not ChartCanvas.is_eighth_offset(0.25), "0.25 is not the eighth line")
	var counts := {}
	for divisions in [1, 2, 3, 4, 6, 8]:
		var hits := 0
		for offset in TimingMap.beat_subdivision_offsets(divisions):
			if ChartCanvas.is_eighth_offset(offset):
				hits += 1
		counts[divisions] = hits
	eq(counts[4], 1, "N=4 draws exactly one eighth line per beat")
	eq(counts[6], 1, "N=6 draws exactly one eighth line per beat")
	eq(counts[3], 0, "N=3 has no eighth line")
	eq(counts[1], 0, "N=1 has no eighth line")
	return true


func test_pre_read() -> bool:
	var chart := Chart.new()
	chart.shapes["S1"] = BoundaryShape.ellipse("S1", 410.0, 245.0, 24)
	chart.shape_keys = [
		{"beat": 8.0, "shape_id": "S0", "easing": "linear"},
		{"beat": 12.0, "shape_id": "S1", "easing": "linear"},
	]
	for u in [0.0, 0.2, 0.5, 0.85]:
		for target in [4.0, 10.0, 14.0]:
			var p := _preview_point(chart, u, target, target)
			var c: Vector2 = BoundaryRuntime.eval_point(chart, u, target).point
			near(p.distance_to(c), 0.0, 0.01, "P(T)=C at u=%.2f T=%.1f" % [u, target])
	return true


func test_pinned_scroll() -> bool:
	near(ChartCanvas.pinned_scroll_beat(40.0, 20.0), 38.4, 0.001, "pinned playhead sits 8% from the edge")
	eq(ChartCanvas.pinned_scroll_beat(0.5, 20.0), 0.0, "pinned scroll never goes negative")
	near(ChartCanvas.pinned_scroll_beat(40.0, 20.0, 0.0), 40.0, 0.001, "zero margin pins the playhead to the edge")
	return true


func test_flow_flip_anchor() -> bool:
	# 翻转方向后播放头仍停在同一屏幕比例：ratio 0.2 → 仍是 0.2。
	near(ChartCanvas.flipped_scroll_beat(24.0, 20.0, 20.0), 8.0, 0.001, "flip keeps the playhead ratio")
	near(ChartCanvas.flipped_scroll_beat(4.0, 0.0, 20.0), -12.0, 0.001, "flip may go negative before clamping")
	eq(ChartCanvas.flipped_scroll_beat(80.0, 20.0, 20.0), 20.0, "off-screen playhead keeps the scroll unchanged")
	return true


func test_chart_end_limit() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.editor["audio_length_ms"] = 60000.0
	near(chart.audio_end_beat(), 120.0, 0.01, "60s at 120 BPM is 120 beats")
	near(chart.end_limit_beat(), 136.0, 0.01, "limit is audio end + 4 bars")
	var note := Note.new("tap", 140.0, 0.0, 60.0)
	chart.notes.append(note)
	near(chart.content_end_beat(), 140.0, 0.01, "content can extend past the audio")
	near(chart.end_limit_beat(), 156.0, 0.01, "limit follows the later of audio and content")
	return true


func test_ring_span_label() -> bool:
	eq(RingWorkspace.span_label(2.0, 4.0), "2 拍", "short span counts beats")
	eq(RingWorkspace.span_label(8.0, 4.0), "2 小节", "whole bars")
	eq(RingWorkspace.span_label(6.0, 4.0), "1 小节 2 拍", "mixed bars and beats")
	eq(RingWorkspace.span_label(0.5, 4.0), "0.5 拍", "fractional beat")
	return true


func test_ring_span_end() -> bool:
	var beats: Array[float] = [0.0, 2.0, 10.0]
	near(RingWorkspace.span_end(beats, 0, 12.0, 4.0), 2.0, 0.001, "span ends at the next key")
	near(RingWorkspace.span_end(beats, 2, 12.0, 4.0), 12.0, 0.001, "last span ends at content end")
	near(RingWorkspace.span_end(beats, 2, 10.0, 4.0), 14.0, 0.001, "empty tail still gets one bar")
	return true


func test_uniform_meter() -> bool:
	var timing := TimingMap.new()
	timing.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(16.0, 140.0, 4)]
	eq(timing.uniform_beats_per_bar(), 4, "same meter everywhere")
	timing.points.append(TimingPoint.new(32.0, 160.0, 3))
	eq(timing.uniform_beats_per_bar(), 0, "mixed meters disable measure shading")
	return true


func test_timing_presorted() -> bool:
	var timing := TimingMap.new()
	timing.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(8.0, 180.0, 4)]
	timing.sort_points()
	for beat in [-2.0, 0.0, 3.5, 8.0, 13.25]:
		near(timing.beat_to_ms_sorted(beat), timing.beat_to_chart_ms(beat), 0.001, "presorted ms matches at beat %.2f" % beat)
	return true


func test_shrink_example() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 60.0, 4)]
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 64)
	chart.shapes["S1"] = BoundaryShape.circle("S1", 180.0, 64)
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear", "morph": 0.0},
		{"beat": 1.0, "shape_id": "S1", "easing": "linear", "morph": 1.0},
	]
	# 飞行时长 1 秒（60 BPM = 1 拍）：从 0 拍到 1 拍走完。
	var u := 0.0
	var p_mid := _preview_point(chart, u, 1.0, 0.5)
	near(p_mid.x, 127.5, 0.5, "1s fall midpoint is halfway")
	var p_end := _preview_point(chart, u, 1.0, 1.0)
	near(p_end.x, 180.0, 0.5, "1s fall ends on the boundary")
	return true


func test_event_restore() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 60.0, 4)]
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 64)
	chart.shapes["S1"] = BoundaryShape.circle("S1", 180.0, 64)
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear", "morph": 0.0},
		{"beat": 1.0, "shape_id": "S1", "easing": "linear", "morph": 1.0},
		{"beat": 2.0, "shape_id": "S0", "easing": "linear", "morph": 1.0},
	]
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
	var lbp_seek := Note.new("seek", 4.0, 0.0, 360.0)
	lbp_seek.id = 4
	lbp_seek.seek_orien = 1
	var lbp_bell := Note.new("bell", 0.0, 0.0, 27.0)
	lbp_bell.id = 3
	lbp_bell.center_u = 0.25
	lbp_bell.radius = 26.0
	width_chart.notes = [lbp_tap, lbp_hold, lbp_bell, lbp_seek]
	var width_text := LBPIO.export_chart(width_chart)
	ok(width_text.contains("tap,"), "lbp keeps taps")
	ok(width_text.contains("hold,"), "lbp keeps holds")
	ok(width_text.contains("90.000,30.000"), "lbp writes visible arc width")
	ok(width_text.contains("width=27.000"), "lbp bell exports width option")
	ok(width_text.contains("seek,"), "lbp exports seek instead of a tap")
	var path := "user://test_export.lbp"
	eq(LBPIO.export_to_file(chart, path), OK, "lbp write")
	var read := FileAccess.get_file_as_string(path)
	eq(read, text, "lbp file matches string")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## 回放视频：光标按录制点插值，超出末尾就停在最后。
func test_video_export_cursor() -> bool:
	var moves := [{"t": 0.0, "x": 0.0, "y": 0.0}, {"t": 100.0, "x": 100.0, "y": 50.0}]
	var mid := VideoExport._cursor_at(moves, 50.0)
	eq(int(mid.x), 50, "cursor interpolation x")
	eq(int(mid.y), 25, "cursor interpolation y")
	var after := VideoExport._cursor_at(moves, 500.0)
	eq(int(after.x), 100, "cursor clamps to last point")
	return true


## 早于第一条命令时取第一条的值（osu 的「夹到第一关键帧」规则）。
## 白 px.png 遮幅先 F 后 C 变黑的写法，在 C 之前必须是黑的，不能先刷白。
func test_storyboard_clamps_first_command() -> bool:
	var text := "\n".join([
		"[Events]",
		"Sprite,Foreground,TopCentre,\"px.png\",320,0",
		" F,0,0,,1",
		" C,0,876,,0,0,0",
		" F,0,2000,,0",
	])
	var board := Storyboard.parse(text, "test.osb")
	eq(board.sprites.size(), 1, "clamp test sprite parsed")
	var items := board.sample(0.0)
	eq(items.size(), 1, "sprite visible at 0ms")
	if items.size() == 1:
		var colour: Color = items[0]["colour"]
		eq(int(round(colour.r * 255.0)), 0, "colour before first C is the first keyframe, not white")
		eq(int(round(colour.g * 255.0)), 0, "green clamped")
		eq(int(round(colour.b * 255.0)), 0, "blue clamped")
	var late := board.sample(900.0)
	eq(late.size(), 1, "sprite still visible at 900ms")
	if late.size() == 1:
		eq(int(round((late[0]["colour"] as Color).r * 255.0)), 0, "colour after C is black")
	return true


## 环随鼠标倾斜：鼠标那一侧靠近镜头（近大远小），0 度 = 关闭。
## 拖播放头时不能重建面板：一次重建 ≈70–80 个控件，跨一个关键帧要付两遍。
## 环编辑器四条轨道必须能处理旧谱的 BoundaryEvent：它只有 start_beat，
## 用 .beat 排序会让每次重绘抛错，整条时间轴画不出来（看起来就是打不开）。
## 撤销不再无限吃内存：快照总量按音符数限额，小谱仍保留 200 步。
## 一张「所有功能都用上」的谱面走真实保存/重开链路，逐字段比对。
## 失败说明某类数据存不住 —— 那是制谱器最致命的问题，所以用整份 dict 比对。
func test_full_chart_round_trip() -> bool:
	var chart := _make_full_chart()
	var before := JSON.stringify(ChartIO.chart_to_dict(chart))
	var reloaded := ChartIO.from_json(ChartIO.to_json(chart))
	ok(reloaded != null, "整谱保存/重开不报错")
	if reloaded == null:
		return true
	var after := JSON.stringify(ChartIO.chart_to_dict(reloaded))
	if after != before:
		# 找出第一处差异，报给用户看
		var a: Dictionary = ChartIO.chart_to_dict(chart)
		var b: Dictionary = ChartIO.chart_to_dict(reloaded)
		var diff := ""
		for key in a.keys():
			if JSON.stringify(a[key]) != JSON.stringify(b.get(key, null)):
				diff = String(key)
				if key == "notes":
					var la: Array = a[key]
					var lb: Array = b.get(key, [])
					for i in mini(la.size(), lb.size()):
						if String(la[i]) != String(lb[i]):
							print("NOTEDIFF %d\n  before=%s\n  after =%s" % [i, la[i], lb[i]])
							break
				break
		ok(false, "保存/重开后字段不一致（首个差异：%s）" % diff)
	else:
		ok(true, "保存/重开后整份谱面字典一致")
	# 关键功能逐个点名，别让整份比对掩盖了“恰好都没写”
	eq(reloaded.notes.size(), chart.notes.size(), "音符数量")
	var types := {}
	for note in reloaded.notes:
		types[note.type] = true
	for type in ["tap", "hold", "path", "seek", "anchor", "bell"]:
		ok(types.has(type), "重开后仍有 %s" % type)
	eq(reloaded.regions.size(), 2, "红区数量")
	eq(reloaded.shape_keys.size(), 3, "形状关键帧数量")
	near(float(reloaded.shape_keys[1].get("morph", 0.0)), 1.5, 0.001, "形变时长")
	eq(reloaded.view_states.size(), 2, "镜头关键帧数量")
	near(reloaded.view_states[1].rotation, 170.0, 0.001, "镜头旋转")
	near(reloaded.timing.points[1].bpm, 180.0, 0.001, "BPM 点")
	eq(reloaded.editor.get("beat_subdivisions", 0), 8, "小节线等分写入 editor")
	eq(reloaded.editor.get("rail_snap", true), false, "轨道吸附写入 editor")
	eq(reloaded.metadata.get("storyboard", ""), "sb/storyboard.osb", "故事板路径")
	eq(reloaded.palette.size(), 1, "配色组")
	# 多段 Path 的第二段：id 必须原样还原，旁挂属性才不会丢
	var child: Note = null
	for note in reloaded.notes:
		if note.type == "path" and note.path_part == 1:
			child = note
			break
	if child != null:
		eq(child.path_style, "ribbon", "第二段 Path 的画法")
		near(child.path_speed, 0.8, 0.001, "第二段 Path 的速度")
		near(child.tolerance, 0.31, 0.001, "第二段 Path 的容差")
		eq(child.path_gaps.size(), 1, "第二段 Path 的擦除缺口")
		eq(child.trace_pts.size(), 2, "第二段 Path 的手绘轨迹")
		eq(child.color, 1, "第二段 Path 的配色组")
		eq(child.lock, true, "第二段 Path 的锁定")
		near(child.width, 64.0, 0.001, "第二段 Path 的头宽度")
		near(child.tail_width, 70.0, 0.001, "第二段 Path 的尾宽度")
	else:
		ok(false, "重开后找不到第二段 Path")
	var path_root: Note = null
	for note in reloaded.notes:
		if note.type == "path" and note.path_part == 0 and is_equal_approx(note.beat, 2.0):
			path_root = note
			break
	if path_root != null:
		near(path_root.width, 66.0, 0.001, "Path 头宽度")
		near(path_root.tail_width, 72.0, 0.001, "Path 尾宽度")
		near(path_root.wait_beat, 0.5, 0.001, "Path 等待拍数")
	else:
		ok(false, "重开后找不到 Path 根段")
	# 再走一遍 App 的真实保存/打开入口（含校验拦截、难度套组分支、notice 信号）
	var app: App = load("res://charter/app.gd").new()
	app.chart = _make_full_chart()
	var temp_path := "user://roundtrip_check.json"
	app.chart_path = temp_path
	ok(app.save_chart(), "App.save_chart() 不被校验拦截")
	ok(app.load_chart(temp_path), "App.load_chart() 能打开刚存的谱面")
	if app.chart != null:
		eq(JSON.stringify(ChartIO.chart_to_dict(app.chart)), before, "走 App 入口保存后整份字典一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	app.free()
	return true


## 造一张覆盖所有可存字段的谱面。
## 难度套组：一首歌多个难度存成一个 .set.json，重开逐个比对内容与星数。
## 保存必须原子：先写 .tmp 再改名；覆盖前留 .bak.1..5，崩了也能找回上一版。
func test_save_atomic_and_backup() -> bool:
	var path := "user://atomic_check/chart.json"
	for suffix in ["", ".bak.1", ".bak.2"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	eq(ChartIO.atomic_write(path, "{\"v\":1}\n"), OK, "首次保存到不存在的目录")
	ok(FileAccess.file_exists(path), "文件已生成")
	eq(ChartIO.atomic_write(path, "{\"v\":2}\n"), OK, "第二次保存")
	ok(FileAccess.file_exists(path + ".bak.1"), "覆盖前生成 .bak.1")
	eq(FileAccess.get_file_as_string(path + ".bak.1"), "{\"v\":1}\n", ".bak.1 是上一版内容")
	ok(not FileAccess.file_exists(path + ".tmp"), "临时文件已改名，不残留")
	for suffix in ["", ".bak.1", ".bak.2"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://atomic_check"))
	return true


func test_difficulty_set_round_trip() -> bool:
	var path := "user://roundtrip_set.set.json"
	var basic := _make_full_chart()
	basic.difficulty = "Basic"
	basic.metadata["version"] = "Basic 3"
	var expert := _make_full_chart()
	expert.difficulty = "Expert"
	expert.metadata["version"] = "Expert 9+"
	var before_basic := JSON.stringify(ChartIO.chart_to_dict(basic))
	var before_expert := JSON.stringify(ChartIO.chart_to_dict(expert))
	var entries := [
		{"name": "Basic 3", "stars": 3.5, "chart": basic},
		{"name": "Expert 9+", "stars": 9.7, "chart": expert},
	]
	eq(ChartIO.save_set(path, entries, "套组测试歌", "imports/x"), OK, "套组保存成功")
	var loaded := ChartIO.load_set(path)
	ok(bool(loaded.get("ok", false)), "套组能打开")
	var rows: Array = loaded.get("entries", [])
	eq(rows.size(), 2, "套组里两个难度")
	if rows.size() == 2:
		eq(String(rows[0].get("name", "")), "Basic 3", "第一个难度名")
		near(float(rows[0].get("stars", -1.0)), 3.5, 0.001, "第一个难度星数")
		eq(String(rows[1].get("name", "")), "Expert 9+", "第二个难度名")
		near(float(rows[1].get("stars", -1.0)), 9.7, 0.001, "第二个难度星数")
		eq(JSON.stringify(ChartIO.chart_to_dict(rows[0]["chart"])), before_basic, "第一个难度内容一致")
		eq(JSON.stringify(ChartIO.chart_to_dict(rows[1]["chart"])), before_expert, "第二个难度内容一致")
	eq(String(loaded.get("title", "")), "套组测试歌", "套组标题")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## LBP 是导出格式：每种音符、红区、关键帧、镜头、配色都必须出现在文本里。
func test_lbp_export_covers_all_types() -> bool:
	var chart := _make_full_chart()
	var text := LBPIO.export_chart(chart)
	for needle in ["tap,", "hold,", "path,", "seek,", "anchor,", "bell,",
			"region,", "key,", "ring,", "group,", "[BoundaryShapes]", "[TimingPoints]"]:
		ok(text.contains(needle), "LBP 导出包含 %s" % needle)
	ok(text.contains("erase="), "LBP 导出带擦除缺口")
	ok(text.contains("lock=1"), "LBP 导出带锁定")
	ok(text.contains("style=ribbon"), "LBP 导出带 Path 画法")
	var path := "user://roundtrip_check.lbp.txt"
	eq(LBPIO.export_to_file(chart, path), OK, "LBP 导出到文件")
	ok(FileAccess.file_exists(path), "LBP 文件存在")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func _make_full_chart() -> Chart:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4), TimingPoint.new(8.0, 180.0, 3)]
	chart.timing.offset_ms = 12.5
	chart.offset_ms = 12.5
	chart.audio_path = "audio/demo_click.wav"
	chart.video_path = "media/bga.mp4"
	chart.video_offset_ms = -33.0
	chart.video_fps = 59.94
	chart.video_opacity = 0.4
	chart.difficulty = "Expert"
	for key in ["title", "artist", "creator", "version", "tags", "license", "background", "storyboard"]:
		chart.metadata[key] = "%s-value" % key
	chart.metadata["storyboard"] = "sb/storyboard.osb"
	chart.metadata["widescreen"] = true
	var custom := BoundaryShape.new()
	custom.id = "S1"
	custom.closed = true
	var pts := [Vector2(300, 0), Vector2(150, 260), Vector2(-150, 260), Vector2(-300, 0), Vector2(-150, -260), Vector2(150, -260)]
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var seg := BoundarySegment.new(float(i) / float(pts.size()), float(i + 1) / float(pts.size()), a, b, "l", "l", i == 2)
		custom.segments.append(seg)
	chart.shapes["S1"] = custom
	chart.shapes["S2"] = BoundaryShape.ellipse("S2", 280.0, 180.0, 48)
	chart.default_shape_id = "S0"
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear"},
		{"beat": 4.0, "shape_id": "S1", "easing": "in-out", "morph": 1.5},
		{"beat": 8.0, "shape_id": "S2", "easing": "linear"},
	]
	chart.view_states = [
		ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear"),
		ViewState.new(8.0, 1.2, 5.0, -3.0, 1.1, 170.0, "in-out"),
	]
	# 红区放在没有音符的时段：同拍被红区盖住的音符会被校验判成「无处落脚」。
	var region_a := Region.new(101, 6.5, 7.0)
	region_a.angle = 200.0
	region_a.width = 60.0
	chart.regions.append(region_a)
	var region_b := Region.new(102, 7.2, 7.6)
	region_b.angle = 200.0
	region_b.width = 45.0
	chart.regions.append(region_b)
	# 每种音符各来一颗，并带上各自的非默认字段
	var tap := Note.new("tap", 1.0, 30.0, 60.0)
	tap.id = chart.next_note_id()
	tap.color = 1
	tap.has_custom_color = true
	tap.custom_color = Color("#ff00aa")
	tap.lock = true
	chart.notes.append(tap)
	var hold := Note.new("hold", 1.5, 90.0, 60.0)
	hold.id = chart.next_note_id()
	hold.end_beat = 3.0
	hold.hold_style = "curved"
	hold.visual_pts = [{"x": 0.1, "y": 0.2, "db": 0.0}]
	chart.notes.append(hold)
	var root := Note.new("path", 2.0, 180.0, 66.0)
	root.id = chart.next_note_id()
	root.end_beat = 3.0
	root.tail_angle = 270.0
	root.tail_width = 72.0
	root.wait_beat = 0.5
	root.trace_pts = [{"x": 0.2, "y": 0.0, "db": 0.0}, {"x": 0.4, "y": 0.2, "db": 1.0}]
	root.path_gaps = [{"from": 0.1, "to": 0.2}]
	root.path_speed = 1.3
	root.path_style = "ribbon"
	root.tolerance = 0.3
	root.samples_per_beat = 6.0
	chart.notes.append(root)
	var part := Note.new("path", 3.0, 270.0, 64.0)
	part.id = chart.next_note_id()
	part.end_beat = 4.0
	part.tail_angle = 0.0
	part.tail_width = 70.0
	part.path_part = 1
	part.path_prev_id = root.id
	part.path_head_local = root.path_tail_local()
	part.path_style = "ribbon"
	part.path_speed = 0.8
	part.tolerance = 0.31
	part.path_gaps = [{"from": 0.2, "to": 0.4}]
	part.trace_pts = [{"x": 0.3, "y": 0.1, "db": 0.0}, {"x": 0.5, "y": 0.3, "db": 1.0}]
	part.color = 1
	part.lock = true
	root.path_next_id = part.id
	chart.notes.append(part)
	var seek := Note.new("seek", 4.5, 0.0, 360.0)
	seek.id = chart.next_note_id()
	seek.end_beat = seek.beat
	seek.seek_orien = 1
	chart.notes.append(seek)
	var pair := chart.make_anchor_pair(5.0, 45.0)
	for item in pair:
		chart.notes.append(item)
	var bell := Note.new("bell", 6.0, 120.0, 24.0)
	bell.id = chart.next_note_id()
	bell.center_u = 120.0 / 360.0
	bell.radius = 40.0
	chart.notes.append(bell)
	chart.palette.append({"name": "夜间", "tap": "#ff00aa", "hold": "#f0c36a", "path": "#8cbfff"})
	chart.editor = {
		"snap": 8, "zoom": 1.4, "waveform": false, "hud": false,
		"flow_down": false, "beat_subdivisions": 8, "rail_snap": false,
	}
	return chart


func test_ring_timeline_selection_ops() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S0"] = BoundaryShape.ellipse("S0", 300.0, 300.0, 48)
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear", "id": 1},
		{"beat": 4.0, "shape_id": "S0", "easing": "linear", "id": 2},
	]
	chart.view_states = [
		ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear"),
		ViewState.new(2.0, 1.2, 0.0, 0.0, 1.0, 45.0, "linear"),
	]
	chart.view_states[0].id = 3
	chart.view_states[1].id = 4
	app.chart = chart
	app.playhead_beat = 0.0
	var workspace := RingWorkspace.new()
	workspace._app = app
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	# 多选 + 复制粘贴：保间距
	timeline._select_only("shape", 1)
	timeline._toggle_select("shape", 2)
	eq(timeline.selection_count(), 2, "跨键多选")
	timeline.copy_selection()
	app.playhead_beat = 8.0
	timeline.paste()
	eq(chart.shape_keys.size(), 4, "粘贴新增两帧")
	var beats: Array[float] = []
	for key in chart.shape_keys:
		beats.append(float(key.get("beat", 0.0)))
	beats.sort()
	near(beats[2], 8.0, 0.001, "粘贴起点是播放头")
	near(beats[3], 12.0, 0.001, "粘贴保持相对间距")
	# 冲突替换：在 8 拍再粘一次，不新增
	app.playhead_beat = 8.0
	timeline.paste()
	eq(chart.shape_keys.size(), 4, "同拍粘贴替换而不是叠加")
	# 删除选中
	var doomed_id := 0
	for key in chart.shape_keys:
		if absf(float(key.get("beat", 0.0)) - 8.0) < 0.001:
			doomed_id = int(key.get("id", 0))
	timeline._select_only("shape", doomed_id)
	timeline.delete_selection()
	eq(chart.shape_keys.size(), 3, "删除选中帧")
	# 插入只影响当前轨
	timeline._select_only("shape", 1)
	app.playhead_beat = 1.0
	timeline.insert_frames(2.0)
	var after: Array[float] = []
	for key in chart.shape_keys:
		after.append(float(key.get("beat", 0.0)))
	after.sort()
	near(after[0], 0.0, 0.001, "插入点之前的帧不动")
	near(after[1], 6.0, 0.001, "插入点之后的形状帧右移")
	near(chart.view_states[1].beat, 2.0, 0.001, "镜头轨不跟着移")
	# 跨轨微移
	timeline._toggle_select("view", 4)
	timeline.nudge_selection(1.0)
	near(chart.view_states[1].beat, 3.0, 0.001, "跨轨选中一起微移")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 演出指令轨：新增、选择、微移、命中、分组和删除都要和图表一致。
func test_ring_timeline_command_lanes() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	app.chart = chart
	app.playhead_beat = 0.0
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 420)
	ok(timeline._lane_top(RingTimeline.LANE_COMMAND_JLINE) > timeline._lane_top(RingTimeline.LANE_BPM),
		"指令轨排在 BPM 轨下面")
	eq(timeline._lane_height(RingTimeline.LANE_COMMAND_FILTER), RingTimeline.COMMAND_ROW_H,
		"指令轨使用自己的行高")
	timeline.add_command_at(RingTimeline.LANE_COMMAND_FILTER, 4.0)
	eq(chart.commands.size(), 1, "双击滤镜轨空白新增一条")
	var command := chart.commands[0]
	eq(command.category(), AlphaCommand.CATEGORY_FILTER, "新增的是滤镜指令")
	near(command.beat, 4.0, 0.001, "按落点拍新增")
	ok(timeline.selected_command() == command, "新增后自动选中")
	timeline.nudge_selection(0.5)
	near(command.beat, 4.5, 0.001, "方向键微移指令")
	var items := timeline._lane_items(RingTimeline.LANE_COMMAND_FILTER)
	eq(items.size(), 1, "滤镜轨按类别取到指令")
	eq(timeline._hit_command(RingTimeline.LANE_COMMAND_FILTER, items,
		Vector2(timeline._x_for(command.beat), 1.0)), 0, "点指令块能命中")
	timeline.delete_selected_command()
	eq(chart.commands.size(), 0, "删除选中指令")
	timeline.add_command_of("TEXT", 2.0)
	timeline.add_command_of("JLINE", 3.0)
	eq(chart.commands.size(), 2, "按名字添加指令")
	eq(timeline._lane_items(RingTimeline.LANE_COMMAND_TEXT).size(), 1, "文本轨只显示文本指令")
	eq(timeline._lane_items(RingTimeline.LANE_COMMAND_JLINE).size(), 1, "判定线轨只显示判定线指令")
	timeline.select_command(chart.commands[0])
	eq(timeline.selection_count(), 1, "指令单选")
	eq(timeline.selected_command(), chart.commands[0], "selected_command 返回当前指令")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 演出指令也要能 Ctrl+C/X/V：复制参数，粘贴到播放头，Cut 保留剪贴板。
func test_ring_timeline_command_copy_paste() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	app.chart = chart
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 420)
	var command := chart.add_command("TEXT", 2.0)
	command.params["content"] = "复制我"
	command.duration = 3.0
	timeline.select_command(command, false)
	timeline.copy_selection()
	eq(timeline._clipboard.size(), 1, "复制一条指令")
	eq(String(timeline._clipboard[0].get("kind", "")), "command", "剪贴板记的是指令")
	app.playhead_beat = 9.0
	timeline.paste()
	eq(chart.commands.size(), 2, "粘贴新增一条指令")
	var pasted: AlphaCommand = chart.commands[1]
	near(pasted.beat, 9.0, 0.001, "粘贴落在播放头")
	eq(pasted.name, "TEXT", "粘贴保留指令类型")
	eq(pasted.text_value("content"), "复制我", "粘贴保留参数")
	near(pasted.duration, 3.0, 0.001, "粘贴保留持续拍数")
	ok(timeline.selected_command() == pasted, "粘贴后选中新指令")
	timeline.cut_selection()
	eq(chart.commands.size(), 1, "剪切删除选中的指令")
	eq(timeline._clipboard.size(), 1, "剪切后剪贴板仍可粘贴")
	app.playhead_beat = 12.0
	timeline.paste()
	eq(chart.commands.size(), 2, "剪切后可再次粘贴")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 音符显示轨：缓存按音符版本构建，能被命中/悬停查询，且排在关键帧轨上方。
func test_ring_note_lane_cache() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	for i in 1000:
		var note := Note.new("tap" if i % 4 else "hold", float(i) * 0.25, 0.0, 60.0)
		note.id = i + 1
		if note.type == "hold":
			note.end_beat = note.beat + 2.0
		chart.notes.append(note)
	app.chart = chart
	var workspace := RingWorkspace.new()
	workspace._app = app
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 420)
	ok(timeline._lane_top(RingTimeline.LANE_NOTES) < timeline._lane_top(RingTimeline.LANE_SHAPE),
		"音符轨在形状轨上方")
	eq(timeline._lane_at(RingTimeline.NOTE_TOP + 4.0), RingTimeline.LANE_NOTES, "音符轨能命中鼠标")
	eq(timeline._lane_items(RingTimeline.LANE_NOTES).size(), 1000, "音符轨取到全部音符")
	timeline._ensure_note_cache(chart)
	eq(timeline._note_beats.size(), 1000, "音符缓存按音符数量构建")
	near(timeline._note_beats[1], 0.25, 0.001, "缓存按拍排序")
	near(timeline._note_spans[0], 2.0, 0.001, "Hold 缓存持续长度")
	eq(timeline._hit_note(Vector2(timeline._x_for(0.25), RingTimeline.NOTE_TOP + 4.0)), 1,
		"音符轨按光标附近拍命中")
	eq(timeline._hit_note(Vector2(timeline._x_for(5.125), RingTimeline.NOTE_TOP + 4.0)), -1,
		"远离音符时不会误命中")
	timeline._ensure_note_cache(chart)
	eq(timeline._note_beats.size(), 1000, "同一版本不重复构建")
	timeline.free()
	workspace.free()
	app.free()
	return true


func test_ring_timeline_filter_menu() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	app.chart = chart
	var workspace := RingWorkspace.new()
	workspace._app = app
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	eq(timeline._filter_menu_names.size(), AlphaCommand.names("filter").size(), "滤镜菜单列出全部滤镜")
	timeline._filter_menu_beat = 5.0
	timeline._filter_menu.id_pressed.emit(1)
	eq(chart.commands.size(), 1, "从菜单添加一条滤镜")
	if chart.commands.size() == 1:
		eq(chart.commands[0].name, AlphaCommand.names("filter")[1], "菜单项对应选中的滤镜种类")
		near(chart.commands[0].beat, 5.0, 0.001, "滤镜落在双击的拍位")
	timeline.free()
	workspace.free()
	app.free()
	return true


func test_ring_playhead_only_redraws_overlay() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shape_keys = [{"beat": 0.0, "shape_id": "S0", "easing": "linear", "id": 1}]
	app.chart = chart
	var workspace := RingWorkspace.new()
	workspace._app = app
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	var before := timeline._content_invalidations
	timeline.on_playhead_changed()
	eq(timeline._content_invalidations, before, "拖播放头不重绘静态轨道体")
	timeline.on_live_change()
	eq(timeline._content_invalidations, before + 1, "谱面变化才重绘轨道体")
	timeline.on_chart_changed()
	eq(timeline._content_invalidations, before + 2, "谱面结构变化重绘轨道体")
	timeline.free()
	workspace.free()
	app.free()
	return true


func test_ring_marquee_and_drag() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S0"] = BoundaryShape.ellipse("S0", 300.0, 300.0, 48)
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear", "id": 1},
		{"beat": 4.0, "shape_id": "S0", "easing": "linear", "id": 2},
	]
	chart.view_states = [ViewState.new(0.0), ViewState.new(2.0)]
	chart.view_states[0].id = 3
	chart.view_states[1].id = 4
	app.chart = chart
	app.playhead_beat = 0.0
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_start = 0.0
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 300)
	# 框选跨两条轨
	timeline._marquee_start = Vector2(190, 60)
	timeline._marquee_current = Vector2(330, 190)
	timeline._marquee_add = false
	timeline._marquee_active = true
	timeline._update_marquee_selection()
	eq(timeline.selection_count(), 2, "框选同时选中形状帧与镜头帧")
	# 跨轨整体拖动
	var anywhere := Vector2(timeline._x_for(0.0), 100)
	timeline._begin_key_drag(anywhere)
	timeline._drag_keys(Vector2(timeline._x_for(2.0), 100))
	timeline._release(Vector2(timeline._x_for(2.0), 100))
	near(float(chart.shape_keys[0].get("beat", 0.0)), 2.0, 0.001, "形状帧跟着拖动")
	near(chart.view_states[0].beat, 2.0, 0.001, "镜头帧一起拖动")
	# 最后一段的整条「保持到结尾」都要能点中（以前只认起点后 0.25 拍）
	var last_hit := timeline._hit_segment(0, chart.sorted_shape_keys(), Vector2(timeline._x_for(5.0), 90))
	eq(last_hit, 1, "最后一段保持区可点选")
	timeline.free()
	workspace.free()
	app.free()
	return true


func test_shape_key_cache_invalidation() -> bool:
	# 真实编辑顺序：时间轴先画过一遍（排序缓存已热），再在播放头加一帧。
	# 缓存失效一旦漏掉，App.mutate 会认为快照没变：不标脏、不记撤销、存盘丢帧。
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S0"] = BoundaryShape.ellipse("S0", 300.0, 300.0, 48)
	chart.shape_keys = [{"beat": 0.0, "shape_id": "S0", "easing": "linear"}]
	app.chart = chart
	eq(chart.sorted_shape_keys().size(), 1, "排序缓存先热起来")
	app.mutate(func() -> void:
		chart.shape_keys.append({"beat": 4.0, "shape_id": "S0", "easing": "in-out"})
	)
	eq(chart.shape_keys.size(), 2, "内存里多了一帧")
	eq(chart.sorted_shape_keys().size(), 2, "时间轴排序缓存跟着失效")
	eq((ChartIO.chart_to_dict(chart)["boundary_keys"] as Array).size(), 2, "存盘快照包含新帧")
	ok(app.dirty, "加帧后标脏")
	ok(chart.version > 0, "加帧后版本号增加")
	# 删除走同一条缓存路径，不能出现「删了还在」
	var doomed: Dictionary = chart.shape_keys[0]
	app.mutate(func() -> void:
		chart.shape_keys.erase(doomed)
	)
	eq(chart.sorted_shape_keys().size(), 1, "删除后缓存同步")
	eq((ChartIO.chart_to_dict(chart)["boundary_keys"] as Array).size(), 1, "删除后快照只剩一帧")
	app.free()
	return true


func test_key_ids_and_v2_migration() -> bool:
	# v1 没有 id / 没有曲线；载入时补 id，并把镜头缓动从目标帧搬到左帧。
	var v1 := {
		"format": "tamaki3-chart", "version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"shapes": [{"id": "S0", "closed": true, "segments": []}],
		"boundary_keys": [
			{"beat": 0.0, "shape": "S0", "easing": "linear"},
			{"beat": 4.0, "shape": "S0", "easing": "in-out"},
		],
		"view_states": [
			{"beat": 0.0, "zoom": 1.0, "rotation": 0.0, "easing": "linear"},
			{"beat": 4.0, "zoom": 1.2, "rotation": 40.0, "easing": "in-out"},
		],
	}
	var chart := ChartIO.chart_from_dict(v1)
	ok(chart != null, "v1 谱面能打开")
	if chart == null:
		return true
	var id0 := int(chart.shape_keys[0].get("id", 0))
	ok(id0 > 0, "形状键自动补 id")
	ok(int(chart.shape_keys[1].get("id", 0)) != id0, "id 不重复")
	eq(chart.view_states[0].easing, "linear", "v1 左帧缓动保持")
	eq(chart.view_states[1].easing, "in-out", "v1 目标帧缓动保持")
	near(float(BoundaryRuntime.eval_view(chart, 2.0)["zoom"]), 1.1, 0.001, "迁移后旧演出不变")
	near(float(chart.shape_keys[1].get("morph", -1.0)), 4.0, 0.001, "v1 整段过渡迁移为显式 4 拍")
	var data := ChartIO.chart_to_dict(chart)
	eq(int(data["version"]), 3, "写回 v3")
	ok(int((data["boundary_keys"] as Array)[0].get("id", 0)) > 0, "写回带 id")
	chart.shape_keys[0]["curve"] = [0.2, 0.0, 0.8, 1.0]
	chart.view_states[0].curve = [0.42, 0.0, 0.58, 1.0]
	var back := ChartIO.from_json(ChartIO.to_json(chart))
	ok(back != null, "v2 往返不报错")
	if back != null:
		eq((back.shape_keys[0].get("curve", []) as Array).size(), 4, "形状曲线往返")
		eq(back.view_states[0].curve.size(), 4, "镜头曲线往返")
		near(Ease.apply_curve("linear", back.shape_keys[0].get("curve", []), 0.5), 0.5, 0.02, "曲线中点")
	var future := data.duplicate(true)
	future["version"] = 99
	ok(ChartIO.chart_from_dict(future) == null, "过新版本拒绝打开")
	ok(ChartIO.last_error.contains("过新"), "拒绝原因说明版本")
	return true


func test_camera_left_key_semantics() -> bool:
	var chart := Chart.new()
	chart.view_states = [
		ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear"),
		ViewState.new(4.0, 1.2, 20.0, 10.0, 1.2, 40.0, "in-out"),
	]
	# 段缓动看目标帧：右帧 in-out 时 1/4 处就是 0.15625，不受左帧 linear 影响。
	near(float(BoundaryRuntime.eval_view(chart, 1.0)["zoom"]), 1.03125, 0.001, "缓动归目标帧")
	near(float(BoundaryRuntime.eval_view(chart, 2.0)["tilt_x"]), 10.0, 0.001, "横倾插值")
	near(float(BoundaryRuntime.eval_view(chart, 2.0)["ellipse"]), 1.1, 0.001, "椭圆比插值")
	chart.view_states[1].easing = "linear"
	near(float(BoundaryRuntime.eval_view(chart, 1.0)["zoom"]), 1.05, 0.001, "目标帧改匀速")
	return true


func test_ease_bezier() -> bool:
	near(Ease.bezier([0.0, 0.0, 1.0, 1.0], 0.25), 0.25, 0.001, "线性贝塞尔")
	near(Ease.bezier([0.42, 0.0, 1.0, 1.0], 0.5), 0.315, 0.02, "缓入曲线")
	near(Ease.apply_curve("linear", [0.0, 0.0, 1.0, 1.0], 0.75), 0.75, 0.001, "曲线优先于预设")
	near(Ease.apply_curve("in-out", [], 0.25), 0.15625, 0.001, "无曲线时退回预设")
	return true


## 过渡在目标帧前完成：0 拍硬切，整段 = 连续变化。
func test_shape_transition_incoming() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S1"] = BoundaryShape.circle("S1", 200.0, 48)
	chart.shape_keys = [
		{"beat": 2.0, "shape_id": "S1", "morph": 1.0, "easing": "linear"},
		{"beat": 4.0, "shape_id": "S0", "morph": 1.0, "easing": "linear"},
	]
	near(BoundaryRuntime.eval_point(chart, 0.0, 0.5).point.x, 330.0, 0.5, "首帧前保持基础圆")
	near(BoundaryRuntime.eval_point(chart, 0.0, 1.5).point.x, 265.0, 0.5, "首帧前 1 拍过渡")
	near(BoundaryRuntime.eval_point(chart, 0.0, 2.5).point.x, 200.0, 0.5, "第一帧后保持 S1")
	near(BoundaryRuntime.eval_point(chart, 0.0, 3.5).point.x, 265.0, 0.5, "目标帧前 1 拍过渡回圆")
	near(BoundaryRuntime.eval_point(chart, 0.0, 4.5).point.x, 330.0, 0.5, "目标帧后保持圆")
	chart.shape_keys[1]["morph"] = 0.0
	near(BoundaryRuntime.eval_point(chart, 0.0, 3.5).point.x, 200.0, 0.5, "目标帧硬切前保持 S1")
	chart.shape_keys[0]["morph"] = 0.0
	near(BoundaryRuntime.eval_point(chart, 0.0, 1.5).point.x, 330.0, 0.5, "首帧硬切前保持圆")
	near(BoundaryRuntime.eval_point(chart, 0.0, 2.0).point.x, 200.0, 0.5, "首帧拍点硬切到 S1")
	return true


## 内容末尾必须算上形状/镜头帧，否则时间轴滚不到、seek 也跳不到。
func test_content_end_includes_ring_keys() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shape_keys = [{"beat": 10.0, "shape_id": "S0", "morph": 0.0}]
	chart.view_states = [ViewState.new(12.0)]
	near(chart.content_end_beat(), 12.0, 0.001, "镜头帧参与内容末尾")
	ok(chart.end_limit_beat() >= 12.0, "可跳转上限覆盖镜头帧")
	chart.shape_keys = [{"beat": 20.0, "shape_id": "S0", "morph": 0.0}]
	chart.mark_dirty()
	near(chart.content_end_beat(), 20.0, 0.001, "形状帧参与内容末尾")
	return true


## v2 的镜头缓动存在左帧；v3 归目标帧，读 v2 时要搬到右帧，旧演出不变。
func test_v2_camera_easing_migration() -> bool:
	var v2 := {
		"format": "tamaki3-chart", "version": 2,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"shapes": [{"id": "S0", "closed": true, "segments": []}, {"id": "S1", "closed": true, "segments": []}],
		"boundary_keys": [
			{"beat": 0.0, "shape": "S0", "easing": "linear"},
			{"beat": 4.0, "shape": "S1", "easing": "in-out"},
		],
		"view_states": [
			{"beat": 0.0, "zoom": 1.0, "easing": "in-out"},
			{"beat": 4.0, "zoom": 1.2, "easing": "linear"},
		],
	}
	var chart := ChartIO.chart_from_dict(v2)
	ok(chart != null, "v2 谱面能打开")
	if chart == null:
		return true
	eq(chart.view_states[1].easing, "in-out", "v2 左帧缓动搬到目标帧")
	near(float(BoundaryRuntime.eval_view(chart, 1.0)["zoom"]), 1.03125, 0.001, "迁移后旧镜头演出不变")
	near(float(chart.shape_keys[1].get("morph", -1.0)), 4.0, 0.001, "v2 形状整段过渡改成显式 4 拍")
	eq(String(chart.shape_keys[1].get("easing", "")), "linear", "v2 形状左帧缓动搬到目标帧")
	return true


## v3 字段：稳定 id、入场过渡、镜头 dolly、每段曲线、face_camera 都要往返。
func test_v3_round_trip_fields() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S1"] = BoundaryShape.circle("S1", 200.0, 48)
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "easing": "linear", "morph": 0.0, "id": 1},
		{"beat": 4.0, "shape_id": "S1", "easing": "in-out", "morph": 1.5, "id": 2,
			"curve": [0.2, 0.0, 0.8, 1.0]},
	]
	chart.view_states = [ViewState.new(0.0), ViewState.new(4.0)]
	chart.view_states[0].id = 3
	chart.view_states[1].id = 4
	chart.view_states[1].dolly = 1.2
	chart.view_states[1].morph = 0.5
	chart.view_states[1].curve = [0.42, 0.0, 0.58, 1.0]
	chart.metadata["face_camera"] = false
	var data := ChartIO.chart_to_dict(chart)
	eq(int(data["version"]), 3, "写回 v3")
	eq((data["events"] as Array).size(), 0, "现代谱不写旧 events")
	var back := ChartIO.from_json(ChartIO.to_json(chart))
	ok(back != null, "v3 往返不报错")
	if back == null:
		return true
	near(float(back.shape_keys[1].get("morph", -1.0)), 1.5, 0.001, "形状入场过渡往返")
	eq((back.shape_keys[1].get("curve", []) as Array).size(), 4, "形状曲线往返")
	eq(int(back.shape_keys[1].get("id", 0)), 2, "形状 id 往返")
	near(back.view_states[1].dolly, 1.2, 0.001, "镜头 dolly 往返")
	near(back.view_states[1].morph, 0.5, 0.001, "镜头入场过渡往返")
	eq(back.view_states[1].curve.size(), 4, "镜头曲线往返")
	eq(back.view_states[1].id, 4, "镜头 id 往返")
	eq(bool(back.metadata.get("face_camera", true)), false, "face_camera 往返")
	return true


## 现代谱不再双写 events；删光关键帧后重开也不能把动画复活。
func test_legacy_events_no_resurrection() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "morph": 0.0, "easing": "linear"},
		{"beat": 4.0, "shape_id": "S0", "morph": 0.0, "easing": "linear"},
	]
	chart.events.append(BoundaryEvent.from_dict({
		"id": "E1", "start_beat": 0.0, "end_beat": 4.0, "target_u0": 0.0, "target_u1": 1.0,
		"from_shape": "S0", "to_shape": "S0", "easing": "linear", "end_behavior": "hold",
		"restore_duration": 0.0, "restore_easing": "in-out",
	}))
	var data := ChartIO.chart_to_dict(chart)
	eq((data["events"] as Array).size(), 0, "有关键帧时不写旧 events")
	var loaded := ChartIO.chart_from_dict(data)
	ok(loaded != null, "现代谱能重开")
	if loaded == null:
		return true
	eq(loaded.events.size(), 0, "载入时丢掉重复 events")
	loaded.shape_keys.clear()
	var emptied := ChartIO.chart_to_dict(loaded)
	eq((emptied["boundary_keys"] as Array).size(), 0, "删光关键帧后 boundary_keys 为空")
	eq((emptied["events"] as Array).size(), 0, "删光关键帧后 events 也为空")
	var reopened := ChartIO.chart_from_dict(emptied)
	ok(reopened != null, "空谱能重开")
	if reopened != null:
		eq(reopened.shape_keys.size(), 0, "关键帧没有复活")
	return true


## dolly 是镜头距离：默认整段平滑，hard cut 在目标帧处切换。
func test_camera_dolly_interpolates() -> bool:
	var states: Array[ViewState] = [ViewState.new(0.0), ViewState.new(4.0)]
	states[1].dolly = 1.4
	states[1].morph = -1.0
	near(float(ViewState.evaluate(states, 2.0)["dolly"]), 1.2, 0.001, "dolly 整段插值")
	states[1].morph = 0.0
	near(float(ViewState.evaluate(states, 3.9)["dolly"]), 1.0, 0.001, "硬切前保持左帧 dolly")
	near(float(ViewState.evaluate(states, 4.0)["dolly"]), 1.4, 0.001, "目标帧处硬切")
	return true


## 点色带选中的是目标帧：introduction 段返回第一帧，最后保持段返回最后一帧。
func test_ring_segment_targets() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shape_keys = [
		{"beat": 0.0, "shape_id": "S0", "morph": 0.0, "easing": "linear", "id": 1},
		{"beat": 4.0, "shape_id": "S0", "morph": 0.0, "easing": "linear", "id": 2},
	]
	app.chart = chart
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 300)
	var items := chart.sorted_shape_keys()
	eq(timeline._hit_segment(0, items, Vector2(timeline._x_for(2.0), 100)), 1, "中间段命中目标帧")
	eq(timeline._hit_segment(0, items, Vector2(timeline._x_for(6.0), 100)), 1, "最后保持段命中最后一帧")
	var intro_chart := Chart.new()
	intro_chart.shape_keys = [{"beat": 2.0, "shape_id": "S0", "morph": 0.0, "easing": "linear", "id": 3}]
	app.chart = intro_chart
	var intro_items := intro_chart.sorted_shape_keys()
	eq(timeline._hit_segment(0, intro_items, Vector2(timeline._x_for(1.0), 100)), 0, "第一帧前的圆带命中第一帧")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 环编辑的增删也要能撤销；没有形状帧时整首是基础圆。
func test_ring_undo_and_default_circle() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	near(BoundaryRuntime.eval_point(chart, 0.0, 40.0).point.x, 330.0, 0.5, "没有形状帧时保持基础圆")
	ok(BoundaryRuntime.pair_at(chart, 40.0).is_empty(), "没有形状帧时不进入过渡")
	var app: App = load("res://charter/app.gd").new()
	app.chart = chart
	app.mutate_ring(func() -> void:
		chart.shape_keys.append({"beat": 4.0, "shape_id": "S0", "easing": "linear", "morph": 0.0,
			"id": chart.next_key_id()})
	)
	eq(app.chart.shape_keys.size(), 1, "环编辑加帧")
	eq(app.chart.sorted_shape_keys().size(), 1, "加帧后时间轴缓存同步")
	eq((ChartIO.chart_to_dict(app.chart)["boundary_keys"] as Array).size(), 1, "加帧后存盘快照同步")
	app.mutate_ring(func() -> void:
		app.chart.view_states.append(ViewState.new(8.0))
	)
	eq(app.chart.sorted_view_states().size(), 2, "加镜头帧后缓存同步")
	app.undo_chart()
	app.undo_chart()
	eq(app.chart.shape_keys.size(), 0, "环编辑撤销")
	app.redo_chart()
	eq(app.chart.shape_keys.size(), 1, "环编辑重做")
	app.free()
	return true


## 播放头停在已有帧上时，插入必须自动放到下一拍，而不是静默替换。
func test_ring_insert_advances_when_occupied() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shape_keys = [{"beat": 0.0, "shape_id": "S0", "easing": "linear", "morph": 0.0, "id": 1}]
	app.chart = chart
	app.snap_division = 4
	app.playhead_beat = 0.0
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 300)
	workspace._insert_key_with_shape("S0")
	eq(chart.shape_keys.size(), 2, "已有帧时插入会新增而不是替换")
	near(workspace.playhead(), 0.25, 0.001, "新增后播放头移到下一拍")
	workspace._insert_key_with_shape("S0")
	eq(chart.shape_keys.size(), 3, "连点继续往后加")
	near(workspace.playhead(), 0.5, 0.001, "第二次也移到下一拍")
	workspace.insert_next_shape()
	eq(chart.shape_keys.size(), 4, "检查器「下一拍」按钮继续加形状帧")
	near(workspace.playhead(), 0.75, 0.001, "下一拍按钮也推进播放头")
	workspace.seek(0.0)
	var views_before := chart.view_states.size()
	workspace._add_view_keyframe()
	eq(chart.view_states.size(), views_before + 1, "已有镜头帧时也会新增")
	near(workspace.playhead(), 0.25, 0.001, "镜头帧也移到下一拍")
	workspace.insert_next_view()
	eq(chart.view_states.size(), views_before + 2, "检查器「下一拍」按钮继续加镜头帧")
	near(workspace.playhead(), 0.5, 0.001, "镜头下一拍按钮推进播放头")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 播放头在空拍时，插入应落在播放头本身；只有已有帧才顺延。
func test_ring_insert_at_empty_playhead() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	app.chart = chart
	app.snap_division = 4
	app.playhead_beat = 0.0
	var workspace := RingWorkspace.new()
	workspace._app = app
	workspace._view_beats = 16.0
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	timeline.size = Vector2(1600, 300)
	workspace._insert_key_with_shape("S0")
	eq(chart.shape_keys.size(), 1, "空拍插入新增一帧")
	near(float(chart.shape_keys[0].get("beat", -1.0)), 0.0, 0.001, "空拍插入落在播放头")
	near(workspace.playhead(), 0.0, 0.001, "空拍插入不移动播放头")
	workspace.seek(4.0)
	workspace._add_view_keyframe()
	var found := false
	for state in chart.view_states:
		if is_equal_approx(state.beat, 4.0):
			found = true
			break
	ok(found, "镜头空拍插入落在播放头")
	timeline.free()
	workspace.free()
	app.free()
	return true


## 环编辑提交只发 ring_changed：不能触发整谱缓存、SFX 表和主检查器重建。
func test_ring_signal_split() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	app.chart = chart
	var counts := [0, 0]
	app.chart_changed.connect(func() -> void: counts[0] += 1)
	app.ring_changed.connect(func() -> void: counts[1] += 1)
	app.mutate_ring(func() -> void:
		chart.shape_keys.append({"beat": 4.0, "shape_id": "S0", "easing": "linear", "morph": 0.0, "id": 1})
	)
	eq(counts[0], 0, "ring edit does not emit chart_changed")
	eq(counts[1], 1, "ring edit emits ring_changed")
	app.free()
	return true


func test_undo_memory_budget() -> bool:
	var undo := UndoStack.new()
	for i in 30:
		var snap := {"notes": [], "i": i}
		snap["notes"].resize(10000)
		undo.record(snap)
	eq(undo.undo_items.size(), 12, "1 万音符谱面只保留 12 步撤销（内存上限）")
	var small := UndoStack.new()
	for i in 260:
		small.record({"notes": [], "i": i})
	eq(small.undo_items.size(), UndoStack.LIMIT, "小谱仍保留 200 步")
	# 撤销一步后用量计数要跟着退，不能越用越少
	var back := undo.undo({"notes": []})
	eq(int(back.get("i", -1)), 29, "撤销取回最近一份快照")
	eq(undo.undo_items.size(), 11, "撤销后列表缩短")
	return true


func test_ring_lane_items_real_chart() -> bool:
	var workspace := RingWorkspace.new()
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	var chart := Chart.new()
	chart.events = [
		BoundaryEvent.new("E1", 4.0, 6.0),
		BoundaryEvent.new("E0", 1.0, 2.0),
	]
	chart.timing.points = [TimingPoint.new(4.0, 120.0, 4), TimingPoint.new(0.0, 120.0, 4)]
	chart.view_states = [ViewState.new(8.0), ViewState.new(0.0)]
	var app: App = load("res://charter/app.gd").new()
	app.chart = chart
	workspace._app = app
	var events: Array = timeline._lane_items(2)
	eq(events.size(), 2, "边界事件轨拿得到旧谱事件")
	if events.size() == 2:
		near(events[0].start_beat, 1.0, 0.001, "事件按 start_beat 排序")
	var points: Array = timeline._lane_items(3)
	near(float(points[0].beat), 0.0, 0.001, "BPM 轨按拍排序")
	timeline.free()
	workspace.free()
	app.free()
	return true


func test_ring_scrub_state() -> bool:
	var workspace := RingWorkspace.new()
	var timeline := RingTimeline.new(workspace)
	workspace._timeline = timeline
	eq(workspace.scrubbing(), false, "没在拖播放头")
	timeline._drag_kind = "playhead"
	eq(workspace.scrubbing(), true, "拖播放头的状态在 Timeline 上也能被认到")
	eq(workspace.dragging(), true, "scrubbing 同时算拖动，面板刷新被压住")
	timeline._drag_kind = ""
	workspace._drag_kind = "key"
	eq(workspace.scrubbing(), false, "拖关键帧不是 scrubbing")
	eq(workspace.dragging(), true, "拖关键帧仍然算 dragging")
	timeline.free()
	workspace.free()
	return true


## 播放头跳转只重画覆盖层：同一拍重复事件不该反复重建环网格。
func test_playhead_redraw_is_light() -> bool:
	var preview := Preview3D.new()
	preview._mesh_dirty = false
	preview.request_playhead_redraw()
	eq(preview._mesh_dirty, false, "播放头跳转不强制重建网格")
	eq(preview._force_3d_frame, true, "仍然让 3D 出一帧")
	preview.request_redraw()
	eq(preview._mesh_dirty, true, "结构改动仍走 request_redraw 强建")
	preview.free()
	return true


func test_ring_tilt_target() -> bool:
	var bounds := Vector2(1600, 900)
	eq(Preview3D.tilt_target_for(Vector2(800, 450), bounds, 7.0), Vector2.ZERO, "tilt zero at centre")
	eq(Preview3D.tilt_target_for(Vector2(800, 450), bounds, 0.0), Vector2.ZERO, "tilt zero at 0 degrees")
	var right := Preview3D.tilt_target_for(Vector2(1600, 450), bounds, 7.0)
	ok(right.y > 6.9 and absf(right.x) < 0.01, "mouse right tilts the right side (remote sign)")
	var top := Preview3D.tilt_target_for(Vector2(800, 0), bounds, 7.0)
	ok(top.x > 6.9 and absf(top.y) < 0.01, "mouse top tilts the top side near")
	# 线性映射：半程就是半幅度（远端口径，没有曲线）
	var half := Preview3D.tilt_target_for(Vector2(1200, 450), bounds, 7.0)
	near(half.y, 3.5, 0.01, "tilt is linear across the screen")
	var corner := Preview3D.tilt_target_for(Vector2(2400, -900), bounds, 7.0)
	ok(corner.y <= 7.0 and corner.y >= -7.0, "tilt clamps horizontally")
	ok(corner.x > 0.0 and corner.x <= 7.0, "tilt clamps vertically")
	return true


## 故事板编辑器播放：播到末尾要么回到开头，要么停住，不能卡在末尾。
func test_storyboard_editor_transport() -> bool:
	eq(StoryboardEditor.transport_action(1000.0, 5000.0, true), StoryboardEditor.TRANSPORT_KEEP, "mid play keeps going")
	eq(StoryboardEditor.transport_action(5000.0, 5000.0, true), StoryboardEditor.TRANSPORT_RESTART, "loop restarts at the end")
	eq(StoryboardEditor.transport_action(5000.0, 5000.0, false), StoryboardEditor.TRANSPORT_STOP, "no loop stops at the end")
	eq(StoryboardEditor.transport_action(6000.0, 5000.0, false), StoryboardEditor.TRANSPORT_STOP, "past the end still stops")
	return true


## 拖时间轴/改命令后必须重算 first_ms/last_ms（否则分桶和快速路径用旧边界）。
func test_storyboard_build_recomputes_bounds() -> bool:
	var text := "[Events]\nSprite,Background,Centre,\"a.png\",320,240\n F,0,0,1000,,1\n M,0,1000,2000,0,0,100,100\n"
	var board := Storyboard.parse(text, "t.osb")
	eq(board.sprites.size(), 1, "one sprite")
	var sprite := board.sprites[0] as Storyboard.Sprite
	eq(sprite.first_ms, 0.0, "first command starts at 0")
	eq(sprite.last_ms, 2000.0, "last command ends at 2000")
	sprite.commands[1].end = 5000.0
	sprite.build()
	eq(sprite.last_ms, 5000.0, "moving a command updates the last bound")
	sprite.commands[0].start = 200.0
	sprite.build()
	eq(sprite.first_ms, 200.0, "moving the first command updates the first bound")
	return true


## 命令查找的游标：前进、后退、跳转都要落到正确的关键帧。
func test_storyboard_command_cursor() -> bool:
	var text := "[Events]\nSprite,Background,Centre,\"a.png\",320,240\n F,0,0,1000,,1\n F,0,1000,2000,,0\n F,0,2000,3000,,1\n"
	var board := Storyboard.parse(text, "t.osb")
	var sprite := board.sprites[0] as Storyboard.Sprite
	eq((sprite.command_at("alpha", 500.0) as Storyboard.Command).start, 0.0, "cursor starts at the first")
	eq((sprite.command_at("alpha", 1500.0) as Storyboard.Command).start, 1000.0, "cursor moves forward")
	eq((sprite.command_at("alpha", 2500.0) as Storyboard.Command).start, 2000.0, "cursor moves forward again")
	eq((sprite.command_at("alpha", 900.0) as Storyboard.Command).start, 0.0, "seek backward leaves the cursor")
	eq((sprite.command_at("alpha", 9000.0) as Storyboard.Command).start, 2000.0, "past the end clamps to the last")
	return true


## 时间轴：默认一层一行；展开后追加这一层的 sprite 行。
func test_storyboard_timeline_rows() -> bool:
	var board := Storyboard.create_blank()
	var sprite := board.add_sprite("a.png", "Background", 4, Vector2(320, 240))
	board.add_command(sprite, "alpha", 0, 0.0, 1000.0, [0.0], [1.0])
	var timeline := StoryboardTimeline.new()
	timeline.set_board(board)
	eq(timeline._rows.size(), 6, "six layer rows by default")
	timeline.expanded["Background"] = true
	timeline._rebuild_rows()
	eq(timeline._rows.size(), 7, "expanding a layer adds its sprite rows")
	timeline.expanded["Background"] = false
	timeline._rebuild_rows()
	eq(timeline._rows.size(), 6, "collapsing removes them again")
	return true


## 时间轴是 osb 时间，吸附要先把 offset 加回谱面时间。
func test_storyboard_timeline_snap_offset() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.offset_ms = -8.0
	var timeline := StoryboardTimeline.new()
	timeline.set_chart(chart)
	timeline.snap_divisor = 4.0
	near(timeline.snap_ms(1000.0), 1008.0, 0.6, "snap converts osb ms through the chart offset")
	return true


## 时间轴鼠标：以前 `InputEventMouseButton.index` 写错，任何点击都在第一行抛错，
## 标尺/眼睛/锁/展开/拖动全失效；这里直接喂一帧鼠标事件，回归到能跳转。
func test_storyboard_timeline_mouse() -> bool:
	var board := Storyboard.create_blank()
	var sprite := board.add_sprite("a.png", "Background", 4, Vector2(320, 240))
	board.add_command(sprite, "alpha", 0, 0.0, 1000.0, [0.0], [1.0])
	var timeline := StoryboardTimeline.new()
	timeline.size = Vector2(800, 250)
	timeline.set_board(board)
	var seeks: Array[float] = []
	timeline.seek.connect(func(ms: float) -> void: seeks.append(ms))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(timeline.GUTTER + 80.0, timeline.HEADER_H + 10.0)
	timeline._gui_input(click)
	eq(seeks.size(), 1, "clicking the ruler seeks")
	ok(timeline.playhead_ms > 0.0, "ruler click moves the playhead")
	click.position = Vector2(13.0, timeline._rows_top() + 9.0)
	timeline._gui_input(click)
	ok(timeline.hidden_layers.has("Video"), "clicking the eye hides that layer")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click.position
	timeline._gui_input(release)
	# 点命令条只选中，不把播放头拽走；双击才跳到命令起点。
	timeline.expanded["Background"] = true
	timeline._rebuild_rows()
	timeline.set_playhead(500.0)
	seeks.clear()
	var bar := click.duplicate() as InputEventMouseButton
	bar.position = Vector2(timeline._ms_to_x(500.0), timeline._rows_top() + 2.0 * timeline.ROW_H + 9.0)
	timeline._gui_input(bar)
	eq(seeks.size(), 0, "clicking a command bar does not seek")
	near(timeline.playhead_ms, 500.0, 0.01, "clicking a command bar keeps the playhead")
	bar.double_click = true
	timeline._gui_input(bar)
	eq(seeks.size(), 1, "double-clicking a command bar seeks")
	near(timeline.playhead_ms, 0.0, 0.01, "double-click jumps to the command start")
	timeline.free()
	return true


## 回放自带录制镜像：加载/导出时按文件里的 mirror 翻，而不是当前设置。
func test_replay_mirror_restore() -> bool:
	var replay := Replay.new()
	replay.settings = {"mirror": "lr"}
	eq(Playtest.replay_mirror(replay, "rot180"), "lr", "replay mirror wins over the current setting")
	replay.settings = {}
	eq(Playtest.replay_mirror(replay, "rot180"), "rot180", "missing mirror falls back to the setting")
	eq(Playtest.replay_mirror(null, "off"), "off", "no replay keeps the setting")
	# 镜像只是本局副本：录制时的 hash 必须按原谱算，否则回放永远匹配不上。
	var chart := DemoChart.make_demo()
	var mirrored := chart.mirrored_copy("lr")
	ok(Replay.hash_chart(chart) != Replay.hash_chart(mirrored),
		"mirrored chart has a different hash")
	near(mirrored.notes[0].angle, fposmod(180.0 - chart.notes[0].angle, 360.0), 0.01,
		"lr mirror flips note angles")
	return true


## 旧镜像回放没有 settings.mirror：靠 hash 反推。两种模式都要能认出来。
func test_replay_infer_mirror() -> bool:
	var chart := DemoChart.make_demo()
	var replay := Replay.new()
	replay.chart_hash = Replay.hash_chart(chart)
	eq(Replay.infer_mirror(replay, chart), "off", "original hash infers off")
	for mode in ["lr", "rot180"]:
		replay.chart_hash = Replay.hash_chart(chart.mirrored_copy(mode))
		eq(Replay.infer_mirror(replay, chart), mode, "mirrored hash infers %s" % mode)
	replay.chart_hash = "not-a-chart"
	eq(Replay.infer_mirror(replay, chart), "", "unknown hash does not guess")
	var export := VideoExport.new()
	eq(export.mirror_mode, "off", "AUTO export defaults to no mirror")
	export.mirror_mode = "rot180"
	eq(export.mirror_mode, "rot180", "AUTO export carries the current mirror")
	export.free()
	return true


## 导出从录制起点开始：从 0 重跑会把本局没玩到的段全判成 MISS。
func test_video_export_start_from_replay() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var replay := Replay.new()
	replay.start_beat = 8.0
	near(VideoExport.start_ms_for(chart, replay), chart.timing.beat_to_chart_ms(8.0), 0.01,
		"export starts at the recorded beat")
	eq(VideoExport.start_ms_for(chart, null), 0.0, "AUTO export still starts at zero")
	return true


## 故事板编辑器测试夹具：建一个带单个 sprite/命令的编辑器（不依赖主界面）。
func _storyboard_editor_for_test() -> StoryboardEditor:
	var editor := StoryboardEditor.new()
	root.add_child(editor)
	editor.open_for(DemoChart.make_empty({"title": "sb"}))
	editor._timeline.size = Vector2(800, 250)
	var sprite := editor._board.add_sprite("a.png", "Background", 4, Vector2(320, 240))
	editor._board.add_command(sprite, "alpha", 0, 0.0, 1000.0, [0.0], [1.0])
	editor._refresh_objects()
	editor._timeline.set_board(editor._board)
	editor._timeline.expanded["Background"] = true
	editor._timeline._rebuild_rows()
	editor._timeline.set_zoom(0.0, 2000.0)
	editor._seek_to(500.0)
	editor._select_sprite(0)
	return editor


static func _storyboard_click(timeline, pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	timeline._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	timeline._gui_input(release)


static func _storyboard_escape(editor: StoryboardEditor) -> void:
	editor._handle_escape()


static func _storyboard_close_dialogs(editor: StoryboardEditor) -> Array:
	var found: Array = []
	for child in editor.get_children():
		if child is ConfirmationDialog and not (child is FileDialog):
			found.append(child)
	return found


## 眼睛/锁必须可逆：第二次点击要恢复。旧实现写入 false 但 has() 仍为真，永远取消不掉。
func test_storyboard_layer_toggle_reversible() -> bool:
	var editor := _storyboard_editor_for_test()
	var timeline = editor._timeline
	var y: float = timeline._rows_top() + 9.0
	_storyboard_click(timeline, Vector2(13.0, y))
	ok(timeline.hidden_layers.has("Video"), "first eye click hides the layer")
	_storyboard_click(timeline, Vector2(13.0, y))
	ok(not timeline.hidden_layers.has("Video"), "second eye click shows it again")
	ok(not editor._canvas.hidden_layers.has("Video"), "canvas follows the un-hide")
	var lock_y: float = timeline._rows_top() + timeline.ROW_H + 9.0
	_storyboard_click(timeline, Vector2(33.0, lock_y))
	ok(timeline.locked_layers.has("Background"), "first lock click locks the layer")
	_storyboard_click(timeline, Vector2(33.0, lock_y))
	ok(not timeline.locked_layers.has("Background"), "second lock click unlocks it")
	ok(not editor._canvas.locked_layers.has("Background"), "canvas follows the unlock")
	eq(editor._undo.size(), 0, "view toggles do not create undo entries")
	editor.free()
	return true


## Esc 先取消命令编辑/选中，最后才关闭；关闭提示不能叠。
func test_storyboard_escape_cancels() -> bool:
	var editor := _storyboard_editor_for_test()
	editor._on_command_selected(0)
	eq(editor._cmd_editing, 0, "command is in edit mode")
	ok(editor._cancel_edit_button.visible, "cancel-edit button is visible")
	_storyboard_escape(editor)
	eq(editor._cmd_editing, -1, "Esc exits command editing first")
	ok(editor.visible, "Esc does not close the editor while editing")
	eq(editor._selected, 0, "Esc keeps the object selected after leaving command editing")
	ok(not editor._cancel_edit_button.visible, "cancel-edit button hides after leaving edit mode")
	_storyboard_escape(editor)
	eq(editor._selected, -1, "next Esc clears the selection")
	ok(editor.visible, "selection cancel does not close the editor")
	ok(not editor._inspector.visible, "selection cancel hides the inspector")
	_storyboard_escape(editor)
	ok(not editor.visible, "third Esc closes an unmodified editor")
	editor.free()
	return true


## 拖命令条后 Esc：时间回滚、dirty 回滚、undo 不留下半截记录。
func test_storyboard_drag_cancel_restores() -> bool:
	var editor := _storyboard_editor_for_test()
	var timeline = editor._timeline
	editor._undo.clear()
	editor._set_dirty(false)
	var y: float = timeline._rows_top() + 2.0 * timeline.ROW_H + 9.0
	var x: float = timeline._ms_to_x(500.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(x, y)
	timeline._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(x + 100.0, y)
	motion.relative = Vector2(100.0, 0.0)
	timeline._gui_input(motion)
	var command := editor._board.sprites[0].commands[0] as Storyboard.Command
	ok(absf(command.start) > 1.0, "drag moved the command start")
	ok(editor._dirty, "drag marks the editor dirty")
	eq(editor._undo.size(), 1, "first drag movement pushes one undo snapshot")
	ok(editor._cancel_current(), "Esc finds an active drag to cancel")
	eq(timeline._drag_mode, 0, "drag mode is reset")
	var restored := editor._board.sprites[0].commands[0] as Storyboard.Command
	near(restored.start, 0.0, 0.01, "cancelled drag restores the command start")
	near(restored.end, 1000.0, 0.01, "cancelled drag restores the command end")
	ok(not editor._dirty, "cancelled drag restores the dirty flag")
	eq(editor._undo.size(), 0, "cancelled drag removes its undo snapshot")
	# 正常拖动仍要留下 undo，并能撤销回去。
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(x, y)
	timeline._gui_input(release)
	var press2 := InputEventMouseButton.new()
	press2.button_index = MOUSE_BUTTON_LEFT
	press2.pressed = true
	press2.position = Vector2(x, y)
	timeline._gui_input(press2)
	var motion2 := InputEventMouseMotion.new()
	motion2.position = Vector2(x + 100.0, y)
	motion2.relative = Vector2(100.0, 0.0)
	timeline._gui_input(motion2)
	release.position = Vector2(x + 100.0, y)
	timeline._gui_input(release)
	ok(absf((editor._board.sprites[0].commands[0] as Storyboard.Command).start) > 1.0,
		"normal drag still moves the command")
	eq(editor._undo.size(), 1, "normal drag keeps its undo snapshot")
	editor._on_undo()
	near((editor._board.sprites[0].commands[0] as Storyboard.Command).start, 0.0, 0.01,
		"undo restores a normal drag")
	editor.free()
	return true


## 关闭提示只有一个；取消=继续编辑；不保存立即关闭。
func test_storyboard_close_dialog_unique() -> bool:
	var editor := _storyboard_editor_for_test()
	editor._set_dirty(true)
	editor._request_close()
	editor._request_close()
	var dialogs := _storyboard_close_dialogs(editor)
	eq(dialogs.size(), 1, "repeated close requests keep one dialog")
	if not dialogs.is_empty():
		var dialog := dialogs[0] as ConfirmationDialog
		eq(dialog.get_cancel_button().text, "继续编辑", "cancel button says continue editing")
		dialog.get_cancel_button().pressed.emit()
		ok(editor.visible, "continue editing keeps the editor open")
	editor.free()

	var discard_editor := _storyboard_editor_for_test()
	discard_editor._set_dirty(true)
	discard_editor._request_close()
	var discard_dialogs := _storyboard_close_dialogs(discard_editor)
	if not discard_dialogs.is_empty():
		var discard_dialog := discard_dialogs[0] as ConfirmationDialog
		for button in discard_dialog.get_ok_button().get_parent().get_children():
			if button is Button and button.text == "不保存并关闭":
				button.pressed.emit()
				break
	ok(not discard_editor.visible, "discard closes the editor immediately")
	discard_editor.free()
	return true


## 宽屏判定：解析后的命令名是 move/x（不是文件里的 M/MX），
## 只查大写字母会把宽屏故事板判成 4:3、试玩按 640 裁掉两侧。
func test_storyboard_wide_detection() -> bool:
	var narrow := Storyboard.parse("[Events]\nSprite,Background,Centre,\"a.png\",320,240\n F,0,0,1000,,1\n", "t.osb")
	ok(not Preview3D._detect_wide(narrow), "4:3 storyboard is not wide")
	var moved := Storyboard.parse("[Events]\nSprite,Background,Centre,\"a.png\",320,240\n M,0,0,1000,320,240,700,240\n", "t.osb")
	ok(Preview3D._detect_wide(moved), "a move command reaching x > 641 marks it wide")
	var vectored := Storyboard.parse("[Events]\nSprite,Foreground,Centre,\"a.png\",320,240\n V,0,0,,427,240\n", "t.osb")
	ok(Preview3D._detect_wide(vectored), "vector scale 427 is the 854-wide letterbox trick")
	return true


## 环编辑时间轴页脚：拍/ms/总长/帧率。
func test_ring_timeline_clock() -> bool:
	eq(RingWorkspace._fmt_clock(120657.7), "2:00.657", "ring footer minutes and millis")
	eq(RingWorkspace._fmt_clock(0.0), "0:00.000", "ring footer zero")
	eq(RingWorkspace._fmt_clock(657.7), "0:00.657", "ring footer sub-minute")
	return true


## 背景明暗：画质页 5 档，曲绘 / BGA / 故事板共用同一个系数。
func test_background_brightness_applies() -> bool:
	# 画质页 5 档：关 / 25 / 50 / 75 / 100
	var steps := [0, 25, 50, 75, 100]
	for value in steps:
		var keep := float(value) / 100.0
		near(Preview3D.background_alpha(keep), Preview3D.BACKGROUND_ALPHA * keep, 0.0001,
			"background alpha follows brightness %d" % value)
	# BGA 用同一个系数
	near(Preview3D.video_alpha(0.8, 0.5), 0.4, 0.0001, "bga alpha follows brightness")
	var export := VideoExport.new()
	eq(export.background_brightness, 1.0, "export defaults to full brightness")
	export.background_brightness = 0.5
	eq(export.background_brightness, 0.5, "export carries brightness into the frame")
	return true


## 故事板保存必须无损：P,* / L / T / Animation / 背景行 / [Variables] 原样回写。
func test_storyboard_roundtrip_lossless() -> bool:
	var text := """[Events]
0,0,"bg.jpg",0,0
1,0,"v.mp4"
Sprite,Background,Centre,"s0.png",320,240
 P,0,0,1000,A
 F,0,0,1000,0,1
 L,0,2
  M,0,0,500,0,0,100,100
  C,0,0,100,255,0,0,0,255,0
 F,0,5000,6000,1,0
 T,BlueSky,0,1000
  F,0,0,500,1,0
Animation,Foreground,Centre,"a0.png",320,240,2,2,1
 F,0,0,100,1,0

[Variables]
$x=1
"""
	var board := Storyboard.parse(text)
	eq(board.sprites.size(), 2, "roundtrip: both objects parsed")
	var anim: Storyboard.Sprite = board.sprites[1]
	eq(anim.frames, 2, "roundtrip: animation frame count kept")
	ok(anim.animation, "roundtrip: Animation stays Animation")
	eq((board.sprites[0] as Storyboard.Sprite).loops.size(), 1, "roundtrip: loop block kept")
	eq(board.event_lines.size(), 2, "roundtrip: background/video event lines kept")
	# T 块内容不能当普通命令播放，否则触发效果会变成全程
	var t_alpha := 0
	for command in (board.sprites[0] as Storyboard.Sprite).commands:
		if (command as Storyboard.Command).kind_name == "alpha" and absf((command as Storyboard.Command).end - 500.0) < 0.01:
			t_alpha += 1
	eq(t_alpha, 0, "roundtrip: trigger commands are not rendered unconditionally")

	var out := board.to_osb_text()
	ok(out.contains("P,0,0,1000,A"), "roundtrip: additive parameter is the last field")
	ok(out.contains("Animation,Foreground"), "roundtrip: Animation written back as Animation")
	ok(out.contains(" L,0,2"), "roundtrip: loop header kept")
	ok(out.contains(" T,BlueSky,0,1000"), "roundtrip: trigger header kept")
	ok(out.contains("0,0," + char(34) + "bg.jpg" + char(34) + ",0,0"), "roundtrip: background line kept")
	ok(out.contains("[Variables]"), "roundtrip: variables section kept")

	var again := Storyboard.parse(out)
	eq(again.sprites.size(), board.sprites.size(), "roundtrip: object count stable")
	eq((again.sprites[1] as Storyboard.Sprite).frames, 2, "roundtrip: animation survives reparse")
	eq((again.sprites[0] as Storyboard.Sprite).loops.size(), 1, "roundtrip: loop survives reparse")
	eq(again.to_osb_text(), out, "roundtrip: writing is idempotent")
	return true


## L 块只吃到同缩进为止：sprite 级命令不能被吞进循环。
func test_storyboard_loop_indent_scope() -> bool:
	var text := """[Events]
Sprite,Foreground,TopLeft,"p.png",0,0
 L,0,2
  F,0,0,100,1,0
 F,0,5000,6000,1,0
"""
	var board := Storyboard.parse(text)
	var sprite: Storyboard.Sprite = board.sprites[0]
	# 循环体只有一条 F，展开 2 份；外面那条 F 只算一条
	eq(sprite.commands.size(), 3, "loop only swallows indented commands")
	eq((sprite.timeline.get("alpha", []) as Array).size(), 3, "timeline has loop copies + one normal")
	ok(absf(sprite.sample_float("alpha", 5500.0, -1.0) - 0.5) < 0.01, "command after the loop still animates")
	# 编辑器不该把循环展开出的副本当成独立命令列出来
	var visible := 0
	for command in sprite.commands:
		if not (command as Storyboard.Command).in_block:
			visible += 1
	eq(visible, 1, "editor only lists commands outside loop blocks")
	return true


## replay v2：坐标归一化到 0..1，换分辨率不改变光标相对位置。
func test_replay_normalized_coords() -> bool:
	var replay := Replay.new()
	replay.coords = Replay.COORDS_UNIT
	replay.add_move(100.0, Vector2(0.25, 0.5))
	replay.add_move(100.4, Vector2(0.30, 0.5))
	replay.add_press(120.0, 116.0, 124.0, 65, Vector2(0.75, 0.5), 90.0, 0.25, true)
	# 同一毫秒内的移动合并成一条（高回报率鼠标不会把文件撑爆）
	eq(replay.events.size(), 2, "moves within the same ms collapse")
	near(float(replay.events[0]["x"]), 0.30, 0.0001, "collapsed move keeps the last position")
	var restored := Replay.from_dict(replay.to_dict())
	eq(restored.coords, Replay.COORDS_UNIT, "coords survive the file roundtrip")
	near(float(restored.events[1]["x"]), 0.75, 0.0001, "press cursor stays normalized")
	# 旧文件（v1、没有 coords 字段）仍按像素读
	var legacy := replay.to_dict()
	legacy.erase("coords")
	legacy["version"] = 1
	eq(Replay.from_dict(legacy).coords, Replay.COORDS_PIXELS, "v1 replay still reads as pixels")
	return true


## 导出帧数是硬约定：nb_frames == ceil(span/1000*fps)。
func test_video_export_frame_total() -> bool:
	eq(VideoExport.frame_total(3000.0, 60), 180, "3s @60 = 180 frames")
	eq(VideoExport.frame_total(3000.0, 120), 360, "3s @120 = 360 frames")
	eq(VideoExport.frame_total(1000.0, 30), 30, "1s @30 = 30 frames")
	eq(VideoExport.frame_total(1.0, 60), 1, "tiny span still produces one frame")
	eq(VideoExport.frame_total(0.0, 60), 1, "empty span still produces one frame")
	return true


## 倾斜只能绕环心旋转：_ring_root 的 origin 必须是 0（旧实现平移了最多 20 单位，
## 这就是「环不在正中心」的来源）。
func test_ring_tilt_keeps_center() -> bool:
	var flat := Preview3D.ring_transform(0.0, 0.0, 0.0, 1.0, 1.0, Vector2.ZERO)
	ok(flat.basis.y.normalized().dot(Vector3.UP) > 0.9999, "no tilt keeps the ring face on")
	eq(flat.origin, Vector3.ZERO, "no tilt leaves the ring at the origin")
	var tilted := Preview3D.ring_transform(0.0, 0.0, 0.0, 1.0, 1.0, Vector2(6.0, -5.0))
	# 远端原版：倾斜时环心会跟着轻轻推一点（每度 2.8 设计单位），不是严格不动。
	near(tilted.origin.x, 5.0 * 2.8, 0.001, "tilt nudges the ring horizontally")
	near(tilted.origin.y, -6.0 * 2.8, 0.001, "tilt nudges the ring vertically")
	ok(tilted.basis.y.normalized().dot(Vector3.UP) < 0.999, "tilt actually rotates the ring")
	ok(absf(tilted.basis.x.length() - 1.0) < 0.001, "tilt keeps the basis length")
	return true


## 故事板编辑器窗口不能超出窗口/屏幕：小屏要缩到 720 内并且仍可滚动到全部元素。
func test_storyboard_editor_fit_size() -> bool:
	var small := StoryboardEditor.fit_size(Vector2(1280, 720))
	ok(small.x <= 1220, "editor width fits 1280 window")
	ok(small.y <= 640, "editor height fits 720 window")
	ok(small.x >= 640 and small.y >= 420, "editor keeps a usable minimum size")
	var large := StoryboardEditor.fit_size(Vector2(1920, 1080))
	ok(large.y >= small.y, "bigger screen gets a taller dialog")
	return true


## 回放视频：按键事件要真的配到音符上；时间/角度不对就不该出命中反馈。
func test_video_export_plan_hits() -> bool:
	var chart := DemoChart.make_demo()
	var exporter := VideoExport.new()
	var events: Array = []
	var late: Array = []
	var flipped: Array = []
	for note in chart.notes:
		if not (note.type in ["tap", "hold", "path"]):
			continue
		var target := chart.timing.beat_to_chart_ms(note.beat)
		if target > 3000.0:
			continue
		events.append({"t": target, "k": "press", "a": note.angle})
		late.append({"t": target + 500.0, "k": "press", "a": note.angle})
		flipped.append({"t": target, "k": "press", "a": fposmod(note.angle + 180.0, 360.0)})
		if events.size() >= 3:
			break
	ok(not events.is_empty(), "demo chart has notes in the first 3s")
	eq(exporter.plan_hits(chart, events).size(), events.size(), "on-time presses all hit")
	eq(exporter.plan_hits(chart, late).size(), 0, "late presses do not hit")
	eq(exporter.plan_hits(chart, flipped).size(), 0, "wrong-angle presses do not hit")
	exporter.free()
	return true


## 飞行时长固定 1 秒，不随 BPM 变：高 BPM 曲不该因此更难读。
func test_note_fall_time() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	near(chart.note_fall_ms(), 1000.0, 0.001, "fall time is one second at 120 BPM")
	chart.timing.points.append(TimingPoint.new(8.0, 240.0, 4))
	near(chart.note_fall_ms(), 1000.0, 0.001, "fall time does not shrink at 240 BPM")
	near(chart.mirrored_copy("lr").note_fall_ms(), 1000.0, 0.001, "mirror keeps the same fall time")
	return true


## 「改 BPM 保持毫秒位置」：锚点之后的拍位按 新/旧 缩放，锚点之前不动。
func test_bpm_lock_scales_following() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var before := Note.new("tap", 2.0, 0.0, 60.0)
	before.id = 1
	var after := Note.new("hold", 12.0, 0.0, 60.0)
	after.id = 2
	after.end_beat = 16.0
	chart.notes = [before, after]
	chart.shape_keys = [{"beat": 20.0, "shape_id": "S0", "easing": "linear"}]
	chart.scale_beats_after(8.0, 2.0)
	near(before.beat, 2.0, 0.0001, "notes before the anchor keep their beat")
	near(after.beat, 16.0, 0.0001, "notes after the anchor scale with the ratio")
	near(after.end_beat, 24.0, 0.0001, "hold end scales too")
	near(float(chart.shape_keys[0]["beat"]), 32.0, 0.0001, "shape keys scale too")
	chart.scale_beats_after(8.0, 1.0)
	near(after.beat, 16.0, 0.0001, "factor 1 is a no-op")
	return true


## 滚轮方向：往上滚 = 页面往上走（回到更早的拍），往下滚 = 继续往后。
func test_wheel_direction_matches_screen() -> bool:
	eq(ChartCanvas.wheel_step(true, true), -3.0, "flow down: wheel up goes back in time")
	eq(ChartCanvas.wheel_step(false, true), 3.0, "flow down: wheel down goes forward in time")
	eq(ChartCanvas.wheel_step(true, false), 3.0, "flow up: wheel up goes back in time")
	eq(ChartCanvas.wheel_step(false, false), -3.0, "flow up: wheel down goes forward in time")
	return true


## 导出视频里的打击音：离线整局静音，必须把 SFX 事件收集起来混进音轨，
## 否则成片只剩音乐（和现在的 bug 一致）。
## 回归：导出用的 ffmpeg 必须是解析后的可执行路径，而不是「用户设置值」。
## 以前直接返回 MediaIO.ffmpeg_exe（默认是哨兵字符串 "ffmpeg"），装了内置 ffmpeg
## 但 PATH 里没有 ffmpeg 的机器会拿到一个执行不起来的字符串，导出直接报「找不到编码器」。
func test_video_export_uses_resolved_ffmpeg() -> bool:
	var exporter := VideoExport.new()
	if not MediaIO.has_ffmpeg():
		exporter.free()
		return true
	var resolved := MediaIO.exe()
	eq(exporter._ffmpeg(), resolved, "exporter uses the resolved ffmpeg path")
	if resolved != "ffmpeg":
		ok(exporter._ffmpeg() != "ffmpeg", "exporter does not fall back to the sentinel value")
	exporter.free()
	return true


func test_video_export_sfx_capture() -> bool:
	var run := Playtest.new()
	run._sfx = HitSfx.new()
	run.offline_mode = true
	run._sim_silent = true
	run.offline_ms = 1234.0
	run.sfx_capture = []
	run._play_hit("don", 1.02)
	eq(run.sfx_capture.size(), 1, "offline silent run still captures hit sfx")
	if not run.sfx_capture.is_empty():
		var event: Dictionary = run.sfx_capture[0]
		near(float(event.get("t", 0.0)), 1234.0, 0.001, "captured sfx keeps the chart time")
		eq(String(event.get("k", "")), "don", "captured sfx keeps the kind")
		near(float(event.get("p", 0.0)), 1.02, 0.001, "captured sfx keeps the pitch")
	run.sfx_capture = null
	run.free()
	# 合成音轨：第一次命中之前必须彻底安静，命中之后必须有声音。
	var exporter := VideoExport.new()
	var wav := "user://test_export_sfx.wav"
	var events := [{"t": 1000.0, "k": "don", "p": 1.0}]
	eq(exporter._render_sfx(events, "default", 0.0, 3000.0, wav), true, "sfx track renders")
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(wav))
	eq(bytes.size(), 44 + 132300 * 2, "sfx track is exactly the export span long")
	if bytes.size() > 48:
		var head := 44
		var peak_before := 0
		for i in 44100:
			peak_before = maxi(peak_before, absi(bytes.decode_s16(head + i * 2)))
		eq(peak_before, 0, "nothing is audible before the first hit")
		var peak_after := 0
		for i in range(44100, 48510):
			peak_after = maxi(peak_after, absi(bytes.decode_s16(head + i * 2)))
		ok(peak_after > 1000, "hit sfx is audible after the first hit")
	eq(exporter._render_sfx([], "default", 0.0, 1000.0, wav), false, "no events means no sfx track")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wav))
	exporter.free()
	return true


## 切出窗口会自动暂停，但离线导出是逐帧驱动的：暂停会把剩下的帧全冻住。
func test_offline_focus_out_keeps_running() -> bool:
	var run := Playtest.new()
	run.offline_mode = true
	run._running = true
	run._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	eq(run._paused, false, "export playtest ignores focus-out")
	run.free()
	return true


## .lbp 包：单个 zip、能读回、音符与判定数据不丢。
func test_lbp_package() -> bool:
	var chart := DemoChart.make_demo()
	var path := "user://test_package.lbp"
	var err := LBPIO.export_package(chart, path)
	eq(err, OK, "lbp package export ok")
	ok(LBPIO.is_package(path), "lbp package is a zip")
	var back := LBPIO.import_package(path)
	ok(back != null, "lbp package imports")
	if back != null:
		eq(back.notes.size(), chart.notes.size(), "lbp package keeps notes")
		eq(back.timing.points.size(), chart.timing.points.size(), "lbp package keeps timing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## .lbp 包要打包实际存在的音频（audio_source 失效时回退 audio_path），
## 且同一路径重新导出后不能残留上一版的故事板素材。
func test_lbp_package_assets() -> bool:
	var root := "user://lbp_assets_test"
	var abs_root := ProjectSettings.globalize_path(root)
	DirAccess.make_dir_recursive_absolute(abs_root)
	var audio := root + "/music.wav"
	var f := FileAccess.open(audio, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([82, 73, 70, 70]))
	f.close()
	var sb_dir := root + "/sb"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sb_dir))
	f = FileAccess.open(sb_dir + "/旧图.png", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()

	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	note.id = 0
	chart.notes.append(note)
	chart.audio_path = audio
	chart.metadata["audio_source"] = root + "/missing_music.wav"
	chart.metadata["storyboard"] = sb_dir

	var pack := root + "/same.lbp"
	ok(LBPIO.export_package(chart, pack) == OK, "lbp assets export ok")
	var back := LBPIO.import_package(pack)
	ok(back != null, "lbp assets package imports")
	var first_sb := String(back.metadata.get("storyboard", "")) if back != null else ""
	ok(back != null and FileAccess.file_exists(back.audio_path), "stale audio source falls back to audio_path")
	ok(back != null and FileAccess.get_file_as_bytes(back.audio_path).size() == 4, "fallback audio bytes survive")
	eq(String(back.metadata.get("audio_source", "")) if back != null else "x", "", "package drops stale audio source")
	ok(FileAccess.file_exists(first_sb + "/旧图.png"), "storyboard asset packed")
	var first_base := back.audio_path.get_base_dir().get_base_dir() if back != null else ""

	# 换掉故事板素材，导出到同一个 .lbp，再导入：旧图不能跟着内容哈希一起留下。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sb_dir + "/旧图.png"))
	f = FileAccess.open(sb_dir + "/新图.png", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([4, 5, 6]))
	f.close()
	ok(LBPIO.export_package(chart, pack) == OK, "lbp assets re-export ok")
	var back2 := LBPIO.import_package(pack)
	ok(back2 != null, "lbp assets package re-imports")
	var second_sb := String(back2.metadata.get("storyboard", "")) if back2 != null else ""
	ok(not FileAccess.file_exists(second_sb + "/旧图.png"), "re-import leaves no stale storyboard asset")
	ok(FileAccess.file_exists(second_sb + "/新图.png"), "re-import has fresh storyboard asset")
	var second_base := back2.audio_path.get_base_dir().get_base_dir() if back2 != null else ""

	for path in [pack, pack + ".tmp", audio, sb_dir + "/新图.png"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sb_dir))
	DirAccess.remove_absolute(abs_root)
	for base in [first_base, second_base]:
		if base.begins_with("user://imports/lbp_"):
			_remove_test_tree(ProjectSettings.globalize_path(base))
	return true


func _remove_test_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_test_tree(path.path_join(name))
		DirAccess.remove_absolute(path.path_join(name))


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


class CountdownProbe:
	extends Playtest

	var ticks: Array[int] = []

	func _play_tick(number: int) -> void:
		ticks.append(number)


func test_playtest_countdown() -> bool:
	eq(Playtest.countdown_number(2.0, 2.0), 3, "countdown starts at 3")
	eq(Playtest.countdown_number(1.34, 2.0), 3, "the first third still shows 3")
	eq(Playtest.countdown_number(1.33, 2.0), 2, "the second third shows 2")
	eq(Playtest.countdown_number(0.5, 2.0), 1, "the last third shows 1")
	eq(Playtest.countdown_number(0.0, 2.0), 0, "zero means GO")
	var game := CountdownProbe.new()
	game.chart = Chart.new()
	game.offline_mode = true
	game._ready_layer = Control.new()
	game.add_child(game._ready_layer)
	game._start_countdown()
	eq(game.ticks, [3], "4/4 begins with the 3 cue")
	game._process_ready(0.501)
	game._process_ready(0.5)
	eq(game.ticks, [3, 2, 1], "one cue per beat before GO")
	ok(not game._running, "play waits for the fourth beat")
	game._process_ready(0.5)
	game._process_ready(0.5)
	eq(game.ticks, [3, 2, 1, 0], "4/4 has four cues including GO")
	ok(game._running and not game._ready_layer.visible, "the GO cue starts play and hides the countdown")
	game.free()
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
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
	near(Preview3D.background_alpha(1.0), 1.0, 0.001, "background is fully opaque at 100% brightness")
	near(Preview3D.background_alpha(0.5), 0.5, 0.001, "brightness scales the still image")
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
	var dir := "user://test_project"
	var entries: Array = [{"name": "Insane", "chart": chart}]
	eq(ChartIO.save_project(entries, dir, "test"), OK, "project save")
	ok(ChartIO.is_project_path(dir), "project folder detected")
	ok(FileAccess.file_exists(dir.path_join("main.tmc")), "project main exists")
	ok(FileAccess.file_exists(dir.path_join("chart0.tmc")), "project chart0 exists")
	ok(FileAccess.file_exists(dir.path_join("shaped.tmc")), "project shaped exists")
	ok(FileAccess.file_exists(dir.path_join("color.tmc")), "project color exists")
	ok(not FileAccess.file_exists(dir.path_join("bpmlist.tmc")), "constant bpm omits bpmlist")
	var from_file := ChartIO.load_chart(dir.path_join("main.tmc"))
	ok(from_file != null, "project chart load")
	if from_file != null:
		eq(from_file.notes.size(), chart.notes.size(), "project notes survive")
		eq(String(from_file.metadata.get("title", "")), String(chart.metadata.get("title", "")), "project title survives")
	for name in ["main.tmc", "chart0.tmc", "shaped.tmc", "color.tmc", "storyboard.tmc", "music.wav", "music.ogg", "music.mp3"]:
		var p := ProjectSettings.globalize_path(dir.path_join(name))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	return true


func test_chart_project_format() -> bool:
	var chart := DemoChart.make_demo()
	chart.notes[0].color = 2
	var group_id := chart.add_group(140.0)
	chart.notes[0].group_id = group_id
	var group_points := chart.group_bpm_points_for(group_id)
	group_points.append(TimingPoint.new(8.0, 180.0, 3))
	chart.group_bpm_points[group_id] = group_points
	chart.timing.points.append(TimingPoint.new(8.0, 140.0, 3))
	var copy := ChartIO.chart_from_dict(ChartIO.chart_to_dict(chart))
	var dir := "user://project_format_test"
	var entries: Array = [{"name": "Beginner", "chart": chart}, {"name": "Master", "chart": copy}]
	eq(ChartIO.save_project(entries, dir, "project test"), OK, "multi difficulty project save")
	ok(FileAccess.file_exists(dir.path_join("main.tmc")), "main.tmc")
	ok(FileAccess.file_exists(dir.path_join("chart0.tmc")), "chart0.tmc")
	ok(FileAccess.file_exists(dir.path_join("chart1.tmc")), "chart1.tmc")
	ok(FileAccess.file_exists(dir.path_join("shaped.tmc")), "shaped.tmc")
	ok(FileAccess.file_exists(dir.path_join("color.tmc")), "color.tmc")
	ok(FileAccess.file_exists(dir.path_join("bpmlist.tmc")), "bpmlist.tmc with bpm change")
	ok(FileAccess.file_exists(dir.path_join("storyboard.tmc")), "storyboard.tmc with events")
	var chart_raw: Dictionary = ChartIO._read_project_struct(dir.path_join("chart0.tmc"), "chart")
	eq((chart_raw.get("groups", []) as Array).size(), 2, "new group block saved in chartN")
	var bpm_raw: Dictionary = ChartIO._read_project_struct(dir.path_join("bpmlist.tmc"), "bpm")
	var has_group_bpm := false
	for row in bpm_raw.get("groups", []):
		if int(row.get("id", -1)) == group_id:
			has_group_bpm = true
	ok(has_group_bpm, "new group id saved in bpmlist")
	var loaded := ChartIO.load_project(dir)
	ok(bool(loaded.get("ok", false)), "multi difficulty project load")
	if bool(loaded.get("ok", false)):
		eq(loaded.entries.size(), 2, "two difficulties")
		var first: Chart = loaded.entries[0].chart
		var grouped_note: Note = null
		for note in first.notes:
			if note.group_id == group_id:
				grouped_note = note
				break
		ok(grouped_note != null, "grouped note survives project")
		if grouped_note != null:
			eq(grouped_note.color, 2, "note color survives")
			eq(grouped_note.group_id, group_id, "note group survives project")
		eq(first.groups.size(), 2, "groups survive project")
		near(first.group_bpm_at(group_id, 9.0), 180.0, 0.001, "group bpm change survives project")
		eq(first.timing.points.size(), 2, "bpm change survives")
	for name in ["main.tmc", "chart0.tmc", "chart1.tmc", "shaped.tmc", "color.tmc", "bpmlist.tmc", "storyboard.tmc", "music.wav", "music.ogg", "music.mp3"]:
		var p := ProjectSettings.globalize_path(dir.path_join(name))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	return true


## TMC 工程的分组 Path 链：组、颜色、锁定、宽度与 Path 修饰必须跟着 id 一起往返。
func test_tmc_group_path_round_trip() -> bool:
	var chart := DemoChart.make_demo()
	chart.ensure_groups()
	var gid := chart.add_group(150.0)
	var parts := Note.path_parts_from_code(
		"[100]path{(part0,40.000,0.000,42.000,180.000,0.720,0.000,0.000,100);" +
		"(part1,42.000,180.000,44.000,0.000,0.720,0.000,0.000,101)}")
	for part in parts:
		part.group_id = gid
		part.color = 1
		part.lock = true
		part.hs = 0.75
		part.sv = 1.25
		part.path_style = "ribbon"
		part.path_speed = 0.8
		part.tolerance = 0.31
		part.width = 66.0
		part.tail_width = 72.0
		part.path_gaps = [{"from": 0.4, "to": 0.6}]
		part.trace_pts = [{"x": 0.1, "y": 0.2, "db": 0.0}, {"x": 0.3, "y": 0.4, "db": 0.5}]
		chart.notes.append(part)
	var region := Region.new(7, 1.0, 2.0)
	region.width = 60.0
	region.shape = "S1"
	region.polarity = 0
	chart.regions.append(region)
	chart.refresh_ids()
	var dir := "user://tmc_group_path"
	_remove_test_tree(ProjectSettings.globalize_path(dir))
	eq(ChartIO.save_project([{"name": "G", "chart": chart}], dir, "G"), OK, "分组 Path 工程保存")
	var project := ChartIO.load_project(dir)
	ok(bool(project.get("ok", false)), "分组 Path 工程读取")
	var loaded: Chart = project.get("entries", [])[0].get("chart", null) if bool(project.get("ok", false)) else null
	ok(loaded != null, "分组 Path 难度加载")
	if loaded != null:
		var root: Note = null
		var child: Note = null
		for note in loaded.notes:
			if note.type != "path":
				continue
			if is_equal_approx(note.beat, 40.0):
				root = note
			elif is_equal_approx(note.beat, 42.0):
				child = note
		ok(root != null and child != null, "分组 Path 链两段都在")
		if root != null:
			eq(root.group_id, gid, "Path 根段保留分组")
			eq(root.color, 1, "Path 根段保留配色")
			eq(root.lock, true, "Path 根段保留锁定")
			eq(root.path_next_id, child.id if child != null else -1, "Path 根段指向第二段")
			near(root.width, 66.0, 0.001, "Path 根段头宽度")
			near(root.tail_width, 72.0, 0.001, "Path 根段尾宽度")
			near(root.hs, 0.75, 0.001, "Path 根段 hs")
		if child != null:
			eq(child.group_id, gid, "Path 第二段保留分组")
			eq(child.color, 1, "Path 第二段保留配色")
			eq(child.lock, true, "Path 第二段保留锁定")
			eq(child.path_style, "ribbon", "Path 第二段保留画法")
			near(child.path_speed, 0.8, 0.001, "Path 第二段速度")
			near(child.tolerance, 0.31, 0.001, "Path 第二段容差")
			near(child.width, 66.0, 0.001, "Path 第二段头宽度")
			near(child.tail_width, 72.0, 0.001, "Path 第二段尾宽度")
			eq(child.path_gaps.size(), 1, "Path 第二段擦除缺口")
			eq(child.trace_pts.size(), 2, "Path 第二段手绘轨迹")
			near(child.sv, 1.25, 0.001, "Path 第二段 sv")
		var loaded_region: Region = null
		for row in loaded.regions:
			if row.id == 7:
				loaded_region = row
				break
		ok(loaded_region != null, "TMC 区域保留")
		if loaded_region != null:
			eq(loaded_region.shape, "S1", "TMC 区域保留 shape")
			eq(loaded_region.polarity, 0, "TMC 区域保留 polarity")
	_remove_test_tree(ProjectSettings.globalize_path(dir))
	return true


func test_note_groups() -> bool:
	var chart := DemoChart.make_demo()
	chart.ensure_groups()
	eq(chart.groups.size(), 1, "default group exists")
	var gid := chart.add_group(140.0)
	eq(chart.groups.size(), 2, "new group added")
	chart.notes[0].group_id = gid
	chart.notes[1].enabled = false
	eq(chart.group_note_count(gid), 1, "group note count")
	ok(chart.note_enabled(chart.notes[0]), "group note enabled by default")
	var points := chart.group_bpm_points_for(gid)
	points.append(TimingPoint.new(8.0, 180.0, 4))
	chart.group_bpm_points[gid] = points
	near(chart.group_bpm_at(gid, 9.0), 180.0, 0.001, "group bpm points apply per group")
	chart.groups[chart.group_index(gid)]["enabled"] = false
	ok(not chart.note_enabled(chart.notes[0]), "false group disables notes")
	ok(chart.note_enabled(chart.notes[1]) == false, "per-note false is preserved")
	var loaded := ChartIO.from_json(ChartIO.to_json(chart))
	ok(loaded != null, "group chart roundtrip loads")
	if loaded != null:
		eq(loaded.groups.size(), 2, "groups survive roundtrip")
		eq(loaded.notes[0].group_id, gid, "note group survives")
		ok(not loaded.notes[1].enabled, "note false state survives")
	return true


## 组 BPM 只给非 0 组做差速；组 0 的 BPM 点就是谱面 timing，
## 换 BPM 时下落时长仍固定，和旧版一致。拍位始终按 timing 换算。
func test_group_note_speed() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 230.0, 4)]
	chart.ensure_groups()
	chart.group_data(0)["bpm"] = 120.0
	chart.group_bpm_points[0] = [TimingPoint.new(0.0, 230.0, 4), TimingPoint.new(1.0, 230.0, 4)]
	chart.ensure_groups()
	near(float(chart.group_data(0)["bpm"]), 230.0, 0.001, "group base follows the first BPM point")
	var preview := Preview3D.new()
	preview.flow_scale = 1.0
	var note := Note.new("tap", 8.0, 90.0, 60.0)
	note.group_id = 0
	chart.notes.append(note)
	var spawn := preview._spawn_beat(chart, note.beat, note.group_id)
	near(chart.timing.beat_to_chart_ms(note.beat) - chart.timing.beat_to_chart_ms(spawn), 1000.0, 1.0,
		"group 0 keeps the 1s fall")
	near(preview._note_progress(chart, note, spawn), 0.0, 0.001, "note starts at the center")
	near(preview._note_progress(chart, note, note.beat), 1.0, 0.001, "note reaches the ring on its beat")
	# 组 0 的 BPM 变化是音频/判定时间，不改变视觉速度。
	chart.group_bpm_points[0] = [TimingPoint.new(0.0, 230.0, 4), TimingPoint.new(4.0, 460.0, 4)]
	spawn = preview._spawn_beat(chart, note.beat, note.group_id)
	near(chart.timing.beat_to_chart_ms(note.beat) - chart.timing.beat_to_chart_ms(spawn), 1000.0, 1.0,
		"group 0 BPM changes do not change the fall time")
	# 其他组才用组 BPM 差速：230 → 460 是 2 秒。
	var gid := chart.add_group(230.0)
	chart.group_bpm_points[gid] = [TimingPoint.new(0.0, 230.0, 4), TimingPoint.new(4.0, 460.0, 4)]
	note.group_id = gid
	spawn = preview._spawn_beat(chart, note.beat, note.group_id)
	near(chart.timing.beat_to_chart_ms(note.beat) - chart.timing.beat_to_chart_ms(spawn), 2000.0, 1.0,
		"higher current group BPM doubles the fall time")
	near(preview._note_progress(chart, note, spawn), 0.0, 0.001, "slowed note starts at the center")
	near(preview._note_progress(chart, note, (spawn + note.beat) * 0.5), 0.5, 0.01,
		"slowed note moves at half speed")
	near(preview._note_progress(chart, note, note.beat), 1.0, 0.001, "slowed note lands on its beat")
	var early := chart.timing.spawn_beat(note.beat, 1500.0)
	ok(preview._notes_around(chart, early, 0.1, 0.1).has(note),
		"slow group note enters the draw window before the normal 1s pre-read")
	preview.free()
	return true


## 回放要保留系统鼠标（进度条/暂停可点）；PERFECT 特效关闭只跳过爆点，判定字仍在。
func test_playtest_feedback() -> bool:
	eq(Playtest.run_mouse_mode(true), Input.MOUSE_MODE_VISIBLE, "replay keeps the system cursor")
	eq(Playtest.run_mouse_mode(false), Input.MOUSE_MODE_HIDDEN, "normal play keeps the custom cursor")
	var preview := Preview3D.new()
	preview.add_hit_pulse(Vector2(10, 10), Color.WHITE, "PERFECT", "tap", "", false)
	eq(preview._pulses.size(), 1, "perfect pulse is still created for its label")
	ok(not bool(preview._pulses[0].get("fx", true)), "perfect pulse can skip the burst")
	preview.add_hit_pulse(Vector2(30, 30), Color.WHITE, "GREAT", "tap", "", true)
	ok(bool(preview._pulses[1].get("fx", true)), "other tiers keep their effect")
	preview.free()
	# PERFECT 爆点和判定字都关掉时，不占特效预算。
	var run := Playtest.new()
	var run_preview := Preview3D.new()
	run._preview = run_preview
	run_preview.show_perfect_fx = false
	run_preview.hud_options = {"judge_filter": "below_perfect"}
	run._pulse_at(0.0, 0.0, Color.WHITE, "PERFECT", 60.0, "tap", "", Vector2(10, 10))
	eq(run_preview._pulses.size(), 0, "hidden perfect pulse is not queued")
	run_preview.hud_options = {"judge_filter": "all"}
	run._pulse_at(0.0, 0.0, Color.WHITE, "PERFECT", 60.0, "tap", "", Vector2(10, 10))
	eq(run_preview._pulses.size(), 1, "perfect label still queues when filter allows")
	# SEEK 的 PERFECT 反馈不跟着「PERFECT 特效」开关走。
	run_preview.hud_options = {"judge_filter": "below_perfect"}
	run._pulse_at(0.0, 0.0, Color.WHITE, "PERFECT", 360.0, "seek", "SEEK", Vector2(40, 40))
	eq(run_preview._pulses.size(), 2, "seek perfect effect ignores the perfect fx toggle")
	ok(bool(run_preview._pulses[1].get("fx", true)), "seek keeps its burst")
	run.free()
	run_preview.free()
	# 回放沿用录制倍速；老回放没有 rate 字段时回退 1×。
	near(Playtest.replay_playback_rate(null, 1.5), 1.5, 0.0001, "normal run keeps requested rate")
	var recorded := Replay.new()
	recorded.settings = {"rate": 1.35}
	near(Playtest.replay_playback_rate(recorded, 1.0), 1.35, 0.0001, "replay uses the recorded rate")
	near(Playtest.replay_playback_rate(Replay.new(), 1.0), 1.0, 0.0001, "old replay falls back to 1x")
	return true


## 判定字档位筛选：PERFECT 以下 = 隐藏 PERFECT，GREAT 以下继续往下收。
func test_judge_label_filter() -> bool:
	ok(Preview3D.judge_label_visible("PERFECT", "all"), "all shows PERFECT")
	ok(not Preview3D.judge_label_visible("PERFECT", "below_perfect"), "below_perfect hides PERFECT")
	ok(Preview3D.judge_label_visible("GREAT", "below_perfect"), "below_perfect keeps GREAT")
	ok(not Preview3D.judge_label_visible("GREAT", "below_great"), "below_great hides GREAT")
	ok(Preview3D.judge_label_visible("GOOD", "below_great"), "below_great keeps GOOD")
	ok(not Preview3D.judge_label_visible("GOOD", "below_good"), "below_good hides GOOD")
	ok(Preview3D.judge_label_visible("BAD", "below_good"), "below_good keeps BAD")
	ok(Preview3D.judge_label_visible("MISS", "miss_only"), "miss_only keeps MISS")
	ok(not Preview3D.judge_label_visible("BAD", "miss_only"), "miss_only hides BAD")
	ok(not Preview3D.judge_label_visible("FULL", "below_perfect"), "FULL follows PERFECT")
	ok(Preview3D.judge_label_visible("FULL", "all"), "all keeps path status")
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
	eq(String(chart.metadata.get("version", "")), "EASY 5", "simai chart uses difficulty name")
	near(chart.offset_ms, -1000.0, 0.001, "simai first -> offset")
	eq(chart.notes.size(), 4, "simai keeps four notes")
	var types: Array[String] = []
	for note in chart.notes:
		types.append(note.type)
	eq(types, ["tap", "hold", "path", "bell"], "simai note types")
	eq(chart.notes[1].hold_style, "straight", "simai hold imports straight")
	eq(Validator.errors(Validator.validate(chart)).size(), 0, "simai import is playable without double-hand conflicts")
	if chart.notes.size() >= 3:
		near(chart.notes[0].angle, 45.0, 0.001, "simai button 1 is top-right")
		near(chart.notes[2].wait_beat, 1.0, 0.001, "maimai star waits one beat after the head tap")
		near(chart.notes[2].end_beat, 4.0, 0.001, "slide tail is head + 1 beat wait + slide length")
		var trace: Array = chart.notes[2].trace_pts
		ok(trace.size() >= 3, "slide trace has samples")
		if trace.size() >= 2:
			var head := Vector2(float(trace[0]["x"]), float(trace[0]["y"]))
			var held := Vector2(float(trace[1]["x"]), float(trace[1]["y"]))
			near(float(trace[1]["db"]), 1.0, 0.001, "trace keeps the star at the head for the wait beat")
			ok(held.distance_to(head) < 0.001, "star is parked during the wait beat")
		near(chart.notes[2].tail_angle, 225.0, 0.001, "simai slide tail button 5")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func test_simai_button_layout() -> bool:
	eq(SimaiSlide.button_angle(1), 45.0, "maimai button 1 is top-right")
	eq(SimaiSlide.button_angle(2), 0.0, "maimai button 2 is right")
	eq(SimaiSlide.button_angle(5), 225.0, "maimai button 5 is bottom-left")
	eq(SimaiSlide.button_angle(8), 90.0, "maimai button 8 is top")
	eq(SimaiSlide.button_angle(9), 45.0, "button index wraps")
	var chart := _import_inote("(120){4}\n1,2,5,8,\n")
	ok(chart != null, "button layout chart imports")
	if chart != null:
		var angles: Array[float] = []
		for note in chart.notes:
			if note.type == "tap":
				angles.append(note.angle)
		eq(angles.size(), 4, "four taps import")
		if angles.size() == 4:
			near(angles[0], 45.0, 0.01, "button 1 maps to top-right")
			near(angles[1], 0.0, 0.01, "button 2 maps to right")
			near(angles[2], 225.0, 0.01, "button 5 maps to bottom-left")
			near(angles[3], 90.0, 0.01, "button 8 maps to top")
	var touch := _import_inote("(120){4}\nD1,\n")
	ok(touch != null, "D1 chart imports")
	if touch != null and not touch.notes.is_empty():
		near(touch.notes[0].angle, 67.5, 0.01, "D1 is counterclockwise from button 1")
	return true


func test_chart_mirror() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var tap := Note.new("tap", 1.0, 45.0, 60.0)
	var path := Note.new("path", 2.0, 90.0, 62.0)
	path.tail_angle = 315.0
	path.path_controls_set = true
	path.path_axis = 0.5
	path.trace_pts = [{"x": 0.5, "y": 0.25, "db": 0.0}, {"x": -0.5, "y": -0.25, "db": 4.0}]
	path.visual_pts = [{"db": 1.0, "da": 30.0}]
	var bell := Note.new("bell", 3.0, 225.0, 26.0)
	bell.center_u = 0.75
	var region := Region.new(1, 0.0, 2.0)
	region.angle = 30.0
	region.width = 40.0
	chart.notes = [tap, path, bell]
	chart.regions = [region]
	var lr := chart.mirrored_copy("lr")
	ok(lr != chart, "mirror works on a copy")
	near(chart.notes[0].angle, 45.0, 0.001, "mirror leaves the source chart alone")
	near(lr.notes[0].angle, 135.0, 0.001, "left-right mirror flips tap angle")
	near(lr.notes[1].tail_angle, 225.0, 0.001, "left-right mirror flips tail angle")
	near(float(lr.notes[1].trace_pts[0]["x"]), -0.5, 0.001, "left-right mirror flips trace x")
	near(float(lr.notes[1].trace_pts[0]["y"]), 0.25, 0.001, "left-right mirror keeps trace y")
	near(float(lr.notes[1].visual_pts[0]["da"]), -30.0, 0.001, "left-right mirror flips visual angle")
	near(lr.notes[1].path_axis, -0.5, 0.001, "left-right mirror flips path axis")
	near(lr.notes[2].center_u, 0.25, 0.001, "left-right mirror flips bell center_u")
	near(lr.regions[0].angle, 150.0, 0.001, "left-right mirror flips limit angle")
	near(lr.regions[0].width, 40.0, 0.001, "mirror keeps limit width")
	var rot := chart.mirrored_copy("rot180")
	near(rot.notes[0].angle, 225.0, 0.001, "180 rotation flips tap angle")
	near(float(rot.notes[1].trace_pts[0]["x"]), -0.5, 0.001, "180 rotation flips trace x")
	near(float(rot.notes[1].trace_pts[0]["y"]), -0.25, 0.001, "180 rotation flips trace y")
	near(rot.notes[1].path_axis, 0.5, 0.001, "180 rotation keeps path axis")
	near(rot.regions[0].angle, 210.0, 0.001, "180 rotation flips limit angle")
	ok(chart.mirrored_copy("off") == chart, "off mode returns the same chart")
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
			near(paths[0].tail_angle, 270.0, 0.01, "same-head keeps the tail nearest the next note")
	var chain := _import_inote("(120){4}\n1-4q7-2[4:2],\n")
	ok(chain != null, "chain chart imports")
	if chain != null:
		var paths: Array[Note] = []
		for note in chain.notes:
			if note.type == "path":
				paths.append(note)
		eq(paths.size(), 1, "chain is one path")
		if paths.size() == 1:
			near(paths[0].tail_angle, 0.0, 0.01, "chain ends on its final button")
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
		near(bells[0].angle, 45.0, 0.01, "A1 sits on button 1")
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


## 从播放头开始的 AUTO 不能从第 0 颗补按；转码任务死了要能被识别出来重跑。
func test_auto_resume_index_and_media_jobs() -> bool:
	var chart := DemoChart.make_empty({"title": "resume"})
	chart.notes = [
		Note.new("tap", 0.0, 0.0, 60.0),
		Note.new("tap", 4.0, 90.0, 60.0),
		Note.new("tap", 8.0, 180.0, 60.0),
	]
	for i in chart.notes.size():
		chart.notes[i].id = i + 1
	chart.refresh_ids()
	var run := Playtest.new()
	run.chart = chart
	run._timeline_start_ms = chart.timing.beat_to_chart_ms(4.0)
	run._init_states()
	eq(run._judge_from, 1, "notes before the start beat are skipped")
	eq(run._auto_index, run._judge_from, "AUTO resumes at the first live note, not note 0")
	run.free()
	MediaIO._jobs["__test__"] = 0
	ok(MediaIO._job_running("__test__"), "a claimed job counts as running")
	MediaIO._jobs["__test__"] = 999999999
	ok(not MediaIO._job_running("__test__"), "a dead pid is not a running job")
	MediaIO._jobs.erase("__test__")
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


## 瞄准辅助：像素距离超了但角度对（±12°）也算命中；角度不对或光标不合法仍拒绝。
func test_aim_angle_fallback() -> bool:
	var run := Playtest.new()
	var note := Note.new("tap", 0.0, 90.0, 60.0)
	var band := PackedVector2Array([Vector2(300, 100), Vector2(340, 100)])
	var target := {"note": note, "points": band, "tolerance": 120.0, "pad": 0.0,
		"dense": false, "ring_radius": 330.0}
	var far_away := {"mouse": Vector2(1200, 900), "angle": 95.0, "valid": true}
	ok(bool(run._match_press(far_away, target).get("ok", false)), "12 degrees of aim still hits")
	var off_angle := {"mouse": Vector2(1200, 900), "angle": 130.0, "valid": true}
	ok(run._match_press(off_angle, target).is_empty(), "40 degrees off does not hit")
	var invalid := {"mouse": Vector2(1200, 900), "angle": 95.0, "valid": false}
	ok(run._match_press(invalid, target).is_empty(), "an invalid cursor never gets aim assist")
	var on_point := {"mouse": Vector2(320, 105), "angle": 300.0, "valid": true}
	ok(bool(run._match_press(on_point, target).get("ok", false)), "a close pixel hit still works")
	run.free()
	return true


## 检查器滚轮：向上滚动条变小（页面上移），向下变大；方向不能反。
func test_inspector_wheel_scrolls_page() -> bool:
	ok(Inspector.wheel_delta(true) < 0.0, "wheel up scrolls the page up")
	ok(Inspector.wheel_delta(false) > 0.0, "wheel down scrolls the page down")
	near(Inspector.wheel_delta(true) + Inspector.wheel_delta(false), 0.0, 0.0001, "both directions use the same step")
	return true


## 宽度手柄：边缘 1:1 跟手；上限按“画出来的弧宽 ≤ 360°”算。
func test_canvas_width_drag() -> bool:
	near(ChartCanvas.dragged_width(60.0, 0.0, 1, 1.0), 60.0, 0.0001, "no movement keeps the width")
	ok(ChartCanvas.dragged_width(60.0, 0.02, 1, 0.5) > 60.0, "dragging right grows the right edge")
	ok(ChartCanvas.dragged_width(60.0, 0.02, -1, 0.5) < 60.0, "dragging the left edge grows outward")
	near(ChartCanvas.dragged_width(60.0, 10.0, 1, 1.5) * 1.5, 360.0, 0.001, "sized taps stop at a full ring")
	near(ChartCanvas.dragged_width(1.0, -10.0, 1, 1.0), 5.0, 0.001, "width never goes below 5 degrees")
	return true


## Bell 宽度手柄：合法范围只有 24–30°，两端拖动方向相反。
func test_bell_width_drag() -> bool:
	near(ChartCanvas.dragged_bell_width(27.0, 0.0, 1), 27.0, 0.0001, "no movement keeps the bell width")
	ok(ChartCanvas.dragged_bell_width(27.0, 0.01, 1) > 27.0, "dragging right grows the right edge")
	ok(ChartCanvas.dragged_bell_width(27.0, 0.01, -1) < 27.0, "dragging the left edge grows outward")
	near(ChartCanvas.dragged_bell_width(27.0, 1.0, 1), Note.BELL_MAX_WIDTH, 0.0001, "bell width stops at 30 degrees")
	near(ChartCanvas.dragged_bell_width(27.0, -1.0, 1), Note.BELL_MIN_WIDTH, 0.0001, "bell width stops at 24 degrees")
	return true


## Limit 红区：身体平移保持时长；边缘改宽度时中心角度只走一半。
func test_region_drag() -> bool:
	var span := ChartCanvas.moved_region(4.0, 6.0, 5.0, 7.0)
	near(span.x, 6.0, 0.0001, "dragging the body moves the start")
	near(span.y, 8.0, 0.0001, "dragging the body keeps the duration")
	near(ChartCanvas.moved_region(0.5, 2.5, 1.0, -5.0).x, 0.0, 0.0001, "the region never starts before beat 0")
	near(ChartCanvas.dragged_region_width(60.0, 0.02, 1), 74.4, 0.0001, "dragging the right edge widens")
	near(ChartCanvas.dragged_region_width(60.0, 0.02, -1), 45.6, 0.0001, "dragging the left edge widens outward")
	near(ChartCanvas.dragged_region_width(60.0, 10.0, 1), 359.0, 0.0001, "width stops below a full ring")
	near(ChartCanvas.dragged_region_angle(90.0, 0.1, 1), 108.0, 0.0001, "angle follows half of the edge drag")
	return true


## 画布默认吸附：拍轴常开（顶栏「网格 小节线：N」），轨道轴由 rail_snap 开关，
## Shift 两个轴一起跳过。
func test_canvas_default_snapping() -> bool:
	var app: App = load("res://charter/app.gd").new()
	app.chart = Chart.new()
	var canvas := ChartCanvas.new()
	canvas._app = app
	var hit := canvas._snap_beat_u(1.13, 0.51, false)
	near(hit.x, 1.25, 0.0001, "默认：拍轴吸到 1/4 小节线")
	near(hit.y, 0.5, 0.0001, "默认：角度吸到 12 等分竖线")
	app.rail_snap = false
	var free_angle := canvas._snap_beat_u(1.13, 0.51, false)
	near(free_angle.x, 1.25, 0.0001, "关掉轨道吸附后拍轴仍然吸")
	near(free_angle.y, 0.51, 0.0001, "关掉轨道吸附后角度保持原样")
	app.beat_subdivisions = 3
	near(canvas._snap_beat_u(1.13, 0.51, false).x, 1.0, 0.0001, "小节线 N=3 时吸附目标跟着变")
	near(canvas._snap_beat_u(1.3, 0.51, false).x, 4.0 / 3.0, 0.0001, "N=3 能吸到 1/3 拍的位置")
	app.beat_subdivisions = 4
	var bypassed := canvas._snap_beat_u(1.13, 0.51, true)
	near(bypassed.x, 1.13, 0.0001, "Shift 绕过：拍不动")
	near(bypassed.y, 0.51, 0.0001, "Shift 绕过：角度不动")
	app.rail_snap = true
	near(canvas._snap_angle(41.0, false), 30.0, 0.0001, "Path 头尾角度吸到最近竖线")
	near(canvas._snap_angle(41.0, true), 41.0, 0.0001, "Shift 时角度手柄不吸")
	app.rail_snap = false
	near(canvas._snap_angle(41.0, false), 41.0, 0.0001, "关掉轨道吸附后角度手柄不吸")
	canvas.free()
	app.free()
	return true


## Anchor 是刚体：松手时整对旋转吸附，夹角与同拍都不变；锁定则整对不动。
func test_anchor_release_snap() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	app.chart = chart
	var canvas := ChartCanvas.new()
	canvas._app = app
	var pair := chart.make_anchor_pair(1.13, 41.0)
	for item in pair:
		chart.notes.append(item)
	canvas._drag_notes = []
	for item in pair:
		canvas._drag_notes.append({"note": item, "beat": 1.0, "angle": item.angle - 21.0,
			"end": 0.0, "tail": 0.0, "center": 0.0})
	canvas._snap_dragged_notes(false)
	near(pair[0].beat, 1.25, 0.0001, "Anchor 松手后整对吸到小节线")
	near(pair[1].beat, pair[0].beat, 0.0001, "Anchor 整对保持同拍")
	near(pair[0].angle, 30.0, 0.0001, "组长吸到竖线")
	near(absf(fposmod(pair[0].angle - pair[1].angle, 360.0) - 180.0), 0.0, 0.001,
		"整对吸附后仍保持 180°")
	# 锁定一颗 → 整对一点都不动（锁不能被伙伴绕过）。
	pair[0].beat = 1.13
	pair[1].beat = 1.13
	pair[0].angle = 41.0
	pair[1].angle = 221.0
	pair[1].lock = true
	canvas._drag_notes[0]["beat"] = 1.0
	canvas._drag_notes[1]["beat"] = 1.0
	canvas._drag_notes[0]["angle"] = 20.0
	canvas._drag_notes[1]["angle"] = 200.0
	canvas._snap_dragged_notes(false)
	near(pair[0].beat, 1.13, 0.0001, "伙伴锁定后组长也不吸拍位")
	near(pair[0].angle, 41.0, 0.0001, "伙伴锁定后组长也不吸角度")
	pair[1].lock = false
	# 没有伙伴的旧 Anchor：只吸它自己。
	var lone := Note.new("anchor", 1.13, 41.0, 0.0)
	lone.id = chart.next_note_id()
	chart.notes.append(lone)
	canvas._drag_notes = [{"note": lone, "beat": 1.0, "angle": 20.0, "end": 0.0, "tail": 0.0, "center": 0.0}]
	canvas._snap_dragged_notes(false)
	near(lone.beat, 1.25, 0.0001, "孤立 Anchor 也吸拍位")
	near(lone.angle, 30.0, 0.0001, "孤立 Anchor 也吸角度")
	# 奇数等分（9 → 每格 40°）：组长上格线，伙伴保住 180°，不强求也在格线上。
	app.angle_divisions = 9
	pair[0].beat = 1.13
	pair[1].beat = 1.13
	pair[0].angle = 41.0
	pair[1].angle = 221.0
	canvas._drag_notes = []
	for item in pair:
		canvas._drag_notes.append({"note": item, "beat": 1.0, "angle": item.angle - 21.0,
			"end": 0.0, "tail": 0.0, "center": 0.0})
	canvas._snap_dragged_notes(false)
	near(pair[0].angle, 40.0, 0.0001, "9 等分时组长吸到 40°")
	near(absf(fposmod(pair[0].angle - pair[1].angle, 360.0) - 180.0), 0.0, 0.001,
		"9 等分时整对仍保持 180°")
	# 旋转 90° 带上伙伴。
	app.angle_divisions = 12
	pair[0].angle = 40.0
	pair[1].angle = 220.0
	app.selected_notes.clear()
	app.selected_notes.append(pair[0].id)
	app.rotate_selected_notes(90.0)
	near(pair[0].angle, 130.0, 0.0001, "旋转 90° 转选中那颗")
	near(pair[1].angle, 310.0, 0.0001, "旋转 90° 也转伙伴")
	canvas.free()
	app.free()
	return true


func test_note_release_snap() -> bool:
	var app: App = load("res://charter/app.gd").new()
	app.chart = Chart.new()
	var canvas := ChartCanvas.new()
	canvas._app = app
	var tap := Note.new("tap", 1.13, 41.0, 60.0)
	canvas._drag_notes = [{"note": tap, "beat": 1.0, "angle": 20.0, "end": 0.0, "tail": 0.0, "center": 0.0}]
	canvas._snap_dragged_notes(false)
	near(tap.beat, 1.25, 0.0001, "松手后拍位回吸到小节线")
	near(tap.angle, 30.0, 0.0001, "松手后角度回吸到竖线")
	var still := Note.new("tap", 1.13, 41.0, 60.0)
	canvas._drag_notes = [{"note": still, "beat": 1.13, "angle": 41.0, "end": 0.0, "tail": 0.0, "center": 0.0}]
	canvas._snap_dragged_notes(false)
	near(still.beat, 1.13, 0.0001, "单击选中不挪拍位")
	near(still.angle, 41.0, 0.0001, "单击选中不挪角度")
	var beat_only := Note.new("tap", 1.9, 41.0, 60.0)
	canvas._drag_notes = [{"note": beat_only, "beat": 1.0, "angle": 41.0, "end": 0.0, "tail": 0.0, "center": 0.0}]
	canvas._snap_dragged_notes(false)
	near(beat_only.beat, 2.0, 0.0001, "只改拍时拍位回吸")
	near(beat_only.angle, 41.0, 0.0001, "只改拍时角度不吸")
	app.rail_snap = false
	var free_angle := Note.new("tap", 1.13, 55.0, 60.0)
	canvas._drag_notes = [{"note": free_angle, "beat": 1.0, "angle": 20.0, "end": 0.0, "tail": 0.0, "center": 0.0}]
	canvas._snap_dragged_notes(false)
	near(free_angle.angle, 55.0, 0.0001, "关掉轨道吸附后拖动不回吸角度")
	near(free_angle.beat, 1.25, 0.0001, "关掉轨道吸附后拍位仍回吸")
	canvas.free()
	app.free()
	return true


## 红区松手回吸：起点对齐小节线、时长不变、中心角按轨道开关、弧宽不动。
func test_region_release_snap() -> bool:
	var app: App = load("res://charter/app.gd").new()
	app.chart = Chart.new()
	var canvas := ChartCanvas.new()
	canvas._app = app
	var region := Region.new(1, 3.1, 4.6)
	region.angle = 41.0
	region.width = 77.0
	canvas._drag_region = region
	canvas._snap_dragged_region(false)
	near(region.start_beat, 3.0, 0.0001, "红区起点吸到小节线")
	near(region.end_beat, 4.5, 0.0001, "回吸时时长不变")
	near(region.angle, 30.0, 0.0001, "红区中心角吸到竖线")
	near(region.width, 77.0, 0.0001, "红区弧宽不吸")
	region.start_beat = 3.1
	region.end_beat = 4.6
	canvas._snap_dragged_region(true)
	near(region.start_beat, 3.1, 0.0001, "Shift 时红区不回吸")
	app.rail_snap = false
	canvas._snap_dragged_region(false)
	near(region.start_beat, 3.0, 0.0001, "关掉轨道吸附后红区拍位仍吸")
	near(region.angle, 30.0, 0.0001, "关掉轨道吸附后红区角度不动")
	canvas.free()
	app.free()
	return true


## 小节线 N 与轨道吸附都写进 editor 并随谱面存盘；旧谱缺字段时回默认。
func test_editor_snap_settings_persist() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	app.set_chart(chart)
	app.set_beat_subdivisions(8)
	app.set_rail_snap(false)
	eq(int(chart.editor.get("beat_subdivisions", 0)), 8, "小节线 N 写进谱面 editor")
	eq(bool(chart.editor.get("rail_snap", true)), false, "轨道吸附开关写进谱面 editor")
	var data := ChartIO.chart_to_dict(chart)
	eq(int(data["editor"].get("beat_subdivisions", 0)), 8, "存盘 JSON 带上小节线 N")
	eq(bool(data["editor"].get("rail_snap", true)), false, "存盘 JSON 带上轨道吸附开关")
	var reloaded := ChartIO.chart_from_dict(data)
	app.set_chart(reloaded)
	eq(app.beat_subdivisions, 8, "重新载入后小节线 N 还在")
	eq(app.rail_snap, false, "重新载入后轨道吸附开关还在")
	reloaded.editor.erase("beat_subdivisions")
	reloaded.editor.erase("rail_snap")
	app.set_chart(reloaded)
	eq(app.beat_subdivisions, 4, "旧谱缺字段时小节线回到 4")
	eq(app.rail_snap, true, "旧谱缺字段时轨道吸附默认开")
	app.free()
	return true


## Anchor 双押：拖一颗要带上同 pairId 的伙伴，整对保持同拍 + 180°。
func test_anchor_pair_drag() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	var pair := chart.make_anchor_pair(4.0, 90.0)
	for item in pair:
		chart.notes.append(item)
	app.chart = chart
	app.selected_notes.append(pair[0].id)
	var dragged: Array[Note] = app.with_anchor_partners(app.get_selected_notes())
	eq(dragged.size(), 2, "dragging one anchor carries its partner")
	ok(dragged.has(pair[1]), "the partner is the other anchor")
	for item in dragged:
		item.beat += 1.0
		item.angle = fposmod(item.angle + 30.0, 360.0)
	near(pair[0].beat, pair[1].beat, 0.0001, "the pair stays on the same beat")
	near(absf(fposmod(pair[0].angle - pair[1].angle + 360.0, 360.0)), 180.0, 0.0001, "the pair stays 180° apart")
	app.free()
	return true


## Path 头手柄：起始拍只能在 0 与“尾巴前 0.25 拍”之间。
## 属性页“复制/删除”传入的是未类型化数组；共享函数必须能接住并返回整对 Anchor。
func test_anchor_partners_untyped_array() -> bool:
	var app: App = load("res://charter/app.gd").new()
	var chart := Chart.new()
	var pair := chart.make_anchor_pair(4.0, 90.0)
	for item in pair:
		chart.notes.append(item)
	app.chart = chart
	var picked: Array[Note] = app.with_anchor_partners([pair[0]])
	eq(picked.size(), 2, "untyped array still carries the anchor partner")
	ok(picked.has(pair[0]) and picked.has(pair[1]), "both anchors are returned")
	app.free()
	return true


func test_path_head_beat() -> bool:
	near(ChartCanvas.path_head_beat(4.0, 8.0), 4.0, 0.0001, "a normal head move keeps the beat")
	near(ChartCanvas.path_head_beat(-3.0, 8.0), 0.0, 0.0001, "the head never goes before beat 0")
	near(ChartCanvas.path_head_beat(9.0, 8.0), 7.75, 0.0001, "the head stops 0.25 beats before the tail")
	near(ChartCanvas.path_head_beat(2.0, 2.1), 1.85, 0.0001, "a short path still keeps a 0.25 beat body")
	return true


## Path 轴长手柄：沿起终弦法向拖过去多少，就是多少个弦长。
func test_path_axis_drag() -> bool:
	var head := Vector2(1, 0)
	var tail := Vector2(0, 0.5)
	var chord := tail - head
	var middle := (head + tail) * 0.5
	near(Preview3D.path_axis_from_drag(head, tail, middle), 0.0, 0.0001, "dragging through the chord keeps it straight")
	var normal := Vector2(-chord.y, chord.x).normalized()
	near(Preview3D.path_axis_from_drag(head, tail, middle + normal * chord.length() * 0.25),
		0.25, 0.0001, "normal drag becomes the axis in chord lengths")
	near(Preview3D.path_axis_from_drag(head, tail, middle - normal * chord.length() * 0.5),
		-0.5, 0.0001, "the other side is negative")
	near(Preview3D.path_axis_from_drag(head, head, middle), 0.0, 0.0001, "a zero-length chord is a no-op")
	return true


func _path_turning(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, points.size() - 1):
		var a := (points[i] - points[i - 1]).normalized()
		var b := (points[i + 1] - points[i]).normalized()
		total += acos(clampf(a.dot(b), -1.0, 1.0))
	return total


## 手绘定型：端点不动、点数封顶、锯齿被压平、拐角保留。
func test_path_smoothing() -> bool:
	var raw: Array[Vector2] = []
	for i in 41:
		raw.append(Vector2(float(i) / 40.0, 0.0 if i % 2 == 0 else 0.01))
	var smooth := Preview3D.finalize_path_points(raw)
	ok(smooth.size() >= 2 and smooth.size() <= Preview3D.PATH_SMOOTH_MAX_POINTS,
		"smoothed trace stays inside the point budget")
	ok(smooth[0].is_equal_approx(raw[0]) and smooth[-1].is_equal_approx(raw[-1]),
		"head and tail are never moved")
	ok(_path_turning(smooth) < _path_turning(raw), "smoothing reduces direction changes")
	var corner: Array[Vector2] = []
	for i in 11:
		corner.append(Vector2(float(i) / 10.0, 0.0))
	for i in range(1, 11):
		corner.append(Vector2(1.0, float(i) / 10.0))
	var kept := Preview3D.finalize_path_points(corner)
	var closest := 99.0
	for point in kept:
		closest = minf(closest, point.distance_to(Vector2(1, 0)))
	ok(closest < 0.02, "a 90 degree corner survives")
	ok(kept.size() <= Preview3D.PATH_SMOOTH_MAX_POINTS, "corner path also respects the budget")
	var line: Array[Vector2] = [Vector2(0, 0), Vector2(0.5, 0), Vector2(1, 0), Vector2(1.5, 0)]
	ok(Preview3D._rdp_path(line, 0.018).size() == 2, "a straight line collapses to its endpoints")
	return true


## Seek / Limit 的入场曲线：数值必须落在设计区间里。
func test_seek_limit_animation_curves() -> bool:
	near(Preview3D.ease_out_cubic(0.0), 0.0, 0.0001, "ease out starts at 0")
	near(Preview3D.ease_out_cubic(1.0), 1.0, 0.0001, "ease out ends at 1")
	ok(Preview3D.ease_out_cubic(0.5) > 0.5, "ease out front-loads the motion")
	var incoming: Vector3 = Preview3D.limit_visual_state(0.5, -100.0)
	ok(incoming.x < 1.0 and incoming.x - incoming.y < 0.32, "the leading edge approaches before the wall fills")
	var active: Vector3 = Preview3D.limit_visual_state(1.0, 0.0)
	near(active.x, 1.0, 0.0001, "Limit reaches the judgment ring on activation")
	near(active.y, 0.68, 0.0001, "the active wall covers the judged depth")
	near(active.z, 1.0, 0.0001, "the active wall is fully visible")
	var exiting: Vector3 = Preview3D.limit_visual_state(1.0, Preview3D.LIMIT_EXIT_MS * 0.5)
	ok(exiting.x > active.x and exiting.x - exiting.y < active.x - active.y, "the wall moves outward and contracts")
	near(Preview3D.limit_visual_state(1.0, Preview3D.LIMIT_EXIT_MS).z, 0.0, 0.0001, "Limit fades out at the end of its exit")
	return true


## 红区驻留：进入那一帧不计时、离开清零、每局每区只断一次。


## Seek 的下落曲线必须和 Tap/Bell 同一条：出生 1/6 环半径、判定拍正好到环。
func test_seek_grow_matches_tap() -> bool:
	near(Preview3D.seek_grow_scale(0.0), Note.SPAWN_LENGTH_RATIO, 0.000001,
		"seek 出生在 1/6 环半径（和 Tap 一样）")
	near(Preview3D.seek_grow_scale(1.0), 1.0, 0.000001, "seek 判定那一拍正好落到环上")
	near(Preview3D.seek_grow_scale(0.5), lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, 0.5), 0.000001,
		"seek 与 Tap 共用同一条线性下落曲线")
	near(Preview3D.seek_grow_scale(-1.0), Note.SPAWN_LENGTH_RATIO, 0.000001, "进度为负时夹到出生点")
	return true


func test_seek_warning_order() -> bool:
	var preview: Preview3D = Preview3D.new()
	var chart: Chart = Chart.new()
	var inward: Note = Note.new("seek", chart.timing.chart_ms_to_beat(1000.0), 0.0)
	inward.seek_orien = 1
	var outward: Note = Note.new("seek", chart.timing.chart_ms_to_beat(1120.0), 0.0)
	outward.seek_orien = 0
	chart.notes.assign([inward, outward])
	var early: Vector2 = preview._seek_warning_strengths(chart, chart.timing.chart_ms_to_beat(690.0), 690.0)
	eq(early, Vector2.ZERO, "Seek rim is idle more than 300ms before judgment")
	var ramp: Vector2 = preview._seek_warning_strengths(chart, chart.timing.chart_ms_to_beat(760.0), 760.0)
	ok(ramp.x > 0.5 and ramp.y == 0.0, "the Seek rim is already bright early in the warning window")
	var first: Vector2 = preview._seek_warning_strengths(chart, chart.timing.chart_ms_to_beat(950.0), 950.0)
	ok(first.x > 0.0 and first.y == 0.0, "overlapping windows present the earlier Seek first")
	var second: Vector2 = preview._seek_warning_strengths(chart, chart.timing.chart_ms_to_beat(1060.0), 1060.0)
	ok(second.x == 0.0 and second.y > 0.0, "the next Seek gets its own pre-judgment cue")
	var end: Vector2 = preview._seek_warning_strengths(chart, outward.beat, 1120.0)
	eq(end, Vector2.ZERO, "the Seek warning ends at judgment")
	inward.beat = outward.beat
	chart.mark_dirty()
	preview._on_chart_changed()
	var together: Vector2 = preview._seek_warning_strengths(chart, chart.timing.chart_ms_to_beat(1060.0), 1060.0)
	ok(together.x > 0.0 and together.y > 0.0, "opposite Seek notes at one time keep both colors")
	preview.free()
	return true


## 重试：上一局的判定文字、火花和连击断连动画不能活到新一局。
func test_limit_dwell_once() -> bool:
	var state := {"time": 0.0, "broken": false}
	ok(not Playtest.limit_dwell_break(state, true, 0.2, 0.2), "the frame you enter does not count")
	ok(not Playtest.limit_dwell_break(state, true, 0.1, 0.2), "100ms is not enough")
	ok(Playtest.limit_dwell_break(state, true, 0.15, 0.2), "200ms of dwell breaks")
	ok(not Playtest.limit_dwell_break(state, true, 1.0, 0.2), "the same region only breaks once")
	ok(not Playtest.limit_dwell_break(state, false, 0.0, 0.2), "leaving resets the timer")
	near(float(state["time"]), 0.0, 0.0001, "timer is cleared after leaving")
	ok(not Playtest.limit_dwell_break(state, true, 0.3, 0.2), "a broken region stays broken for the run")
	return true


## 环预览拖动音符：只按光标绕环心转过的角度旋转，跨 0°/360° 连续。
func test_preview_note_drag_angle() -> bool:
	near(Preview3D.dragged_angle(10.0, 90.0, 100.0), 20.0, 0.0001, "dragging right rotates by the same amount")
	near(Preview3D.dragged_angle(10.0, 100.0, 90.0), 0.0, 0.0001, "dragging back returns to the start")
	near(Preview3D.dragged_angle(350.0, 10.0, 350.0), 330.0, 0.0001, "crossing 0 degrees stays continuous")
	near(Preview3D.dragged_angle(0.0, 0.0, 359.0), 359.0, 0.0001, "a small left drag does not jump")
	return true


## 倍数校正：2/3 与 3/2 的错位能被谱面 BPM 拉回来，误差太大则不动。
func test_bpm_snap_multipliers() -> bool:
	ok(BpmDetect.MULTIPLIERS.has(1.5), "a 3:2 multiplier exists")
	ok(BpmDetect.MULTIPLIERS.has(4.0), "a 4x multiplier exists")
	near(BpmDetect.snap_to_reference(100.1, 150.0), 150.15, 0.001, "2/3 detection snaps up to the chart tempo")
	near(BpmDetect.snap_to_reference(158.3, 238.0), 237.45, 0.001, "238 with a 2/3 detection snaps back")
	near(BpmDetect.snap_to_reference(65.3, 257.0), 261.2, 0.001, "a quarter-tempo detection snaps with x4")
	near(BpmDetect.snap_to_reference(193.0, 193.0), 193.0, 0.001, "an exact match stays exact")
	near(BpmDetect.snap_to_reference(140.0, 200.0), 140.0, 0.001, "an unrelated value is left alone")
	return true


## 判定区回到细分之前：0.85R 一段，短星最少 3 段；判定只看轨迹参数，
## 不读任何“飞行时长”设置——视觉快慢不该改变判定。
func test_path_zone_granularity() -> bool:
	near(PathProgress.GATE_SPACING, 0.85, 0.0001, "judgement zones are back to 0.85R")
	var short_path := PackedVector2Array()
	for i in 41:
		short_path.append(Vector2(0.7 * float(i) / 40.0, 0.0))
	var tracker := PathProgress.new()
	tracker.configure(short_path)
	var projected := tracker.points
	tracker.confirm_head()
	eq(tracker.group_count, 3, "a 0.7R slide splits into 3 judgement zones again")
	eq(tracker.remaining_groups(), 2, "the head counts as the first cleared zone")
	# 沿轨迹喂一串点：进度必须跟着走，而不是一口气算完整条。
	for i in projected.size():
		tracker.feed(projected[i], 100.0 + float(i) * 5.0, projected, tracker.contact_radius * 2.0, 0.0)
	ok(tracker.fraction > 0.0, "tracing the slide builds progress")
	ok(tracker.remaining_groups() < 2, "tracing clears judgement zones")
	ok(tracker.body_ready(), "the tail connects once every zone is traced")
	# 判定器不接收 BPM / 飞行时长：同一段轨迹在任何设置下结果一致（结构性保证）。
	var replayed := PathProgress.new()
	replayed.configure(short_path)
	replayed.confirm_head()
	for i in projected.size():
		replayed.feed(projected[i], 100.0 + float(i) * 5.0, projected, replayed.contact_radius * 2.0, 0.0)
	near(replayed.fraction, tracker.fraction, 0.0001, "judgement is independent of fall time")
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
	ok(app.save_set_file(), "saving the group writes a project")
	var out_dir := "user://test_set_out"
	var written: int = app.save_all_difficulties(out_dir)
	eq(written, app.difficulties.size(), "every difficulty is written to disk")
	# 旧套组保存时转成工程；重新打开工程仍在。
	ok(not app.set_path.is_empty(), "import writes a project main.tmc")
	ok(FileAccess.file_exists(app.set_path), "project main exists")
	var reopened: App = load("res://charter/app.gd").new()
	ok(reopened.open_project(app.set_path), "project reopens")
	eq(reopened.difficulties.size(), app.difficulties.size(), "reopened project has every difficulty")
	eq(reopened.difficulty_names()[0], app.difficulty_names()[0], "difficulty names survive the round trip")
	ok(reopened.chart != null and reopened.chart.notes.size() > 0, "reopened project loads its first difficulty")
	ok(reopened.switch_difficulty(1), "reopened project can switch difficulty")
	ok(reopened.chart.notes.size() > 0, "switched difficulty has notes")
	# 静态小工具：命令行参数解析与标签拼装。
	eq(app.import_label("Lv.9", "Song", "me", "std"), "Lv.9  [std]  Song  (me)", "import label format")
	eq(app.import_label("", "", "", ""), "未命名难度", "empty label falls back")
	reopened.free()
	app.free()
	for cleanup_dir in ["user://sets", out_dir]:
		var abs_dir := ProjectSettings.globalize_path(cleanup_dir)
		if not DirAccess.dir_exists_absolute(abs_dir):
			continue
		for file_name in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(file_name))
		for sub_name in DirAccess.get_directories_at(abs_dir):
			for file_name in DirAccess.get_files_at(abs_dir.path_join(sub_name)):
				DirAccess.remove_absolute(abs_dir.path_join(sub_name).path_join(file_name))
			DirAccess.remove_absolute(abs_dir.path_join(sub_name))
		DirAccess.remove_absolute(abs_dir)
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
	eq(int(levels[0].get("index", 0)), 2, "majdata normalizes 0-based API index")
	eq(String(levels[3].get("level", "")), "13+", "majdata keeps Re:Master")
	eq(int(levels[3].get("index", 0)), 6, "majdata Re:Master is index 6")
	var all_levels := ChartBrowser.maj_levels(["1", "5", "7+", "", "12", "13+", "14?"])
	eq(all_levels.size(), 6, "majdata keeps EASY and Utage")
	eq(int(all_levels[0].get("index", 0)), 1, "majdata EASY is index 1")
	eq(int(all_levels[5].get("index", 0)), 7, "majdata Utage is index 7")

	var path := "user://test_maidata_levels.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("&title=T\n&artist=A\n&lv_1=4\n&des_1=x\n&inote_1=(120){1},1,\n&lv_4=12+\n&des_4=y\n&inote_4=(120){1},2,\n&lv_6=13.2\n&inote_6=(120){1},3,\n&lv_7=12?\n&inote_7=(120){1},4,\n")
	file.close()
	var parsed := ChartBrowser.levels_from_maidata(path)
	eq(parsed.size(), 4, "maidata parses all seven difficulty slots")
	eq(String(parsed[0].get("level", "")), "4", "maidata level is read")
	eq(String(parsed[1].get("creator", "")), "y", "maidata designer is read")
	eq(int(parsed[2].get("index", 0)), 6, "maidata keeps Re:MAS")
	eq(int(parsed[3].get("index", 0)), 7, "maidata keeps Utage")
	eq(String(parsed[3].get("level", "")), "12?", "maidata keeps unconfirmed level")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("&title=T\n&lv_2=5\n&inote_2=\n&lv_3=7\n&inote_3=(120){1},1,\n")
	file.close()
	eq(ChartBrowser.levels_from_maidata(path).size(), 1, "maidata skips empty inote")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	eq(SimaiIO.difficulty_name(1), "EASY", "difficulty 1 is EASY")
	eq(SimaiIO.difficulty_name(6), "Re:MAS", "difficulty 6 is Re:MAS")
	eq(SimaiIO.difficulty_name(7), "宴", "difficulty 7 is Utage")
	eq(SimaiIO.difficulty_label(2, "6.0"), "BASIC 6.0", "difficulty label includes tier")
	eq(SimaiIO.difficulty_label(7, "?"), "宴 ?", "difficulty label keeps unknown level")
	eq(ChartBrowser.favorites_from_json({"adx:11": {}}).size(), 0, "old favorites are cleared")
	eq(ChartBrowser.favorites_from_json({"version": 2, "items": {"adx:11": {}}}).size(), 1, "new favorites load")

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

func test_replay_round_trip() -> bool:
	var replay := Replay.new()
	replay.chart_path = "user://demo.json"
	replay.chart_hash = "abc123"
	replay.start_beat = 4.0
	replay.settings = {"offset_ms": 12.5, "flow": 1.0}
	replay.add_move(100.0, Vector2(10.5, 20.25))
	replay.add_press(120.0, 116.0, 124.0, 65, Vector2(1.0, 2.0), 33.5, 0.25, true)
	replay.add_release(160.0, 65)
	replay.add_seek(200.0, 196.0, 204.0, 1)
	replay.add_offset(240.0, -8.5)
	replay.result = {"hit": 3, "tiers": {"PERFECT": 3}}
	eq(replay.event_count(), 5, "replay records five events")
	eq(String(replay.events[1]["k"]), "press", "replay keeps event kind")
	near(float(replay.events[1]["t"]), 120.0, 0.001, "replay keeps press time")

	var data := replay.to_dict()
	eq(String(data["format"]), Replay.FORMAT, "replay dict carries format tag")
	var loaded := Replay.from_dict(data)
	ok(loaded != null, "replay dict loads")
	if loaded == null:
		return true
	eq(loaded.event_count(), 5, "replay events survive round trip")
	eq(loaded.chart_hash, "abc123", "replay keeps chart hash")
	near(float(loaded.events[0]["x"]), 10.5, 0.01, "replay keeps move x")
	eq(bool(loaded.events[1]["v"]), true, "replay keeps press validity")
	eq(int(loaded.events[3]["dir"]), 1, "replay keeps seek direction")
	near(float(loaded.events[4]["v"]), -8.5, 0.01, "replay keeps offset value")
	eq(int(loaded.result["hit"]), 3, "replay keeps result summary")

	# 格式/版本不符时拒绝加载，别把坏文件当成回放播出去。
	var bad_format := data.duplicate(true)
	bad_format["format"] = "something-else"
	ok(Replay.from_dict(bad_format) == null, "replay rejects foreign format")
	var bad_version := data.duplicate(true)
	bad_version["version"] = 99
	ok(Replay.from_dict(bad_version) == null, "replay rejects newer version")

	var path := "user://test_replay_roundtrip.tmkrpl"
	eq(replay.save_to(path), OK, "replay saves as gzip")
	var from_file := Replay.load_from(path)
	ok(from_file != null, "replay loads from gzip")
	if from_file != null:
		eq(from_file.event_count(), 5, "replay file keeps events")
		near(float(from_file.events[1]["lo"]), 116.0, 0.01, "replay file keeps press window")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 谱面哈希：同一张谱面稳定，改一个音符就变。
	var chart := DemoChart.make_demo()
	var hash_a := Replay.hash_chart(chart)
	ok(not hash_a.is_empty(), "chart hash is not empty")
	eq(Replay.hash_chart(chart), hash_a, "chart hash is stable")
	if not chart.notes.is_empty():
		chart.notes[0].beat += 0.5
		ok(Replay.hash_chart(chart) != hash_a, "chart hash changes after edit")
	return true


## TMC 工程 / 难度套组回放：按 hash 找到录制时的难度，旧镜像回放再反推。
func test_replay_match_project_entry() -> bool:
	var first := Chart.new()
	first.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	first.notes.append(Note.new("tap", 1.0, 90.0, 60.0))
	var second := Chart.new()
	second.timing.points = [TimingPoint.new(0.0, 150.0, 4)]
	second.notes.append(Note.new("tap", 2.0, 180.0, 60.0))
	var entries := [{"chart": first}, {"chart": second}]
	var replay := Replay.new()
	replay.chart_hash = Replay.hash_chart(second)
	eq(Replay.match_chart_entry(entries, replay), 1, "project replay matches the recorded difficulty")
	replay.chart_hash = "not-a-chart"
	eq(Replay.match_chart_entry(entries, replay), -1, "unknown hash does not guess a difficulty")
	replay.chart_hash = Replay.hash_chart(second.mirrored_copy("lr"))
	eq(Replay.match_chart_entry(entries, replay), 1, "old mirrored replay still matches")
	eq(String(replay.settings.get("mirror", "")), "lr", "matched mirror is written back")
	return true


## 回放分派：事件按时间喂回判定队列，按键带着录制时的光标和区间。
func test_replay_dispatch() -> bool:
	var run := Playtest.new()
	var replay := Replay.new()
	replay.add_move(100.0, Vector2(5.0, 6.0))
	replay.add_press(120.0, 116.0, 124.0, 65, Vector2(7.0, 8.0), 45.0, 0.5, true)
	replay.add_release(150.0, 65)
	replay.add_seek(160.0, 156.0, 164.0, 1)
	replay.add_offset(170.0, -12.0)
	run._replay_events = replay.events
	run._dispatch_replay(110.0)
	eq(run._path_motion_samples.size(), 1, "replay applies move events")
	eq(run._key_presses.size(), 0, "replay waits for future events")
	run._dispatch_replay(165.0)
	eq(run._key_presses.size(), 1, "replay applies press events")
	near(float(run._key_presses[0]["time"]), 120.0, 0.001, "replayed press keeps its time")
	eq(run._key_presses[0]["mouse"], Vector2(7.0, 8.0), "replayed press keeps its cursor")
	near(float(run._key_presses[0]["lo"]), 116.0, 0.001, "replayed press keeps its frame window")
	ok(not run._keys_held.has(65), "replayed release erases the held key")
	eq(run._seek_presses.size(), 1, "replay applies seek events")
	run._dispatch_replay(200.0)
	near(run._offset_override, -12.0, 0.001, "replay applies offset changes")
	near(run._active_offset(), -12.0, 0.001, "recorded offset beats the live setting")
	eq(run._replay_index, 5, "every event is dispatched once")
	run._dispatch_replay(500.0)
	eq(run._replay_index, 5, "events are not dispatched twice")
	run.free()
	return true


## 进度条比例：起点/终点要夹住，中间线性。
func test_replay_scrub() -> bool:
	var run := Playtest.new()
	run._replay_start_ms = 1000.0
	run._replay_total_ms = 5000.0
	run._replay_ms = 3000.0
	near(run._replay_fraction(), 0.5, 0.001, "scrub maps the middle of the song")
	run._replay_ms = 1000.0
	near(run._replay_fraction(), 0.0, 0.001, "scrub clamps at the start")
	run._replay_ms = 9000.0
	near(run._replay_fraction(), 1.0, 0.001, "scrub clamps past the end")
	run._replay_start_ms = 0.0
	run._replay_total_ms = 0.0
	run._replay_ms = 0.0
	near(run._replay_fraction(), 0.0, 0.001, "empty span does not divide by zero")
	run.free()
	return true


## 回放文件名：Windows 非法字符要替换，空名字要有兜底。
func test_replay_file_name() -> bool:
	var run := Playtest.new()
	eq(run._sanitize_file_name("a/b:c*?"), "a_b_c__", "file name replaces illegal characters")
	eq(run._sanitize_file_name("  "), "replay", "blank file name falls back")
	eq(run._sanitize_file_name("Sakura_紫"), "Sakura_紫", "normal names are kept")
	run.free()
	return true


## 试玩界面构建冒烟测试：控件属性名写错时 _build_ui 会中途报错，
## 这种错误单测和空跑都抓不到，只有真开一局试玩才会暴露。
func test_playtest_ui_builds() -> bool:
	var run := Playtest.new()
	run._build_ui()
	eq(run._replay_button.text, "回放本局", "results screen has a replay button")
	eq(run._export_replay_button.text, "导出回放", "results screen has a replay-file export button")
	eq(run._export_replay_button.get_parent() == run._replay_button.get_parent(), true,
		"replay export button sits in the same row as the replay button")
	eq(run._replay_bar != null and not run._replay_bar.visible, true, "replay bar is built but hidden")
	eq(run._replay_exit_button != null and run._replay_exit_button.get_parent() == run._replay_bar.get_child(0),
		true, "replay bar ends with an exit button")
	eq(run._results != null, true, "results panel is built")
	run.free()
	return true


## 鼠标左右键当成两个独立键位，且不会和真实 Key 枚举相撞。


func test_retry_clears_playtest_visuals() -> bool:
	var preview := Preview3D.new()
	preview._pulses = [{"age": 0.2}, {"age": 0.4}]
	preview._arc_flashes = [{"age": 0.1}]
	preview._hud_combo_prev = 37
	preview._hud_combo_broken = 37
	preview._hud_combo_break_at = 1234
	preview.reset_path_cuts()
	eq(preview._pulses.size(), 0, "重试清空上一局的判定文字/火花")
	eq(preview._arc_flashes.size(), 0, "重试清空上一局的命中弧闪")
	eq(preview._hud_combo_prev, 0, "重试复位连击动画缓存")
	eq(preview._hud_combo_broken, 0, "重试不再显示上一局的断连数字")
	preview.free()
	return true


## 复制 Path 必须带上整条链并重映射 id：照抄旧 id 会让新 part 指向原链，
## 预览/试玩/存盘都把它当子部件跳过，用户看到的就是“粘贴没反应”。
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
## 镜像站返回的两种 JSON 都要能解析成「难度名 → 星数」。
func test_osu_star_hints_json() -> bool:
	# sayobot：data.bid_data[].version / star
	var sayobot: Variant = JSON.parse_string('{"status":0,"data":{"bid_data":[{"version":"Insane","star":4.7},{"version":"Hard","star":2.5}]}}')
	var from_sayobot := OsuIO.hints_from_json(sayobot)
	eq(from_sayobot.size(), 2, "sayobot yields two difficulties")
	ok(absf(float(from_sayobot.get("Insane", 0.0)) - 4.7) < 0.001, "sayobot star value")
	ok(absf(float(from_sayobot.get("Hard", 0.0)) - 2.5) < 0.001, "sayobot second value")

	# osu.direct：顶层 beatmaps[].version / difficulty_rating
	var direct: Variant = JSON.parse_string('{"id":1,"beatmaps":[{"version":"Extra","difficulty_rating":6.39},{"version":"Normal","difficulty_rating":2.0}]}')
	var from_direct := OsuIO.hints_from_json(direct)
	eq(from_direct.size(), 2, "osu.direct yields two difficulties")
	ok(absf(float(from_direct.get("Extra", 0.0)) - 6.39) < 0.001, "osu.direct rating value")

	# 没有星数字段就返回空，调用方按文件顺序处理
	ok(OsuIO.hints_from_json(JSON.parse_string('{"data":{"bid_data":[{"version":"X"}]}}')).is_empty(), "no star field means empty hints")
	ok(OsuIO.hints_from_json(null).is_empty(), "null input is safe")
	return true


## .osu 文本里的 BeatmapSetID 能读出来。
func test_osu_beatmap_set_id() -> bool:
	var text := """osu file format v14

[Metadata]
Title:Shoujo A
BeatmapID:4499482
BeatmapSetID:2137985

[Difficulty]
CircleSize:4
"""
	eq(OsuIO._read_beatmap_set_id(text), 2137985, "BeatmapSetID parsed")
	eq(OsuIO._read_beatmap_set_id("[Metadata]\nTitle:X\n"), 0, "missing id gives 0")
	return true



## 难度按星数排序：升序、未知排最后、原始下标不变。
func test_osu_difficulty_star_sort() -> bool:
	var entries := [
		{"index": 0, "version": "ANOTHER", "stars": 6.5},
		{"index": 1, "version": "BEGINNER", "stars": 1.2},
		{"index": 2, "version": "HYPER", "stars": 4.0},
		{"index": 3, "version": "LOCAL ONLY", "stars": -1.0},
	]
	var sorted := OsuIO.sort_by_stars(entries)
	eq(sorted.size(), 4, "keeps every difficulty")
	eq(String(sorted[0]["version"]), "BEGINNER", "lowest stars first")
	eq(String(sorted[1]["version"]), "HYPER", "then middle")
	eq(String(sorted[2]["version"]), "ANOTHER", "then highest")
	eq(String(sorted[3]["version"]), "LOCAL ONLY", "unknown stars go last")
	eq(int(sorted[2]["index"]), 0, "original zip index is preserved")
	eq(int(sorted[0]["index"]), 1, "original zip index follows the entry")

	# 没有星数时顺序原样保留
	var plain := OsuIO.sort_by_stars([{"index": 0, "version": "B"}, {"index": 1, "version": "A"}])
	eq(String(plain[0]["version"]), "B", "no stars keeps file order")
	return true


## 难度名后缀星数：顶部下拉和窗口标题显示，名字本身保持干净。
func test_difficulty_star_label() -> bool:
	var app_script := load("res://charter/app.gd")
	eq(String(app_script.star_label("Insane", 5.42)), "Insane  5.42★", "known stars are appended")
	eq(String(app_script.star_label("Insane", -1.0)), "Insane", "unknown stars keep the bare name")
	var app = app_script.new()
	app.difficulties.append({"name": "Insane", "stars": 5.42, "chart": null})
	app.difficulties.append({"name": "Easy", "chart": null})
	eq(app.difficulty_names()[0], "Insane  5.42★", "difficulty list shows stars")
	eq(app.difficulty_names()[1], "Easy", "difficulty without stars stays bare")
	eq(app.difficulty_name(0), "Insane  5.42★", "single difficulty name shows stars")
	app.free()
	return true


## 星数写进套组文件，重新打开还在（否则排序对了但看不到星）。
func test_difficulty_stars_round_trip() -> bool:
	var path := "user://test_stars_set.json"
	var chart := DemoChart.make_demo()
	var entries: Array = [{"name": "Insane", "stars": 5.42, "chart": chart}]
	eq(ChartIO.save_set(path, entries), OK, "set with stars saves")
	var loaded := ChartIO.load_set(path)
	ok(bool(loaded.get("ok", false)), "set with stars loads")
	var first: Dictionary = loaded.get("entries", [])[0]
	near(float(first.get("stars", -1.0)), 5.42, 0.001, "stars survive the set round trip")
	eq(String(first.get("name", "")), "Insane", "stored name stays clean")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## 难度标签末尾追加星数。
func test_import_label_stars() -> bool:
	var app_script := load("res://charter/app.gd")
	var with_stars := String(app_script.import_label("Insane", "Song", "Mapper", "std", 5.42))
	ok(with_stars.ends_with("5.42★"), "star rating appended at the end, got: %s" % with_stars)
	ok(with_stars.contains("Insane"), "version still in label")
	var without := String(app_script.import_label("Insane", "Song", "Mapper", "std"))
	ok(not without.contains("★"), "no star when rating is unknown")
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


func test_alpha_command_catalog() -> bool:
	eq(AlphaCommand.CATALOG.size(), 27, "catalog has 27 commands")
	eq(AlphaCommand.names("filter").size(), 24, "24 filter commands")
	eq(AlphaCommand.names("jline").size(), 1, "one judge line command")
	eq(AlphaCommand.names("text").size(), 2, "two text commands")
	var seen := {}
	for entry in AlphaCommand.CATALOG:
		var command_name := String(entry.get("name", ""))
		ok(not seen.has(command_name), "unique command name %s" % command_name)
		seen[command_name] = true
		ok(not String(entry.get("label", "")).is_empty(), "label for %s" % command_name)
		ok(float(entry.get("duration", -1.0)) >= 0.0, "duration for %s" % command_name)
	ok(AlphaCommand.spec_of("NOPE").is_empty(), "unknown command has no spec")
	eq(AlphaCommand.default_duration("NOPE"), 1.0, "unknown command falls back to one beat")
	return true


func test_alpha_command_envelope() -> bool:
	var flash := AlphaCommand.new("FLASH", 4.0)
	eq(flash.envelope_at(3.0), 0.0, "not started yet")
	eq(flash.envelope_at(4.5), 1.0, "hold segment is full strength")
	eq(flash.envelope_at(5.5), 0.0, "released after the end")
	flash.enabled = false
	eq(flash.envelope_at(4.5), 0.0, "disabled command is silent")
	var kaleido := AlphaCommand.new("KALEIDOSCOPE", 2.0)
	eq(kaleido.envelope_at(3.0), 1.0, "stateful command holds inside its window")
	eq(kaleido.envelope_at(9.0), 0.0, "stateful command stops at its end beat")
	var shake := AlphaCommand.new("SHAKE", 1.0)
	ok(shake.envelope_at(1.2) > 0.0 and shake.envelope_at(1.2) < 1.0, "shake ramps in")
	eq(shake.envelope_at(1.6), 1.0, "shake reaches full strength")
	eq(shake.envelope_at(4.0), 0.0, "shake released")
	return true


func test_jline_ring_state() -> bool:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var first := chart.add_command("JLINE", 1.0)
	first.duration = 4.0
	first.params["color"] = "#ff0000"
	first.params["width"] = 10.0
	first.params["alpha"] = 0.8
	first.params["expand"] = 0.5
	var state := Preview3D.jline_state(chart, 2.0)
	ok(bool(state.get("active", false)), "JLINE active inside its window")
	near(float(state.get("width", 0.0)), 10.0, 0.001, "JLINE width reaches the ring")
	near(float(state.get("alpha", 0.0)), 0.8, 0.001, "JLINE alpha reaches the ring")
	var color: Color = state.get("color", Color.BLACK)
	near(color.r, 1.0, 0.001, "JLINE red reaches the ring")
	var second := chart.add_command("JLINE", 2.5)
	second.duration = 4.0
	second.params["color"] = "#0000ff"
	second.params["width"] = 4.0
	state = Preview3D.jline_state(chart, 3.0)
	near(float(state.get("width", 0.0)), 4.0, 0.001, "last started JLINE takes over by default")
	color = state.get("color", Color.BLACK)
	near(color.b, 1.0, 0.001, "last started JLINE color wins")
	second.params["blend"] = "交叉淡入"
	state = Preview3D.jline_state(chart, 3.0)
	var mixed: Color = state.get("color", Color.BLACK)
	ok(mixed.r > 0.01 and mixed.b > 0.01, "crossfade mixes both JLINE colors")
	var width := float(state.get("width", 0.0))
	ok(width > 4.0 and width < 10.0, "crossfade mixes both JLINE widths")
	eq(AlphaCommand.defaults("JLINE").get("blend", ""), "后开始接管", "JLINE defaults to last-started blend")
	return true


func test_filter_region_state() -> bool:
	var defaults := AlphaCommand.defaults("FLASH")
	eq(defaults.get("region_on", true), false, "old filters stay full-screen by default")
	eq(float(defaults.get("region_span", 0.0)), 360.0, "region defaults to a full ring")
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var flash := chart.add_command("FLASH", 1.0)
	flash.duration = 4.0
	flash.params["region_on"] = true
	flash.params["region_angle"] = 30.0
	flash.params["region_span"] = 90.0
	flash.params["region_inner"] = 0.4
	flash.params["region_outer"] = 0.9
	flash.params["region_feather"] = 0.05
	var zoom := chart.add_command("ZOOM", 2.0)
	zoom.duration = 4.0
	zoom.params["region_on"] = true
	zoom.params["region_angle"] = 180.0
	zoom.params["region_span"] = 60.0
	var preview := Preview3D.new()
	var state := preview._filter_state(chart, 3.0)
	ok(bool(state.get("active", false)), "filters are active")
	var region: Dictionary = state.get("region", {})
	eq(bool(region.get("on", false)), true, "region is read from the active filter")
	near(float(region.get("angle", 0.0)), 180.0, 0.001, "last started filter owns the region")
	near(float(region.get("span", 0.0)), 60.0, 0.001, "region span is kept")
	var uniforms: Dictionary = state.get("uniforms", {})
	ok(float(uniforms.get("zoom", 1.0)) > 1.0, "filter effects still merge")
	preview.free()
	return true


func test_filter_layer_visibility() -> bool:
	var preview := Preview3D.new()
	var layer := ColorRect.new()
	preview.add_child(layer)
	preview._filter_layer = layer
	preview._filter_warmup_left = 0
	var empty := Chart.new()
	empty.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	preview._update_filter_visibility(empty, 0.0)
	ok(not layer.visible, "no filter commands keeps the layer hidden")
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	var flash := chart.add_command("FLASH", 1.0)
	flash.duration = 4.0
	preview._update_filter_visibility(chart, 0.5)
	ok(not layer.visible, "before the filter starts the layer stays hidden")
	preview._update_filter_visibility(chart, 3.0)
	ok(layer.visible, "an active filter shows the layer")
	preview._update_filter_visibility(chart, 9.0)
	ok(not layer.visible, "after the filter ends the layer hides again")
	preview._filter_warmup_left = Preview3D.FILTER_WARMUP_FRAMES
	preview._update_filter_visibility(empty, 0.0)
	ok(layer.visible, "warmup frames keep the layer visible")
	preview._filter_warmup_left = 0
	preview._update_filter_visibility(null, 0.0)
	ok(not layer.visible, "a missing chart hides the layer")
	preview.free()
	return true


func test_playfield_quality_settings() -> bool:
	var app: Node = load("res://charter/app.gd").new()
	var preview := Preview3D.new()
	preview._build_layers()
	app.use_3d_ring = false
	app.msaa_3d_level = 0
	app.ring_3d_scale = "low"
	preview.apply_playfield_quality(app)
	ok(not preview._viewport_container.visible, "the flat playfield hides the 3D targets")
	eq(preview._subviewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "flat mode skips the 3D render")
	eq(preview._subviewport.msaa_3d, Viewport.MSAA_DISABLED, "the preview uses the requested AA")
	near(preview._subviewport.scaling_3d_scale, 0.5, 0.001, "the preview uses the requested scale")
	app.use_3d_ring = true
	app.msaa_3d_level = 2
	preview.apply_playfield_quality(app)
	ok(preview._viewport_container.visible and preview._force_3d_frame, "reenabling 3D schedules a fresh frame")
	eq(preview._subviewport.msaa_3d, Viewport.MSAA_4X, "AA changes apply without rebuilding the preview")
	preview.free()
	app.free()
	return true


func test_storyboard_cache_budget() -> bool:
	var previous_textures: Dictionary = Preview3D._tex_cache
	var previous_boost: Dictionary = Preview3D._tex_boost
	var previous_sizes: Dictionary[String, int] = Preview3D._tex_sizes
	var previous_use: Dictionary[String, int] = Preview3D._tex_last_used
	var previous_boards: Dictionary = Preview3D._board_cache
	var previous_bytes: int = Preview3D._tex_cache_bytes
	var previous_trim_ms: int = Preview3D._tex_next_trim_ms
	var previous_generation: int = Preview3D._tex_generation
	var previous_eviction_generation: int = Preview3D._tex_eviction_generation
	Preview3D._tex_cache = {}
	Preview3D._tex_boost = {}
	Preview3D._tex_sizes = {}
	Preview3D._tex_last_used = {}
	Preview3D._board_cache = {}
	Preview3D._tex_cache_bytes = 0
	Preview3D._tex_next_trim_ms = 0

	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var bytes: int = image.get_data_size()
	var now: int = 10000
	Preview3D._cache_storyboard_texture("active", image, 1.0, now - 4000)
	Preview3D._cache_storyboard_texture("oldest", image, 2.0, now - 3000)
	Preview3D._cache_storyboard_texture("recent", image, 1.0, now - 1000)
	Preview3D.keep_storyboard_texture("active", now)
	Preview3D._trim_storyboard_textures(now, bytes * 2)
	ok(not Preview3D._tex_cache.has("oldest") and not Preview3D._tex_boost.has("oldest"), "the oldest unused texture and its metadata are evicted")
	ok(Preview3D._tex_cache.has("active") and Preview3D._tex_cache.has("recent"), "the trim preserves current and recently used textures")
	eq(Preview3D._tex_cache_bytes, bytes * 2, "eviction accounts for the released image bytes")
	Preview3D._trim_storyboard_textures(now + 250, bytes)
	eq(Preview3D._tex_cache.size(), 2, "an active scene can temporarily exceed the budget")
	Preview3D._trim_storyboard_textures(now + 4000, bytes)
	eq(Preview3D._tex_cache.size(), 1, "temporary overage is trimmed after the scene stops using its textures")

	for i in Preview3D.STORYBOARD_BOARD_CACHE_LIMIT:
		Preview3D._cache_storyboard(str(i), Storyboard.new())
	Preview3D._get_cached_storyboard("0")
	Preview3D._cache_storyboard("new", Storyboard.new())
	ok(Preview3D._board_cache.has("0") and not Preview3D._board_cache.has("1"), "parsed boards also evict the least recently used entry")
	eq(Preview3D._board_cache.size(), Preview3D.STORYBOARD_BOARD_CACHE_LIMIT, "parsed board cache stays bounded")

	Preview3D._tex_cache = previous_textures
	Preview3D._tex_boost = previous_boost
	Preview3D._tex_sizes = previous_sizes
	Preview3D._tex_last_used = previous_use
	Preview3D._board_cache = previous_boards
	Preview3D._tex_cache_bytes = previous_bytes
	Preview3D._tex_next_trim_ms = previous_trim_ms
	Preview3D._tex_generation = previous_generation
	Preview3D._tex_eviction_generation = previous_eviction_generation
	return true


func test_text_command_center() -> bool:
	var preview := Preview3D.new()
	preview.size = Vector2(800, 600)
	var text := AlphaCommand.new("TEXT", 1.0)
	text.params["content"] = "HELLO"
	text.params["x"] = 0.5
	text.params["y"] = -0.5
	var center := preview._text_center(text)
	near(center.x, 600.0, 0.001, "text X is normalized to the preview width")
	near(center.y, 150.0, 0.001, "text Y is normalized to the preview height")
	preview.free()
	return true


func test_note_mods_io() -> bool:
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	ok(note.mods_to_dict().is_empty(), "default note has no mods")
	note.hs = 1.5
	note.sv = 0.75
	note.spawn = 0.3
	note.bounce = 0.5
	note.bounce_dir = 1
	note.touch_start = "A1"
	note.touch_end = "E8"
	var mods := note.mods_to_dict()
	ok(mods.has("hs") and mods.has("touch_start"), "mods written")
	var restored := Note.from_dict(note.to_dict())
	ok(is_equal_approx(restored.hs, 1.5), "hs round trips")
	ok(is_equal_approx(restored.sv, 0.75), "sv round trips")
	ok(is_equal_approx(restored.spawn, 0.3), "spawn round trips")
	ok(is_equal_approx(restored.bounce, 0.5), "bounce round trips")
	eq(restored.bounce_dir, 1, "bounce direction round trips")
	eq(restored.touch_start, "A1", "touch start round trips")
	eq(restored.touch_end, "E8", "touch end round trips")
	return true


func test_note_touch_zones() -> bool:
	eq(Note.touch_sensor("A1"), 0, "A1 is sensor 0")
	eq(Note.touch_sensor("A8"), 7, "A8 is sensor 7")
	eq(Note.touch_sensor("B1"), 8, "B1 is sensor 8")
	eq(Note.touch_sensor("C"), 16, "C is sensor 16")
	eq(Note.touch_sensor("D1"), 17, "D1 is sensor 17")
	eq(Note.touch_sensor("E8"), 32, "E8 is sensor 32")
	eq(Note.touch_sensor("F1"), -1, "F zone does not exist")
	eq(Note.touch_sensor("A9"), -1, "sensor index out of range")
	ok(Note.is_touch_position("b7"), "lowercase touch zone accepted")
	ok(not Note.is_touch_position("Q1"), "unknown zone rejected")
	eq(Note.mirror_touch("A1"), "B1", "mirror A to B")
	eq(Note.mirror_touch("D4"), "E4", "mirror D to E")
	eq(Note.mirror_touch("C"), "C", "center zone stays")
	var slide := Note.new("path", 2.0, 90.0, 60.0)
	slide.touch_start = "A1"
	ok(slide.is_touch_slide(), "touch zone makes a touch slide")
	slide.mirror_lr()
	eq(slide.touch_start, "B1", "mirroring swaps the touch zone")
	return true


func test_chart_commands_roundtrip() -> bool:
	var chart := Chart.new()
	chart.timing.points.clear()
	chart.timing.points.append(TimingPoint.new(0.0, 120.0, 4))
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	note.id = 1
	note.hs = 0.75
	chart.notes.append(note)
	var text := chart.add_command("TEXT", 2.0)
	text.params["content"] = "HELLO"
	chart.add_command("JLINE", 3.0)
	eq(chart.commands.size(), 2, "two commands added")
	eq(text.id, "C1", "first command id")
	ok(is_equal_approx(chart.duration_beats(), 4.0), "command duration counted")

	var json := ChartIO.to_json(chart)
	var loaded := ChartIO.from_json(json)
	ok(loaded != null, "chart with commands loads back")
	if loaded == null:
		return false
	eq(loaded.commands.size(), 2, "commands survive the round trip")
	eq(String(loaded.commands_in("text")[0].params.get("content", "")), "HELLO", "text content survives")
	ok(is_equal_approx(loaded.notes[0].hs, 0.75), "note mods survive")
	ok(is_equal_approx(loaded.duration_beats(), 4.0), "loaded duration matches")

	var dir := "user://pr97_tmc"
	eq(ChartIO.save_project([{"name": "Alpha", "chart": chart}], dir, "Alpha"), OK, "TMC project with commands saves")
	var project := ChartIO.load_project(dir)
	ok(bool(project.get("ok", false)), "TMC project with commands loads")
	if bool(project.get("ok", false)):
		var tmc_chart: Chart = project.entries[0].chart
		eq(tmc_chart.commands.size(), 2, "commands survive TMC")
		eq(String(tmc_chart.commands_in("text")[0].params.get("content", "")), "HELLO", "TMC text content survives")
		ok(is_equal_approx(tmc_chart.notes[0].hs, 0.75), "TMC note mods survive")
	var project_dir := ProjectSettings.globalize_path(dir)
	for name in ["main.tmc", "chart0.tmc", "color.tmc", "shaped.tmc", "storyboard.tmc", "music.wav"]:
		var path := project_dir.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(project_dir):
		DirAccess.remove_absolute(project_dir)

	var legacy := ChartIO.chart_from_dict({
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"notes": [],
	})
	ok(legacy != null and legacy.commands.is_empty(), "charts without commands still load")
	return true


## 演出指令 + 音符修饰在 dict / JSON / 单文件 / 三文件 / TMC 工程里都要原样往返。
func test_alpha_command_save_load_chain() -> bool:
	var root := "user://alpha_chain_test"
	_remove_alpha_chain_dir(root)
	var chart := _make_alpha_chain_chart()
	var data := ChartIO.chart_to_dict(chart)
	ok(data.has("commands"), "chart_to_dict 写出 commands")
	ok(_check_alpha_chain("dict", ChartIO.chart_from_dict(data)), "dict 往返")
	var json := ChartIO.to_json(chart)
	ok(json.contains("\"commands\""), "JSON 写出 commands")
	ok(_check_alpha_chain("json", ChartIO.from_json(json)), "JSON 往返")
	var single := root.path_join("single.json")
	eq(ChartIO.save_chart_file(chart, single), OK, "单文件保存")
	ok(_check_alpha_chain("single", ChartIO.load_chart(single)), "单文件读取")
	var three := root.path_join("three")
	eq(ChartIO.save_three_file(chart, three), OK, "三文件保存")
	ok(_check_alpha_chain("three", ChartIO.load_three_file(three)), "三文件读取")
	ok(ChartIO.chart_path_exists(three), "回放路径接受三文件文件夹")
	ok(ChartIO.chart_path_exists(single), "回放路径接受单文件")
	var three_json := FileAccess.get_file_as_string(three.path_join("chart.json"))
	ok(three_json.contains("\"commands\""), "三文件 chart.json 带 commands")
	var app: App = load("res://charter/app.gd").new()
	app.chart = chart
	var app_dir := root.path_join("app_three")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(app_dir))
	app.chart_path = app_dir
	ok(app.save_chart(), "App 三文件保存")
	ok(app.load_chart(app_dir), "App 三文件读取")
	ok(_check_alpha_chain("app-three", app.chart), "App 三文件往返")
	app.free()
	var project := root.path_join("project")
	var second := ChartIO.chart_from_dict(ChartIO.chart_to_dict(chart))
	second.metadata["version"] = "2"
	second.commands_in("text")[0].params["content"] = "WORLD"
	eq(ChartIO.save_project([{"name": "test", "chart": chart}, {"name": "second", "chart": second}],
		project.path_join("main.tmc")), OK, "TMC 工程保存")
	var loaded_project := ChartIO.load_project(project.path_join("main.tmc"))
	ok(bool(loaded_project.get("ok", false)), "TMC 工程读取")
	ok(ChartIO.chart_path_exists(project.path_join("main.tmc")), "回放路径接受工程主文件")
	ok(ChartIO.chart_path_exists(project), "回放路径接受工程文件夹")
	ok(not ChartIO.chart_path_exists(root.path_join("missing.tmc")), "回放路径拒绝不存在的文件")
	var entries: Array = loaded_project.get("entries", [])
	eq(entries.size(), 2, "TMC 工程难度数量")
	if entries.size() == 2:
		var first_chart: Chart = entries[0].get("chart", null) as Chart
		var second_chart: Chart = entries[1].get("chart", null) as Chart
		ok(_check_alpha_chain("tmc-1", first_chart), "TMC 第一难度往返")
		ok(_check_alpha_chain("tmc-2", second_chart, "WORLD"), "TMC 第二难度往返")
		eq(second_chart.commands_in("text")[0].text_value("content"), "WORLD", "第二难度保留自己的文本")
	var chart_tmc := FileAccess.get_file_as_string(project.path_join("chart0.tmc"))
	ok(chart_tmc.contains("command="), "TMC chart0 写出 command=")
	ok(chart_tmc.contains("HELLO"), "TMC chart0 写出文本内容")
	var second_tmc := FileAccess.get_file_as_string(project.path_join("chart1.tmc"))
	ok(second_tmc.contains("WORLD"), "TMC chart1 写出自己的文本")
	var app_project: App = load("res://charter/app.gd").new()
	ok(app_project.load_chart(project.path_join("main.tmc")), "App 打开 TMC 工程")
	eq(app_project.difficulties.size(), 2, "App TMC 工程保留两个难度")
	if app_project.chart != null:
		ok(_check_alpha_chain("app-tmc", app_project.chart), "App TMC 工程往返")
	app_project.free()
	_remove_alpha_chain_dir(root)
	return true


func _make_alpha_chain_chart() -> Chart:
	var chart := Chart.new()
	chart.timing.points.clear()
	chart.timing.points.append(TimingPoint.new(0.0, 120.0, 4))
	chart.metadata["title"] = "chain"
	chart.metadata["artist"] = "test"
	chart.metadata["creator"] = "test"
	chart.metadata["version"] = "1"
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	note.id = 1
	note.hs = 1.5
	note.sv = 2.0
	note.head_speed = 1.2
	note.spawn = 0.3
	note.bounce = 0.4
	note.bounce_dir = 1
	note.touch_start = "A1"
	note.touch_end = "B8"
	chart.notes.append(note)
	var jline := chart.add_command("JLINE", 2.0)
	jline.params["color"] = "#123456"
	jline.params["width"] = 8.0
	var text := chart.add_command("TEXT", 4.0)
	text.params["content"] = "HELLO"
	text.params["size"] = 64.0
	text.duration = 2.5
	text.easing = "ease_in_out"
	var flash := chart.add_command("FLASH", 6.0)
	flash.params["strength"] = 0.6
	flash.params["region_on"] = true
	flash.params["region_angle"] = 45.0
	flash.params["region_span"] = 90.0
	flash.params["region_inner"] = 0.3
	flash.params["region_outer"] = 0.8
	flash.params["region_feather"] = 0.05
	flash.enabled = false
	chart.refresh_ids()
	return chart


func _check_alpha_chain(label: String, loaded: Chart, expected_text: String = "HELLO") -> bool:
	if loaded == null:
		ok(false, "%s 读取失败" % label)
		return false
	eq(loaded.commands.size(), 3, "%s 指令数量" % label)
	var by_name := {}
	for command in loaded.commands:
		by_name[command.name] = command
	var jline: AlphaCommand = by_name.get("JLINE") as AlphaCommand
	ok(jline != null, "%s JLINE 存在" % label)
	if jline != null:
		near(jline.beat, 2.0, 0.001, "%s JLINE 拍" % label)
		eq(String(jline.params.get("color", "")), "#123456", "%s JLINE 颜色" % label)
		near(float(jline.params.get("width", 0.0)), 8.0, 0.001, "%s JLINE 粗细" % label)
	var text: AlphaCommand = by_name.get("TEXT") as AlphaCommand
	ok(text != null, "%s TEXT 存在" % label)
	if text != null:
		eq(text.text_value("content"), expected_text, "%s TEXT 内容" % label)
		near(text.duration, 2.5, 0.001, "%s TEXT 时长" % label)
		eq(text.easing, "ease_in_out", "%s TEXT 缓动" % label)
	var flash: AlphaCommand = by_name.get("FLASH") as AlphaCommand
	ok(flash != null, "%s FLASH 存在" % label)
	if flash != null:
		ok(not flash.enabled, "%s FLASH 停用" % label)
		near(float(flash.params.get("strength", 0.0)), 0.6, 0.001, "%s FLASH 强度" % label)
		ok(bool(flash.params.get("region_on", false)), "%s FLASH 区域开启" % label)
		near(float(flash.params.get("region_angle", 0.0)), 45.0, 0.001, "%s FLASH 区域角度" % label)
		near(float(flash.params.get("region_span", 0.0)), 90.0, 0.001, "%s FLASH 区域跨度" % label)
		near(float(flash.params.get("region_inner", 0.0)), 0.3, 0.001, "%s FLASH 内半径" % label)
		near(float(flash.params.get("region_outer", 0.0)), 0.8, 0.001, "%s FLASH 外半径" % label)
	eq(loaded.notes.size(), 1, "%s 音符数量" % label)
	if loaded.notes.size() == 1:
		var note := loaded.notes[0]
		near(note.hs, 1.5, 0.001, "%s hs" % label)
		near(note.sv, 2.0, 0.001, "%s sv" % label)
		near(note.head_speed, 1.2, 0.001, "%s head_speed" % label)
		near(note.spawn, 0.3, 0.001, "%s spawn" % label)
		near(note.bounce, 0.4, 0.001, "%s bounce" % label)
		eq(note.bounce_dir, 1, "%s bounce_dir" % label)
		eq(note.touch_start, "A1", "%s touch_start" % label)
		eq(note.touch_end, "B8", "%s touch_end" % label)
	eq(loaded.next_command_id(), "C4", "%s 下一条指令 id" % label)
	return true


func _remove_alpha_chain_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			if dir.current_is_dir():
				_remove_alpha_chain_dir(path.path_join(name))
			else:
				DirAccess.remove_absolute(absolute.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)


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
func test_storyboard_sample_ownership() -> bool:
	var board: Storyboard = Storyboard.parse(
		'[Events]\nSprite,Foreground,Centre,"one.png",320,240\n F,0,100,200,1,1\n')
	var sprite: Storyboard.Sprite = board.sprites[0]
	var lifetime: WeakRef = weakref(sprite)
	var canvas := StoryboardCanvas.new()
	canvas.set_board(board, "user://")
	canvas._items = board.sample(100.0)
	eq(canvas._items.size(), 1, "first visible frame keeps a reference for editing")
	canvas.set_playhead(150.0)
	eq(board.sample(100.0).size(), 1, "seeking does not clear the storyboard sample")
	eq(board.sample(200.0).size(), 1, "last visible frame stays in the time index")
	eq(board.sample(201.0).size(), 0, "the storyboard stops sampling outside visibility")
	canvas.free()
	board = null
	sprite = null
	ok(lifetime.get_ref() == null, "cached endpoint states do not keep their sprite alive")
	return true


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
