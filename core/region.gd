class_name Region
extends RefCounted

var id: int = 1
var kind: String = "limit"
var start_beat: float = 0.0
var end_beat: float = 1.0
var angle: float = 0.0
var width: float = 90.0
var polarity: int = 1
var shape: String = ""


func _init(p_id: int = 1, p_start: float = 0.0, p_end: float = 1.0) -> void:
	id = p_id
	start_beat = p_start
	end_beat = p_end


func duration() -> float:
	return maxf(0.0, end_beat - start_beat)


func active_at(beat: float) -> bool:
	return beat + 0.000001 >= start_beat and beat - 0.000001 <= end_beat


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"start_beat": snappedf(start_beat, 0.001),
		"end_beat": snappedf(end_beat, 0.001),
		"angle": snappedf(angle, 0.001),
		"width": snappedf(width, 0.001),
		"polarity": polarity,
		"shape": shape,
	}


static func from_dict(data: Dictionary) -> Region:
	var region := Region.new(
		int(data.get("id", 1)),
		float(data.get("start_beat", 0.0)),
		float(data.get("end_beat", 1.0))
	)
	region.kind = String(data.get("kind", "limit"))
	if region.kind == "red":
		region.kind = "limit"
	region.angle = float(data.get("angle", 0.0))
	region.width = float(data.get("width", 90.0))
	region.polarity = int(data.get("polarity", 1))
	region.shape = String(data.get("shape", ""))
	return region


func to_code() -> String:
	return "[%d]red(%s,%s,%s)" % [
		id, str(snappedf(start_beat, 0.001)), str(snappedf(end_beat, 0.001)),
		str(snappedf(width, 0.001))
	]


static func from_code(code: String) -> Region:
	var text := code.strip_edges()
	var close := text.find("]")
	var open := text.find("(")
	var end := text.rfind(")")
	if close <= 1 or open < 0 or end <= open:
		return null
	var region := Region.new(int(text.substr(1, close - 1)), 0.0, 1.0)
	var parts := text.substr(open + 1, end - open - 1).split(",", true)
	if parts.size() > 0:
		region.start_beat = float(parts[0])
		region.end_beat = float(parts[1]) if parts.size() > 1 else region.start_beat
		region.width = float(parts[2]) if parts.size() > 2 else 90.0
	region.kind = "limit"
	region.angle = 0.0
	return region
