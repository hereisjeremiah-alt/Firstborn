class_name EarthGen
extends RefCounted
## The "Earth" game mode: today's continents, seas, big lakes, mountain ranges, deserts,
## rainforests and great rivers, squeezed onto the game map (80N to 56S, all longitudes).
## Data comes from data/earth.png and data/earth.json (made by tools/make_earth.py).
## The same seed and size always make the same world; the seed only changes small details
## (resources, springs, the suggested start).

const LAT_TOP := 80.0
const LAT_SPAN := 136.0


## Map size for a chosen world size: about the same number of tiles as the square world.
static func dims(size: int) -> Vector2i:
	var w := int(round(size * sqrt(360.0 / LAT_SPAN)))
	var h := int(round(float(w) * LAT_SPAN / 360.0))
	return Vector2i(w, h)


static func latlon_to_tile(wm: WorldMap, la: float, lo: float) -> Vector2i:
	return Vector2i(clampi(int((lo + 180.0) / 360.0 * wm.w), 0, wm.w - 1), clampi(int((LAT_TOP - la) / LAT_SPAN * wm.h), 0, wm.h - 1))


static func tile_to_latlon(wm: WorldMap, q: Vector2i) -> Vector2:
	return Vector2(LAT_TOP - (q.y + 0.5) / wm.h * LAT_SPAN, (q.x + 0.5) / wm.w * 360.0 - 180.0)


static func generate(seed_value: int, size: int) -> WorldMap:
	var d := dims(size)
	var wm := WorldMap.new()
	wm.setup(d.x, d.y)
	wm.seed_value = seed_value
	wm.earth = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tex: Texture2D = load("res://data/earth.png")
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var iw := img.get_width()
	var ih := img.get_height()
	var n_detail := WorldGen._noise(seed_value + 53, 0.08, 2)
	var n_t := WorldGen._noise(seed_value + 37, 0.03, 2)
	var n := d.x * d.y
	var raw := PackedFloat32Array()
	raw.resize(n)
	# --- sample the atlas
	for y in d.y:
		for x in d.x:
			var i := y * d.x + x
			var px := img.get_pixel(int((x + 0.5) / d.x * iw), int((y + 0.5) / d.y * ih))
			var r := px.r * 255.0
			raw[i] = r
			wm.moisture[i] = clampf(px.g + n_detail.get_noise_2d(x, y) * 0.06, 0.0, 1.0)
			wm.base_temp[i] = px.b * 255.0 / 4.0 - 30.0 + n_t.get_noise_2d(x, y) * 1.5
			if r >= 100.0:
				var e := (r - 100.0) / 155.0
				wm.elevation[i] = 0.02 + e * 0.98 + n_detail.get_noise_2d(x + 300, y) * 0.03
			else:
				wm.elevation[i] = -0.5 + r / 200.0
	wm.sea_level = 0.0
	wm.hill_level = 0.40
	wm.peak_level = 1.0
	wm.min_level = -0.5
	# --- terrain
	for y in d.y:
		for x in d.x:
			var i := y * d.x + x
			var e := wm.elevation[i]
			var m := wm.moisture[i]
			var t := wm.base_temp[i]
			var ter := Defs.T.PLAINS
			if raw[i] < 100.0:
				ter = Defs.T.DEEP_OCEAN if raw[i] < 40.0 else Defs.T.OCEAN
			elif t < -7.0:
				ter = Defs.T.SNOWY
			elif e >= 0.82:
				ter = Defs.T.PEAK
			elif e >= 0.62:
				ter = Defs.T.MOUNTAIN
			elif e >= 0.40:
				ter = Defs.T.ROCKY if (m < 0.42 or n_detail.get_noise_2d(x, y) > 0.35) else Defs.T.HILLS
				if t < 1.0 and ter == Defs.T.HILLS:
					ter = Defs.T.TUNDRA
				elif t > 11.0 and m < 0.40:
					ter = Defs.T.BADLANDS if n_detail.get_noise_2d(x, y) > 0.0 else Defs.T.HIGH_DESERT
				elif t < 9.0 and t >= 1.0 and m > 0.55:
					ter = Defs.T.ALPINE
			else:
				ter = WorldGen._biome(t, m, e < 0.08)
			wm.terrain[i] = ter
	# --- beaches on warm, low coasts
	for y in range(1, d.y - 1):
		for x in range(1, d.x - 1):
			var i := y * d.x + x
			var ter := wm.terrain[i]
			if Defs.TERRAIN[ter]["water"] or wm.elevation[i] > 0.12 or wm.base_temp[i] < 6.0:
				continue
			for dd in WorldGen.N4:
				var qi := wm.idx(Vector2i(x, y) + dd)
				if wm.terrain[qi] == Defs.T.OCEAN and n_detail.get_noise_2d(x * 3, y * 3) > -0.1:
					wm.terrain[i] = Defs.T.BEACH
					break
	# --- enclosed water bodies (Caspian, Great Lakes, Victoria, Baikal...) are fresh lakes
	var seen := PackedByteArray()
	seen.resize(n)
	for i0 in n:
		if seen[i0] == 1 or not (wm.terrain[i0] == Defs.T.OCEAN or wm.terrain[i0] == Defs.T.DEEP_OCEAN):
			continue
		var comp: Array = [i0]
		seen[i0] = 1
		var k := 0
		while k < comp.size():
			var ci: int = comp[k]
			k += 1
			var cx := ci % d.x
			var cy := ci / d.x
			for dd in WorldGen.N4:
				var nx: int = (cx + dd.x + d.x) % d.x           # the world wraps east-west for seas
				var ny: int = cy + dd.y
				if ny < 0 or ny >= d.y:
					continue
				var ni := ny * d.x + nx
				if seen[ni] == 0 and (wm.terrain[ni] == Defs.T.OCEAN or wm.terrain[ni] == Defs.T.DEEP_OCEAN):
					seen[ni] = 1
					comp.append(ni)
		if comp.size() < n / 120:
			for ci in comp:
				wm.terrain[ci] = Defs.T.LAKE
	# --- the great rivers
	var f := FileAccess.open("res://data/earth.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for name in data["rivers"].keys():
		var pts: Array = data["rivers"][name]
		for k in range(pts.size() - 1):
			var a := latlon_to_tile(wm, float(pts[k][0]), float(pts[k][1]))
			var b := latlon_to_tile(wm, float(pts[k + 1][0]), float(pts[k + 1][1]))
			_river_line(wm, a, b)
	# --- fish
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
	return WorldGen.finish_world(wm, rng, 0.15)


## A 4-connected river channel from a to b (only on land).
static func _river_line(wm: WorldMap, a: Vector2i, b: Vector2i) -> void:
	var p := a
	var guard := 0
	while p != b and guard < 4000:
		guard += 1
		_set_river(wm, p)
		var dx := b.x - p.x
		var dy := b.y - p.y
		if absi(dx) >= absi(dy):
			p.x += signi(dx)
		else:
			p.y += signi(dy)
	_set_river(wm, b)


static func _set_river(wm: WorldMap, q: Vector2i) -> void:
	if not wm.inb(q):
		return
	var i := wm.idx(q)
	var ter := wm.terrain[i]
	if ter == Defs.T.OCEAN or ter == Defs.T.DEEP_OCEAN or ter == Defs.T.LAKE or ter == Defs.T.PEAK:
		return
	wm.terrain[i] = Defs.T.RIVER
