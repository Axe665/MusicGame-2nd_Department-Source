extends Preview3D

var draw_us: int = 0
var draw_count: int = 0
var total_us: int = 0


func draw_overlay(canvas: Control) -> void:
	var started := Time.get_ticks_usec()
	super.draw_overlay(canvas)
	draw_us = Time.get_ticks_usec() - started
	total_us += draw_us
	draw_count += 1
