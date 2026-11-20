class_name EntityLayer
extends Node2D
## Draws buildings, animals, people, selection and the build ghost every frame (only what is on screen).

var game: Node   # game.gd (untyped to avoid a cyclic dependency)
var font: Font

const SKIN := [Color(0.96, 0.80, 0.64), Color(0.86, 0.66, 0.48), Color(0.72, 0.52, 0.36), Color(0.55, 0.38, 0.25), Color(0.42, 0.28, 0.18)]
const HAIR := [Color(0.12, 0.08, 0.05), Color(0.30, 0.18, 0.08), Color(0.52, 0.32, 0.14), Color(0.20, 0.14, 0.10)]
const HIDE := Color(0.55, 0.40, 0.25)


var bold: FontVariation


func _ready() -> void:
	font = ThemeDB.fallback_font
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.6


## Text drawn at its real on-screen pixel size, so it stays sharp at any zoom.
## `at` is in world space (centre of the baseline); `px` is the size on screen.
func crisp_text(at: Vector2, text: String, px: float, col: Color, outline := 3, outline_col := Color(0, 0, 0, 0.85)) -> void:
	var z: float = maxf(0.01, game.camera.zoom.x)
	var fs := maxi(6, roundi(px))
	var w := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(at, 0.0, Vector2(1.0 / z, 1.0 / z))
	var o := Vector2(roundf(-w * 0.5), 0.0)
	if outline > 0:
		draw_string_outline(bold, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, outline_col)
	draw_string(bold, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_process_inner(_delta)
	PerfLog.add("p_entity", (Time.get_ticks_usec() - _pt) / 1000.0)


func _process_inner(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var _t0 := Time.get_ticks_usec()
	_draw_all()
	if not game.perf.is_empty():
		game.perf["draw_ms"] = float(game.perf["draw_ms"]) + (Time.get_ticks_usec() - _t0) / 1000.0


func _draw_all() -> void:
	var sim: Sim = game.sim
	var view: Rect2 = game.view_rect.grow(48.0)
	var zoom: float = game.camera.zoom.x
	if game.picking:
		_draw_picker(sim)
		return
	# territory: the borders of every claimed state, in its owner's colour
	var sm: StateMap = sim.states
	var lw := 2.5 / maxf(0.35, zoom)
	for st in sm.count():
		var ow := int(sm.owners[st])
		if (ow < 0 and st != game.selected_state) or not view.intersects(sm.bboxes[st]):
			continue
		var col: Color = sim.civ(ow).color if ow >= 0 else Color(1, 1, 1)
		if st == game.selected_state:
			draw_multiline(sm.borders[st], Color(1, 1, 1, 0.9), lw * 1.8)
		draw_multiline(sm.borders[st], Color(col, 0.75), lw)
	_draw_town_plan(sim, view, zoom)
	# buildings
	for c in sim.colonies:
		for b in c.buildings:
			if view.has_point(b.center()):
				_draw_building(sim, b)
	for sh in sim.ships:
		if view.has_point(sh.pos):
			_draw_ship(sim, sh, zoom)
	# fully zoomed out: people and animals are not drawn at all, only their icons (much faster);
	# at high game speed they aren't drawn at all, to keep the frame rate up
	var fast: bool = game.speed >= Settings.derender_speed and not game.paused
	var detail := zoom >= 0.55 and not fast
	sim.fx_on = detail
	if not detail and not sim.fx.is_empty():
		sim.fx.clear()
	if detail:
		_draw_stains(sim, view)
		for a in sim.animals:
			if not a.alive and view.has_point(a.pos):
				_draw_animal(a)
		for a in sim.animals:
			if a.alive and not a.def().get("flying", false) and view.has_point(a.pos):
				_draw_animal(a)
		var sleepers := {}
		for p in sim.people_all:
			if p.alive and not p.at_sea() and view.has_point(p.pos):
				var inside := sim.indoors(p)
				if inside != null and not (game.selected_ids.has(p.id) or p.id == game.selected_human_id):
					sleepers[inside] = int(sleepers.get(inside, 0)) + 1     # asleep inside: hidden
					continue
				_draw_human(p, game.selected_ids.has(p.id) or p.id == game.selected_human_id, zoom, sim.col_of(p).color)
		# a few drifting z's over every home with people asleep inside
		for hb in sleepers.keys():
			var top: Vector2 = Vector2(hb.tile) * Defs.TILE + Vector2(hb.size().x * Defs.TILE * 0.7, -2.0)
			for k in mini(3, int(sleepers[hb])):
				var zt := fmod(Time.get_ticks_msec() / 1000.0 + k * 0.7, 2.0)
				draw_string(font, top + Vector2(k * 4.0, -zt * 5.0 - k * 3.0), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 9 + k, Color(1, 1, 1, 1.0 - zt * 0.45))
		for a in sim.animals:
			if a.alive and a.def().get("flying", false) and view.has_point(a.pos):
				_draw_animal(a)
	# land marked for clearing, and the box being dragged
	for i in sim.colony.clear_marks.keys():
		var q := Vector2i(int(i) % sim.world.w, int(i) / sim.world.w)
		var tp := Vector2(q) * Defs.TILE
		if view.has_point(tp):
			draw_rect(Rect2(tp + Vector2(2, 2), Vector2(12, 12)), Color(1.0, 0.55, 0.15, 0.9), false, 1.0)
			draw_line(tp + Vector2(5, 5), tp + Vector2(11, 11), Color(1.0, 0.55, 0.15, 0.9), 1.0)
			draw_line(tp + Vector2(11, 5), tp + Vector2(5, 11), Color(1.0, 0.55, 0.15, 0.9), 1.0)
	if game.clear_dragging and game.tool_mode == "clear":
		var cr: Rect2 = game.clear_rect()
		draw_rect(cr, Color(1.0, 0.6, 0.2, 0.15))
		draw_rect(cr, Color(1.0, 0.6, 0.2, 0.9), false, 2.0 / maxf(0.5, zoom))
	# arrows and sling stones in flight
	for sh in sim.tower_shots:
		var a0: Vector2 = sh[0]
		var a1: Vector2 = sh[1]
		var total := float(sh[4]) if sh.size() > 4 else 0.25
		var ammo := str(sh[3]) if sh.size() > 3 else "arrow"
		var ph := clampf(1.0 - float(sh[2]) / total, 0.0, 1.0)
		var at := a0.lerp(a1, ph)
		var dir := (a1 - a0).normalized()
		if ammo == "boulder":
			at.y -= sin(ph * PI) * a0.distance_to(a1) * 0.35       # a high arc
			draw_circle(at + Vector2(1, 1), 3.2, Color(0, 0, 0, 0.3))
			draw_circle(at, 3.0, Color(0.52, 0.50, 0.46))
			draw_circle(at - Vector2(0.8, 0.8), 1.4, Color(0.68, 0.66, 0.62))
		elif ammo == "rock":
			at.y -= sin(ph * PI) * 6.0
			draw_circle(at, 1.4, Color(0.45, 0.43, 0.40))
		else:
			draw_line(at - dir * 5.0, at, Color(0.25, 0.18, 0.1), 1.2)
	if detail:
		_draw_fx(sim, view, zoom)
	_draw_selection(sim)
	_draw_ghost(sim)
	_draw_markers(sim, view, zoom, fast)
	_draw_orders(zoom)


# ------------------------------------------------------------------ war structures
func _war_structure(sim: Sim, b: Building, o: Vector2, s: Vector2, m: Color) -> void:
	var tribe: Color = sim.civ(b.civ_id).color
	var wood := Color(0.50, 0.34, 0.18) * m
	var dark := Color(0.32, 0.21, 0.11) * m
	var stone := Color(0.62, 0.60, 0.56) * m
	var tsec := Time.get_ticks_msec() / 1000.0
	var c := o + s * 0.5
	match b.type:
		"lookout_perch":
			# four poles, a small platform and a pile of throwing rocks
			for pt in [Vector2(3, 3), Vector2(13, 3), Vector2(3, 13), Vector2(13, 13)]:
				draw_line(o + pt + Vector2(0, 2), o + pt - Vector2(0, 2), dark, 1.6)
			draw_rect(Rect2(o + Vector2(2, 2), Vector2(12, 9)), wood)
			for k in 3:
				draw_line(o + Vector2(2, 4 + k * 3), o + Vector2(14, 4 + k * 3), dark, 0.7)
			_pile(o + Vector2(8, 13), 3.0, Color(0.55, 0.54, 0.50) * m)
			draw_circle(o + Vector2(8, 5), 1.6, tribe * m)
		"sling_platform":
			# raised stone platform with a parapet
			draw_rect(Rect2(o + Vector2(1, 1), Vector2(14, 14)), stone.darkened(0.2))
			draw_rect(Rect2(o + Vector2(2, 2), Vector2(12, 12)), stone)
			for k in 4:
				draw_rect(Rect2(o + Vector2(2 + k * 3.6, 1), Vector2(2, 2)), stone.lightened(0.15))
			draw_rect(Rect2(o + Vector2(5, 5), Vector2(6, 6)), Color(0.42, 0.34, 0.24) * m)
			draw_circle(o + Vector2(8, 8), 1.5, tribe * m)
			var sw := tsec * 6.0 + b.id
			draw_line(o + Vector2(8, 8), o + Vector2(8, 8) + Vector2(cos(sw), sin(sw)) * 4.0, Color(0.6, 0.5, 0.35) * m, 0.8)
		"bastion":
			# squat bronze-capped strong point with four corner turrets
			var r := Rect2(o + Vector2(2, 2), s - Vector2(4, 4))
			draw_rect(r, stone.darkened(0.15))
			draw_rect(r.grow(-2), stone)
			for pt in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
				draw_circle(pt, 4.0, stone.darkened(0.3))
				draw_circle(pt, 3.0, Color(0.80, 0.55, 0.25) * m)      # bronze caps
			draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(0.45, 0.36, 0.26) * m)
			draw_circle(c, 1.8, tribe * m)
		"ballista_tower":
			# round stone tower with a great crossbow on top
			draw_circle(c + Vector2(1, 1), 13.5, Color(0, 0, 0, 0.25 * m.a))
			draw_circle(c, 13.0, stone.darkened(0.25))
			draw_circle(c, 11.5, stone)
			for k in 10:
				var ang := k * TAU / 10.0
				draw_rect(Rect2(c + Vector2(cos(ang), sin(ang)) * 10.5 - Vector2(1.5, 1.5), Vector2(3, 3)), stone.lightened(0.15))
			draw_circle(c, 7.0, Color(0.40, 0.32, 0.22) * m)
			var aim := tsec * 0.4 + b.id
			var dv := Vector2(cos(aim), sin(aim))
			draw_line(c - dv * 5.0, c + dv * 6.0, dark, 2.2)                          # stock
			draw_line(c + dv * 3.0 + dv.orthogonal() * 6.0, c + dv * 3.0 - dv.orthogonal() * 6.0, Color(0.35, 0.35, 0.38) * m, 1.8)   # iron bow
			draw_circle(c, 1.4, tribe * m)
		"war_drum_circle":
			draw_circle(c, s.x * 0.45, Color(0.55, 0.45, 0.30, 0.5 * m.a))
			for k in 4:
				var ang := k * TAU / 4.0 + 0.4
				var dp := c + Vector2(cos(ang), sin(ang)) * 8.5
				draw_circle(dp + Vector2(1, 1), 4.0, Color(0, 0, 0, 0.25 * m.a))
				draw_circle(dp, 4.0, Color(0.48, 0.30, 0.16) * m)
				var beat := 0.5 + 0.5 * sin(tsec * 8.0 + k * 1.7)
				draw_circle(dp, 3.0, Color(0.88, 0.80, 0.62).lerp(Color(1, 0.95, 0.85), beat * 0.4) * m)   # hide skin
			draw_circle(c, 3.0, Color(0.30, 0.28, 0.26) * m)                    # fire pit
			draw_circle(c, 1.8, Color(1.0, 0.55, 0.15, (0.6 + 0.4 * sin(tsec * 9.0)) * m.a))
			if b.built:
				draw_line(c + Vector2(9, -12), c + Vector2(9, 2), dark, 1.2)
				draw_colored_polygon(PackedVector2Array([c + Vector2(9, -12), c + Vector2(16, -10), c + Vector2(9, -8)]), tribe * m)
		"ram_shed":
			_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, s.y - 12)), Color(0.42, 0.30, 0.18) * m, 1, m)
			# the ram: a big log on wheels with an iron-capped head
			var ry := o.y + s.y - 7
			draw_rect(Rect2(Vector2(o.x + 6, ry - 2), Vector2(s.x - 14, 4)), Color(0.55, 0.38, 0.20) * m)
			draw_circle(Vector2(o.x + s.x - 8, ry), 2.6, Color(0.40, 0.40, 0.42) * m)
			for wx in [o.x + 10, o.x + s.x - 16]:
				draw_circle(Vector2(wx, ry + 3), 2.6, dark)
				draw_circle(Vector2(wx, ry + 3), 1.0, wood)
		"catapult":
			var base := Rect2(o + Vector2(4, 8), Vector2(s.x - 8, s.y - 14))
			draw_rect(base, wood)
			draw_rect(base, dark, false, 1.0)
			for wx in [base.position.x + 1, base.end.x - 1]:
				for wy in [base.position.y, base.end.y]:
					draw_circle(Vector2(wx, wy), 2.6, dark)
			var arm := -0.9 + 0.25 * sin(tsec * 0.8 + b.id)
			var piv := c + Vector2(0, 1)
			var tip := piv + Vector2(cos(arm - PI * 0.5), sin(arm - PI * 0.5)) * 12.0
			draw_line(piv, tip, Color(0.45, 0.30, 0.16) * m, 2.0)
			draw_circle(tip, 2.4, Color(0.40, 0.30, 0.20) * m)                  # bucket
			draw_circle(tip, 1.4, Color(0.62, 0.60, 0.56) * m)                  # boulder
			_pile(o + Vector2(s.x - 6, s.y - 5), 3.0, Color(0.55, 0.54, 0.50) * m)
		"trebuchet":
			# tall A-frame, long throwing arm and a counterweight box
			var fy := o.y + s.y - 6
			draw_line(Vector2(o.x + 8, fy), Vector2(c.x, o.y + 10), dark, 2.2)
			draw_line(Vector2(o.x + s.x - 8, fy), Vector2(c.x, o.y + 10), dark, 2.2)
			draw_line(Vector2(o.x + 5, fy), Vector2(o.x + s.x - 5, fy), wood, 2.4)
			var arm2 := 0.6 + 0.15 * sin(tsec * 0.5 + b.id)
			var pv := Vector2(c.x, o.y + 10)
			var adir := Vector2(cos(arm2 + PI), sin(arm2 + PI))
			draw_line(pv - adir * 9.0, pv + adir * 20.0, Color(0.50, 0.34, 0.18) * m, 2.0)
			var cw := pv - adir * 9.0
			draw_rect(Rect2(cw - Vector2(4, 1), Vector2(8, 7)), Color(0.38, 0.30, 0.22) * m)   # counterweight
			draw_line(pv + adir * 20.0, pv + adir * 20.0 + Vector2(0, 7), Color(0.75, 0.70, 0.55) * m, 0.8)  # sling rope
			draw_circle(pv + adir * 20.0 + Vector2(0, 8), 2.0, Color(0.62, 0.60, 0.56) * m)
			draw_circle(pv, 1.6, Color(0.35, 0.35, 0.38) * m)


# ------------------------------------------------------------------ weaponsmithing bench
func _smithing_bench(b: Building, o: Vector2, s: Vector2, m: Color) -> void:
	var wood := Color(0.55, 0.38, 0.20) * m
	var dark := Color(0.34, 0.22, 0.11) * m
	# a lean-to roof over the back, a heavy work bench with an anvil stone and tools
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, 9)), Color(0.52, 0.44, 0.30) * m)
	for k in 6:
		draw_line(o + Vector2(2 + k * (s.x - 4) / 5.0, 1), o + Vector2(2 + k * (s.x - 4) / 5.0, 10), dark, 0.8)
	draw_rect(Rect2(o + Vector2(3, 13), Vector2(s.x - 6, 9)), wood)
	draw_rect(Rect2(o + Vector2(3, 13), Vector2(s.x - 6, 9)), dark, false, 1.0)
	for lx in [5.0, s.x - 6.0]:
		draw_line(o + Vector2(lx, 22), o + Vector2(lx, 28), dark, 1.6)
	draw_circle(o + Vector2(s.x * 0.68, 17.5), 3.2, Color(0.45, 0.45, 0.48) * m)    # anvil stone
	draw_line(o + Vector2(8, 16), o + Vector2(14, 19), Color(0.45, 0.30, 0.18) * m, 1.4)   # hammer handle
	draw_rect(Rect2(o + Vector2(13, 17.5), Vector2(3, 3)), Color(0.40, 0.40, 0.44) * m)
	# finished blades hanging on the back wall
	for k in 3:
		var bx := o.x + 6 + k * 7
		draw_line(Vector2(bx, o.y + 3), Vector2(bx, o.y + 9), Color(0.70, 0.72, 0.78) * m, 1.4)
		draw_line(Vector2(bx - 1.5, o.y + 7), Vector2(bx + 1.5, o.y + 7), dark, 1.0)
	draw_circle(o + Vector2(s.x - 5, s.y - 4), 2.4, Color(0.35, 0.33, 0.30) * m)   # quench bucket
	draw_circle(o + Vector2(s.x - 5, s.y - 4), 1.6, Color(0.30, 0.45, 0.60) * m)


# ------------------------------------------------------------------ bonus buildings
func _bonus_structure(sim: Sim, b: Building, o: Vector2, s: Vector2, m: Color, era: int, roof: Color) -> void:
	var tsec := Time.get_ticks_msec() / 1000.0
	var c := o + s * 0.5
	var wood := Color(0.50, 0.34, 0.18) * m
	var dark := Color(0.32, 0.21, 0.11) * m
	var stone := Color(0.64, 0.62, 0.58) * m
	match b.type:
		"shaman_circle":
			# a ring of painted posts around a smoking herb fire, hides and skulls
			draw_circle(c, s.x * 0.46, Color(0.52, 0.44, 0.30, 0.55 * m.a))
			for k in 8:
				var a := k * TAU / 8.0
				var pp := c + Vector2(cos(a), sin(a)) * s.x * 0.38
				draw_circle(pp + Vector2(1, 1), 2.4, Color(0, 0, 0, 0.3 * m.a))
				draw_circle(pp, 2.2, wood)
				draw_circle(pp, 1.0, (Color(0.85, 0.3, 0.2) if k % 2 == 0 else Color(0.95, 0.9, 0.75)) * m)
			draw_circle(c, 4.5, Color(0.30, 0.28, 0.26) * m)
			draw_circle(c, 2.8, Color(1.0, 0.55, 0.2, (0.6 + 0.4 * sin(tsec * 7.0)) * m.a))
			for k in 3:
				var ph := fmod(tsec * 0.5 + k * 0.33, 1.0)
				draw_circle(c + Vector2(sin(ph * 6.0) * 3.0, -ph * 16.0), 1.5 + ph * 3.0, Color(0.55, 0.75, 0.55, 0.45 * (1.0 - ph) * m.a))   # herb smoke
			draw_rect(Rect2(c + Vector2(-14, 6), Vector2(8, 5)), Color(0.72, 0.58, 0.38) * m)       # hide mat
			draw_circle(c + Vector2(10, -9), 2.0, Color(0.92, 0.9, 0.82) * m)                      # skull
		"great_hearth":
			# a long stone-lined fire pit under a timber smoke roof, with spits
			draw_rect(Rect2(o + Vector2(2, 3), s - Vector2(4, 6)), stone.darkened(0.2))
			draw_rect(Rect2(o + Vector2(4, 5), s - Vector2(8, 10)), Color(0.25, 0.22, 0.20) * m)
			for k in 5:
				var fx := o.x + 8 + k * (s.x - 16) / 4.0
				var fl := 0.6 + 0.4 * sin(tsec * 8.0 + k * 1.3)
				draw_circle(Vector2(fx, c.y), 3.0, Color(1.0, 0.45, 0.12, fl * m.a))
				draw_circle(Vector2(fx, c.y - 1), 1.6, Color(1.0, 0.85, 0.4, fl * m.a))
			draw_line(o + Vector2(4, c.y - o.y - 6), o + Vector2(s.x - 4, c.y - o.y - 6), dark, 1.4)   # spit
			draw_circle(Vector2(c.x - 6, c.y - 6), 2.4, Color(0.6, 0.32, 0.2) * m)
			for pt in [Vector2(2, 2), Vector2(s.x - 3, 2), Vector2(2, s.y - 3), Vector2(s.x - 3, s.y - 3)]:
				draw_circle(o + pt, 1.8, dark)
		"flint_works":
			_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, s.y - 14)), Color(0.55, 0.45, 0.30) * m, era, m)
			# open knapping floor in front: flint nodules, flakes and finished blades on a mat
			var fl2 := Rect2(o + Vector2(3, s.y - 13), Vector2(s.x - 6, 11))
			draw_rect(fl2, Color(0.62, 0.55, 0.42) * m)
			for k in 7:
				draw_circle(fl2.position + Vector2(4 + k * 5.5, 3 + (k % 3) * 2.5), 1.6, Color(0.30, 0.30, 0.34) * m)
			for k in 4:
				var bx := fl2.position + Vector2(8 + k * 8, 8)
				draw_colored_polygon(PackedVector2Array([bx, bx + Vector2(5, -1), bx + Vector2(0, 2)]), Color(0.75, 0.75, 0.80) * m)
		"stone_calendar":
			# a ring of tall stones with a sun-stone in the middle and a sightline
			draw_circle(c, s.x * 0.47, Color(0.50, 0.46, 0.36, 0.45 * m.a))
			for k in 10:
				var a := k * TAU / 10.0
				var sp := c + Vector2(cos(a), sin(a)) * s.x * 0.40
				draw_rect(Rect2(sp - Vector2(2.2, 3.5) + Vector2(1, 1), Vector2(4.4, 7)), Color(0, 0, 0, 0.3 * m.a))
				draw_rect(Rect2(sp - Vector2(2.2, 3.5), Vector2(4.4, 7)), stone)
				draw_rect(Rect2(sp - Vector2(2.2, 3.5), Vector2(1.4, 7)), stone.lightened(0.15))
			draw_circle(c, 4.0, stone.darkened(0.1))
			draw_circle(c, 2.2, Color(0.95, 0.80, 0.35) * m)                 # sun-stone
			var sun := tsec * 0.2
			draw_line(c, c + Vector2(cos(sun), sin(sun)) * s.x * 0.36, Color(0.95, 0.85, 0.5, 0.6 * m.a), 1.0)
		"marketplace":
			# a paved square of colourful stalls
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.74, 0.68, 0.56) * m)
			var cols := [Color(0.80, 0.25, 0.20), Color(0.25, 0.50, 0.80), Color(0.90, 0.75, 0.25), Color(0.35, 0.65, 0.35)]
			for k in 4:
				var st := o + Vector2(4 + (k % 2) * (s.x * 0.5), 4 + (k / 2) * (s.y * 0.5))
				var w := s.x * 0.5 - 8
				for j in int(w / 3.0):
					draw_rect(Rect2(st + Vector2(j * 3, 0), Vector2(3, 6)), ((cols[k] as Color) if j % 2 == 0 else Color(0.95, 0.92, 0.85)) * m)
				for j in 3:
					draw_circle(st + Vector2(4 + j * 5, 10), 1.6, [Color(0.85, 0.3, 0.3), Color(0.9, 0.7, 0.3), Color(0.5, 0.75, 0.35)][j] * m)   # goods
			draw_circle(c, 2.5, Color(0.6, 0.6, 0.62) * m)              # well / scales in the middle
		"bathhouse":
			_hip_roof(Rect2(o + Vector2(1, 1), Vector2(s.x * 0.45, s.y - 2)), roof, m)
			var pool := Rect2(o + Vector2(s.x * 0.5, 3), Vector2(s.x * 0.5 - 3, s.y - 6))
			draw_rect(pool, stone.darkened(0.15))
			draw_rect(pool.grow(-2), Color(0.35, 0.62, 0.78) * m)
			for k in 3:
				var ph := fmod(tsec * 0.4 + k * 0.33, 1.0)
				draw_circle(pool.get_center() + Vector2((k - 1) * 6, -ph * 8.0), 1.5 + ph * 2.5, Color(1, 1, 1, 0.35 * (1.0 - ph) * m.a))   # steam
			for k in 4:
				draw_circle(pool.position + Vector2(2 + k * pool.size.x / 3.5, 1.5), 1.2, stone.lightened(0.2))     # columns
		"academy":
			var base := Rect2(o + Vector2(1, 1), s - Vector2(2, 2))
			draw_rect(base, Color(0.82, 0.79, 0.72) * m)
			draw_rect(base, Color(0.50, 0.47, 0.42) * m, false, 1.0)
			_hip_roof(Rect2(o + Vector2(4, 4), s - Vector2(8, 14)), Color(0.66, 0.30, 0.22) * m, m)
			for k in 6:
				draw_circle(o + Vector2(6 + k * (s.x - 12) / 5.0, s.y - 6), 1.5, Color(0.95, 0.93, 0.88) * m)   # colonnade
			draw_rect(Rect2(c + Vector2(-5, 6), Vector2(10, 4)), Color(0.90, 0.84, 0.66) * m)    # scroll table
			draw_line(c + Vector2(-4, 8), c + Vector2(4, 8), Color(0.3, 0.3, 0.35) * m, 0.6)
		"iron_foundry":
			_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 14, s.y - 4)), Color(0.32, 0.30, 0.30) * m, era, m)
			# a squat bloomery furnace with a glowing mouth and a tall chimney
			var fz := o + Vector2(s.x - 10, s.y * 0.5)
			draw_circle(fz, 6.5, Color(0.42, 0.36, 0.32) * m)
			draw_circle(fz, 4.5, Color(0.30, 0.26, 0.24) * m)
			draw_circle(fz + Vector2(0, 2), 2.4, Color(1.0, 0.45, 0.1, (0.7 + 0.3 * sin(tsec * 10.0)) * m.a))
			for k in 3:
				var ph := fmod(tsec * 0.6 + k * 0.33, 1.0)
				draw_circle(fz + Vector2(ph * 6.0, -6.0 - ph * 12.0), 1.6 + ph * 3.0, Color(0.35, 0.35, 0.38, 0.55 * (1.0 - ph) * m.a))
			for k in 3:
				draw_rect(Rect2(o + Vector2(4 + k * 6, s.y - 6), Vector2(4, 3)), Color(0.45, 0.45, 0.50) * m)   # iron blooms


# ------------------------------------------------------------------ monolith & bandit camp
## A tall rough standing stone of grey granite on a trampled patch, with a few smaller stones
## around it. Carved notches on its face count the years.
func _monolith(o: Vector2, s: Vector2, built: bool, m: Color) -> void:
	var c := o + s * 0.5
	# trampled earth and a ring of small stones
	draw_circle(c + Vector2(0, 3), s.x * 0.45, Color(0.48, 0.42, 0.32, 0.55) * m)
	for k in 6:
		var a := k * TAU / 6.0 + 0.3
		var sp := c + Vector2.from_angle(a) * s.x * 0.38 + Vector2(0, 3)
		draw_circle(sp, 2.3, Color(0.42, 0.41, 0.39) * m)
		draw_circle(sp + Vector2(-0.6, -0.8), 1.2, Color(0.58, 0.57, 0.54) * m)
	# shadow cast to the side
	draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 6), c + Vector2(5, 6), c + Vector2(15, 11), c + Vector2(6, 12)]), Color(0, 0, 0, 0.28 * m.a))
	if not built:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 6), c + Vector2(6, 6), c + Vector2(4, -4), c + Vector2(-5, -3)]), Color(0.50, 0.49, 0.46) * m)
		return
	# the stone: rough, uneven outline, lit from the left
	var base_col := Color(0.52, 0.51, 0.48) * m
	var dark := Color(0.38, 0.37, 0.35) * m
	var light := Color(0.66, 0.65, 0.61) * m
	var outline := PackedVector2Array([c + Vector2(-6, 6), c + Vector2(6, 6), c + Vector2(5.5, -6), c + Vector2(4, -15),
		c + Vector2(2, -20), c + Vector2(-2.5, -21), c + Vector2(-5, -16), c + Vector2(-6.5, -5)])
	draw_colored_polygon(outline, base_col)
	# shaded right side and lit left edge
	draw_colored_polygon(PackedVector2Array([c + Vector2(1.5, 6), c + Vector2(6, 6), c + Vector2(5.5, -6), c + Vector2(4, -15), c + Vector2(2, -20), c + Vector2(1, -12)]), dark)
	draw_line(c + Vector2(-6.5, -5), c + Vector2(-5, -16), light, 1.2)
	draw_line(c + Vector2(-5, -16), c + Vector2(-2.5, -21), light, 1.0)
	# cracks, lichen and carved year notches
	draw_line(c + Vector2(-3, -8), c + Vector2(-1, -4), dark, 0.8)
	draw_line(c + Vector2(-1, -4), c + Vector2(-2, 1), dark, 0.6)
	draw_circle(c + Vector2(-4, 2), 1.3, Color(0.55, 0.60, 0.40, 0.8) * m)
	draw_circle(c + Vector2(3, -10), 1.0, Color(0.55, 0.60, 0.40, 0.7) * m)
	for k in 4:
		var y := -17.0 + k * 3.0
		draw_line(c + Vector2(-3, y), c + Vector2(0.5, y + 0.4), Color(0.30, 0.29, 0.27) * m, 0.8)
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0.25, 0.24, 0.23) * m, 0.8)


## Lumber yard: a stack of logs, a sawhorse with a log on it, a chopping block and bundles of sticks.
func _lumber_yard(o: Vector2, s: Vector2, m: Color) -> void:
	draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.55, 0.45, 0.32, 0.6) * m)
	# sawdust
	for k in 7:
		draw_circle(o + Vector2(10 + (k * 7) % 28, 18 + (k * 5) % 10), 1.4, Color(0.85, 0.72, 0.48, 0.7) * m)
	# log stack (ends facing us)
	var ls := o + Vector2(4, 4)
	for row in 3:
		for k in 4 - row:
			var lc := ls + Vector2(5 + k * 6 + row * 3, 13 - row * 5)
			draw_circle(lc, 3.0, Color(0.42, 0.27, 0.14) * m)
			draw_circle(lc, 2.1, Color(0.80, 0.64, 0.40) * m)
			draw_circle(lc, 0.7, Color(0.62, 0.46, 0.26) * m)
	# sawhorse with a log
	var sh := o + Vector2(s.x - 18, 10)
	draw_line(sh + Vector2(0, 0), sh + Vector2(-3, 9), Color(0.35, 0.24, 0.12) * m, 1.4)
	draw_line(sh + Vector2(0, 0), sh + Vector2(3, 9), Color(0.35, 0.24, 0.12) * m, 1.4)
	draw_line(sh + Vector2(10, 0), sh + Vector2(7, 9), Color(0.35, 0.24, 0.12) * m, 1.4)
	draw_line(sh + Vector2(10, 0), sh + Vector2(13, 9), Color(0.35, 0.24, 0.12) * m, 1.4)
	draw_line(sh + Vector2(-4, -1), sh + Vector2(15, -1), Color(0.46, 0.30, 0.16) * m, 3.6)
	draw_line(sh + Vector2(-4, -2), sh + Vector2(15, -2), Color(0.60, 0.42, 0.24) * m, 1.2)
	# chopping block with an axe
	var cb := o + Vector2(s.x - 10, s.y - 8)
	draw_circle(cb, 3.6, Color(0.45, 0.30, 0.16) * m)
	draw_circle(cb, 2.6, Color(0.76, 0.60, 0.38) * m)
	draw_line(cb + Vector2(-1, 0), cb + Vector2(3, -6), Color(0.45, 0.32, 0.18) * m, 1.2)
	draw_rect(Rect2(cb + Vector2(2, -8), Vector2(3, 2.5)), Color(0.55, 0.55, 0.58) * m)
	# bundles of sticks
	for k in 2:
		var bp := o + Vector2(8 + k * 9, s.y - 6)
		for j in 4:
			draw_line(bp + Vector2(j * 1.2, -2), bp + Vector2(j * 1.2 + 6, -3), Color(0.55, 0.40, 0.22) * m, 0.9)
		draw_line(bp + Vector2(3, -4), bp + Vector2(3, 0), Color(0.75, 0.68, 0.45) * m, 0.8)


## A ragged outlaw camp: two patched tents, a fire, a stash of stolen goods and a black banner.
func _bandit_camp(o: Vector2, s: Vector2, m: Color) -> void:
	var c := o + s * 0.5
	draw_circle(c, s.x * 0.47, Color(0.40, 0.33, 0.24, 0.55) * m)
	for k in 2:
		var tp := o + Vector2(6 + k * (s.x - 20), 6)
		draw_colored_polygon(PackedVector2Array([tp + Vector2(0, 14), tp + Vector2(7, 0), tp + Vector2(14, 14)]), Color(0.45, 0.38, 0.30) * m)
		draw_colored_polygon(PackedVector2Array([tp + Vector2(7, 0), tp + Vector2(14, 14), tp + Vector2(8, 14)]), Color(0.36, 0.30, 0.24) * m)
		draw_rect(Rect2(tp + Vector2(3, 8), Vector2(3, 3)), Color(0.55, 0.35, 0.25) * m)    # patch
	_campfire(c + Vector2(-8, 4), 0, true, m)
	# stash: sacks and a chest
	draw_circle(c + Vector2(10, 10), 3.0, Color(0.70, 0.60, 0.40) * m)
	draw_circle(c + Vector2(14, 11), 2.6, Color(0.65, 0.55, 0.36) * m)
	draw_rect(Rect2(c + Vector2(4, 12), Vector2(6, 4)), Color(0.45, 0.30, 0.15) * m)
	draw_rect(Rect2(c + Vector2(6, 13), Vector2(2, 1)), Color(0.9, 0.75, 0.3) * m)
	# black banner with a white skull mark
	var pole := o + Vector2(s.x - 6, 2)
	draw_line(pole, pole + Vector2(0, 18), Color(0.3, 0.22, 0.12) * m, 1.4)
	draw_rect(Rect2(pole + Vector2(-9, 0), Vector2(9, 6)), Color(0.08, 0.08, 0.08) * m)
	draw_circle(pole + Vector2(-4.5, 2.6), 1.6, Color(0.9, 0.9, 0.85) * m)
	draw_rect(Rect2(pole + Vector2(-5.5, 3.6), Vector2(2.0, 1.2)), Color(0.9, 0.9, 0.85) * m)


# ------------------------------------------------------------------ town plan: roads and zones
const ROAD_COL := Color(0.62, 0.50, 0.34)
const ROAD_EDGE := Color(0.45, 0.35, 0.22)


func _draw_town_plan(sim: Sim, view: Rect2, zoom: float) -> void:
	var w := sim.world.w
	var T := float(Defs.TILE)
	var planning: bool = game.tool_mode.begins_with("zone") or game.tool_mode.ends_with("road") or (game.hud != null and game.hud.planner != null and game.hud.planner.visible) \
		or game.build_mode != "" or (game.hud != null and game.hud.build_layer != null and game.hud.build_layer.visible)
	# zones: tinted tiles while planning
	if planning:
		for i in sim.colony.zones.keys():
			var ii := int(i)
			var tp := Vector2(ii % w, ii / w) * T
			if not view.has_point(tp):
				continue
			var zc: Color = Defs.ZONES[int(sim.colony.zones[i])]["color"]
			draw_rect(Rect2(tp, Vector2(T, T)), Color(zc, 0.22))
			# outline where the zone ends
			var z := int(sim.colony.zones[i])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb = Vector2i(ii % w, ii / w) + d
				if int(sim.colony.zones.get(nb.y * w + nb.x, 0)) != z:
					var a := tp + Vector2(T, T) * 0.5 + Vector2(d) * T * 0.5
					var o := Vector2(d.y, d.x) * T * 0.5
					draw_line(a - o, a + o, Color(zc, 0.85), 1.0)
	# finished roads: packed earth with darker verges, joined to their neighbours; bridges are planks with rails
	for i in sim.road_tiles.keys():
		var ii := int(i)
		var q := Vector2i(ii % w, ii / w)
		var tp := Vector2(q) * T
		if not view.has_point(tp):
			continue
		var c := tp + Vector2(T, T) * 0.5
		var bridge := sim.world.road[ii] == 2
		var col := ROAD_COL if sim.world.snowy[ii] == 0 else ROAD_COL.lerp(Color(0.9, 0.9, 0.92), 0.5)
		var edge := ROAD_EDGE
		if bridge:
			col = Color(0.60, 0.44, 0.26)
			edge = Color(0.36, 0.24, 0.12)
		var links: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb = q + d
			if sim.world.inb(nb) and sim.world.road[nb.y * w + nb.x] != 0:
				links.append(d)
		var hw := 6.0 if bridge else 5.0
		draw_rect(Rect2(c - Vector2(hw, hw), Vector2(hw, hw) * 2.0), edge)
		for d in links:
			draw_rect(Rect2(c - Vector2(hw, hw), Vector2(hw, hw) * 2.0).merge(Rect2(c + Vector2(d) * T * 0.5 - Vector2(hw, hw), Vector2(hw, hw) * 2.0)), edge)
		draw_rect(Rect2(c - Vector2(hw - 1, hw - 1), Vector2(hw - 1, hw - 1) * 2.0), col)
		for d in links:
			draw_rect(Rect2(c - Vector2(hw - 1, hw - 1), Vector2(hw - 1, hw - 1) * 2.0).merge(Rect2(c + Vector2(d) * T * 0.5 - Vector2(hw - 1, hw - 1), Vector2(hw - 1, hw - 1) * 2.0)), col)
		if bridge:
			# planks across the direction of travel, and posts at the corners
			var along_x := links.has(Vector2i(1, 0)) or links.has(Vector2i(-1, 0))
			for k in 4:
				var off := -6.0 + k * 4.0
				if along_x:
					draw_line(c + Vector2(off, -5), c + Vector2(off, 5), edge, 0.8)
				else:
					draw_line(c + Vector2(-5, off), c + Vector2(5, off), edge, 0.8)
			for cx in [-1.0, 1.0]:
				for cy in [-1.0, 1.0]:
					draw_rect(Rect2(c + Vector2(cx * 6.0, cy * 6.0) - Vector2(1, 1), Vector2(2, 2)), Color(0.30, 0.20, 0.10))
		elif zoom >= 1.5:
			draw_rect(Rect2(c + Vector2(float(ii % 3) - 2.0, float(ii % 5) - 2.0), Vector2(1, 1)), col.darkened(0.2))
	# planned roads: dashed outlines
	for i in sim.colony.road_marks.keys():
		var ii := int(i)
		var tp := Vector2(ii % w, ii / w) * T
		if view.has_point(tp):
			draw_rect(Rect2(tp + Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.8, 0.45, 0.8), false, 1.0)
	# enemy roads your Billies will tear up
	for i in sim.colony.wreck_marks.keys():
		var ii := int(i)
		var tp := Vector2(ii % w, ii / w) * T
		if view.has_point(tp):
			draw_line(tp + Vector2(3, 3), tp + Vector2(13, 13), Color(1, 0.25, 0.2, 0.95), 2.0)
			draw_line(tp + Vector2(13, 3), tp + Vector2(3, 13), Color(1, 0.25, 0.2, 0.95), 2.0)
	# live drag preview
	if game.clear_dragging and game.tool_mode != "clear":
		var a: Vector2 = game.clear_start
		var b: Vector2 = game.get_global_mouse_position()
		if game.tool_mode == "road":
			for q in game.road_tiles_between(a, b):
				var ok: bool = sim.road_ok(q)
				draw_rect(Rect2(Vector2(q) * T + Vector2(3, 3), Vector2(10, 10)), Color(0.95, 0.8, 0.45, 0.55) if ok else Color(1, 0.3, 0.2, 0.4))
		else:
			var t0 := sim.world.tile_of(a)
			var t1 := sim.world.tile_of(b)
			var r := Rect2(Vector2(mini(t0.x, t1.x), mini(t0.y, t1.y)) * T, (Vector2(absi(t1.x - t0.x), absi(t1.y - t0.y)) + Vector2.ONE) * T)
			var zc = Color(1, 0.4, 0.3) if game.tool_mode in ["zone0", "unroad"] else Defs.ZONES[int(game.tool_mode.substr(4))]["color"]
			draw_rect(r, Color(zc, 0.2))
			draw_rect(r, Color(zc, 0.9), false, 2.0 / maxf(0.5, zoom))


# ------------------------------------------------------------------ combat effects
const LUNGE_T := 0.22
const HURT_T := 0.35


## Lunge toward the target when striking; knocked back a little when hit.
func _combat_off(o: Object) -> Vector2:
	var now := Fx.now()
	var off := Vector2.ZERO
	var ls := now - float(o.get("strike_at"))
	if ls < LUNGE_T:
		off += (o.get("strike_dir") as Vector2) * sin(ls / LUNGE_T * PI) * 3.5
	var hs := now - float(o.get("hurt_at"))
	if hs < HURT_T:
		off += (o.get("hurt_dir") as Vector2) * sin(hs / HURT_T * PI) * 2.0
		off.x += sin(hs * 90.0) * 0.8 * (1.0 - hs / HURT_T)   # shudder
	return off


func _hurt_flash(o: Object) -> float:
	var hs := Fx.now() - float(o.get("hurt_at"))
	return clampf(1.0 - hs / HURT_T, 0.0, 1.0) if hs >= 0.0 else 0.0


## Blood on the ground under the fighting (drawn beneath bodies).
func _draw_stains(sim: Sim, view: Rect2) -> void:
	var now := Fx.now()
	for e in sim.fx:
		if str(e["k"]) != "stain":
			continue
		var p: Vector2 = e["p"]
		if not view.has_point(p):
			continue
		var ph := (now - float(e["t0"])) / float(e["dur"])
		if ph >= 1.0 or ph < 0.0:
			continue
		var a := 0.55 * (1.0 - ph * ph)
		var sc := float(e["s"])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(e["seed"])
		var col := Color(0.42, 0.04, 0.03, a)
		_ellipse(p, 3.2 * sc, 1.6 * sc, col)
		for i in 3:
			_ellipse(p + Vector2(rng.randf_range(-5, 5), rng.randf_range(-2, 2)) * sc, rng.randf_range(0.8, 1.6) * sc, rng.randf_range(0.5, 1.0) * sc, col)


func _draw_fx(sim: Sim, view: Rect2, zoom: float) -> void:
	var now := Fx.now()
	var keep: Array = []
	for e in sim.fx:
		var ph := (now - float(e["t0"])) / float(e["dur"])
		if ph >= 1.0:
			continue
		keep.append(e)
		var p: Vector2 = e["p"]
		if ph < 0.0 or not view.has_point(p):
			continue
		var d: Vector2 = e.get("d", Vector2.RIGHT)
		var ang := d.angle()
		var fade := 1.0 - ph
		match str(e["k"]):
			"slash":
				# a bright arc sweeping across the target
				var c: Color = e["c"]
				var sweep := lerpf(-1.2, 1.2, minf(1.0, ph * 1.6))
				draw_arc(p - d * 3.0, 8.0, ang - 1.2, ang + sweep, 10, Color(c, 0.95 * fade), 2.2)
				draw_arc(p - d * 3.0, 6.5, ang - 1.0, ang + sweep * 0.9, 8, Color(1, 1, 1, 0.7 * fade), 1.0)
			"pierce":
				var c: Color = e["c"]
				var tip := p + d * lerpf(-6.0, 3.0, minf(1.0, ph * 3.0))
				draw_line(tip - d * 9.0, tip, Color(c, fade), 1.6)
				draw_line(tip - d * 9.0 + d.orthogonal() * 1.2, tip - d * 4.0, Color(1, 1, 1, 0.5 * fade), 0.8)
			"blunt":
				var r := lerpf(2.0, 9.0, ph)
				draw_arc(p, r, 0.0, TAU, 14, Color(1.0, 0.95, 0.8, 0.9 * fade), 1.6)
			"bite":
				# three claw rakes
				var o := d.orthogonal()
				var ln := lerpf(2.0, 9.0, minf(1.0, ph * 2.5))
				for i in 3:
					var off := o * (float(i) - 1.0) * 2.6
					draw_line(p + off - d * ln * 0.5 - o * 2.0, p + off + d * ln * 0.5 + o * 2.0, Color(0.95, 0.15, 0.1, 0.95 * fade), 1.4)
			"burst":
				# impact star
				var sc := float(e.get("s", 1.0))
				var r0 := 2.0 * sc
				var r1 := lerpf(4.0, 10.0, ph) * sc
				for i in 6:
					var a2 := ang + float(i) * TAU / 6.0 + 0.3
					var v := Vector2.from_angle(a2)
					draw_line(p + v * r0, p + v * r1, Color(1.0, 0.92, 0.55, fade), 1.3)
				if ph < 0.35:
					draw_circle(p, 2.5 * sc * (1.0 - ph * 2.0), Color(1, 1, 0.9, 0.9))
			"blood":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(e["seed"])
				var t := ph * float(e["dur"])
				for i in int(e.get("n", 4)):
					var v := d * rng.randf_range(20.0, 55.0) + Vector2(rng.randf_range(-25, 25), rng.randf_range(-45, -10))
					var q := p + v * t + Vector2(0, 120.0) * t * t
					var sz := rng.randf_range(0.8, 1.6)
					draw_circle(q, sz, Color(0.62, 0.03, 0.02, fade))
			"whiff":
				var o := d.orthogonal()
				for i in 3:
					var w := float(i) - 1.0
					var a0 := p + o * w * 3.0 - d * 3.0
					draw_line(a0, a0 + d * lerpf(3.0, 10.0, ph), Color(1, 1, 1, 0.55 * fade), 1.0)
			"dust":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(e["seed"])
				for i in 4:
					var v := Vector2.from_angle(rng.randf() * TAU) * lerpf(1.0, 7.0, ph)
					draw_circle(p + v, lerpf(1.5, 3.2, ph), Color(0.72, 0.64, 0.5, 0.45 * fade))
			"chips":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(e["seed"])
				var t := ph * float(e["dur"])
				for i in int(e.get("n", 5)):
					var v := (d * -1.0) * rng.randf_range(10.0, 35.0) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-50, -15))
					var q := p + v * t + Vector2(0, 110.0) * t * t
					draw_rect(Rect2(q, Vector2(1.6, 1.6)), Color(0.55, 0.45, 0.32, fade))
			"num":
				if zoom >= 1.4:
					var rise := p + Vector2(0, -10.0 * ph)
					crisp_text(rise, str(int(e["v"])), clampf(4.5 * zoom, 11.0, 15.0), Color(1.0, 0.85, 0.4, fade), 3, Color(0, 0, 0, 0.8 * fade))
	sim.fx = keep


# ------------------------------------------------------------------ helpers
func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ people
func _draw_human(p: Human, selected: bool, zoom: float, tribe: Color) -> void:
	var s := 1.0
	var a := p.age_years()
	if a < 3.0:
		s = 0.5
	elif a < 12.0:
		s = 0.72
	elif a < 16.0:
		s = 0.88
	var skin: Color = Config.race_skin(p.race)
	skin = skin.lightened(float(p.id % 5) * 0.03) if p.id % 2 == 0 else skin.darkened(float(p.id % 5) * 0.03)
	var hair: Color = HAIR[(p.id * 7) % HAIR.size()]
	if a > 55.0:
		hair = Color(0.82, 0.82, 0.80)
	var pos := p.pos + _combat_off(p)
	var flash := _hurt_flash(p)
	if flash > 0.0:
		skin = skin.lerp(Color(1.0, 0.25, 0.2), flash * 0.75)
	_ellipse(pos + Vector2(0, 6) * s, 5.0 * s, 2.0 * s, Color(0, 0, 0, 0.28))
	if selected:
		draw_arc(pos + Vector2(0, 6) * s, 8.0, 0, TAU, 24, Color(1.0, 0.9, 0.3), 1.5)
	if p.sleeping:
		# lying down
		draw_rect(Rect2(pos + Vector2(-7, 1) * s, Vector2(14, 5) * s), HIDE.darkened(0.2))
		draw_circle(pos + Vector2(-6, 2.5) * s, 2.8 * s, skin)
		draw_circle(pos + Vector2(-7, 2.0) * s, 2.8 * s, hair)
		var zt := fmod(p.anim, 2.0)
		draw_string(font, pos + Vector2(4, -6 - zt * 4), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 1.0 - zt * 0.5))
		return
	var moving := not p.path.is_empty()
	var bob := sin(p.anim * 12.0) * 1.0 if moving else 0.0
	var f := p.facing
	# legs
	var leg := sin(p.anim * 12.0) * 1.5 if moving else 0.0
	draw_rect(Rect2(pos + Vector2(-2.5 + leg * 0.5, 2) * s, Vector2(2, 5) * s), skin.darkened(0.25))
	draw_rect(Rect2(pos + Vector2(0.5 - leg * 0.5, 2) * s, Vector2(2, 5) * s), skin.darkened(0.3))
	# body (hide clothing)
	var body_c := HIDE.lerp(tribe, 0.45)
	if p.gender == "F":
		body_c = body_c.lightened(0.1)
	draw_rect(Rect2(pos + Vector2(-3.5, -4 + bob) * s, Vector2(7, 7) * s), body_c)
	draw_rect(Rect2(pos + Vector2(-3.5, 1 + bob) * s, Vector2(7, 2) * s), body_c.darkened(0.25))
	# armor on soldiers and war-party fighters: hide, leather with a wicker shield, bronze scale, iron mail
	var tier := Warfare.armor_tier(game.sim.col_of(p)) if Warfare.is_fighter(p) and a >= 12.0 else 0
	if tier > 0:
		var ac: Color = [Color(0.55, 0.40, 0.25), Color(0.48, 0.32, 0.18), Color(0.82, 0.58, 0.28), Color(0.62, 0.64, 0.68)][tier - 1]
		draw_rect(Rect2(pos + Vector2(-3.7, -4.2 + bob) * s, Vector2(7.4, 5.6) * s), ac)
		if tier >= 3:
			for ry in 3:
				draw_line(pos + Vector2(-3.5, -3 + ry * 1.7 + bob) * s, pos + Vector2(3.5, -3 + ry * 1.7 + bob) * s, ac.darkened(0.3), 0.6)
		draw_rect(Rect2(pos + Vector2(-3.7, -4.2 + bob) * s, Vector2(7.4, 5.6) * s), ac.darkened(0.35), false, 0.7)
		if tier >= 2:
			var sh_c: Color = Color(0.62, 0.50, 0.30) if tier == 2 else ac.lightened(0.1)
			draw_circle(pos + Vector2(-f * 5.0, -1 + bob) * s, 3.0 * s, sh_c.darkened(0.25))
			draw_circle(pos + Vector2(-f * 5.0, -1 + bob) * s, 2.2 * s, sh_c)
	# arms
	draw_rect(Rect2(pos + Vector2(-5, -3 + bob) * s, Vector2(1.5, 5) * s), skin)
	draw_rect(Rect2(pos + Vector2(3.5, -3 + bob) * s, Vector2(1.5, 5) * s), skin)
	# head
	var head := pos + Vector2(0, -7 + bob) * s
	if p.gender == "F":
		draw_rect(Rect2(head + Vector2(-3.5, -2) * s, Vector2(7, 7) * s), hair)
	draw_circle(head, 3.3 * s, skin.lerp(Color(0.5, 0.75, 0.4), 0.35) if p.is_sick() else skin)
	draw_rect(Rect2(head + Vector2(-3.3, -3.6) * s, Vector2(6.6, 2.2) * s), hair)
	draw_rect(Rect2(head + Vector2(f * 1.2 - 0.5, -0.5) * s, Vector2(1, 1) * s), Color(0.1, 0.07, 0.05))
	if p.gender == "M" and a >= 16.0:
		draw_rect(Rect2(head + Vector2(-2, 1.5) * s, Vector2(4, 2) * s), hair)
	# job tool / carried goods
	if int(p.carrying.get("log", 0)) > 0:
		# a whole log over the shoulder
		var lc := head + Vector2(0, 2.5) * s
		draw_line(lc + Vector2(-f * 9, 1) * s, lc + Vector2(f * 7, -3) * s, Color(0.36, 0.22, 0.12), 3.6 * s)
		draw_line(lc + Vector2(-f * 9, 0.2) * s, lc + Vector2(f * 7, -3.8) * s, Color(0.52, 0.34, 0.18), 1.4 * s)
		draw_circle(lc + Vector2(f * 7, -3) * s, 1.8 * s, Color(0.80, 0.66, 0.42))
	elif p.carry_total() > 0:
		draw_rect(Rect2(pos + Vector2(f * 4 - 2, -2 + bob) * s, Vector2(4, 4) * s), _carry_color(p))
	elif p.weapon != "" and a >= 12.0:
		_draw_weapon(p, pos, f, bob)
	elif p.job == "hunter" and a >= 12.0:
		draw_line(pos + Vector2(f * 5, -10 + bob), pos + Vector2(f * 5, 4 + bob), Color(0.45, 0.32, 0.2), 1.0)
		draw_line(pos + Vector2(f * 5, -10 + bob), pos + Vector2(f * 5, -12 + bob), Color(0.7, 0.7, 0.72), 1.5)
	if p.pregnant_days >= 0.0:
		draw_circle(pos + Vector2(f * 2.5, -0.5 + bob) * s, 2.2 * s, body_c.lightened(0.1))
	if p.job == "soldier" and a >= 12.0:
		# helmet: leather, bronze or iron depending on the weapon's age
		var hc := Color(0.45, 0.32, 0.20)
		if p.weapon != "":
			hc = [Color(0.45, 0.32, 0.20), Color(0.45, 0.32, 0.20), Color(0.80, 0.56, 0.26), Color(0.62, 0.64, 0.68)][int(Defs.weapon(p.weapon)["era"])]
		draw_rect(Rect2(head + Vector2(-3.6, -4.2) * s, Vector2(7.2, 3.0) * s), hc)
		draw_rect(Rect2(head + Vector2(-0.5, -5.2) * s, Vector2(1.0, 1.2) * s), hc.lightened(0.2))
	# status
	if p.task.get("type", "") == "flee":
		draw_string(font, pos + Vector2(-2, -15), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.3, 0.2))
	var lead: bool = game.sim.col_of(p).leader_id == p.id
	if lead:
		# a small gold circlet marks the tribe's Chief or President
		var cr := head + Vector2(0, -4.6) * s
		draw_rect(Rect2(cr + Vector2(-3.0, -0.6) * s, Vector2(6.0, 1.6) * s), Color(1.0, 0.82, 0.25))
		for dx in [-2.6, 0.0, 2.6]:
			draw_rect(Rect2(cr + Vector2(dx - 0.6, -2.0) * s, Vector2(1.2, 1.6) * s), Color(1.0, 0.82, 0.25))
	if zoom >= 2.2 or selected:
		var px := clampf(5.5 * zoom, 12.0, 17.0)
		crisp_text(pos + Vector2(0, 15), p.name, px, Color(1.0, 0.86, 0.45) if lead else Color(1, 1, 1), 4)


func _draw_weapon(p: Human, pos: Vector2, f: float, bob: float) -> void:
	if Smithing.is_custom(p.weapon):
		# the player's own pixel-art design, held upright in the hand
		var tex := Smithing.texture(game.sim, p.weapon)
		if tex != null:
			var hand2 := pos + Vector2(f * 5, bob)
			var sc := 0.55
			var sz := Vector2(tex.get_width(), tex.get_height()) * sc
			var ty: Dictionary = Smithing.TYPES[str(Defs.weapon(p.weapon)["type"])]
			var grip := float((ty["blade"] as Vector2i).y) * sc + 2.0      # hold it just below the blade
			draw_set_transform(hand2, f * 0.18, Vector2.ONE)
			draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -grip), sz), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var wd: Dictionary = Defs.weapon(p.weapon)
	var metal = [Color(0.55, 0.55, 0.55), Color(0.55, 0.55, 0.55), Color(0.82, 0.58, 0.28), Color(0.72, 0.74, 0.78)][int(wd["era"])]
	var shaft := Color(0.45, 0.32, 0.2)
	var hand := pos + Vector2(f * 5, bob)
	if p.weapon.ends_with("spear"):
		draw_line(hand + Vector2(0, 5), hand + Vector2(0, -12), shaft, 1.0)
		draw_colored_polygon(PackedVector2Array([hand + Vector2(0, -16), hand + Vector2(1.5, -12), hand + Vector2(-1.5, -12)]), metal)
	elif p.weapon.ends_with("sword"):
		draw_line(hand + Vector2(0, 1), hand + Vector2(f * 2, -9), metal, 1.6)
		draw_line(hand + Vector2(-2, 0), hand + Vector2(2, 0), Color(0.35, 0.25, 0.15), 1.4)
	elif p.weapon == "flint_axe":
		draw_line(hand + Vector2(0, 2), hand + Vector2(f * 1.5, -8), shaft, 1.4)
		draw_colored_polygon(PackedVector2Array([hand + Vector2(f * 1.5, -9), hand + Vector2(f * 5, -7.5), hand + Vector2(f * 4, -4.5), hand + Vector2(f * 1.5, -6)]), Color(0.45, 0.42, 0.40))
	elif p.weapon == "stone_club":
		draw_line(hand + Vector2(0, 2), hand + Vector2(f * 1.5, -7), shaft, 1.6)
		draw_circle(hand + Vector2(f * 1.5, -8), 2.0, metal)
	elif p.weapon == "sling":
		draw_line(hand, hand + Vector2(f * 3, -4), Color(0.6, 0.5, 0.35), 1.0)
		draw_circle(hand + Vector2(f * 3, -4), 1.2, Color(0.5, 0.5, 0.5))
	elif p.weapon == "longbow":
		draw_arc(hand + Vector2(-f * 1, -4), 9.0, -PI * 0.5 - 0.95 if f > 0 else PI * 0.5 - 0.95, -PI * 0.5 + 0.95 if f > 0 else PI * 0.5 + 0.95, 10, shaft, 1.3)
		draw_line(hand + Vector2(-f * 1, -12), hand + Vector2(-f * 1, 4), Color(0.9, 0.9, 0.85, 0.8), 0.6)
	else:      # bows, crossbow
		draw_arc(hand + Vector2(-f * 1, -3), 6.0, -PI * 0.5 - 0.9 if f > 0 else PI * 0.5 - 0.9, -PI * 0.5 + 0.9 if f > 0 else PI * 0.5 + 0.9, 8, shaft, 1.2)
		draw_line(hand + Vector2(-f * 1 + 0, -9), hand + Vector2(-f * 1, 3), Color(0.9, 0.9, 0.85, 0.8), 0.6)


func _carry_color(p: Human) -> Color:
	for k in p.carrying.keys():
		match str(k):
			"wood":
				return Color(0.55, 0.36, 0.18)
			"stone", "copper_ore", "tin_ore", "iron_ore":
				return Color(0.6, 0.6, 0.62)
			"berries":
				return Color(0.8, 0.15, 0.25)
			"water":
				return Color(0.3, 0.6, 0.95)
			"raw_meat", "fish":
				return Color(0.8, 0.35, 0.35)
			"grass":
				return Color(0.5, 0.75, 0.3)
			"crops", "fruit":
				return Color(0.95, 0.6, 0.15)
	return Color(0.7, 0.6, 0.4)


# ------------------------------------------------------------------ animals
func _draw_animal(a: Animal) -> void:
	var pos := a.pos + (_combat_off(a) if a.alive else Vector2.ZERO)
	var flash := _hurt_flash(a) if a.alive else 0.0
	if flash > 0.0:
		_ellipse(pos + Vector2(0, -1), 7.5, 5.0, Color(1.0, 0.2, 0.15, 0.45 * flash))
	var f := a.facing
	var moving := a.moving
	var bob := absf(sin(a.anim * 14.0)) * 1.0 if moving else 0.0
	if not a.alive:
		var c := _animal_color(a.species).darkened(0.3)
		_ellipse(pos, 6.0, 3.0, c)
		if a.meat_left > 0:
			draw_circle(pos + Vector2(1, 0), 1.6, Color(0.6, 0.1, 0.1))
		return
	match a.species:
		"bird":
			var flap := sin(a.anim * 18.0) * 3.0
			draw_polyline(PackedVector2Array([pos + Vector2(-4, flap), pos, pos + Vector2(4, flap)]), Color(0.15, 0.13, 0.12), 1.2)
			return
		"rabbit":
			_ellipse(pos + Vector2(0, 3), 4.0, 1.5, Color(0, 0, 0, 0.25))
			_ellipse(pos + Vector2(0, -bob), 3.5, 2.6, Color(0.62, 0.52, 0.40))
			draw_circle(pos + Vector2(f * 3, -2 - bob), 1.8, Color(0.62, 0.52, 0.40))
			draw_line(pos + Vector2(f * 3, -3 - bob), pos + Vector2(f * 2.5, -7 - bob), Color(0.55, 0.45, 0.35), 1.0)
			draw_circle(pos + Vector2(-f * 3.5, -1 - bob), 1.0, Color(0.95, 0.95, 0.95))
		"deer", "goat", "antelope", "camel", "bison":
			var body := _animal_color(a.species)
			_ellipse(pos + Vector2(0, 6), 6.0, 2.0, Color(0, 0, 0, 0.25))
			var leg_off := sin(a.anim * 14.0) * 1.5 if moving else 0.0
			for lx in [-3.5, 3.5]:
				draw_line(pos + Vector2(lx + leg_off, 1), pos + Vector2(lx - leg_off, 6), body.darkened(0.3), 1.2)
			_ellipse(pos + Vector2(0, -1 - bob), 6.0, 3.2, body)
			draw_line(pos + Vector2(f * 4.5, -2 - bob), pos + Vector2(f * 6.5, -6 - bob), body, 2.0)
			draw_circle(pos + Vector2(f * 7, -7 - bob), 2.2, body)
			if a.species == "deer" and a.id % 2 == 0:
				draw_line(pos + Vector2(f * 6.5, -9 - bob), pos + Vector2(f * 5, -13 - bob), Color(0.85, 0.78, 0.6), 1.0)
				draw_line(pos + Vector2(f * 7.5, -9 - bob), pos + Vector2(f * 9, -13 - bob), Color(0.85, 0.78, 0.6), 1.0)
			elif a.species == "goat":
				draw_line(pos + Vector2(f * 6.5, -9 - bob), pos + Vector2(f * 5, -11 - bob), Color(0.4, 0.38, 0.35), 1.2)
			elif a.species == "antelope":
				draw_line(pos + Vector2(f * 6.5, -9 - bob), pos + Vector2(f * 5.5, -14 - bob), Color(0.25, 0.2, 0.15), 1.0)
				draw_line(pos + Vector2(f * 7.5, -9 - bob), pos + Vector2(f * 8.0, -14 - bob), Color(0.25, 0.2, 0.15), 1.0)
			elif a.species == "camel":
				draw_circle(pos + Vector2(-f * 1.0, -4.5 - bob), 3.0, body.lightened(0.05))      # hump
			elif a.species == "bison":
				draw_circle(pos + Vector2(f * 3.0, -3.5 - bob), 4.0, body.darkened(0.2))         # shaggy shoulders
		_:
			var body := _animal_color(a.species)
			var size := 1.0
			if a.species == "bear":
				size = 1.6
			elif a.species == "boar":
				size = 1.1
			_ellipse(pos + Vector2(0, 5 * size), 6.0 * size, 2.0 * size, Color(0, 0, 0, 0.25))
			var leg_off := sin(a.anim * 14.0) * 1.5 if moving else 0.0
			for lx in [-3.5, 3.5]:
				draw_line(pos + Vector2(lx + leg_off, 0) * size, pos + Vector2(lx - leg_off, 5) * size, body.darkened(0.35), 1.6 * size)
			_ellipse(pos + Vector2(0, -1 - bob) * size, 6.0 * size, 3.4 * size, body)
			draw_circle(pos + Vector2(f * 6, -2 - bob) * size, 2.8 * size, body.lightened(0.05))
			if a.species == "wolf" or a.species == "jaguar":
				draw_line(pos + Vector2(-f * 5.5, -1 - bob), pos + Vector2(-f * 9, -4 - bob), body, 1.5)
				draw_line(pos + Vector2(f * 5.5, -4 - bob), pos + Vector2(f * 5.5, -7 - bob), body, 1.2)
			if a.species == "jaguar":
				for sp in [Vector2(-2, -2), Vector2(1, 0), Vector2(3, -3), Vector2(-4, 0)]:
					draw_circle(pos + sp + Vector2(0, -bob), 0.8, Color(0.2, 0.15, 0.08))
			if a.species == "boar":
				draw_line(pos + Vector2(f * 8, -1 - bob), pos + Vector2(f * 9.5, -3 - bob), Color(0.95, 0.92, 0.85), 1.0)
			if a.state == "chase":
				draw_string(font, pos + Vector2(-2, -12 * size), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.25, 0.2))


func _animal_color(sp: String) -> Color:
	match sp:
		"rabbit":
			return Color(0.62, 0.52, 0.40)
		"deer":
			return Color(0.62, 0.42, 0.24)
		"boar":
			return Color(0.32, 0.24, 0.18)
		"goat":
			return Color(0.88, 0.86, 0.80)
		"wolf":
			return Color(0.52, 0.52, 0.54)
		"bear":
			return Color(0.36, 0.24, 0.15)
		"jaguar":
			return Color(0.88, 0.66, 0.26)
		"antelope":
			return Color(0.78, 0.58, 0.34)
		"camel":
			return Color(0.80, 0.66, 0.44)
		"bison":
			return Color(0.34, 0.24, 0.16)
		"crocodile":
			return Color(0.28, 0.36, 0.20)
	return Color(0.4, 0.4, 0.4)


# ------------------------------------------------------------------ buildings
# Era palettes: structures look more advanced as a tribe moves through the ages.
const WALLS := [Color(0.55, 0.40, 0.25), Color(0.58, 0.55, 0.50), Color(0.55, 0.38, 0.22), Color(0.72, 0.70, 0.66)]
const SHADOW_HEIGHT := {"campfire": 0.0, "fence": 3.0, "wall": 7.0, "gate": 8.0, "blacksmith": 12.0, "training_camp": 0.0,
	"capitol": 20.0, "map_table": 3.0, "arrow_tower": 24.0, "farm": 0.0, "bedding": 2.0, "drying_rack": 5.0,
	"research_table": 3.0, "well": 3.0, "shelter": 10.0, "stone_hut": 10.0, "house": 14.0, "stone_house": 16.0,
	"storage": 8.0, "granary": 12.0, "workshop": 12.0, "healer_hut": 10.0, "mine": 8.0, "hunting_camp": 9.0,
	"watchtower": 22.0, "harbor": 6.0, "monolith": 0.0, "lumber_yard": 0.0, "mercenary_hall": 12.0, "bandit_camp": 0.0,
	"lookout_perch": 14.0, "war_drum_circle": 0.0, "sling_platform": 12.0, "ram_shed": 9.0, "bastion": 18.0, "catapult": 8.0,
	"ballista_tower": 24.0, "trebuchet": 22.0, "shaman_circle": 4.0, "great_hearth": 3.0, "flint_works": 10.0, "stone_calendar": 12.0,
	"marketplace": 8.0, "bathhouse": 12.0, "academy": 18.0, "iron_foundry": 14.0, "smithing_bench": 6.0}
const ROOFS := [Color(0.72, 0.62, 0.34), Color(0.66, 0.58, 0.30), Color(0.45, 0.30, 0.18), Color(0.70, 0.30, 0.22)]


func _draw_building(sim: Sim, b: Building) -> void:
	var T := float(Defs.TILE)
	var o := Vector2(b.tile) * T
	var s := Vector2(b.size()) * T
	var era: int = sim.civ(b.civ_id).era_i
	var alpha := 1.0 if b.built else 0.45
	var m := Color(1, 1, 1, alpha)
	var wall: Color = WALLS[era] * m
	var roof: Color = ROOFS[era] * m
	var height: float = SHADOW_HEIGHT.get(b.type, 6.0) * (1.0 if b.built else 0.5)
	var round_types := ["stone_hut", "healer_hut", "hunting_camp", "granary", "well"]
	if height > 0.0:
		if b.type in round_types:
			_round_shadow(o + s * 0.5, minf(s.x, s.y) * 0.46, height)
		elif b.type != "fence" and b.type != "wall" and b.type != "gate":
			_shadow(o, s, height)
		elif b.type != "fence":
			_shadow(o + Vector2(1, 1), s - Vector2(2, 2), height * (1.0 + b.tier * 0.5))
	match b.type:
		"lookout_perch", "war_drum_circle", "sling_platform", "ram_shed", "bastion", "catapult", "ballista_tower", "trebuchet":
			_war_structure(sim, b, o, s, m)
		"smithing_bench":
			_smithing_bench(b, o, s, m)
		"shaman_circle", "great_hearth", "flint_works", "stone_calendar", "marketplace", "bathhouse", "academy", "iron_foundry":
			_bonus_structure(sim, b, o, s, m, era, roof)
		"monolith":
			_monolith(o, s, b.built, m)
		"lumber_yard":
			_lumber_yard(o, s, m)
		"bandit_camp":
			_bandit_camp(o, s, m)
		"campfire":
			_campfire(o + Vector2(8, 8), era, b.is_lit(), m)
		"shelter":
			if era == 0:
				_lean_to(o, s, m)
			else:
				_house(o, s, wall, roof, era, m)
		"stone_hut":
			_round_roof(o + s * 0.5, minf(s.x, s.y) * 0.44, Color(0.66, 0.58, 0.30) * m, Color(0.58, 0.55, 0.50) * m, m)
		"house", "stone_house":
			_house(o, s, wall, roof, maxi(era, 2 if b.type == "house" else 3), m)
		"storage":
			if era == 0:
				draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.48, 0.38, 0.22, 0.35 * alpha))
				draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.42, 0.28, 0.15) * m, false, 1.5)
				for k in 4:
					var lg := Rect2(o + Vector2(4, 5 + k * 3.5), Vector2(13, 3))
					draw_rect(lg, Color(0.55, 0.36, 0.18) * m)
					draw_circle(lg.position + Vector2(13, 1.5), 1.5, Color(0.72, 0.55, 0.32) * m)   # log ends
				_pile(o + Vector2(23, 10), 4.5, Color(0.58, 0.58, 0.6) * m)
				_pile(o + Vector2(22, 23), 5.0, Color(0.75, 0.6, 0.35) * m)
				_pile(o + Vector2(9, 24), 4.0, Color(0.85, 0.82, 0.72) * m)
			else:
				_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, s.y - 9)), roof, era, m)
				for k in 4:
					_crate(o + Vector2(3 + k * 7, s.y - 7), 6.0, Color(0.62, 0.42, 0.24) * m)
		"granary":
			_round_roof(o + s * 0.5, minf(s.x, s.y) * 0.44, roof.lightened(0.05), Color(0.70, 0.55, 0.38) * m, m)
		"research_table":
			var top: Color = [Color(0.55, 0.55, 0.56), Color(0.60, 0.56, 0.48), Color(0.52, 0.36, 0.20), Color(0.46, 0.30, 0.18)][era] * m
			var tr := Rect2(o + Vector2(2, 3), Vector2(s.x - 4, s.y - 6))
			draw_rect(Rect2(tr.position + Vector2(2, 2), tr.size), Color(0, 0, 0, 0.25 * alpha))
			draw_rect(tr, top)
			draw_rect(Rect2(tr.position, Vector2(tr.size.x, 2)), top.lightened(0.15))
			draw_rect(tr, top.darkened(0.45), false, 1.0)
			if era == 0:
				draw_line(o + Vector2(6, 7), o + Vector2(14, 10), Color(0.9, 0.88, 0.8) * m, 1.5)      # bones
				draw_circle(o + Vector2(22, 8), 2.0, Color(0.5, 0.5, 0.5) * m)
			elif era == 1:
				draw_circle(o + Vector2(8, 8), 2.5, Color(0.75, 0.45, 0.28) * m)                     # clay pot
				draw_circle(o + Vector2(8, 8), 1.2, Color(0.3, 0.18, 0.1) * m)
				draw_rect(Rect2(o + Vector2(16, 6), Vector2(8, 5)), Color(0.8, 0.75, 0.6) * m)      # tablet
			else:
				draw_rect(Rect2(o + Vector2(6, 6), Vector2(9, 5)), Color(0.92, 0.88, 0.75) * m)      # scroll
				draw_circle(o + Vector2(22, 8), 2.0, (Color(0.80, 0.55, 0.25) if era == 2 else Color(0.5, 0.52, 0.56)) * m)
			if b.stored > 0.0 and b.built:
				draw_rect(Rect2(o + Vector2(2, -2), Vector2((s.x - 4) * clampf(b.stored / 40.0, 0.0, 1.0), 2)), Color(0.5, 0.8, 1.0))
		"bedding":
			draw_rect(Rect2(o + Vector2(1, 3), Vector2(30, 11)), Color(0.62, 0.68, 0.32, 0.6 * alpha))
			draw_rect(Rect2(o + Vector2(3, 5), Vector2(11, 7)), HIDE * m)
			draw_rect(Rect2(o + Vector2(18, 5), Vector2(11, 7)), HIDE.lightened(0.1) * m)
			draw_rect(Rect2(o + Vector2(3, 5), Vector2(3, 7)), HIDE.lightened(0.25) * m)
			draw_rect(Rect2(o + Vector2(18, 5), Vector2(3, 7)), HIDE.lightened(0.35) * m)
		"drying_rack":
			var wood := Color(0.45, 0.3, 0.16) * m
			draw_line(o + Vector2(2, 8), o + Vector2(14, 8), Color(0, 0, 0, 0.25 * alpha), 2.0)
			draw_line(o + Vector2(1, 6), o + Vector2(15, 6), wood, 1.5)
			draw_circle(o + Vector2(2, 6), 1.6, wood.darkened(0.2))
			draw_circle(o + Vector2(14, 6), 1.6, wood.darkened(0.2))
			var owner := sim.civ(b.civ_id)
			if owner.raw_food() > 0.0 or owner.count("dried_meat") > 0.0:
				for k in 4:
					draw_rect(Rect2(o + Vector2(3.5 + k * 2.7, 4), Vector2(2, 5)), Color(0.6, 0.18, 0.15) * m)
		"hunting_camp":
			_tipi(o + Vector2(11, 14), 10.0, Color(0.66, 0.5, 0.32) * m, m)
			var wood2 := Color(0.4, 0.28, 0.15) * m
			draw_line(o + Vector2(23, 20), o + Vector2(31, 20), wood2, 1.5)
			draw_circle(o + Vector2(23, 20), 1.4, wood2)
			draw_circle(o + Vector2(31, 20), 1.4, wood2)
			draw_rect(Rect2(o + Vector2(24, 21), Vector2(6, 7)), HIDE.lightened(0.15) * m)        # stretched hide
			draw_rect(Rect2(o + Vector2(24, 21), Vector2(6, 7)), HIDE.darkened(0.3) * m, false, 1.0)
		"farm":
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.42, 0.30, 0.18, alpha))
			for k in 5:
				draw_line(o + Vector2(3, 5 + k * 9), o + Vector2(s.x - 3, 5 + k * 9), Color(0.32, 0.22, 0.12, alpha), 2.0)
			if era >= 2:
				draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.45, 0.32, 0.18, alpha), false, 1.5)   # fenced field
			if b.crop_stage >= 1:
				var g := b.crop_growth if b.crop_stage == 1 else 1.0
				for row in 5:
					for col in 7:
						var p := o + Vector2(5 + col * 6.3, 5 + row * 9)
						var rad := 0.8 + g * 2.0
						draw_circle(p + Vector2(0.6, 0.6), rad, Color(0.12, 0.25, 0.08, 0.5))
						draw_circle(p, rad, Color(0.3, 0.62, 0.22))
						draw_circle(p - Vector2(0.5, 0.5), rad * 0.5, Color(0.45, 0.78, 0.32))
						if b.crop_stage == 2:
							draw_circle(p, 1.1, Color(0.95, 0.75, 0.25))
		"well":
			var c := o + Vector2(8, 8)
			draw_circle(c, 6.5, Color(0.55, 0.53, 0.50) * m)
			draw_arc(c, 6.0, PI, PI * 1.5, 8, Color(0.72, 0.70, 0.66) * m, 1.5)
			draw_circle(c, 4.0, Color(0.18, 0.32, 0.45) * m)
			draw_circle(c + Vector2(1, 1), 2.5, Color(0.12, 0.24, 0.36) * m)
			draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), Color(0.45, 0.30, 0.16) * m, 1.5)
		"healer_hut":
			_round_roof(o + s * 0.5, minf(s.x, s.y) * 0.44, Color(0.50, 0.62, 0.30) * m, Color(0.62, 0.50, 0.34) * m, m)
			var cc := o + s * 0.5
			draw_rect(Rect2(cc + Vector2(-1.5, -5), Vector2(3, 10)), Color(0.95, 0.95, 0.95) * m)
			draw_rect(Rect2(cc + Vector2(-5, -1.5), Vector2(10, 3)), Color(0.95, 0.95, 0.95) * m)
		"mine":
			var cm := o + s * 0.5
			for k in 9:
				var ang := k * TAU / 9.0
				_pile(cm + Vector2(cos(ang), sin(ang)) * s.x * 0.36, 3.5, Color(0.52, 0.49, 0.45) * m)   # rubble ring
			draw_rect(Rect2(cm - Vector2(8, 8), Vector2(16, 16)), Color(0.45, 0.30, 0.16) * m)        # timber collar
			draw_rect(Rect2(cm - Vector2(6, 6), Vector2(12, 12)), Color(0.08, 0.06, 0.05) * m)        # shaft
			draw_rect(Rect2(cm - Vector2(6, 6), Vector2(12, 3)), Color(0.18, 0.14, 0.1) * m)
			draw_line(cm + Vector2(-9, -2), cm + Vector2(9, -2), Color(0.55, 0.38, 0.2) * m, 2.0)      # windlass beam
			draw_circle(cm + Vector2(0, -2), 1.8, Color(0.62, 0.62, 0.62) * m)
		"workshop":
			_gable_roof(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.40, 0.28, 0.18) * m, era, m)
			var ch := Rect2(o + Vector2(s.x - 10, 4), Vector2(6, 6))
			draw_rect(ch, Color(0.45, 0.43, 0.42) * m)                                                 # chimney from above
			draw_rect(Rect2(ch.position + Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.08, 0.06, 0.05) * m)
			var tsec := Time.get_ticks_msec() / 1000.0
			for k in 3:
				var ph := fmod(tsec * 0.6 + k * 0.33, 1.0)
				draw_circle(ch.get_center() + Vector2(ph * 10.0, -ph * 6.0), 1.5 + ph * 2.5, Color(0.7, 0.7, 0.72, 0.5 * (1.0 - ph) * alpha))
			var glow := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)
			draw_circle(o + Vector2(6, s.y - 4), 2.5, Color(1.0, 0.55, 0.15, glow * alpha))           # forge
		"wall":
			_wall(sim, b, o, m)
		"gate":
			_gate(sim, b, o, m)
		"arrow_tower":
			var tc := o + Vector2(8, 8)
			var stone := Color(0.60, 0.58, 0.55) * m
			draw_circle(tc, 7.5, stone.darkened(0.25))
			draw_circle(tc - Vector2(0.8, 0.8), 6.5, stone)
			for k in 8:
				var ang := k * TAU / 8.0
				draw_rect(Rect2(tc + Vector2(cos(ang), sin(ang)) * 5.8 - Vector2(1.2, 1.2), Vector2(2.4, 2.4)), stone.lightened(0.15))
			draw_circle(tc, 3.5, Color(0.36, 0.30, 0.24) * m)          # wooden floor
			draw_circle(tc + Vector2(0.5, 0.5), 1.4, sim.civ(b.civ_id).color * m)   # archer
		"blacksmith":
			_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, s.y - 10)), Color(0.34, 0.30, 0.28) * m, era, m)
			var ch2 := Rect2(o + Vector2(4, 4), Vector2(6, 6))
			draw_rect(ch2, Color(0.42, 0.40, 0.40) * m)
			draw_rect(Rect2(ch2.position + Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.08, 0.06, 0.05) * m)
			var tsec2 := Time.get_ticks_msec() / 1000.0
			if b.craft != "":
				for k in 3:
					var ph := fmod(tsec2 * 0.7 + k * 0.33, 1.0)
					draw_circle(ch2.get_center() + Vector2(ph * 8.0, -ph * 7.0), 1.4 + ph * 2.4, Color(0.55, 0.55, 0.58, 0.55 * (1.0 - ph) * alpha))
			# open-air forge and anvil in front
			var fg := o + Vector2(7, s.y - 5)
			draw_circle(fg, 3.5, Color(0.30, 0.28, 0.26) * m)
			var glow2 := (0.6 + 0.4 * sin(tsec2 * 9.0)) if b.craft != "" else 0.25
			draw_circle(fg, 2.0, Color(1.0, 0.5, 0.12, glow2 * alpha))
			var av := o + Vector2(s.x - 10, s.y - 6)
			draw_rect(Rect2(av, Vector2(7, 3)), Color(0.25, 0.25, 0.28) * m)
			draw_rect(Rect2(av + Vector2(-2, 0.5), Vector2(2, 2)), Color(0.30, 0.30, 0.33) * m)
		"training_camp":
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.66, 0.56, 0.38, 0.9 * alpha))     # beaten earth
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), Color(0.42, 0.30, 0.16) * m, false, 1.5)
			for k in 3:
				var dm := o + Vector2(10 + k * 14, 10)
				draw_circle(dm + Vector2(1, 1), 3.2, Color(0, 0, 0, 0.25 * alpha))
				draw_circle(dm, 3.0, Color(0.85, 0.75, 0.40) * m)             # straw dummy
				draw_line(dm - Vector2(4, 0), dm + Vector2(4, 0), Color(0.45, 0.32, 0.18) * m, 1.2)
			for k in 2:
				var tg := o + Vector2(14 + k * 18, s.y - 10)
				draw_circle(tg, 4.0, Color(0.90, 0.85, 0.70) * m)            # target
				draw_circle(tg, 2.5, Color(0.80, 0.25, 0.20) * m)
				draw_circle(tg, 1.0, Color(0.95, 0.90, 0.75) * m)
			draw_line(o + Vector2(4, 24), o + Vector2(4, 40), Color(0.40, 0.28, 0.15) * m, 2.0)     # weapon rack
			for k in 4:
				draw_line(o + Vector2(2, 26 + k * 4), o + Vector2(8, 24 + k * 4), Color(0.6, 0.6, 0.62) * m, 1.0)
		"mercenary_hall":
			# long timber hall with a striped awning, weapon racks and the tribe's banner
			_gable_roof(Rect2(o + Vector2(1, 1), Vector2(s.x - 2, s.y - 12)), Color(0.46, 0.30, 0.18) * m, era, m)
			var aw := Rect2(o + Vector2(3, s.y - 12), Vector2(s.x - 6, 6))
			for k in int(aw.size.x / 4.0):
				draw_rect(Rect2(aw.position + Vector2(k * 4, 0), Vector2(4, 6)), (Color(0.75, 0.22, 0.18) if k % 2 == 0 else Color(0.92, 0.86, 0.72)) * m)
			for k in 2:
				var rk := o + Vector2(6 + k * (s.x - 18), s.y - 5)
				draw_line(rk, rk + Vector2(8, 0), Color(0.40, 0.28, 0.15) * m, 1.5)
				for j in 3:
					draw_line(rk + Vector2(1 + j * 3, 1), rk + Vector2(2 + j * 3, -6), Color(0.65, 0.65, 0.68) * m, 1.0)
			draw_circle(o + Vector2(s.x * 0.5, s.y - 4), 2.4, Color(0.85, 0.68, 0.25) * m)     # coin chest
			if b.built:
				FlagArt.draw(self, Rect2(o + Vector2(2, -8), Vector2(11, 7)), sim.civ(b.civ_id).flag, 1.0, Time.get_ticks_msec() / 1000.0)
				draw_line(o + Vector2(2, -8), o + Vector2(2, 6), Color(0.3, 0.2, 0.1), 1.2)
		"capitol":
			var base := Rect2(o + Vector2(1, 1), s - Vector2(2, 2))
			draw_rect(base, Color(0.80, 0.77, 0.70) * m)                   # stone platform
			draw_rect(base, Color(0.50, 0.47, 0.42) * m, false, 1.0)
			for k in 7:
				draw_circle(o + Vector2(5 + k * 6.3, 4), 1.4, Color(0.95, 0.93, 0.88) * m)            # columns
				draw_circle(o + Vector2(5 + k * 6.3, s.y - 4), 1.4, Color(0.95, 0.93, 0.88) * m)
			_hip_roof(Rect2(o + Vector2(6, 8), s - Vector2(12, 16)), Color(0.72, 0.32, 0.22) * m, m)
			var cc2 := o + s * 0.5
			draw_circle(cc2, 4.0, Color(0.85, 0.70, 0.30) * m)              # gilded dome
			draw_circle(cc2 - Vector2(1, 1), 2.2, Color(1.0, 0.88, 0.5) * m)
			if b.built:
				FlagArt.draw(self, Rect2(o + Vector2(s.x - 14, -8), Vector2(12, 8)), sim.civ(b.civ_id).flag, 1.0, Time.get_ticks_msec() / 1000.0)
				draw_line(o + Vector2(s.x - 14, -8), o + Vector2(s.x - 14, 6), Color(0.3, 0.2, 0.1), 1.2)
		"map_table":
			var tr2 := Rect2(o + Vector2(2, 2), Vector2(s.x - 4, s.y - 4))
			draw_rect(Rect2(tr2.position + Vector2(2, 2), tr2.size), Color(0, 0, 0, 0.25 * alpha))
			draw_rect(tr2, Color(0.48, 0.32, 0.18) * m)
			var mp := tr2.grow(-2.0)
			draw_rect(mp, Color(0.90, 0.84, 0.66) * m)                     # parchment
			draw_line(mp.position + Vector2(2, 3), mp.position + Vector2(10, 6), Color(0.3, 0.45, 0.75) * m, 1.0)
			draw_line(mp.position + Vector2(14, 2), mp.position + Vector2(22, 8), Color(0.3, 0.55, 0.3) * m, 1.0)
			draw_circle(mp.position + Vector2(18, 4), 1.2, Color(0.8, 0.2, 0.2) * m)
		"watchtower":
			var r := Rect2(o + Vector2(2, 2), s - Vector2(4, 4))
			for pt in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
				draw_circle(pt, 2.0, Color(0.38, 0.26, 0.14) * m)
			_hip_roof(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), Color(0.70, 0.30, 0.22) * m, m)
		"harbor":
			var deck := Color(0.55, 0.40, 0.24) * m
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), deck)
			for k in int(s.y / 4):
				draw_line(o + Vector2(2, 3 + k * 4), o + Vector2(s.x - 2, 3 + k * 4), deck.darkened(0.25), 1.0)
			draw_rect(Rect2(o + Vector2(1, 1), s - Vector2(2, 2)), deck.darkened(0.45), false, 1.0)
			for pt in [Vector2(2, 2), Vector2(s.x - 3, 2), Vector2(2, s.y - 3), Vector2(s.x - 3, s.y - 3)]:
				draw_circle(o + pt, 1.8, Color(0.30, 0.20, 0.12) * m)        # posts
			draw_circle(o + Vector2(6, 6), 2.2, Color(0.35, 0.24, 0.14) * m)
			draw_line(o + Vector2(6, 6), o + Vector2(18, 10), Color(0.35, 0.24, 0.14) * m, 1.5)   # crane arm
			for k in 3:
				_crate(o + Vector2(s.x - 14 + (k % 2) * 6, 3 + (k / 2) * 6), 5.0, Color(0.50, 0.36, 0.22) * m)
			if b.ship_order >= 0:
				var pct := clampf(b.ship_progress, 0.0, 1.0)
				draw_rect(Rect2(o + Vector2(4, s.y * 0.55), Vector2((s.x - 8) * pct, 4)), Color(0.42, 0.28, 0.15))
				draw_rect(Rect2(o + Vector2(4, s.y * 0.55), Vector2(s.x - 8, 4)), Color(0.9, 0.85, 0.7, 0.8), false, 1.0)
		"fence":
			var c := o + Vector2(8, 8)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb := sim.building_at(b.tile + d)
				if nb != null and nb.type == "fence":
					var dv := Vector2(d) * T
					draw_line(c + Vector2(1, 1), c + dv + Vector2(1, 1), Color(0, 0, 0, 0.25 * alpha), 2.0)
					draw_line(c, c + dv, Color(0.5, 0.34, 0.18) * m, 1.5)
			draw_circle(c + Vector2(1, 1), 2.0, Color(0, 0, 0, 0.3 * alpha))
			draw_circle(c, 1.8, Color(0.45, 0.3, 0.16) * m)
	if b.built and b.cur_hp() < b.max_hp() - 0.5:
		var hpct := clampf(b.cur_hp() / b.max_hp(), 0.0, 1.0)
		draw_rect(Rect2(o + Vector2(0, -4), Vector2(s.x, 3)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(o + Vector2(0, -4), Vector2(s.x * hpct, 3)), Color(1.0 - hpct, 0.2 + hpct * 0.7, 0.2))
	if b.built and not b.type in ["fence", "farm", "campfire", "wall", "gate", "arrow_tower", "capitol"]:
		var pole := o + Vector2(s.x - 3, 2)
		draw_circle(pole, 1.2, Color(0.35, 0.25, 0.15))
		draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(6, 1.5), pole + Vector2(0, 3)]), sim.civ(b.civ_id).color)
	if not b.built:
		# blueprint: dashed outline, materials bar (blue) then construction bar (green)
		var bp := Color(0.55, 0.8, 1.0, 0.85)
		for k in int((s.x + s.y) * 2 / 6):
			var d := k * 6.0
			var p1: Vector2
			if d < s.x:
				p1 = o + Vector2(d, 0)
			elif d < s.x + s.y:
				p1 = o + Vector2(s.x, d - s.x)
			elif d < s.x * 2 + s.y:
				p1 = o + Vector2(s.x - (d - s.x - s.y), s.y)
			else:
				p1 = o + Vector2(0, s.y - (d - s.x * 2 - s.y))
			draw_circle(p1, 0.9, bp)
		var cost: Dictionary = b.cost()
		var total := 0.0
		var have := 0.0
		for k in cost.keys():
			total += float(cost[k])
			have += minf(float(cost[k]), float(b.delivered.get(k, 0.0)))
		var mat := have / maxf(1.0, total)
		var pct := clampf(b.progress / float(b.def()["work"]), 0.0, 1.0)
		draw_rect(Rect2(o + Vector2(0, s.y + 1), Vector2(s.x, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(o + Vector2(0, s.y + 1), Vector2(s.x * mat, 2)), Color(0.4, 0.7, 1.0))
		draw_rect(Rect2(o + Vector2(0, s.y + 3), Vector2(s.x * pct, 2)), Color(0.4, 0.9, 0.3))


## Walls join up with neighbouring wall and gate tiles. Tier 0 sharpened logs, 1 mortared
## stone, 2 thick fortified stone with battlements.
func _wall_links(sim: Sim, b: Building) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb := sim.building_at(b.tile + d)
		if nb != null and (nb.type == "wall" or nb.type == "gate") and nb.civ_id == b.civ_id:
			out.append(d)
	return out


func _wall(sim: Sim, b: Building, o: Vector2, m: Color) -> void:
	var c := o + Vector2(8, 8)
	var links := _wall_links(sim, b)
	if b.tier == 0:
		var log_c := Color(0.50, 0.34, 0.18) * m
		var dirs: Array = links if not links.is_empty() else [Vector2i(1, 0)]
		for d in dirs:
			for k in 2:
				var lp := c + Vector2(d) * (2.0 + k * 4.0)
				draw_circle(lp + Vector2(1.2, 1.2), 2.4, Color(0, 0, 0, 0.3 * m.a))
				draw_circle(lp, 2.3, log_c)
				draw_circle(lp - Vector2(0.6, 0.6), 1.0, log_c.lightened(0.35))
		draw_circle(c, 2.4, log_c.darkened(0.1))
		draw_circle(c - Vector2(0.6, 0.6), 1.0, log_c.lightened(0.35))
		return
	var w := 6.0 if b.tier == 1 else 9.0
	var st := (Color(0.62, 0.60, 0.56) if b.tier == 1 else Color(0.50, 0.49, 0.48)) * m
	draw_rect(Rect2(c - Vector2(w, w) * 0.5, Vector2(w, w)), st)
	for d in links:
		var dv := Vector2(d)
		var r := Rect2(c + dv * 4.0 - Vector2(w, w) * 0.5 + (dv * 4.0).abs() * 0.0, Vector2(w, w))
		r = r.merge(Rect2(c + dv * 8.0 - Vector2(w, w) * 0.5, Vector2(w, w)))
		draw_rect(r, st)
	# joints and top light
	draw_rect(Rect2(c - Vector2(w, w) * 0.5, Vector2(w, 1.5)), st.lightened(0.18))
	draw_line(c + Vector2(-w * 0.5, 0), c + Vector2(w * 0.5, 0), st.darkened(0.25), 1.0)
	if b.tier == 2:
		for d in links + [Vector2i(0, 0)]:
			var mc := c + Vector2(d) * 6.0
			draw_rect(Rect2(mc - Vector2(4.5, 4.5), Vector2(2.5, 2.5)), st.lightened(0.15))
			draw_rect(Rect2(mc + Vector2(2.0, 2.0), Vector2(2.5, 2.5)), st.darkened(0.15))


func _gate(sim: Sim, b: Building, o: Vector2, m: Color) -> void:
	var c := o + Vector2(8, 8)
	var links := _wall_links(sim, b)
	var horiz := links.has(Vector2i(1, 0)) or links.has(Vector2i(-1, 0)) or links.is_empty()
	var post = ([Color(0.45, 0.30, 0.16), Color(0.62, 0.60, 0.56), Color(0.50, 0.49, 0.48)][b.tier]) * m
	var door := Color(0.55, 0.38, 0.20) * m
	var a1 := c + (Vector2(-7, 0) if horiz else Vector2(0, -7))
	var a2 := c + (Vector2(7, 0) if horiz else Vector2(0, 7))
	draw_rect(Rect2(a1 - Vector2(2.5, 2.5), Vector2(5, 5)), post)
	draw_rect(Rect2(a2 - Vector2(2.5, 2.5), Vector2(5, 5)), post)
	var dr := Rect2(c - (Vector2(5, 2.5) if horiz else Vector2(2.5, 5)), (Vector2(10, 5) if horiz else Vector2(5, 10)))
	draw_rect(dr, door)
	for k in 4:
		if horiz:
			draw_line(Vector2(dr.position.x + 1 + k * 2.6, dr.position.y), Vector2(dr.position.x + 1 + k * 2.6, dr.end.y), door.darkened(0.3), 0.8)
		else:
			draw_line(Vector2(dr.position.x, dr.position.y + 1 + k * 2.6), Vector2(dr.end.x, dr.position.y + 1 + k * 2.6), door.darkened(0.3), 0.8)
	draw_rect(dr, door.darkened(0.5), false, 1.0)


func _campfire(c: Vector2, era: int, lit: bool, m: Color) -> void:
	var ring := 6.0 + era * 0.8
	var stone: Color = [Color(0.5, 0.5, 0.52), Color(0.56, 0.54, 0.50), Color(0.70, 0.50, 0.28), Color(0.38, 0.38, 0.40)][era]
	draw_circle(c, ring - 1.0, Color(0.16, 0.12, 0.10) * m)          # ash pit
	for k in 7 + era * 2:
		var ang := k * TAU / (7 + era * 2)
		var sp := c + Vector2(cos(ang), sin(ang)) * ring
		draw_circle(sp + Vector2(0.6, 0.6), 1.9, Color(0, 0, 0, 0.3 * m.a))
		draw_circle(sp, 1.8, stone * m)
		draw_circle(sp - Vector2(0.5, 0.5), 0.8, stone.lightened(0.25) * m)
	draw_line(c + Vector2(-4, 3), c + Vector2(4, -3), Color(0.4, 0.26, 0.14) * m, 2.0)
	draw_line(c + Vector2(-4, -3), c + Vector2(4, 3), Color(0.35, 0.22, 0.12) * m, 2.0)
	if lit:
		var t := Time.get_ticks_msec() / 1000.0
		var fl := sin(t * 11.0) * 0.6 + sin(t * 7.3) * 0.4
		draw_circle(c, 4.2 + fl, Color(1.0, 0.45, 0.1, 0.9))
		draw_circle(c + Vector2(fl * 0.5, -0.5), 2.6 + fl * 0.5, Color(1.0, 0.75, 0.25))
		draw_circle(c, 1.2, Color(1.0, 0.95, 0.7))


## Shadow cast toward the lower right (sun in the upper left), longer for taller buildings.
func _shadow(o: Vector2, s: Vector2, height: float) -> void:
	var off := Vector2(height * 0.45, height * 0.35)
	draw_rect(Rect2(o + off * 0.5 + Vector2(1, 1), s - Vector2(2, 2)), Color(0.05, 0.04, 0.08, 0.16))
	draw_rect(Rect2(o + off + Vector2(1, 1), s - Vector2(2, 2)), Color(0.05, 0.04, 0.08, 0.16))


func _round_shadow(c: Vector2, r: float, height: float) -> void:
	var off := Vector2(height * 0.45, height * 0.35)
	draw_circle(c + off * 0.5, r, Color(0.05, 0.04, 0.08, 0.16))
	draw_circle(c + off, r, Color(0.05, 0.04, 0.08, 0.16))


## A small crate seen from above.
func _crate(p: Vector2, sz: float, col: Color) -> void:
	var r := Rect2(p, Vector2(sz, sz))
	draw_rect(Rect2(p + Vector2(1, 1), r.size), Color(0, 0, 0, 0.3 * col.a))
	draw_rect(r, col)
	draw_line(p, p + Vector2(sz, sz), col.darkened(0.3), 1.0)
	draw_rect(r, col.darkened(0.45), false, 1.0)


## A heap of stones / goods seen from above, lit from the top-left.
func _pile(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(1.2, 1.2), r, Color(0, 0, 0, 0.28 * col.a))
	draw_circle(c, r, col.darkened(0.12))
	draw_circle(c - Vector2(r, r) * 0.22, r * 0.68, col)
	draw_circle(c - Vector2(r, r) * 0.42, r * 0.3, col.lightened(0.22))


## Gable roof from directly above. The ridge runs along the long side; the slope facing the
## sun (north / west) is lit and the other one is in shade. Covering depends on the era.
func _gable_roof(r: Rect2, col: Color, era: int, m: Color) -> void:
	var horiz := r.size.x >= r.size.y
	var lit := col.lightened(0.12)
	var dark := col.darkened(0.22)
	var a: Rect2
	var b2: Rect2
	if horiz:
		a = Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5))
		b2 = Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5))
	else:
		a = Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
		b2 = Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y))
	draw_rect(a, lit)
	draw_rect(b2, dark)
	# covering texture: thatch strokes (early), shingle / tile courses (later)
	var lines := int((r.size.y if horiz else r.size.x) / 3.0)
	for k in lines:
		var f := (k + 0.5) / lines
		if horiz:
			var yy := r.position.y + f * r.size.y
			draw_line(Vector2(r.position.x + 1, yy), Vector2(r.end.x - 1, yy), (lit if f < 0.5 else dark).darkened(0.18), 1.0)
		else:
			var xx := r.position.x + f * r.size.x
			draw_line(Vector2(xx, r.position.y + 1), Vector2(xx, r.end.y - 1), (lit if f < 0.5 else dark).darkened(0.18), 1.0)
	if era >= 2:
		var step := 4.0
		for k in int((r.size.x if horiz else r.size.y) / step):
			var t := (k + 0.5) * step
			if horiz:
				draw_line(Vector2(r.position.x + t, r.position.y + 1), Vector2(r.position.x + t, r.end.y - 1), Color(0, 0, 0, 0.12 * m.a), 1.0)
			else:
				draw_line(Vector2(r.position.x + 1, r.position.y + t), Vector2(r.end.x - 1, r.position.y + t), Color(0, 0, 0, 0.12 * m.a), 1.0)
	# ridge
	if horiz:
		draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), col.lightened(0.3), 2.0)
	else:
		draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), col.lightened(0.3), 2.0)
	draw_rect(r, col.darkened(0.5), false, 1.0)


## Hip roof from above: four slopes meeting at a short ridge, lit top/left, shaded bottom/right.
func _hip_roof(r: Rect2, col: Color, m: Color) -> void:
	var c := r.get_center()
	var inset := minf(r.size.x, r.size.y) * 0.5
	var r1 := Vector2(r.position.x + inset, c.y)
	var r2 := Vector2(r.end.x - inset, c.y)
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var bl := Vector2(r.position.x, r.end.y)
	var br := r.end
	draw_colored_polygon(PackedVector2Array([tl, tr, r2, r1]), col.lightened(0.14))       # north
	draw_colored_polygon(PackedVector2Array([tl, r1, bl]), col.lightened(0.05))            # west
	draw_colored_polygon(PackedVector2Array([bl, r1, r2, br]), col.darkened(0.24))         # south
	draw_colored_polygon(PackedVector2Array([tr, br, r2]), col.darkened(0.14))             # east
	for e in [[tl, r1], [tr, r2], [bl, r1], [br, r2], [r1, r2]]:
		draw_line(e[0], e[1], col.lightened(0.28), 1.0)
	draw_rect(r, col.darkened(0.5), false, 1.0)


## Conical thatched / domed roof from above: rings of thatch, a lit upper-left side and a peak.
func _round_roof(c: Vector2, rad: float, thatch: Color, base: Color, m: Color) -> void:
	draw_circle(c, rad + 1.5, base.darkened(0.15))            # wall foot / stone ring
	for k in 10:
		var ang := k * TAU / 10.0
		draw_circle(c + Vector2(cos(ang), sin(ang)) * (rad + 0.8), 1.5, base)
	draw_circle(c, rad, thatch.darkened(0.2))
	draw_circle(c - Vector2(rad, rad) * 0.12, rad * 0.86, thatch)
	draw_circle(c - Vector2(rad, rad) * 0.28, rad * 0.45, thatch.lightened(0.14))
	for k in 3:
		draw_arc(c, rad * (0.35 + k * 0.22), 0, TAU, 20, thatch.darkened(0.18), 1.0)
	for k in 8:
		var ang := k * TAU / 8.0
		draw_line(c + Vector2(cos(ang), sin(ang)) * 2.0, c + Vector2(cos(ang), sin(ang)) * rad, thatch.darkened(0.25), 1.0)
	draw_circle(c, 2.2, thatch.darkened(0.35))
	draw_circle(c - Vector2(0.6, 0.6), 1.0, thatch.lightened(0.3))
	draw_arc(c, rad, 0, TAU, 24, thatch.darkened(0.5), 1.0)


## Tipi from above: hide cone with the pole bundle sticking out of the smoke hole.
func _tipi(c: Vector2, rad: float, hide: Color, m: Color) -> void:
	_round_shadow(c, rad, 8.0)
	draw_circle(c, rad, hide.darkened(0.15))
	draw_circle(c - Vector2(rad, rad) * 0.15, rad * 0.8, hide)
	for k in 6:
		var ang := k * TAU / 6.0 + 0.3
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * rad, hide.darkened(0.3), 1.0)
	draw_circle(c, 2.0, Color(0.15, 0.1, 0.06) * m)
	for k in 4:
		var ang := k * TAU / 4.0 + 0.8
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * 4.0, Color(0.35, 0.24, 0.12) * m, 1.0)
	draw_arc(c, rad, 0, TAU, 20, hide.darkened(0.5), 1.0)


## Caveman lean-to from above: a single sloping thatch mat leaning on two forked poles.
func _lean_to(o: Vector2, s: Vector2, m: Color) -> void:
	var thatch := Color(0.72, 0.62, 0.34) * m
	var r := Rect2(o + Vector2(3, 4), s - Vector2(6, 10))
	var bands := 6
	for k in bands:
		var f := float(k) / bands
		draw_rect(Rect2(r.position + Vector2(0, f * r.size.y), Vector2(r.size.x, r.size.y / bands + 0.5)), thatch.lightened(0.14 - f * 0.4))
	for k in int(r.size.x / 3):
		draw_line(r.position + Vector2(1.5 + k * 3, 1), r.position + Vector2(1.5 + k * 3, r.size.y - 1), thatch.darkened(0.25), 1.0)
	draw_line(r.position, r.position + Vector2(r.size.x, 0), Color(0.42, 0.30, 0.16) * m, 2.0)     # ridge pole
	draw_rect(r, thatch.darkened(0.5), false, 1.0)
	draw_rect(Rect2(Vector2(r.position.x + r.size.x * 0.35, r.end.y), Vector2(r.size.x * 0.3, 4)), Color(0.12, 0.08, 0.05, 0.6 * m.a))   # dark opening
	draw_circle(r.position + Vector2(0, r.size.y), 1.5, Color(0.40, 0.28, 0.15) * m)
	draw_circle(r.end, 1.5, Color(0.40, 0.28, 0.15) * m)


## House from above: era 1 thatch gable, 2 timber shingles, 3 tiled hip roof with a chimney.
func _house(o: Vector2, s: Vector2, wall: Color, roof: Color, era: int, m: Color) -> void:
	var r := Rect2(o + Vector2(1, 1), s - Vector2(2, 2))
	draw_rect(r.grow(0.5), wall.darkened(0.3))           # wall tops peeking under the eaves
	var rr := r.grow(-1.0)
	if era >= 3:
		_hip_roof(rr, roof, m)
		for k in 4:
			var yy := rr.position.y + (k + 0.5) * rr.size.y / 4.0
			draw_line(Vector2(rr.position.x + 3, yy), Vector2(rr.end.x - 3, yy), Color(0, 0, 0, 0.12 * m.a), 1.0)   # tile courses
		var ch := Rect2(rr.position + Vector2(rr.size.x * 0.68, rr.size.y * 0.15), Vector2(5, 5))
		draw_rect(Rect2(ch.position + Vector2(2, 2), ch.size), Color(0, 0, 0, 0.3 * m.a))
		draw_rect(ch, Color(0.55, 0.52, 0.50) * m)
		draw_rect(Rect2(ch.position + Vector2(1.5, 1.5), Vector2(2, 2)), Color(0.08, 0.06, 0.05) * m)
	else:
		_gable_roof(rr, roof, era, m)
	# doorstep on the south side
	draw_rect(Rect2(Vector2(o.x + s.x * 0.5 - 3, o.y + s.y - 1), Vector2(6, 2)), Color(0.40, 0.32, 0.24) * m)


# ------------------------------------------------------------------ markers & flags
## Coloured dots above every person and a flag at every tribe's camp. Both keep a constant
## on-screen size, so they stay visible when zoomed far out.
func _draw_markers(sim: Sim, view: Rect2, zoom: float, fast := false) -> void:
	var k := clampf(1.0 / zoom, 0.45, 6.0)
	for p in ([] if fast else sim.people_all):
		if not p.alive or p.at_sea() or not view.has_point(p.pos):
			continue
		var col: Color = sim.col_of(p).color
		var r := (3.2 if p.civ_id == 0 else 2.6) * k
		var at: Vector2 = p.pos + Vector2(0, -15.0 - 4.0 * k)
		draw_circle(at, r + 1.2 * k, Color(0, 0, 0, 0.7))
		draw_circle(at, r, col)
		if game.selected_ids.has(p.id) or p.id == game.selected_human_id:
			draw_arc(at, r + 3.0 * k, 0, TAU, 16, Color(1, 1, 1), 1.5 * k)
	for c in sim.colonies:
		if c.collapsed or c.bandit:
			continue
		var base := sim.world.center_of(c.home) + Vector2(-Defs.TILE * 1.5, -Defs.TILE)
		if view.grow(80.0 * k).has_point(base):
			_flag(base, c, k)
	# small banners over states while a tribe is raising its flag there
	for cid in sim.claims_in_progress.keys():
		var st: int = sim.claims_in_progress[cid]
		var at := sim.world.center_of(sim.states.centers[st])
		if view.has_point(at):
			FlagArt.draw(self, Rect2(at + Vector2(0, -18) * k, Vector2(10, 7) * k), sim.civ(int(cid)).flag, 0.8 * k, Time.get_ticks_msec() / 1000.0)
			draw_line(at, at + Vector2(0, -18) * k, Color(0.3, 0.2, 0.1), 1.2 * k)


func _flag(base: Vector2, c: Colony, k: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var top := base + Vector2(0, -34.0 * k)
	draw_line(base + Vector2(1, 1) * k, top + Vector2(1, 1) * k, Color(0, 0, 0, 0.5), 2.5 * k)
	draw_line(base, top, Color(0.35, 0.24, 0.14), 2.0 * k)
	draw_circle(top, 1.8 * k, Color(0.85, 0.75, 0.4))
	# waving banner in the tribe's own design
	var w := 20.0 * k
	var h := 13.0 * k
	FlagArt.draw(self, Rect2(top + Vector2(0, 1.0 * k), Vector2(w, h)), c.flag if not c.flag.is_empty() else FlagArt.default_flag(), 1.6 * k, t)
	if not game.sim.enemies_of(c.civ_id).is_empty() and game.sim.at_war(0, c.civ_id):
		draw_string_outline(font, top + Vector2(w + 3.0 * k, h * 0.8), "⚔", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), maxi(1, int(2 * k)), Color(0, 0, 0))
		draw_string(font, top + Vector2(w + 3.0 * k, h * 0.8), "⚔", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), Color(1, 0.3, 0.2))
	if k < 0.7:
		return          # close up, the flag alone is enough
	crisp_text(base + Vector2(0, 14.0 * k), c.name, 17.0, c.color.lightened(0.45), 5, Color(0, 0, 0, 0.9))


# ------------------------------------------------------------------ ships
func _draw_ship(sim: Sim, sh: Ship, zoom: float) -> void:
	var c := sim.civ(sh.civ_id)
	var bob := sin(sh.anim * 2.2) * 0.6
	var length: float = [16.0, 22.0, 30.0][sh.kind]
	var width: float = [5.0, 8.0, 10.0][sh.kind]
	var xf := Transform2D(sh.heading, sh.pos + Vector2(0, bob))
	# shadow and wake
	var shadow := PackedVector2Array()
	for k in 16:
		var ang := k * TAU / 16.0
		shadow.append(xf * Vector2(cos(ang) * length * 0.55, sin(ang) * width * 0.6) + Vector2(3, 3))
	draw_colored_polygon(shadow, Color(0.02, 0.05, 0.12, 0.3))
	if not sh.path.is_empty():
		for k in 3:
			var wp := xf * Vector2(-length * 0.6 - k * 6.0, 0)
			draw_arc(wp, 3.0 + k * 2.5, sh.heading + PI * 0.6, sh.heading + PI * 1.4, 8, Color(1, 1, 1, 0.4 - k * 0.12), 1.0)
	var local := [Vector2(-length * 0.5, -width * 0.5), Vector2(length * 0.3, -width * 0.5), Vector2(length * 0.55, 0),
		Vector2(length * 0.3, width * 0.5), Vector2(-length * 0.5, width * 0.5)]
	var hull := PackedVector2Array()
	var deck := PackedVector2Array()
	for v in local:
		hull.append(xf * v)
		deck.append(xf * (v * 0.78))
	draw_colored_polygon(hull, Color(0.42, 0.28, 0.15))
	draw_colored_polygon(deck, Color(0.60, 0.44, 0.26))
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, Color(0.20, 0.12, 0.07), 1.0)
	if sh.kind == 2:
		for k in 4:
			var x := -length * 0.35 + k * length * 0.2
			draw_line(xf * Vector2(x, -width * 0.5), xf * Vector2(x - 2, -width * 0.5 - 4), Color(0.35, 0.24, 0.14), 1.0)
			draw_line(xf * Vector2(x, width * 0.5), xf * Vector2(x - 2, width * 0.5 + 4), Color(0.35, 0.24, 0.14), 1.0)
	for i in sh.passengers.size():
		draw_circle(xf * Vector2(-length * 0.3 + (i % 5) * 3.5, -1.5 + (i / 5) * 3.0), 1.5, c.color)
	if sh.kind >= 1:
		# the sail stands up, so it is drawn upright to read well from above
		var mast := sh.pos + Vector2(0, bob - 2)
		draw_line(mast, mast + Vector2(0, -14), Color(0.35, 0.24, 0.14), 1.5)
		draw_colored_polygon(PackedVector2Array([mast + Vector2(1, -13), mast + Vector2(9, -5), mast + Vector2(1, -3)]), Color(0.95, 0.93, 0.85))
		draw_colored_polygon(PackedVector2Array([mast + Vector2(1, -13), mast + Vector2(5, -12), mast + Vector2(1, -10)]), c.color)
	else:
		draw_line(xf * Vector2(-length * 0.1, -width * 0.45), xf * Vector2(-length * 0.1, -width * 0.45 - 4), c.color, 1.5)   # pennant
	if sh.id == game.selected_ship_id:
		draw_arc(sh.pos, length * 0.7, 0, TAU, 28, Color(1.0, 0.9, 0.3), 1.5 / maxf(0.5, zoom))
		for t in sh.path:
			draw_circle(Vector2(t) * Defs.TILE + Vector2(8, 8), 1.2, Color(1, 1, 1, 0.4))


# ------------------------------------------------------------------ overlays
func _draw_orders(zoom: float) -> void:
	if game.dragging:
		var gmp := get_global_mouse_position()
		var r := Rect2(game.drag_start, gmp - game.drag_start).abs()
		draw_rect(r, Color(0.5, 0.9, 1.0, 0.12))
		draw_rect(r, Color(0.6, 0.95, 1.0, 0.9), false, 1.0 / zoom)
	if game.order_marker_t > 0.0:
		var t: float = game.order_marker_t
		var col: Color = game.order_marker_col
		draw_arc(game.order_marker, (1.0 - t) * 14.0 + 4.0, 0, TAU, 24, Color(col, t), 2.0 / zoom)


func _draw_picker(sim: Sim) -> void:
	var sp := sim.world.center_of(sim.world.spawn)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0)
	draw_arc(sp, 22.0, 0, TAU, 32, Color(1, 1, 1, pulse), 2.0)
	draw_string(font, sp + Vector2(-40, -28), "Suggested", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color(1, 1, 1, pulse))
	var t: Vector2i = game.hover_tile
	if sim.world.inb(t):
		var ok := sim.start_problem(t) == ""
		var col := Color(0.4, 1.0, 0.45) if ok else Color(1.0, 0.35, 0.3)
		var c := sim.world.center_of(t)
		draw_arc(c, 40.0, 0, TAU, 40, Color(col, 0.8), 2.0)
		draw_rect(Rect2(Vector2(t) * Defs.TILE, Vector2(Defs.TILE, Defs.TILE)), Color(col, 0.5))



func _draw_selection(sim: Sim) -> void:
	if game.selected_building_id < 0:
		return
	var b := sim.building(game.selected_building_id)
	if b == null:
		return
	var o := Vector2(b.tile) * Defs.TILE
	draw_rect(Rect2(o - Vector2(1, 1), Vector2(b.size()) * Defs.TILE + Vector2(2, 2)), Color(1.0, 0.9, 0.3), false, 1.5)


func _draw_ghost(sim: Sim) -> void:
	var type: String = game.build_mode
	if type == "":
		return
	var t: Vector2i = game.place_tile
	var d: Dictionary = Defs.BUILDINGS[type]
	var sz: Vector2i = d["size"]
	var err := sim.can_place(sim.colony, type, t)
	var col := Color(0.3, 1.0, 0.4, 0.35) if err == "" else Color(1.0, 0.3, 0.25, 0.35)
	var o := Vector2(t) * Defs.TILE
	draw_rect(Rect2(o, Vector2(sz) * Defs.TILE), col)
	draw_rect(Rect2(o, Vector2(sz) * Defs.TILE), Color(col, 0.9), false, 1.0)
