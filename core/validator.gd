class_name Validator
extends RefCounted

const EPS := 0.001


static func validate(chart: Chart) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	_check_timing(chart, issues)
	_check_shapes(chart, issues)
	_check_shape_keys(chart, issues)
	_check_events(chart, issues)
	_check_view_states(chart, issues)
	_check_regions(chart, issues)
	_check_notes(chart, issues)
	_check_playability(chart, issues)
	return issues


static func errors(issues: Array) -> Array[Dictionary]:
	return issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "error")


static func warnings(issues: Array) -> Array[Dictionary]:
	return issues.filter(func(item: Dictionary) -> bool: return item.get("level", "") == "warning")


static func _add(issues: Array[Dictionary], level: String, message: String, target: String = "") -> void:
	issues.append({"level": level, "message": message, "target": target})


static func _check_timing(chart: Chart, issues: Array[Dictionary]) -> void:
	if chart.timing.points.is_empty():
		_add(issues, "error", "至少需要一个 BPM 点", "timing")
		return
	var first := chart.timing.points[0]
	if first.beat > 0.0001:
		_add(issues, "error", "第一个 BPM 点必须不晚于第 0 小节", "timing")
	for point in chart.timing.points:
		# 上限放宽到 4000：舞萌谱面常用 1000+ 的 BPM 段做演出（例如 ANU 的 2020 BPM）。
		if point.bpm < 20.0 or point.bpm > 4000.0:
			_add(issues, "error", "BPM %.1f 越界（20–4000）" % point.bpm, "timing")
		if point.beats_per_bar < 1 or point.beats_per_bar > 16:
			_add(issues, "error", "拍号分子 %d 越界（1–16）" % point.beats_per_bar, "timing")


static func _check_shapes(chart: Chart, issues: Array[Dictionary]) -> void:
	if chart.shapes.is_empty():
		_add(issues, "error", "至少需要一个边界形状", "shape")
		return
	if chart.get_default_shape() == null:
		_add(issues, "error", "默认边界形状不存在", "shape")
	for shape in chart.sorted_shapes():
		for message in shape.validate():
			_add(issues, "error", message, "shape:" + shape.id)


static func _check_shape_keys(chart: Chart, issues: Array[Dictionary]) -> void:
	var previous := -INF
	for key in chart.sorted_shape_keys():
		var beat := float(key.get("beat", 0.0))
		if beat < 0.0:
			_add(issues, "error", "形状关键帧不能在第 0 拍之前", "key")
		if beat <= previous + 0.0001:
			_add(issues, "error", "形状关键帧的拍必须递增", "key")
		previous = beat
		if chart.get_shape(String(key.get("shape_id", ""))) == null:
			_add(issues, "error", "形状关键帧引用了不存在的形状", "key")


static func _check_events(chart: Chart, issues: Array[Dictionary]) -> void:
	for event in chart.events:
		if event.id.is_empty():
			_add(issues, "error", "BoundaryEvent 缺少 id", "event")
		if event.end_beat <= event.start_beat + EPS:
			_add(issues, "error", "事件 %s 的结束拍必须晚于开始拍" % event.id, "event:" + event.id)
		if event.target_u0 < 0.0 or event.target_u1 > 1.0 or event.target_u1 <= event.target_u0 + 0.00001:
			_add(issues, "error", "事件 %s 的 target 区间非法" % event.id, "event:" + event.id)
		if chart.get_shape(event.from_shape) == null or chart.get_shape(event.to_shape) == null:
			_add(issues, "error", "事件 %s 引用了不存在的形状" % event.id, "event:" + event.id)
		if event.end_behavior != "restore" and event.end_behavior != "hold":
			_add(issues, "error", "事件 %s 的 endBehavior 必须是 restore/hold" % event.id, "event:" + event.id)
		if event.restore_duration < 0.0:
			_add(issues, "error", "事件 %s 的恢复时长不能为负" % event.id, "event:" + event.id)
		_check_event_morph(chart, event, issues)
	for i in chart.events.size():
		for j in range(i + 1, chart.events.size()):
			var a := chart.events[i]
			var b := chart.events[j]
			if _ranges_overlap(a.target_u0, a.target_u1, b.target_u0, b.target_u1) and _event_times_overlap(a, b):
				_add(issues, "error", "事件 %s 与 %s 的 target/时间重叠" % [a.id, b.id], "event:" + a.id)


static func _check_event_morph(chart: Chart, event: BoundaryEvent, issues: Array[Dictionary]) -> void:
	var end_time := event.end_beat
	if event.end_behavior == "restore":
		end_time += maxf(0.0, event.restore_duration)
	if end_time <= event.start_beat + 0.001:
		return
	for i in 9:
		var t := lerpf(event.start_beat, end_time, float(i) / 8.0)
		var points := BoundaryRuntime.eval_shape(chart, t, 96)
		if BoundaryShape.runs_self_intersects(points, chart.get_default_shape().closed):
			_add(issues, "error", "事件 %s 在 %s 拍附近造成环线自交" % [event.id, chart.timing.format_beat(t)], "event:" + event.id)
			return
		# 凹形与局部收放都允许；只拦自交。


static func _event_times_overlap(a: BoundaryEvent, b: BoundaryEvent) -> bool:
	var a_end := a.end_beat + (a.restore_duration if a.end_behavior == "restore" else 0.0)
	var b_end := b.end_beat + (b.restore_duration if b.end_behavior == "restore" else 0.0)
	return not (a_end <= b.start_beat + EPS or b_end <= a.start_beat + EPS)


static func _ranges_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return not (a1 <= b0 + 0.00001 or b1 <= a0 + 0.00001)


static func _check_view_states(chart: Chart, issues: Array[Dictionary]) -> void:
	for state in chart.view_states:
		if state.zoom < 0.75 or state.zoom > 1.4:
			_add(issues, "warning", "视角 %.2f 超出 0.75–1.4 建议范围" % state.zoom, "view")
		if state.ellipse < 0.5 or state.ellipse > 1.5:
			_add(issues, "warning", "椭圆系数 %.2f 偏离较大" % state.ellipse, "view")


static func _check_regions(chart: Chart, issues: Array[Dictionary]) -> void:
	for region in chart.regions:
		if region.kind != "limit":
			_add(issues, "error", "区域 %d 的类型非法（只支持 limit）" % region.id, "region:%d" % region.id)
		if region.end_beat <= region.start_beat + EPS:
			_add(issues, "error", "红区 %d 的结束拍必须晚于开始拍" % region.id, "region:%d" % region.id)
		if region.duration() > 4.0 + EPS:
			_add(issues, "error", "红区 %d 超过 4 拍上限" % region.id, "region:%d" % region.id)
		if region.width < 0.0 or region.width > 360.0:
			_add(issues, "error", "红区 %d 的宽度越界" % region.id, "region:%d" % region.id)
		if not region.shape.is_empty() and chart.get_shape(region.shape) == null:
			_add(issues, "error", "红区 %d 引用了不存在的形状" % region.id, "region:%d" % region.id)


static func _check_notes(chart: Chart, issues: Array[Dictionary]) -> void:
	var seen_ids := {}
	for note in chart.notes:
		if seen_ids.has(note.id):
			_add(issues, "error", "音符 id %d 重复" % note.id, "note:%d" % note.id)
		seen_ids[note.id] = true
		if not Note.TYPES.has(note.type):
			_add(issues, "error", "音符 %d 的类型 %s 未知" % [note.id, note.type], "note:%d" % note.id)
		if note.width < 0.0 or note.width > 360.0:
			_add(issues, "error", "音符 %d 的宽度越界" % note.id, "note:%d" % note.id)
		match note.type:
			"hold":
				if note.end_beat <= note.beat + EPS:
					_add(issues, "error", "Hold %d 的结束拍必须晚于头部" % note.id, "note:%d" % note.id)
			"path":
				if note.end_beat <= note.beat + EPS:
					_add(issues, "error", "Path %d 的尾部时间必须晚于头部" % note.id, "note:%d" % note.id)
				if note.tolerance < 0.0 or note.tolerance > 1.0:
					_add(issues, "error", "Path %d 的容差越界" % note.id, "note:%d" % note.id)
				if note.samples_per_beat <= 0.0:
					_add(issues, "error", "Path %d 的采样密度必须为正" % note.id, "note:%d" % note.id)
				if not note.trace_pts.is_empty() and note.trace_pts.size() < 2:
					_add(issues, "error", "Path %d 的平面点不足 2 个" % note.id, "note:%d" % note.id)
				for point in note.trace_pts:
					var x := float(point.get("x", 0.0))
					var y := float(point.get("y", 0.0))
					if sqrt(x * x + y * y) > 1.05:
						_add(issues, "error", "Path %d 的点越出环内平面" % note.id, "note:%d" % note.id)
						break
			"bell":
				if note.radius <= 0.0:
					_add(issues, "error", "Bell %d 的半径必须为正" % note.id, "note:%d" % note.id)
				if note.center_u < 0.0 or note.center_u >= 1.0:
					_add(issues, "error", "Bell %d 的中心 u 越界" % note.id, "note:%d" % note.id)
			"anchor":
				# 双押配置：单颗 Anchor 不再成立，必须同拍反向成对。
				if _anchor_partner(chart, note) == null:
					_add(issues, "error", "Anchor %d 必须与同拍反向的另一颗配对" % note.id, "note:%d" % note.id)
		if note.space != "plane" or note.type == "path":
			var u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
			var shape := chart.get_default_shape()
			if shape != null:
				var sampled := shape.point_at(u)
				if sampled.get("gap", false):
					_add(issues, "error", "音符 %d 落在缺口段上" % note.id, "note:%d" % note.id)
	# 同拍最多一对（双押）；第三颗 Anchor 直接拒绝。
	var anchor_counts := {}
	for note in chart.notes:
		if note.type != "anchor":
			continue
		var key := "%.4f" % note.beat
		anchor_counts[key] = int(anchor_counts.get(key, 0)) + 1
	for key in anchor_counts:
		if int(anchor_counts[key]) > 2:
			_add(issues, "error", "同拍 Anchor 超过双押上限（%s 拍有 %d 颗，最多 2 颗）" % [key, int(anchor_counts[key])], "notes")


static func _anchor_partner(chart: Chart, note: Note) -> Note:
	return chart.anchor_partner(note)


static func _check_playability(chart: Chart, issues: Array[Dictionary]) -> void:
	# 按拍预分组，避免每个拍点都扫描全部音符（10k 音符时会退化成 O(n²)）。
	var groups: Dictionary = {}
	for note in chart.notes:
		if note.type in ["tap", "hold", "path"]:
			var key := snappedf(note.beat, 0.001)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(note)
		if note.type == "path":
			var tail_key := snappedf(note.end_beat, 0.001)
			if not groups.has(tail_key):
				groups[tail_key] = []
			groups[tail_key].append(note)
	for beat_key in groups.keys():
		var beat := float(beat_key)
		var lists := JudgeMath.intervals_for_notes(groups[beat_key], beat)
		if lists.is_empty():
			continue
		var common := JudgeMath.intersect_all(lists)
		if common.is_empty():
			_add(issues, "error", "第 %s 拍同刻目标没有公共角度" % chart.timing.format_beat(beat), "beat:%.3f" % beat)
			continue
		var safe := JudgeMath.subtract(common, JudgeMath.red_intervals(chart.regions, beat))
		if JudgeMath.total_length(safe) <= 0.001:
			_add(issues, "error", "第 %s 拍减去 Limit 区后没有安全落脚点" % chart.timing.format_beat(beat), "beat:%.3f" % beat)
