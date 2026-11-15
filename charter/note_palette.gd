class_name NotePalette
extends Control

const CARDS := [
	{"type": "tap", "label": "Tap", "key": "1", "color": UITheme.CORAL},
	{"type": "hold", "label": "Hold", "key": "2", "color": UITheme.AMBER},
	{"type": "path", "label": "Path", "key": "3", "color": UITheme.CYAN},
	{"type": "seek", "label": "Seek", "key": "4", "color": UITheme.SEEK_IN},
	{"type": "anchor", "label": "Anchor", "key": "5", "color": UITheme.VIOLET},
	{"type": "bell", "label": "Bell", "key": "6", "color": UITheme.GOLD},
	{"type": "limit", "label": "Limit", "key": "7", "color": UITheme.RED},
]

var _app: Node = null
var _hover: int = -1


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	custom_minimum_size = Vector2(0, 88)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw()
	)
	if _app != null:
		_app.tool_changed.connect(func(_t: String) -> void: queue_redraw())
		_app.selection_changed.connect(queue_redraw)
		_app.chart_changed.connect(queue_redraw)


func _rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var pad := 4.0
	var gap := 4.0
	var count := CARDS.size()
	var card_w := maxf(30.0, (size.x - pad * 2.0 - gap * float(count - 1)) / float(count))
	var card_h := maxf(48.0, size.y - pad * 2.0)
	for i in count:
		result.append(Rect2(Vector2(pad + float(i) * (card_w + gap), pad), Vector2(card_w, card_h)))
	return result


func _draw() -> void:
	var rects := _rects()
	var font := UITheme.bold_font()
	var mono := UITheme.mono_font()
	var active := _active_type()
	var selected := _selected_type()
	for i in rects.size():
		var card: Dictionary = CARDS[i]
		var rect := rects[i]
		if i == _hover:
			rect.position.y -= 2.0
		var type := String(card["type"])
		var color: Color = card["color"]
		var is_active := type == active
		var points := _card_points(rect)
		var back := PackedVector2Array()
		for p in points:
			back.append(p + Vector2(4, 4))
		draw_colored_polygon(back, Color(0, 0, 0, 0.55))
		draw_colored_polygon(points, UITheme.ACCENT if is_active else UITheme.CARD)
		var border := UITheme.CARD_INK if not is_active else UITheme.CARD_INK
		points.append(points[0])
		draw_polyline(points, border, 1.5, true)
		if is_active:
			draw_line(Vector2(rect.position.x + 8, rect.position.y + 2), Vector2(rect.end.x - 14, rect.position.y + 2), UITheme.CARD_INK, 2.0, true)
		var icon_center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.40)
		_draw_icon(type, icon_center, minf(rect.size.x * 0.34, 28.0), color)
		var label := String(card["label"]).to_upper()
		var label_size := 11 if rect.size.x >= 46.0 else 9
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		draw_string(font, Vector2(rect.position.x + (rect.size.x - label_width) * 0.5, rect.end.y - 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, UITheme.CARD_INK)
		draw_string(mono, Vector2(rect.end.x - 12, rect.position.y + 12), String(card["key"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UITheme.CARD_INK.r, UITheme.CARD_INK.g, UITheme.CARD_INK.b, 0.55))
		if type == selected:
			draw_circle(Vector2(rect.position.x + 7, rect.position.y + 7), 2.6, color)


func _card_points(rect: Rect2) -> PackedVector2Array:
	var cut := 7.0
	return PackedVector2Array([
		Vector2(rect.position.x + cut, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y - cut),
		Vector2(rect.end.x - cut, rect.end.y),
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x, rect.position.y + cut),
	])


func _active_type() -> String:
	if _app == null:
		return "tap"
	return String(_app.tool)


func _selected_type() -> String:
	if _app == null:
		return ""
	if _app.selected_region_id >= 0:
		return "limit"
	var note = _app.get_selected_note()
	if note != null:
		return String(note.type)
	return ""


func _draw_icon(type: String, center: Vector2, r: float, color: Color) -> void:
	var rx := r
	var ry := r * 0.80
	# 卡片是浅色底：淡环用深色，七张卡才能读出同一条判定环。
	NoteGlyph.ring(self, center, rx, ry, Color(0, 0, 0, 0.14), 1.2, 36)
	match type:
		"tap":
			var span := 50.0
			NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5, span * 0.5, color, 4.2, 14)
			var p := NoteGlyph.ellipse_point(center, rx, ry, 0.0)
			var n := NoteGlyph.ring_normal(center, rx, ry, 0.0)
			draw_line(p - n * 5.0, p + n * 4.0, UITheme.CARD_INK, 1.6, true)
			draw_circle(p, 1.5, UITheme.CARD_INK)
		"hold":
			var span := 56.0
			NoteGlyph.fill_sector(self, center, rx, ry, -span * 0.5, span * 0.5, Color(color.r, color.g, color.b, 0.30), 20)
			NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5, span * 0.5, color, 4.0, 18)
			NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5 + 1.0, span * 0.5 - 1.0, Color(1, 1, 1, 0.38), 1.1, 16)
			NoteGlyph.stroke_arc(self, center, rx * 0.52, ry * 0.52, -span * 0.5 + 6.0, span * 0.5 - 6.0, Color(color.r, color.g, color.b, 0.58), 1.6, 14)
		"path":
			var head := NoteGlyph.ellipse_point(center, rx, ry, 0.0)
			var tail := NoteGlyph.ellipse_point(center, rx * 0.60, ry * 0.60, 150.0)
			var control := center + Vector2(rx * 0.50, -ry * 0.10)
			var trail := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var q0 := head.lerp(control, t)
				var q1 := control.lerp(tail, t)
				trail.append(q0.lerp(q1, t))
			draw_polyline(trail, color, 2.0, true)
			NoteGlyph.star(self, head, r * 0.34, color, 1.8)
			draw_circle(tail, 2.0, color)
		"seek":
			NoteGlyph.stroke_arc(self, center, rx, ry, 0.0, 360.0, color, 2.2, 36)
			for i in 8:
				var a := float(i) * 45.0
				var p := NoteGlyph.ellipse_point(center, rx, ry, a)
				var n := NoteGlyph.ring_normal(center, rx, ry, a)
				var tip := p - n * 4.0
				var side := Vector2(-n.y, n.x) * 2.2
				draw_colored_polygon(PackedVector2Array([tip, p + side, p - side]), color)
		"anchor":
			var p := NoteGlyph.ellipse_point(center, rx, ry, 0.0)
			NoteGlyph.diamond(self, p, r * 0.32, color, 1.8)
			var q := p + Vector2(0, r * 0.50)
			draw_line(p, q, Color(color.r, color.g, color.b, 0.75), 1.2, true)
			draw_circle(q, 1.7, color)
		"bell":
			var span := 60.0
			NoteGlyph.bell_band(self, center, rx, ry, -span * 0.5, span * 0.5, 6.0, 3.0)
		"limit":
			var span := 80.0
			NoteGlyph.fill_sector(self, center, rx, ry, -span * 0.5, span * 0.5, Color(color.r, color.g, color.b, 0.22), 20)
			NoteGlyph.stroke_arc(self, center, rx, ry, -span * 0.5, span * 0.5, color, 3.0, 18)
			var top := NoteGlyph.ellipse_point(center, rx, ry, 0.0)
			draw_dashed_line(center, top, Color(color.r, color.g, color.b, 0.55), 1.2, 3.0, true, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var index := _index_at(event.position)
		if index != _hover:
			_hover = index
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _index_at(event.position)
		if index >= 0 and _app != null:
			_app.set_tool(String(CARDS[index]["type"]))
			accept_event()


func _index_at(point: Vector2) -> int:
	var rects := _rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1
