class_name TimingMap
extends RefCounted

const MAX_BEAT_SUBDIVISIONS := 64
const MAX_VERTICAL_LINES := 64

var points: Array[TimingPoint] = []
var offset_ms: float = 0.0


func _init() -> void:
	points = [TimingPoint.new(0.0, 120.0, 4)]


func sort_points() -> void:
	points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool: return a.beat < b.beat)
	if points.is_empty():
		points = [TimingPoint.new(0.0, 120.0, 4)]
	var deduped: Array[TimingPoint] = []
	for point in points:
		if not deduped.is_empty() and is_equal_approx(deduped[-1].beat, point.beat):
			deduped[-1] = point
		else:
			deduped.append(point)
	points = deduped


func bpm_at(beat: float) -> float:
	var result := 120.0
	for point in points:
		if point.beat <= beat + 0.0001:
			result = point.bpm
		else:
			break
	return result


func beats_per_bar_at(beat: float) -> int:
	var result := 4
	for point in points:
		if point.beat <= beat + 0.0001:
			result = point.beats_per_bar
		else:
			break
	return maxi(result, 1)


func beat_to_chart_ms(beat: float) -> float:
	sort_points()
	if beat < 0.0:
		return beat * 60000.0 / maxf(0.001, bpm_at(0.0))
	var cursor := 0.0
	var ms := 0.0
	var bpm := bpm_at(0.0)
	for point in points:
		if point.beat <= 0.0:
			bpm = point.bpm
			continue
		if point.beat >= beat:
			break
		ms += (point.beat - cursor) * 60000.0 / maxf(0.001, bpm)
		cursor = point.beat
		bpm = point.bpm
	ms += (beat - cursor) * 60000.0 / maxf(0.001, bpm)
	return ms


func chart_ms_to_beat(ms: float) -> float:
	sort_points()
	if ms < 0.0:
		return ms * maxf(0.001, bpm_at(0.0)) / 60000.0
	var cursor := 0.0
	var bpm := bpm_at(0.0)
	var remaining := ms
	for point in points:
		if point.beat <= 0.0:
			bpm = point.bpm
			continue
		var span_ms := (point.beat - cursor) * 60000.0 / maxf(0.001, bpm)
		if remaining <= span_ms:
			return cursor + remaining * maxf(0.001, bpm) / 60000.0
		remaining -= span_ms
		cursor = point.beat
		bpm = point.bpm
	return cursor + remaining * maxf(0.001, bpm) / 60000.0


func beat_to_audio_ms(beat: float) -> float:
	return beat_to_chart_ms(beat) - offset_ms


func audio_ms_to_beat(audio_ms: float) -> float:
	return chart_ms_to_beat(audio_ms + offset_ms)


static func parse_positive_int(text: String, max_value: int) -> int:
	## Shared editor input rule: only positive integers within the drawable
	## range are accepted; anything else returns 0.
	var clean := text.strip_edges()
	if clean.is_empty() or not clean.is_valid_int():
		return 0
	var value := int(clean)
	if value < 1 or value > max_value:
		return 0
	return value


static func parse_beat_subdivision(text: String) -> int:
	return parse_positive_int(text, MAX_BEAT_SUBDIVISIONS)


static func parse_vertical_lines(text: String) -> int:
	return parse_positive_int(text, MAX_VERTICAL_LINES)


static func normalize_bpm(value: float) -> float:
	## Keep at most three decimals. A BPM whose rounded fraction has only one
	## decimal digit is rounded to the nearest integer, as requested by the
	## new-chart import flow.
	var rounded := roundf(value * 1000.0) / 1000.0
	var fraction := absf(rounded - roundf(rounded))
	var thousandths := int(roundf(fraction * 1000.0))
	if thousandths > 0 and thousandths % 100 == 0:
		return roundf(rounded)
	return rounded


static func normalize_offset_ms(value: float) -> float:
	var rounded := roundf(value * 1000.0) / 1000.0
	return 0.0 if is_zero_approx(rounded) else rounded


static func beat_subdivision_offsets(divisions: int) -> PackedFloat32Array:
	## Offsets inside one beat, excluding the beat line itself. For example
	## 4 returns [0.25, 0.5, 0.75], i.e. 4−1 thin lines split the beat in 4.
	var offsets := PackedFloat32Array()
	var count := clampi(divisions, 1, MAX_BEAT_SUBDIVISIONS)
	if count <= 1:
		return offsets
	var step := 1.0 / float(count)
	for index in range(1, count):
		offsets.append(step * float(index))
	return offsets


static func vertical_line_offsets(count: int) -> PackedFloat32Array:
	## N interior vertical lines, evenly spaced across u∈(0,1). They split
	## the editing area into N+1 intervals; together with the two plot edges
	## there are N+2 visible vertical boundaries.
	var offsets := PackedFloat32Array()
	var lines := mini(count, MAX_VERTICAL_LINES)
	if lines <= 0:
		return offsets
	var step := 1.0 / float(lines + 1)
	for index in range(1, lines + 1):
		offsets.append(step * float(index))
	return offsets


static func nearest_beat_subdivision(beat: float, divisions: int) -> float:
	## Nearest horizontal 小节线 position: beat lines plus the N−1 fine lines
	## configured by the 小节线 input. The whole grid is recalculated from the
	## current N so changing the input immediately changes the snap targets.
	var count := clampi(divisions, 1, MAX_BEAT_SUBDIVISIONS)
	var step := 1.0 / float(count)
	return roundf(beat / step) * step


static func nearest_vertical_line_u(u: float, count: int) -> float:
	## Nearest interior vertical line in u space, clamped to the outermost
	## interior lines so the plot edges are not silently used as snap targets.
	var lines := mini(count, MAX_VERTICAL_LINES)
	if lines <= 0:
		return clampf(u, 0.0, 1.0)
	var step := 1.0 / float(lines + 1)
	var index := clampi(roundi(u / step), 1, lines)
	return float(index) * step


func format_beat(beat: float, divide: int = 4) -> String:
	var bpb := float(beats_per_bar_at(beat))
	var bar := floori(beat / bpb)
	var within := beat - float(bar) * bpb
	var unit := roundi((within / bpb) * float(divide))
	if unit >= divide:
		bar += 1
		unit -= divide
	return "%d:%d:%d" % [bar, unit, divide]


func parse_beat(text: String) -> float:
	var clean := text.strip_edges()
	if clean.contains(":"):
		var parts := clean.split(":")
		if parts.size() >= 2:
			var bar := float(parts[0])
			var numerator := float(parts[1])
			var denominator := float(parts[2]) if parts.size() > 2 else 4.0
			var bpb := float(beats_per_bar_at(0.0))
			return bar * bpb + (numerator / maxf(0.001, denominator)) * bpb
	return float(clean)
