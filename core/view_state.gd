class_name ViewState
extends RefCounted

var beat: float = 0.0
var zoom: float = 1.0
var tilt_x: float = 0.0
var tilt_y: float = 0.0
var ellipse: float = 1.0
var rotation: float = 0.0
var easing: String = "linear"
## 稳定身份：多选、撤销、拖拽都按 id 找键，不靠数组下标。
var id: int = 0
## 每段一条 cubic-bezier；空数组 = 用 easing 预设。
var curve: Array = []


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
	var data := {
		"beat": snappedf(beat, 0.001),
		"zoom": snappedf(zoom, 0.001),
		"tilt_x": snappedf(tilt_x, 0.001),
		"tilt_y": snappedf(tilt_y, 0.001),
		"ellipse": snappedf(ellipse, 0.001),
		"rotation": snappedf(rotation, 0.001),
		"easing": easing,
	}
	if id > 0:
		data["id"] = id
	if curve.size() == 4:
		data["curve"] = [snappedf(float(curve[0]), 0.001), snappedf(float(curve[1]), 0.001),
			snappedf(float(curve[2]), 0.001), snappedf(float(curve[3]), 0.001)]
	return data


static func from_dict(data: Dictionary) -> ViewState:
	var state := ViewState.new(
		float(data.get("beat", 0.0)),
		float(data.get("zoom", 1.0)),
		float(data.get("tilt_x", 0.0)),
		float(data.get("tilt_y", 0.0)),
		float(data.get("ellipse", 1.0)),
		float(data.get("rotation", 0.0)),
		String(data.get("easing", "linear"))
	)
	state.id = int(data.get("id", 0))
	var raw_curve: Variant = data.get("curve", [])
	if raw_curve is Array and (raw_curve as Array).size() == 4:
		for value in raw_curve:
			state.curve.append(float(value))
	return state


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
	var sorted: Array[ViewState] = states
	if not _is_sorted(states):
		sorted = []
		for state in states:
			sorted.append(state)
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
			# 缓动归左帧（出向），和形状关键帧一致；曲线优先于预设。
			var p := Ease.apply_curve(a.easing, a.curve, (beat - a.beat) / span)
			# 旋转走最短弧：350°→10° 是 +20°，不是反向绕 340°。
			var turn := JudgeMath.angle_delta(a.rotation, b.rotation)
			return {
				"zoom": lerpf(a.zoom, b.zoom, p),
				"rotation": wrapf(a.rotation + turn * p, -180.0, 180.0),
				"tilt_x": lerpf(a.tilt_x, b.tilt_x, p),
				"tilt_y": lerpf(a.tilt_y, b.tilt_y, p),
				"ellipse": lerpf(a.ellipse, b.ellipse, p),
			}
	return _state_dict(sorted[-1])


static func _is_sorted(states: Array[ViewState]) -> bool:
	for i in range(1, states.size()):
		if states[i].beat < states[i - 1].beat:
			return false
	return true


static func _state_dict(state: ViewState) -> Dictionary:
	return {
		"zoom": state.zoom,
		"tilt_x": state.tilt_x,
		"tilt_y": state.tilt_y,
		"ellipse": state.ellipse,
		"rotation": state.rotation,
	}
