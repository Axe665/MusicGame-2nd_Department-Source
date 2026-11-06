extends Control

## 真实输入审计：用 Input.parse_input_event 注入真正的 InputEventKey（走 _input），
## 光标故意固定在屏幕角落，验证“按键是否被判定吃掉”。
## 覆盖：普通 Tap、1/4 拍密集三连、同拍双押、Hold、Path 头、以及对照片（故意不打）。

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
	]
	var last_tap_id := 0
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
		if note.type == "tap":
			last_tap_id = note.id
	# 最后一颗 Tap 作为对照片：故意不按，必须 MISS。
	var control_id := last_tap_id

	var events: Array = []
	for i in chart.notes.size():
		var note: Note = chart.notes[i]
		if note.id == control_id:
			continue
		var key := KEY_A + i
		var head_ms := chart.timing.beat_to_chart_ms(note.beat)
		events.append({"ms": head_ms, "key": key, "down": true, "sent": false})
		if note.type == "hold":
			var tail_ms := chart.timing.beat_to_chart_ms(note.end_beat)
			events.append({"ms": tail_ms - 40.0, "key": key, "down": false, "sent": false})
		else:
			events.append({"ms": head_ms + 40.0, "key": key, "down": false, "sent": false})

	var playtest := Playtest.new()
	add_child(playtest)
	playtest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	playtest.setup(chart, 0.0, "")
	await get_tree().process_frame

	var finish_ms := chart.timing.beat_to_chart_ms(9.5)
	while is_instance_valid(playtest) and playtest._chart_ms() < finish_ms:
		await get_tree().process_frame
		var now_ms: float = playtest._chart_ms()
		for event in events:
			if bool(event["sent"]) or now_ms < float(event["ms"]):
				continue
			event["sent"] = true
			# 光标固定在角落：位置判定不应影响普通段命中。
			playtest._preview.mouse_screen = Vector2(24, 24)
			var key_event := InputEventKey.new()
			key_event.keycode = int(event["key"])
			key_event.physical_keycode = int(event["key"])
			key_event.pressed = bool(event["down"])
			Input.parse_input_event(key_event)
	await get_tree().process_frame

	print("按键事件=%d 过期=%d 命中=%d MISS=%d 判定=%s" % [
		playtest._press_total, playtest._press_expired, playtest._hit_count,
		playtest._miss_count, str(playtest._tier_counts)])
	for line in playtest._log:
		print("  ", line)

	var expected_presses := 0
	for event in events:
		if bool(event["down"]):
			expected_presses += 1
	_check(playtest._press_total >= expected_presses, "所有注入的按下事件都被收到（%d/%d）" % [playtest._press_total, expected_presses])
	_check(playtest._press_expired == 0, "没有按键未经判定就过期（%d）" % playtest._press_expired)
	var tap_misses := 0
	var control_missed := false
	for line in playtest._log:
		if String(line).begins_with("MISS Tap"):
			tap_misses += 1
			if String(line).contains("#%d " % control_id):
				control_missed = true
	_check(tap_misses == 1, "只有对照片 MISS，其它 Tap 都判定成功（实际 Tap MISS=%d）" % tap_misses)
	_check(control_missed, "对照片 #%d 正确判为 MISS" % control_id)
	_check(playtest._hit_count >= 8, "至少 8 颗音符被判定（实际 %d）" % playtest._hit_count)
	var hold_ok := false
	var path_head_ok := false
	for line in playtest._log:
		if String(line).contains("HOLD #") and String(line).contains("HEAD"):
			hold_ok = true
		if String(line).contains("PATH #") and String(line).contains("HEAD") and not String(line).contains("MISS"):
			path_head_ok = true
	_check(hold_ok, "Hold 头被按键命中")
	_check(path_head_ok, "Path 头被按键命中（光标在角落也不影响）")

	playtest.queue_free()
	await get_tree().process_frame
