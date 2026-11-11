class_name ConvertOptimizer
extends RefCounted

## 舞萌转谱的鼠标层（std 只调用 snap_heads_to_path_tails）：
##   1. 同刻只留一颗：星星 > Hold > Tap > Bell，同类型看谁更顺。
##   2. 星星时间重叠：前一条能缩短就缩短，缩短后把后一颗头吸到前一条尾；
##      缩不了就把后一条只留星头降 Tap。
##   3. 星星超速：压短轨迹（尾巴可能不在原按钮），保留星星本体。
##   4. 严格 A-B-A-B 交互段（≥5 颗、均速超上限）整段锁到一对 45° 位置；
##      ≤45°（舞萌邻键）的快速 Tap 交替（≥3 颗）整段收到第一颗角度，形成叠键；
##      其余大于 45° 且快过鼠标上限的折返逐颗压成 45°。
##   5. 星星期间只留落在星轨上的 Tap/Hold/Bell。
##   6. Hold 尾巴撞到下一颗按键时缩短，不足半拍降 Tap。
##   7. Bell 撞上 100ms 内的 Tap/Hold 时吸到同一角度（单光标不可能同时站两处）。
##   8. 32 分扫键段（≥3 颗、间隔 ≤35ms、角度真的在扫）按键按不过来，整段转 Bell 用鼠标扫。

const RING_RADIUS := 330.0
## 鼠标跟轨迹的速度上限（px/s，按 330px 半径折算）。
const MAX_TRACE_SPEED := 3600.0
## 连打位移的速度上限：超过这个速度的 >45° 折返才压成 45°。
const MAX_HEAD_SPEED := 2200.0
## 严格交替段至少这么多颗才整段锁定。
const MIN_RUN_NOTES := 5
## 锁定后一对位置之间固定 45°。
const RUN_LOCK_STEP := 45.0
## 缩短后至少还要有这么多滑动时间，否则不如降级。
const MIN_MOVE_MS := 120.0
## 压短后至少保留这么多轨迹，否则读不出“要滑”。
const MIN_PATH_LENGTH_R := 0.15
## 星星期间其他音符离星轨多近才算“顺手能碰到”。
const ON_TRACK_R := 0.30
## 滑条底线：比这更短 / 头尾弦长更小的 Path 读不出“要滑”，降级。
const MIN_SLIDE_MS := 160.0
const MIN_SLIDE_CHORD_R := 0.6
## 快速扫键：间隔 ≤45ms（≈22 颗/秒）、至少 3 颗、角度真的在扫 ≥45°，按键按不过来。
const SWEEP_GAP_MS := 45.0
const SWEEP_MIN_NOTES := 3
const SWEEP_MIN_SPAN := 45.0
## 每颗至少移动这么多角度才算“在扫”；同角度连爆会在这一步断开。
const SWEEP_MIN_STEP := 10.0


static func optimize_maimai(chart: Chart, counts: Dictionary) -> Dictionary:
	var stats := {
		"dropped": 0, "chords": 0, "snapped": 0, "shortened": 0,
		"degraded": 0, "off_track": 0, "relaxed": 0, "locked": 0, "stacked": 0, "rebuilt": 0, "bells_moved": 0, "swept": 0,
	}
	_resolve_chords(chart, counts, stats)
	_fit_path_overlaps(chart, counts, stats)
	_fit_all_paths(chart, counts, stats)
	_refresh_path_tails(chart)
	var locked := _compress_jumps(chart, stats)
	enforce_slide_floor(chart, counts, stats)
	_drop_off_track(chart, counts, stats)
	_clamp_holds(chart, counts, stats)
	# 压角/Hold 降级会新造出 45° 邻键来回；补一遍只叠不改别的，别留下“看着能叠却没叠”。
	_lock_interaction_runs(chart, stats, true, locked)
	_snap_bells_to_press_notes(chart, stats)
	# 放在 Bell 吸附之后：转出来的扫键串不该再被吸回旁边的 Tap/Hold，否则整条路线散掉。
	_sweep_runs_to_bells(chart, stats)
	chart.refresh_ids()
	return stats


# ---------------------------------------------------------------- 同刻去重

static func _resolve_chords(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	var groups: Array[Array] = []
	var i := 0
	while i < ordered.size():
		var group: Array[Note] = [ordered[i]]
		var group_ms := chart.timing.beat_to_chart_ms(ordered[i].beat)
		var j := i + 1
		while j < ordered.size() and absf(chart.timing.beat_to_chart_ms(ordered[j].beat) - group_ms) < 1.0:
			group.append(ordered[j])
			j += 1
		groups.append(group)
		i = j
	var previous_end := Vector2.INF
	for g in groups.size():
		var group: Array = groups[g]
		var best_priority := -1
		for note in group:
			best_priority = maxi(best_priority, _priority(note))
		var next_points: Array[Vector2] = []
		if g + 1 < groups.size():
			for candidate in groups[g + 1]:
				next_points.append(_note_point(candidate))
		var keeper: Note = null
		var best_score := -INF
		for note in group:
			if _priority(note) != best_priority:
				continue
			var score := 0.0
			if note.type == "path":
				score = -_distance_to_any(_note_end_point(note), next_points)
				if next_points.is_empty():
					score = -_distance(previous_end, _note_point(note))
			else:
				score = -_distance(previous_end, _note_point(note))
			if keeper == null or score > best_score:
				keeper = note
				best_score = score
		if keeper == null:
			continue
		for note in group:
			if note != keeper:
				_remove_note(chart, counts, note, stats)
				stats["chords"] = int(stats["chords"]) + 1
		previous_end = _note_end_point(keeper)


static func _priority(note: Note) -> int:
	match note.type:
		"path": return 3
		"hold": return 2
		"tap": return 1
		_: return 0


static func _note_point(note: Note) -> Vector2:
	if note.type == "bell":
		return _unit(note.center_u * 360.0) * clampf(note.bell_radius, 0.0, 1.0)
	if note.type == "path" and not note.trace_pts.is_empty():
		return Vector2(float(note.trace_pts[0].get("x", 0.0)), float(note.trace_pts[0].get("y", 0.0)))
	return _unit(note.angle)


static func _note_end_point(note: Note) -> Vector2:
	if note.type == "path":
		if not note.trace_pts.is_empty():
			return Vector2(float(note.trace_pts[-1].get("x", 0.0)), float(note.trace_pts[-1].get("y", 0.0)))
		return _unit(note.tail_angle)
	return _note_point(note)


static func _unit(angle_deg: float) -> Vector2:
	var angle := deg_to_rad(angle_deg)
	return Vector2(cos(angle), sin(angle))


static func _distance(a: Vector2, b: Vector2) -> float:
	if not a.is_finite() or not b.is_finite():
		return 0.0
	return a.distance_to(b)


static func _distance_to_any(point: Vector2, others: Array[Vector2]) -> float:
	var best := INF
	for other in others:
		best = minf(best, _distance(point, other))
	return 0.0 if best == INF else best


# ---------------------------------------------------------------- 星星重叠

static func _fit_path_overlaps(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	var paths: Array[Note] = []
	for note in chart.sorted_notes():
		if note.type == "path" and note.path_part == 0:
			paths.append(note)
	var active: Note = null
	for path in paths:
		if not chart.notes.has(path):
			continue
		if active != null and chart.notes.has(active):
			var gap_ms := chart.timing.beat_to_chart_ms(path.beat) - chart.timing.beat_to_chart_ms(active.end_beat)
			if gap_ms < -1.0:
				# 时间重叠：前一条缩到后一条头上。
				if _shorten_path(active, path.beat, chart):
					stats["shortened"] = int(stats["shortened"]) + 1
					_snap_to_tail(path, active, stats)
				else:
					# 缩不动：后一条只留星头（降 Tap），active 继续跑完。
					_degrade_path(path, counts, stats, true)
					continue
			elif absf(gap_ms) <= 1.0:
				_snap_to_tail(path, active, stats)
		active = path


## 每一条星星都按鼠标速度上限压短；压到读不出就降级。
static func _fit_all_paths(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	for note in chart.notes.duplicate():
		if note.type != "path":
			continue
		if not _fit_speed(note, chart):
			_degrade_path(note, counts, stats, true)


static func _snap_to_tail(note: Note, path: Note, stats: Dictionary) -> void:
	var delta := JudgeMath.angle_delta(note.angle, path.tail_angle)
	if absf(delta) < 0.01:
		return
	_rotate_note(note, delta)
	stats["snapped"] = int(stats["snapped"]) + 1


## 把星星缩到 new_end_beat。时间压缩后仍超速就压短轨迹。
static func _shorten_path(note: Note, new_end_beat: float, chart: Chart) -> bool:
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, note.duration() - 0.001))
	var new_duration := new_end_beat - note.beat
	if new_duration <= wait + 0.001:
		return false
	var move_ms := chart.timing.beat_to_chart_ms(new_end_beat) - chart.timing.beat_to_chart_ms(note.beat + wait)
	if move_ms < MIN_MOVE_MS:
		return false
	var old_duration := note.duration()
	note.end_beat = new_end_beat
	var old_move := maxf(0.001, old_duration - wait)
	var new_move := maxf(0.001, new_duration - wait)
	for point in note.trace_pts:
		var db := float(point.get("db", 0.0))
		if db <= wait:
			continue
		point["db"] = wait + (db - wait) * new_move / old_move
	return _fit_speed(note, chart)


## 超速时按速度上限截断轨迹；截完重新按弧长分配时间（整体变慢）。
static func _fit_speed(note: Note, chart: Chart) -> bool:
	if note.trace_pts.size() < 2:
		return false
	var move_ms := chart.timing.beat_to_chart_ms(note.end_beat) - chart.timing.beat_to_chart_ms(note.beat + note.wait_beat)
	if move_ms <= 1.0:
		return false
	var total := 0.0
	var cutoff := -1.0
	var previous := Vector2(float(note.trace_pts[0].get("x", 0.0)), float(note.trace_pts[0].get("y", 0.0)))
	var previous_db := float(note.trace_pts[0].get("db", 0.0))
	for i in range(1, note.trace_pts.size()):
		var point: Dictionary = note.trace_pts[i]
		var current := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
		var db := float(point.get("db", 0.0))
		var segment := previous.distance_to(current)
		var dt := chart.timing.beat_to_chart_ms(note.beat + db) - chart.timing.beat_to_chart_ms(note.beat + previous_db)
		if dt > 0.001 and segment * RING_RADIUS / dt * 1000.0 > MAX_TRACE_SPEED:
			# 这一段里最多还能滑多远，超出部分截掉。
			var allowed := MAX_TRACE_SPEED * dt / 1000.0 / RING_RADIUS
			cutoff = total + minf(segment, allowed)
			break
		total += segment
		previous = current
		previous_db = db
	if cutoff >= 0.0:
		note.trace_pts = _truncate_trace(note.trace_pts, cutoff)
	if note.trace_pts.size() < 2:
		return false
	var length := _trace_length(note.trace_pts)
	if length < MIN_PATH_LENGTH_R:
		return false
	_retime_trace(note, chart)
	return true


static func _truncate_trace(points: Array[Dictionary], limit: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var total := 0.0
	result.append(points[0].duplicate())
	for i in range(1, points.size()):
		var a := Vector2(float(points[i - 1].get("x", 0.0)), float(points[i - 1].get("y", 0.0)))
		var b := Vector2(float(points[i].get("x", 0.0)), float(points[i].get("y", 0.0)))
		var segment := a.distance_to(b)
		if total + segment >= limit:
			var q := 0.0 if segment <= 0.0001 else (limit - total) / segment
			var cut := a.lerp(b, q)
			result.append({"x": cut.x, "y": cut.y, "db": float(points[i - 1].get("db", 0.0))})
			break
		total += segment
		result.append(points[i].duplicate())
	return result


## 按“真实时间”分配轨迹：BPM 中途变化时也保持恒定像素速度。
static func _retime_trace(note: Note, chart: Chart) -> void:
	var wait := maxf(0.0, note.wait_beat)
	var start_ms := chart.timing.beat_to_chart_ms(note.beat + wait)
	var end_ms := chart.timing.beat_to_chart_ms(note.end_beat)
	var move_ms := maxf(0.001, end_ms - start_ms)
	var distances: Array[float] = [0.0]
	var total := 0.0
	for i in range(1, note.trace_pts.size()):
		var a := Vector2(float(note.trace_pts[i - 1].get("x", 0.0)), float(note.trace_pts[i - 1].get("y", 0.0)))
		var b := Vector2(float(note.trace_pts[i].get("x", 0.0)), float(note.trace_pts[i].get("y", 0.0)))
		total += a.distance_to(b)
		distances.append(total)
	total = maxf(0.0001, total)
	note.trace_pts[0]["db"] = 0.0
	for i in range(1, note.trace_pts.size()):
		var target_ms := start_ms + move_ms * distances[i] / total
		var beat := chart.timing.audio_ms_to_beat(target_ms)
		note.trace_pts[i]["db"] = clampf(beat - note.beat, 0.0, note.duration())


static func _trace_length(points: Array[Dictionary]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += Vector2(float(points[i - 1].get("x", 0.0)), float(points[i - 1].get("y", 0.0))).distance_to(
			Vector2(float(points[i].get("x", 0.0)), float(points[i].get("y", 0.0)))
		)
	return total


static func _refresh_path_tails(chart: Chart) -> void:
	for note in chart.notes:
		if note.type != "path" or note.trace_pts.is_empty():
			continue
		var last: Dictionary = note.trace_pts[-1]
		note.tail_angle = fposmod(rad_to_deg(atan2(float(last.get("y", 0.0)), float(last.get("x", 0.0)))), 360.0)


# ---------------------------------------------------------------- 大位移交互

static func _compress_jumps(chart: Chart, stats: Dictionary) -> Dictionary:
	var locked := _lock_interaction_runs(chart, stats)
	var tail_paths := {}
	for path in chart.notes:
		if path.type == "path":
			tail_paths[_beat_key(chart, path.end_beat)] = path
	var previous: Note = null
	for note in chart.sorted_notes():
		if note.type == "bell":
			continue
		var key := _beat_key(chart, note.beat)
		# 同拍落在某条星尾上的音符：始终吸住当前尾点（星星转过后也要重吸）。
		if tail_paths.has(key) and tail_paths[key] != note:
			var tail_path: Note = tail_paths[key]
			var snap_delta := JudgeMath.angle_delta(note.angle, tail_path.tail_angle)
			if absf(snap_delta) > 0.01:
				_rotate_note(note, snap_delta)
			previous = note
			continue
		# 交互段已经整段锁好，不再逐颗旋转，但后续音符仍从锁定后的位置继续算。
		if locked.has(note.id):
			previous = note
			continue
		if previous != null:
			var previous_end := previous.tail_angle if previous.type == "path" else previous.angle
			var previous_beat := previous.end_beat if previous.type in ["path", "hold"] else previous.beat
			var delta := JudgeMath.angle_delta(previous_end, note.angle)
			var gap_ms := chart.timing.beat_to_chart_ms(note.beat) - chart.timing.beat_to_chart_ms(previous_beat)
			var chord := 2.0 * sin(deg_to_rad(absf(delta)) * 0.5) * RING_RADIUS
			var too_fast := gap_ms > 0.1 and chord / gap_ms * 1000.0 > MAX_HEAD_SPEED
			if absf(delta) > 45.0 and too_fast:
				_rotate_note(note, signf(delta) * 45.0 - delta)
				stats["relaxed"] = int(stats["relaxed"]) + 1
		previous = note
	return locked


## 严格 A-B-A-B 的两位置交互（Tap/Hold 头，Path 打断，Bell 忽略）：
## 段够长且平均速度快过鼠标上限时，第一颗不动，第二颗朝原转向收到 45°，
## 整段都锁到这两个位置，避免鼠标每次跨 90°/180°。
## 邻键（≤45°）的快速 Tap 交替整段收到第一颗的角度，形成「叠键」，
## 连 228px 的抖动都不需要。
## 只收 Tap；Hold 头保持原位置，符合「tap 优化」的范围。
static func _lock_interaction_runs(chart: Chart, stats: Dictionary, stack_only: bool = false, skip: Dictionary = {}) -> Dictionary:
	var locked := {}
	var ordered := chart.sorted_notes()
	var i := 0
	while i < ordered.size():
		var first := ordered[i]
		if first.type != "tap" and first.type != "hold":
			i += 1
			continue
		if skip.has(first.id):
			i += 1
			continue
		var j := i + 1
		while j < ordered.size() and ordered[j].type == "bell":
			j += 1
		if j >= ordered.size() or (ordered[j].type != "tap" and ordered[j].type != "hold"):
			i = maxi(i + 1, j)
			continue
		if skip.has(ordered[j].id):
			i = j
			continue
		var a_angle := first.angle
		var b_angle := ordered[j].angle
		var delta := absf(JudgeMath.angle_delta(a_angle, b_angle))
		if delta <= 0.5:
			i = j
			continue
		# 邻键（≤45°）的 Tap-Tap 直接收叠键；Tap/Hold 混合段保持原位置。
		var stack := delta <= 45.0 and first.type == "tap" and ordered[j].type == "tap"
		if delta <= 45.0 and not stack:
			i = j
			continue
		if stack_only and not stack:
			i = j
			continue
		var run: Array[Note] = [first, ordered[j]]
		var k := j + 1
		while k < ordered.size():
			var next := ordered[k]
			if next.type == "bell":
				k += 1
				continue
			if next.type != "tap" and next.type != "hold":
				break
			if skip.has(next.id):
				break
			if stack:
				# 叠键只收 Tap，且整段只要落在首颗 ±45°（舞萌邻键）内就算来回；
				# 不再要求严格 A-B-A-B，轻微漂移、三颗 A-B-A 都能收。
				if next.type != "tap" or absf(JudgeMath.angle_delta(next.angle, a_angle)) > 45.0:
					break
			else:
				var expect := a_angle if run.size() % 2 == 0 else b_angle
				if absf(JudgeMath.angle_delta(next.angle, expect)) > 1.0:
					break
			run.append(next)
			k += 1
		var min_run := 3 if stack else MIN_RUN_NOTES
		var did_lock := false
		var eligible := run.size() >= min_run
		if eligible and stack:
			# 只有真正“来回”的段才叠：单向扫台阶（0→45→90）叠完会给下一颗留下大跳。
			var deviated := false
			var returned := false
			for note in run:
				if absf(JudgeMath.angle_delta(note.angle, a_angle)) > 10.0:
					deviated = true
				elif deviated:
					returned = true
			eligible = deviated and returned
		if eligible:
			var first_ms := chart.timing.beat_to_chart_ms(run[0].beat)
			var last_ms := chart.timing.beat_to_chart_ms(run[-1].beat)
			var avg_gap := (last_ms - first_ms) / float(run.size() - 1)
			var span := 0.0
			for note in run:
				span = maxf(span, absf(JudgeMath.angle_delta(note.angle, a_angle)))
			var chord := 2.0 * sin(deg_to_rad(span) * 0.5) * RING_RADIUS
			var speed := chord / maxf(0.001, avg_gap) * 1000.0
			if avg_gap > 0.1 and speed > MAX_HEAD_SPEED:
				did_lock = true
				if stack:
					for note in run:
						_rotate_note(note, JudgeMath.angle_delta(note.angle, a_angle))
						locked[note.id] = true
					stats["stacked"] = int(stats.get("stacked", 0)) + 1
				else:
					# 180° 没有原转向：angle_delta 固定给 -180，也就是顺时针 45°。
					var turn := JudgeMath.angle_delta(a_angle, b_angle)
					var direction := 1.0 if turn > 0.0 else -1.0
					var lock_b := fposmod(a_angle + direction * RUN_LOCK_STEP, 360.0)
					for index in run.size():
						var target := a_angle if index % 2 == 0 else lock_b
						_rotate_note(run[index], JudgeMath.angle_delta(run[index].angle, target))
						locked[run[index].id] = true
					stats["locked"] = int(stats.get("locked", 0)) + 1
		# 段失败时只退到断点前一颗：断点处往往才是真正可叠的子段开头。
		i = maxi(k if did_lock else k - 1, i + 1)
	return locked


## Bell 是触摸装饰，但 PC 只有一个光标：和 100ms 内的 Tap/Hold 撞车时，
## 把它吸到那颗按键的角度上，让一个光标同时完成“贴住 Bell + 按时按键”。
static func _snap_bells_to_press_notes(chart: Chart, stats: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	var press: Array[Note] = []
	for note in ordered:
		if note.type == "tap" or note.type == "hold":
			press.append(note)
	if press.is_empty():
		return
	var p := 0
	for bell in ordered:
		if bell.type != "bell":
			continue
		var bell_ms := chart.timing.beat_to_chart_ms(bell.beat)
		while p + 1 < press.size():
			var here := absf(chart.timing.beat_to_chart_ms(press[p].beat) - bell_ms)
			var next := absf(chart.timing.beat_to_chart_ms(press[p + 1].beat) - bell_ms)
			if next > here:
				break
			p += 1
		var best: Note = null
		var best_dt := INF
		for candidate in [press[p], press[p - 1] if p > 0 else null]:
			if candidate == null:
				continue
			var dt := absf(chart.timing.beat_to_chart_ms(candidate.beat) - bell_ms)
			if dt <= 100.0 and dt < best_dt:
				best_dt = dt
				best = candidate
		if best == null:
			continue
		var target := fposmod(best.angle, 360.0)
		if absf(JudgeMath.angle_delta(bell.center_u * 360.0, target)) <= 0.5:
			continue
		bell.center_u = fposmod(target / 360.0, 1.0)
		bell.angle = target
		stats["bells_moved"] = int(stats["bells_moved"]) + 1


## 快速扫键段：连续 Tap、间隔 ≤45ms、≥3 颗、角度跨度 ≥45°，一对一改成 Bell
## （时间和角度不变）。按键打不到 28 颗/秒，但鼠标沿这条路线扫过去能收。
static func _sweep_runs_to_bells(chart: Chart, stats: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	var i := 0
	while i < ordered.size():
		if ordered[i].type != "tap":
			i += 1
			continue
		var run: Array[Note] = [ordered[i]]
		var j := i + 1
		while j < ordered.size():
			var next := ordered[j]
			if next.type != "tap":
				break
			var prev := run[run.size() - 1]
			var gap := chart.timing.beat_to_chart_ms(next.beat) - chart.timing.beat_to_chart_ms(prev.beat)
			if gap > SWEEP_GAP_MS:
				break
			if absf(JudgeMath.angle_delta(next.angle, prev.angle)) < SWEEP_MIN_STEP:
				break
			run.append(next)
			j += 1
		var span := 0.0
		for note in run:
			span = maxf(span, absf(JudgeMath.angle_delta(note.angle, run[0].angle)))
		# 同角度的 32 分连打不转：那不是“扫”，转成 Bell 会变成停住就全收。
		if run.size() >= SWEEP_MIN_NOTES and span >= SWEEP_MIN_SPAN:
			for note in run:
				note.type = "bell"
				note.bell_radius = 1.0
				note.center_u = fposmod(note.angle, 360.0) / 360.0
				note.width = clampf(note.width, Note.BELL_MIN_WIDTH, Note.BELL_MAX_WIDTH)
			stats["swept"] = int(stats["swept"]) + run.size()
			i = j
		else:
			i += 1


static func _beat_key(chart: Chart, beat: float) -> int:
	return int(roundf(chart.timing.beat_to_chart_ms(beat)))


## 把音符整体旋转 delta；星星连轨迹一起转。
static func _rotate_note(note: Note, delta: float) -> void:
	if note.type == "bell":
		note.center_u = fposmod(note.center_u + delta / 360.0, 1.0)
		return
	note.angle = fposmod(note.angle + delta, 360.0)
	if note.type == "path":
		note.tail_angle = fposmod(note.tail_angle + delta, 360.0)
		var rotation := deg_to_rad(delta)
		for point in note.trace_pts:
			var p := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))).rotated(rotation)
			point["x"] = p.x
			point["y"] = p.y
		if note.path_head_local.is_finite():
			note.path_head_local = note.path_head_local.rotated(rotation)


# ---------------------------------------------------------------- 星星期间的音符

static func _drop_off_track(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	var paths: Array[Note] = []
	for note in chart.notes:
		if note.type == "path":
			paths.append(note)
	if paths.is_empty():
		return
	for note in chart.notes.duplicate():
		if note.type not in ["tap", "hold", "bell"]:
			continue
		var on_track := false
		for path in paths:
			if not chart.notes.has(path):
				continue
			if note.beat <= path.beat + 0.0005 or note.beat > path.end_beat + 0.0005:
				continue
			var local := path.trace_local_at(note.beat - path.beat)
			if local.distance_to(_note_point(note)) <= ON_TRACK_R:
				on_track = true
				break
		if on_track:
			continue
		var covered := false
		for path in paths:
			if chart.notes.has(path) and note.beat > path.beat + 0.0005 and note.beat <= path.end_beat + 0.0005:
				covered = true
				break
		if covered:
			_remove_note(chart, counts, note, stats)
			stats["off_track"] = int(stats["off_track"]) + 1


# ---------------------------------------------------------------- Hold / 底线

## Hold 尾巴撞到下一颗按键时缩短；不足半拍降 Tap。
static func _clamp_holds(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	for i in ordered.size():
		var note := ordered[i]
		if note.type != "hold" or not chart.notes.has(note):
			continue
		var next_beat := INF
		for j in range(i + 1, ordered.size()):
			if ordered[j].type == "bell":
				continue
			if ordered[j].beat > note.beat + 0.0001:
				next_beat = ordered[j].beat
				break
		if next_beat == INF:
			continue
		var limit := next_beat - 0.0625
		if limit < note.end_beat:
			note.end_beat = maxf(note.beat, limit)
		if note.end_beat - note.beat < 0.5:
			note.type = "tap"
			note.end_beat = note.beat
			counts["hold"] = maxi(0, int(counts.get("hold", 0)) - 1)
			counts["tap"] = int(counts.get("tap", 0)) + 1
			stats["degraded"] = int(stats["degraded"]) + 1


static func enforce_slide_floor(chart: Chart, counts: Dictionary, stats: Dictionary) -> void:
	for note in chart.sorted_notes():
		if note.type != "path" or not chart.notes.has(note):
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


static func _degrade_path(note: Note, counts: Dictionary, stats: Dictionary, force_tap: bool = false) -> void:
	var duration := note.duration()
	note.trace_pts.clear()
	note.wait_beat = 0.0
	note.tail_angle = note.angle
	note.tail_width = 52.0
	note.space = "ring"
	if duration >= 0.5 and not force_tap:
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


# ---------------------------------------------------------------- std 共用

## 一只鼠标：星的尾判和后一颗头同拍时，把后一颗的头旋到前一条的尾点上，
## 两条都保住，形成一笔画。std 和舞萌共用。
static func snap_heads_to_path_tails(chart: Chart) -> int:
	var paths: Array[Note] = []
	for note in chart.notes:
		if note.type == "path" and note.path_part == 0:
			paths.append(note)
	if paths.is_empty():
		return 0
	var snapped := 0
	for note in chart.sorted_notes():
		if note.type == "path" and note.path_part > 0:
			continue
		var best: Note = null
		var best_gap := 1.0
		for path in paths:
			if path == note or path.beat >= note.beat - 0.0001:
				continue
			var gap := absf(chart.timing.beat_to_chart_ms(path.end_beat) - chart.timing.beat_to_chart_ms(note.beat))
			if gap < best_gap:
				best_gap = gap
				best = path
		if best == null or best_gap >= 1.0:
			continue
		var delta := JudgeMath.angle_delta(note.angle, best.tail_angle)
		if absf(delta) < 0.01:
			continue
		_rotate_note(note, delta)
		snapped += 1
	return snapped


## 诊断：轨迹有没有超过鼠标速度上限（测试用，不参与转谱决策）。
static func _trace_bad(note: Note, chart: Chart) -> bool:
	if note.trace_pts.size() < 2:
		return true
	for i in range(1, note.trace_pts.size()):
		var a := Vector2(float(note.trace_pts[i - 1].get("x", 0.0)), float(note.trace_pts[i - 1].get("y", 0.0)))
		var b := Vector2(float(note.trace_pts[i].get("x", 0.0)), float(note.trace_pts[i].get("y", 0.0)))
		if a.length() > 1.05 or b.length() > 1.05:
			return true
		var dt := chart.timing.beat_to_chart_ms(note.beat + float(note.trace_pts[i].get("db", 0.0))) - chart.timing.beat_to_chart_ms(note.beat + float(note.trace_pts[i - 1].get("db", 0.0)))
		if dt > 0.001 and a.distance_to(b) * RING_RADIUS / dt * 1000.0 > MAX_TRACE_SPEED:
			return true
	return false
