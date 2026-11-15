class_name JudgeScatter
extends Control

## 结算页的判定散布图（Etterna 风格）：
##   横轴 = 歌曲时间，纵轴 = 判定偏移（上 Late / 下 Early），
##   每个点是一次命中，颜色按判定等级区分；横线是 0ms 与各判定窗口。
const SPAN_MS := 180.0
const DOT_RADIUS := 1.35

var hits: Array[Dictionary] = []
var duration_ms: float = 0.0


func set_hits(values: Array, total_ms: float = 0.0) -> void:
	hits.clear()
	for hit in values:
		if hit is Dictionary:
			hits.append(hit)
	duration_ms = maxf(0.0, total_ms)
	queue_redraw()


static func tier_color(tier: String) -> Color:
	match tier:
		"PERFECT":
			return Color(0.62, 0.88, 1.0)
		"GREAT":
			return Color(0.98, 0.86, 0.36)
		"GOOD":
			return Color(0.56, 0.90, 0.56)
		"BAD":
			return Color(1.0, 0.58, 0.34)
		"MISS":
			return Color(1.0, 0.36, 0.36)
		_:
			return Color(0.85, 0.88, 0.95)


static func _clock(ms: float) -> String:
	var total := maxi(0, int(round(ms / 1000.0)))
	return "%d:%02d" % [total / 60, total % 60]


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))
	if w < 90.0 or h < 70.0:
		return
	var mono := UITheme.mono_font()
	var left := 58.0
	var right := w - 12.0
	var top := 16.0
	var bottom := h - 20.0
	var mid := (top + bottom) * 0.5
	var half_height := (bottom - top) * 0.5
	# 判定窗口横线：±65 / ±115 / ±170
	for window_ms: float in [65.0, 115.0, 170.0]:
		for direction: float in [-1.0, 1.0]:
			var y: float = mid - direction * window_ms / SPAN_MS * half_height
			draw_line(Vector2(left, y), Vector2(right, y), Color(1, 1, 1, 0.07), 1.0)
	draw_line(Vector2(left, mid), Vector2(right, mid), Color(1, 1, 1, 0.30), 1.0)
	draw_line(Vector2(left, top), Vector2(left, bottom), Color(1, 1, 1, 0.14), 1.0)
	draw_line(Vector2(left, bottom), Vector2(right, bottom), Color(1, 1, 1, 0.14), 1.0)
	# 纵轴标注（与参考图一致：上 Late / 下 Early）
	draw_string(mono, Vector2(4.0, top + 9.0), "Late", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.72, 0.72, 0.9))
	draw_string(mono, Vector2(2.0, top + 20.0), "+%dms" % int(SPAN_MS), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
	draw_string(mono, Vector2(1.0, bottom - 1.0), "Early", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.86, 1.0, 0.9))
	draw_string(mono, Vector2(2.0, bottom - 12.0), "−%dms" % int(SPAN_MS), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
	if hits.is_empty():
		draw_string(mono, Vector2((left + right) * 0.5 - 48.0, mid), "无判定样本", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.MUTED)
		return
	var span := duration_ms
	if span <= 1.0:
		var low := INF
		var high := -INF
		for hit in hits:
			var t := float(hit.get("time", 0.0))
			low = minf(low, t)
			high = maxf(high, t)
		span = maxf(1.0, high - low)
	var sum := 0.0
	for hit in hits:
		var offset := clampf(float(hit.get("offset", 0.0)), -SPAN_MS, SPAN_MS)
		sum += offset
		var time_ms := clampf(float(hit.get("time", 0.0)), 0.0, span)
		var x := left + time_ms / span * (right - left)
		var y := mid - offset / SPAN_MS * half_height
		var color := tier_color(String(hit.get("tier", "")))
		draw_circle(Vector2(x, y), DOT_RADIUS, Color(color.r, color.g, color.b, 0.9))
	# 平均偏移：一条横线
	var mean := sum / float(hits.size())
	var mean_y := mid - clampf(mean, -SPAN_MS, SPAN_MS) / SPAN_MS * half_height
	draw_line(Vector2(left, mean_y), Vector2(right, mean_y), Color(1.0, 0.86, 0.35, 0.75), 1.2)
	# 顶部信息：样本数 / 平均 / 时间范围
	var info := "判定散布 %d 次，平均 %+.1fms，%s – %s" % [hits.size(), mean, _clock(0.0), _clock(span)]
	var info_w := mono.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(mono, Vector2(right - info_w, top - 5.0), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.78, 0.88))
