class_name PathProgress
extends RefCounted

## Ordered path groups + tolerance scan, adapted from AstroDX's slide scan.
## Groups come from the path geometry (arc length + corners), not from maimai's
## physical sensor layout, so any plane curve or deformed ring works.
const SAMPLE_SPACING := 0.06
const GATE_SPACING := 0.85
const CONTACT_RADIUS := 0.25
const CORNER_RADIUS := 0.34
## How many groups a single movement may skip. AstroDX uses one by default.
const SKIP_TOLERANCE := 1
## Short slides (three groups or fewer) must be traced through every group.
const NO_SKIP_GROUP_LIMIT := 3
const REJOIN_DISTANCE := 0.45
const REJOIN_GRACE_MS := 180.0

var points := PackedVector2Array()
var parameters := PackedFloat32Array()
var distances := PackedFloat32Array()
var mandatory := PackedByteArray()
var gates := PackedInt32Array()
var gate_radii := PackedFloat32Array()
var cleared := PackedByteArray()
var covered := PackedByteArray()
var length := 0.0
var contact_radius := CONTACT_RADIUS
var group_count := 0
var tolerance := 0
var next_gate := 0
var next_index := 0
var required_index := 0
var fraction := 0.0
var coverage := 0.0
var progress := 0.0
var previous := Vector2.INF
var previous_ms := -INF
var _furthest := 0.0
var _covered_length := 0.0
var _covered_to := 0.0
var _away_since := -INF
var _screen_points := PackedVector2Array()
var _from := Vector2.INF
var _to := Vector2.INF
var _from_ms := 0.0
var _to_ms := 0.0
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
	cleared.clear()
	covered.clear()
	length = 0.0
	group_count = 0
	tolerance = 0
	next_gate = 0
	next_index = 0
	required_index = 0
	fraction = 0.0
	coverage = 0.0
	progress = 0.0
	_furthest = 0.0
	_covered_length = 0.0
	_covered_to = 0.0
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
	var targets: Array[float] = [0.0, length * 0.80, length]
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
		if target < length * 0.80 - 0.00001:
			required_index = points.size()
	covered.resize(maxi(0, points.size() - 1))
	covered.fill(0)
	cleared.resize(maxi(0, gates.size() - 1))
	cleared.fill(0)
	group_count = cleared.size()
	tolerance = SKIP_TOLERANCE if group_count > NO_SKIP_GROUP_LIMIT else 0


## The slide head counts as the first judgement group (maimai's A-zone exemption).
## It is marked cleared but not covered: the player still has to trace the body.
func confirm_head() -> void:
	if group_count > 0 and cleared[0] == 0:
		cleared[0] = 1
		next_gate = 1
		next_index = mini(points.size(), int(gates[1])) if gates.size() > 1 else points.size()
		fraction = float(parameters[next_index - 1]) if next_index > 0 else 0.0


func reset_motion() -> void:
	previous = Vector2.INF
	previous_ms = -INF
	_pending_tail_exit = -INF
	_away_since = -INF


func body_ready() -> bool:
	return group_count > 0 and next_gate >= group_count


## The tail was actually reached/judged; only then may the visual erase the
## remaining tail segment.
func mark_complete() -> void:
	fraction = 1.0
	progress = 1.0
	coverage = 1.0


## Completion is judged by tail timing only; body groups never cap the tier.
func remaining_groups() -> int:
	return maxi(0, group_count - next_gate)


func feed(point: Vector2, ms: float, projected: PackedVector2Array, radius: float, start_ms: float, _coordinate_scale := 0.0) -> void:
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
	# Split long mouse jumps so a fast sweep still visits every group it crosses.
	var steps := clampi(ceili(from.distance_to(point) / maxf(0.00001, radius * 0.45)), 1, 128)
	var step_vector := (point - from) / float(steps)
	for step in steps + 1:
		var t := float(step) / float(steps)
		_scan_groups(from.lerp(point, t), projected, radius, step_vector)


func _scan_groups(point: Vector2, projected: PackedVector2Array, radius: float, movement: Vector2) -> void:
	var scan := next_gate
	var budget := tolerance
	var moving := movement.length() > radius * 0.15
	while scan < group_count:
		var closest := _group_closest(scan, point, projected)
		var tangent: Vector2 = closest.get("tangent", Vector2.ZERO)
		var group_start := int(gates[scan])
		var group_end := int(gates[scan + 1]) if scan + 1 < gates.size() else points.size() - 1
		var group_length := float(distances[group_end] - distances[group_start])
		var backwards := moving and tangent != Vector2.ZERO and group_length > contact_radius \
			and movement.normalized().dot(tangent) < -0.3
		if closest.distance <= radius and not backwards:
			_clear_through(scan, closest, movement)
			return
		budget -= 1
		if budget < 0:
			return
		scan += 1


func _group_closest(index: int, point: Vector2, projected: PackedVector2Array) -> Dictionary:
	var start := int(gates[index])
	var finish := int(gates[index + 1]) if index + 1 < gates.size() else points.size() - 1
	var result := {"distance": INF, "local": Vector2.ZERO, "parameter": 0.0}
	if finish <= start:
		if _valid(projected, start):
			return {"distance": point.distance_to(projected[start]), "local": points[start], "parameter": parameters[start]}
		return result
	for i in range(start, finish):
		if not _valid(projected, i) or not _valid(projected, i + 1):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, projected[i], projected[i + 1])
		var distance := point.distance_to(closest)
		if distance >= float(result["distance"]):
			continue
		var a := projected[i]
		var b := projected[i + 1]
		var ab := b - a
		var t := 0.0 if ab.length_squared() <= 0.000001 else clampf((closest - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		result["distance"] = distance
		result["local"] = points[i].lerp(points[i + 1], t)
		result["parameter"] = lerpf(parameters[i], parameters[i + 1], t)
		result["path_distance"] = lerpf(float(distances[i]), float(distances[i + 1]), t)
		result["edge"] = i
		result["tangent"] = ab.normalized() if ab.length_squared() > 0.000001 else Vector2.ZERO
	return result


static func _valid(points_array: PackedVector2Array, index: int) -> bool:
	return index >= 0 and index < points_array.size() and points_array[index].is_finite()


## Clear every group up to `index`. Groups are contiguous; skipped intermediate
## groups count as cleared but their corridor stays visually pending unless the
## movement actually touched them.
func _clear_through(index: int, closest: Dictionary, _movement: Vector2) -> void:
	# Only the group the cursor actually touched gets corridor coverage.
	var hit_distance := float(closest.get("path_distance", 0.0))
	var skipped := index > next_gate
	var cover_from := _covered_to if not skipped else float(distances[clampi(int(gates[index]), 0, distances.size() - 1)])
	if cleared[index] == 0:
		cleared[index] = 1
	# Continuous progress fills everything between the last covered point and the
	# hit; a skipped group never fills the gap it jumped over.
	if hit_distance > cover_from:
		for edge in range(covered.size()):
			if float(distances[edge + 1]) <= cover_from + 0.000001:
				continue
			if float(distances[edge]) >= hit_distance - 0.000001:
				break
			if covered[edge] == 0:
				covered[edge] = 1
				_covered_length += float(distances[edge + 1] - distances[edge])
		_covered_to = maxf(_covered_to, hit_distance)
	for group in range(next_gate, index):
		cleared[group] = 1
	next_gate = index + 1
	next_index = points.size() if next_gate >= group_count else int(gates[next_gate])
	var fallback_index := clampi(index, 0, maxi(0, distances.size() - 1))
	var reached := float(closest.get("path_distance", distances[fallback_index]))
	_furthest = maxf(_furthest, reached)
	if next_gate >= group_count:
		_furthest = length
		_covered_to = length
		progress = 1.0
		coverage = 1.0
		# fraction deliberately stays at the last touched point; the visual
		# tail is only erased by mark_complete() after the tail is judged.
	else:
		progress = clampf(_furthest / length, 0.0, 1.0)
		fraction = clampf(float(closest["parameter"]), 0.0, 1.0)
		coverage = minf(1.0, _covered_length / length)


## Coverage unlocks nothing; completion is the last group's contact. Holding an
## early arrival until the perfect window avoids a forced early GOOD.
func finish_contact(window_from: float, window_to: float, tail_radius: float, target_ms := INF, perfect_ms := 80.0) -> float:
	if not body_ready():
		return INF
	var begin := INF
	var end := -INF
	var interval := circle_interval(_from, _to, _screen_points[-1], tail_radius)
	var t := maxf(interval.x, 0.0)
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
