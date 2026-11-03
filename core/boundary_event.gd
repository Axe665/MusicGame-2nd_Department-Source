class_name BoundaryEvent
extends RefCounted

var id: String = "E0"
var start_beat: float = 0.0
var end_beat: float = 1.0
var target_u0: float = 0.0
var target_u1: float = 1.0
var from_shape: String = "S0"
var to_shape: String = "S0"
var easing: String = "in-out"
var end_behavior: String = "restore"
var restore_duration: float = 0.5
var restore_easing: String = "in-out"


func _init(
	p_id: String = "E0",
	p_start: float = 0.0,
	p_end: float = 1.0,
	p_u0: float = 0.0,
	p_u1: float = 1.0,
	p_from: String = "S0",
	p_to: String = "S0"
) -> void:
	id = p_id
	start_beat = p_start
	end_beat = p_end
	target_u0 = p_u0
	target_u1 = p_u1
	from_shape = p_from
	to_shape = p_to


func duration() -> float:
	return maxf(0.0, end_beat - start_beat)


func covers_u(u: float) -> bool:
	return u + 0.000001 >= target_u0 and u - 0.000001 <= target_u1


func covers_beat(beat: float) -> bool:
	return beat + 0.000001 >= start_beat and beat - 0.000001 <= end_beat


func to_dict() -> Dictionary:
	return {
		"id": id,
		"start_beat": snappedf(start_beat, 0.001),
		"end_beat": snappedf(end_beat, 0.001),
		"target_u0": snappedf(target_u0, 0.0001),
		"target_u1": snappedf(target_u1, 0.0001),
		"from_shape": from_shape,
		"to_shape": to_shape,
		"easing": easing,
		"end_behavior": end_behavior,
		"restore_duration": snappedf(restore_duration, 0.001),
		"restore_easing": restore_easing,
	}


static func from_dict(data: Dictionary) -> BoundaryEvent:
	var event := BoundaryEvent.new(
		String(data.get("id", "E0")),
		float(data.get("start_beat", 0.0)),
		float(data.get("end_beat", 1.0)),
		float(data.get("target_u0", 0.0)),
		float(data.get("target_u1", 1.0)),
		String(data.get("from_shape", "S0")),
		String(data.get("to_shape", "S0"))
	)
	event.easing = String(data.get("easing", "in-out"))
	event.end_behavior = String(data.get("end_behavior", "restore"))
	event.restore_duration = float(data.get("restore_duration", 0.5))
	event.restore_easing = String(data.get("restore_easing", "in-out"))
	return event
