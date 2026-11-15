extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)


func _run() -> void:
	var app := root.get_node("App")
	app.hit_sfx_style = "default"
	var editor = load("res://charter/main.tscn").instantiate()
	root.add_child(editor)
	editor.set_process(false)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	var bus := AudioServer.get_bus_index("SFX")
	AudioServer.add_bus_effect(bus, capture)
	await create_timer(0.3).timeout
	for kind in HitSfx.PATHS:
		for player in editor._sfx._players:
			player.stop()
		await create_timer(0.05).timeout
		capture.clear_buffer()
		editor._sfx.play(kind)
		await create_timer(0.25).timeout
		var peak := 0.0
		for frame in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		_check(peak > 0.001, "%s produces audio on SFX bus" % kind)
	# Both imported and native charts must retain crossed events after a slow frame.
	var fixture := "user://sfx_maidata.txt"
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	file.store_string("&title=SFX\n&wholebpm=120\n&inote_1=(120){4}1,2h[4:1],3-5[4:1],E\n")
	file.close()
	var imported := SimaiIO.import_maidata(fixture, 1)
	_check(imported != null, "simai sound fixture imports")
	var custom := DemoChart.make_empty({"bpm": 120.0})
	custom.notes.clear()
	for i in 3:
		var note := Note.new("tap", 0.25 * float(i + 1), 90.0, 60.0)
		note.id = i + 1
		custom.notes.append(note)
	for chart in [custom, imported]:
		if chart == null:
			continue
		for player in editor._sfx._players:
			player.stop()
		await create_timer(0.05).timeout
		capture.clear_buffer()
		app.set_chart(chart, "", false)
		editor._build_sfx_events()
		editor._sfx_last_beat = 0.0
		editor._sfx_event_index = 0
		var expected := 0
		for event in editor._sfx_events:
			if float(event["beat"]) <= 1.0:
				expected += 1
		var before: int = editor._sfx._index
		editor._fire_editor_sfx(1.0)
		_check(expected > 0 and editor._sfx._index - before == expected, "slow frame plays all crossed chart events")
		_check(await _await_peak(capture) > 0.001, "editor chart events reach SFX bus")
		before = editor._sfx._index
		editor._fire_editor_sfx(1.0)
		_check(editor._sfx._index == before, "same beat never duplicates sounds")
		# 滑条尾现在落在第 4 拍（头拍 + 1 拍等待 + 滑动），跳转点放在它之前。
		editor._rebase_playback(3.0)
		before = editor._sfx._index
		editor._fire_editor_sfx(3.0)
		_check(editor._sfx._index == before, "explicit seek skips earlier sounds")
	app.hit_sfx_style = "mute"
	for player in editor._sfx._players:
		player.stop()
	var playtest := Playtest.new()
	root.add_child(playtest)
	playtest.set_process(false)
	app.hit_sfx_style = "mute"
	app.appearance_changed.emit()
	_check(playtest._sfx.style == "mute", "playtest applies live mute setting")
	app.hit_sfx_style = "default"
	app.appearance_changed.emit()
	_check(playtest._sfx.style == "default", "playtest applies live unmute setting")
	for chart in [custom, imported]:
		if chart == null:
			continue
		playtest.setup(chart, 0.0, "")
		playtest._preview.time_beat = 0.0
		await process_frame
		var note: Note = chart.notes[0]
		var stamp: float = chart.timing.beat_to_chart_ms(note.beat)
		playtest._preview.prepare_playtest_frame(note.beat, 0.016)
		var point := playtest._preview.note_head_screen(note, note.beat)
		playtest._key_presses.append({"time": stamp, "mouse": point, "angle": note.angle, "key": KEY_A})
		playtest._assign_presses(stamp, note.beat)
		var before: int = playtest._sfx._index
		capture.clear_buffer()
		playtest._judge_tap(note, stamp, note.beat)
		_check(playtest._hit_count == 1, "playtest accepts chart hit")
		_check(playtest._sfx._index == before + 1, "playtest chart hit triggers sound")
		_check(await _await_peak(capture) > 0.001, "playtest chart hit reaches SFX bus")
	# Head contact and slide start are separate audible events during the wait.
	for width in [60.0, 75.0]:
		var chart := DemoChart.make_empty({"bpm": 120.0})
		chart.notes.clear()
		var note := Note.new("path", 2.0, 0.0, width)
		note.end_beat = 6.0
		note.wait_beat = 1.0
		note.tail_angle = 180.0
		note.generate_path_shape()
		chart.notes.append(note)
		playtest.setup(chart, 0.0, "")
		playtest._preview.prepare_playtest_frame(2.0, 0.016)
		var point := playtest._preview.note_head_screen(note, 2.0)
		playtest._press_assignments[note.id] = {"time": 1000.0, "mouse": point}
		var before: int = playtest._sfx._index
		capture.clear_buffer()
		playtest._judge_path(note, 1000.0, 2.0, point)
		_check(playtest._sfx._index == before + 1, "Path head hit triggers exactly one sound")
		var player: AudioStreamPlayer = playtest._sfx._players[before % playtest._sfx._players.size()]
		_check(player.stream == playtest._sfx._streams[HitSfx.kind_for_note(note)], "Path head uses same sound as matching Tap")
		_check(await _await_peak(capture) > 0.001, "Path head hit reaches SFX bus")
		playtest._judge_path(note, 1010.0, 2.02, point)
		_check(playtest._sfx._index == before + 1, "judged Path head never repeats its sound")
		playtest._judge_path(note, 1500.0, 3.0, point)
		_check(playtest._sfx._index == before + 2 and bool(playtest._states[note.id]["slide_cued"]), "waiting still ends with a separate slide cue")
		app.set_chart(chart, "", false)
		editor._build_sfx_events()
		_check(editor._sfx_events[0]["kind"] == HitSfx.kind_for_note(note), "editor Path head matches Tap sound too")
	AudioServer.remove_bus_effect(bus, 0)
	playtest.free()
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("SFX playback: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## 无头/Dummy 音频按缓冲周期出帧，固定等 0.2s 会抖；等到真的出帧为止。
func _await_peak(capture: AudioEffectCapture, timeout_sec := 1.0) -> float:
	var waited := 0.0
	while waited < timeout_sec:
		await create_timer(0.05).timeout
		waited += 0.05
		var peak := _capture_peak(capture)
		if peak > 0.001:
			return peak
	return 0.0


func _capture_peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak
