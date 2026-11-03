class_name TimingPoint
extends RefCounted

var beat: float = 0.0
var bpm: float = 120.0
var beats_per_bar: int = 4


func _init(p_beat: float = 0.0, p_bpm: float = 120.0, p_beats_per_bar: int = 4) -> void:
	beat = p_beat
	bpm = p_bpm
	beats_per_bar = p_beats_per_bar


func to_dict() -> Dictionary:
	return {
		"beat": snappedf(beat, 0.001),
		"bpm": snappedf(bpm, 0.001),
		"beats_per_bar": beats_per_bar,
	}


static func from_dict(data: Dictionary) -> TimingPoint:
	return TimingPoint.new(
		float(data.get("beat", 0.0)),
		float(data.get("bpm", 120.0)),
		int(data.get("beats_per_bar", 4))
	)
