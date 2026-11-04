class_name JudgeMath
extends RefCounted

## One-dimensional logical-angle math used by validation and the playtest.
## Intervals are non-wrapping [start, end] pairs in degrees, 0 <= start < end <= 360.

const EPS := 0.000001


static func normalize_angle(angle: float) -> float:
	return fposmod(angle, 360.0)


static func angle_delta(from_angle: float, to_angle: float) -> float:
	return fposmod(to_angle - from_angle + 180.0, 360.0) - 180.0


static func angle_distance(a: float, b: float) -> float:
	return absf(angle_delta(a, b))


static func in_arc(angle: float, center: float, width: float) -> bool:
	if width >= 360.0:
		return true
	return angle_distance(angle, center) <= width * 0.5 + EPS


static func interval(center: float, width: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if width >= 360.0:
		result.append(Vector2(0.0, 360.0))
		return result
	var half := maxf(width, 0.0) * 0.5
	var start := normalize_angle(center - half)
	var end := normalize_angle(center + half)
	if half >= 180.0:
		result.append(Vector2(0.0, 360.0))
	elif start <= end:
		result.append(Vector2(start, end))
	else:
		result.append(Vector2(start, 360.0))
		result.append(Vector2(0.0, end))
	return result


static func intersect(a: Array[Vector2], b: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for first in a:
		for second in b:
			var start := maxf(first.x, second.x)
			var end := minf(first.y, second.y)
			if end - start > EPS:
				result.append(Vector2(start, end))
	return result


static func intersect_all(lists: Array) -> Array[Vector2]:
	if lists.is_empty():
		return []
	var result: Array[Vector2] = []
	for item in lists[0]:
		result.append(item)
	for i in range(1, lists.size()):
		result = intersect(result, lists[i])
		if result.is_empty():
			return []
	return result


static func subtract(base: Array[Vector2], cuts: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = base.duplicate()
	for cut in cuts:
		var next: Array[Vector2] = []
		for piece in result:
			if cut.y <= piece.x + EPS or cut.x >= piece.y - EPS:
				next.append(piece)
				continue
			if cut.x > piece.x + EPS:
				next.append(Vector2(piece.x, minf(cut.x, piece.y)))
			if cut.y < piece.y - EPS:
				next.append(Vector2(maxf(cut.y, piece.x), piece.y))
		result = next
	return result


static func total_length(intervals: Array[Vector2]) -> float:
	var total := 0.0
	for item in intervals:
		total += maxf(0.0, item.y - item.x)
	return total


static func intervals_for_notes(notes: Array, beat: float) -> Array:
	var lists: Array = []
	for note in notes:
		match note.type:
			"tap":
				if absf(note.beat - beat) <= 0.001:
					lists.append(interval(note.angle, note.width))
			"hold":
				if absf(note.beat - beat) <= 0.001:
					lists.append(interval(note.angle, note.width))
			"path":
				if absf(note.beat - beat) <= 0.001:
					lists.append(interval(note.angle, note.width))
				if absf(note.end_beat - beat) <= 0.001:
					lists.append(interval(note.tail_angle, note.tail_width))
	return lists


static func red_intervals(regions: Array[Region], beat: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for region in regions:
		if region.kind == "red" and region.active_at(beat):
			result.append_array(interval(region.angle, region.width))
	return result


static func playable_at(chart: Chart, beat: float) -> Array[Vector2]:
	var lists := intervals_for_notes(chart.notes, beat)
	if lists.is_empty():
		return []
	var common := intersect_all(lists)
	if common.is_empty():
		return []
	return subtract(common, red_intervals(chart.regions, beat))


static func trace_distance(point: Vector2, polyline: Array[Vector2]) -> float:
	if polyline.is_empty():
		return INF
	if polyline.size() == 1:
		return point.distance_to(polyline[0])
	var best := INF
	for i in range(polyline.size() - 1):
		var a := polyline[i]
		var b := polyline[i + 1]
		var ab := b - a
		var denom := ab.length_squared()
		var t := 0.0 if denom <= EPS else clampf((point - a).dot(ab) / denom, 0.0, 1.0)
		best = minf(best, point.distance_to(a + ab * t))
	return best
