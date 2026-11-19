class_name Ship
extends RefCounted
## A boat built at a Harbor. Sails on sea, lakes and rivers and carries people between shores.

var id := 0
var civ_id := 0
var kind := 0                 # index into Defs.SHIP_TYPES
var pos := Vector2.ZERO
var heading := 0.0
var path: Array = []          # water tiles
var passengers: Array = []    # human ids
var unload_at := Vector2i(-1, -1)   # land tile to unload onto after arriving
var name := ""
var anim := 0.0
var idle_t := 0.0


func def() -> Dictionary:
	return Defs.SHIP_TYPES[kind]


func label() -> String:
	return "%s \"%s\"" % [def()["name"], name] if name != "" else str(def()["name"])


func capacity(c: Colony) -> int:
	return int(def()["cap"]) + int(c.bonus("ship_cap"))


func speed(c: Colony) -> float:
	return float(def()["speed"]) * (1.0 + c.bonus("ship_speed"))


func to_dict() -> Dictionary:
	return {"id": id, "civ": civ_id, "kind": kind, "x": pos.x, "y": pos.y, "heading": heading,
		"passengers": passengers.duplicate(), "name": name}


static func from_dict(d: Dictionary) -> Ship:
	var s := Ship.new()
	s.id = int(d["id"])
	s.civ_id = int(d.get("civ", 0))
	s.kind = int(d.get("kind", 0))
	s.pos = Vector2(float(d["x"]), float(d["y"]))
	s.heading = float(d.get("heading", 0.0))
	s.passengers = d.get("passengers", [])
	s.name = str(d.get("name", ""))
	return s
