class_name SeekBar
extends Control

## 播放进度条：可点击、可拖动。只负责画和报告位置，跳转逻辑交给外面。
## 编辑器里替代只会显示的 ProgressBar，播放中拖动会立刻打断播放并重新对齐音频。

signal seek_to(fraction: float)

const TRACK_HEIGHT := 6.0
const KNOB_IDLE := 5.5
const KNOB_HOT := 7.5

var progress: float = 0.0
var _hovered: bool = false
var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(160.0, 18.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "点击或拖动跳转播放位置（播放中也可以）"
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw()
	)


func set_progress(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if absf(next - progress) < 0.0004:
		return
	progress = next
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_seek(event.position.x)
			queue_redraw()
			accept_event()
		elif _dragging:
			_dragging = false
			queue_redraw()
			accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		_seek(event.position.x)
		accept_event()


func _seek(local_x: float) -> void:
	seek_to.emit(clampf(local_x / maxf(1.0, size.x), 0.0, 1.0))


func _draw() -> void:
	var mid := size.y * 0.5
	var half := TRACK_HEIGHT * 0.5
	draw_rect(Rect2(0.0, mid - half, size.x, TRACK_HEIGHT), Color(1, 1, 1, 0.09), true)
	draw_line(Vector2(0.0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.14), 1.0)
	var filled := size.x * progress
	if filled > 0.5:
		draw_rect(Rect2(0.0, mid - half, filled, TRACK_HEIGHT), UITheme.GOLD, true)
		draw_rect(Rect2(0.0, mid - half, filled, 1.5), Color(1, 1, 1, 0.55), true)
	var hot := _hovered or _dragging
	var knob := KNOB_HOT if hot else KNOB_IDLE
	var center := Vector2(filled, mid)
	draw_circle(center, knob + 4.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.20 if hot else 0.12))
	draw_circle(center, knob, Color(1, 1, 1, 0.97))
	draw_arc(center, knob, 0.0, TAU, 28, UITheme.GOLD, 2.0, true)
	if _dragging:
		# 拖动时给一条细竖线，方便看清落点。
		draw_line(Vector2(filled, 1.0), Vector2(filled, size.y - 1.0), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1.0)
