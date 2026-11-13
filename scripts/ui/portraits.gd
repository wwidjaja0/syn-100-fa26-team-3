extends RefCounted
## Speaker portraits for the dialogue box (dialogue_box.gd), one per character in data/dialogue.json.
##
## PLACEHOLDERS. There is no portrait art yet, so each one is a 28x28 pixel map below, one
## character per pixel, keyed to a colour in "colors" (snapped to assets/palette.json). To use real
## art, give the character a "portrait" path in data/dialogue.json: a PNG strip of three square
## frames, left to right idle, talking (mouth open), blinking. The pixel map is then ignored.
##
## Every portrait has four frames:
##   idle    the map as drawn
##   talk    "talk" recolours some keys (an open mouth, a lit lamp) while its voice blips
##   blink   "blink" recolours the eyes, for a few frames now and then
##   dim     idle, darkened: whoever isn't speaking

const Px := preload("res://scripts/ui/pixel_draw.gd")
const SIZE := 28
const DIM := 0.55                       # how bright the listener's portrait is

const MAPS := {
	"you": {
		"colors": {".": Color8(27, 17, 18), "k": Color8(14, 5, 5), "h": Color8(63, 31, 14), "H": Color8(109, 51, 28),
				"g": Color8(30, 80, 102), "G": Color8(165, 221, 214), "s": Color8(181, 127, 109), "S": Color8(126, 86, 78),
				"W": Color8(249, 228, 177), "e": Color8(14, 5, 5), "m": Color8(86, 44, 29), "o": Color8(181, 127, 109),
				"b": Color8(235, 100, 23), "B": Color8(171, 70, 30), "j": Color8(68, 83, 99), "J": Color8(35, 52, 90)},
		"talk": {"o": "k", "m": "k"},
		"blink": {"e": "S", "W": "S"},
		"rows": [
			"............................",
			"..........kkkkkkkk..........",
			"........kkhhhHHhhhkk........",
			".......khhhHHhhhhhhk........",
			"......khhHhhhhhhhHhhhk......",
			"......kkkkkkhhhhkkkkkk......",
			"......kgGggkhhhhkgGggk......",
			"......kggggkkkkkkggggk......",
			"......khsssssssssssshk......",
			"......kshhhsssssshhhsk......",
			"......kssssssssssssssk......",
			"......kssWessssssWessk......",
			"......kssWessssssWessk......",
			"......kssSSssssssSSssk......",
			"......kssssssSSssssssk......",
			"......kSssssssssssssSk......",
			"......kSssssmmmmssssSk......",
			"......kSssssoooossssSk......",
			".......kSsSssssssSsSk.......",
			"........kkSSssssSSkk........",
			"..........kSSSSSSk..........",
			"........kbbbbbbbbbbk........",
			"......kjjBbbbbbbbbBjjk......",
			"....kjjjjjBBbbbbBBjjjjjk....",
			"...kjjjjjjjBBbbBBjjjjjjjk...",
			"..kjjJjjjjjjJBBJjjjjjjJjjk..",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
		],
	},
	"aqua_dispatch": {
		"colors": {".": Color8(21, 40, 53), "k": Color8(14, 5, 5), "h": Color8(32, 30, 33), "H": Color8(69, 63, 76),
				"s": Color8(126, 86, 78), "S": Color8(99, 68, 50), "W": Color8(249, 228, 177), "e": Color8(14, 5, 5),
				"m": Color8(63, 31, 14), "o": Color8(126, 86, 78), "n": Color8(119, 115, 127), "N": Color8(68, 83, 99),
				"c": Color8(153, 194, 182), "j": Color8(35, 113, 148), "J": Color8(23, 62, 79)},
		"talk": {"o": "k", "m": "k"},
		"blink": {"e": "S", "W": "S"},
		"rows": [
			"............kkkk............",
			"...........khhhhk...........",
			"........kkkkhHhhkkkk........",
			".......khhhhhhhhhhhhk.......",
			"......khhHhhhhhhhhHhhk......",
			"....nnkhhhhhhhhhhhhhhknn....",
			"...nN.khsssssssssssshk.Nn...",
			"...n..kssssssssssssssk..n...",
			"...n..kshhhsssssshhhsk..n...",
			"...knnnssssssssssssssnnnk...",
			"...knnnsseWsssssseWssnnnk...",
			"...kNNnsseWsssssseWssnNNk...",
			"...knnnssssssssssssssnnnk...",
			"...knnnssssssSSssssssnnnk...",
			"......kSssssssssssssNN......",
			"......kSssssmmmmsssNSk......",
			"......kSssssooooskksSk......",
			".......kSsSsssssskkSk.......",
			"........kkSSssssSSkk........",
			"..........kSSSSSSk..........",
			"........kcccccccccck........",
			"......kjjcccjjjjcccjjk......",
			"....kjjjjjjcjjjjcjjjjjjk....",
			"...kjjjjjjjjcjjcjjjjjjjjk...",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
			"..kjjJjjjjjjjJJjjjjjjjJjjk..",
		],
	},
	"aqua_beacon": {
		"colors": {".": Color8(20, 52, 76), "k": Color8(14, 5, 5), "n": Color8(119, 115, 127), "N": Color8(68, 83, 99),
				"r": Color8(171, 70, 30), "R": Color8(245, 168, 49), "e": Color8(99, 161, 173), "E": Color8(30, 80, 102),
				"o": Color8(30, 80, 102), "O": Color8(165, 221, 214), "g": Color8(32, 30, 33)},
		"talk": {"o": "O", "r": "R"},
		"blink": {"e": "E"},
		"rows": [
			".............kk.............",
			".............kk.............",
			"............krrk............",
			"............krrk............",
			".............kk.............",
			".............NN.............",
			".......kkkkkkkkkkkkkk.......",
			"......knnnnnnnnnnnnnnk......",
			".....knnNNNNNNNNNNNNnnk.....",
			".....knNkkkkkkkkkkkkNnk.....",
			".....knNkeeekkkkeeekNnk.....",
			".....knNkeeekkkkeeekNnk.....",
			".....knNkkkkkkkkkkkkNnk.....",
			".....knNkkooooooookkNnk.....",
			".....knNkkkkkkkkkkkkNnk.....",
			".....knnNNNNNNNNNNNNnnk.....",
			".....knnnnnnnnnnnnnnnnk.....",
			".....knngkgkgkgkgkgknnk.....",
			".....knnkgkgkgkgkgkgnnk.....",
			".....knngkgkgkgkgkgknnk.....",
			".....knnnnnnnnnnnnnnnnk.....",
			".....kNNNNNNNNNNNNNNNNk.....",
			"......kkkkkkkkkkkkkkkk......",
			".........kNNNNNNNNk.........",
			".......kkNNNNNNNNNNkk.......",
			"......knnnnnnnnnnnnnnk......",
			"......kNNNNNNNNNNNNNNk......",
			"......kkkkkkkkkkkkkkkk......",
		],
	},
}


## {"idle", "talk", "blink", "dim"} -> Texture2D for a character, or {} if it has no portrait.
## image_path, if not "", is a PNG strip of idle | talk | blink frames that replaces the pixel map.
static func build(id: String, image_path: String, palette: Array) -> Dictionary:
	if image_path != "" and ResourceLoader.exists(image_path):
		return _from_strip(load(image_path).get_image(), palette)
	if not MAPS.has(id):
		return {}
	var m: Dictionary = MAPS[id]
	var snapped := {}
	for key: String in m.colors:
		snapped[key] = Px.palette_color(palette, m.colors[key])
	return {
		"idle": _from_map(m.rows, snapped, {}),
		"talk": _from_map(m.rows, snapped, m.get("talk", {})),
		"blink": _from_map(m.rows, snapped, m.get("blink", {})),
		"dim": _dimmed(_image_from_map(m.rows, snapped, {}), palette),
	}


static func _image_from_map(rows: Array, colors: Dictionary, swap: Dictionary) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in mini(rows.size(), SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), SIZE):
			var key: String = swap.get(row[x], row[x])
			img.set_pixel(x, y, colors.get(key, Px.INK))
	return img


static func _from_map(rows: Array, colors: Dictionary, swap: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(_image_from_map(rows, colors, swap))


## each pixel darkened, then snapped back onto the palette (the UI draws only palette colours)
static func _dimmed(img: Image, palette: Array) -> ImageTexture:
	var out := img.duplicate() as Image
	var cache := {}
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if not cache.has(c):
				cache[c] = Px.palette_color(palette, Color(c.r * DIM, c.g * DIM, c.b * DIM))
			out.set_pixel(x, y, cache[c])
	return ImageTexture.create_from_image(out)


static func _from_strip(strip: Image, palette: Array) -> Dictionary:
	var s := strip.get_height()
	var frames := []
	for i in 3:
		var x := mini(i * s, strip.get_width() - s)    # a short strip repeats its last frame
		frames.append(strip.get_region(Rect2i(x, 0, s, s)))
	return {
		"idle": ImageTexture.create_from_image(frames[0]),
		"talk": ImageTexture.create_from_image(frames[1]),
		"blink": ImageTexture.create_from_image(frames[2]),
		"dim": _dimmed(frames[0], palette),
	}
