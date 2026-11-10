extends Control

## 检查器里的金键形状预览：长度跟着「弧宽」变，只做视觉参考，不参与判定。

var arc_width := 45.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_arc_width(value: float) -> void:
	value = clampf(value, 6.0, 180.0)
	if is_equal_approx(arc_width, value):
		return
	arc_width = value
	queue_redraw()


func _draw() -> void:
	var t := clampf((arc_width - 6.0) / 174.0, 0.0, 1.0)
	var span := lerpf(52.0, maxf(52.0, size.x - 28.0), t)
	var half := minf(15.0, (size.y - 16.0) * 0.36)
	var p := size * Vector2(0.5, 0.46)
	_key(p, span, half)
	draw_string(UITheme.mono_font(), Vector2(10.0, size.y - 6.0), "%.0f°" % arc_width,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func _key(p: Vector2, span: float, half: float) -> void:
	var tip := 7.0
	_poly(p, span, half + 5.0, tip + 3.0, Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.10))
	_poly(p, span, half + 2.0, tip + 1.5, Color(0, 0, 0, 0.5))
	_poly(p, span, half, tip, Color(1, 1, 1, 0.94))
	_poly(p, span, half * 0.62, tip * 0.62, UITheme.KEY_YELLOW)


func _poly(p: Vector2, span: float, half: float, tip: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-span * 0.5 - tip, 0.0), p + Vector2(-span * 0.5, -half),
		p + Vector2(span * 0.5, -half), p + Vector2(span * 0.5 + tip, 0.0),
		p + Vector2(span * 0.5, half), p + Vector2(-span * 0.5, half),
	]), color)
