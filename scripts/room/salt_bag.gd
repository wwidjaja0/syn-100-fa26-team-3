extends Node
## The open sack of reef salt mix by the supply cabinet (the "salt" group), and how it cakes.
##
## Reef salt mix is mostly sea salt, plus the magnesium and calcium chlorides and carbonates that
## make it seawater. Those chlorides pull water out of damp air well below the point plain salt does,
## and warmth speeds it up, so an open sack in a humid cabin crusts over: `cake` (0 loose .. 1 caked
## solid) creeps up while the cabin's air (room/cabin_climate.gd) is above CAKE_FROM humidity, faster
## the damper and warmer it is. It never goes back: dried-out caked salt stays lumpy. The crust lumps
## on top of the heap ("salt_crust_a/_b/_c") show as it goes.
##
## Clicking the sack scoops out REEF SALT (items/salt.tres), carrying how caked it was (ItemData meta
## "cake"; CAKED REEF SALT past crafting.gd's CAKED_AT). Caked salt still works, but dissolves slowly
## into SALTWATER (crafting/crafting.gd). The sack doesn't run out.

const CAKE_FROM := 0.5                  # relative humidity where the mix starts pulling in water
const CAKE_SECONDS := 240.0             # caking solid in saturated air at TEMP_REF
const TEMP_REF := 30.0                  # degC; every TEMP_SPAN warmer doubles the rate, cooler halves
const TEMP_SPAN := 10.0
const CAKED_ICON := preload("res://ui/icon_salt_caked.png")

var cake := 0.0

var _main: Node
var _crusts: Array[Node3D] = []


func setup(main: Node, room: Node3D) -> void:
	_main = main
	var sack := room.find_child("salt_sack_*", true, false) as MeshInstance3D
	if sack:                            # the sack sits in the cabinet's shadow: a little warm light on it
		var light := OmniLight3D.new()
		light.name = "salt_fill"
		light.light_color = Color(1.0, 0.8, 0.6)
		light.light_energy = 1.4
		light.omni_range = 1.4
		light.omni_attenuation = 1.5
		main.get_node("WorldVP/Lights").add_child(light)
		light.global_position = sack.global_transform * sack.get_aabb().get_center() + Vector3(-0.2, 0.5, 0.8)
	for n in ["salt_crust_a_*", "salt_crust_b_*", "salt_crust_c_*"]:
		var c := room.find_child(n, true, false) as Node3D
		if c:
			_crusts.append(c)


## how fast it is caking now, per second
func rate() -> float:
	var climate = _main.climate
	var wet := maxf(0.0, (climate.humid - CAKE_FROM) / (1.0 - CAKE_FROM))
	return wet * pow(2.0, (climate.temp - TEMP_REF) / TEMP_SPAN) / CAKE_SECONDS


## per frame, from main.gd. delta in seconds.
func update(delta: float) -> void:
	cake = minf(cake + rate() * delta, 1.0)
	for i in _crusts.size():
		_crusts[i].visible = cake >= 0.25 * (i + 1)


func label() -> String:
	if cake >= 0.75:
		return "REEF SALT MIX (CAKED SOLID)"
	if cake >= _main.workbench.CAKED_AT:
		return "REEF SALT MIX (CAKING)"
	return "REEF SALT MIX"


## a click on the sack: a scoop of salt into the inventory
func click() -> void:
	var bar = _main.ui.inventory
	if not bar.has_room():
		return
	var item: ItemData = InventoryManager.get_item("salt").duplicate()
	item.set_meta("cake", cake)
	if cake >= _main.workbench.CAKED_AT:
		item.name = "CAKED REEF SALT"
		item.icon = CAKED_ICON
	bar.fly(item, _main.picker.screen_point("salt"), _main.clock)
	UiSounds.play("pick")
	GameState.set_flag("took_salt")
	if cake >= _main.workbench.CAKED_AT:
		_main.interactions.say("salt_caked")
	else:
		_main.interactions.say("salt_scoop")
