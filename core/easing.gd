class_name Ease
extends RefCounted

## Shared easing vocabulary for BoundaryEvent and ViewState.
## cubic-bezier is approximated: the editor only exposes linear/in-out for v1.
static func apply(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"in-out":
			return t * t * (3.0 - 2.0 * t)
		"cubic-bezier":
			return t * t * (3.0 - 2.0 * t)
		_:
			return t


## 每段一条 cubic-bezier：控制点 (x1,y1) (x2,y2)，x 限制在 0..1，
## y 允许超出（回弹）。牛顿迭代求 x 对应的 t，失败时退二分。
static func bezier(raw: Array, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if raw.size() != 4:
		return t
	var x1 := clampf(float(raw[0]), 0.0, 1.0)
	var y1 := float(raw[1])
	var x2 := clampf(float(raw[2]), 0.0, 1.0)
	var y2 := float(raw[3])
	var guess := t
	for i in 8:
		var x := _bezier_axis(x1, x2, guess) - t
		if absf(x) < 0.00001:
			return _bezier_axis(y1, y2, guess)
		var d := _bezier_slope(x1, x2, guess)
		if absf(d) < 0.00001:
			break
		guess = clampf(guess - x / d, 0.0, 1.0)
	var low := 0.0
	var high := 1.0
	for i in 16:
		guess = (low + high) * 0.5
		if _bezier_axis(x1, x2, guess) < t:
			low = guess
		else:
			high = guess
	return _bezier_axis(y1, y2, guess)


## 段有自定义曲线就用曲线，否则退回预设名。
static func apply_curve(kind: String, raw: Array, t: float) -> float:
	if raw.size() == 4:
		return bezier(raw, t)
	return apply(kind, t)


static func _bezier_axis(a1: float, a2: float, t: float) -> float:
	var mt := 1.0 - t
	return 3.0 * mt * mt * t * a1 + 3.0 * mt * t * t * a2 + t * t * t


static func _bezier_slope(a1: float, a2: float, t: float) -> float:
	var mt := 1.0 - t
	return 3.0 * mt * mt * a1 + 6.0 * mt * t * (a2 - a1) + 3.0 * t * t * (1.0 - a2)


static func curve(kind: String, t: float) -> float:
	## BoundarySegment interpolation. b is kept as a parse-compatible alias.
	t = clampf(t, 0.0, 1.0)
	match kind:
		"l":
			return t
		"s":
			return t * t * (3.0 - 2.0 * t)
		"si":
			return 1.0 - cos(t * PI * 0.5)
		"so":
			return sin(t * PI * 0.5)
		"b":
			return t * t * (3.0 - 2.0 * t)
		_:
			return t
