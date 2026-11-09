class_name PathProgress
extends RefCounted

## Geometry is stored in ring-radius units. Parameters map confirmed distance
## back to the note's relative beat, so erasure and drawing use the same curve.
const CHECKPOINT_SPACING := 0.14
const CONTACT_RADIUS := 0.13
const REQUIRED_COVERAGE := 0.90

var points := PackedVector2Array()
var parameters := PackedFloat32Array()
var distances := PackedFloat32Array()
var length := 0.0
var contact_radius := CONTACT_RADIUS
var next_index := 0
var required_index := 0
var fraction := 0.0
var coverage := 0.0
var previous := Vector2.INF
var previous_ms := -INF
var _screen_points := PackedVector2Array()
var _radius := 0.0
var _from := Vector2.INF
var _to := Vector2.INF
var _from_ms := 0.0
var _to_ms := 0.0
var _finish_min_t := INF


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
	length = 0.0
	next_index = 0
	required_index = 0
	fraction = 0.0
	coverage = 0.0
	reset_motion()
	if source.size() < 2:
		return
	var cumulative := PackedFloat32Array([0.0])
	for i in source.size():
		if not source[i].is_finite():
			return # Never connect across a missing piece of geometry.
		if i > 0:
			length += source[i - 1].distance_to(source[i])
			cumulative.append(length)
	if length <= 0.000001:
		return
	contact_radius = minf(CONTACT_RADIUS, length * 0.12)
	var spacing := maxf(length / 2048.0, minf(CHECKPOINT_SPACING, length / 8.0))
	var targets: Array[float] = [0.0, length * REQUIRED_COVERAGE, length]
	var d := spacing
	while d < length:
		targets.append(d)
		d += spacing
	# Preserve corners even if uniform sampling would step over their vertices.
	for i in range(1, source.size() - 1):
		var a := source[i] - source[i - 1]
		var b := source[i + 1] - source[i]
		if a.length_squared() > 0.000001 and b.length_squared() > 0.000001 and a.normalized().dot(b.normalized()) < 0.8:
			targets.append(float(cumulative[i]))
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
		if source_parameters.size() == source.size():
			parameters.append(lerpf(source_parameters[edge], source_parameters[edge + 1], t))
		else:
			parameters.append(target / length)
		if target < length * REQUIRED_COVERAGE - 0.00001:
			required_index = points.size()


func reset_motion() -> void:
	previous = Vector2.INF
	previous_ms = -INF
	_finish_min_t = INF


## Each input segment can pass several checkpoints, in movement order. A later
## intersection cannot satisfy an earlier checkpoint after the cursor passed it.
func feed(point: Vector2, ms: float, projected: PackedVector2Array, radius: float, start_ms: float) -> void:
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
	_radius = radius
	var order_t := 0.0
	if next_index > required_index:
		_finish_min_t = 0.0
	while next_index < projected.size():
		var interval := circle_interval(from, point, projected[next_index], radius)
		var hit_t := maxf(order_t, interval.x)
		if interval.y < hit_t or not is_finite(hit_t):
			break
		order_t = hit_t
		if next_index == required_index:
			_finish_min_t = hit_t
		fraction = float(parameters[next_index])
		coverage = float(distances[next_index]) / length
		next_index += 1


## Return the actual contact time inside the finish window, including a fast
## pass that both enters and leaves the end of the path between rendered frames.
func finish_contact(window_from: float, window_to: float, tail_radius: float) -> float:
	if not is_finite(_finish_min_t) or _to_ms < window_from or _from_ms > window_to:
		return INF
	var first := INF
	for i in range(required_index, next_index):
		first = minf(first, _contact_in_window(_screen_points[i], _radius, window_from, window_to))
	if not _screen_points.is_empty():
		first = minf(first, _contact_in_window(_screen_points[-1], tail_radius, window_from, window_to))
	return first


func _contact_in_window(center: Vector2, radius: float, window_from: float, window_to: float) -> float:
	var interval := circle_interval(_from, _to, center, radius)
	var begin := maxf(interval.x, _finish_min_t)
	var end := interval.y
	if begin > end or not is_finite(begin):
		return INF
	var first := maxf(window_from, lerpf(_from_ms, _to_ms, begin))
	var last := minf(window_to, lerpf(_from_ms, _to_ms, end))
	return first if first <= last + 0.00001 else INF


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
