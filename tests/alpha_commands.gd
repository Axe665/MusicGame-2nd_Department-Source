extends SceneTree

## 演出指令（JLINE / TEXT / 滤镜）的数据层测试。
## 单独运行：godot --headless --path . --script res://tests/alpha_commands.gd

var passed := 0
var failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		_failures.append(label)


func _run() -> void:
	_test_catalog()
	_test_defaults_and_normalize()
	_test_envelope()
	_test_stateful()
	_test_roundtrip()
	_test_strongest()
	_test_filter_strength()
	_test_serialization_shape()
	_test_chart_commands()
	_test_note_mods()
	_test_touch_positions()
	_test_note_mods_roundtrip()
	_test_chart_roundtrip()

	if failed == 0:
		print("alpha_commands: %d passed" % passed)
	else:
		print("alpha_commands: %d passed, %d failed" % [passed, failed])
		for item in _failures:
			print("  FAIL ", item)
	quit(1 if failed > 0 else 0)


func _test_catalog() -> void:
	var jline := AlphaCommand.catalog(AlphaCommand.CATEGORY_JLINE)
	var text := AlphaCommand.catalog(AlphaCommand.CATEGORY_TEXT)
	var filters := AlphaCommand.catalog(AlphaCommand.CATEGORY_FILTER)
	check(jline.size() == 1, "判定线目录只有 JLINE")
	check(text.size() == 2, "文本目录含 TEXT / JUDGETEXT")
	check(filters.size() == 24, "滤镜目录 26 条，实际 %d" % filters.size())
	check(jline.size() + text.size() + filters.size() == AlphaCommand.CATALOG.size(), "三类相加等于总目录")

	var seen := {}
	for entry in AlphaCommand.CATALOG:
		var name := String(entry.get("name", ""))
		check(not name.is_empty(), "指令名非空")
		check(not seen.has(name), "指令名唯一: %s" % name)
		seen[name] = true
		check(not Array(entry.get("params", [])).is_empty(), "%s 至少一个参数" % name)
		check(AlphaCommand.spec_of(name).get("label", "") != "", "%s 有中文名" % name)

	check(AlphaCommand.spec_of("FLASH").get("category", "") == AlphaCommand.CATEGORY_FILTER, "FLASH 属于滤镜")
	check(AlphaCommand.spec_of("JLINE").get("category", "") == AlphaCommand.CATEGORY_JLINE, "JLINE 属于判定线")
	check(AlphaCommand.spec_of("TEXT").get("category", "") == AlphaCommand.CATEGORY_TEXT, "TEXT 属于文本")
	check(AlphaCommand.spec_of("NOPE").is_empty(), "未知指令返回空目录")


func _test_defaults_and_normalize() -> void:
	var defaults := AlphaCommand.defaults("FLASH")
	check(is_equal_approx(float(defaults.get("strength", 0.0)), 0.8), "FLASH 默认强度 0.8")
	check(AlphaCommand.default_duration("KALEIDOSCOPE") == 2.0, "KALEIDOSCOPE 默认 2 拍，有明确结束点")
	check(AlphaCommand.default_duration("FLASH") == 1.0, "FLASH 默认时长 1 拍")

	var normalized := AlphaCommand.normalize("FLASH", {"strength": 9.0, "junk": 1})
	check(is_equal_approx(float(normalized.get("strength", 0.0)), 1.0), "强度被夹到 1.0")
	check(not normalized.has("junk"), "目录外参数被丢弃")

	var color_normalized := AlphaCommand.normalize("JLINE", {"color": "not-a-color"})
	check(String(color_normalized.get("color", "")) == "#66e0ff", "非法颜色回落到默认")
	var good_color := AlphaCommand.normalize("JLINE", {"color": "#112233"})
	check(String(good_color.get("color", "")) == "#112233", "合法颜色保留")


func _test_envelope() -> void:
	var command := AlphaCommand.new("FLASH", 4.0)
	command.duration = 2.0
	command.params["strength"] = 1.0

	check(command.envelope_at(3.5) == 0.0, "起始拍之前为 0")
	check(command.envelope_at(4.0) == 0.0, "起始拍瞬间起势从 0 开始")
	check(command.envelope_at(5.0) > 0.99, "中段保持 1")
	check(command.envelope_at(6.0) == 0.0, "结束拍归 0")
	check(is_equal_approx(command.progress_at(5.0), 0.5), "进度按拍数折算")

	var ramp := command.envelope_at(4.25)
	check(ramp > 0.0 and ramp < 1.0, "起势段介于 0 与 1 之间")

	var tail := command.envelope_at(5.75)
	check(tail > 0.0 and tail < 1.0, "收势段介于 0 与 1 之间")

	command.enabled = false
	check(command.envelope_at(5.0) == 0.0, "禁用后包络恒为 0")


func _test_stateful() -> void:
	var flip := AlphaCommand.new("INVERT", 8.0)
	check(not flip.is_stateful(), "INVERT 现在是有限时长滤镜")
	check(flip.envelope_at(8.4) == 1.0, "反色起手后立即满强度")
	check(flip.envelope_at(100.0) == 0.0, "反色超过时长后停止")

	var kaleido := AlphaCommand.new("KALEIDOSCOPE", 2.0)
	check(kaleido.is_stateful(), "万花筒是开关型")
	check(kaleido.envelope_at(3.0) == 1.0, "万花筒窗口内生效")
	check(kaleido.envelope_at(5.0) == 0.0, "万花筒到结束拍就停，不会一直挂在画面上")
	kaleido.params["on"] = false
	check(kaleido.flag("on", true) == false, "关闭标记可读取")

	check(AlphaCommand.canonical("TVNOISE") == "GLITCH", "雪花噪点折叠到故障")
	check(AlphaCommand.canonical("shatter") == "GLITCH", "碎裂折叠到故障，且不区分大小写")
	check(AlphaCommand.canonical("GAUSSIAN") == "RADIALBLUR", "高斯模糊折叠到径向模糊")
	check(AlphaCommand.canonical("TRAIL") == "RADIALBLUR", "拖影折叠到径向模糊")
	check(AlphaCommand.spec_of("TVNOISE").get("label", "") == "故障", "别名能解析到保留下来的目录项")

	var legacy := AlphaCommand.from_dict({"name": "gaussian", "beat": 4.0, "duration": 1.0})
	check(legacy.name == "RADIALBLUR", "旧谱别名在载入时改名")
	check(legacy.to_dict()["name"] == "RADIALBLUR", "写出时只写保留名")

	var zero_duration := AlphaCommand.from_dict({"name": "KALEIDOSCOPE", "beat": 4.0, "duration": 0.0})
	check(zero_duration.duration >= 0.25, "旧谱的 0 时长状态指令载入时补成有界时长")
	check(zero_duration.envelope_at(4.5) == 1.0, "补完时长后仍然生效")


func _test_roundtrip() -> void:
	var command := AlphaCommand.new("TEXT", 12.5)
	command.id = "C7"
	command.duration = 3.0
	command.easing = "ease_out"
	command.params["content"] = "你好"
	command.params["size"] = 64.0
	command.params["x"] = -0.3

	var raw := command.to_dict()
	var restored := AlphaCommand.from_dict(raw)
	check(restored.id == "C7", "id 往返")
	check(restored.name == "TEXT", "名字往返")
	check(is_equal_approx(restored.beat, 12.5), "起始拍往返")
	check(is_equal_approx(restored.duration, 3.0), "时长往返")
	check(restored.easing == "ease_out", "缓动往返")
	check(String(restored.params.get("content", "")) == "你好", "文本参数往返")
	check(is_equal_approx(restored.number("size"), 64.0), "数值参数往返")
	check(is_equal_approx(restored.number("x"), -0.3), "坐标参数往返")

	var partial := AlphaCommand.from_dict({"name": "FLASH", "beat": 1.0})
	check(is_equal_approx(partial.number("strength"), 0.8), "缺省参数补默认值")
	check(is_equal_approx(partial.duration, 1.0), "缺省时长补默认值")


func _test_strongest() -> void:
	var weak := AlphaCommand.new("SHAKE", 0.0)
	weak.duration = 4.0
	weak.params["strength"] = 0.2
	var strong := AlphaCommand.new("SHAKE", 0.5)
	strong.duration = 1.0
	strong.params["strength"] = 0.9

	var commands: Array[AlphaCommand] = [weak, strong]
	# 不假设谁强：按包络实算，验证 strongest 与实算一致。
	var sample_beat := 1.1
	var expected: AlphaCommand = null
	var expected_value := 0.0
	for command in commands:
		var value := command.envelope_at(sample_beat)
		if value > expected_value:
			expected = command
			expected_value = value
	check(AlphaCommand.strongest(commands, "SHAKE", sample_beat) == expected, "同名取包络更强的一条")
	check(AlphaCommand.strongest(commands, "GLITCH", sample_beat) == null, "无同名指令返回 null")

	var active := AlphaCommand.active_at(commands, sample_beat)
	var active_expected := 0
	for command in commands:
		if command.envelope_at(sample_beat) > 0.0:
			active_expected += 1
	check(active.size() == active_expected, "active_at 只返回包络大于 0 的指令")
	check(AlphaCommand.enabled_commands(commands).size() == 2, "enabled_commands 保留启用项")


func _test_filter_strength() -> void:
	var flash := AlphaCommand.new("FLASH", 0.0)
	flash.duration = 2.0
	flash.params["strength"] = 0.8
	var commands: Array[AlphaCommand] = [flash]
	check(AlphaCommand.filter_strength(commands, "FLASH", 1.0) > 0.79, "中段强度约等于参数值")
	check(AlphaCommand.filter_strength(commands, "FLASH", -1.0) == 0.0, "未开始时强度为 0")
	check(AlphaCommand.filter_strength(commands, "ZOOM", 1.0) == 0.0, "未使用的滤镜强度为 0")

	var tint := AlphaCommand.new("TINT", 0.0)
	tint.params["color"] = "#00ff88"
	var tint_commands: Array[AlphaCommand] = [tint]
	var color := AlphaCommand.filter_color(tint_commands, "TINT", 0.5)
	check(absf(color.g - 1.0) < 0.01, "TINT 颜色可读出")


func _test_serialization_shape() -> void:
	var raw := AlphaCommand.new("MOVE", 2.0).to_dict()
	check(raw.has("name") and raw.has("beat") and raw.has("duration"), "序列化含基础字段")
	check(raw.has("params") and raw.get("params") is Dictionary, "序列化含参数表")
	check(not raw.has("label"), "不持久化展示名")


func _test_chart_commands() -> void:
	var chart := Chart.new()
	check(chart.commands.is_empty(), "新谱没有演出指令")
	var flash := chart.add_command("FLASH", 4.0)
	check(flash.id == "C1", "第一条指令编号 C1")
	check(flash.name == "FLASH", "指令名写入")
	check(is_equal_approx(chart.duration_beats(), 5.0), "指令时长并入谱面时长")
	var text := chart.add_command("TEXT", 2.0)
	check(text.id == "C2", "第二条指令编号 C2")
	check(chart.sorted_commands()[0] == text, "sorted_commands 按拍排序")
	check(chart.commands_in("text").size() == 1, "commands_in 按分类过滤")
	check(chart.commands_in("jline").is_empty(), "没有判定线指令")

	check(chart.remove_command(flash), "删除指令成功")
	check(not chart.remove_command(flash), "重复删除返回 false")
	check(chart.commands.size() == 1, "只剩一条指令")

	chart.refresh_ids()
	var next := chart.add_command("JLINE", 6.0)
	check(next.id == "C3", "refresh_ids 记住最大编号")

	chart.duration_beats()
	var long_command := chart.add_command("SIZE_NOT_A_REAL_COMMAND", 100.0)
	check(is_equal_approx(long_command.duration, 1.0), "未知指令退回 1 拍默认时长")


func _test_note_mods() -> void:
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	check(note.visual_alpha() == 1.0, "默认不透明")
	check(note.speed_scale() == 1.0, "默认速度 1")
	check(note.spawn_radius() == 0.0, "默认从圆心出生")
	check(not note.is_touch_slide(), "默认不是触摸滑条")

	note.alpha = 2.0
	check(note.visual_alpha() == 1.0, "不透明度夹到 1")
	note.alpha = -1.0
	check(note.visual_alpha() == 0.0, "不透明度夹到 0")
	note.hs = 0.01
	check(note.speed_scale() == 0.2, "速度倍率有下限")
	note.hs = 99.0
	check(note.speed_scale() == 4.0, "速度倍率有上限")

	note.spawn = 0.0
	note.bounce = 1.0
	note.bounce_dir = 0
	check(is_equal_approx(note.bounce_radius(0.0), 1.0), "弹跳起点在环上")
	check(is_equal_approx(note.bounce_radius(0.5), 0.0), "内凹弹跳中途最靠内")
	check(is_equal_approx(note.bounce_radius(1.0), 1.0), "弹跳终点回环上")
	note.bounce_dir = 1
	check(is_equal_approx(note.bounce_radius(0.5), 2.0), "外凸弹跳中途越过环")
	note.bounce = 0.0
	check(is_equal_approx(note.bounce_radius(0.5), 1.0), "不弹时半径不变")


func _test_touch_positions() -> void:
	check(Note.touch_sensor("A1") == 0, "A1 是 0 号传感器")
	check(Note.touch_sensor("A8") == 7, "A8 是 7 号传感器")
	check(Note.touch_sensor("B1") == 8, "B1 是 8 号传感器")
	check(Note.touch_sensor("B8") == 15, "B8 是 15 号传感器")
	check(Note.touch_sensor("C") == 16, "C 是 16 号传感器")
	check(Note.touch_sensor("C1") == 16, "C1 也是 16 号")
	check(Note.touch_sensor("D1") == 17, "D1 是 17 号")
	check(Note.touch_sensor("E8") == 32, "E8 是 32 号")
	check(Note.touch_sensor("e3") == 27, "小写字母也认")
	check(Note.touch_sensor("F1") == -1, "F 区不存在")
	check(Note.touch_sensor("A9") == -1, "8 路以外的编号非法")
	check(Note.touch_sensor("A") == -1, "A 必须带编号")
	check(Note.touch_sensor("") == -1, "空写法非法")
	check(Note.is_touch_position("b7"), "合法写法")
	check(not Note.is_touch_position("Q1"), "非法区不认")

	check(Note.mirror_touch("A1") == "B1", "左右镜像 A→B")
	check(Note.mirror_touch("B8") == "A8", "左右镜像 B→A")
	check(Note.mirror_touch("D4") == "E4", "左下镜像到右下")
	check(Note.mirror_touch("E4") == "D4", "右下镜像到左下")
	check(Note.mirror_touch("C") == "C", "中区镜像不变")

	var slide := Note.new("path", 2.0, 90.0, 60.0)
	slide.touch_start = "A1"
	slide.touch_end = "E8"
	check(slide.is_touch_slide(), "写触摸区后识别为触摸滑条")
	check(slide.touch_head_sensor() == 0, "起点传感器")
	check(slide.touch_tail_sensor() == 32, "终点传感器")
	slide.mirror_lr()
	check(slide.touch_start == "B1", "镜像后起点换到 B")
	check(slide.touch_end == "D8", "镜像后终点换到 D")


func _test_note_mods_roundtrip() -> void:
	var note := Note.new("hold", 2.0, 45.0, 60.0)
	note.end_beat = 4.0
	note.alpha = 0.5
	note.hs = 1.5
	note.sv = 2.0
	note.head_speed = 1.2
	note.spawn = 0.25
	note.bounce = 0.4
	note.bounce_dir = 1
	note.touch_start = "A2"
	note.touch_end = "C"

	var restored := Note.from_dict(note.to_dict())
	check(is_equal_approx(restored.alpha, 0.5), "alpha 往返")
	check(is_equal_approx(restored.hs, 1.5), "hs 往返")
	check(is_equal_approx(restored.sv, 2.0), "sv 往返")
	check(is_equal_approx(restored.head_speed, 1.2), "head_speed 往返")
	check(is_equal_approx(restored.spawn, 0.25), "spawn 往返")
	check(is_equal_approx(restored.bounce, 0.4), "bounce 往返")
	check(restored.bounce_dir == 1, "bounce_dir 往返")
	check(restored.touch_start == "A2", "touch_start 往返")
	check(restored.touch_end == "C", "touch_end 往返")

	var plain := Note.new("tap", 0.0, 0.0, 60.0)
	check(plain.mods_to_dict().is_empty(), "默认修饰不写入")
	plain.apply_mods({"touch_start": "ZZ", "alpha": 3.0})
	check(plain.touch_start.is_empty(), "非法触摸写法被丢弃")
	check(is_equal_approx(plain.alpha, 1.0), "超范围 alpha 被夹回")


func _test_chart_roundtrip() -> void:
	var chart := Chart.new()
	chart.timing.points.clear()
	chart.timing.points.append(TimingPoint.new(0.0, 120.0, 4))
	var note := Note.new("tap", 1.0, 90.0, 60.0)
	note.id = 1
	chart.notes.append(note)
	note.alpha = 0.4
	note.hs = 2.0
	note.spawn = 0.3
	note.bounce = 0.5
	note.bounce_dir = 1
	note.touch_start = "A1"
	note.touch_end = "E8"

	var text := chart.add_command("TEXT", 2.0)
	text.params["content"] = "HELLO"
	chart.add_command("JLINE", 3.0)
	var flash := chart.add_command("FLASH", 1.0)
	flash.params["strength"] = 0.6

	var json := ChartIO.to_json(chart)
	var loaded := ChartIO.from_json(json)
	check(loaded != null, "带指令的谱面能读回")
	if loaded == null:
		return
	check(loaded.commands.size() == 3, "三条指令都回来了")
	var texts := loaded.commands_in("text")
	check(texts.size() == 1 and String(texts[0].params.get("content", "")) == "HELLO", "文本内容往返")
	var flashes := loaded.commands_in("filter")
	check(flashes.size() == 1 and is_equal_approx(flashes[0].number("strength"), 0.6), "滤镜参数往返")
	check(loaded.commands[0].id.begins_with("C"), "指令保留编号")
	check(is_equal_approx(loaded.duration_beats(), 4.0), "时长按指令计入")

	var restored_note := loaded.notes[0]
	check(is_equal_approx(restored_note.alpha, 0.4), "谱面里的 alpha 往返")
	check(is_equal_approx(restored_note.hs, 2.0), "谱面里的 hs 往返")
	check(is_equal_approx(restored_note.spawn, 0.3), "谱面里的 spawn 往返")
	check(is_equal_approx(restored_note.bounce, 0.5), "谱面里的 bounce 往返")
	check(restored_note.bounce_dir == 1, "谱面里的 bounce_dir 往返")
	check(restored_note.touch_start == "A1", "谱面里的 touch_start 往返")
	check(restored_note.touch_end == "E8", "谱面里的 touch_end 往返")

	# 旧文件（没有 commands 键）照常打开。
	var legacy := ChartIO.chart_from_dict({
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"notes": ["[1]tap(1,90)"],
	})
	check(legacy != null and legacy.commands.is_empty(), "旧谱没有指令也能载入")

	var unknown := ChartIO.chart_from_dict({
		"format": "tamaki3-chart",
		"version": 1,
		"timing": {"points": [{"beat": 0.0, "bpm": 120.0, "beats_per_bar": 4}]},
		"notes": [],
		"commands": [{"name": "NOT_A_COMMAND", "beat": 0.0}],
	})
	check(unknown != null and unknown.commands.is_empty(), "未知指令整条丢弃")

	var mirrored := chart.mirrored_copy("lr")
	check(mirrored.commands.size() == 3, "镜像副本保留指令")
	check(mirrored.notes[0].touch_start == "B1", "镜像副本把触摸区换边")
