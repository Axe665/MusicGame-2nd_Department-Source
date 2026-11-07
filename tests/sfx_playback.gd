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
		await create_timer(0.2).timeout
		_check(_capture_peak(capture) > 0.001, "editor chart events reach SFX bus")
		before = editor._sfx._index
		editor._fire_editor_sfx(1.0)
		_check(editor._sfx._index == before, "same beat never duplicates sounds")
		editor._rebase_playback(4.0)
		before = editor._sfx._index
		editor._fire_editor_sfx(4.0)
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
		var point := playtest._preview.note_head_screen(note, note.beat)
		playtest._key_presses.append({"time": stamp, "mouse": point, "angle": note.angle, "key": KEY_A})
		var before: int = playtest._sfx._index
		capture.clear_buffer()
		playtest._judge_tap(note, stamp, note.beat)
		_check(playtest._hit_count == 1, "playtest accepts chart hit")
		_check(playtest._sfx._index == before + 1, "playtest chart hit triggers sound")
		await create_timer(0.2).timeout
		_check(_capture_peak(capture) > 0.001, "playtest chart hit reaches SFX bus")
	AudioServer.remove_bus_effect(bus, 0)
	playtest.free()
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	print("SFX playback: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _capture_peak(capture: AudioEffectCapture) -> float:
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak
