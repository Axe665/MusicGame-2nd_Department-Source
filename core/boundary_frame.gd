class_name BoundaryFrame
extends RefCounted

## Prepared boundary evaluation for one chart/time. Discard after geometry edits.
## Rendering and cursor queries share exact results; u is never quantized.

class ShapeSampler:
	extends RefCounted
	var shape: BoundaryShape
	var segments: Array[BoundarySegment]
	var monotonic: bool = true
	var _samples: Dictionary = {}

	func _init(source: BoundaryShape) -> void:
		shape = source
		segments = source.sorted_segments()
		for i in range(1, segments.size()):
			if segments[i].u1 < segments[i - 1].u1:
				monotonic = false

	func point_at(u: float) -> Dictionary:
		var uu := 0.0 if is_equal_approx(u, 1.0) else fposmod(u, 1.0)
		var found: BoundarySegment = null
		if monotonic:
			var low := 0
			var high := segments.size()
			while low < high:
				var mid := (low + high) / 2
				if segments[mid].u1 < uu - 0.000001:
					low = mid + 1
				else:
					high = mid
			if low < segments.size() and segments[low].u0 <= uu + 0.000001:
				found = segments[low]
		else:
			# Preserve lookup semantics for malformed shapes while editing.
			for segment in segments:
				if uu + 0.000001 >= segment.u0 and uu - 0.000001 <= segment.u1:
					found = segment
					break
		if found == null and shape.closed and uu <= 0.000001 and not segments.is_empty():
			found = segments[-1]
		if found == null:
			return {"point": Vector2.ZERO, "gap": true, "segment": null}
		return {"point": found.point_at(found.local_t(u)), "gap": found.gap, "segment": found}

	func sample_points(count: int) -> Array[Dictionary]:
		if not _samples.has(count):
			_samples[count] = shape.sample_points(count)
		return _samples[count]


var chart: Chart
var beat: float
var _base: ShapeSampler
var _events: Array[Dictionary] = []
var _points: Dictionary = {}
var _samplers: Dictionary = {}


func _init(source: Chart, time: float, previous: BoundaryFrame = null) -> void:
	chart = source
	beat = time
	if previous != null and previous.chart == chart:
		_samplers = previous._samplers
	else:
		for shape in chart.sorted_shapes():
			_samplers[shape] = ShapeSampler.new(shape)
	_base = _samplers.get(chart.get_default_shape())
	for event in chart.events:
		var tail := event.end_beat
		if event.end_behavior == "restore":
			tail += maxf(0.0, event.restore_duration)
		if beat + 0.000001 < event.start_beat or beat > tail + 0.000001:
			continue
		var from: ShapeSampler = _samplers.get(chart.get_shape(event.from_shape))
		var to: ShapeSampler = _samplers.get(chart.get_shape(event.to_shape))
		var p := 0.0
		if beat <= event.end_beat:
			p = Ease.apply(event.easing, (beat - event.start_beat) / maxf(0.000001, event.duration()))
		elif event.end_behavior == "hold":
			p = 1.0
		elif event.restore_duration > 0.000001:
			var swap := from
			from = to
			to = swap
			p = Ease.apply(event.restore_easing, clampf((beat - event.end_beat) / event.restore_duration, 0.0, 1.0))
		_events.append({"event": event, "from": from, "to": to, "p": p})


func point_at(u: float) -> Dictionary:
	if _points.has(u):
		return _points[u]
	var result := _evaluate(u)
	_points[u] = result
	return result


func _evaluate(u: float) -> Dictionary:
	if _base == null:
		return {"point": Vector2.ZERO, "gap": true}
	for i in range(_events.size() - 1, -1, -1):
		var state := _events[i]
		var event: BoundaryEvent = state.event
		if not event.covers_u(u):
			continue
		var from: ShapeSampler = state.from
		var to: ShapeSampler = state.to
		if from == null or to == null:
			return _base.point_at(u)
		var a := from.point_at(u)
		var b := to.point_at(u)
		var p: float = state.p
		var from_vec: Vector2 = a.point
		return {"point": from_vec.lerp(b.point, p), "gap": a.gap if p < 0.5 else b.gap, "segment": null}
	return _base.point_at(u)


func sample_points(count: int) -> Array[Dictionary]:
	var safe_count := maxi(count, 8)
	if _base == null:
		var empty: Array[Dictionary] = []
		for i in safe_count:
			empty.append(point_at(float(i) / float(safe_count)))
		return empty
	var base_points := _base.sample_points(safe_count)
	var result := base_points.duplicate()
	for state in _events:
		var event: BoundaryEvent = state.event
		var from: ShapeSampler = state.from
		var to: ShapeSampler = state.to
		var from_points: Array[Dictionary] = from.sample_points(safe_count) if from != null else []
		var to_points: Array[Dictionary] = to.sample_points(safe_count) if to != null else []
		var p: float = state.p
		for i in safe_count:
			if not event.covers_u(float(i) / float(safe_count)):
				continue
			if from == null or to == null:
				result[i] = base_points[i]
				continue
			var a := from_points[i]
			var b := to_points[i]
			var from_vec: Vector2 = a.point
			result[i] = {"point": from_vec.lerp(b.point, p), "gap": a.gap if p < 0.5 else b.gap, "segment": null}
	for i in safe_count:
		_points[float(i) / float(safe_count)] = result[i]
	return result
