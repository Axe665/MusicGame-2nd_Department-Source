class_name Note
extends RefCounted

const TYPES := ["tap", "hold", "path", "trace", "anchor", "bell"]

var id: int = 1
var type: String = "tap"
var beat: float = 0.0
var angle: float = 0.0
var width: float = 60.0
var end_beat: float = 0.0
var wait_beat: float = 0.0
var tail_angle: float = 0.0
var tail_width: float = 45.0
var hold: bool = true
var move_px: float = 120.0
var radius: float = 44.0
var tolerance: float = 0.24
var samples_per_beat: float = 4.0
var path_style: String = "arc"
var path_gaps: Array[Dictionary] = []
var visual_pts: Array[Dictionary] = []
var trace_style: String = "wipe"
var space: String = "ring"
var plane_x: float = 0.5
var plane_y: float = 0.5
var plane_radius: float = 0.10
var trace_pts: Array[Dictionary] = []
var anchor_pair: int = -1
var pair_id: String = ""
var color: int = 0
var lock: bool = false
var center_u: float = 0.25


func _init(p_type: String = "tap", p_beat: float = 0.0, p_angle: float = 0.0, p_width: float = 60.0) -> void:
	type = p_type
	beat = p_beat
	angle = p_angle
	width = p_width


func duration() -> float:
	return maxf(0.0, end_beat - beat)


func is_point_target() -> bool:
	return type in ["tap", "hold", "path", "anchor"]


func path_local_at(relative_beat: float) -> Vector2:
	var total := duration()
	if total <= 0.000001:
		return _unit_from_angle(angle)
	var wait := clampf(wait_beat, 0.0, maxf(0.0, total - 0.000001))
	var move_total := maxf(0.000001, total - wait)
	var p := clampf((relative_beat - wait) / move_total, 0.0, 1.0)
	if path_style == "star":
		return _star_local(p)
	return _unit_from_angle(path_angle_at(relative_beat))


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
	# 五角星表现层：5 条弦，头尾判定仍各自独立。
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
	if space != "ring":
		data["space"] = space
		data["plane_x"] = snappedf(plane_x, 0.0001)
		data["plane_y"] = snappedf(plane_y, 0.0001)
		data["plane_radius"] = snappedf(plane_radius, 0.0001)
	match type:
		"hold":
			data["end_beat"] = snappedf(end_beat, 0.001)
			data["hold"] = hold
			if not visual_pts.is_empty():
				data["visual"] = _points_to_dict(visual_pts)
		"path":
			data["end_beat"] = snappedf(end_beat, 0.001)
			if wait_beat > 0.0:
				data["wait"] = snappedf(wait_beat, 0.001)
			data["tail_angle"] = snappedf(tail_angle, 0.001)
			data["tail_width"] = snappedf(tail_width, 0.001)
			data["tolerance"] = snappedf(tolerance, 0.001)
			data["samples"] = snappedf(samples_per_beat, 0.001)
			if path_style != "arc":
				data["path_style"] = path_style
			if not path_gaps.is_empty():
				data["path_gaps"] = _ranges_to_array(path_gaps)
			if not visual_pts.is_empty():
				data["visual"] = _points_to_dict(visual_pts)
		"trace":
			data["end_beat"] = snappedf(end_beat, 0.001)
			if wait_beat > 0.0:
				data["wait"] = snappedf(wait_beat, 0.001)
			data["move"] = snappedf(move_px, 0.001)
			data["trace"] = _points_to_dict(trace_pts)
			if trace_style != "wipe":
				data["trace_style"] = trace_style
		"anchor":
			if anchor_pair >= 0:
				data["pair"] = anchor_pair
			if not pair_id.is_empty():
				data["pair_id"] = pair_id
		"bell":
			data["center_u"] = snappedf(center_u, 0.0001)
			data["radius"] = snappedf(radius, 0.001)
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
	note.move_px = float(raw.get("move", 120.0))
	note.radius = float(raw.get("radius", 24.0))
	note.tolerance = float(raw.get("tolerance", 0.24))
	note.samples_per_beat = float(raw.get("samples", 4.0))
	note.path_style = String(raw.get("path_style", "arc"))
	note.trace_style = String(raw.get("trace_style", "wipe"))
	note.space = String(raw.get("space", "ring"))
	note.plane_x = float(raw.get("plane_x", 0.5))
	note.plane_y = float(raw.get("plane_y", 0.5))
	note.plane_radius = float(raw.get("plane_radius", 0.10))
	note.anchor_pair = int(raw.get("pair", -1))
	note.pair_id = String(raw.get("pair_id", ""))
	note.center_u = float(raw.get("center_u", 0.25))
	if raw.has("visual"):
		note.visual_pts = _points_from_array(raw.get("visual", []))
	if raw.has("path_gaps"):
		note.path_gaps = _ranges_from_array(raw.get("path_gaps", []))
	if raw.has("trace"):
		note.trace_pts = _points_from_array(raw.get("trace", []))
	return note


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


static func _points_from_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in raw:
		if item is Dictionary:
			var point := {}
			for key in item.keys():
				point[String(key)] = float(item[key])
			result.append(point)
	return result
