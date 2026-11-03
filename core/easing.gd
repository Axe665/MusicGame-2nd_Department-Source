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
