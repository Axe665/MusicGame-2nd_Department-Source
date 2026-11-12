class_name NoteGlyph
extends RefCounted

## 编辑器 note 图示共用的「判定环缩略图」画法。
## 角度以 12 点为 0°，顺时针增加；x 轴向右、y 轴向下，和屏幕坐标一致。

const TAU_DEG := 360.0


static func ellipse_point(center: Vector2, rx: float, ry: float, angle_deg: float) -> Vector2:
	var radians := deg_to_rad(angle_deg - 90.0)
	return center + Vector2(cos(radians) * rx, sin(radians) * ry)


static func ring_points(center: Vector2, rx: float, ry: float, from_deg: float, to_deg: float, steps: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(2, steps)
	for i in count + 1:
		var t := float(i) / float(count)
		points.append(ellipse_point(center, rx, ry, lerpf(from_deg, to_deg, t)))
	return points


static func stroke_arc(canvas: CanvasItem, center: Vector2, rx: float, ry: float, from_deg: float, to_deg: float, color: Color, width: float, steps: int = 24) -> void:
	var points := ring_points(center, rx, ry, from_deg, to_deg, steps)
	if points.size() < 2:
		return
	canvas.draw_polyline(points, color, width, true)
	var cap := width * 0.5
	canvas.draw_circle(points[0], cap, color)
	canvas.draw_circle(points[points.size() - 1], cap, color)


static func sector_polygon(center: Vector2, rx: float, ry: float, from_deg: float, to_deg: float, steps: int = 24) -> PackedVector2Array:
	var polygon := PackedVector2Array([center])
	polygon.append_array(ring_points(center, rx, ry, from_deg, to_deg, steps))
	return polygon


static func fill_sector(canvas: CanvasItem, center: Vector2, rx: float, ry: float, from_deg: float, to_deg: float, color: Color, steps: int = 24) -> void:
	canvas.draw_colored_polygon(sector_polygon(center, rx, ry, from_deg, to_deg, steps), color)


static func ring(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, width: float = 1.2, steps: int = 40) -> void:
	stroke_arc(canvas, center, rx, ry, 0.0, TAU_DEG, color, width, steps)


static func star(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width: float = 2.0) -> void:
	var points := PackedVector2Array()
	for i in 11:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	canvas.draw_polyline(points, color, width, true)


static func diamond(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width: float = 2.0) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	canvas.draw_polyline(points, color, width, true)


## 环上金键：暗色外晕 + 白壳 + 金色核心 + 圆头。
static func bell_band(canvas: CanvasItem, center: Vector2, rx: float, ry: float, from_deg: float, to_deg: float, shell_width: float, core_width: float) -> void:
	stroke_arc(canvas, center, rx, ry, from_deg, to_deg, Color(0, 0, 0, 0.42), shell_width + 3.0, 20)
	stroke_arc(canvas, center, rx, ry, from_deg, to_deg, Color(1, 1, 1, 0.94), shell_width, 20)
	stroke_arc(canvas, center, rx, ry, from_deg, to_deg, UITheme.KEY_YELLOW, core_width, 20)


## 环上某点的外法线；环形退化到圆心时退回向上。
static func ring_normal(center: Vector2, rx: float, ry: float, angle_deg: float) -> Vector2:
	var point := ellipse_point(center, rx, ry, angle_deg)
	var direction := point - center
	return direction.normalized() if direction.length() > 0.001 else Vector2.UP
