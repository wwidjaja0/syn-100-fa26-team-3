extends RefCounted
## Drawing helpers for the 480x270 pixel UI. Every function draws on the CanvasItem you pass in,
## during that item's _draw(). Load it with:
##     const Px := preload("res://scripts/ui/pixel_draw.gd")
##     Px.text(self, "HELLO", Vector2(10, 10), Px.WHITE, Px.INK)
##
## The UI is drawn after the post shader's palette snap, so only palette colours belong here:
## use palette_color() to snap a colour to assets/palette.json.

const W := 480                          # the game's canvas, before the integer upscale
const H := 270
const FONT := preload("res://ui/pixel_font.fnt")   # 5x7 capitals, made by make_ui_assets.py
const FONT_SIZE := 7
const WHITE := Color(1, 1, 1)
const INK := Color8(14, 5, 5)           # the darkest palette colour; text outlines and shadows
const GREY := Color8(170, 170, 178)


## width in pixels of a line of text in the pixel font
static func text_width(s: String) -> int:
	return int(FONT.get_string_size(s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) - 1


## text with its top-left at pos (always capitals). shadow, if given, draws a 1 px ring round it.
static func text(ci: CanvasItem, s: String, pos: Vector2, color: Color, shadow = null) -> void:
	s = s.to_upper()
	var base := pos.floor() + Vector2(0, FONT_SIZE)
	if shadow != null:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx != 0 or dy != 0:
					ci.draw_string(FONT, base + Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, shadow)
	ci.draw_string(FONT, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## a 1 px rectangle outline just inside r
static func frame(ci: CanvasItem, r: Rect2, color: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), color)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), color)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), color)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), color)


## a 1 px circle outline (click ripples, map marks)
static func ring(ci: CanvasItem, c: Vector2, radius: float, color: Color) -> void:
	var n := int(8.0 * radius) + 8
	for i in n:
		var a := TAU * i / n
		var p := (c + Vector2(cos(a), sin(a)) * radius).round()
		if p.x >= 0 and p.y >= 0 and p.x < W and p.y < H:
			ci.draw_rect(Rect2(p, Vector2.ONE), color)


## the palette colour closest to c, weighted the way the post shader weighs it (2 R, 4 G, 3 B).
## palette is the parsed assets/palette.json: [[r, g, b], ...] in 0..255.
static func palette_color(palette: Array, c: Color) -> Color:
	var best := Color.BLACK
	var bd := INF
	for p in palette:
		var q := Color8(int(p[0]), int(p[1]), int(p[2]))
		var e := 2.0 * pow(q.r - c.r, 2) + 4.0 * pow(q.g - c.g, 2) + 3.0 * pow(q.b - c.b, 2)
		if e < bd:
			bd = e
			best = q
	return best


static func load_palette() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/palette.json"))
