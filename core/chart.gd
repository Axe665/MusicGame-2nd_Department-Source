class_name Chart
extends RefCounted

var format_version: int = 1
var audio_path: String = ""
var video_path: String = ""
var video_offset_ms: float = 0.0
var video_fps: float = 60.0
var video_opacity: float = 0.35
var pre_read_ms: float = 1000.0
var offset_ms: float = 0.0
var difficulty: String = "Normal"
var metadata: Dictionary = {
	"title": "未命名谱面",
	"artist": "",
	"creator": "",
	"version": "",
	"tags": "",
	"license": "",
	"background": "",
}
var timing: TimingMap = TimingMap.new()
var default_shape_id: String = "S0"
var shapes: Dictionary = {}
var events: Array[BoundaryEvent] = []
var view_states: Array[ViewState] = []
var regions: Array[Region] = []
var notes: Array[Note] = []
var editor: Dictionary = {}

var _next_note_id: int = 1
var _next_region_id: int = 1
var _next_event_id: int = 1


func _init() -> void:
	shapes["S0"] = BoundaryShape.circle("S0", 330.0, 32)
	view_states = [ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear")]


func get_shape(shape_id: String) -> BoundaryShape:
	return shapes.get(shape_id, null)


func get_default_shape() -> BoundaryShape:
	var shape: BoundaryShape = get_shape(default_shape_id)
	if shape == null and not shapes.is_empty():
		shape = shapes.values()[0]
	return shape


func sorted_shapes() -> Array[BoundaryShape]:
	var result: Array[BoundaryShape] = []
	for shape in shapes.values():
		if shape is BoundaryShape:
			result.append(shape)
	result.sort_custom(func(a: BoundaryShape, b: BoundaryShape) -> bool: return a.id < b.id)
	return result


func sorted_notes() -> Array[Note]:
	var result := notes.duplicate()
	result.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	return result


func next_note_id() -> int:
	var result := _next_note_id
	_next_note_id += 1
	return result


func next_region_id() -> int:
	var result := _next_region_id
	_next_region_id += 1
	return result


func next_event_id() -> String:
	var result := "E%d" % _next_event_id
	_next_event_id += 1
	return result


func refresh_ids() -> void:
	var max_note := 0
	for note in notes:
		max_note = maxi(max_note, note.id)
	_next_note_id = max_note + 1
	var max_region := 0
	for region in regions:
		max_region = maxi(max_region, region.id)
	_next_region_id = max_region + 1
	var max_event := 0
	for event in events:
		var digits := event.id.trim_prefix("E")
		if digits.is_valid_int():
			max_event = maxi(max_event, int(digits))
	_next_event_id = max_event + 1


func notes_at(beat: float, tolerance: float = 0.001) -> Array[Note]:
	var result: Array[Note] = []
	for note in notes:
		if absf(note.beat - beat) <= tolerance:
			result.append(note)
	return result


func regions_at(beat: float) -> Array[Region]:
	var result: Array[Region] = []
	for region in regions:
		if region.active_at(beat):
			result.append(region)
	return result


func beat_to_ms(beat: float) -> float:
	return timing.beat_to_chart_ms(beat)


func ms_to_beat(ms: float) -> float:
	return timing.chart_ms_to_beat(ms)


func duration_beats() -> float:
	var last := 0.0
	for note in notes:
		last = maxf(last, maxf(note.beat, note.end_beat))
	for region in regions:
		last = maxf(last, region.end_beat)
	for event in events:
		last = maxf(last, event.end_beat + maxf(0.0, event.restore_duration))
	return last


func bar_length() -> float:
	return float(timing.beats_per_bar_at(0.0))
