class_name ConvertOptimizer
extends RefCounted

## 导入后的两层优化：
##   1. 布局层：删除同一只鼠标打不了的同刻/近同刻音符，按 45° 车道
##      缩短连续大位移，整理 Hold / Path 冲突。
##   2. 轨迹层（仅舞萌）：把自交、急折、超速的 Path 换成 Sentakki 段库
##      里鼠标能跟上的轨迹；连一小段 45° 都放不下时才降级成 Hold/Tap。
##
## osu!std 的 Path 已经由 Sentakki 转换器生成，这里只跑布局层。

const RING_RADIUS := 330.0
const MAX_HEAD_SPEED := 3800.0
const MAX_TAIL_SPEED := 4200.0
const MAX_TRACE_SPEED := 3600.0
const MAX_TURN_DEG := 120.0
const MAX_TRACE_LENGTH_R := 12.0
const MIN_GAP_MS := 45.0
const PLAN_VELOCITY := 1.4
## 滑条底线：比这更短的 Path 来不及滑（240BPM 的 1/8 拍 = 125ms 会被降级，
## 120~180BPM 的常规滑条不受影响）。
const MIN_SLIDE_MS := 160.0
## 弦长底线：头尾离不到 0.6R 的滑条，玩家读起来和 Tap 没区别。
const MIN_SLIDE_CHORD_R := 0.6
## Bell 和同时段 Path 的最小设计距离（0.35R，试玩尺度约 150px）：
## 鼠标要同时接铃铛和跟进滑条时，两个目标叠在一起就没法打。
const BELL_PATH_CLEARANCE_R := 0.35
const BELL_PATH_TIME_PAD := 0.6


static func optimize_maimai(chart: Chart, counts: Dictionary) -> Dictionary:
	var stats := {"dropped": 0, "relaxed": 0, "rebuilt": 0, "degraded": 0, "bells_moved": 0}
	_drop_near_duplicates(chart, counts, stats)
	var degrade_ids := {}
	_cap_events(chart, counts, stats, degrade_ids, true)
	_rebuild_paths(chart, counts, stats, degrade_ids)
	enforce_slide_floor(chart, counts, stats)
	clamp_holds(chart, counts)
	space_bells_from_paths(chart, counts, stats)
	resolve_conflicts(chart, counts)
	return stats


## 太短 / 太小的滑条降级成 Hold 或 Tap：
## 尾判需要一个 250ms 的提前窗口，比整条滑条还长的 Path 既读不出来也打不准；
## 头尾弦长不到 0.6R 的滑条，玩家看不出“要滑”。
static func enforce_slide_floor(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	for note in chart.sorted_notes():
		if note.type != "path":
			continue
		var span_ms := chart.timing.beat_to_chart_ms(note.end_beat) - chart.timing.beat_to_chart_ms(note.beat)
		var chord := _slide_chord(note) * RING_RADIUS
		if span_ms >= MIN_SLIDE_MS and chord >= MIN_SLIDE_CHORD_R * RING_RADIUS:
			continue
		_degrade_path(note, counts, stats)


static func _slide_chord(note: Note) -> float:
	if note.trace_pts.size() < 2:
		return 0.0
	var head := Vector2(float(note.trace_pts[0].get("x", 0.0)), float(note.trace_pts[0].get("y", 0.0)))
	var tail := Vector2(float(note.trace_pts[-1].get("x", 0.0)), float(note.trace_pts[-1].get("y", 0.0)))
	return head.distance_to(tail)


## Bell 和同时段的 Path 叠在一起时，把 Bell 沿环挪开（挪不动就删掉）。
## 鼠标只有一个：滑条在跑的时候还要去接一个正好压在轨迹上的铃铛，是打不出来的。
static func space_bells_from_paths(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	if chart.get_default_shape() == null:
		return
	var paths: Array[Note] = []
	for note in chart.notes:
		if note.type == "path":
			paths.append(note)
	if paths.is_empty():
		return
	for bell in chart.notes.duplicate():
		if bell.type != "bell":
			continue
		if not _bell_conflicts(chart, bell.center_u, bell.beat, paths):
			continue
		var moved := false
		for step in range(1, 21):
			for direction in [1.0, -1.0]:
				var u := fposmod(bell.center_u + direction * float(step) * 0.01, 1.0)
				if _bell_conflicts(chart, u, bell.beat, paths):
					continue
				bell.center_u = u
				moved = true
				stats["bells_moved"] = int(stats["bells_moved"]) + 1
				break
			if moved:
				break
		if not moved:
			_remove_note(chart, counts, bell, stats)


static func _bell_conflicts(chart: Chart, u: float, beat: float, paths: Array[Note]) -> bool:
	# 边界事件会让环在 Bell 的那一刻变形，所以按那一刻的真实边界取点。
	var sampled: Dictionary = BoundaryRuntime.eval_point(chart, fposmod(u, 1.0), beat)
	if bool(sampled.get("gap", false)):
		return false
	var bell_point: Vector2 = sampled.get("point", Vector2.ZERO)
	if bell_point.length() <= 0.001:
		return false
	var limit := BELL_PATH_CLEARANCE_R * bell_point.length()
	var scaled := bell_point.normalized() * RING_RADIUS
	for path in paths:
		if beat < path.beat - BELL_PATH_TIME_PAD or beat > path.end_beat + BELL_PATH_TIME_PAD:
			continue
		var count := maxi(4, mini(16, path.trace_pts.size()))
		for i in count:
			var q := float(i) / float(count - 1)
			var point := _trace_point_at(path, q)
			if point.distance_to(scaled) < limit:
				return true
	return false


## 按比例在 trace_pts 上插值（用 db 当时间轴）。
static func _trace_point_at(note: Note, fraction: float) -> Vector2:
	var points := note.trace_pts
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return Vector2(float(points[0].get("x", 0.0)), float(points[0].get("y", 0.0))) * RING_RADIUS
	var first_db := float(points[0].get("db", 0.0))
	var last_db := float(points[-1].get("db", 0.0))
	var target := first_db + (last_db - first_db) * clampf(fraction, 0.0, 1.0)
	var previous := 0
	for i in range(1, points.size()):
		if float(points[i].get("db", 0.0)) >= target:
			previous = i - 1
			break
		previous = i
	var a := points[previous]
	var b := points[mini(previous + 1, points.size() - 1)]
	var a_db := float(a.get("db", 0.0))
	var b_db := float(b.get("db", 0.0))
	var q := 0.0 if absf(b_db - a_db) <= 0.000001 else clampf((target - a_db) / (b_db - a_db), 0.0, 1.0)
	var point := Vector2(
		lerpf(float(a.get("x", 0.0)), float(b.get("x", 0.0)), q),
		lerpf(float(a.get("y", 0.0)), float(b.get("y", 0.0)), q)
	)
	return point * RING_RADIUS


static func optimize_osu(chart: Chart, counts: Dictionary) -> Dictionary:
	var stats := {"dropped": 0, "relaxed": 0, "rebuilt": 0, "degraded": 0}
	_drop_near_duplicates(chart, counts, stats)
	_cap_events(chart, counts, stats, {}, false)
	resolve_conflicts(chart, counts)
	return stats


static func _drop_near_duplicates(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	var sequence := chart.sorted_notes()
	var i := 1
	while i < sequence.size():
		var previous: Note = sequence[i - 1]
		var current: Note = sequence[i]
		if not chart.notes.has(previous):
			sequence.remove_at(i - 1)
			continue
		if not chart.notes.has(current):
			sequence.remove_at(i)
			continue
		var gap := chart.timing.beat_to_chart_ms(current.beat) - chart.timing.beat_to_chart_ms(previous.beat)
		if gap >= MIN_GAP_MS:
			i += 1
			continue
		# 同一只鼠标：优先保留 Tap/Hold/Path，铃铛让路。
		if current.type == "bell" and previous.type != "bell":
			_remove_note(chart, counts, current, stats)
			sequence.remove_at(i)
			continue
		if previous.type == "bell" and current.type != "bell":
			_remove_note(chart, counts, previous, stats)
			sequence.remove_at(i - 1)
			continue
		_remove_note(chart, counts, current, stats)
		sequence.remove_at(i)


## 把 Tap / Hold / Path 头和 Path 尾统一排成事件，按实际像素速度压到 45° 车道。
## Path 头被移动时整条星星一起转；Path 尾被压缩时只改 tail_angle，
## 由 _rebuild_paths 重新生成轨迹。
static func _cap_events(chart: Chart, counts: Dictionary, stats: Dictionary, degrade_ids: Dictionary, include_tails: bool) -> void:
	var events: Array[Dictionary] = []
	for note in chart.notes:
		events.append({"beat": note.beat, "angle": note.angle, "note": note, "kind": "head"})
		if include_tails and note.type == "path" and note.end_beat > note.beat + 0.001:
			events.append({"beat": note.end_beat, "angle": note.tail_angle, "note": note, "kind": "tail"})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var beat_a := float(a["beat"])
		var beat_b := float(b["beat"])
		if absf(beat_a - beat_b) > 0.0001:
			return beat_a < beat_b
		return String(a["kind"]) == "head" and String(b["kind"]) == "tail"
	)
	var index := 1
	while index < events.size():
		var previous: Dictionary = events[index - 1]
		var current: Dictionary = events[index]
		var previous_note: Note = previous["note"]
		var current_note: Note = current["note"]
		if not chart.notes.has(previous_note):
			events.remove_at(index - 1)
			continue
		if not chart.notes.has(current_note):
			events.remove_at(index)
			continue
		var gap := chart.timing.beat_to_chart_ms(float(current["beat"])) - chart.timing.beat_to_chart_ms(float(previous["beat"]))
		if gap <= 0.001:
			index += 1
			continue
		var budget := MAX_TAIL_SPEED if String(current["kind"]) == "tail" else MAX_HEAD_SPEED
		var delta := JudgeMath.angle_delta(float(previous["angle"]), float(current["angle"]))
		var delta_abs := absf(delta)
		var chord := 2.0 * sin(deg_to_rad(delta_abs) * 0.5) * RING_RADIUS
		if chord / gap * 1000.0 <= budget:
			index += 1
			continue
		var max_chord := budget * gap / 1000.0
		var max_delta := rad_to_deg(2.0 * asin(clampf(max_chord / (2.0 * RING_RADIUS), 0.0, 1.0)))
		var steps := int(floor(max_delta / 45.0))
		if steps < 1:
			if String(current["kind"]) == "tail":
				degrade_ids[current_note.id] = true
				events.remove_at(index)
			else:
				_remove_note(chart, counts, current_note, stats)
				_remove_events_for(events, current_note)
			continue
		var target_delta := signf(delta) * minf(delta_abs, float(steps) * 45.0)
		var target := fposmod(float(previous["angle"]) + target_delta, 360.0)
		if String(current["kind"]) == "head":
			var shift := JudgeMath.angle_delta(float(current["angle"]), target)
			current_note.angle = target
			current["angle"] = target
			if current_note.type == "path":
				current_note.tail_angle = fposmod(current_note.tail_angle + shift, 360.0)
				for j in range(index + 1, events.size()):
					var tail_event: Dictionary = events[j]
					if tail_event["note"] == current_note and String(tail_event["kind"]) == "tail":
						tail_event["angle"] = current_note.tail_angle
						break
			stats["relaxed"] = int(stats["relaxed"]) + 1
		else:
			current_note.tail_angle = target
			current["angle"] = target
			stats["relaxed"] = int(stats["relaxed"]) + 1
		index += 1


static func _remove_events_for(events: Array[Dictionary], note: Note) -> void:
	var i := events.size() - 1
	while i >= 0:
		if events[i]["note"] == note:
			events.remove_at(i)
		i -= 1


static func _rebuild_paths(chart: Chart, counts: Dictionary, stats: Dictionary, degrade_ids: Dictionary) -> void:
	for note in chart.notes.duplicate():
		if note.type != "path":
			continue
		var bad := degrade_ids.has(note.id) or _trace_bad(note, chart)
		if not bad:
			continue
		var move_ms := chart.timing.beat_to_chart_ms(note.end_beat) - chart.timing.beat_to_chart_ms(note.beat + note.wait_beat)
		if move_ms <= 1.0:
			_degrade_path(note, counts, stats)
			continue
		var delta := JudgeMath.angle_delta(note.angle, note.tail_angle)
		var delta_abs := absf(delta)
		var original_steps := maxi(1, int(round(delta_abs / 45.0)))
		var max_chord := MAX_TAIL_SPEED * move_ms / 1000.0
		var max_delta := rad_to_deg(2.0 * asin(clampf(max_chord / (2.0 * RING_RADIUS), 0.0, 1.0)))
		var max_steps := mini(original_steps, int(floor(max_delta / 45.0)))
		var built := false
		if delta_abs >= 1.0 and max_steps >= 1:
			for steps in range(max_steps, 0, -1):
				var target := fposmod(note.angle + signf(delta) * float(steps) * 45.0, 360.0)
				var parts := SentakkiSlide.plan_between(note.angle, target, move_ms, PLAN_VELOCITY, true, true, 2)
				if parts.is_empty():
					continue
				note.tail_angle = target
				note.tail_width = 52.0
				note.trace_pts = SentakkiSlide.trace_from_parts(note.angle, parts, note.duration(), note.wait_beat)
				note.samples_per_beat = 4.0
				note.path_style = "arc"
				note.path_controls_set = false
				stats["rebuilt"] = int(stats["rebuilt"]) + 1
				built = true
				break
		if not built:
			_degrade_path(note, counts, stats)


static func _trace_bad(note: Note, chart: Chart) -> bool:
	var points: Array[Dictionary] = note.trace_pts
	if points.size() < 2:
		return true
	var head := Vector2(float(points[0].get("x", 0.0)), float(points[0].get("y", 0.0)))
	var expected_head := Vector2(cos(deg_to_rad(note.angle)), sin(deg_to_rad(note.angle)))
	if head.distance_to(expected_head) > 0.10:
		return true
	var last := Vector2(float(points[-1].get("x", 0.0)), float(points[-1].get("y", 0.0)))
	var expected_tail := Vector2(cos(deg_to_rad(note.tail_angle)), sin(deg_to_rad(note.tail_angle)))
	if last.distance_to(expected_tail) > 0.14:
		return true
	var total := 0.0
	for i in range(1, points.size()):
		var a := Vector2(float(points[i - 1].get("x", 0.0)), float(points[i - 1].get("y", 0.0)))
		var b := Vector2(float(points[i].get("x", 0.0)), float(points[i].get("y", 0.0)))
		var segment := a.distance_to(b)
		total += segment
		if a.length() > 1.05 or b.length() > 1.05:
			return true
		var dt := chart.timing.beat_to_chart_ms(note.beat + float(points[i].get("db", 0.0))) - chart.timing.beat_to_chart_ms(note.beat + float(points[i - 1].get("db", 0.0)))
		if dt > 0.001 and segment * RING_RADIUS / dt * 1000.0 > MAX_TRACE_SPEED:
			return true
		if i >= 2:
			var before := Vector2(float(points[i - 2].get("x", 0.0)), float(points[i - 2].get("y", 0.0)))
			var v1 := a - before
			var v2 := b - a
			if v1.length() > 0.0001 and v2.length() > 0.0001:
				if absf(rad_to_deg(v1.angle_to(v2))) > MAX_TURN_DEG:
					return true
		for j in range(i + 2, points.size()):
			var c := Vector2(float(points[j - 1].get("x", 0.0)), float(points[j - 1].get("y", 0.0)))
			var d := Vector2(float(points[j].get("x", 0.0)), float(points[j].get("y", 0.0)))
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
	if total > MAX_TRACE_LENGTH_R:
		return true
	return false


static func _degrade_path(note: Note, counts: Dictionary, stats: Dictionary) -> void:
	var duration := note.duration()
	note.trace_pts.clear()
	note.wait_beat = 0.0
	note.tail_angle = note.angle
	note.tail_width = 52.0
	note.space = "ring"
	if duration >= 0.5:
		note.type = "hold"
		note.end_beat = note.beat + duration
		note.hold = true
		note.hold_style = "straight"
		counts["path"] = maxi(0, int(counts.get("path", 0)) - 1)
		counts["hold"] = int(counts.get("hold", 0)) + 1
	else:
		note.type = "tap"
		note.end_beat = note.beat
		counts["path"] = maxi(0, int(counts.get("path", 0)) - 1)
		counts["tap"] = int(counts.get("tap", 0)) + 1
	stats["degraded"] = int(stats["degraded"]) + 1


static func _remove_note(chart: Chart, counts: Dictionary, note: Note, stats: Dictionary) -> void:
	if not chart.notes.has(note):
		return
	chart.notes.erase(note)
	counts["dropped"] = int(counts.get("dropped", 0)) + 1
	if counts.has(note.type):
		counts[note.type] = maxi(0, int(counts[note.type]) - 1)
	stats["dropped"] = int(stats["dropped"]) + 1


## 原 SimaiIO._clamp_holds：Hold 不能跨过下一颗音符；太短就降级 Tap。
static func clamp_holds(chart: Chart, counts: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	for i in ordered.size():
		var note := ordered[i]
		if note.type != "hold":
			continue
		var next_beat := INF
		for j in range(i + 1, ordered.size()):
			if ordered[j].beat > note.beat + 0.0001:
				next_beat = ordered[j].beat
				break
		var limit := next_beat - 0.0625
		if limit < note.end_beat:
			note.end_beat = limit
		if note.end_beat - note.beat < 0.5:
			note.type = "tap"
			note.end_beat = note.beat
			counts["hold"] = maxi(0, int(counts.get("hold", 0)) - 1)
			counts["tap"] = int(counts.get("tap", 0)) + 1


## 原 SimaiIO._resolve_conflicts：同拍目标角度不重合时只留最宽的一侧。
static func resolve_conflicts(chart: Chart, counts: Dictionary) -> void:
	var dummy := {"dropped": 0}
	for _pass in 6:
		var by_beat := {}
		for note in chart.notes:
			if note.type in ["tap", "hold", "path"]:
				var key := snappedf(note.beat, 0.001)
				if not by_beat.has(key):
					by_beat[key] = []
				by_beat[key].append({"note": note, "angle": note.angle, "width": note.width})
			if note.type == "path":
				var tail_key := snappedf(note.end_beat, 0.001)
				if not by_beat.has(tail_key):
					by_beat[tail_key] = []
				by_beat[tail_key].append({"note": note, "angle": note.tail_angle, "width": note.tail_width})
		var remove: Array[Note] = []
		for key in by_beat.keys():
			var events: Array = by_beat[key]
			if events.size() <= 1:
				continue
			var lists: Array = []
			for event in events:
				lists.append(JudgeMath.interval(float(event["angle"]), float(event["width"])))
			if not JudgeMath.intersect_all(lists).is_empty():
				continue
			events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["width"]) > float(b["width"]))
			var keeper: Note = events[0]["note"]
			for event in events:
				var note: Note = event["note"]
				if note != keeper and not remove.has(note):
					remove.append(note)
		if remove.is_empty():
			return
		for note in remove:
			_remove_note(chart, counts, note, dummy)
