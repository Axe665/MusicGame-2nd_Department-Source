class_name ViewState
extends RefCounted

var beat: float = 0.0
var zoom: float = 1.0
var tilt_x: float = 0.0
var tilt_y: float = 0.0
var ellipse: float = 1.0
var rotation: float = 0.0
var easing: String = "linear"


func _init(
	p_beat: float = 0.0,
	p_zoom: float = 1.0,
	p_tilt_x: float = 0.0,
	p_tilt_y: float = 0.0,
	p_ellipse: float = 1.0,
	p_rotation: float = 0.0,
	p_easing: String = "linear"
) -> void:
	beat = p_beat
	zoom = p_zoom
	tilt_x = p_tilt_x
	tilt_y = p_tilt_y
	ellipse = p_ellipse
	rotation = p_rotation
	easing = p_easing


func to_dict() -> Dictionary:
	return {
		"beat": snappedf(beat, 0.001),
		"zoom": snappedf(zoom, 0.001),
		"tilt_x": snappedf(tilt_x, 0.001),
		"tilt_y": snappedf(tilt_y, 0.001),
		"ellipse": snappedf(ellipse, 0.001),
		"rotation": snappedf(rotation, 0.001),
		"easing": easing,
	}


static func from_dict(data: Dictionary) -> ViewState:
	return ViewState.new(
		float(data.get("beat", 0.0)),
		float(data.get("zoom", 1.0)),
		float(data.get("tilt_x", 0.0)),
		float(data.get("tilt_y", 0.0)),
		float(data.get("ellipse", 1.0)),
		float(data.get("rotation", 0.0)),
		String(data.get("easing", "linear"))
	)


static func default_state() -> Dictionary:
	return {
		"zoom": 1.0,
		"tilt_x": 0.0,
		"tilt_y": 0.0,
		"ellipse": 1.0,
		"rotation": 0.0,
	}


static func evaluate(states: Array[ViewState], beat: float) -> Dictionary:
	if states.is_empty():
		return default_state()
	var sorted := states.duplicate()
	sorted.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
	if beat <= sorted[0].beat:
		return _state_dict(sorted[0])
	if beat >= sorted[-1].beat:
		return _state_dict(sorted[-1])
	for i in sorted.size() - 1:
		var a: ViewState = sorted[i]
		var b: ViewState = sorted[i + 1]
		if beat >= a.beat and beat <= b.beat:
			var span := maxf(0.000001, b.beat - a.beat)
			var p := Ease.apply(b.easing, (beat - a.beat) / span)
			# zoom/rotation 平滑插值；tilt/ellipse 到关键帧瞬切（不动就按左帧）。
			return {
				"zoom": lerpf(a.zoom, b.zoom, p),
				"rotation": lerpf(a.rotation, b.rotation, p),
				"tilt_x": a.tilt_x,
				"tilt_y": a.tilt_y,
				"ellipse": a.ellipse,
			}
	return _state_dict(sorted[-1])


static func _state_dict(state: ViewState) -> Dictionary:
	return {
		"zoom": state.zoom,
		"tilt_x": state.tilt_x,
		"tilt_y": state.tilt_y,
		"ellipse": state.ellipse,
		"rotation": state.rotation,
	}
