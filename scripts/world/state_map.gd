class_name StateMap
extends RefCounted
## Territory states: the land is divided into named regions (roughly 24x24 tiles each, following
## coasts). A tribe owns the state its camp stands in and can claim unclaimed neighbouring states
## by planting its banner at their centre. Taking a state another tribe holds needs a war.

const SPACING := 24
const MIN_SIZE := 30

var w := 0
var h := 0
var ids := PackedInt32Array()       # tile -> state id (-1 = sea)
var owners := PackedInt32Array()    # state id -> civ id (-1 = unclaimed)
var centers: Array = []             # state id -> Vector2i (where the banner goes)
var sizes: Array = []               # state id -> tile count
var names: Array = []
var neighbors: Array = []           # state id -> Dictionary of neighbouring state ids
var bboxes: Array = []              # state id -> Rect2 (world pixels)
var borders: Array = []             # state id -> PackedVector2Array of line segments (world pixels)
var version := 0                    # bumps whenever an owner changes (maps redraw)


static func build(wm: WorldMap, seed_value: int) -> StateMap:
	var sm := StateMap.new()
	sm._generate(wm, seed_value)
	return sm


static func _is_land(wm: WorldMap, i: int) -> bool:
	var t := wm.terrain[i]
	return t != Defs.T.OCEAN and t != Defs.T.DEEP_OCEAN


func _generate(wm: WorldMap, seed_value: int) -> void:
	w = wm.w
	h = wm.h
	var n := w * h
	ids.resize(n)
	ids.fill(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var queue := PackedInt32Array()
	var count := 0
	# seeds on a jittered grid
	for gy in range(0, h, SPACING):
		for gx in range(0, w, SPACING):
			var x := clampi(gx + rng.randi_range(2, SPACING - 3), 0, w - 1)
			var y := clampi(gy + rng.randi_range(2, SPACING - 3), 0, h - 1)
			var i := y * w + x
			if _is_land(wm, i) and ids[i] < 0:
				ids[i] = count
				queue.append(i)
				count += 1
	count = _flood(wm, queue, count)
	# land the grid missed (small islands) gets states of its own
	for i in n:
		if ids[i] < 0 and _is_land(wm, i):
			ids[i] = count
			count = _flood(wm, PackedInt32Array([i]), count + 1)
	# measure, then fold tiny slivers into a neighbour
	var sz := PackedInt32Array()
	sz.resize(count)
	for i in n:
		if ids[i] >= 0:
			sz[ids[i]] += 1
	var remap := PackedInt32Array()
	remap.resize(count)
	for s in count:
		remap[s] = s
	for i in n:
		var s := ids[i]
		if s < 0 or sz[s] >= MIN_SIZE:
			continue
		var x := i % w
		var y := i / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q = Vector2i(x, y) + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var o := ids[q.y * w + q.x]
			if o >= 0 and o != s and sz[o] >= MIN_SIZE:
				remap[s] = o
				break
	# compact ids
	var final := PackedInt32Array()
	final.resize(count)
	final.fill(-1)
	var next := 0
	for s in count:
		var r := remap[s]
		while remap[r] != r:
			r = remap[r]
		if final[r] < 0:
			final[r] = next
			next += 1
		final[s] = final[r]
	for i in n:
		if ids[i] >= 0:
			ids[i] = final[ids[i]]
	_measure(wm, next, rng)


func _flood(wm: WorldMap, queue: PackedInt32Array, count: int) -> int:
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		var s := ids[i]
		if x > 0:
			_grow(wm, i - 1, s, queue)
		if x < w - 1:
			_grow(wm, i + 1, s, queue)
		if y > 0:
			_grow(wm, i - w, s, queue)
		if y < h - 1:
			_grow(wm, i + w, s, queue)
	return count


func _grow(wm: WorldMap, j: int, s: int, queue: PackedInt32Array) -> void:
	if ids[j] < 0 and _is_land(wm, j):
		ids[j] = s
		queue.append(j)


func _measure(wm: WorldMap, count: int, rng: RandomNumberGenerator) -> void:
	owners.resize(count)
	owners.fill(-1)
	centers.clear()
	sizes.clear()
	names.clear()
	neighbors.clear()
	bboxes.clear()
	borders.clear()
	var sx := PackedFloat64Array()
	var sy := PackedFloat64Array()
	sx.resize(count)
	sy.resize(count)
	var terr_count: Array = []
	var mins: Array = []
	var maxs: Array = []
	for s in count:
		sizes.append(0)
		neighbors.append({})
		terr_count.append({})
		mins.append(Vector2i(w, h))
		maxs.append(Vector2i(-1, -1))
		borders.append(PackedVector2Array())
	var T := float(Defs.TILE)
	for y in h:
		for x in w:
			var i := y * w + x
			var s := ids[i]
			if s >= 0:
				sizes[s] += 1
				sx[s] += x
				sy[s] += y
				var tc: Dictionary = terr_count[s]
				var ter := wm.terrain[i]
				tc[ter] = int(tc.get(ter, 0)) + 1
				mins[s] = Vector2i(mini(mins[s].x, x), mini(mins[s].y, y))
				maxs[s] = Vector2i(maxi(maxs[s].x, x), maxi(maxs[s].y, y))
			# borders on the right and bottom edge of this tile
			if x < w - 1:
				var r := ids[i + 1]
				if r != s:
					var a := Vector2((x + 1) * T, y * T)
					var b := Vector2((x + 1) * T, (y + 1) * T)
					_border(s, a, b)
					_border(r, a, b)
					if s >= 0 and r >= 0:
						neighbors[s][r] = true
						neighbors[r][s] = true
			if y < h - 1:
				var d := ids[i + w]
				if d != s:
					var a := Vector2(x * T, (y + 1) * T)
					var b := Vector2((x + 1) * T, (y + 1) * T)
					_border(s, a, b)
					_border(d, a, b)
					if s >= 0 and d >= 0:
						neighbors[s][d] = true
						neighbors[d][s] = true
	# banner spot: the walkable tile closest to the middle of the state
	for s in count:
		var c := Vector2(sx[s] / maxi(1, sizes[s]), sy[s] / maxi(1, sizes[s]))
		centers.append(Vector2i(c))
		bboxes.append(Rect2(Vector2(mins[s]) * T, Vector2(maxs[s] - mins[s] + Vector2i(1, 1)) * T))
	var best_d := PackedFloat64Array()
	best_d.resize(count)
	best_d.fill(1e18)
	for y in h:
		for x in w:
			var i := y * w + x
			var s := ids[i]
			if s < 0 or wm.cost_at(Vector2i(x, y)) <= 0.0:
				continue
			var d := Vector2(x, y).distance_squared_to(Vector2(sx[s] / sizes[s], sy[s] / sizes[s]))
			if d < best_d[s]:
				best_d[s] = d
				centers[s] = Vector2i(x, y)
	for s in count:
		names.append(_name(rng, terr_count[s]))


func _border(s: int, a: Vector2, b: Vector2) -> void:
	if s < 0:
		return
	var arr: PackedVector2Array = borders[s]
	arr.append(a)
	arr.append(b)
	borders[s] = arr


const _TERRAIN_WORD := {
	Defs.T.PLAINS: ["Plains", "Fields", "Meadows"], Defs.T.GRASSLAND: ["Grasslands", "Downs", "Leas"],
	Defs.T.FOREST: ["Woods", "Forest", "Weald"], Defs.T.DENSE_FOREST: ["Deepwood", "Thicket", "Forest"],
	Defs.T.SNOW_FOREST: ["Frostwood", "Pinewood"], Defs.T.TUNDRA: ["Barrens", "Tundra", "Coldlands"],
	Defs.T.RAINFOREST: ["Jungle", "Rainwood"], Defs.T.HILLS: ["Hills", "Heights", "Ridge"],
	Defs.T.ROCKY: ["Crags", "Rocks", "Scarp"], Defs.T.MOUNTAIN: ["Mountains", "Peaks", "Spine"],
	Defs.T.PEAK: ["Peaks", "Summits"], Defs.T.BEACH: ["Coast", "Shore", "Strand"], Defs.T.VALLEY: ["Vale", "Valley", "Dale"],
	Defs.T.DESERT: ["Desert", "Sands", "Dunes"], Defs.T.HIGH_DESERT: ["Mesa", "Drylands"], Defs.T.SAVANNA: ["Savanna", "Veld"],
	Defs.T.STEPPE: ["Steppe", "Wilds"], Defs.T.SWAMP: ["Marsh", "Fens", "Bog"], Defs.T.BADLANDS: ["Badlands", "Wastes"],
	Defs.T.ALPINE: ["Highlands", "Uplands"], Defs.T.SNOWY: ["Snowfields"],
}


func _name(rng: RandomNumberGenerator, tc: Dictionary) -> String:
	var best := Defs.T.PLAINS
	var best_n := -1
	for k in tc.keys():
		if int(k) == Defs.T.LAKE or int(k) == Defs.T.RIVER or int(k) == Defs.T.SPRING:
			continue
		if int(tc[k]) > best_n:
			best_n = int(tc[k])
			best = int(k)
	var words: Array = _TERRAIN_WORD.get(best, ["Lands"])
	var root := Names.person(rng, "M", rng.randi_range(0, 5)).split(" ")[0]
	if rng.randf() < 0.5:
		return "%s %s" % [root, words[rng.randi() % words.size()]]
	return "The %s of %s" % [words[rng.randi() % words.size()], root]


func count() -> int:
	return owners.size()


func at(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return -1
	return ids[t.y * w + t.x]


func owner_at(t: Vector2i) -> int:
	var s := at(t)
	return owners[s] if s >= 0 else -1


func owned_by(civ_id: int) -> Array:
	var out: Array = []
	for s in owners.size():
		if owners[s] == civ_id:
			out.append(s)
	return out


func set_owner(s: int, civ_id: int) -> void:
	owners[s] = civ_id
	version += 1


## True if state s touches a state owned by civ_id.
func borders_civ(s: int, civ_id: int) -> bool:
	for o in (neighbors[s] as Dictionary).keys():
		if owners[int(o)] == civ_id:
			return true
	return false
