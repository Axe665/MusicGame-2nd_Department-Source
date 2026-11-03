class_name BoundarySegment
extends RefCounted

var u0: float = 0.0
var u1: float = 1.0
var p0: Vector2 = Vector2.ZERO
var p1: Vector2 = Vector2.ZERO
var ix: String = "s"
var iy: String = "s"
var gap: bool = false


func _init(
	p_u0: float = 0.0,
	p_u1: float = 1.0,
	p_p0: Vector2 = Vector2.ZERO,
	p_p1: Vector2 = Vector2.ZERO,
	p_ix: String = "s",
	p_iy: String = "s",
	p_gap: bool = false
) -> void:
	u0 = p_u0
	u1 = p_u1
	p0 = p_p0
	p1 = p_p1
	ix = p_ix
	iy = p_iy
	gap = p_gap


func point_at(t: float) -> Vector2:
	var tt := clampf(t, 0.0, 1.0)
	var cx := Ease.curve(ix, tt)
	var cy := Ease.curve(iy, tt)
	return Vector2(lerpf(p0.x, p1.x, cx), lerpf(p0.y, p1.y, cy))


func local_t(u: float) -> float:
	var span := maxf(0.000001, u1 - u0)
	return clampf((u - u0) / span, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"u0": snappedf(u0, 0.0001),
		"u1": snappedf(u1, 0.0001),
		"x0": snappedf(p0.x, 0.001),
		"y0": snappedf(p0.y, 0.001),
		"x1": snappedf(p1.x, 0.001),
		"y1": snappedf(p1.y, 0.001),
		"ix": ix,
		"iy": iy,
		"gap": gap,
	}


static func from_dict(data: Dictionary) -> BoundarySegment:
	return BoundarySegment.new(
		float(data.get("u0", 0.0)),
		float(data.get("u1", 1.0)),
		Vector2(float(data.get("x0", 0.0)), float(data.get("y0", 0.0))),
		Vector2(float(data.get("x1", 0.0)), float(data.get("y1", 1.0))),
		String(data.get("ix", "s")),
		String(data.get("iy", "s")),
		bool(data.get("gap", false))
	)
