extends Control

## Topmost transparent overlay for the 3D preview. Kept as a separate Control
## so text and hit feedback stay crisp and are not affected by 3D projection.


var preview: Control
## true 时只画光标层（鼠标移动时不必重绘整个场景）。
var cursor_only: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if preview == null:
		return
	if cursor_only:
		if preview.has_method("draw_cursor_overlay"):
			preview.draw_cursor_overlay(self)
	elif preview.has_method("draw_overlay"):
		preview.draw_overlay(self)
