class_name Pathfinder
extends RefCounted
## Grid pathfinding on top of Godot's native AStarGrid2D (C++), weighted by terrain cost.

var astar := AStarGrid2D.new()
var world: WorldMap


func setup(wm: WorldMap) -> void:
	world = wm
	astar.region = Rect2i(0, 0, wm.w, wm.h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in wm.h:
		for x in wm.w:
			refresh_tile(Vector2i(x, y))


func refresh_tile(p: Vector2i) -> void:
	if not world.inb(p):
		return
	var c := world.cost_at(p)
	if c <= 0.0 or world.wall[world.idx(p)] == 1:
		astar.set_point_solid(p, true)
	else:
		astar.set_point_solid(p, false)
		astar.set_point_weight_scale(p, c)


## Returns an Array of Vector2i tiles from `from` (excluded) to `to` (included). Empty if unreachable.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if not world.inb(from) or not world.inb(to):
		return []
	var start := from
	if astar.is_point_solid(start):
		start = open_near(from, 4)
		if start.x < 0:
			return []
	var goal := to
	if astar.is_point_solid(goal):
		goal = open_near(to, 3)
		if goal.x < 0:
			return []
	if start == goal:
		return [goal]
	if start != from:
		# standing on something solid (a wall just finished around you): step off it first
		var rest := find_path(start, goal)
		rest.push_front(start)
		return rest
	var pts := astar.get_id_path(start, goal, true)
	if pts.is_empty():
		return []
	var out: Array = []
	for k in range(1, pts.size()):
		out.append(pts[k])
	# a partial path that never leaves the start means the goal is unreachable (other shore,
	# island): never fall back to walking a straight line across water
	return out


## Nearest tile people can stand on (not water, not a wall), searching outward in rings.
func open_near(t: Vector2i, max_r: int) -> Vector2i:
	for r in range(0, max_r + 1):
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if absi(ox) != r and absi(oy) != r:
					continue
				var q := t + Vector2i(ox, oy)
				if world.inb(q) and not astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)
