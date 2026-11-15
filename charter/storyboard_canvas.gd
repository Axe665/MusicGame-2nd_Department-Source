class_name StoryboardCanvas
extends Control

## 故事板画布：按当前播放头把 .osb 画出来，点选 / Ctrl 多选 / 框选 / 拖动。
## 坐标映射和 Preview3D 一致（场心恒为 320,240；宽屏只是左右多露），
## 拖动只改数据，由 editor 负责写回 .osb 与刷新预览。

## 选择变化（可能是多个）。空数组 = 取消选择。
signal selection_changed(indices: Array)
## 拖动中：bases 是按下时每个对象的位置（故事板单位），delta 是相对按下点的位移。
signal dragged(indices: Array, bases: Array, delta: Vector2)
signal released()

var board: Storyboard = null
var dir := ""
var playhead_ms := 0.0
## 主选中项（属性面板用）；selected_items 是全部选中。
var selected := -1
var selected_items: Array[int] = []
## 图层显隐（只在画布上过滤，不影响数据）。
var hidden_layers: Dictionary = {}

const TEX_MAX := 1024

var _tex: Dictionary = {}
var _boost: Dictionary = {}
var _index_of: Dictionary = {}
var _items: Array[Dictionary] = []
var _wide_cache := -1
var _drag_indices: Array[int] = []
var _drag_bases: Array[Vector2] = []
var _drag_origin := Vector2.ZERO
var _dragging := false
var _marquee := Rect2()
var _marquee_active := false
var _marquee_from := Vector2.ZERO
var _marquee_additive := false
## 按下但还没决定是「点选 / 拖动 / 框选」：移动超过阈值才升级。
var _pending := false
var _press_point := Vector2.ZERO
var _pressed_hit := -1
var _pressed_additive := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(440, 300)
	tooltip_text = "点选 / Ctrl 点加选 / 空白处拖框选；拖动写进当前时刻的移动关键帧"


func set_board(value: Storyboard, path: String) -> void:
	board = value
	dir = path
	_index_of.clear()
	_wide_cache = -1
	if board != null:
		for i in board.sprites.size():
			_index_of[board.sprites[i]] = i
	queue_redraw()


func set_playhead(ms: float) -> void:
	playhead_ms = ms
	queue_redraw()


## 列表点选：换成单选（画布多选时由 ensure_selected 保住已选集合）。
func set_selected(index: int) -> void:
	selected = index
	selected_items.clear()
	if index >= 0:
		selected_items.append(index)
	queue_redraw()


func ensure_selected(index: int) -> void:
	selected = index
	if index >= 0 and not selected_items.has(index):
		selected_items.clear()
		selected_items.append(index)
	queue_redraw()


func set_layer_visible(layer: String, visible: bool) -> void:
	if visible:
		hidden_layers.erase(layer)
	else:
		hidden_layers[layer] = true
	queue_redraw()


func _wide() -> bool:
	if _wide_cache >= 0:
		return _wide_cache == 1
	var wide := false
	if board != null:
		for sprite in board.sprites:
			if sprite.pos.x > 641.0:
				wide = true
				break
	_wide_cache = 1 if wide else 0
	return wide


func _layout() -> Dictionary:
	var field := 854.0 if _wide() else 640.0
	var scale := minf(size.x / field, size.y / 480.0)
	return {"scale": scale, "offset": size * 0.5 - Vector2(320, 240) * scale}


func _texture(full: String) -> Texture2D:
	if _tex.has(full):
		return _tex[full]
	var image: Image = null
	if FileAccess.file_exists(full):
		image = Image.load_from_file(ProjectSettings.globalize_path(full))
		if image != null and not image.is_empty():
			var longest := maxi(image.get_width(), image.get_height())
			if longest > TEX_MAX:
				_boost[full] = float(longest) / float(TEX_MAX)
				var ratio := float(TEX_MAX) / float(longest)
				image.resize(maxi(1, roundi(float(image.get_width()) * ratio)),
					maxi(1, roundi(float(image.get_height()) * ratio)), Image.INTERPOLATE_BILINEAR)
		else:
			image = null
	var texture: Texture2D = null
	if image != null and not image.is_empty():
		texture = ImageTexture.create_from_image(image)
	_tex[full] = texture
	return texture


## 一个 item 的绘制参数（画、命中、框选共用一套）。
func _item_geometry(item: Dictionary, layout: Dictionary) -> Dictionary:
	var full := dir + "/" + String(item["path"]).get_file()
	var texture := _texture(full)
	if texture == null:
		return {}
	var sprite_size := Vector2(texture.get_width(), texture.get_height())
	var scale: float = layout["scale"]
	var offset: Vector2 = layout["offset"]
	return {
		"texture": texture,
		"size": sprite_size,
		"anchor": Preview3D._storyboard_anchor(int(item["origin"]), sprite_size),
		"pos": offset + (item["pos"] as Vector2) * scale,
		"scale": item["scale"] * scale * float(_boost.get(full, 1.0)),
		"rotation": deg_to_rad(float(item["rotation"])),
		"colour": item["colour"],
		"alpha": float(item["alpha"]),
	}


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.06))
	if board == null or dir.is_empty():
		_draw_marquee()
		return
	var layout := _layout()
	var scale: float = layout["scale"]
	var offset: Vector2 = layout["offset"]
	# 640 场的可见边界（宽屏时左右各多露 107）。
	draw_rect(Rect2(offset, Vector2(640, 480) * scale), Color(1, 1, 1, 0.10), false, 1.0)
	_items = board.sample(playhead_ms)
	for item in _items:
		if hidden_layers.has(String(item["layer"])):
			continue
		var geo := _item_geometry(item, layout)
		if geo.is_empty():
			continue
		var colour: Color = geo["colour"]
		colour.a *= clampf(float(geo["alpha"]), 0.0, 1.0)
		draw_set_transform(geo["pos"], float(geo["rotation"]), geo["scale"])
		draw_texture(geo["texture"], -(geo["anchor"] as Vector2), colour)
		if selected_items.has(int(_index_of.get(item.get("sprite"), -1))):
			var thin := 2.0 / maxf(0.001, (geo["scale"] as Vector2).x)
			draw_rect(Rect2(-(geo["anchor"] as Vector2), geo["size"]),
				Color(1.0, 0.85, 0.2, 0.95), false, thin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_marquee()


func _draw_marquee() -> void:
	if not _marquee_active or _marquee.size.x < 2.0 and _marquee.size.y < 2.0:
		return
	draw_rect(_marquee, Color(0.37, 0.92, 0.86, 0.12))
	draw_rect(_marquee, Color(0.37, 0.92, 0.86, 0.85), false, 1.0)


## 点在哪个对象上（逆序 = 最上层优先）；-1 表示空白。
func _hit(point: Vector2) -> int:
	if _items.is_empty() and board != null:
		_items = board.sample(playhead_ms)
	var layout := _layout()
	for i in range(_items.size() - 1, -1, -1):
		var item: Dictionary = _items[i]
		if hidden_layers.has(String(item["layer"])):
			continue
		var sprite = item.get("sprite")
		if sprite == null:
			continue
		var geo := _item_geometry(item, layout)
		if geo.is_empty():
			continue
		var local := (point - (geo["pos"] as Vector2)).rotated(-float(geo["rotation"]))
		var sprite_scale: Vector2 = geo["scale"]
		local.x /= maxf(0.001, sprite_scale.x)
		local.y /= maxf(0.001, sprite_scale.y)
		if Rect2(-(geo["anchor"] as Vector2), geo["size"]).has_point(local):
			return int(_index_of.get(sprite, -1))
	return -1


## 旋转后对象的轴对齐包围盒（框选用）。
func _item_bounds(item: Dictionary, layout: Dictionary) -> Rect2:
	var geo := _item_geometry(item, layout)
	if geo.is_empty():
		return Rect2()
	var anchor: Vector2 = geo["anchor"]
	var sprite_size: Vector2 = geo["size"]
	var pos: Vector2 = geo["pos"]
	var sprite_scale: Vector2 = geo["scale"]
	var rot: float = geo["rotation"]
	var corners := [
		Vector2(-anchor.x, -anchor.y), Vector2(sprite_size.x - anchor.x, -anchor.y),
		Vector2(sprite_size.x - anchor.x, sprite_size.y - anchor.y), Vector2(-anchor.x, sprite_size.y - anchor.y),
	]
	var bounds := Rect2(pos, Vector2.ZERO)
	for corner in corners:
		var point: Vector2 = pos + (corner as Vector2).rotated(rot) * sprite_scale
		bounds = bounds.expand(point)
	return bounds


func _commit_marquee() -> void:
	if _marquee.size.length() < 3.0:
		return
	var layout := _layout()
	var hits: Array[int] = []
	for item in _items:
		if hidden_layers.has(String(item["layer"])):
			continue
		var sprite = item.get("sprite")
		if sprite == null:
			continue
		if _marquee.intersects(_item_bounds(item, layout)):
			var index := int(_index_of.get(sprite, -1))
			if index >= 0 and not hits.has(index):
				hits.append(index)
	if not _marquee_additive:
		selected_items.clear()
	for index in hits:
		if not selected_items.has(index):
			selected_items.append(index)
	selected = selected_items[0] if not selected_items.is_empty() else -1
	selection_changed.emit(selected_items)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pending = true
			_press_point = event.position as Vector2
			_pressed_hit = _hit(_press_point)
			_pressed_additive = bool(event.ctrl_pressed) or bool(event.shift_pressed)
			accept_event()
			return
		if _pending:
			_pending = false
			if _pressed_hit >= 0:
				_toggle_or_select(_pressed_hit, _pressed_additive)
			elif not _pressed_additive:
				selected_items.clear()
				selected = -1
				selection_changed.emit(selected_items)
			queue_redraw()
			accept_event()
			return
		if _marquee_active:
			_marquee_active = false
			_commit_marquee()
			queue_redraw()
			accept_event()
			return
		if _dragging:
			_dragging = false
			_drag_indices.clear()
			_drag_bases.clear()
			released.emit()
			accept_event()
		return
	if event is InputEventMouseMotion:
		var position := event.position as Vector2
		if _pending:
			if (position - _press_point).length() < 6.0:
				return
			_pending = false
			# Ctrl/Shift 拖动、或在空白处拖动 = 框选；普通拖动对象 = 移动。
			if _pressed_hit < 0 or _pressed_additive:
				_marquee_active = true
				_marquee_additive = _pressed_additive
				_marquee_from = _press_point
				_marquee = Rect2(_press_point, Vector2.ZERO).expand(position)
				queue_redraw()
				accept_event()
				return
			_dragging = true
			_drag_origin = _press_point
			_drag_indices.clear()
			for index in selected_items:
				_drag_indices.append(index)
			_drag_bases.clear()
			for index in _drag_indices:
				_drag_bases.append((board.sprites[index] as Storyboard.Sprite).pos)
			queue_redraw()
			accept_event()
			return
		if _marquee_active:
			_marquee = Rect2(_marquee_from, Vector2.ZERO).expand(position)
			queue_redraw()
			accept_event()
			return
		if _dragging:
			var scale: float = _layout()["scale"]
			var delta: Vector2 = (position - _drag_origin) / maxf(0.0001, scale)
			dragged.emit(_drag_indices, _drag_bases, delta)
			accept_event()


func _toggle_or_select(hit: int, additive: bool) -> void:
	if additive:
		if selected_items.has(hit):
			selected_items.erase(hit)
			selected = selected_items[0] if not selected_items.is_empty() else -1
		else:
			selected_items.append(hit)
			selected = hit
	elif not selected_items.has(hit):
		selected_items.clear()
		selected_items.append(hit)
		selected = hit
	else:
		selected = hit
	selection_changed.emit(selected_items)
	queue_redraw()
