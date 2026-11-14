extends Control

## 检查器 Hold 形状预览：只做视觉参考，不参与判定。
## 扇形角度 = 当前实际弧宽；身体固定 1 拍样本，让宽窄一眼可比。

var arc_width := 30.0
var duration := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(width: float, hold_beats: float) -> void:
	arc_width = clampf(width, 0.0, 180.0)
	duration = maxf(0.0, hold_beats)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.32, size.y * 0.42)
	var rx := clampf(size.x * 0.18, 52.0, 84.0)
	var ry := minf(30.0, size.y * 0.32)
	NoteGlyph.ring(self, center, rx, ry, Color(1, 1, 1, 0.14), 1.2, 48)
	var span := clampf(arc_width, 0.0, 180.0)
	if span >= 0.5:
		var inner := 0.52
		NoteGlyph.fill_annular_sector(self, center, rx, ry, inner, -span * 0.5, span * 0.5, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.22), 20)
		NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5, span * 0.5, UITheme.AMBER, 4.2, 18)
		NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5 + 1.5, span * 0.5 - 1.5, Color(1, 1, 1, 0.40), 1.2, 16)
		NoteGlyph.stroke_arc(self, center, rx * inner, ry * inner, -span * 0.5, span * 0.5, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.75), 2.0, 16)
		var outer_a := NoteGlyph.ellipse_point(center, rx, ry, -span * 0.5)
		var inner_a := NoteGlyph.ellipse_point(center, rx * inner, ry * inner, -span * 0.5)
		var outer_b := NoteGlyph.ellipse_point(center, rx, ry, span * 0.5)
		var inner_b := NoteGlyph.ellipse_point(center, rx * inner, ry * inner, span * 0.5)
		draw_line(outer_a, inner_a, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.45), 1.2, true)
		draw_line(outer_b, inner_b, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.45), 1.2, true)
	else:
		var top := NoteGlyph.ellipse_point(center, rx, ry, 0.0)
		draw_line(top + Vector2(0, -4), top + Vector2(0, 4), UITheme.AMBER, 2.0, true)
	var label := "弧宽 %.0f°" % span
	if duration > 0.0:
		label += "，时长 %.2f 拍" % duration
	draw_string(UITheme.mono_font(), Vector2(8.0, size.y - 8.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
