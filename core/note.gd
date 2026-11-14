class_name Note
extends RefCounted

const TYPES := ["tap", "hold", "path", "seek", "anchor", "bell"]

## 本作把"长度"统一到 l 上：l = 旧版 tap 与判定环重合时的条带长度，
## 也就是 note.width 这个角度（默认 60°）画出来的弧长。
##   普通 Tap / Hold 头 = 0.5 l
##   大小 Tap（sized）= size_ratio × l，size_ratio ∈ [0, 1.5]
## 数值同时用于绘制与判定，看到的长度就是能打到的长度。
const TAP_LENGTH_SCALE := 0.5
const HOLD_HEAD_LENGTH_SCALE := 0.5
## 金键的可见/判定弧宽标准：和 Tap 到环时的可见长度同级（62° 的 Tap 可见 31°）。
## 旧谱和导出的 Bell 都是 45°，载入时统一收敛，避免一条金键比 Tap 长 45%。
const BELL_MIN_WIDTH := 24.0
const BELL_MAX_WIDTH := 30.0
## 舞萌星星的默认深蓝色。
const DEFAULT_PATH_COLOR := Color(0.55, 0.75, 1.0)
const SIZED_TAP_MIN := 0.0
const SIZED_TAP_MAX := 1.5
## 出现时（环心）的长度 = 1/6 l，飞向判定环的过程中长到 1 l。
const SPAWN_LENGTH_RATIO := 1.0 / 6.0
## 自定义颜色与背景的 WCAG 对比度低于这个值就提示“看不清”，但不阻止保存。
const MIN_CONTRAST := 2.5

var id: int = 1
var type: String = "tap"
var beat: float = 0.0
var angle: float = 0.0
var width: float = 60.0
## 大小 Tap：sized 为 true 时长度取 size_ratio × l，否则按 TAP_LENGTH_SCALE 固定。
var sized: bool = false
var size_ratio: float = 1.0
var end_beat: float = 0.0
var wait_beat: float = 0.0
var tail_angle: float = 0.0
var tail_width: float = 45.0
var hold: bool = true
var hold_style: String = "straight"
var radius: float = 44.0
var tolerance: float = 0.24
var samples_per_beat: float = 4.0
var path_speed: float = 1.0
var path_style: String = "arc"
var path_gaps: Array[Dictionary] = []
var visual_pts: Array[Dictionary] = []
## New Path editor controls. `path_controls_set` keeps legacy charts' explicit
## trace points untouched until the author edits one of these values.
var path_centrifuge: float = 0.72
var path_axis: float = 0.0
var path_controls_set: bool = false
var path_head_local: Vector2 = Vector2.INF
var path_part: int = 0
var path_prev_id: int = -1
var path_next_id: int = -1
## Transient preview flag: one synthetic note represents a whole part chain.
var path_chain: bool = false
## Transient: true when loaded from legacy Path JSON; ChartIO normalizes it.
var path_legacy: bool = false
var space: String = "ring"
var trace_pts: Array[Dictionary] = []
var anchor_pair: int = -1
var pair_id: String = ""
var color: int = 0
## 谱师自定义的星星颜色（只对 Path 生效）；默认 false 表示用统一绿色。
var has_custom_color: bool = false
var custom_color: Color = DEFAULT_PATH_COLOR
var lock: bool = false
var center_u: float = 0.25
## Seek: 0 = outward (wheel up), 1 = inward (wheel down).
var seek_orien: int = 0
## Transient editor state: freshly placed Seek waiting for W/S orientation.
var seek_pending: bool = false
## 兼容字段：所有 Bell 都在判定环上（舞萌 C 触也并入外环），读取旧谱时统一归 1.0。
var bell_radius: float = 1.0


func _init(p_type: String = "tap", p_beat: float = 0.0, p_angle: float = 0.0, p_width: float = 60.0) -> void:
	type = p_type
	beat = p_beat
	angle = p_angle
	width = p_width
	# 单点音符的结束拍必须等于开始拍。以前默认 0，导致 tap 的 end_beat=0，
	# 判定里按“结束时间”做过期检查时会把它们当成 0ms：谱面播到 6 秒后，
	# 所有 tap 都被判定为“早就过期”而跳过（表现就是突然整段没有判定）。
	end_beat = p_beat
	# 金键以前是金币（宽度 0）。没有弧宽就画不出键，旧数据统一补成标准宽度；
	# 45°/180° 的历史值也在这里收敛，绘制、判定、编辑器看到的是同一个长度。
	if type == "bell":
		width = clampf(width if width > 0.0 else BELL_MAX_WIDTH, BELL_MIN_WIDTH, BELL_MAX_WIDTH)
	if type == "path":
		space = "plane"


func duration() -> float:
	return maxf(0.0, end_beat - beat)


## 相对 l 的倍率。Path / Trace / Anchor / Bell 不参与长度系统，返回 1。
func length_ratio() -> float:
	if type == "tap":
		return clampf(size_ratio, SIZED_TAP_MIN, SIZED_TAP_MAX) if sized else TAP_LENGTH_SCALE
	if type == "hold":
		return HOLD_HEAD_LENGTH_SCALE
	return 1.0


## 到判定环时的实际角度宽度。绘制与判定都走这里，保证"看到多长 = 能打多长"。
func arc_width() -> float:
	return maxf(0.0, width * length_ratio())


## 金键的有效弧宽。数据已收敛，这里再兜底一次，编辑器直接改 width 也不会越界。
func bell_width() -> float:
	return clampf(width, BELL_MIN_WIDTH, BELL_MAX_WIDTH)


## 大小 Tap 只允许 Tap 使用；给编辑器一个统一的入口。
func set_size_ratio(value: float) -> void:
	sized = true
	size_ratio = clampf(snappedf(value, 0.01), SIZED_TAP_MIN, SIZED_TAP_MAX)


func is_point_target() -> bool:
	return type in ["tap", "hold", "path", "anchor"]


func path_local_at(relative_beat: float) -> Vector2:
	var total := duration()
	if total <= 0.000001:
		return _unit_from_angle(angle)
	var p := clampf(relative_beat / total, 0.0, 1.0)
	# Path 只允许平面：有显式二维点时按点走，旧环 Path 则迁移成
	# 半径 1.0 → 0.72 的平面弧，头仍在环上。
	if not trace_pts.is_empty():
		return trace_local_at(relative_beat)
	var a := path_angle_at(relative_beat)
	return _unit_from_angle(a) * lerpf(1.0, 0.72, p)


## trace_pts 在相对拍处的位置。点的 x/y 是“环半径 = 1.0”的设计坐标：
## 长度 1.0 就是环外缘，因此环上与平面上的 trace 用的是同一份数据。
func trace_local_at(relative_beat: float) -> Vector2:
	if trace_pts.is_empty():
		return Vector2.ZERO
	var target := clampf(relative_beat, 0.0, duration())
	var previous: Dictionary = trace_pts[0]
	if target <= float(previous.get("db", 0.0)):
		return Vector2(float(previous.get("x", 0.0)), float(previous.get("y", 0.0)))
	for i in range(1, trace_pts.size()):
		var point: Dictionary = trace_pts[i]
		var db := float(point.get("db", 0.0))
		if target <= db:
			var last_db := float(previous.get("db", 0.0))
			var span := db - last_db
			var q := 0.0 if span <= 0.000001 else (target - last_db) / span
			return Vector2(
				lerpf(float(previous.get("x", 0.0)), float(point.get("x", 0.0)), q),
				lerpf(float(previous.get("y", 0.0)), float(point.get("y", 0.0)), q)
			)
		previous = point
	return Vector2(float(previous.get("x", 0.0)), float(previous.get("y", 0.0)))


func path_tail_local() -> Vector2:
	return path_local_at(duration())


## Imported traces encode the wait as coincident opening points. Animation
## already applies wait_beat, so traverse only the moving part of that geometry.
func path_motion_beat(progress: float) -> float:
	var start := 0.0
	if trace_pts.size() >= 2:
		var head := Vector2(float(trace_pts[0].get("x", 0.0)), float(trace_pts[0].get("y", 0.0)))
		for point in trace_pts:
			var local := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
			if local.distance_squared_to(head) > 0.00000001:
				break
			start = clampf(float(point.get("db", 0.0)), 0.0, duration())
	return lerpf(start, duration(), clampf(progress, 0.0, 1.0))


func path_head_point() -> Vector2:
	if path_part > 0 and path_head_local.is_finite():
		return path_head_local
	return _unit_from_angle(angle)


## Fills the new editor values from the current trace for legacy charts. It does
## not rewrite the trace, so opening an old chart keeps its original shape.
func derive_path_controls() -> void:
	if path_controls_set:
		return
	var tail := path_tail_local()
	path_centrifuge = clampf(tail.length(), 0.0, 1.0)
	var chord := tail - path_head_point()
	var length := chord.length()
	if length > 0.0001:
		var normal := Vector2(-chord.y, chord.x) / length
		var middle := path_local_at(duration() * 0.5)
		path_axis = clampf((middle - (path_head_point() + tail) * 0.5).dot(normal) / length, -2.0, 2.0)
	else:
		path_axis = 0.0


func set_path_centrifuge(value: float) -> void:
	path_centrifuge = clampf(snappedf(value, 0.01), 0.0, 1.0)
	generate_path_shape()


func set_path_axis(value: float) -> void:
	path_axis = clampf(snappedf(value, 0.01), -2.0, 2.0)
	generate_path_shape()


## Rebuilds the Path as a quadratic trajectory from the head to the tail.
## `path_axis` is the signed normal offset of the trajectory midpoint, measured
## in units of the head-tail chord. A zero axis is a straight line; a negative
## axis mirrors the curve across that chord.
func generate_path_shape() -> void:
	path_controls_set = true
	visual_pts.clear()
	var head := path_head_point()
	var tail := _unit_from_angle(tail_angle) * clampf(path_centrifuge, 0.0, 1.0)
	var total := duration()
	var chord := tail - head
	var length := chord.length()
	if length <= 0.0001:
		trace_pts = [
			{"x": head.x, "y": head.y, "db": 0.0},
			{"x": head.x, "y": head.y, "db": total},
		]
		path_axis = 0.0
		return
	var normal := Vector2(-chord.y, chord.x) / length
	var middle := (head + tail) * 0.5
	var axis := clampf(path_axis, -2.0, 2.0)
	if (middle + normal * (axis * length)).length() > 1.000001:
		axis = _path_axis_limit(middle, normal, length, axis)
		path_axis = axis
	var control := middle + normal * (2.0 * axis * length)
	trace_pts = []
	var samples := 24
	for i in samples + 1:
		var t := float(i) / float(samples)
		var p := head * ((1.0 - t) * (1.0 - t)) + control * (2.0 * (1.0 - t) * t) + tail * (t * t)
		trace_pts.append({
			"x": snappedf(p.x, 0.000001),
			"y": snappedf(p.y, 0.000001),
			"db": snappedf(total * t, 0.000001),
		})


## Nearest same-side axis where the trajectory midpoint lands on radius 1.
func _path_axis_limit(middle: Vector2, normal: Vector2, length: float, desired: float) -> float:
	var a := length * length
	var b := 2.0 * length * middle.dot(normal)
	var c := middle.length_squared() - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return 0.0
	var root := sqrt(disc)
	var best := 0.0
	var found := false
	for candidate in [(-b + root) / (2.0 * a), (-b - root) / (2.0 * a)]:
		if desired >= 0.0 and candidate < 0.0:
			continue
		if desired < 0.0 and candidate > 0.0:
			continue
		if absf(candidate) > absf(desired) + 0.0001:
			continue
		if not found or absf(candidate) < absf(best):
			best = candidate
			found = true
	return best if found else 0.0


func path_angle_at(relative_beat: float) -> float:
	var total := duration()
	if total <= 0.000001:
		return angle
	var wait := clampf(wait_beat, 0.0, maxf(0.0, total - 0.000001))
	var move_total := maxf(0.000001, total - wait)
	var p := clampf((relative_beat - wait) / move_total, 0.0, 1.0)
	if visual_pts.is_empty():
		return angle + _short_delta(angle, tail_angle) * p
	var points: Array[Dictionary] = [{"db": 0.0, "da": 0.0}]
	for point in visual_pts:
		points.append(point)
	points.append({"db": total, "da": _short_delta(angle, tail_angle)})
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("db", 0.0)) < float(b.get("db", 0.0)))
	var target := p * total
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var db_a := float(a.get("db", 0.0))
		var db_b := float(b.get("db", 0.0))
		if target >= db_a and target <= db_b:
			var span := maxf(0.000001, db_b - db_a)
			var t := (target - db_a) / span
			var da_a := float(a.get("da", 0.0))
			var da_b := float(b.get("da", 0.0))
			return angle + lerpf(da_a, da_b, t)
	return tail_angle


func _unit_from_angle(degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(cos(radians), sin(radians))


func _star_local(p: float) -> Vector2:
	# 保留给旧谱面读取；新的 Path 一律平面，不再生成五角星。
	var tips: Array[Vector2] = []
	for k in 5:
		tips.append(_unit_from_angle(angle - 90.0 + float(k) * 72.0) * 0.78)
	var order: Array[int] = [0, 2, 4, 1, 3, 0]
	var cursor := clampf(p, 0.0, 1.0) * 5.0
	var index := mini(int(cursor), 4)
	return tips[order[index]].lerp(tips[order[index + 1]], cursor - float(index))


func path_sample_beats() -> Array[float]:
	var result: Array[float] = []
	var total := duration()
	if total <= 0.000001:
		return result
	var density := maxf(0.25, samples_per_beat)
	var count := maxi(int(ceil(total * density)), 1)
	for i in count + 1:
		var rel := total * float(i) / float(count)
		if erased_at(rel):
			continue
		result.append(beat + rel)
	return result


func erased_at(relative_beat: float) -> bool:
	var total := duration()
	if total <= 0.000001 or path_gaps.is_empty():
		return false
	var p := clampf(relative_beat / total, 0.0, 1.0)
	for gap in path_gaps:
		var a := clampf(float(gap.get("from", 0.0)), 0.0, 1.0)
		var b := clampf(float(gap.get("to", 0.0)), 0.0, 1.0)
		if p >= minf(a, b) and p <= maxf(a, b):
			return true
	return false


func _short_delta(from_angle: float, to_angle: float) -> float:
	var delta := fposmod(to_angle - from_angle + 180.0, 360.0) - 180.0
	return delta


func mirror_u() -> void:
	## Mirror by rotating the note 180° around the ring centre: angle + 180,
	## wrapped back into 0–360. Time, widths and judging radii are unchanged.
	angle = fposmod(angle + 180.0, 360.0)
	tail_angle = fposmod(tail_angle + 180.0, 360.0)
	center_u = fposmod(center_u + 0.5, 1.0)
	for point in trace_pts:
		# Plane/trace coordinates are centred on the ring: a 180° rotation
		# negates both axes.
		point["x"] = -float(point.get("x", 0.0))
		point["y"] = -float(point.get("y", 0.0))
	if path_part > 0 and path_head_local.is_finite():
		path_head_local = -path_head_local


func to_dict() -> Dictionary:
	var data := {
		"id": id,
		"type": type,
		"beat": snappedf(beat, 0.001),
		"angle": snappedf(angle, 0.001),
		"width": snappedf(width, 0.001),
		"color": color,
		"lock": lock,
	}
	match type:
		"tap":
			if sized:
				data["sized"] = true
				data["size"] = snappedf(size_ratio, 0.01)
		"hold":
			data["end_beat"] = snappedf(end_beat, 0.001)
			data["hold"] = hold
			if hold_style != "straight":
				data["hold_style"] = hold_style
			if not visual_pts.is_empty():
				data["visual"] = _points_to_dict(visual_pts)
		"path":
			# 谱师自定义的星星颜色（RGB 0–255）；不写就用默认绿。
			if has_custom_color:
				data["rgb"] = [int(round(custom_color.r * 255.0)), int(round(custom_color.g * 255.0)), int(round(custom_color.b * 255.0))]
			data["space"] = "plane"
			data["end_beat"] = snappedf(end_beat, 0.001)
			if wait_beat > 0.0:
				data["wait"] = snappedf(wait_beat, 0.001)
			data["tail_angle"] = snappedf(tail_angle, 0.001)
			data["tail_width"] = snappedf(tail_width, 0.001)
			data["tolerance"] = snappedf(tolerance, 0.001)
			data["samples"] = snappedf(samples_per_beat, 0.001)
			if path_speed != 1.0:
				data["speed"] = snappedf(path_speed, 0.001)
			if path_style != "arc":
				data["path_style"] = path_style
			if not path_gaps.is_empty():
				data["path_gaps"] = _ranges_to_array(path_gaps)
			if not visual_pts.is_empty():
				data["visual"] = _points_to_dict(visual_pts)
			if not trace_pts.is_empty():
				data["trace"] = _points_to_dict(trace_pts)
			if path_controls_set:
				data["centrifuge"] = snappedf(path_centrifuge, 0.01)
				data["axis"] = snappedf(path_axis, 0.01)
			if path_part != 0 or path_prev_id >= 0 or path_next_id >= 0:
				data["part"] = path_part
				data["prev_part"] = path_prev_id
				data["next_part"] = path_next_id
			if path_part > 0 and path_head_local.is_finite():
				data["head_x"] = snappedf(path_head_local.x, 0.0001)
				data["head_y"] = snappedf(path_head_local.y, 0.0001)
		"seek":
			data["orien"] = 1 if seek_orien == 1 else 0
		"anchor":
			if anchor_pair >= 0:
				data["pair"] = anchor_pair
			if not pair_id.is_empty():
				data["pair_id"] = pair_id
		"bell":
			data["center_u"] = snappedf(center_u, 0.0001)
			data["radius"] = snappedf(radius, 0.001)
			if absf(bell_radius - 1.0) > 0.0001:
				data["bell_radius"] = snappedf(bell_radius, 0.001)
	return data


static func from_dict(raw: Dictionary) -> Note:
	var note := Note.new(
		String(raw.get("type", "tap")),
		float(raw.get("beat", 0.0)),
		float(raw.get("angle", 0.0)),
		float(raw.get("width", 60.0))
	)
	note.id = int(raw.get("id", 1))
	note.color = int(raw.get("color", 0))
	note.lock = bool(raw.get("lock", false))
	note.end_beat = float(raw.get("end_beat", note.beat))
	note.wait_beat = float(raw.get("wait", 0.0))
	note.tail_angle = float(raw.get("tail_angle", note.angle))
	note.tail_width = float(raw.get("tail_width", note.width))
	note.hold = bool(raw.get("hold", true))
	note.hold_style = String(raw.get("hold_style", "straight"))
	note.radius = float(raw.get("radius", 24.0))
	note.tolerance = float(raw.get("tolerance", 0.24))
	note.samples_per_beat = float(raw.get("samples", 4.0))
	note.path_speed = float(raw.get("speed", 1.0))
	note.path_style = String(raw.get("path_style", "arc"))
	note.space = "plane" if note.type == "path" else "ring"
	note.anchor_pair = int(raw.get("pair", -1))
	note.pair_id = String(raw.get("pair_id", ""))
	note.center_u = float(raw.get("center_u", 0.25))
	note.bell_radius = float(raw.get("bell_radius", 1.0))
	note.sized = bool(raw.get("sized", false)) and note.type == "tap"
	note.size_ratio = clampf(float(raw.get("size", 1.0)), SIZED_TAP_MIN, SIZED_TAP_MAX)
	if raw.has("rgb"):
		var rgb: Array = raw.get("rgb", [])
		if rgb.size() >= 3:
			note.custom_color = Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0)
			note.has_custom_color = true
	if raw.has("visual"):
		note.visual_pts = _points_from_array(raw.get("visual", []))
	if raw.has("path_gaps"):
		note.path_gaps = _ranges_from_array(raw.get("path_gaps", []))
	if raw.has("trace"):
		note.trace_pts = _points_from_array(raw.get("trace", []))
	if note.type == "seek":
		note.seek_orien = 1 if int(raw.get("orien", 0)) == 1 else 0
		note.angle = 0.0
		note.width = 360.0
		note.end_beat = note.beat
	if note.type == "path":
		if raw.has("centrifuge"):
			note.path_centrifuge = clampf(float(raw.get("centrifuge", 0.72)), 0.0, 1.0)
			note.path_controls_set = true
		if raw.has("axis"):
			note.path_axis = clampf(float(raw.get("axis", 0.0)), -2.0, 2.0)
			note.path_controls_set = true
		note.path_part = int(raw.get("part", 0))
		note.path_prev_id = int(raw.get("prev_part", -1))
		note.path_next_id = int(raw.get("next_part", -1))
		if raw.has("head_x") and raw.has("head_y"):
			note.path_head_local = Vector2(float(raw.get("head_x", 0.0)), float(raw.get("head_y", 0.0)))
		if note.path_controls_set and note.trace_pts.is_empty():
			note.generate_path_shape()
		elif not note.path_controls_set:
			note.derive_path_controls()
			note.path_controls_set = true
			note.path_legacy = true
			note.visual_pts.clear()
			note.path_style = "arc"
			if note.trace_pts.is_empty():
				# Legacy angle-only Path: migrate it immediately to the new
				# axis/centrifuge representation. Explicit legacy traces keep
				# their points while gaining the new editor values.
				note.generate_path_shape()
	return note


## 旧版 Trace 的 x/y 是 0..1 的屏幕比例（老预览窗直接按像素铺开）。
## 这里换算成“环半径 = 1.0”的设计坐标，并按 16:9 的舞台铺满环内。
static func _ranges_to_array(ranges: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in ranges:
		result.append({"from": float(item.get("from", 0.0)), "to": float(item.get("to", 0.0))})
	return result


static func _ranges_from_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in raw:
		if item is Dictionary:
			result.append({"from": float(item.get("from", 0.0)), "to": float(item.get("to", 0.0))})
	return result


static func _points_to_dict(points: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in points:
		result.append(point.duplicate())
	return result


static func _code_num(value: float) -> String:
	return str(snappedf(value, 0.001))


## Compact v1 chart code for one note. Path chains are serialized as one line by
## ChartIO; this produces a single-part line when called directly.
func to_code() -> String:
	var b := _code_num(beat)
	var a := _code_num(angle)
	match type:
		"tap":
			# 旧格式 [id]tap(beat,angle)；宽度/大小 Tap 只在非默认时追加。
			if sized:
				return "[%d]tap(%s,%s,%s,1,%s)" % [id, b, a, _code_num(width), _code_num(size_ratio)]
			if not is_equal_approx(width, 60.0):
				return "[%d]tap(%s,%s,%s)" % [id, b, a, _code_num(width)]
			return "[%d]tap(%s,%s)" % [id, b, a]
		"hold":
			# 旧格式 [id]hold(beat,end,angle)；非默认宽度追加第 4 段。
			if not is_equal_approx(width, 60.0):
				return "[%d]hold(%s,%s,%s,%s)" % [id, b, _code_num(end_beat), a, _code_num(width)]
			return "[%d]hold(%s,%s,%s)" % [id, b, _code_num(end_beat), a]
		"seek":
			return "[%d]seek(%s,%d)" % [id, b, 1 if seek_orien == 1 else 0]
		"anchor":
			if anchor_pair >= 0:
				return "[%d]anchor(%s,%s,%s,%d)" % [id, b, a, pair_id, anchor_pair]
			return "[%d]anchor(%s,%s,%s)" % [id, b, a, pair_id]
		"bell":
			# 旧格式 [id]bell(beat,angle)；弧宽/半径非默认时追加，半径需要宽度占位。
			var bell_width_value := bell_width()
			var bell_radius_value := snappedf(radius, 0.001)
			var has_width := not is_equal_approx(bell_width_value, BELL_MAX_WIDTH)
			var has_radius := not is_equal_approx(bell_radius_value, 26.0)
			if has_width and has_radius:
				return "[%d]bell(%s,%s,%s,%s)" % [id, b, a, _code_num(bell_width_value), _code_num(bell_radius_value)]
			if has_width:
				return "[%d]bell(%s,%s,%s)" % [id, b, a, _code_num(bell_width_value)]
			if has_radius:
				return "[%d]bell(%s,%s,%s,%s)" % [id, b, a, _code_num(BELL_MAX_WIDTH), _code_num(bell_radius_value)]
			return "[%d]bell(%s,%s)" % [id, b, a]
		"path":
			return "[%d]path{%s}" % [id, path_part_code()]
	return ""


## Optional final field preserves waiting time while keeping old Path codes valid.
func path_part_code() -> String:
	var fields := "part%d,%s,%s,%s,%s,%s,%s" % [path_part, _code_num(beat),
		_code_num(angle), _code_num(end_beat), _code_num(tail_angle),
		_code_num(path_centrifuge), _code_num(path_axis)]
	if wait_beat > 0.0:
		fields += "," + _code_num(clampf(wait_beat, 0.0, maxf(0.0, duration() - 0.001)))
	return "(" + fields + ")"


static func from_code(code: String) -> Note:
	var text := code.strip_edges()
	if not text.begins_with("["):
		return null
	var close := text.find("]")
	if close <= 1:
		return null
	var id := int(text.substr(1, close - 1))
	var rest := text.substr(close + 1)
	var open := rest.find("(")
	if open < 0:
		return null
	var kind := rest.substr(0, open).strip_edges()
	var body := rest.substr(open + 1)
	if body.ends_with(")"):
		body = body.substr(0, body.length() - 1)
	var parts := body.split(",", true)
	var note := Note.new(kind, 0.0, 0.0, 60.0)
	note.id = id
	match kind:
		"tap":
			note.beat = float(parts[0]) if parts.size() > 0 else 0.0
			note.angle = float(parts[1]) if parts.size() > 1 else 0.0
			if parts.size() > 2:
				note.width = float(parts[2])
			if parts.size() > 3:
				note.sized = int(parts[3]) == 1
			if parts.size() > 4:
				note.size_ratio = clampf(float(parts[4]), SIZED_TAP_MIN, SIZED_TAP_MAX)
		"hold":
			note.beat = float(parts[0]) if parts.size() > 0 else 0.0
			note.end_beat = float(parts[1]) if parts.size() > 1 else note.beat
			note.angle = float(parts[2]) if parts.size() > 2 else 0.0
			if parts.size() > 3:
				note.width = float(parts[3])
		"seek":
			note.beat = float(parts[0]) if parts.size() > 0 else 0.0
			note.end_beat = note.beat
			note.seek_orien = 1 if parts.size() > 1 and int(parts[1]) == 1 else 0
			note.angle = 0.0
			note.width = 360.0
		"anchor":
			note.beat = float(parts[0]) if parts.size() > 0 else 0.0
			note.end_beat = note.beat
			note.angle = float(parts[1]) if parts.size() > 1 else 0.0
			note.pair_id = parts[2].strip_edges() if parts.size() > 2 else ""
			note.width = 0.0
			if parts.size() > 3:
				note.anchor_pair = int(parts[3])
		"bell":
			note.beat = float(parts[0]) if parts.size() > 0 else 0.0
			note.end_beat = note.beat
			note.angle = float(parts[1]) if parts.size() > 1 else 0.0
			if parts.size() > 2:
				note.width = float(parts[2])
			note.center_u = fposmod(note.angle / 360.0, 1.0)
			note.radius = 26.0
			if parts.size() > 3:
				note.radius = float(parts[3])
		_:
			return null
	return note


## Parse a Path chain line into part notes. The root keeps `[id]`; subsequent
## parts receive deterministic ids derived from the root id.
static func path_parts_from_code(code: String) -> Array[Note]:
	var result: Array[Note] = []
	var text := code.strip_edges()
	var close := text.find("]")
	if close <= 1:
		return result
	var root_id := int(text.substr(1, close - 1))
	var open := text.find("{")
	var end := text.rfind("}")
	if open < 0 or end <= open:
		return result
	var body := text.substr(open + 1, end - open - 1)
	var segments := body.split(";", true)
	var previous: Note = null
	for index in segments.size():
		var segment := segments[index].strip_edges()
		if segment.begins_with("("):
			segment = segment.substr(1)
		if segment.ends_with(")"):
			segment = segment.substr(0, segment.length() - 1)
		var fields := segment.split(",", true)
		if fields.size() < 7:
			continue
		# fields[0] is partN; fields[7] is optional waiting time in beats.
		var number := int(fields[0].replace("part", ""))
		var note := Note.new("path", float(fields[1]), float(fields[2]), 60.0)
		note.id = root_id if index == 0 else root_id + 1000 * index
		note.path_part = number
		note.end_beat = float(fields[3])
		note.wait_beat = clampf(float(fields[7]), 0.0, maxf(0.0, note.duration() - 0.001)) if fields.size() > 7 else 0.0
		note.tail_angle = float(fields[4])
		note.path_centrifuge = clampf(float(fields[5]), 0.0, 1.0)
		note.path_axis = clampf(float(fields[6]), -2.0, 2.0)
		note.path_controls_set = true
		note.width = 60.0
		note.tail_width = 45.0
		note.tolerance = 0.24
		note.samples_per_beat = 4.0
		if previous != null:
			note.path_prev_id = previous.id
			note.path_head_local = previous.path_tail_local()
			note.angle = rad_to_deg(atan2(note.path_head_local.y, note.path_head_local.x))
			previous.path_next_id = note.id
		else:
			note.path_part = 0
		note.generate_path_shape()
		result.append(note)
		previous = note
	return result


static func _points_from_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in raw:
		if item is Dictionary:
			var point := {}
			for key in item.keys():
				point[String(key)] = float(item[key])
			result.append(point)
	return result


# ---------------------------------------------------------------- 自定义颜色


func supports_custom_color() -> bool:
	return type in ["tap", "hold", "path"]


## 最终显示色：单音符覆盖 > 配色组 > 类型默认色。
func resolved_color(chart: Chart, fallback: Color) -> Color:
	if has_custom_color:
		return custom_color
	if color > 0 and chart != null:
		var picked := chart.palette_color(color, type)
		if picked.a > 0.0:
			return picked
	return fallback


static func relative_luminance(color: Color) -> float:
	return 0.2126 * _channel_luminance(color.r) + 0.7152 * _channel_luminance(color.g) + 0.0722 * _channel_luminance(color.b)


static func _channel_luminance(value: float) -> float:
	var channel := clampf(value, 0.0, 1.0)
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


## WCAG 对比度（1–21）。低于 MIN_CONTRAST 时只提示，不阻止保存。
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
