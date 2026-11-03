class_name BoundaryRuntime
extends RefCounted

## Shared C(u,t) evaluator. The preview, validation and playtest all call this.
## Events only touch the target u range; notes' u/time/width are never modified.


static func eval_point(chart: Chart, u: float, beat: float) -> Dictionary:
	var base := chart.get_default_shape()
	if base == null:
		return {"point": Vector2.ZERO, "gap": true}
	var active := _event_for_u(chart, u, beat)
	if active == null:
		return base.point_at(u)
	return _eval_event(chart, active, u, beat)


static func eval_shape(chart: Chart, beat: float, samples: int = 256) -> Array[Dictionary]:
	var count := maxi(samples, 8)
	var base := chart.get_default_shape()
	if base == null:
		var empty: Array[Dictionary] = []
		for i in count:
			empty.append({"point": Vector2.ZERO, "gap": true})
		return empty
	var base_points := base.sample_points(count)
	var result := base_points.duplicate()
	for event in chart.events:
		var tail := event.end_beat
		if event.end_behavior == "restore":
			tail += maxf(0.0, event.restore_duration)
		if beat + 0.000001 < event.start_beat or beat > tail + 0.000001:
			continue
		var from_shape := chart.get_shape(event.from_shape)
		var to_shape := chart.get_shape(event.to_shape)
		var from_points: Array[Dictionary] = []
		var to_points: Array[Dictionary] = []
		var p := 0.0
		var restoring := false
		if from_shape != null and to_shape != null:
			from_points = from_shape.sample_points(count)
			to_points = to_shape.sample_points(count)
			if beat <= event.end_beat:
				p = Ease.apply(event.easing, (beat - event.start_beat) / maxf(0.000001, event.duration()))
			elif event.end_behavior == "hold":
				p = 1.0
			elif event.restore_duration > 0.000001:
				restoring = true
				p = Ease.apply(event.restore_easing, clampf((beat - event.end_beat) / event.restore_duration, 0.0, 1.0))
		for i in count:
			if not event.covers_u(float(i) / float(count)):
				continue
			if from_points.is_empty():
				result[i] = base_points[i]
				continue
			var a := from_points[i]
			var b := to_points[i]
			if restoring:
				a = to_points[i]
				b = from_points[i]
			var from_vec: Vector2 = a.point
			result[i] = {"point": from_vec.lerp(b.point, p), "gap": a.gap if p < 0.5 else b.gap, "segment": null}
	return result


static func _event_for_u(chart: Chart, u: float, beat: float) -> BoundaryEvent:
	var found: BoundaryEvent = null
	for event in chart.events:
		if not event.covers_u(u):
			continue
		if beat + 0.000001 < event.start_beat:
			continue
		var tail := event.end_beat
		if event.end_behavior == "restore":
			tail += maxf(0.0, event.restore_duration)
		if beat > tail + 0.000001:
			continue
		# Validation forbids overlapping target ranges; last one wins only as a fallback.
		found = event
	return found


static func _eval_event(chart: Chart, event: BoundaryEvent, u: float, beat: float) -> Dictionary:
	var from_shape := chart.get_shape(event.from_shape)
	var to_shape := chart.get_shape(event.to_shape)
	if from_shape == null or to_shape == null:
		return chart.get_default_shape().point_at(u)
	var from_point := from_shape.point_at(u)
	var to_point := to_shape.point_at(u)
	var to_vec: Vector2 = to_point.point
	var from_vec: Vector2 = from_point.point
	if beat <= event.end_beat:
		var span := maxf(0.000001, event.end_beat - event.start_beat)
		var p := Ease.apply(event.easing, (beat - event.start_beat) / span)
		return {
			"point": from_vec.lerp(to_vec, p),
			"gap": from_point.gap if p < 0.5 else to_point.gap,
			"segment": null,
		}
	if event.end_behavior == "hold":
		return {"point": to_vec, "gap": to_point.gap, "segment": null}
	if event.restore_duration <= 0.000001:
		return {"point": from_vec, "gap": from_point.gap, "segment": null}
	var rp := clampf((beat - event.end_beat) / event.restore_duration, 0.0, 1.0)
	rp = Ease.apply(event.restore_easing, rp)
	return {
		"point": to_vec.lerp(from_vec, rp),
		"gap": to_point.gap if rp < 0.5 else from_point.gap,
		"segment": null,
	}


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
