class_name Building
extends RefCounted
## A placed structure (under construction or finished).

var id := 0
var civ_id := 0
var type := "campfire"
var tile := Vector2i.ZERO
var progress := 0.0
var built := false
var fuel := 0.0          # campfire: game hours of burn time left
var crop_stage := 0      # farm: 0 empty, 1 growing, 2 ready
var crop_growth := 0.0
var tended := false
var occupants: Array = []  # human ids sleeping here
var stored := 0.0         # research table: research value of materials waiting to be studied
var delivered := {}       # blueprint: materials brought to the site so far
var ship_order := -1      # harbor: ship type being built (-1 = none)
var ship_progress := 0.0
var tier := 0             # walls & gates: fortification level (0 palisade, 1 stone, 2 fortified)
var hp := -1.0            # current strength (-1 = full; set on first damage)
var craft := ""           # blacksmith: weapon being forged
var craft_progress := 0.0
var auto_craft := true    # blacksmith: forge weapons for unarmed soldiers on its own
var zoned := false       # stands in the town zone that suits it (transient, Sim.refresh_zones)
var shoot_cd := 0.0       # towers (transient)


func def() -> Dictionary:
	return Defs.BUILDINGS[type]


## Materials it takes to build (walls and gates depend on their fortification level).
func cost() -> Dictionary:
	if type == "wall":
		return Defs.WALL_TIERS[tier]["wall_cost"]
	if type == "gate":
		return Defs.WALL_TIERS[tier]["gate_cost"]
	return def()["cost"]


func display_name() -> String:
	if type == "wall" or type == "gate":
		return Defs.wall_name(type, tier)
	return str(def()["name"])


func max_hp() -> float:
	if type == "wall" or type == "gate":
		return float(Defs.WALL_TIERS[tier]["hp"]) * (1.2 if type == "gate" else 1.0)
	return float(def().get("hp", 60.0 + float(def()["work"]) * 3.0))


func cur_hp() -> float:
	return max_hp() if hp < 0.0 else hp


func size() -> Vector2i:
	return def()["size"]


func center() -> Vector2:
	var s := size()
	return Vector2((tile.x + s.x * 0.5) * Defs.TILE, (tile.y + s.y * 0.5) * Defs.TILE)


func center_tile() -> Vector2i:
	var s := size()
	return tile + Vector2i(s.x / 2, s.y / 2)


func tiles() -> Array:
	var out: Array = []
	var s := size()
	for y in s.y:
		for x in s.x:
			out.append(tile + Vector2i(x, y))
	return out


## Materials still missing before construction can start (item -> amount).
func needs() -> Dictionary:
	var out := {}
	if built:
		return out
	var cost: Dictionary = cost()
	for k in cost.keys():
		var left := float(cost[k]) - float(delivered.get(k, 0.0))
		if left > 0.001:
			out[k] = left
	return out


func supplied() -> bool:
	return needs().is_empty()


func housing() -> int:
	return int(def()["housing"]) if built else 0


func is_lit() -> bool:
	return type == "campfire" and built and fuel > 0.0


func to_dict() -> Dictionary:
	return {"id": id, "civ": civ_id, "type": type, "x": tile.x, "y": tile.y, "progress": progress, "built": built,
		"fuel": fuel, "stored": stored, "delivered": delivered.duplicate(), "ship_order": ship_order, "ship_progress": ship_progress, "crop_stage": crop_stage, "crop_growth": crop_growth, "occupants": occupants.duplicate(),
		"tier": tier, "hp": hp, "craft": craft, "craft_progress": craft_progress, "auto_craft": auto_craft}


static func from_dict(d: Dictionary) -> Building:
	var b := Building.new()
	b.id = int(d["id"])
	b.civ_id = int(d.get("civ", 0))
	b.type = str(d["type"])
	if b.type == "palisade":
		b.type = "wall"          # older saves
	if not Defs.BUILDINGS.has(b.type):
		b.type = "storage"
	b.tier = int(d.get("tier", 0))
	b.hp = float(d.get("hp", -1.0))
	b.craft = str(d.get("craft", ""))
	b.craft_progress = float(d.get("craft_progress", 0.0))
	b.auto_craft = bool(d.get("auto_craft", true))
	b.tile = Vector2i(int(d["x"]), int(d["y"]))
	b.progress = float(d["progress"])
	b.built = bool(d["built"])
	b.fuel = float(d["fuel"])
	b.stored = float(d.get("stored", 0.0))
	b.delivered = d.get("delivered", {})
	b.ship_order = int(d.get("ship_order", -1))
	b.ship_progress = float(d.get("ship_progress", 0.0))
	if not b.built and not d.has("delivered"):
		b.delivered = b.cost().duplicate()   # older saves paid up front
	b.crop_stage = int(d["crop_stage"])
	b.crop_growth = float(d["crop_growth"])
	b.occupants = d.get("occupants", [])
	return b
