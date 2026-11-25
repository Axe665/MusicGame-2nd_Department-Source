extends Control

## Topmost transparent overlay for the 3D preview. Kept as a separate Control
## so text and hit feedback stay crisp and are not affected by 3D projection.


var preview: Control
## true 时只画光标层（鼠标移动时不必重绘整个场景）。
var cursor_only: bool = false
## 只画某一层（stage/bars/combo/seek/limit/path/hold/notes/fx/hud）。
## 空字符串 = 旧的全量 draw_overlay；Overlay 根节点不再自己绘制。
var layer_name: String = ""
## true 时只画 storyboard 的背景层（垫在 3D 环下面）。
var storyboard_background: bool = false
## true 时画 storyboard 的加色层（前景/背景由 additive_front 决定）。
var storyboard_additive: bool = false
## true 时画 storyboard 的 Foreground（在判定环之上、音符之下）。
var storyboard_front: bool = false
## true 时画 storyboard 的 Overlay（在所有音符之上）。
var storyboard_overlay: bool = false
var additive_front: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if preview == null:
		return
	if storyboard_background:
		if preview.has_method("draw_storyboard_background"):
			preview.draw_storyboard_background(self)
	elif storyboard_front:
		if preview.has_method("draw_storyboard_front"):
			preview.draw_storyboard_front(self)
	elif storyboard_overlay:
		if preview.has_method("draw_storyboard_overlay"):
			preview.draw_storyboard_overlay(self)
	elif storyboard_additive:
		var method := "draw_storyboard_additive_front" if additive_front else "draw_storyboard_additive_background"
		if preview.has_method(method):
			preview.call(method, self)
	elif cursor_only:
		if preview.has_method("draw_cursor_overlay"):
			preview.draw_cursor_overlay(self)
	elif not layer_name.is_empty():
		if preview.has_method("draw_layer"):
			preview.draw_layer(layer_name, self)
	elif preview.has_method("draw_overlay"):
		preview.draw_overlay(self)
