class_name ResourceLayer
extends Node2D
## Trees, bushes, rocks, ores… drawn in 16x16-tile chunks. Only a changed chunk is redrawn,
## and Godot culls chunks that are off screen.

const CHUNK := 16

var world: WorldMap
var season := 0
var chunks := {}


class Chunk extends Node2D:
	var layer: ResourceLayer
	var origin := Vector2i.ZERO

	func _draw() -> void:
		layer.draw_chunk(self, origin)


const SPRITE_SCALE := 0.75   # resources are drawn a bit smaller than a tile so the map reads cleanly


func build(wm: WorldMap) -> void:
	world = wm
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for c in get_children():
		c.queue_free()
	chunks.clear()
	var cw := ceili(float(wm.w) / CHUNK)
	var ch := ceili(float(wm.h) / CHUNK)
	for cy in ch:
		for cx in cw:
			var c := Chunk.new()
			c.layer = self
			c.origin = Vector2i(cx * CHUNK, cy * CHUNK)
			add_child(c)
			chunks[Vector2i(cx, cy)] = c


func draw_chunk(c: Node2D, origin: Vector2i) -> void:
	var T := Defs.TILE
	for y in range(origin.y, mini(origin.y + CHUNK, world.h)):
		for x in range(origin.x, mini(origin.x + CHUNK, world.w)):
			var i := y * world.w + x
			var r := world.res_type[i]
			if r == 0:
				continue
			if r in Defs.TREES:
				_draw_tree(c, r, i, x, y)
				continue
			var tex := _tex_for(r, world.res_amount[i], i)
			if tex == null:
				continue
			var sz := Vector2(tex.get_width(), tex.get_height()) * SPRITE_SCALE
			# stand on the bottom-centre of the tile
			var pos := Vector2(x * T + (T - sz.x) * 0.5, y * T + T - sz.y - 1.0)
			c.draw_texture_rect(tex, Rect2(pos, sz), false)


## Trees are drawn from above as overlapping crowns of varied size, so woods read as real forest.
func _draw_tree(c: Node2D, r: int, i: int, x: int, y: int) -> void:
	var h := (x * 73856093) ^ (y * 19349663)
	h = absi(h)
	var kind := "oak"
	match r:
		Defs.R.TREE:
			kind = "oak_bare" if season == 3 else ("oak_fall" if season == 2 else "oak")
		Defs.R.PINE:
			kind = "pine_snow" if world.snowy[i] == 1 else "pine"
		Defs.R.SNOW_PINE:
			kind = "pine_snow"
		Defs.R.PALM:
			kind = "palm"
		Defs.R.JUNGLE_TREE:
			kind = "jungle"
		Defs.R.ACACIA:
			kind = "acacia"
		Defs.R.JUNIPER:
			kind = "juniper"
	var variants: Array = Art.trees[kind]
	var tex: Texture2D = variants[h % variants.size()]
	var s := 0.85 + float((h / 7) % 100) / 100.0 * 0.45
	var sz := Vector2(tex.get_width(), tex.get_height()) * s
	var jitter := Vector2(float((h / 13) % 7) - 3.0, float((h / 101) % 7) - 3.0)
	var center := Vector2((x + 0.5) * Defs.TILE, (y + 0.5) * Defs.TILE) + jitter
	c.draw_texture_rect(tex, Rect2(center - sz * 0.5, sz), false)


func _tex_for(r: int, amount: int, i: int) -> Texture2D:
	var snowy := world.snowy[i] == 1
	match r:
		Defs.R.TREE:
			if season == 3:
				return Art.res_tex["tree_bare"]
			if season == 2:
				return Art.res_tex["tree_fall"]
		Defs.R.PINE:
			if snowy:
				return Art.res_tex["pine_snow"]
		Defs.R.BERRY_BUSH:
			if amount <= 0:
				return Art.res_tex["bush_empty"]
		Defs.R.FRUIT_BUSH:
			if amount <= 0:
				return Art.res_tex["fruit_empty"]
		Defs.R.MUSHROOM, Defs.R.GRASS, Defs.R.STICKS, Defs.R.CACTUS, Defs.R.SHRUB, Defs.R.REEDS:
			if amount <= 0:
				return null
	return Art.res_tex.get(r, null)


func tile_changed(t: Vector2i) -> void:
	var key := Vector2i(t.x / CHUNK, t.y / CHUNK)
	if chunks.has(key):
		chunks[key].queue_redraw()


func set_season(s: int) -> void:
	season = s
	redraw_all()


func redraw_all() -> void:
	for c in chunks.values():
		c.queue_redraw()
