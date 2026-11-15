class_name ChartGhostLayer
extends ChartCanvas

## Half-transparent preview for copied/cut notes. It reuses ChartCanvas's note
## drawing routines but skips the grid, regions and interaction.

var ghost_notes: Array[Note] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate = Color(1.0, 1.0, 1.0, 0.5)
	set_process(false)


func _show_type_label(_note: Note) -> bool:
	return false


func _draw() -> void:
	if _app == null:
		return
	var plot := _plot_rect()
	for note in ghost_notes:
		match note.type:
			"tap":
				_draw_tap(note)
			"hold":
				_draw_hold(note)
			"path":
				_draw_path(note)
			"seek":
				_draw_seek(note)
			"anchor":
				_draw_anchor(note)
			"bell":
				_draw_bell(note)
