class_name Animal
extends RefCounted
## A wild animal. Behaviour lives in AnimalAI.

var id := 0
var species := "rabbit"
var pos := Vector2.ZERO
var health := 10.0
var hunger := 100.0
var thirst := 100.0
var age_days := 0.0
var alive := true
var carcass_t := 0.0      # time since death (carcass rots away)
var meat_left := 0
var hide_left := 0
var bone_left := 0

# transient
var state := "wander"
var target := Vector2.ZERO
var moving := false
var wait := 0.0
var think_t := 0.0
var facing := 1.0
var anim := 0.0
var lod_acc := 0.0
var strike_at := -10.0    # combat visuals (real time of the last strike / hit)
var strike_dir := Vector2.RIGHT
var hurt_at := -10.0
var hurt_dir := Vector2.LEFT
var attack_cd := 0.0
var threat_id := -1       # human that provoked / is hunting it
var prey_id := -1         # animal or human being chased (predators)
var prey_is_human := false
var hunted_by := -1
var claimed_by := -1      # hunter butchering the carcass


func def() -> Dictionary:
	return Defs.ANIMALS[species]


func init_species(sp: String) -> void:
	species = sp
	var d := def()
	health = float(d["hp"])
	meat_left = int(d["meat"])
	hide_left = int(d["hide"])
	bone_left = int(d["bone"])


func to_dict() -> Dictionary:
	return {"id": id, "sp": species, "x": pos.x, "y": pos.y, "hp": health, "hunger": hunger, "thirst": thirst,
		"age": age_days, "alive": alive, "ct": carcass_t, "meat": meat_left, "hide": hide_left, "bone": bone_left}


static func from_dict(d: Dictionary) -> Animal:
	var a := Animal.new()
	a.id = int(d["id"])
	a.species = str(d["sp"])
	a.pos = Vector2(float(d["x"]), float(d["y"]))
	a.health = float(d["hp"])
	a.hunger = float(d["hunger"])
	a.thirst = float(d["thirst"])
	a.age_days = float(d["age"])
	a.alive = bool(d["alive"])
	a.carcass_t = float(d["ct"])
	a.meat_left = int(d["meat"])
	a.hide_left = int(d["hide"])
	a.bone_left = int(d["bone"])
	a.target = a.pos
	return a
