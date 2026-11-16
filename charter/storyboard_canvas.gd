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
## 画布缩放/平移（1 = 适配窗口；滚轮缩放，中键拖动）。
var zoom := 1.0
var pan := Vector2.ZERO
var show_grid := true

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
## 加色层：同一 CanvasItem 不能混两种混合模式，所以 P,A 单独一个 ADD 子节点。
var _add_layer: Control = null
var _panning := false
var _pan_from := Vector2.ZERO
var _pan_origin := Vector2.ZERO
## 鼠标所在的设计坐标（读数用；-1 = 不在画布上）。
var mouse_design := Vector2(-1, -1)
## 悬停变化（编辑器更新读数用）。
var _on_hover_changed: Callable = Callable()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(320, 160)
	tooltip_text = "点选 / Ctrl 点加选 / 空白处拖框选；拖动写进当前时刻的移动关键帧；滚轮缩放，中键平移"


func _ready() -> void:
	var layer := AdditiveLayer.new()
	layer.canvas = self
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_layer = layer


## 滚轮缩放：光标下的设计点保持不动。
func _zoom_at(point: Vector2, factor: float) -> void:
	var old := _layout()
	var design := (point - (old["offset"] as Vector2)) / maxf(0.0001, float(old["scale"]))
	zoom = clampf(zoom * factor, 0.25, 8.0)
	var base := minf(size.x / (854.0 if _wide() else 640.0), size.y / 480.0)
	var new_scale := base * zoom
	pan = point - size * 0.5 + (Vector2(320, 240) - design) * new_scale
	queue_redraw()


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
	var base := minf(size.x / field, size.y / 480.0)
	var scale := base * zoom
	return {"scale": scale, "offset": size * 0.5 - Vector2(320, 240) * scale + pan}


## 图层顺序（先画的在下），同图层内按文件顺序。
static func _layer_rank(layer: String) -> int:
	var index := Storyboard.LAYERS.find(layer)
	return index if index >= 0 else 0


static func _sort_by_layer(a: Dictionary, b: Dictionary) -> bool:
	var la := _layer_rank(String(a["layer"]))
	var lb := _layer_rank(String(b["layer"]))
	if la != lb:
		return la < lb
	return int((a["sprite"] as Storyboard.Sprite).order) < int((b["sprite"] as Storyboard.Sprite).order)


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
	# 官方 Design 页那样每 32 设计像素一条细线，方便对齐。
	if show_grid:
		var step := 32.0 * scale
		if step >= 4.0:
			var field := 854.0 if _wide() else 640.0
			var grid_colour := Color(1, 1, 1, 0.055)
			var x := offset.x
			while x <= offset.x + field * scale + 0.5:
				draw_line(Vector2(x, offset.y), Vector2(x, offset.y + 480.0 * scale), grid_colour, 1.0)
				x += step
			var y := offset.y
			while y <= offset.y + 480.0 * scale + 0.5:
				draw_line(Vector2(offset.x, y), Vector2(offset.x + field * scale, y), grid_colour, 1.0)
				y += step
		draw_line(Vector2(size.x * 0.5, offset.y), Vector2(size.x * 0.5, offset.y + 480.0 * scale),
			Color(1, 1, 1, 0.10), 1.0)
		draw_line(Vector2(offset.x, offset.y + 240.0 * scale), Vector2(offset.x + (854.0 if _wide() else 640.0) * scale, offset.y + 240.0 * scale),
			Color(1, 1, 1, 0.10), 1.0)
	_items = board.sample(playhead_ms)
	_items.sort_custom(_sort_by_layer)
	_draw_items(self, false)
	if _add_layer != null:
		(_add_layer as AdditiveLayer).queue_redraw()
	_draw_marquee()


## 一遍只画一种混合：加色元素交给 ADD 子节点（和 Preview3D 的分层方式一致）。
func _draw_items(ci: CanvasItem, additive_only: bool) -> void:
	var layout := _layout()
	for item in _items:
		if hidden_layers.has(String(item["layer"])):
			continue
		if bool(item.get("additive", false)) != additive_only:
			continue
		var geo := _item_geometry(item, layout)
		if geo.is_empty():
			continue
		var colour := Preview3D.storyboard_item_colour(item, geo["size"], geo["scale"], size)
		ci.draw_set_transform(geo["pos"], float(geo["rotation"]), geo["scale"])
		ci.draw_texture(geo["texture"], -(geo["anchor"] as Vector2), colour)
		if selected_items.has(int(_index_of.get(item.get("sprite"), -1))):
			var thin := 2.0 / maxf(0.001, (geo["scale"] as Vector2).x)
			ci.draw_rect(Rect2(-(geo["anchor"] as Vector2), geo["size"]),
				Color(1.0, 0.85, 0.2, 0.95), false, thin)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(button.position, 1.15)
			accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(button.position, 1.0 / 1.15)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			if _panning:
				_pan_from = button.position
				_pan_origin = pan
			accept_event()
			return
	if event is InputEventMouseMotion:
		var hover := _layout()
		mouse_design = ((event as InputEventMouseMotion).position - (hover["offset"] as Vector2)) / maxf(0.0001, float(hover["scale"]))
		if _on_hover_changed.is_valid():
			_on_hover_changed.call()
	if event is InputEventMouseMotion and _panning:
		var motion := event as InputEventMouseMotion
		pan = _pan_origin + (motion.position - _pan_from)
		queue_redraw()
		accept_event()
		return
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


## 加色元素单独一层：CanvasItem 的混合模式是整层属性，不能和普通 alpha 混在同一个 _draw 里。
class AdditiveLayer extends Control:
	var canvas = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _draw() -> void:
		if canvas != null:
			canvas._draw_items(self, true)
