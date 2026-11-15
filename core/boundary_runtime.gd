class_name BoundaryRuntime
extends RefCounted

## Shared C(u,t) evaluator. The preview, validation and playtest all call this.
## Events only touch the target u range; notes' u/time/width are never modified.


static func eval_point(chart: Chart, u: float, beat: float) -> Dictionary:
	var pair := pair_at(chart, beat)
	if pair.is_empty():
		var base := chart.get_default_shape()
		if base == null:
			return {"point": Vector2.ZERO, "gap": true}
		return base.point_at(u)
	var from_point: Dictionary = (pair["from"] as BoundaryShape).point_at(u)
	var to_point: Dictionary = (pair["to"] as BoundaryShape).point_at(u)
	var p := float(pair["p"])
	return {
		"point": (from_point.point as Vector2).lerp(to_point.point, p),
		"gap": bool(from_point.gap) if p < 0.5 else bool(to_point.gap),
		"segment": null,
	}


static func eval_shape(chart: Chart, beat: float, samples: int = 256) -> Array[Dictionary]:
	var count := maxi(samples, 8)
	var result: Array[Dictionary] = []
	var pair := pair_at(chart, beat)
	if pair.is_empty():
		var base := chart.get_default_shape()
		if base == null:
			for i in count:
				result.append({"point": Vector2.ZERO, "gap": true})
			return result
		return base.sample_points(count)
	var from_points := (pair["from"] as BoundaryShape).sample_points(count)
	var to_points := (pair["to"] as BoundaryShape).sample_points(count)
	var p := float(pair["p"])
	for i in count:
		var a: Dictionary = from_points[i]
		var b: Dictionary = to_points[i]
		result.append({
			"point": (a.point as Vector2).lerp(b.point, p),
			"gap": a.gap if p < 0.5 else b.gap,
			"segment": null,
		})
	return result


## 当前拍落在哪两个形状之间：{from, to, p}。
## 空谱面或没有关键帧时返回空；第一帧之前从默认形状渐变到第一帧。
static func pair_at(chart: Chart, beat: float) -> Dictionary:
	var keys := chart.sorted_shape_keys()
	if keys.is_empty():
		return {}
	var last: Dictionary = keys[keys.size() - 1]
	if beat >= float(last.get("beat", 0.0)) - 0.000001:
		var last_shape := chart.get_shape(String(last.get("shape_id", "")))
		if last_shape == null:
			return {}
		return {"from": last_shape, "to": last_shape, "p": 0.0}
	var first: Dictionary = keys[0]
	var first_beat := float(first.get("beat", 0.0))
	if beat <= first_beat:
		var first_shape := chart.get_shape(String(first.get("shape_id", "")))
		if first_shape == null:
			return {}
		var base := chart.get_default_shape()
		if base == null or first_beat <= 0.000001:
			return {"from": first_shape, "to": first_shape, "p": 0.0}
		var intro := Ease.apply(String(first.get("easing", "in-out")), clampf(beat / first_beat, 0.0, 1.0))
		return {"from": base, "to": first_shape, "p": intro}
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var a_beat := float(a.get("beat", 0.0))
		var b_beat := float(b.get("beat", 0.0))
		if beat < a_beat or beat > b_beat:
			continue
		var from_shape := chart.get_shape(String(a.get("shape_id", "")))
		var to_shape := chart.get_shape(String(b.get("shape_id", "")))
		if from_shape == null or to_shape == null:
			continue
		var span := maxf(0.000001, b_beat - a_beat)
		var p := Ease.apply(String(a.get("easing", "in-out")), clampf((beat - a_beat) / span, 0.0, 1.0))
		return {"from": from_shape, "to": to_shape, "p": p}
	return {}


static func eval_view(chart: Chart, beat: float) -> Dictionary:
	return ViewState.evaluate(chart.view_states, beat)


static func nearest_u(chart: Chart, beat: float, screen_point: Vector2, projector: Callable, samples: int = 512, frame: BoundaryFrame = null) -> Dictionary:
	## Two-stage nearest point: coarse ring sweep, then a local refine.
	var best_u := 0.0
	var best_distance := INF
	var count := maxi(16, samples / 2)
	for i in count:
		var u := float(i) / float(count)
		var data := frame.point_at(u) if frame != null else eval_point(chart, u, beat)
		if data.gap:
			continue
		var screen: Vector2 = projector.call(data.point)
		var distance := screen.distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best_u = u
	if best_distance == INF:
		return {"u": 0.0, "distance": INF}
	var span := 1.0 / float(count)
	for i in 17:
		var u := fposmod(best_u - span + 2.0 * span * float(i) / 16.0, 1.0)
		var data := frame.point_at(u) if frame != null else eval_point(chart, u, beat)
		if data.gap:
			continue
		var screen: Vector2 = projector.call(data.point)
		var distance := screen.distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			best_u = u
	return {"u": best_u, "distance": best_distance}
