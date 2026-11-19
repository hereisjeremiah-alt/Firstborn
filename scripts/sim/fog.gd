class_name Fog
extends RefCounted
## Fog of war (an option in world creation). The map starts black except around your camp;
## your Billies uncover the land around them as they go, and your buildings keep their
## surroundings uncovered. Explored land stays visible.
## The fog is a 1-pixel-per-tile image drawn over the world, the minimap and the world map.

const PEOPLE_R := 9
const BUILDING_R := 11
const START_R := 16

var on := false
var explored := PackedByteArray()
var image: Image
var texture: ImageTexture
var w := 0
var h := 0
var _dirty := false
var _acc := 0.0


func setup(world: WorldMap, enabled: bool) -> void:
	on = enabled
	w = world.w
	h = world.h
	explored.resize(w * h)
	explored.fill(0 if enabled else 1)
	_make_image()


func _make_image() -> void:
	image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.02, 0.02, 0.03, 1.0))
	if not on:
		image.fill(Color(0, 0, 0, 0))
	else:
		for i in explored.size():
			if explored[i] == 1:
				image.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	texture = ImageTexture.create_from_image(image)


func is_explored(t: Vector2i) -> bool:
	if not on:
		return true
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return false
	return explored[t.y * w + t.x] == 1


func reveal(c: Vector2i, r: int) -> void:
	if not on:
		return
	var r2 := r * r
	for y in range(maxi(0, c.y - r), mini(h, c.y + r + 1)):
		var dy := y - c.y
		for x in range(maxi(0, c.x - r), mini(w, c.x + r + 1)):
			var dx := x - c.x
			if dx * dx + dy * dy > r2:
				continue
			var i := y * w + x
			if explored[i] == 0:
				explored[i] = 1
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				_dirty = true


## Called every frame: uncovers land around the player's people and buildings a few times a second.
func update(sim: Sim, dt: float) -> void:
	if not on or not sim.started:
		return
	_acc += dt
	if _acc >= 0.4:
		_acc = 0.0
		var c := sim.colony
		for p in c.people:
			if p.alive and not p.at_sea():
				reveal(sim.world.tile_of(p.pos), PEOPLE_R)
		for sh in sim.ships:
			if sh.civ_id == 0:
				reveal(sim.world.tile_of(sh.pos), PEOPLE_R + 2)
	if _dirty:
		_dirty = false
		texture.update(image)


func reveal_buildings(sim: Sim) -> void:
	for b in sim.colony.buildings:
		reveal(b.center_tile(), BUILDING_R)


func to_save() -> Dictionary:
	return {"on": on, "explored": explored.compress(FileAccess.COMPRESSION_ZSTD), "size": explored.size()}


func from_save(world: WorldMap, d: Dictionary) -> void:
	w = world.w
	h = world.h
	on = bool(d.get("on", false))
	if on and d.has("explored"):
		explored = (d["explored"] as PackedByteArray).decompress(int(d["size"]), FileAccess.COMPRESSION_ZSTD)
	else:
		explored.resize(w * h)
		explored.fill(0 if on else 1)
	_make_image()
