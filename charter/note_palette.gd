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
		_draw_icon(type, icon_center, minf(rect.size.x * 0.34, 22.0), color)
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
	match type:
		"tap":
			draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), color, 8.0, true)
			for i in 5:
				var x := center.x - r + (2.0 * r) * float(i) / 4.0
				draw_line(Vector2(x, center.y - 4), Vector2(x, center.y + 4), Color(0, 0, 0, 0.22), 1.0)
			draw_line(center + Vector2(0, -8), center + Vector2(0, 8), UITheme.INK, 2.0)
		"hold":
			var points := PackedVector2Array([
				center + Vector2(-r * 0.8, -r * 0.45),
				center + Vector2(0, -r * 0.8),
				center + Vector2(r * 0.8, -r * 0.45),
				center + Vector2(r * 0.8, r * 0.45),
				center + Vector2(0, r * 0.8),
				center + Vector2(-r * 0.8, r * 0.45),
				center + Vector2(-r * 0.8, -r * 0.45),
			])
			draw_polyline(points, color, 3.0, true)
			draw_line(center + Vector2(0, r * 0.8), center + Vector2(r * 0.55, r * 1.4), color, 5.0, true)
		"path":
			var star := PackedVector2Array()
			for i in 11:
				var angle := -PI * 0.5 + TAU * float(i) / 10.0
				var radius := r if i % 2 == 0 else r * 0.45
				star.append(center + Vector2(cos(angle), sin(angle)) * radius)
			star.append(star[0])
			draw_polyline(star, color, 2.5, true)
		"seek":
			draw_arc(center, r * 0.9, 0.0, TAU, 28, color, 2.2, true)
			draw_arc(center, r * 0.5, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.55), 1.5, true)
			for i in 6:
				var a := TAU * float(i) / 6.0
				var dir := Vector2(cos(a), sin(a))
				var p0 := center + dir * r * 0.64
				var p1 := center + dir * r * 0.44
				draw_line(p0, p1, color, 1.6, true)
				draw_circle(p0, 1.4, color)
		"anchor":
			var diamond := PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0),
				center + Vector2(0, r), center + Vector2(-r, 0),
				center + Vector2(0, -r),
			])
			draw_polyline(diamond, color, 2.5, true)
			draw_line(center + Vector2(0, -r * 0.35), center + Vector2(0, r * 0.2), color, 1.5, true)
			draw_line(center + Vector2(0, r * 0.2), center + Vector2(r * 0.3, r * 0.45), color, 1.5, true)
		"bell":
			# 金键：白壳 + 金色核心 + 尖角端（和 Tap/Hold 同一套语言）。
			var kw := r * 0.86
			var kh := r * 0.62
			var tip := r * 0.26
			var key := PackedVector2Array([
				center + Vector2(-kw - tip, 0.0), center + Vector2(-kw, -kh),
				center + Vector2(kw, -kh), center + Vector2(kw + tip, 0.0),
				center + Vector2(kw, kh), center + Vector2(-kw, kh),
			])
			var shell := PackedVector2Array()
			for p in key:
				shell.append(center + (p - center) * 1.16)
			draw_colored_polygon(shell, Color(0, 0, 0, 0.5))
			draw_colored_polygon(key, Color(1, 1, 1, 0.94))
			var core := PackedVector2Array()
			for p in key:
				core.append(center + (p - center) * 0.62)
			draw_colored_polygon(core, UITheme.KEY_YELLOW)
		"limit":
			draw_arc(center, r * 0.9, -PI * 0.8, PI * 0.1, 20, color, 7.0, true)
			draw_line(center + Vector2(r * 0.3, -r * 0.9), center + Vector2(r * 0.3, r * 0.9), Color(color.r, color.g, color.b, 0.55), 1.5)


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
