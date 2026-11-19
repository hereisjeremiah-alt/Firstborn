class_name TerrainView
extends Sprite2D
## The ground. One texel per tile, scaled up and blended by terrain.gdshader, so biomes flow
## into each other, mountains read as shaded relief and coastlines are clean — even when zoomed out.

const SNOWABLE := [Defs.T.PLAINS, Defs.T.GRASSLAND, Defs.T.FOREST, Defs.T.DENSE_FOREST, Defs.T.HILLS,
	Defs.T.ROCKY, Defs.T.VALLEY, Defs.T.BEACH, Defs.T.MOUNTAIN, Defs.T.STEPPE, Defs.T.ALPINE, Defs.T.HIGH_DESERT, Defs.T.SWAMP]

# Softer, map-like palette (separate from Defs colours so gameplay data stays untouched).
const PALETTE := {
	Defs.T.DEEP_OCEAN: Color(0.13, 0.25, 0.42), Defs.T.OCEAN: Color(0.20, 0.38, 0.58),
	Defs.T.BEACH: Color(0.86, 0.80, 0.60), Defs.T.PLAINS: Color(0.64, 0.70, 0.42),
	Defs.T.GRASSLAND: Color(0.47, 0.64, 0.34), Defs.T.FOREST: Color(0.32, 0.52, 0.28),
	Defs.T.DENSE_FOREST: Color(0.24, 0.42, 0.24), Defs.T.SNOW_FOREST: Color(0.78, 0.83, 0.82),
	Defs.T.TUNDRA: Color(0.74, 0.77, 0.70), Defs.T.RAINFOREST: Color(0.20, 0.44, 0.26),
	Defs.T.HILLS: Color(0.56, 0.60, 0.40), Defs.T.ROCKY: Color(0.58, 0.56, 0.50),
	Defs.T.MOUNTAIN: Color(0.52, 0.50, 0.47), Defs.T.PEAK: Color(0.92, 0.93, 0.95),
	Defs.T.LAKE: Color(0.27, 0.50, 0.66), Defs.T.RIVER: Color(0.30, 0.55, 0.72),
	Defs.T.VALLEY: Color(0.42, 0.62, 0.32), Defs.T.SPRING: Color(0.40, 0.68, 0.80),
	Defs.T.SNOWY: Color(0.90, 0.92, 0.94),
	Defs.T.DESERT: Color(0.88, 0.76, 0.50), Defs.T.HIGH_DESERT: Color(0.72, 0.65, 0.48),
	Defs.T.SAVANNA: Color(0.74, 0.70, 0.40), Defs.T.STEPPE: Color(0.64, 0.66, 0.45),
	Defs.T.SWAMP: Color(0.30, 0.40, 0.28), Defs.T.BADLANDS: Color(0.68, 0.43, 0.30),
	Defs.T.ALPINE: Color(0.50, 0.64, 0.42),
}

var world: WorldMap
var _color_img: Image
var _color_tex: ImageTexture


func build(wm: WorldMap) -> void:
	world = wm
	centered = false
	scale = Vector2(Defs.TILE, Defs.TILE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_color_img = make_color_image(wm, false)
	_color_tex = ImageTexture.create_from_image(_color_img)
	texture = _color_tex
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/render/terrain.gdshader")
	mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(_height_image(wm)))
	mat.set_shader_parameter("map_size", Vector2(wm.w, wm.h))
	mat.set_shader_parameter("sub", 4.0)
	material = mat


## Picks how many terrain pixels each tile is split into, so a pixel stays ~2+ screen pixels.
func set_zoom(z: float) -> void:
	var px := float(Defs.TILE) * z / 2.2
	var s := 1.0
	while s * 2.0 <= px and s < 8.0:
		s *= 2.0
	if material and absf(float(material.get_shader_parameter("sub")) - s) > 0.1:
		material.set_shader_parameter("sub", s)


func refresh_colors() -> void:
	_color_img = make_color_image(world, false)
	_color_tex.update(_color_img)


## Colour image (one pixel per tile). With `shaded` the hill shading is baked in (for minimaps).
static func make_color_image(wm: WorldMap, shaded: bool) -> Image:
	var img := Image.create_empty(wm.w, wm.h, false, Image.FORMAT_RGB8)
	var land_span := maxf(0.001, wm.peak_level - wm.sea_level)
	var sea_span := maxf(0.001, wm.sea_level - wm.min_level)
	for y in wm.h:
		for x in wm.w:
			var i := y * wm.w + x
			var t := int(wm.terrain[i])
			var e := wm.elevation[i]
			var c: Color = PALETTE.get(t, Defs.TERRAIN[t]["color"])
			if wm.snowy[i] == 1:
				c = PALETTE[Defs.T.PEAK] if t == Defs.T.MOUNTAIN else PALETTE[Defs.T.SNOWY]
			elif t == Defs.T.OCEAN or t == Defs.T.DEEP_OCEAN:
				# deeper water is darker
				var depth := clampf((wm.sea_level - e) / sea_span, 0.0, 1.0)
				c = PALETTE[Defs.T.OCEAN].lerp(Color(0.10, 0.20, 0.36), depth)
			elif t == Defs.T.MOUNTAIN or t == Defs.T.HILLS or t == Defs.T.ROCKY:
				# higher ground gets lighter and greyer toward the snowline
				var hgt := clampf((e - wm.sea_level) / land_span, 0.0, 1.0)
				c = c.lerp(Color(0.70, 0.69, 0.68), clampf((hgt - 0.6) * 1.2, 0.0, 0.6))
			var r := wm.res_type[i]
			if r in Defs.TREES:
				c = c.darkened(0.16)       # forests read as darker patches from above
			if shaded:
				var e2 := wm.elevation[mini(i + wm.w + 1, wm.w * wm.h - 1)]
				if not Defs.TERRAIN[t]["water"]:
					var k := clampf((e - e2) * 4.0, -0.18, 0.18)
					c = c.lightened(k) if k > 0.0 else c.darkened(-k)
			img.set_pixel(x, y, c)
	return img


static func _height_image(wm: WorldMap) -> Image:
	var img := Image.create_empty(wm.w, wm.h, false, Image.FORMAT_RGF)
	var span := maxf(0.001, wm.peak_level - wm.sea_level)
	for y in wm.h:
		for x in wm.w:
			var i := y * wm.w + x
			var water := 1.0 if Defs.TERRAIN[wm.terrain[i]]["water"] else 0.0
			# lakes and rivers keep their ground height so their shores don't look like cliffs
			var hgt := clampf((wm.elevation[i] - wm.sea_level) / span, 0.0, 1.0)
			img.set_pixel(x, y, Color(hgt, water, 0.0))
	return img


static func _grain_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var img := Image.create_empty(64, 64, false, Image.FORMAT_L8)
	for y in 64:
		for x in 64:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## Covers cold-region ground with snow in winter and melts it in spring.
## Returns the tiles that changed so pathfinding can be refreshed.
func apply_snow(sim: Sim) -> Array:
	var changed: Array = []
	var winter := sim.time.season() == 3
	for y in world.h:
		for x in world.w:
			var i := y * world.w + x
			var want := 0
			if winter and SNOWABLE.has(int(world.terrain[i])) and sim.is_cold_season_tile(i):
				want = 1
			if world.snowy[i] != want:
				world.snowy[i] = want
				changed.append(Vector2i(x, y))
	if not changed.is_empty() and _color_tex != null:
		refresh_colors()
	return changed
