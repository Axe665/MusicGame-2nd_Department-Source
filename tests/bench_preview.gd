extends Preview3D

var draw_us: int = 0
var draw_count: int = 0
var total_us: int = 0
var t_paths: int = 0
var t_holds: int = 0
var t_notes: int = 0
var t_hud: int = 0
var t_cursor: int = 0
var t_other: int = 0


func draw_overlay(canvas: Control) -> void:
	var started := Time.get_ticks_usec()
	super.draw_overlay(canvas)
	draw_us = Time.get_ticks_usec() - started
	total_us += draw_us
	draw_count += 1


func _draw_paths(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_paths(canvas, chart, t, pre)
	t_paths += Time.get_ticks_usec() - s


func _draw_holds(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_holds(canvas, chart, t, pre)
	t_holds += Time.get_ticks_usec() - s


func _draw_notes(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_notes(canvas, chart, t, pre)
	t_notes += Time.get_ticks_usec() - s


func _draw_hud_live(canvas: Control, chart: Chart, t: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_hud_live(canvas, chart, t)
	t_hud += Time.get_ticks_usec() - s


func _draw_hud_static(canvas: Control, chart: Chart, t: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_hud_static(canvas, chart, t)
	t_hud += Time.get_ticks_usec() - s


func _draw_cursor(canvas: Control, chart: Chart, t: float) -> void:
	var s := Time.get_ticks_usec()
	super._draw_cursor(canvas, chart, t)
	t_cursor += Time.get_ticks_usec() - s


func summary() -> String:
	# 走分层路径时 draw_overlay 不会被调用，帧数只能用 _perf_frames。
	var f := float(maxi(1, _perf_frames)) * 1000.0
	return "paths=%.2f holds=%.2f notes=%.2f hud=%.2f cursor=%.2f" % [
		float(t_paths) / f, float(t_holds) / f,
		float(t_notes) / f, float(t_hud) / f, float(t_cursor) / f,
	]
