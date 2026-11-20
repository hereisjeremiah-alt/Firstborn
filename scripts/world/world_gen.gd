class_name WorldGen
extends RefCounted
## Deterministic seeded world generation: continents, oceans, mountains, hills, rivers, lakes,
## springs, valleys, biomes and resource placement. The same seed + size always gives the same world.

const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func generate(seed_value: int, size: int) -> WorldMap:
	var wm := WorldMap.new()
	wm.setup(size, size)
	wm.seed_value = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scale := 1.0      # features keep the same size in tiles; bigger maps simply hold more of them

	var n_elev := _noise(seed_value, 0.011 * scale, 5)
	var n_cont := _noise(seed_value + 11, 0.004 * scale, 3)
	var n_warp := _noise(seed_value + 13, 0.02, 2)
	var n_moist := _noise(seed_value + 23, 0.012 * scale, 4)
	var n_temp := _noise(seed_value + 37, 0.008 * scale, 3)
	var n_lake := _noise(seed_value + 41, 0.035 * scale, 2)
	var n_detail := _noise(seed_value + 53, 0.06 * scale, 2)

	var n := size * size
	# --- land masses: several continents (each a cluster of blobs) plus small islands
	var blobs := _land_blobs(rng, size)
	for y in size:
		for x in size:
			# warp the coordinates so coastlines wiggle
			var wx := x + n_warp.get_noise_2d(x, y) * 22.0
			var wy := y + n_warp.get_noise_2d(x + 500, y + 500) * 22.0
			var land := 0.0
			for bl in blobs:
				var dx: float = (wx - float(bl[0])) / float(bl[2])
				var dy: float = (wy - float(bl[1])) / float(bl[2])
				var dd := dx * dx + dy * dy
				if dd < 1.0:
					land = maxf(land, (1.0 - dd) * float(bl[3]))
			# keep a band of ocean around the edge of the world
			var edge := minf(minf(x, y), minf(size - 1 - x, size - 1 - y)) / (size * 0.06)
			var e := land * 1.0 + n_elev.get_noise_2d(x, y) * 0.42 + n_cont.get_noise_2d(x, y) * 0.22 - 0.38
			e -= (1.0 - clampf(edge, 0.0, 1.0)) * 0.9
			wm.elevation[y * size + x] = e
			wm.moisture[y * size + x] = clampf(n_moist.get_noise_2d(x, y) * 0.75 + 0.5, 0.0, 1.0)

	# --- thresholds: sea level from the whole map, everything else measured on land or water only,
	# so the balance of hills, mountains and deep sea is stable for every seed and size
	var sorted := wm.elevation.duplicate()
	sorted.sort()
	var sea_i := int(n * 0.60)
	var land_n := n - sea_i
	var deep_th: float = sorted[int(sea_i * 0.55)]
	var sea_th: float = sorted[sea_i]
	var beach_th: float = sorted[sea_i + int(land_n * 0.05)]
	var valley_hi: float = sorted[sea_i + int(land_n * 0.50)]
	var hill_th: float = sorted[sea_i + int(land_n * 0.74)]
	var mount_th: float = sorted[sea_i + int(land_n * 0.88)]
	var peak_th: float = sorted[sea_i + int(land_n * 0.955)]
	wm.sea_level = sea_th
	wm.hill_level = hill_th
	wm.peak_level = sorted[n - 1]
	wm.min_level = sorted[0]

	# --- base temperature: cold north, hot south, colder at altitude
	for y in size:
		for x in size:
			var i := y * size + x
			var lat := float(y) / float(size)
			var alt := clampf((wm.elevation[i] - sea_th) / maxf(0.001, peak_th - sea_th), 0.0, 1.0)
			wm.base_temp[i] = lerpf(-3.0, 27.0, lat) + n_temp.get_noise_2d(x, y) * 7.0 - alt * 14.0

	# --- classify terrain
	for y in size:
		for x in size:
			var i := y * size + x
			var e := wm.elevation[i]
			var m := wm.moisture[i]
			var t := wm.base_temp[i]
			var ter := Defs.T.PLAINS
			if e < deep_th:
				ter = Defs.T.DEEP_OCEAN
			elif e < sea_th:
				ter = Defs.T.OCEAN
			elif e >= peak_th:
				ter = Defs.T.PEAK
			elif e >= mount_th:
				ter = Defs.T.MOUNTAIN
			elif e >= hill_th:
				ter = Defs.T.ROCKY if (m < 0.42 or n_detail.get_noise_2d(x, y) > 0.35) else Defs.T.HILLS
				if t < 1.0 and ter == Defs.T.HILLS:
					ter = Defs.T.TUNDRA
				elif t > 11.0 and m < 0.40:
					ter = Defs.T.BADLANDS if n_detail.get_noise_2d(x, y) > 0.0 else Defs.T.HIGH_DESERT
				elif t < 9.0 and t >= 1.0 and m > 0.55:
					ter = Defs.T.ALPINE
			elif e < beach_th:
				ter = Defs.T.BEACH
			else:
				ter = _biome(t, m, e < sea_th + (hill_th - sea_th) * 0.22)
			wm.terrain[i] = ter

	# --- lakes (inland basins)
	for y in range(2, size - 2):
		for x in range(2, size - 2):
			var i := y * size + x
			var ter := wm.terrain[i]
			if ter == Defs.T.BEACH or ter == Defs.T.OCEAN or ter == Defs.T.DEEP_OCEAN:
				continue
			if wm.elevation[i] < hill_th and n_lake.get_noise_2d(x, y) > 0.42 and _min_dist_ocean_ok(wm, x, y):
				wm.terrain[i] = Defs.T.LAKE

	# --- rivers: start in the highlands and flow downhill to a lake or the sea
	var river_count := maxi(6, size / 20)
	var made := 0
	var tries := 0
	while made < river_count and tries < river_count * 40:
		tries += 1
		var s := Vector2i(rng.randi_range(8, size - 9), rng.randi_range(8, size - 9))
		var st := wm.t_at(s)
		if not (st == Defs.T.HILLS or st == Defs.T.ROCKY or st == Defs.T.TUNDRA):
			continue
		if _carve_river(wm, s, rng):
			made += 1

	return finish_world(wm, rng, valley_hi)


## Springs, valleys, fish, resources and the starting spot: the last steps of every world.
static func finish_world(wm: WorldMap, rng: RandomNumberGenerator, valley_hi: float) -> WorldMap:
	var size := wm.w
	var n := wm.w * wm.h
	# --- springs: clean fresh water in the hills
	var springs := 0
	var tries := 0
	while springs < maxi(4, size / 32) and tries < 2000:
		tries += 1
		var p := Vector2i(rng.randi_range(4, wm.w - 5), rng.randi_range(4, wm.h - 5))
		var pt := wm.t_at(p)
		if pt == Defs.T.HILLS or pt == Defs.T.GRASSLAND or pt == Defs.T.FOREST or pt == Defs.T.VALLEY:
			wm.terrain[wm.idx(p)] = Defs.T.SPRING
			springs += 1

	# --- valleys: fertile lowland strips along rivers in upland areas
	for y in range(1, wm.h - 1):
		for x in range(1, wm.w - 1):
			var i := y * wm.w + x
			if wm.terrain[i] != Defs.T.RIVER:
				continue
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var q := Vector2i(x + ox, y + oy)
					if not wm.inb(q):
						continue
					var qi := wm.idx(q)
					var qt := wm.terrain[qi]
					if (qt == Defs.T.PLAINS or qt == Defs.T.GRASSLAND or qt == Defs.T.FOREST) and wm.elevation[qi] > valley_hi:
						wm.terrain[qi] = Defs.T.VALLEY

	# --- beaches also form along lakes in warm areas
	for y in range(1, wm.h - 1):
		for x in range(1, wm.w - 1):
			var i := y * wm.w + x
			if wm.terrain[i] != Defs.T.LAKE:
				continue
			for d in N4:
				var q: Vector2i = Vector2i(x, y) + d
				var qi := wm.idx(q)
				if wm.terrain[qi] == Defs.T.PLAINS and wm.base_temp[qi] > 18.0:
					wm.terrain[qi] = Defs.T.BEACH

	# --- fish stocks
	for i in n:
		match wm.terrain[i]:
			Defs.T.OCEAN:
				wm.fish[i] = 6.0
			Defs.T.DEEP_OCEAN:
				wm.fish[i] = 3.0
			Defs.T.LAKE:
				wm.fish[i] = 8.0
			Defs.T.RIVER:
				wm.fish[i] = 5.0

	_place_resources(wm, rng)
	wm.spawn = _find_spawn(wm, rng)
	# clear a small camp area at the spawn
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var q := wm.spawn + Vector2i(ox, oy)
			if wm.inb(q):
				var r := wm.res_type[wm.idx(q)]
				if r != Defs.R.BERRY_BUSH:
					wm.res_type[wm.idx(q)] = Defs.R.NONE
					wm.res_amount[wm.idx(q)] = 0
	return wm


## [x, y, radius, strength] blobs. Continents are clusters of 3-5 overlapping blobs; islands are single small ones.
static func _land_blobs(rng: RandomNumberGenerator, size: int) -> Array:
	var blobs: Array = []
	var count := 2 + size / 256 + rng.randi_range(0, 1)
	var centers: Array = []
	for c in count:
		var best := Vector2(size * 0.5, size * 0.5)
		for attempt in 60:
			var cand := Vector2(rng.randf_range(0.18, 0.82) * size, rng.randf_range(0.18, 0.82) * size)
			var ok := true
			for o in centers:
				if cand.distance_to(o) < size * 0.34:
					ok = false
					break
			best = cand
			if ok:
				break
		centers.append(best)
		var r := size * rng.randf_range(0.13, 0.19)
		blobs.append([best.x, best.y, r, 1.0])
		for k in rng.randi_range(3, 5):
			var ang := rng.randf() * TAU
			var off := Vector2(cos(ang), sin(ang)) * r * rng.randf_range(0.4, 0.9)
			blobs.append([best.x + off.x, best.y + off.y, r * rng.randf_range(0.45, 0.75), rng.randf_range(0.8, 1.0)])
	# small islands scattered across the ocean
	for k in size / 16:
		var p := Vector2(rng.randf_range(0.06, 0.94) * size, rng.randf_range(0.06, 0.94) * size)
		blobs.append([p.x, p.y, rng.randf_range(3.5, 10.0), rng.randf_range(0.85, 1.05)])
	return blobs


static func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = s
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = freq
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = octaves
	return nz


static func _biome(t: float, m: float, lowland: bool) -> int:
	if t < 2.0:
		return Defs.T.SNOW_FOREST if m > 0.45 else Defs.T.TUNDRA
	if lowland and m > 0.76 and t > 6.0:
		return Defs.T.SWAMP
	if t > 20.0:
		if m < 0.36:
			return Defs.T.DESERT
		if m < 0.47:
			return Defs.T.SAVANNA
		if m > 0.58:
			return Defs.T.RAINFOREST
		return Defs.T.GRASSLAND
	if m < 0.31:
		return Defs.T.HIGH_DESERT if t < 15.0 else Defs.T.DESERT
	if t < 10.0 and m < 0.42:
		return Defs.T.STEPPE
	if m > 0.68:
		return Defs.T.DENSE_FOREST
	if m > 0.50:
		return Defs.T.FOREST
	if m > 0.34:
		return Defs.T.GRASSLAND
	return Defs.T.PLAINS


static func _min_dist_ocean_ok(wm: WorldMap, x: int, y: int) -> bool:
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var q := Vector2i(x + ox, y + oy)
			if wm.inb(q):
				var t := wm.t_at(q)
				if t == Defs.T.OCEAN or t == Defs.T.DEEP_OCEAN or t == Defs.T.BEACH:
					return false
	return true


static func _carve_river(wm: WorldMap, start: Vector2i, rng: RandomNumberGenerator) -> bool:
	var cur := start
	var visited := {}
	var course: Array = []
	for step in 900:
		visited[cur] = true
		course.append(cur)
		var best := Vector2i(-1, -1)
		var best_e := 1e9
		for d in N4:
			var q: Vector2i = cur + d
			if not wm.inb(q) or visited.has(q):
				continue
			var qt := wm.t_at(q)
			if qt == Defs.T.MOUNTAIN or qt == Defs.T.PEAK:
				continue
			var e := wm.elevation[wm.idx(q)] + rng.randf_range(-0.015, 0.015)
			if e < best_e:
				best_e = e
				best = q
		if best.x < 0:
			break
		var bt := wm.t_at(best)
		if bt == Defs.T.OCEAN or bt == Defs.T.DEEP_OCEAN or bt == Defs.T.LAKE or bt == Defs.T.RIVER:
			_commit_river(wm, course)
			return true
		cur = best
	if course.size() < 25:
		return false
	# no outlet: the river pools into a small lake at its end
	_commit_river(wm, course)
	var end_p: Vector2i = course[course.size() - 1]
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var q := end_p + Vector2i(ox, oy)
			if wm.inb(q) and ox * ox + oy * oy <= 5:
				var qt := wm.t_at(q)
				if qt != Defs.T.MOUNTAIN and qt != Defs.T.PEAK:
					wm.terrain[wm.idx(q)] = Defs.T.LAKE
	return true


static func _commit_river(wm: WorldMap, course: Array) -> void:
	for k in course.size():
		var p: Vector2i = course[k]
		wm.terrain[wm.idx(p)] = Defs.T.RIVER
		# the lower course widens
		if k > 70:
			var side := Vector2i(1, 0) if (k / 30) % 2 == 0 else Vector2i(0, 1)
			var q := p + side
			if wm.inb(q):
				var qt := wm.t_at(q)
				if qt != Defs.T.MOUNTAIN and qt != Defs.T.PEAK and qt != Defs.T.OCEAN and qt != Defs.T.DEEP_OCEAN:
					wm.terrain[wm.idx(q)] = Defs.T.RIVER


static func _place_resources(wm: WorldMap, rng: RandomNumberGenerator) -> void:
	for y in wm.h:
		for x in wm.w:
			var i := y * wm.w + x
			var t := wm.terrain[i]
			var temp := wm.base_temp[i]
			var roll := rng.randf()
			var r := Defs.R.NONE
			var deciduous := Defs.R.TREE if temp > 7.0 else Defs.R.PINE
			match t:
				Defs.T.PLAINS:
					r = _pick(roll, [[0.025, Defs.R.BERRY_BUSH], [0.09, Defs.R.GRASS], [0.012, Defs.R.STICKS], [0.012, Defs.R.SMALL_STONES], [0.018, deciduous], [0.004, Defs.R.LARGE_STONE]])
				Defs.T.GRASSLAND:
					r = _pick(roll, [[0.13, Defs.R.GRASS], [0.03, Defs.R.BERRY_BUSH], [0.035, deciduous], [0.015, Defs.R.STICKS], [0.01, Defs.R.SMALL_STONES]])
				Defs.T.FOREST:
					r = _pick(roll, [[0.48, deciduous], [0.03, Defs.R.MUSHROOM], [0.02, Defs.R.BERRY_BUSH], [0.04, Defs.R.STICKS], [0.01, Defs.R.SMALL_STONES], [0.006, Defs.R.LARGE_STONE]])
				Defs.T.DENSE_FOREST:
					r = _pick(roll, [[0.70, deciduous], [0.05, Defs.R.MUSHROOM], [0.03, Defs.R.STICKS], [0.006, Defs.R.BOULDER]])
				Defs.T.SNOW_FOREST:
					r = _pick(roll, [[0.50, Defs.R.SNOW_PINE], [0.03, Defs.R.STICKS], [0.015, Defs.R.SMALL_STONES], [0.008, Defs.R.BERRY_BUSH]])
				Defs.T.TUNDRA:
					r = _pick(roll, [[0.03, Defs.R.GRASS], [0.03, Defs.R.SMALL_STONES], [0.01, Defs.R.LARGE_STONE], [0.03, Defs.R.SNOW_PINE]])
				Defs.T.RAINFOREST:
					r = _pick(roll, [[0.62, Defs.R.JUNGLE_TREE], [0.05, Defs.R.FRUIT_BUSH], [0.03, Defs.R.MUSHROOM], [0.02, Defs.R.STICKS]])
				Defs.T.HILLS:
					r = _pick(roll, [[0.05, Defs.R.SMALL_STONES], [0.04, Defs.R.LARGE_STONE], [0.02, Defs.R.BOULDER], [0.08, Defs.R.PINE], [0.04, Defs.R.GRASS], [0.006, Defs.R.COPPER_ORE], [0.004, Defs.R.TIN_ORE]])
				Defs.T.ROCKY:
					var ore_mult := 3.0 if _near_mountain(wm, x, y) else 1.0
					r = _pick(roll, [[0.06, Defs.R.LARGE_STONE], [0.05, Defs.R.BOULDER], [0.06, Defs.R.SMALL_STONES], [0.01 * ore_mult, Defs.R.COPPER_ORE], [0.008 * ore_mult, Defs.R.TIN_ORE], [0.008 * ore_mult, Defs.R.IRON_ORE]])
				Defs.T.BEACH:
					r = _pick(roll, [[0.04 if temp > 15.0 else 0.0, Defs.R.PALM], [0.03, Defs.R.SMALL_STONES], [0.015, Defs.R.STICKS]])
				Defs.T.DESERT:
					r = _pick(roll, [[0.04, Defs.R.CACTUS], [0.03, Defs.R.SMALL_STONES], [0.03, Defs.R.SHRUB], [0.01, Defs.R.LARGE_STONE]])
				Defs.T.HIGH_DESERT:
					r = _pick(roll, [[0.05, Defs.R.JUNIPER], [0.06, Defs.R.SHRUB], [0.04, Defs.R.SMALL_STONES], [0.02, Defs.R.LARGE_STONE], [0.01, Defs.R.CACTUS]])
				Defs.T.SAVANNA:
					r = _pick(roll, [[0.035, Defs.R.ACACIA], [0.12, Defs.R.GRASS], [0.02, Defs.R.SHRUB], [0.012, Defs.R.BERRY_BUSH]])
				Defs.T.STEPPE:
					r = _pick(roll, [[0.14, Defs.R.GRASS], [0.02, Defs.R.SMALL_STONES], [0.02, Defs.R.SHRUB], [0.012, Defs.R.BERRY_BUSH]])
				Defs.T.SWAMP:
					r = _pick(roll, [[0.18, Defs.R.REEDS], [0.04, Defs.R.MUSHROOM], [0.12, deciduous]])
				Defs.T.BADLANDS:
					var bad_ore := 3.0 if _near_mountain(wm, x, y) else 1.5
					r = _pick(roll, [[0.06, Defs.R.LARGE_STONE], [0.03, Defs.R.BOULDER], [0.05, Defs.R.SMALL_STONES], [0.012 * bad_ore, Defs.R.COPPER_ORE], [0.008 * bad_ore, Defs.R.IRON_ORE], [0.02, Defs.R.SHRUB]])
				Defs.T.ALPINE:
					r = _pick(roll, [[0.08, Defs.R.GRASS], [0.06, Defs.R.PINE], [0.04, Defs.R.SMALL_STONES], [0.02, Defs.R.BERRY_BUSH]])
				Defs.T.VALLEY:
					r = _pick(roll, [[0.045, Defs.R.BERRY_BUSH], [0.10, Defs.R.GRASS], [0.05, deciduous], [0.015, Defs.R.STICKS]])
			if r != Defs.R.NONE:
				wm.res_type[i] = r
				wm.res_amount[i] = Defs.RES[r]["amount"]
	wm.build_regrow_list()


static func _pick(roll: float, table: Array) -> int:
	var acc := 0.0
	for e in table:
		acc += float(e[0])
		if roll < acc:
			return int(e[1])
	return Defs.R.NONE


static func _near_mountain(wm: WorldMap, x: int, y: int) -> bool:
	for d in N4:
		var q: Vector2i = Vector2i(x, y) + d * 2
		if wm.inb(q) and wm.t_at(q) == Defs.T.MOUNTAIN:
			return true
	return false


static func _find_spawn(wm: WorldMap, rng: RandomNumberGenerator) -> Vector2i:
	var good := [Defs.T.PLAINS, Defs.T.GRASSLAND, Defs.T.VALLEY, Defs.T.FOREST, Defs.T.SAVANNA, Defs.T.STEPPE]
	var margin := int(wm.w * 0.15)
	var margin_y := int(wm.h * 0.15)
	for attempt in 6000:
		var p := Vector2i(rng.randi_range(margin, wm.w - margin), rng.randi_range(margin_y, wm.h - margin_y))
		var i := wm.idx(p)
		if not good.has(int(wm.terrain[i])):
			continue
		var t := wm.base_temp[i]
		var relax := attempt > 3000
		if not relax and (t < 8.0 or t > 22.0):
			continue
		if has_fresh_water_near(wm, p, 7 if not relax else 14):
			return p
	# fallback: any walkable land tile near the middle
	return wm.walkable_near(Vector2i(wm.w / 2, wm.h / 2), wm.w / 2)


static func has_fresh_water_near(wm: WorldMap, p: Vector2i, r: int) -> bool:
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var q := p + Vector2i(ox, oy)
			if wm.inb(q) and wm.is_fresh(q):
				return true
	return false
