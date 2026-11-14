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
var _from: ShapeSampler = null
var _to: ShapeSampler = null
var _p: float = 0.0
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
	var pair := BoundaryRuntime.pair_at(chart, beat)
	if pair.is_empty():
		return
	_from = _samplers.get(pair.get("from"))
	_to = _samplers.get(pair.get("to"))
	_p = float(pair.get("p", 0.0))


func point_at(u: float) -> Dictionary:
	if _points.has(u):
		return _points[u]
	var result := _evaluate(u)
	_points[u] = result
	return result


func _evaluate(u: float) -> Dictionary:
	if _from == null or _to == null:
		if _base == null:
			return {"point": Vector2.ZERO, "gap": true}
		return _base.point_at(u)
	var a := _from.point_at(u)
	var b := _to.point_at(u)
	return {
		"point": (a.point as Vector2).lerp(b.point, _p),
		"gap": a.gap if _p < 0.5 else b.gap,
		"segment": null,
	}


func sample_points(count: int) -> Array[Dictionary]:
	var safe_count := maxi(count, 8)
	if _from == null or _to == null:
		if _base == null:
			var empty: Array[Dictionary] = []
			for i in safe_count:
				empty.append(point_at(float(i) / float(safe_count)))
			return empty
		return _base.sample_points(safe_count)
	var from_points := _from.sample_points(safe_count)
	var to_points := _to.sample_points(safe_count)
	var result: Array[Dictionary] = []
	for i in safe_count:
		var a: Dictionary = from_points[i]
		var b: Dictionary = to_points[i]
		result.append({
			"point": (a.point as Vector2).lerp(b.point, _p),
			"gap": a.gap if _p < 0.5 else b.gap,
			"segment": null,
		})
		_points[float(i) / float(safe_count)] = result[i]
	return result
