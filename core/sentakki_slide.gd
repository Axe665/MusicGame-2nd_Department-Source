class_name SentakkiSlide
extends RefCounted

## Sentakki 的滑条段库（LumpBloom7/Sentakki，osu.Game.Rulesets.Sentakki）。
## 这里只保留转换器用得到的部分：形状 × 相对终点道 × 镜像、最短时长、
## 按剩余时长拼段，以及把段链采样成平面轨迹。
##
## 坐标约定：所有点都在“环半径 = 1”的设计坐标里；Sentakki 的罗盘角
## （0 = 上，顺时针增大）在 _compass_point 里换成设计角（0 = 右，逆时针）。

const PLAYFIELD_RADIUS := 296.5
const SHAPES := ["straight", "circle", "v", "u", "cup", "thunder", "fan"]
const MAX_PARTS := 12
const _SHAPE_PENALTY := {
	"straight": 0.0,
	"circle": 0.15,
	"v": 0.25,
	"u": 0.45,
	"cup": 0.90,
	"thunder": 0.90,
	"fan": 0.50,
}

static var _cache: Dictionary = {}


## Sentakki 的 VALID_CONVERT_PATHS。`short_straight` 给舞萌路径优化用：
## 舞萌的半拍/一拍星星经常只是一小段直线，Sentakki 为了 osu 转换手感
## 排除了 1/7 道直线，但这里需要它。
static func valid_parts(short_straight: bool = false) -> Array[Dictionary]:
	var key := "short" if short_straight else "strict"
	if _cache.has(key):
		return _cache[key]
	var result: Array[Dictionary] = []
	for shape in SHAPES:
		for lanes in 8:
			for mirrored in [false, true]:
				if not _valid(shape, lanes, mirrored, short_straight):
					continue
				var points := _shape_points(shape, 0.0, lanes, mirrored)
				var length := _polyline_length(points)
				result.append({
					"shape": shape,
					"lanes": lanes,
					"mirrored": mirrored,
					"length": length,
					"min_ms": length * PLAYFIELD_RADIUS / 5.0,
				})
	_cache[key] = result
	return result


static func _valid(shape: String, lanes: int, mirrored: bool, short_straight: bool) -> bool:
	var n := posmod(lanes, 8)
	match shape:
		"straight":
			if n == 0 or mirrored:
				return false
			if short_straight:
				return true
			return n != 1 and n != 7
		"circle":
			return n != 1 and n != 7
		"v":
			return not mirrored and n != 0
		"u", "cup":
			return true
		"fan":
			return not mirrored and n == 4
		"thunder":
			return n == 4
	return false


## Sentakki chooseSlidePartFor：按剩余时长随机拼段。velocity 是
## SliderMultiplier × SV；`rng` 由调用方按谱面种子初始化。
static func choose_parts(duration_ms: float, velocity: float, rng: RandomNumberGenerator, allow_fans: bool = true, max_parts: int = MAX_PARTS) -> Array:
	var candidates := valid_parts(false)
	var factor := 1.0 + 1.0 / maxf(0.25, velocity)
	var remaining := duration_ms
	var parts: Array = []
	var last: Dictionary = {}
	var guard := 0
	while guard < max_parts:
		guard += 1
		var pool: Array = []
		for part in candidates:
			if not allow_fans and String(part["shape"]) == "fan":
				continue
			if float(part["min_ms"]) * factor < remaining:
				pool.append(part)
		if pool.is_empty():
			break
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap: Dictionary = pool[i]
			pool[i] = pool[j]
			pool[j] = swap
		var picked: Dictionary = {}
		for part in pool:
			if String(part["shape"]) == "circle" and not last.is_empty():
				if String(last["shape"]) == "circle" and bool(last["mirrored"]) == bool(part["mirrored"]) and posmod(int(last["lanes"]), 8) != 0:
					continue
			picked = part
			break
		if picked.is_empty():
			break
		remaining -= float(picked["min_ms"]) * factor
		parts.append(picked)
		last = picked
	return parts


## 舞萌路径优化用：在 move_ms 内，从 start_angle 走到 tail_angle，
## 选一条 Sentakki 合法、鼠标跟得上的段链。优先单段、短轨迹；
## 单段不行才试两段。返回空数组表示这条轨迹不该保留。
static func plan_between(start_angle: float, tail_angle: float, move_ms: float, velocity: float = 1.4, short_straight: bool = true, allow_fans: bool = true, max_parts: int = 2) -> Array:
	if move_ms <= 1.0:
		return []
	var factor := 1.0 + 1.0 / maxf(0.25, velocity)
	var delta := JudgeMath.angle_delta(start_angle, tail_angle)
	var target_mod := posmod(roundi(-delta / 45.0), 8)
	var original_sign := signf(delta)
	var candidates := valid_parts(short_straight)
	var best: Array = []
	var best_score := INF
	for part in candidates:
		if not allow_fans and String(part["shape"]) == "fan":
			continue
		if posmod(int(part["lanes"]), 8) != target_mod:
			continue
		if float(part["min_ms"]) * factor >= move_ms:
			continue
		var score := _part_score(part, original_sign, 0)
		if score < best_score:
			best_score = score
			best = [part]
	if not best.is_empty():
		return best
	if max_parts < 2:
		return []
	for first in candidates:
		if not allow_fans and String(first["shape"]) == "fan":
			continue
		for second in candidates:
			if not allow_fans and String(second["shape"]) == "fan":
				continue
			var total_lanes := int(first["lanes"]) + int(second["lanes"])
			if posmod(total_lanes, 8) != target_mod:
				continue
			if absi(total_lanes) > 8:
				continue
			if (float(first["min_ms"]) + float(second["min_ms"])) * factor >= move_ms:
				continue
			var score := _part_score(first, original_sign, 0) + _part_score(second, original_sign, 1) + 0.25
			if score < best_score:
				best_score = score
				best = [first, second]
	return best


static func _part_score(part: Dictionary, original_sign: float, index: int) -> float:
	var shape := String(part["shape"])
	var lanes := posmod(int(part["lanes"]), 8)
	var score := float(part["length"]) + float(_SHAPE_PENALTY.get(shape, 0.5)) + float(index) * 0.1
	if shape == "circle":
		var path_sign := 1.0 if bool(part["mirrored"]) else -1.0
		if lanes == 0:
			path_sign = 1.0 if bool(part["mirrored"]) else -1.0
		if original_sign != 0.0 and signf(original_sign) != path_sign:
			score += 1.0
	elif lanes != 0 and lanes != 4:
		# 非圆形的段默认顺时针（设计角减小）。
		if original_sign != 0.0 and original_sign > 0.0:
			score += 2.0
	return score


## 把段链转成 Chart 的 trace_pts（x/y 在单位圆内，db 是相对拍）。
## 时间按轨迹长度分配：滑动速度恒定。
static func trace_from_parts(start_angle: float, parts: Array, duration_beats: float, wait_beats: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if parts.is_empty():
		return result
	var poly: Array[Vector2] = []
	var current := start_angle
	for part in parts:
		var points := _shape_points(String(part["shape"]), 0.0, int(part["lanes"]), bool(part["mirrored"]))
		var rotation := deg_to_rad(current - 67.5)
		for point in points:
			var rotated := point.rotated(rotation)
			if not poly.is_empty() and poly[-1].distance_to(rotated) < 0.0001:
				continue
			poly.append(rotated)
		current = fposmod(current - float(part["lanes"]) * 45.0, 360.0)
	if poly.is_empty():
		return result
	poly = _densify_polyline(poly, 12)
	var cumulative: Array[float] = [0.0]
	var total := 0.0
	for i in range(1, poly.size()):
		total += poly[i].distance_to(poly[i - 1])
		cumulative.append(total)
	if total < 0.0001:
		total = 0.0001
	var wait := clampf(wait_beats, 0.0, maxf(0.0, duration_beats - 0.0001))
	var move := maxf(0.001, duration_beats - wait)
	result.append({"x": poly[0].x, "y": poly[0].y, "db": 0.0})
	if wait > 0.0:
		result.append({"x": poly[0].x, "y": poly[0].y, "db": wait})
	for i in range(1, poly.size()):
		result.append({"x": poly[i].x, "y": poly[i].y, "db": wait + move * cumulative[i] / total})
	return result


static func _shape_points(shape: String, start_lane: float, lanes: int, mirrored: bool) -> Array[Vector2]:
	var n := posmod(lanes, 8)
	match shape:
		"straight", "fan":
			return [_lane_point(start_lane), _lane_point(start_lane + float(n))]
		"circle":
			return _circle_points(start_lane, n, mirrored)
		"v":
			return [_lane_point(start_lane), Vector2.ZERO, _lane_point(start_lane + float(n))]
		"u":
			return _u_points(start_lane, n, mirrored)
		"cup":
			return _cup_points(start_lane, n, mirrored)
		"thunder":
			return _thunder_points(start_lane, n, mirrored)
	return [_lane_point(start_lane), _lane_point(start_lane + float(n))]


static func _circle_points(start_lane: float, lanes: int, mirrored: bool) -> Array[Vector2]:
	var start := 22.5 + start_lane * 45.0
	var sweep := 0.0
	if lanes == 0:
		sweep = 360.0 if not mirrored else -360.0
	elif not mirrored:
		sweep = float(lanes) * 45.0
	else:
		sweep = -(360.0 - float(lanes) * 45.0)
	var count := maxi(16, int(ceil(absf(sweep) / 6.0)))
	var result: Array[Vector2] = []
	for i in count + 1:
		result.append(_compass_point(1.0, start + sweep * float(i) / float(count)))
	return result


static func _u_points(start_lane: float, lanes: int, mirrored: bool) -> Array[Vector2]:
	var p0 := _lane_point(start_lane)
	var p1 := p0.lerp(_lane_point(start_lane + (3.0 if mirrored else 5.0)), 0.51)
	var start_angle := 22.5 + start_lane * 45.0
	var end_angle := 22.5 + (start_lane + float(lanes)) * 45.0
	var angle_diff := (start_angle + end_angle) * 0.5
	if absf(float(lanes)) <= (3.0 if mirrored else 4.0):
		angle_diff += 180.0
	var p2 := _compass_point(115.0 / PLAYFIELD_RADIUS, angle_diff)
	var p4 := _lane_point(start_lane + float(lanes))
	var p3 := p4.lerp(_lane_point(start_lane + float(lanes) + (-3.0 if mirrored else 3.0)), 0.51)
	return _chaikin([p0, p1, p2, p3, p4], 2)


static func _cup_points(start_lane: float, lanes: int, mirrored: bool) -> Array[Vector2]:
	var r := 135.0 / PLAYFIELD_RADIUS
	var x := posmod(-lanes, 8) if mirrored else lanes
	var origin_angle := 90.0
	var angle1 := 300.0
	var angle2 := 269.0
	var angle3 := 230.0
	var loop_end: float = float([60.0, 90.0, 180.0, 240.0, 300.0, 330.0, 360.0, 390.0][x])
	var offset := start_lane * 45.0
	if mirrored:
		origin_angle = -origin_angle + 45.0
		angle1 = -angle1 + 45.0
		angle2 = -angle2 + 45.0
		angle3 = -angle3 + 45.0
		loop_end = -loop_end + 45.0
	var loop_origin := _compass_point(r, origin_angle + offset)
	var node0 := _lane_point(start_lane)
	var node1 := loop_origin + _compass_point(r, angle1 + offset)
	var node2 := loop_origin + _compass_point(r, angle2 + offset)
	var node3 := loop_origin + _compass_point(r, angle3 + offset)
	var mid_angle: float = (angle3 + loop_end) * 0.5 + (180.0 if x >= 3 else 0.0) + offset
	var node4 := loop_origin + _compass_point(r, mid_angle)
	var node5 := loop_origin + _compass_point(r, loop_end + offset)
	var node6 := _lane_point(start_lane + float(lanes))
	return _chaikin([node0, node1, node2, node3, node4, node5, node6], 2)


static func _thunder_points(start_lane: float, lanes: int, mirrored: bool) -> Array[Vector2]:
	var lane1 := (3.0 if mirrored else 5.0) + start_lane
	var lane2 := (2.0 if mirrored else 6.0) + start_lane
	var lane3 := (6.0 if mirrored else 2.0) + start_lane
	var lane4 := (7.0 if mirrored else 1.0) + start_lane
	var node0 := _lane_point(start_lane)
	var node1 := _line_intersection(_lane_point(start_lane), _lane_point(lane1), _lane_point(lane2), _lane_point(lane3))
	var node2 := _line_intersection(_lane_point(lane2), _lane_point(lane3), _lane_point(lane4), _lane_point(4.0 + start_lane))
	var node3 := _lane_point(4.0 + start_lane)
	return [node0, node1, node2, node3]


static func _line_intersection(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Vector2:
	var denominator := (b2.x - b1.x) * (a2.y - a1.y) - (b2.y - b1.y) * (a2.x - a1.x)
	if absf(denominator) < 0.000001:
		return (a1 + a2 + b1 + b2) * 0.25
	var mu := ((a1.x - b1.x) * (a2.y - a1.y) - (a1.y - b1.y) * (a2.x - a1.x)) / denominator
	return b1 + (b2 - b1) * mu


static func _lane_point(lane: float, radius: float = 1.0) -> Vector2:
	return _compass_point(radius, 22.5 + lane * 45.0)


static func _compass_point(radius: float, compass_deg: float) -> Vector2:
	var design := deg_to_rad(90.0 - compass_deg)
	return Vector2(cos(design), sin(design)) * radius


static func _chaikin(points: Array[Vector2], iterations: int) -> Array[Vector2]:
	if points.size() < 3:
		return points
	var result := points
	for _iteration in iterations:
		var smoothed: Array[Vector2] = [result[0]]
		for i in range(1, result.size() - 1):
			smoothed.append(result[i - 1].lerp(result[i], 0.25))
			smoothed.append(result[i - 1].lerp(result[i], 0.75))
		smoothed.append(result[-1])
		result = smoothed
	return result


static func _polyline_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## 只补点、不删原点：直线至少 12 个采样，V/折线的拐角保持原样。
static func _densify_polyline(points: Array[Vector2], min_count: int) -> Array[Vector2]:
	var result := points.duplicate()
	while result.size() < min_count:
		var longest := 0.0
		var longest_index := -1
		for i in range(1, result.size()):
			var distance: float = result[i].distance_to(result[i - 1])
			if distance > longest:
				longest = distance
				longest_index = i
		if longest_index < 0 or longest < 0.0001:
			break
		result.insert(longest_index, result[longest_index - 1].lerp(result[longest_index], 0.5))
	return result
