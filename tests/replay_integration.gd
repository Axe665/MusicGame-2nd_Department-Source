extends Node

## 回放全链路冒烟：构造录制输入 → Playtest.setup 进入回放 → 拖到结尾结算。
## 这一层覆盖“事件能分派”之外的东西：时间轴、判定、结算和进度条真正跑一遍。

var _failed := 0


func _ready() -> void:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.metadata["title"] = "replay-check"
	chart.metadata["version"] = "1"
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	note.id = 0
	chart.notes.append(note)
	chart.refresh_ids()
	var hit_ms := chart.timing.beat_to_chart_ms(1.0)
	var replay := Replay.new()
	replay.coords = Replay.COORDS_UNIT
	replay.chart_path = "user://replay_integration_chart.json"
	replay.chart_hash = Replay.hash_chart(chart)
	replay.start_beat = 0.0
	replay.settings = {"title": "replay-check", "version": "1", "offset_ms": 0.0, "mirror": "off"}
	replay.add_move(hit_ms - 50.0, Vector2(0.5, 0.5))
	replay.add_press(hit_ms, hit_ms - 8.0, hit_ms + 8.0, 65, Vector2(0.5, 0.5), 90.0, 0.25, true)
	replay.add_release(hit_ms + 60.0, 65)
	var run := Playtest.new()
	add_child(run)
	await get_tree().process_frame
	run._build_ui()
	run.replay_source = replay
	await run.setup(chart, 0.0, replay.chart_path)
	await get_tree().process_frame
	_check(run.replay_mode, "setup enters replay mode")
	_check(run._running, "replay starts without countdown")
	_check(run._preview.custom_cursor_visible, "replay keeps the custom cursor visible")
	_check(run._preview.auto_cursor.is_finite(), "replay uses the recorded cursor")
	run._seek_replay(1.0)
	await get_tree().process_frame
	_check(run._finished, "replay reaches the results screen")
	_check(int(run._tier_counts.get("PERFECT", 0)) == 1, "recorded press judges as PERFECT")
	_check(run._replay_index == 2, "events up to the end are dispatched once")
	_check(is_equal_approx(run._replay_ms, run._replay_total_ms), "replay ends at the chart end")
	if _failed > 0:
		push_error("replay_integration: %d failed" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[replay] PASS ", message)
	else:
		_failed += 1
		push_error("[replay] FAIL " + message)
