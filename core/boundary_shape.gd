class_name BoundaryShape
extends RefCounted

var id: String = "S0"
var closed: bool = true
var segments: Array[BoundarySegment] = []

## 编辑器只暴露“顶点”：顶点沿环均匀等分，段由相邻顶点生成。
## 文件仍存段，所以老谱面和求值代码都不用改。
const MIN_VERTICES := 3
const MAX_VERTICES := 48
const DEFAULT_VERTICES := 8


## 顶点环的规范化：段按 u 排序、相邻端点共用；超过 24 段的老谱面降采样。
## 顶点 u 由结构决定（不暴露给谱师），插入/删除顶点不会挪动其他顶点。
func normalize() -> void:
	if segments.is_empty():
		var fallback := BoundaryShape.circle(id, 330.0, DEFAULT_VERTICES)
		segments = fallback.segments
		return
	# 旧谱每段可以有自己的 X/Y 曲线；顶点模型只有直线段，这里统一降级。
	for segment in segments:
		if segment.ix != "l" or segment.iy != "l":
			resample(segments.size())
			return
	if segments.size() > MAX_VERTICES:
		resample(MAX_VERTICES)
		return
	segments.sort_custom(func(a: BoundarySegment, b: BoundarySegment) -> bool: return a.u0 < b.u0)
	for i in segments.size():
		if not closed and i == segments.size() - 1:
			break
		# 只修真正断开的接点，浮点尾数保持原样，存盘才能逐字节稳定。
		var next_point: Vector2 = segments[(i + 1) % segments.size()].p0
		if segments[i].p1.distance_to(next_point) > 0.000001:
			segments[i].p1 = next_point


## 按 u 均匀重采样成 count 段：老形状降采样和“顶点数”改数用这个。
func resample(count: int) -> void:
	var n := clampi(count, MIN_VERTICES, MAX_VERTICES)
	var points: Array[Vector2] = []
	var gaps: Array[bool] = []
	for i in n:
		points.append(point_at(float(i) / float(n)).point)
		# 缺口按段中点取样，避开 u 的接缝。
		gaps.append(bool(point_at((float(i) + 0.5) / float(n)).gap))
	segments.clear()
	for i in n:
		segments.append(BoundarySegment.new(
			float(i) / float(n), float(i + 1) / float(n),
			points[i], points[(i + 1) % n], "l", "l", gaps[i]
		))


## 在某一段的 u 中点插一个顶点；轮廓完全不变，只是多一个可拖的手柄。
func insert_vertex(segment_index: int) -> bool:
	if segments.size() >= MAX_VERTICES:
		return false
	var sorted := sorted_segments()
	if sorted.is_empty():
		return false
	var segment: BoundarySegment = sorted[clampi(segment_index, 0, sorted.size() - 1)]
	var u := (segment.u0 + segment.u1) * 0.5
	var point := segment.point_at(0.5)
	segments.erase(segment)
	segments.append(BoundarySegment.new(segment.u0, u, segment.p0, point, "l", "l", segment.gap))
	segments.append(BoundarySegment.new(u, segment.u1, point, segment.p1, "l", "l", segment.gap))
	return true


## 删顶点 = 把该顶点两侧的段合成一段；其他顶点不动。
func remove_vertex(index: int) -> bool:
	var sorted := sorted_segments()
	var n := sorted.size()
	if n <= MIN_VERTICES:
		return false
	var i := posmod(index, n)
	if i == 0:
		var last: BoundarySegment = sorted[n - 1]
		var first: BoundarySegment = sorted[0]
		first.u0 = last.u0
		first.p0 = last.p0
		segments.erase(last)
	else:
		var previous: BoundarySegment = sorted[i - 1]
		var segment: BoundarySegment = sorted[i]
		previous.u1 = segment.u1
		previous.p1 = segment.p1
		segments.erase(segment)
	return true


func vertex_count() -> int:
	return segments.size()


func vertices() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for segment in sorted_segments():
		result.append(segment.p0)
	return result


## 拖顶点：相邻两段的端点一起动，环结构上不可能断接。
func set_vertex(index: int, point: Vector2) -> void:
	var sorted := sorted_segments()
	var n := sorted.size()
	if n == 0:
		return
	var i := posmod(index, n)
	sorted[i].p0 = point
	sorted[posmod(i - 1, n)].p1 = point


func set_vertex_count(count: int) -> void:
	resample(count)


func segment_has_gap(index: int) -> bool:
	var sorted := sorted_segments()
	if index < 0 or index >= sorted.size():
		return false
	return sorted[index].gap


func set_gap(index: int, value: bool) -> void:
	var sorted := sorted_segments()
	if index < 0 or index >= sorted.size():
		return
	sorted[index].gap = value


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
	# 凹形（凹口、内凹弧）允许；只拦自交和结构错误。
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


func to_code() -> String:
	return "shape{%s}" % _body_code()


func _body_code() -> String:
	var chunks: Array[String] = []
	for seg in sorted_segments():
		chunks.append("[%d,(%s,%s),(%s,%s),(%s,%s),(%s,%s)]" % [
			1 if seg.gap else 0, seg.ix, seg.iy,
			str(seg.u0), str(seg.u1), str(seg.p0.x), str(seg.p1.x), str(seg.p0.y), str(seg.p1.y)
		])
	return "[%s,%d,segments{%s}]" % [id, 1 if closed else 0, ",".join(chunks)]


static func shapes_to_code(shapes: Array) -> String:
	var chunks: Array[String] = []
	for shape in shapes:
		chunks.append((shape as BoundaryShape)._body_code())
	return "shape{%s}" % ";".join(chunks)


static func shapes_from_code(code: String) -> Array[BoundaryShape]:
	var result: Array[BoundaryShape] = []
	var text := code.strip_edges()
	var open := text.find("{")
	var close := text.rfind("}")
	if open < 0 or close <= open:
		return result
	for chunk in _split_top_level(text.substr(open + 1, close - open - 1), ";"):
		if chunk.strip_edges().is_empty():
			continue
		var shape := _shape_from_body(chunk.strip_edges())
		if shape != null:
			result.append(shape)
	return result


static func from_code(code: String) -> BoundaryShape:
	var shapes := shapes_from_code(code)
	return shapes[0] if not shapes.is_empty() else BoundaryShape.new()


static func _shape_from_body(chunk: String) -> BoundaryShape:
	var text := chunk.strip_edges()
	var seg_open := text.find(",segments{")
	if seg_open < 0:
		return null
	var header := text.substr(1, seg_open - 1)
	var head_fields := header.split(",", true)
	var shape := BoundaryShape.new()
	if head_fields.size() > 0:
		shape.id = head_fields[0].strip_edges()
	if head_fields.size() > 1:
		shape.closed = int(head_fields[1]) != 0
	var body_start := seg_open + ",segments{".length()
	var body_end := text.rfind("}]")
	if body_end < body_start:
		body_end = text.rfind("}")
	var body := text.substr(body_start, body_end - body_start)
	var regex := RegEx.new()
	regex.compile("\\[\\s*(\\d+)\\s*,\\s*\\(([^,]+),([^)]+)\\)\\s*,\\s*\\(([^,]+),([^)]+)\\)\\s*,\\s*\\(([^,]+),([^)]+)\\)\\s*,\\s*\\(([^,]+),([^)]+)\\)\\s*\\]")
	for found in regex.search_all(body):
		shape.segments.append(BoundarySegment.new(
			float(found.get_string(4)), float(found.get_string(5)),
			Vector2(float(found.get_string(6)), float(found.get_string(8))),
			Vector2(float(found.get_string(7)), float(found.get_string(9))),
			found.get_string(2).strip_edges(), found.get_string(3).strip_edges(),
			int(found.get_string(1)) != 0
		))
	return shape


static func _split_top_level(text: String, separator: String) -> Array[String]:
	var result: Array[String] = []
	var start := 0
	var depth := 0
	for i in text.length():
		var ch := text[i]
		if ch == "[" or ch == "{" or ch == "(":
			depth += 1
		elif ch == "]" or ch == "}" or ch == ")":
			depth -= 1
		elif ch == separator and depth == 0:
			result.append(text.substr(start, i - start))
			start = i + 1
	result.append(text.substr(start))
	return result


static func circle(p_id: String, radius: float, count: int = 48) -> BoundaryShape:
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


static func ellipse(p_id: String, rx: float, ry: float, count: int = 48) -> BoundaryShape:
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
