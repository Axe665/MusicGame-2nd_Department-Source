extends Control

## Topmost transparent overlay for the 3D preview. Kept as a separate Control
## so text and hit feedback stay crisp and are not affected by 3D projection.


var preview: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if preview != null and preview.has_method("draw_overlay"):
		preview.draw_overlay(self)
