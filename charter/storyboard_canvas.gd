class_name StoryboardCanvas
extends Control

## 故事板画布：按当前播放头把 .osb 画出来，点选 / 拖动 Sprite。
## 坐标映射和 Preview3D 一致（场心恒为 320,240；宽屏只是左右多露），
## 拖动只改数据，由 editor 负责写回 .osb 与刷新预览。

signal picked(index: int)
## 拖动中：from/to 都是故事板设计坐标（640x480 单位）。
signal dragged(index: int, from: Vector2, to: Vector2)
signal released()

var board: Storyboard = null
var dir := ""
var playhead_ms := 0.0
var selected := -1
## 图层显隐（只在画布上过滤，不影响数据）。
var hidden_layers: Dictionary = {}

const TEX_MAX := 1024

var _tex: Dictionary = {}
var _boost: Dictionary = {}
var _index_of: Dictionary = {}
var _items: Array[Dictionary] = []
var _wide_cache := -1
var _drag_index := -1
var _drag_origin := Vector2.ZERO
var _drag_start := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(440, 300)
	tooltip_text = "点选 Sprite 后拖动即可改位置（写进当前时刻的移动关键帧）"


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


func set_layer_visible(layer: String, visible: bool) -> void:
	if visible:
		hidden_layers.erase(layer)
	else:
		hidden_layers[layer] = true
	queue_redraw()


func set_selected(index: int) -> void:
	selected = index
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.06))
	if board == null or dir.is_empty():
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
		var full := dir + "/" + String(item["path"]).get_file()
		var texture := _texture(full)
		if texture == null:
			continue
		var sprite_size := Vector2(texture.get_width(), texture.get_height())
		var anchor := Preview3D._storyboard_anchor(int(item["origin"]), sprite_size)
		var pos: Vector2 = offset + (item["pos"] as Vector2) * scale
		var sprite_scale: Vector2 = item["scale"] * scale * float(_boost.get(full, 1.0))
		var rotation := deg_to_rad(float(item["rotation"]))
		var colour: Color = item["colour"]
		colour.a *= clampf(float(item["alpha"]), 0.0, 1.0)
		draw_set_transform(pos, rotation, sprite_scale)
		draw_texture(texture, -anchor, colour)
		if selected >= 0 and int(_index_of.get(item.get("sprite"), -2)) == selected:
			var thin := 2.0 / maxf(0.001, sprite_scale.x)
			draw_rect(Rect2(-anchor, sprite_size), Color(1.0, 0.85, 0.2, 0.95), false, thin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 点在哪个对象上（逆序 = 最上层优先）；-1 表示空白。
func _hit(point: Vector2) -> int:
	if _items.is_empty() and board != null:
		_items = board.sample(playhead_ms)
	var layout := _layout()
	var scale: float = layout["scale"]
	var offset: Vector2 = layout["offset"]
	for i in range(_items.size() - 1, -1, -1):
		var item: Dictionary = _items[i]
		if hidden_layers.has(String(item["layer"])):
			continue
		var sprite = item.get("sprite")
		if sprite == null:
			continue
		var full := dir + "/" + String(item["path"]).get_file()
		var texture := _texture(full)
		if texture == null:
			continue
		var sprite_size := Vector2(texture.get_width(), texture.get_height())
		var anchor := Preview3D._storyboard_anchor(int(item["origin"]), sprite_size)
		var pos: Vector2 = offset + (item["pos"] as Vector2) * scale
		var sprite_scale: Vector2 = item["scale"] * scale * float(_boost.get(full, 1.0))
		var local := (point - pos).rotated(-deg_to_rad(float(item["rotation"])))
		local.x /= maxf(0.001, sprite_scale.x)
		local.y /= maxf(0.001, sprite_scale.y)
		if Rect2(-anchor, sprite_size).has_point(local):
			return int(_index_of.get(sprite, -1))
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit(event.position as Vector2)
			if hit != selected:
				selected = hit
				picked.emit(hit)
			queue_redraw()
			if hit >= 0:
				_drag_index = hit
				_drag_origin = event.position
				_drag_start = (board.sprites[hit] as Storyboard.Sprite).pos
				accept_event()
		elif _drag_index >= 0:
			_drag_index = -1
			released.emit()
			accept_event()
		return
	if event is InputEventMouseMotion and _drag_index >= 0:
		var scale: float = _layout()["scale"]
		var delta: Vector2 = (event.position - _drag_origin) / maxf(0.0001, scale)
		dragged.emit(_drag_index, _drag_start, _drag_start + delta)
		accept_event()
