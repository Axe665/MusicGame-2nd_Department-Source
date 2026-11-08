class_name SimaiSlide
extends RefCounted

## simai 星星几何（设计坐标，环半径 = 1.0，0° = 右，逆时针）。
## 按钮 1 在 90°（上），顺时针每键 45°。
##
## p/q = U 型，pp/qq = Cup 型，s/z = 闪电，V = 经过点的大 V，
## w = 扇形（这里只取中轴，三条尾巴不画），其余是直线 / 外周弧 / 过圆心 v。
## Sentakki 的 U/Cup/Thunder 用 22.5° 起的道坐标，这里整体 +22.5° 对齐本作按钮。

const BUTTON_STEP := 45.0


static func button_angle(button: int) -> float:
	return fposmod(90.0 - float(button - 1) * BUTTON_STEP, 360.0)


static func button_point(button: int, radius: float = 1.0) -> Vector2:
	var angle := deg_to_rad(button_angle(button))
	return Vector2(cos(angle), sin(angle)) * radius


## segments: [{shape: "-", end: 5, via: 3}, ...]，按顺序首尾相接。
static func build(start_button: int, segments: Array) -> Array[Vector2]:
	var points: Array[Vector2] = [button_point(start_button)]
	var current := start_button
	for raw in segments:
		var segment: Dictionary = raw
		var shape := String(segment.get("shape", "-"))
		var end_button := int(segment.get("end", current))
		var via_button := int(segment.get("via", 0))
		var start_lane := current - 1
		var lanes := posmod(end_button - current, 8)
		var shape_points: Array[Vector2] = []
		match shape:
			"p":
				shape_points = _rotated(SentakkiSlide._u_points(start_lane, lanes, false))
			"q":
				shape_points = _rotated(SentakkiSlide._u_points(start_lane, lanes, true))
			"pp":
				shape_points = _rotated(SentakkiSlide._cup_points(start_lane, lanes, false))
			"qq":
				shape_points = _rotated(SentakkiSlide._cup_points(start_lane, lanes, true))
			"s":
				shape_points = _thunder(start_lane, end_button, false)
			"z":
				shape_points = _thunder(start_lane, end_button, true)
			"v":
				shape_points = [button_point(current), Vector2.ZERO, button_point(end_button)]
			"V":
				shape_points = [button_point(current), button_point(via_button), button_point(end_button)]
			"^", ">", "<":
				shape_points = _arc(current, end_button, shape)
			_:
				shape_points = [button_point(current), button_point(end_button)]
		for point in shape_points:
			if points.is_empty() or points[-1].distance_to(point) > 0.0001:
				points.append(point)
		current = end_button
	for i in points.size():
		if points[i].length() > 1.0:
			points[i] = points[i].normalized()
	return SentakkiSlide._densify_polyline(points, 12)


static func _rotated(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var rotation := deg_to_rad(22.5)
	for point in points:
		result.append(point.rotated(rotation))
	return result


## s/z 的终点必须是对面按钮；不符合就退回直线，避免画出奇怪的折线。
static func _thunder(start_lane: int, end_button: int, mirrored: bool) -> Array[Vector2]:
	if posmod(end_button - 1 - start_lane, 8) != 4:
		return [button_point(start_lane + 1), button_point(end_button)]
	return _rotated(SentakkiSlide._thunder_points(start_lane, 4, mirrored))


## > 顺时针（设计角减小），< 逆时针，^ 取短边。
static func _arc(start_button: int, end_button: int, shape: String) -> Array[Vector2]:
	var start_angle := button_angle(start_button)
	var end_angle := button_angle(end_button)
	var sweep := 0.0
	match shape:
		">":
			sweep = -fposmod(start_angle - end_angle, 360.0)
			if absf(sweep) < 0.001:
				sweep = -360.0
		"<":
			sweep = fposmod(end_angle - start_angle, 360.0)
			if absf(sweep) < 0.001:
				sweep = 360.0
		_:
			sweep = JudgeMath.angle_delta(start_angle, end_angle)
			if absf(sweep) < 0.001:
				sweep = 360.0
	var count := maxi(16, int(ceil(absf(sweep) / 6.0)))
	var points: Array[Vector2] = []
	for i in count + 1:
		points.append(button_point(start_button).rotated(deg_to_rad(sweep * float(i) / float(count))))
	return points
