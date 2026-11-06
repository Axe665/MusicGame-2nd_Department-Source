class_name TimingChart
extends Control

## 结算页的判定偏差直方图：横轴 ±150ms，零线居中。

const SPAN_MS := 150.0
const BIN_MS := 3.0
const AXIS_STEP_MS := 30.0

var errors: Array[float] = []


func set_errors(values: Array[float]) -> void:
	errors = values.duplicate()
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.22))
	if w < 40.0 or h < 40.0:
		return
	var baseline := h - 22.0
	var mono := UITheme.mono_font()
	var zero_x := w * 0.5
	var half := int(SPAN_MS / BIN_MS)
	if errors.is_empty():
		draw_string(mono, Vector2(zero_x - 42, h * 0.5), "无判定样本", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.MUTED)
		return
	var bins := {}
	var peak := 0
	for error in errors:
		var index := clampi(int(round(error / BIN_MS)), -half, half)
		var count := int(bins.get(index, 0)) + 1
		bins[index] = count
		peak = maxi(peak, count)
	var bar_width := (w - 24.0) / float(half * 2 + 1)
	var usable_height := baseline - 16.0
	for index in bins.keys():
		var count := int(bins[index])
		var bar_height := maxf(2.0, usable_height * float(count) / float(maxi(1, peak)))
		var x := zero_x + float(index) * bar_width
		var centered := absi(int(index)) <= 1
		var color := Color(0.93, 0.98, 1.0, 1.0) if centered else Color(0.42, 0.72, 1.0, 0.92)
		draw_rect(Rect2(Vector2(x - bar_width * 0.42, baseline - bar_height), Vector2(bar_width * 0.84, bar_height)), color)
	# 零线和刻度
	draw_line(Vector2(12, baseline), Vector2(w - 12, baseline), Color(1, 1, 1, 0.20), 1.0)
	draw_line(Vector2(zero_x, 12), Vector2(zero_x, baseline), Color(1, 1, 1, 0.30), 1.0)
	var step := int(AXIS_STEP_MS / BIN_MS)
	for i in range(-step * 5, step * 5 + 1, step):
		var x := zero_x + float(i) * bar_width
		draw_line(Vector2(x, baseline), Vector2(x, baseline + 4.0), Color(1, 1, 1, 0.22), 1.0)
		var text := "%+d" % int(round(float(i) * BIN_MS))
		if i == 0:
			text = "0"
		draw_string(mono, Vector2(x - 14.0, baseline + 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.MUTED)
	# 平均偏差标记
	var mean := 0.0
	for error in errors:
		mean += error
	mean /= float(errors.size())
	var mean_x := zero_x + mean / BIN_MS * bar_width
	draw_line(Vector2(mean_x, 10), Vector2(mean_x, baseline), Color(1.0, 0.86, 0.35, 0.95), 1.6)
