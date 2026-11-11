extends Node
## Story progress that outlives any one scene: which day it is, what you've done, and which radio
## stations you've reached. What you carry lives in the InventoryManager autoload.

signal changed
## a station was reached over the radio for the first time (it now shows on the microfiche)
signal station_contacted(id: String)

var day := 1
var flags := {}                            # e.g. "fiche_seen", "window_opened", "took_jar"
var stations := {}                         # id -> {callsign, name, lat, lon, problems}, from data/stations.json
var contacted: Array[String] = []          # station ids, in the order they were reached
## areas of the microfiche printed in full: {id, name, lat, lon, radius_deg}. Starts with
## data/stations.json's "revealed" list (the Pacific Northwest); every station reached adds its own.
## Areas whose id has a detail map (made by pipeline/scene/make_fiche.py) can be zoomed into.
var revealed: Array[Dictionary] = []
var _start_revealed: Array[Dictionary] = []


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stations.json"))
	for s: Dictionary in data.stations:
		stations[s.id] = s
	for a: Dictionary in data.revealed:
		_start_revealed.append(a)
	revealed = _start_revealed.duplicate()


func flag(name: String) -> bool:
	return flags.get(name, false)


func set_flag(name: String, value := true) -> void:
	flags[name] = value
	changed.emit()


## call this from the radio when a conversation reaches a station; it is marked on the microfiche
## and the map is printed around it
func contact_station(id: String) -> void:
	if not stations.has(id):
		push_error("unknown station '%s' (see data/stations.json)" % id)
		return
	if id in contacted:
		return
	contacted.append(id)
	var s: Dictionary = stations[id]
	reveal(s.lat, s.lon, s.get("reveal_deg", 5.0), id, s.name)
	station_contacted.emit(id)
	changed.emit()


## print the microfiche in full within radius_deg of a point (the story can call this directly too).
## Give it an id from data/stations.json to make it zoomable.
func reveal(lat: float, lon: float, radius_deg: float, id := "", name := "") -> void:
	revealed.append({"id": id, "name": name, "lat": lat, "lon": lon, "radius_deg": radius_deg})
	changed.emit()


func is_contacted(id: String) -> bool:
	return id in contacted


## a new game: day 1, nothing done, the map as it started (pause menu's QUIT TO TITLE)
func reset() -> void:
	day = 1
	flags.clear()
	reset_map()


## back to the start: no stations reached, only the starting areas printed (debug menu)
func reset_map() -> void:
	contacted.clear()
	revealed = _start_revealed.duplicate()
	changed.emit()
