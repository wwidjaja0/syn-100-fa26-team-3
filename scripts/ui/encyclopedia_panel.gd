extends RefCounted
## The encyclopedia's blank-book shell. Recipe and discovery content will be added here once
## the aquarium repair objects and rules exist.

const Px := preload("res://scripts/ui/pixel_draw.gd")

const PANEL := Rect2(28, 14, 424, 232)
const BOOK := Rect2(55, 38, 370, 184)
const LEFT_PAGE := Rect2(65, 46, 174, 168)
const RIGHT_PAGE := Rect2(241, 46, 174, 168)
const CLOSE := Vector2(441, 24)

var _overlay: Control
var _cover: Color
var _cover_hi: Color
var _paper: Color
var _paper_edge: Color


func _init(overlay: Control, palette: Array) -> void:
	_overlay = overlay
	_cover = Px.palette_color(palette, Color8(66, 35, 25))
	_cover_hi = Px.palette_color(palette, Color8(122, 72, 43))
	_paper = Px.palette_color(palette, Color8(231, 212, 166))
	_paper_edge = Px.palette_color(palette, Color8(171, 143, 96))


func over_close(p: Vector2) -> bool:
	return absf(p.x - CLOSE.x) < 6.0 and absf(p.y - CLOSE.y) < 6.0


func hover_label(p: Vector2) -> String:
	return "CLOSE" if over_close(p) else ""


## Open is 0..1. The covers and pages spread horizontally from the centre seam.
func draw(open: float, cur: Vector2) -> void:
	var cols := int(BOOK.size.x * open)
	if cols <= 0:
		return

	var left := BOOK.get_center().x - cols / 2.0
	var visible_book := Rect2(left, BOOK.position.y, cols, BOOK.size.y)
	_overlay.draw_rect(PANEL, _overlay.panel_lo)
	Px.frame(_overlay, PANEL, _overlay.panel_hi)
	_overlay.draw_rect(visible_book, _cover)
	Px.frame(_overlay, visible_book, _cover_hi)
	if open < 1.0:
		return

	# Two intentionally blank paper pages, ready for future aquarium repair recipes.
	_overlay.draw_rect(LEFT_PAGE, _paper)
	_overlay.draw_rect(RIGHT_PAGE, _paper)
	Px.frame(_overlay, LEFT_PAGE, _paper_edge)
	Px.frame(_overlay, RIGHT_PAGE, _paper_edge)
	_overlay.draw_rect(Rect2(238, 43, 4, 174), _cover)
	_overlay.draw_rect(Rect2(239, 47, 1, 166), _cover_hi)
	_overlay.draw_rect(Rect2(242, 47, 1, 166), _paper_edge)

	# Small page details keep the blank spread readable without implying recipe content.
	for page: Rect2 in [LEFT_PAGE, RIGHT_PAGE]:
		_overlay.draw_rect(Rect2(page.position + Vector2(12, 14),
				Vector2(page.size.x - 24, 1)), _paper_edge)
		var corner: Vector2 = page.end - Vector2(13, 12)
		_overlay.draw_rect(Rect2(corner, Vector2(5, 1)), _paper_edge)

	var title := "ENCYCLOPEDIA"
	Px.text(_overlay, title, Vector2(PANEL.get_center().x - Px.text_width(title) / 2.0, 20),
			Px.WHITE, Px.INK)
	var hint := "J / ESC TO CLOSE"
	Px.text(_overlay, hint, Vector2(PANEL.get_center().x - Px.text_width(hint) / 2.0, 231),
			_overlay.panel_hi)

	var cb := Rect2(CLOSE - Vector2(5, 5), Vector2(11, 11))
	_overlay.draw_rect(cb, _overlay.panel_lo)
	Px.frame(_overlay, cb, Px.WHITE if over_close(cur) else _overlay.panel_hi)
	for i in range(-2, 3):
		_overlay.draw_rect(Rect2(CLOSE + Vector2(i, i), Vector2.ONE), Px.WHITE)
		_overlay.draw_rect(Rect2(CLOSE + Vector2(i, -i), Vector2.ONE), Px.WHITE)
