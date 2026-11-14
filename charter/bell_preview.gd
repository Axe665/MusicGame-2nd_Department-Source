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
	var center := Vector2(size.x * 0.38, size.y * 0.48)
	var rx := clampf(size.x * 0.20, 56.0, 90.0)
	var ry := minf(30.0, size.y * 0.34)
	NoteGlyph.ring(self, center, rx, ry, Color(1, 1, 1, 0.14), 1.4, 48)
	var span := clampf(arc_width, Note.BELL_MIN_WIDTH, Note.BELL_MAX_WIDTH)
	NoteGlyph.bell_band(self, center, rx, ry, 90.0 - span * 0.5, 90.0 + span * 0.5, 9.0, 5.0)
	draw_string(UITheme.mono_font(), Vector2(center.x + rx + 12.0, center.y + 4.0), "%.0f°" % arc_width,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
