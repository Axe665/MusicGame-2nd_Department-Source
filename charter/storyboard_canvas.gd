class_name StoryboardCanvas
extends Control

## 故事板画布：按当前播放头把 .osb 画出来，点选 / Ctrl 多选 / 框选 / 拖动。
## 坐标映射和 Preview3D 一致（场心恒为 320,240；宽屏只是左右多露）。
##
## 和游戏预览的差别：编辑器要看到安全框外的东西（超宽背景、被 M 命令推到画外的
## 元素），框外盖一层暗色蒙版；框外不可点，避免误拖。

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
## 图层显隐/锁定（只在画布上过滤，不影响数据）。
var hidden_layers: Dictionary = {}
var locked_layers: Dictionary = {}
## 画布缩放/平移（1 = 适配；滚轮缩放，中键拖动）。
var zoom := 1.0
var pan := Vector2.ZERO
var show_grid := true
## field = 只适配安全框；content = 连超宽背景一起适配（默认，编辑器里看整张图）。
var fit_mode := "content"
## 「适配内容」时算一次的包围盒（播放中不重算，免得画面每帧缩放跳动）。
var _bounds_cache := Rect2()
var _bounds_valid := false

const TEX_MAX := 1024

var _tex: Dictionary = {}
var _boost: Dictionary = {}
var _size_cache: Dictionary = {}
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
## 蒙版层：框外压暗；在加色层上面，保证框外的加色元素也一起暗掉。
var _mask_layer: Control = null
## 选择框/框选层：在蒙版上面。
var _ui_layer: Control = null
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
	custom_minimum_size = Vector2(480, 300)
	tooltip_text = "点选 / Ctrl 点加选 / 空白处拖框选；拖动写进当前时刻的移动关键帧；滚轮缩放，中键平移"


func _ready() -> void:
	var layer := AdditiveLayer.new()
	layer.canvas = self
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_layer = layer

	_mask_layer = MaskLayer.new()
	_mask_layer.canvas = self
	_mask_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mask_layer)
	_mask_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ui_layer = UiLayer.new()
	_ui_layer.canvas = self
	_ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_layer)
	_ui_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _wide() -> bool:
	if _wide_cache >= 0:
		return _wide_cache == 1
	# 和 Preview3D 用同一套宽屏判定：只看 pos 会漏掉靠 M/MX 移到 854 场的对象，
	# 编辑器就会按 4:3 画、和试玩/导出对不上。
	var wide := board != null and Preview3D._detect_wide(board)
	_wide_cache = 1 if wide else 0
	return wide


func field_width() -> float:
	return 854.0 if _wide() else 640.0


## 设计坐标 → 画布坐标的缩放/偏移。fit_mode = content 时把安全框和当前可见
## 对象的包围盒一起装进画布，超宽背景才看得到。
func _layout() -> Dictionary:
	var field := field_width()
	var bounds := Rect2(Vector2.ZERO, Vector2(field, 480.0))
	if fit_mode == "content" and _bounds_valid:
		bounds = _bounds_cache
	var margin := 0.94
	var base := minf(size.x / maxf(1.0, bounds.size.x * 1.12),
		size.y / maxf(1.0, bounds.size.y * 1.12)) * margin
	var scale := base * zoom
	var offset := size * 0.5 - bounds.get_center() * scale + pan
	return {"scale": scale, "offset": offset, "bounds": bounds}


## 安全框 + 当前播放头可见对象的包围盒；限制在安全框 3 倍以内，
## 免得某个被 M 命令丢到 10000 的 sprite 把整张画布缩成一点。
func _compute_content_bounds(field_bounds: Rect2) -> Rect2:
	var bounds := field_bounds
	if board == null or dir.is_empty():
		return bounds
	var limit := Rect2(field_bounds.position - field_bounds.size, field_bounds.size * 3.0)
	for item in board.sample(playhead_ms):
		if float(item.get("alpha", 0.0)) <= 0.004:
			continue
		var sprite = item.get("sprite")
		if sprite == null:
			continue
		var full := dir + "/" + String(item["path"]).get_file()
		var tex_size := _texture_size(full)
		if tex_size == Vector2.ZERO:
			continue
		# 贴图超过 1024 时被缩小过，设计尺寸要乘回 boost，否则「适配内容」会算小。
		var boost := float(_boost.get(full, 1.0))
		var size_design := tex_size * boost
		var anchor := Preview3D._storyboard_anchor(int(item["origin"]), tex_size) * boost
		var sprite_scale: Vector2 = item["scale"]
		var pos: Vector2 = item["pos"]
		var corners := [
			Vector2(-anchor.x, -anchor.y) * sprite_scale,
			Vector2(size_design.x - anchor.x, -anchor.y) * sprite_scale,
			Vector2(size_design.x - anchor.x, size_design.y - anchor.y) * sprite_scale,
			Vector2(-anchor.x, size_design.y - anchor.y) * sprite_scale,
		]
		var rot := deg_to_rad(float(item["rotation"]))
		var box := Rect2(pos, Vector2.ZERO)
		for corner in corners:
			box = box.expand(pos + (corner as Vector2).rotated(rot))
		box = box.intersection(limit)
		if box.has_area():
			bounds = bounds.merge(box)
	return bounds


## 安全框在画布上的矩形（框外压暗、命中判定都按它）。
func field_rect() -> Rect2:
	var layout := _layout()
	return Rect2(layout["offset"], Vector2(field_width(), 480.0) * float(layout["scale"]))


## 滚轮缩放：光标下的设计点保持不动。
func _zoom_at(point: Vector2, factor: float) -> void:
	var old := _layout()
	var design: Vector2 = (point - (old["offset"] as Vector2)) / maxf(0.0001, float(old["scale"]))
	zoom = clampf(zoom * factor, 0.2, 8.0)
	var changed := _layout()
	var landed: Vector2 = (changed["offset"] as Vector2) + design * float(changed["scale"])
	pan += point - landed
	queue_redraw()


func fit_field() -> void:
	fit_mode = "field"
	_bounds_valid = false
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()


func fit_content() -> void:
	fit_mode = "content"
	_bounds_cache = _compute_content_bounds(Rect2(Vector2.ZERO, Vector2(field_width(), 480.0)))
	_bounds_valid = true
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()


func set_board(value: Storyboard, path: String) -> void:
	board = value
	dir = path
	_index_of.clear()
	_wide_cache = -1
	_items.clear()
	_bounds_valid = false
	if board != null:
		for i in board.sprites.size():
			_index_of[board.sprites[i]] = i
	queue_redraw()


func set_playhead(ms: float) -> void:
	playhead_ms = ms
	_items.clear()
	queue_redraw()


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


func set_layer_locked(layer: String, locked: bool) -> void:
	if locked:
		locked_layers[layer] = true
	else:
		locked_layers.erase(layer)
	queue_redraw()


func _texture(full: String) -> Texture2D:
	if _tex.has(full):
		return _tex[full]
	# 主预览已经解过同一张图（静态缓存），编辑器直接复用，避免再同步解码一遍。
	var shared: Texture2D = Preview3D._tex_cache.get(full)
	if shared != null:
		_tex[full] = shared
		_boost[full] = float(Preview3D._tex_boost.get(full, 1.0))
		_size_cache[full] = shared.get_size()
		return shared
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
		_size_cache[full] = Vector2(image.get_width(), image.get_height())
	_tex[full] = texture
	return texture


func _texture_size(full: String) -> Vector2:
	if _size_cache.has(full):
		return _size_cache[full]
	if _tex.has(full) and _tex[full] != null:
		var t: Texture2D = _tex[full]
		_size_cache[full] = Vector2(t.get_width(), t.get_height())
		return _size_cache[full]
	var texture := _texture(full)
	return _size_cache.get(full, texture.get_size() if texture != null else Vector2.ZERO)


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
		return
	var layout := _layout()
	var scale: float = layout["scale"]
	var offset: Vector2 = layout["offset"]
	# 网格和场框画在故事板下面，和 osu 的 Design 页一样每 32 设计像素一条。
	if show_grid:
		var step := 32.0 * scale
		if step >= 4.0:
			var field := field_width()
			var grid_colour := Color(1, 1, 1, 0.05)
			var x := offset.x
			while x <= offset.x + field * scale + 0.5:
				draw_line(Vector2(x, offset.y), Vector2(x, offset.y + 480.0 * scale), grid_colour, 1.0)
				x += step
			var y := offset.y
			while y <= offset.y + 480.0 * scale + 0.5:
				draw_line(Vector2(offset.x, y), Vector2(offset.x + field * scale, y), grid_colour, 1.0)
				y += step
	# 不排序、不复制：sample() 的缓存数组归 Storyboard 所有，
	# 绘制按图层顺序分组遍历（比每帧 sort_custom 285 项便宜，也不会改到别人的数组）。
	_items = board.sample(playhead_ms)
	_draw_items(self, false)
	if _add_layer != null:
		(_add_layer as AdditiveLayer).queue_redraw()
	if _mask_layer != null:
		_mask_layer.queue_redraw()
	if _ui_layer != null:
		_ui_layer.queue_redraw()


## 一遍只画一种混合：加色元素交给 ADD 子节点（和 Preview3D 的分层方式一致）。
func _draw_items(ci: Control, additive_only: bool) -> void:
	var layout := _layout()
	var view := ci.size
	# 先画的在下：Video → Background → Fail → Pass → Foreground → Overlay。
	for layer in Storyboard.LAYERS:
		if hidden_layers.has(layer):
			continue
		for item in _items:
			if String(item["layer"]) != layer:
				continue
			if bool(item.get("additive", false)) != additive_only:
				continue
			var geo := _item_geometry(item, layout)
			if geo.is_empty():
				continue
			var pos: Vector2 = geo["pos"]
			var sprite_size: Vector2 = geo["size"]
			var sprite_scale: Vector2 = geo["scale"]
			var rot: float = geo["rotation"]
			var anchor: Vector2 = geo["anchor"]
			var radius := (sprite_size * 0.5 - anchor).length() * maxf(sprite_scale.x, sprite_scale.y) + 4.0
			if pos.x + radius < 0.0 or pos.y + radius < 0.0 \
					or pos.x - radius > view.x or pos.y - radius > view.y:
				continue
			var colour := Preview3D.storyboard_item_colour(item, sprite_size, sprite_scale, view)
			ci.draw_set_transform(pos, rot, sprite_scale)
			ci.draw_texture(geo["texture"], -anchor, colour)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 框外压暗 + 高亮安全框。
func _draw_mask(ci: Control) -> void:
	var field := field_rect()
	if field.size.x <= 1.0 or field.size.y <= 1.0:
		return
	var shade := Color(0.0, 0.0, 0.0, 0.62)
	ci.draw_rect(Rect2(0.0, 0.0, size.x, maxf(0.0, field.position.y)), shade)
	ci.draw_rect(Rect2(0.0, field.end.y, size.x, maxf(0.0, size.y - field.end.y)), shade)
	ci.draw_rect(Rect2(0.0, field.position.y, maxf(0.0, field.position.x), field.size.y), shade)
	ci.draw_rect(Rect2(field.end.x, field.position.y, maxf(0.0, size.x - field.end.x), field.size.y), shade)
	ci.draw_rect(field, Color(0.32, 0.85, 0.82, 0.55), false, 1.5)
	ci.draw_line(Vector2(field.position.x, field.get_center().y), Vector2(field.end.x, field.get_center().y),
		Color(0.32, 0.85, 0.82, 0.18), 1.0)
	ci.draw_line(Vector2(field.get_center().x, field.position.y), Vector2(field.get_center().x, field.end.y),
		Color(0.32, 0.85, 0.82, 0.18), 1.0)


## 选中框 + 框选矩形。
func _draw_ui(ci: Control) -> void:
	var layout := _layout()
	for item in _items:
		var sprite = item.get("sprite")
		if sprite == null or not selected_items.has(int(_index_of.get(sprite, -1))):
			continue
		var geo := _item_geometry(item, layout)
		if geo.is_empty():
			continue
		var scale: Vector2 = geo["scale"]
		var thin := 2.0 / maxf(0.001, maxf(scale.x, scale.y))
		ci.draw_set_transform(geo["pos"], float(geo["rotation"]), scale)
		ci.draw_rect(Rect2(-(geo["anchor"] as Vector2), geo["size"]),
			Color(1.0, 0.85, 0.2, 0.95), false, thin)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _marquee_active and not (_marquee.size.x < 2.0 and _marquee.size.y < 2.0):
		ci.draw_rect(_marquee, Color(0.37, 0.92, 0.86, 0.12))
		ci.draw_rect(_marquee, Color(0.37, 0.92, 0.86, 0.85), false, 1.0)


## 点在哪个对象上（逆序 = 最上层优先）；-1 表示空白或框外。
func _hit(point: Vector2) -> int:
	if not field_rect().has_point(point):
		return -1
	if _items.is_empty() and board != null:
		_items = board.sample(playhead_ms)
	var layout := _layout()
	# 从最上层往下找；同层里 order 最大的压在最上面，先命中它。
	for layer_index in range(Storyboard.LAYERS.size() - 1, -1, -1):
		var layer: String = Storyboard.LAYERS[layer_index]
		if hidden_layers.has(layer) or locked_layers.has(layer):
			continue
		var best := -1
		var best_order := -1
		for item in _items:
			if String(item["layer"]) != layer:
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
			if not Rect2(-(geo["anchor"] as Vector2), geo["size"]).has_point(local):
				continue
			var order := int((sprite as Storyboard.Sprite).order)
			if order >= best_order:
				best_order = order
				best = int(_index_of.get(sprite, -1))
		if best >= 0:
			return best
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
		bounds = bounds.expand(pos + (corner as Vector2).rotated(rot) * sprite_scale)
	return bounds


func _commit_marquee() -> void:
	if _marquee.size.length() < 3.0:
		return
	var layout := _layout()
	var hits: Array[int] = []
	for item in _items:
		if hidden_layers.has(String(item["layer"])) or locked_layers.has(String(item["layer"])):
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
			# 按下就选中：否则拖动未选中的对象会去拖上一次选中的东西。
			if _pressed_hit >= 0 and not _pressed_additive:
				_toggle_or_select(_pressed_hit, false)
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


## Esc 取消当前的按下/拖动/框选/平移。返回 true 表示有交互被取消。
func cancel_interaction() -> bool:
	var active := _pending or _dragging or _marquee_active or _panning
	_pending = false
	_dragging = false
	_marquee_active = false
	_panning = false
	_drag_indices.clear()
	_drag_bases.clear()
	_marquee = Rect2()
	queue_redraw()
	return active


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
	else:
		selected = hit
	selection_changed.emit(selected_items)
	queue_redraw()


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


class MaskLayer extends Control:
	var canvas = null

	func _draw() -> void:
		if canvas != null:
			canvas._draw_mask(self)


class UiLayer extends Control:
	var canvas = null

	func _draw() -> void:
		if canvas != null:
			canvas._draw_ui(self)
