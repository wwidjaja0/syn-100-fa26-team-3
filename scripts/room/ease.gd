extends RefCounted
## Easing curves shared by the room's moving parts. t runs 0..1 (clamped).
##     const Ease := preload("res://scripts/room/ease.gd")
##     value = Ease.out_back(t)


## slow - fast - slow
static func smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## overshoots the end a little, then settles (s = how far)
static func out_back(t: float, s := 1.2) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (s + 1.0) * t * t * t + s * t * t
