extends Control

## 真实输入审计：用 Input.parse_input_event 注入真正的 InputEventKey（走 _input）。
## 两组场景各跑一遍完整试玩：
##   A 光标对准音符 → 全部命中（位置判定能正常命中）
##   B 光标在角落   → 全部 MISS（位置判定确实生效，不是按键即判定）
## 覆盖：普通 Tap、1/4 拍密集三连、同拍双押、Hold、Path 头、对照片、6.5 秒后的 Tap。

var passed := 0
var failed := 0


func _ready() -> void:
	await _run()
	print("=== INPUT AUDIT RESULT passed=%d failed=%d ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s" % label)


func _run() -> void:
	var app := get_node_or_null("/root/App")
	if app != null:
		app.playtest_offset_ms = 0.0

	var aligned := await _run_case(false)
	_check(int(aligned["tap_miss"]) == 1, "A 光标对准：只有对照片 MISS（实际 %d）" % int(aligned["tap_miss"]))
	_check(int(aligned["hit"]) >= 10, "A 光标对准：至少 10 颗命中（实际 %d）" % int(aligned["hit"]))
	_check(bool(aligned["late_hit"]), "A 光标对准：6.5 秒后的 Tap 仍能判定（end_beat 兜底）")

	var far := await _run_case(true)
	_check(int(far["tap_miss"]) >= 8, "B 光标在角落：Tap 应被位置判定拒收（实际 MISS %d）" % int(far["tap_miss"]))
	_check(int(far["hit"]) == 0, "B 光标在角落：0 命中（实际 %d）" % int(far["hit"]))


func _build_chart() -> Chart:
	var chart: Chart = DemoChart.make_empty({"title": "input-audit", "bpm": 120.0})
	chart.notes.clear()
	chart.timing.points.clear()
	chart.timing.points.append(TimingPoint.new(0.0, 120.0, 4))
	var definitions := [
		["tap", 1.0, 0.0],
		["tap", 2.0, 0.0],
		["tap", 3.0, 0.0],
		["tap", 3.25, 0.0],
		["tap", 3.5, 0.0],
		["tap", 4.0, 0.0],
		["tap", 4.0, 0.0],
		["hold", 5.0, 6.0],
		["path", 6.0, 7.0],
		["tap", 8.0, 0.0],
		["tap", 13.0, 0.0],
	]
	for i in definitions.size():
		var entry: Array = definitions[i]
		var note := Note.new(String(entry[0]), float(entry[1]), 90.0 if i % 2 == 0 else 270.0, 60.0)
		note.id = i + 1
		note.end_beat = float(entry[2]) if float(entry[2]) > 0.0 else float(entry[1])
		if note.type == "path":
			note.tail_angle = 270.0
			note.tail_width = 52.0
			note.tolerance = 0.24
			note.wait_beat = 0.25
		if note.type == "hold":
			note.hold_style = "straight"
		chart.notes.append(note)
	# 模拟历史脏数据：6.5 秒后那颗 Tap 的 end_beat 写成 0，必须靠 target_ms 兜底。
	for note in chart.notes:
		if note.type == "tap" and absf(note.beat - 13.0) < 0.001:
			note.end_beat = 0.0
	return chart


func _run_case(cursor_far: bool) -> Dictionary:
	var chart := _build_chart()
	var control_id := 0
	for note in chart.notes:
		if note.type == "tap" and absf(note.beat - 8.0) < 0.001:
			control_id = note.id

	var events: Array = []
	for i in chart.notes.size():
		var note: Note = chart.notes[i]
		if note.id == control_id:
			continue
		var key := KEY_A + i
		var head_ms := chart.timing.beat_to_chart_ms(note.beat)
		events.append({"ms": head_ms, "key": key, "down": true, "note": note, "sent": false})
		if note.type == "hold":
			var tail_ms := chart.timing.beat_to_chart_ms(note.end_beat)
			events.append({"ms": tail_ms - 40.0, "key": key, "down": false, "note": note, "sent": false})
		else:
			events.append({"ms": head_ms + 40.0, "key": key, "down": false, "note": note, "sent": false})

	var playtest := Playtest.new()
	add_child(playtest)
	playtest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	playtest.setup(chart, 0.0, "")
	await get_tree().process_frame

	var finish_ms := chart.timing.beat_to_chart_ms(14.5)
	while is_instance_valid(playtest) and playtest._chart_ms() < finish_ms:
		await get_tree().process_frame
		var now_ms: float = playtest._chart_ms()
		var beat: float = chart.timing.chart_ms_to_beat(now_ms)
		for event in events:
			if bool(event["sent"]) or now_ms < float(event["ms"]):
				continue
			event["sent"] = true
			if cursor_far:
				playtest._preview.mouse_screen = Vector2(24, 24)
			else:
				var note: Note = event["note"]
				playtest._preview.mouse_screen = playtest._preview.note_head_screen(note, beat)
			var key_event := InputEventKey.new()
			key_event.keycode = int(event["key"])
			key_event.physical_keycode = int(event["key"])
			key_event.pressed = bool(event["down"])
			Input.parse_input_event(key_event)
	await get_tree().process_frame

	var tap_misses := 0
	var control_missed := false
	var late_hit := false
	for line in playtest._log:
		var text := String(line)
		if text.begins_with("MISS Tap"):
			tap_misses += 1
			if text.contains("#%d " % control_id):
				control_missed = true
		if text.contains("Tap #%d " % (chart.notes.size())) and not text.contains("MISS"):
			late_hit = true
	print("[case far=%s] 命中=%d MISS=%d TapMISS=%d late_hit=%s" % [
		str(cursor_far), playtest._hit_count, playtest._miss_count, tap_misses, str(late_hit)])
	var result := {
		"hit": playtest._hit_count,
		"tap_miss": tap_misses,
		"miss": playtest._miss_count,
		"late_hit": late_hit,
		"control_missed": control_missed,
		"log": playtest._log.duplicate(),
	}
	playtest.queue_free()
	await get_tree().process_frame
	return result
