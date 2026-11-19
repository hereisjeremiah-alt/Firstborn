class_name WorldMap
extends RefCounted
## Grid data for the whole world. Everything is stored in flat packed arrays (index = y * w + x)
## so very large maps stay cheap in memory and fast to iterate.

var w := 0
var h := 0
var seed_value := 0
var terrain := PackedByteArray()       # Defs.T
var elevation := PackedFloat32Array()
var moisture := PackedFloat32Array()
var base_temp := PackedFloat32Array()  # yearly mean temperature in °C
var res_type := PackedByteArray()      # Defs.R
var res_amount := PackedInt32Array()
var fish := PackedFloat32Array()       # fish stock on water tiles
var blocked := PackedByteArray()       # 1 = fence (blocks animals)
var wall := PackedByteArray()          # 1 = finished wall (blocks people too)
var road := PackedByteArray()          # 1 = road (people walk about twice as fast)
var snowy := PackedByteArray()         # 1 = ground currently covered by seasonal snow
var spawn := Vector2i.ZERO
var regrow_tiles := PackedInt32Array()   # tiles whose resource can grow back (scanned daily)
var fish_day := PackedInt32Array()       # day each water tile's fish stock was last brought up to date
var sea_level := 0.0
var hill_level := 0.5
var peak_level := 1.0
var min_level := -1.0


func setup(width: int, height: int) -> void:
	w = width
	h = height
	var n := w * h
	terrain.resize(n)
	elevation.resize(n)
	moisture.resize(n)
	base_temp.resize(n)
	res_type.resize(n)
	res_amount.resize(n)
	fish.resize(n)
	blocked.resize(n)
	wall.resize(n)
	road.resize(n)
	fish_day.resize(n)
	fish_day.fill(0)
	snowy.resize(n)
	terrain.fill(0)
	res_type.fill(0)
	res_amount.fill(0)
	fish.fill(0.0)
	blocked.fill(0)
	snowy.fill(0)


func build_regrow_list() -> void:
	regrow_tiles = PackedInt32Array()
	for i in w * h:
		var r := res_type[i]
		if r != 0 and Defs.RES[r]["regrow"]:
			regrow_tiles.append(i)


## Fish recover slowly over time; brought up to date lazily when someone fishes.
func fish_level(i: int, day: int, winter: bool) -> float:
	var days := day - fish_day[i]
	if days > 0:
		var cap := 8.0 if terrain[i] == Defs.T.LAKE else 6.0
		fish[i] = minf(cap, fish[i] + days * (0.15 if winter else 0.45))
		fish_day[i] = day
	return fish[i]


func idx(p: Vector2i) -> int:
	return p.y * w + p.x


func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func t_at(p: Vector2i) -> int:
	return terrain[p.y * w + p.x]


func terrain_cost(p: Vector2i) -> float:
	if not inb(p):
		return 0.0
	return Defs.TERRAIN[terrain[idx(p)]]["cost"]


## Movement cost for walkers (terrain plus whatever is growing on the tile). 0 = blocked.
func cost_at(p: Vector2i) -> float:
	if not inb(p):
		return 0.0
	var i := idx(p)
	var c: float = Defs.TERRAIN[terrain[i]]["cost"]
	if c <= 0.0:
		return 0.0
	if road[i] == 1:
		return Defs.ROAD_SPEED_COST + (0.15 if snowy[i] == 1 else 0.0)
	var r := res_type[i]
	if r != Defs.R.NONE:
		c += float(Defs.RES[r]["cost"])
	if snowy[i] == 1:
		c += 0.3
	return c


func walkable(p: Vector2i) -> bool:
	return cost_at(p) > 0.0 and wall[idx(p)] == 0


func animal_walkable(p: Vector2i) -> bool:
	if not inb(p):
		return false
	var i := idx(p)
	if blocked[i] == 1:
		return false
	return Defs.TERRAIN[terrain[i]]["cost"] > 0.0 and terrain[i] != Defs.T.RIVER


func is_water(p: Vector2i) -> bool:
	return inb(p) and Defs.TERRAIN[terrain[idx(p)]]["water"]


func is_fresh(p: Vector2i) -> bool:
	return inb(p) and Defs.TERRAIN[terrain[idx(p)]]["fresh"]


func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / Defs.TILE), floori(pos.y / Defs.TILE))


func center_of(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * Defs.TILE, (t.y + 0.5) * Defs.TILE)


## Ring search outward from origin. Returns the first tile (closest ring) satisfying pred, or (-1,-1).
func find_nearest(origin: Vector2i, max_r: int, pred: Callable) -> Vector2i:
	if inb(origin) and pred.call(origin):
		return origin
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var p := Vector2i(origin.x + dx, origin.y + dy)
				if inb(p) and pred.call(p):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = p
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				var p := Vector2i(origin.x + dx, origin.y + dy)
				if inb(p) and pred.call(p):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = p
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Fast specialised ring search for harvestable resources (perimeter of each ring only).
## types: Dictionary used as a set of Defs.R values. claims: tile index -> claimer id.
func find_resource(origin: Vector2i, max_r: int, types: Dictionary, claims: Dictionary) -> Vector2i:
	if _res_ok(origin.x, origin.y, types, claims):
		return origin
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var x: int = origin.x + dx
				var y: int = origin.y + dy
				if _res_ok(x, y, types, claims):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = Vector2i(x, y)
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				var x: int = origin.x + dx
				var y: int = origin.y + dy
				if _res_ok(x, y, types, claims):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = Vector2i(x, y)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _res_ok(x: int, y: int, types: Dictionary, claims: Dictionary) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var i := y * w + x
	var rt := res_type[i]
	return rt != 0 and types.has(rt) and res_amount[i] > 0 and not claims.has(i)


## Nearest walkable tile next to (or at) p.
func walkable_near(p: Vector2i, max_r: int = 3) -> Vector2i:
	return find_nearest(p, max_r, func(q: Vector2i) -> bool: return walkable(q))


## A walkable tile from which water tile `water` can be reached (adjacent).
func shore_of(water: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q: Vector2i = water + d
		if walkable(q) and t_at(q) != Defs.T.RIVER:
			return q
	if t_at(water) == Defs.T.RIVER:
		return water   # rivers can be waded into
	return Vector2i(-1, -1)
