class_name Smithing
extends RefCounted
## Player-designed weapons. At the Weaponsmithing Bench the player paints a weapon in pixel art
## in two parts — the blade (or spearhead) and the hilt/handle — choosing the material of every
## pixel. What can be made is held back by research:
##   Weaponsmithing I (Bench, Caveman)  knives and spears of flint, bone, wood and hide
##   Weaponsmithing II (Stone Age)       daggers; obsidian and ground stone; antler grips
##   Weaponsmithing III (Bronze Age)     short swords; copper and bronze
##   Weaponsmithing IV (Iron Age)        longswords and pikes; iron
## Smiths forge the designs from stored materials. Custom weapons are made for fighting other
## Billies: they are used in fights between people, never for hunting.

const LEVEL_TECHS := ["smithing_bench", "weaponsmithing", "weaponsmithing_3", "weaponsmithing_4"]
const LEVEL_NAMES := ["Weaponsmithing I (Bench)", "Weaponsmithing II", "Weaponsmithing III", "Weaponsmithing IV"]

## type -> grid sizes (blade = the cutting part or spearhead; handle = hilt or shaft), reach, power
const TYPES := {
	"knife": {"name": "Knife", "level": 1, "blade": Vector2i(7, 9), "handle": Vector2i(5, 7), "reach": 1.1, "power": 0.82, "hours": 2.0,
		"desc": "A short blade lashed to a grip."},
	"spear": {"name": "Spear", "level": 1, "blade": Vector2i(7, 10), "handle": Vector2i(3, 26), "reach": 1.8, "power": 1.0, "hours": 2.5,
		"desc": "A spearhead on a long shaft: the longer the shaft, the further it reaches."},
	"dagger": {"name": "Dagger", "level": 2, "blade": Vector2i(7, 13), "handle": Vector2i(7, 7), "reach": 1.2, "power": 0.92, "hours": 3.0,
		"desc": "A long, pointed fighting blade with a guard."},
	"short_sword": {"name": "Short Sword", "level": 3, "blade": Vector2i(7, 17), "handle": Vector2i(9, 8), "reach": 1.3, "power": 1.06, "hours": 4.5,
		"desc": "A cast metal blade with hilt and guard."},
	"longsword": {"name": "Longsword", "level": 4, "blade": Vector2i(7, 23), "handle": Vector2i(11, 10), "reach": 1.45, "power": 1.12, "hours": 6.0,
		"desc": "A long forged blade with a cross-guard and pommel."},
	"pike": {"name": "Pike", "level": 4, "blade": Vector2i(7, 12), "handle": Vector2i(3, 32), "reach": 2.1, "power": 1.08, "hours": 5.0,
		"desc": "A heavy iron head on a very long shaft."},
}
const TYPE_ORDER := ["knife", "spear", "dagger", "short_sword", "longsword", "pike"]

## Materials (index order is saved in designs — only add to the end).
## hard: blade strength; grip: handle bonus; cost: stored goods used per 8 pixels.
const MATERIALS := [
	{"id": "flint", "name": "Flint", "level": 1, "hard": 11.0, "grip": 0.0, "cost": {"stone": 1},
		"shades": [Color(0.70, 0.72, 0.78), Color(0.50, 0.53, 0.60), Color(0.32, 0.34, 0.40)]},
	{"id": "bone", "name": "Bone", "level": 1, "hard": 9.0, "grip": 0.03, "cost": {"bones": 1},
		"shades": [Color(0.96, 0.93, 0.84), Color(0.86, 0.81, 0.68), Color(0.68, 0.62, 0.50)]},
	{"id": "wood", "name": "Wood", "level": 1, "hard": 4.0, "grip": 0.02, "cost": {"wood": 1},
		"shades": [Color(0.72, 0.52, 0.30), Color(0.55, 0.37, 0.20), Color(0.38, 0.24, 0.12)]},
	{"id": "hide", "name": "Hide wrap", "level": 1, "hard": 2.0, "grip": 0.05, "cost": {"hides": 1},
		"shades": [Color(0.78, 0.60, 0.40), Color(0.62, 0.45, 0.28), Color(0.44, 0.30, 0.18)]},
	{"id": "ochre", "name": "Red ochre (paint)", "level": 1, "hard": -1.0, "grip": 0.0, "cost": {},
		"shades": [Color(0.86, 0.36, 0.22), Color(0.70, 0.24, 0.14), Color(0.50, 0.16, 0.10)]},
	{"id": "obsidian", "name": "Obsidian", "level": 2, "hard": 13.0, "grip": 0.0, "cost": {"stone": 2},
		"shades": [Color(0.36, 0.34, 0.44), Color(0.18, 0.17, 0.24), Color(0.07, 0.06, 0.10)]},
	{"id": "jade", "name": "Ground stone", "level": 2, "hard": 12.0, "grip": 0.0, "cost": {"stone": 2},
		"shades": [Color(0.58, 0.74, 0.58), Color(0.40, 0.58, 0.44), Color(0.26, 0.40, 0.30)]},
	{"id": "antler", "name": "Antler", "level": 2, "hard": 8.0, "grip": 0.05, "cost": {"bones": 1, "hides": 1},
		"shades": [Color(0.90, 0.82, 0.66), Color(0.74, 0.62, 0.44), Color(0.54, 0.44, 0.30)]},
	{"id": "copper", "name": "Copper", "level": 3, "hard": 15.0, "grip": 0.04, "cost": {"copper_ore": 1},
		"shades": [Color(0.95, 0.62, 0.42), Color(0.80, 0.45, 0.28), Color(0.58, 0.30, 0.18)]},
	{"id": "bronze", "name": "Bronze", "level": 3, "hard": 19.0, "grip": 0.05, "cost": {"copper_ore": 1, "tin_ore": 1},
		"shades": [Color(0.94, 0.78, 0.44), Color(0.78, 0.58, 0.28), Color(0.55, 0.38, 0.16)]},
	{"id": "iron", "name": "Iron", "level": 4, "hard": 26.0, "grip": 0.06, "cost": {"iron_ore": 1},
		"shades": [Color(0.78, 0.80, 0.84), Color(0.56, 0.58, 0.63), Color(0.34, 0.36, 0.40)]},
	{"id": "gold", "name": "Gold inlay", "level": 3, "hard": -1.0, "grip": 0.0, "cost": {"copper_ore": 1},
		"shades": [Color(1.0, 0.90, 0.45), Color(0.92, 0.72, 0.22), Color(0.70, 0.50, 0.12)]},
]


## Highest Weaponsmithing level the tribe has researched (0 = none).
static func level(c: Colony) -> int:
	var lv := 0
	for k in LEVEL_TECHS.size():
		if c.researched.has(LEVEL_TECHS[k]):
			lv = k + 1
		else:
			break
	return lv


static func code(mat: int, shade: int) -> int:
	return mat * 3 + shade + 1


static func color_of(code_v: int) -> Color:
	if code_v <= 0:
		return Color(0, 0, 0, 0)
	var m: Dictionary = MATERIALS[(code_v - 1) / 3]
	return m["shades"][(code_v - 1) % 3]


static func mat_of(code_v: int) -> Dictionary:
	return MATERIALS[(code_v - 1) / 3]


static func empty_part(size: Vector2i) -> Array:
	var a: Array = []
	a.resize(size.x * size.y)
	a.fill(0)
	return a


## Damage, reach, forge time, cost and the lowest level needed, from a design.
## Returns {"ok": bool, "why": String, ...}.
static func evaluate(design: Dictionary) -> Dictionary:
	var ty: Dictionary = TYPES[design["type"]]
	var bs: Vector2i = ty["blade"]
	var hs: Vector2i = ty["handle"]
	var blade: Array = design["blade"]
	var handle: Array = design["handle"]
	var counts := {}
	var need := int(ty["level"])
	var hard_sum := 0.0
	var hard_n := 0
	var top := bs.y
	var bottom := -1
	for i in blade.size():
		var cv := int(blade[i])
		if cv <= 0:
			continue
		var m := mat_of(cv)
		counts[m["id"]] = int(counts.get(m["id"], 0)) + 1
		need = maxi(need, int(m["level"]))
		if float(m["hard"]) >= 0.0:
			hard_sum += float(m["hard"])
			hard_n += 1
		top = mini(top, i / bs.x)
		bottom = maxi(bottom, i / bs.x)
	var grip := 0.0
	var handle_n := 0
	var h_top := hs.y
	var h_bottom := -1
	for i in handle.size():
		var cv := int(handle[i])
		if cv <= 0:
			continue
		var m := mat_of(cv)
		counts[m["id"]] = int(counts.get(m["id"], 0)) + 1
		need = maxi(need, int(m["level"]))
		grip += float(m["grip"])
		handle_n += 1
		h_top = mini(h_top, i / hs.x)
		h_bottom = maxi(h_bottom, i / hs.x)
	var out := {"ok": true, "why": "", "level": need, "counts": counts}
	if hard_n < 4:
		out["ok"] = false
		out["why"] = "The blade needs at least 4 pixels of a hard material (flint, bone, stone or metal)."
	elif handle_n < 3:
		out["ok"] = false
		out["why"] = "The handle needs at least 3 pixels."
	var hard := hard_sum / maxf(1.0, hard_n)
	var length := float(maxi(0, bottom - top + 1)) / bs.y
	var fill := float(hard_n) / float(bs.x * bs.y)
	var size_f := clampf(0.62 + 0.45 * length + 0.25 * minf(fill * 2.5, 1.0), 0.65, 1.3)
	var grip_f := 1.0 + minf(0.08, grip / maxf(1.0, handle_n) * 1.6)
	out["dmg"] = snappedf(hard * float(ty["power"]) * size_f * grip_f, 0.1)
	var reach := float(ty["reach"])
	if design["type"] == "spear" or design["type"] == "pike":
		var shaft := float(maxi(0, h_bottom - h_top + 1)) / hs.y
		reach *= 0.75 + 0.35 * shaft
	out["range"] = snappedf(reach, 0.05)
	var px := 0
	for k in counts.keys():
		px += int(counts[k])
	out["hours"] = snappedf(float(ty["hours"]) + px / 40.0, 0.1)
	var cost := {}
	for k in counts.keys():
		var m: Dictionary = _mat_by_id(k)
		var units := ceili(int(counts[k]) / 8.0)
		for item in m["cost"].keys():
			cost[item] = int(cost.get(item, 0)) + units * int(m["cost"][item])
	out["cost"] = cost
	return out


static func _mat_by_id(id: String) -> Dictionary:
	for m in MATERIALS:
		if m["id"] == id:
			return m
	return MATERIALS[0]


# ---------------------------------------------------------------- the registry
## Saves a design (new or edited) and makes it forgeable. Returns its id, or "" if invalid.
static func save_design(sim: Sim, design: Dictionary, id := "") -> String:
	var ev := evaluate(design)
	if not ev["ok"]:
		return ""
	if id == "" or not sim.custom_weapons.has(id):
		sim.custom_weapon_seq += 1
		id = "cw_%d" % sim.custom_weapon_seq
	var d := design.duplicate(true)
	d["name"] = str(design.get("name", "")).strip_edges()
	if d["name"] == "":
		d["name"] = "%s %s" % [str(_main_material(ev)), TYPES[design["type"]]["name"]]
	sim.custom_weapons[id] = d
	install(id, d)
	return id


static func _main_material(ev: Dictionary) -> String:
	var best := ""
	var bn := -1
	for k in ev["counts"].keys():
		var m := _mat_by_id(k)
		if float(m["hard"]) > 4.0 and int(ev["counts"][k]) > bn:
			bn = int(ev["counts"][k])
			best = str(m["name"])
	return best


static func install(id: String, d: Dictionary) -> void:
	var ev := evaluate(d)
	Defs.CUSTOM[id] = {"name": d["name"], "era": int(ev["level"]) - 1, "dmg": float(ev["dmg"]), "range": float(ev["range"]),
		"hours": float(ev["hours"]), "cost": ev["cost"], "custom": true, "type": d["type"]}
	_tex_cache.erase(id)


static func install_all(sim: Sim) -> void:
	Defs.CUSTOM.clear()
	_tex_cache.clear()
	for id in sim.custom_weapons.keys():
		install(id, sim.custom_weapons[id])


static func delete_design(sim: Sim, id: String) -> void:
	sim.custom_weapons.erase(id)
	# forged copies stay usable; only the design (and new orders) go away
	for c in sim.colonies:
		c.weapon_orders = c.weapon_orders.filter(func(w): return str(w) != id)


static func is_custom(w: String) -> bool:
	return Defs.CUSTOM.has(w)


# ---------------------------------------------------------------- pictures
static var _tex_cache := {}


## The finished weapon as one picture: blade on top, handle below, centred.
static func image_of(d: Dictionary) -> Image:
	var ty: Dictionary = TYPES[d["type"]]
	var bs: Vector2i = ty["blade"]
	var hs: Vector2i = ty["handle"]
	var w := maxi(bs.x, hs.x)
	var img := Image.create(w, bs.y + hs.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bx := (w - bs.x) / 2
	var hx := (w - hs.x) / 2
	for i in bs.x * bs.y:
		var cv := int(d["blade"][i])
		if cv > 0:
			img.set_pixel(bx + i % bs.x, i / bs.x, color_of(cv))
	for i in hs.x * hs.y:
		var cv := int(d["handle"][i])
		if cv > 0:
			img.set_pixel(hx + i % hs.x, bs.y + i / hs.x, color_of(cv))
	return img


static func texture(sim: Sim, id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	if not sim.custom_weapons.has(id):
		return null
	var t := ImageTexture.create_from_image(image_of(sim.custom_weapons[id]))
	_tex_cache[id] = t
	return t


# ---------------------------------------------------------------- starter designs
## A simple flint knife and flint spear, so the bench isn't empty the first time.
static func starter(type: String) -> Dictionary:
	var ty: Dictionary = TYPES[type]
	var bs: Vector2i = ty["blade"]
	var hs: Vector2i = ty["handle"]
	var blade := empty_part(bs)
	var handle := empty_part(hs)
	var metal = {"knife": 0, "spear": 0, "dagger": 5, "short_sword": 9, "longsword": 10, "pike": 10}[type]
	var cx := bs.x / 2
	for y in bs.y:
		var half := 0
		if type == "spear" or type == "pike":
			half = clampi(int(float(y) / bs.y * 3.5), 0, 3) if y < bs.y - 2 else 0
		else:
			half = 0 if y == 0 else (1 if y < 3 or bs.x < 7 else 2)
		for x in range(cx - half, cx + half + 1):
			var shade := 0 if x < cx else (1 if x == cx else 2)
			blade[y * bs.x + x] = code(metal, shade)
	var hcx := hs.x / 2
	var wood_i := 2
	var wrap_i := 3
	for y in hs.y:
		if hs.x >= 7 and y == 0:
			for x in hs.x:
				handle[y * hs.x + x] = code(metal if metal >= 8 else 1, 1)        # guard
			continue
		var m := wrap_i if (y % 2 == 0 and y < 6) else wood_i
		if type == "spear" or type == "pike":
			m = wrap_i if y < 3 else wood_i
		for x in range(hcx - (1 if hs.x >= 5 else 0), hcx + (1 if hs.x >= 5 else 0) + 1):
			handle[y * hs.x + x] = code(m, 1 if x == hcx else 2)
	return {"name": "", "type": type, "blade": blade, "handle": handle}
