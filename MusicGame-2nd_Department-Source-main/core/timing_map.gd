class_name TimingMap
extends RefCounted

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
