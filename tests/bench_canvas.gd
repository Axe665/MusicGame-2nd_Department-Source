extends ChartCanvas

var draw_us: int = 0
var draw_count: int = 0
var total_us: int = 0


func _draw() -> void:
	var started := Time.get_ticks_usec()
	super._draw()
	draw_us = Time.get_ticks_usec() - started
	total_us += draw_us
	draw_count += 1
