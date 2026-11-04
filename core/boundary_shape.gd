class_name BoundaryShape
extends RefCounted

var id: String = "S0"
var closed: bool = true
var segments: Array[BoundarySegment] = []


func sorted_segments() -> Array[BoundarySegment]:
	var copy := segments.duplicate()
	copy.sort_custom(func(a: BoundarySegment, b: BoundarySegment) -> bool: return a.u0 < b.u0)
	return copy


func segment_at(u: float) -> BoundarySegment:
	var uu := fposmod(u, 1.0)
	if is_equal_approx(u, 1.0):
		uu = 0.0
	# This is called for every ring sample. Find the first segment in u order
	# without allocating and sorting the entire array for each point. Scan the
	# live array so control-point edits and segment splits need no cache invalidation.
	var found: BoundarySegment = null
	var last: BoundarySegment = null
	for segment in segments:
		if last == null or segment.u0 > last.u0:
			last = segment
		if uu + 0.000001 >= segment.u0 and uu - 0.000001 <= segment.u1:
			if found == null or segment.u0 < found.u0:
				found = segment
	if found != null:
		return found
	# A closed shape's u=1 seam belongs to the last segment.
	if closed and uu <= 0.000001 and not segments.is_empty():
		return last
	return null


func point_at(u: float) -> Dictionary:
	var segment := segment_at(u)
	if segment == null:
		return {"point": Vector2.ZERO, "gap": true, "segment": null}
	var point := segment.point_at(segment.local_t(u))
	return {"point": point, "gap": segment.gap, "segment": segment}


func sample_points(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var safe_count := maxi(count, 2)
	var sorted := sorted_segments()
	var index := 0
	for i in safe_count:
		var u := float(i) / float(safe_count)
		# Samples and segments are both in u order: walk the segments once.
		while index < sorted.size() and u - 0.000001 > sorted[index].u1:
			index += 1
		var segment: BoundarySegment = null
		if index < sorted.size() and u + 0.000001 >= sorted[index].u0:
			segment = sorted[index]
		elif closed and i == 0 and not sorted.is_empty():
			segment = sorted[-1]
		if segment == null:
			result.append({"point": Vector2.ZERO, "gap": true, "segment": null})
		else:
			result.append({"point": segment.point_at(segment.local_t(u)), "gap": segment.gap, "segment": segment})
	return result


func validate() -> Array[String]:
	var issues: Array[String] = []
	if segments.is_empty():
		issues.append("形状 %s 没有分段" % id)
		return issues
	var sorted := sorted_segments()
	if absf(sorted[0].u0) > 0.0001:
		issues.append("形状 %s 的首段 u0 必须为 0" % id)
	if absf(sorted[-1].u1 - 1.0) > 0.0001:
		issues.append("形状 %s 的末段 u1 必须为 1" % id)
	for i in sorted.size():
		var segment := sorted[i]
		if segment.u0 < -0.0001 or segment.u1 > 1.0001:
			issues.append("形状 %s 第 %d 段 u 越界" % [id, i + 1])
		if segment.u1 - segment.u0 < 0.00001:
			issues.append("形状 %s 第 %d 段过窄" % [id, i + 1])
		if segment.p0.is_finite() == false or segment.p1.is_finite() == false:
			issues.append("形状 %s 第 %d 段坐标非法" % [id, i + 1])
		if i > 0:
			var prev := sorted[i - 1]
			if absf(prev.u1 - segment.u0) > 0.0001:
				issues.append("形状 %s 第 %d 段 u 不连续" % [id, i + 1])
			if not prev.gap and not segment.gap and prev.p1.distance_to(segment.p0) > 0.01:
				issues.append("形状 %s 第 %d 段端点不接" % [id, i + 1])
	if closed and not sorted[0].gap and not sorted[-1].gap:
		if sorted[0].p0.distance_to(sorted[-1].p1) > 0.01:
			issues.append("形状 %s 未闭合：C(0)≠C(1)" % id)
	var samples: Array[Dictionary] = []
	for segment in sorted:
		for k in 9:
			samples.append({"point": segment.point_at(float(k) / 8.0), "gap": segment.gap})
	if runs_self_intersects(samples, closed):
		issues.append("形状 %s 自交：环线不允许交叉" % id)
	if runs_out_of_range(samples):
		issues.append("形状 %s 变形过激：局部半径超出平均值 0.40–1.65 倍" % id)
	if not runs_convex(samples, closed):
		issues.append("形状 %s 非凸：禁止凹口/星形/折返轮廓" % id)
	return issues


static func polyline_self_intersects(points: Array[Vector2], closed: bool) -> bool:
	var n := points.size()
	if n < 4:
		return false
	var segment_count := n if closed else n - 1
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var span := maxf(max_x - min_x, max_y - min_y)
	var cell := maxf(4.0, span / maxf(8.0, sqrt(float(segment_count))))
	# 网格粗筛：只和同一格/相邻格里的线段做精确相交测试。
	var buckets: Dictionary = {}
	for i in segment_count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var x0 := floori(minf(a.x, b.x) / cell)
		var x1 := floori(maxf(a.x, b.x) / cell)
		var y0 := floori(minf(a.y, b.y) / cell)
		var y1 := floori(maxf(a.y, b.y) / cell)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var key := Vector2i(gx, gy)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(i)
	var seen := PackedInt32Array()
	seen.resize(segment_count)
	for i in segment_count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var x0 := floori(minf(a.x, b.x) / cell)
		var x1 := floori(maxf(a.x, b.x) / cell)
		var y0 := floori(minf(a.y, b.y) / cell)
		var y1 := floori(maxf(a.y, b.y) / cell)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var candidates: Array = buckets.get(Vector2i(gx, gy), [])
				for j in candidates:
					if j <= i or j == i + 1:
						continue
					if closed and i == 0 and j == segment_count - 1:
						continue
					if seen[j] == i + 1:
						continue
					seen[j] = i + 1
					var c := points[j]
					var d := points[(j + 1) % n]
					if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
						return true
	return false


static func runs_self_intersects(points: Array[Dictionary], closed: bool) -> bool:
	var runs: Array = []
	var current: Array[Vector2] = []
	var has_gap := false
	for item in points:
		if bool(item.get("gap", false)):
			has_gap = true
			if current.size() > 2:
				runs.append(current)
			current = []
			continue
		var point: Vector2 = item.point
		if current.is_empty() or current[-1].distance_to(point) > 0.001:
			current.append(point)
	if current.size() > 2:
		runs.append(current)
	if closed and not has_gap and runs.size() == 1:
		var loop: Array[Vector2] = runs[0]
		if loop.size() > 2 and loop[0].distance_to(loop[-1]) < 0.001:
			loop.remove_at(loop.size() - 1)
		return polyline_self_intersects(loop, true)
	for run in runs:
		if polyline_self_intersects(run, false):
			return true
	return false


static func runs_out_of_range(points: Array[Dictionary]) -> bool:
	var total := 0.0
	var count := 0
	var distances: Array[float] = []
	for item in points:
		if bool(item.get("gap", false)):
			continue
		var point: Vector2 = item.point
		var distance: float = point.length()
		distances.append(distance)
		total += distance
		count += 1
	if count < 4:
		return false
	var average := total / float(count)
	if average < 1.0:
		return false
	for distance in distances:
		if distance < average * 0.40 or distance > average * 1.65:
			return true
	return false


static func runs_convex(points: Array[Dictionary], closed: bool) -> bool:
	var runs: Array = []
	var current: Array[Vector2] = []
	var has_gap := false
	for item in points:
		if bool(item.get("gap", false)):
			has_gap = true
			if current.size() > 2:
				runs.append(current)
			current = []
			continue
		var point: Vector2 = item.point
		if current.is_empty() or current[-1].distance_to(point) > 0.001:
			current.append(point)
	if current.size() > 2:
		runs.append(current)
	if closed and not has_gap and runs.size() == 1:
		var loop: Array[Vector2] = runs[0]
		if loop.size() > 2 and loop[0].distance_to(loop[-1]) < 0.001:
			loop.remove_at(loop.size() - 1)
		return _polyline_convex(loop, true)
	for run in runs:
		if not _polyline_convex(run, false):
			return false
	return true


static func _polyline_convex(points: Array[Vector2], closed: bool) -> bool:
	var n := points.size()
	if n < 3:
		return true
	var sign := 0
	var count := n if closed else n - 2
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var c := points[(i + 2) % n]
		var cross := (b - a).cross(c - b)
		var sin_turn := cross / maxf(0.0001, (b - a).length() * (c - b).length())
		if absf(sin_turn) < 0.02:
			continue
		var current_sign := 1 if sin_turn > 0.0 else -1
		if sign == 0:
			sign = current_sign
		elif sign != current_sign:
			return false
	return true


func to_dict() -> Dictionary:
	var segs: Array[Dictionary] = []
	for segment in sorted_segments():
		segs.append(segment.to_dict())
	return {"id": id, "closed": closed, "segments": segs}


static func from_dict(data: Dictionary) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = String(data.get("id", "S0"))
	shape.closed = bool(data.get("closed", true))
	for raw in data.get("segments", []):
		if raw is Dictionary:
			shape.segments.append(BoundarySegment.from_dict(raw))
	return shape


static func circle(p_id: String, radius: float, count: int = 32) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = p_id
	shape.closed = true
	var safe_count := maxi(count, 4)
	for i in safe_count:
		var a0 := TAU * float(i) / float(safe_count)
		var a1 := TAU * float(i + 1) / float(safe_count)
		shape.segments.append(BoundarySegment.new(
			float(i) / float(safe_count),
			float(i + 1) / float(safe_count),
			Vector2(cos(a0), sin(a0)) * radius,
			Vector2(cos(a1), sin(a1)) * radius,
			"l", "l"
		))
	return shape


static func ellipse(p_id: String, rx: float, ry: float, count: int = 32) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = p_id
	shape.closed = true
	var safe_count := maxi(count, 4)
	for i in safe_count:
		var a0 := TAU * float(i) / float(safe_count)
		var a1 := TAU * float(i + 1) / float(safe_count)
		shape.segments.append(BoundarySegment.new(
			float(i) / float(safe_count),
			float(i + 1) / float(safe_count),
			Vector2(cos(a0) * rx, sin(a0) * ry),
			Vector2(cos(a1) * rx, sin(a1) * ry),
			"l", "l"
		))
	return shape


static func star(p_id: String, outer: float, inner: float, points: int = 5) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = p_id
	shape.closed = true
	var vertices: Array[Vector2] = []
	var n := maxi(points, 3)
	for i in n * 2:
		var radius := outer if i % 2 == 0 else inner
		var a := -PI * 0.5 + TAU * float(i) / float(n * 2)
		vertices.append(Vector2(cos(a), sin(a)) * radius)
	for i in vertices.size():
		var next := (i + 1) % vertices.size()
		shape.segments.append(BoundarySegment.new(
			float(i) / float(vertices.size()),
			float(i + 1) / float(vertices.size()),
			vertices[i],
			vertices[next],
			"l", "l"
		))
	return shape
