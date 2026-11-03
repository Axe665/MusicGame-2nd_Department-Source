extends Control

var canvas = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if canvas == null or canvas._app == null:
		return
	var plot: Rect2 = canvas._plot_rect()
	var y: float = canvas._beat_to_y(canvas._app.playhead_beat)
	if y >= plot.position.y - 1.0 and y <= plot.end.y + 1.0:
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.95), 1.5, true)
		var arrow := PackedVector2Array([Vector2(plot.position.x - 8, y - 5), Vector2(plot.position.x, y), Vector2(plot.position.x - 8, y + 5)])
		draw_colored_polygon(arrow, UITheme.ACCENT)
	if plot.has_point(canvas._mouse_pos):
		var x: float = canvas._u_to_x(canvas._hover_u)
		var hover_y: float = canvas._beat_to_y(canvas._hover_beat)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.10), 1.0)
		draw_line(Vector2(plot.position.x, hover_y), Vector2(plot.end.x, hover_y), Color(1, 1, 1, 0.10), 1.0)
		draw_string(UITheme.mono_font(), Vector2(plot.end.x - 150, plot.position.y + 14), "u %.1f°  |  %.2f 拍" % [canvas._hover_u * 360.0, canvas._hover_beat], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.42))
	if canvas._marquee.size.x > 1.0 and canvas._marquee.size.y > 1.0:
		draw_rect(canvas._marquee, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.08))
		draw_rect(canvas._marquee, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.55), false, 1.0)
