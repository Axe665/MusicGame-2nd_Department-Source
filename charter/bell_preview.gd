extends Control

## 检查器里的金键形状预览：长度跟着「弧宽」变，只做视觉参考，不参与判定。

var arc_width := Note.BELL_MAX_WIDTH


func _ready() -> void:
	custom_minimum_size = Vector2(0, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_arc_width(value: float) -> void:
	value = clampf(value, Note.BELL_MIN_WIDTH, Note.BELL_MAX_WIDTH)
	if is_equal_approx(arc_width, value):
		return
	arc_width = value
	queue_redraw()


func _draw() -> void:
	var t := clampf((arc_width - Note.BELL_MIN_WIDTH) / (Note.BELL_MAX_WIDTH - Note.BELL_MIN_WIDTH), 0.0, 1.0)
	var span := lerpf(52.0, maxf(52.0, size.x - 28.0), t)
	var half := minf(15.0, (size.y - 16.0) * 0.36)
	var p := size * Vector2(0.5, 0.46)
	_key(p, span, half)
	draw_string(UITheme.mono_font(), Vector2(10.0, size.y - 6.0), "%.0f°" % arc_width,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func _key(p: Vector2, span: float, half: float) -> void:
	_bar(p, span, half + 5.0, Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.10))
	_bar(p, span, half + 2.0, Color(0, 0, 0, 0.5))
	_bar(p, span, half, Color(1, 1, 1, 0.94))
	_bar(p, span, half * 0.62, UITheme.KEY_YELLOW)


func _bar(p: Vector2, span: float, half: float, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-span * 0.5, -half), Vector2(span, half * 2.0)), color)
	draw_circle(p + Vector2(-span * 0.5, 0.0), half, color)
	draw_circle(p + Vector2(span * 0.5, 0.0), half, color)
