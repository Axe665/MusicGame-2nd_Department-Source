class_name PathProgress
extends RefCounted

## Fine samples form a corridor; coarse gates preserve route order.
const SAMPLE_SPACING := 0.06
const GATE_SPACING := 0.85
const CONTACT_RADIUS := 0.25
const CORNER_RADIUS := 0.34
const REQUIRED_COVERAGE := 0.80
const END_PROGRESS := 0.90
const REJOIN_DISTANCE := 0.45
const REJOIN_GRACE_MS := 180.0

var points := PackedVector2Array()
var parameters := PackedFloat32Array()
var distances := PackedFloat32Array()
var mandatory := PackedByteArray()
var gates := PackedInt32Array()
var gate_radii := PackedFloat32Array()
var covered := PackedByteArray()
var length := 0.0
var contact_radius := CONTACT_RADIUS
var next_index := 0
var next_gate := 0
var required_index := 0
var fraction := 0.0
var coverage := 0.0
var progress := 0.0
var previous := Vector2.INF
var previous_ms := -INF
var _furthest := 0.0
var _covered_length := 0.0
var _away_since := -INF
var _screen_points := PackedVector2Array()
var _from := Vector2.INF
var _to := Vector2.INF
var _from_ms := 0.0
var _to_ms := 0.0
var _finish_min_t := INF
var _pending_tail_exit := -INF


static func for_note(note: Note) -> PathProgress:
	var tracker := PathProgress.new()
	var source := PackedVector2Array()
	var times := PackedFloat32Array()
	var total := maxf(0.000001, note.duration())
	if not note.trace_pts.is_empty():
		source.append(note.path_local_at(0.0))
		times.append(0.0)
		for point in note.trace_pts:
			source.append(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))))
			times.append(clampf(float(point.get("db", 0.0)) / total, 0.0, 1.0))
		source.append(note.path_local_at(total))
		times.append(1.0)
	else:
		for i in 129:
			var t := float(i) / 128.0
			source.append(note.path_local_at(total * t))
			times.append(t)
	tracker.configure(source, times)
	return tracker


func configure(source: PackedVector2Array, source_parameters := PackedFloat32Array()) -> void:
	points.clear()
	parameters.clear()
	distances.clear()
	mandatory.clear()
	gates.clear()
	gate_radii.clear()
	covered.clear()
	length = 0.0
	next_index = 0
	next_gate = 0
	required_index = 0
	fraction = 0.0
	coverage = 0.0
	progress = 0.0
	_furthest = 0.0
	_covered_length = 0.0
	reset_motion()
	if source.size() < 2:
		return
	var cumulative := PackedFloat32Array([0.0])
	for i in source.size():
		if not source[i].is_finite():
			return
		if i > 0:
			length += source[i - 1].distance_to(source[i])
			cumulative.append(length)
	if length <= 0.000001:
		return
	contact_radius = minf(CONTACT_RADIUS, length * 0.18)
	var corners: Array[float] = []
	for i in range(1, source.size() - 1):
		var a := source[i] - source[i - 1]
		var b := source[i + 1] - source[i]
		if a.length_squared() > 0.000001 and b.length_squared() > 0.000001 and a.normalized().dot(b.normalized()) < 0.8:
			corners.append(float(cumulative[i]))
	var gate_targets: Array[float] = [0.0, length]
	var gate_step := minf(GATE_SPACING, length / 3.0)
	var d := gate_step
	while d < length - 0.00001:
		var close_to_corner := false
		for corner in corners:
			if absf(corner - d) < minf(0.25, length * 0.08):
				close_to_corner = true
		if not close_to_corner:
			gate_targets.append(d)
		d += gate_step
	gate_targets.append_array(corners)
	gate_targets.sort()
	var targets: Array[float] = [0.0, length * REQUIRED_COVERAGE, length * END_PROGRESS, length]
	targets.append_array(gate_targets)
	var spacing := maxf(length / 1024.0, minf(SAMPLE_SPACING, length / 24.0))
	d = spacing
	while d < length:
		targets.append(d)
		d += spacing
	targets.sort()
	var edge := 0
	for target in targets:
		if not distances.is_empty() and target - float(distances[-1]) < 0.00001:
			continue
		while edge < source.size() - 2 and float(cumulative[edge + 1]) <= target:
			edge += 1
		var span := float(cumulative[edge + 1] - cumulative[edge])
		var t := 0.0 if span <= 0.000001 else clampf((target - float(cumulative[edge])) / span, 0.0, 1.0)
		points.append(source[edge].lerp(source[edge + 1], t))
		distances.append(target)
		parameters.append(lerpf(source_parameters[edge], source_parameters[edge + 1], t) if source_parameters.size() == source.size() else target / length)
		var is_gate := false
		for gate in gate_targets:
			if absf(gate - target) < 0.00001:
				is_gate = true
		mandatory.append(1 if is_gate else 0)
		if is_gate:
			gates.append(points.size() - 1)
			var radius := contact_radius
			for corner in corners:
				if absf(corner - target) < 0.00001:
					radius = maxf(radius, minf(CORNER_RADIUS, length * 0.24))
			gate_radii.append(radius)
		if target < length * REQUIRED_COVERAGE - 0.00001:
			required_index = points.size()
	covered.resize(maxi(0, points.size() - 1))
	covered.fill(0)


func confirm_head() -> void:
	if next_gate == 0 and points.size() >= 2:
		next_gate = 1
		next_index = 1


func reset_motion() -> void:
	previous = Vector2.INF
	previous_ms = -INF
	_finish_min_t = INF
	_pending_tail_exit = -INF
	_away_since = -INF


func body_ready() -> bool:
	return points.size() >= 2 and coverage + 0.00001 >= REQUIRED_COVERAGE and next_gate >= gates.size() - 1


func quality_tier() -> String:
	return "PERFECT" if coverage >= 0.90 - 0.00001 else ("GREAT" if coverage >= 0.85 - 0.00001 else "GOOD")


func feed(point: Vector2, ms: float, projected: PackedVector2Array, radius: float, start_ms: float, coordinate_scale := 0.0) -> void:
	_finish_min_t = INF
	if not point.is_finite() or projected.size() != points.size() or ms < previous_ms:
		reset_motion()
		return
	var from := previous if previous.is_finite() else point
	var from_ms := previous_ms if previous.is_finite() else ms
	previous = point
	previous_ms = ms
	if ms < start_ms or points.size() < 2:
		return
	if from_ms < start_ms:
		from = from.lerp(point, clampf((start_ms - from_ms) / maxf(0.000001, ms - from_ms), 0.0, 1.0))
		from_ms = start_ms
	_from = from
	_to = point
	_from_ms = from_ms
	_to_ms = ms
	_screen_points = projected
	var scale := 1.0
	for i in points.size() - 1:
		var local_length := points[i].distance_to(points[i + 1])
		if local_length > 0.000001 and projected[i].is_finite() and projected[i + 1].is_finite():
			scale = maxf(0.000001, projected[i].distance_to(projected[i + 1]) / local_length)
			break
	if coordinate_scale > 0.0:
		scale = coordinate_scale
	var steps := clampi(ceili(from.distance_to(point) / maxf(0.00001, radius * 0.45)), 1, 128)
	var step_length := from.distance_to(point) / float(steps) / scale
	for step in steps + 1:
		var t := float(step) / float(steps)
		_consume_position(from.lerp(point, t), lerpf(from_ms, ms, t), projected, radius, scale, step_length if step > 0 else 0.0, (point - from) / float(steps) if step > 0 else Vector2.ZERO)
		if body_ready() and (progress >= END_PROGRESS or next_gate == gates.size()) and not is_finite(_finish_min_t):
			_finish_min_t = t


func _consume_position(point: Vector2, ms: float, projected: PackedVector2Array, radius: float, scale: float, step_length: float, movement: Vector2) -> void:
	var gap := minf(REJOIN_DISTANCE, length * 0.15)
	if is_finite(_away_since) and ms - _away_since > REJOIN_GRACE_MS:
		gap = minf(0.30, length * 0.10)
	var low := maxf(0.0, _furthest - maxf(0.4, contact_radius))
	var high := minf(length, _furthest + step_length * 1.6 + gap)
	if next_gate < gates.size():
		high = minf(high, float(distances[gates[next_gate]]) + float(gate_radii[next_gate]))
	var effective_radius := radius
	for gate in [next_gate - 1, next_gate]:
		if gate >= 0 and gate < gates.size() and point.distance_to(projected[gates[gate]]) <= float(gate_radii[gate]) * scale:
			effective_radius = maxf(effective_radius, float(gate_radii[gate]) * scale)
	var best_distance := INF
	var best_s := 0.0
	var best_edge := 0
	var best_t := 0.0
	for i in range(_edge_at(low), mini(points.size() - 1, _edge_at(high) + 1)):
		var a := projected[i]
		var b := projected[i + 1]
		if not a.is_finite() or not b.is_finite():
			continue
		var ab := b - a
		var span := float(distances[i + 1] - distances[i])
		if span <= 0.000001:
			continue
		var t := 0.0 if ab.length_squared() <= 0.000001 else (point - a).dot(ab) / ab.length_squared()
		t = clampf(t, maxf(0.0, (low - float(distances[i])) / span), minf(1.0, (high - float(distances[i])) / span))
		var distance := point.distance_to(a + ab * t)
		var candidate_s := float(distances[i]) + span * t
		if candidate_s > _furthest + 0.00001 and ab.dot(movement) < -0.15 * ab.length() * movement.length():
			continue # A retraced branch needs an actual change of direction.
		var forward_tie := candidate_s > best_s and candidate_s >= _furthest and ab.dot(movement) > 0.000001
		if distance < best_distance - 0.00001 or (absf(distance - best_distance) <= 0.00001 and forward_tie):
			best_distance = distance
			best_s = candidate_s
			best_edge = i
			best_t = t
	if best_distance > effective_radius:
		if not is_finite(_away_since):
			_away_since = ms
		return
	_away_since = -INF
	if best_s > _furthest:
		_furthest = best_s
		fraction = lerpf(parameters[best_edge], parameters[best_edge + 1], best_t)
		progress = _furthest / length
		next_index = mini(points.size(), best_edge + 1)
	# Only touched pieces receive coverage. Rejoining does not fill the gap.
	var reach := effective_radius / scale
	for i in range(_edge_at(maxf(0.0, best_s - reach)), mini(points.size() - 1, _edge_at(minf(length, best_s + reach)) + 1)):
		if covered[i] == 0 and projected[i].is_finite() and projected[i + 1].is_finite() and point.distance_to(projected[i].lerp(projected[i + 1], 0.5)) <= effective_radius:
			covered[i] = 1
			_covered_length += float(distances[i + 1] - distances[i])
	coverage = minf(1.0, _covered_length / length)
	while next_gate < gates.size():
		var index := gates[next_gate]
		var gate_radius := float(gate_radii[next_gate])
		if absf(float(distances[index]) - best_s) > gate_radius + 0.00001 or point.distance_to(projected[index]) > gate_radius * scale:
			break
		next_gate += 1


func _edge_at(distance: float) -> int:
	var low := 0
	var high := distances.size() - 1
	while low < high:
		var mid := (low + high + 1) / 2
		if float(distances[mid]) <= distance:
			low = mid
		else:
			high = mid - 1
	return mini(low, maxi(0, distances.size() - 2))


## Coverage unlocks the tail; only actual end contact supplies its timing.
## Holding an early arrival until the perfect window avoids a forced early GOOD.
func finish_contact(window_from: float, window_to: float, tail_radius: float, target_ms := INF, perfect_ms := 80.0) -> float:
	var begin := INF
	var end := -INF
	if is_finite(_finish_min_t) and body_ready():
		var interval := circle_interval(_from, _to, _screen_points[-1], tail_radius)
		var t := maxf(interval.x, _finish_min_t)
		if is_finite(t) and t <= interval.y:
			begin = maxf(window_from, lerpf(_from_ms, _to_ms, t))
			end = minf(window_to, lerpf(_from_ms, _to_ms, interval.y))
	if begin <= end:
		if not is_finite(target_ms):
			return begin
		_pending_tail_exit = end
		var score_from := target_ms - perfect_ms
		if begin <= score_from and end >= score_from:
			return score_from
		if begin > score_from:
			return begin
		if _to.distance_to(_screen_points[-1]) <= tail_radius and _to_ms < score_from:
			return INF
	if is_finite(_pending_tail_exit) and _pending_tail_exit >= window_from:
		return _pending_tail_exit
	return INF


static func circle_interval(from: Vector2, to: Vector2, center: Vector2, radius: float) -> Vector2:
	if not from.is_finite() or not to.is_finite() or not center.is_finite() or radius <= 0.0:
		return Vector2(INF, -INF)
	var direction := to - from
	var offset := from - center
	var a := direction.length_squared()
	var c := offset.length_squared() - radius * radius
	if a <= 0.000001:
		return Vector2(0.0, 1.0) if c <= 0.0 else Vector2(INF, -INF)
	var b := offset.dot(direction)
	var discriminant := b * b - a * c
	if discriminant < 0.0:
		return Vector2(INF, -INF)
	var root := sqrt(discriminant)
	var begin := maxf(0.0, (-b - root) / a)
	var end := minf(1.0, (-b + root) / a)
	return Vector2(begin, end) if begin <= end else Vector2(INF, -INF)
