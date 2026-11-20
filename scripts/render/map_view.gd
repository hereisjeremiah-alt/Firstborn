class_name MapView
extends Control
## World map / minimap: terrain image, colony, people, buildings and the camera view. Click to jump.

var game: Node
var map_tex: ImageTexture
var show_animals := false
var territory_mode := false     # political map (needs a Map Table)
var _terr_tex: ImageTexture
var _border_tex: ImageTexture
var _tex_version := -1
var _road_tex: ImageTexture
var _road_version := -1
var _road_t := 0.0
var zoomable := false            # the big World Map: mouse wheel zooms, right/middle-drag pans
var map_zoom := 1.0
var map_center := Vector2(0.5, 0.5)   # point of the map (0..1) at the middle of the view
var _panning := false
var _bold: FontVariation
const MAX_ZOOM := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.5


func set_zoom(z: float, keep_screen := Vector2(-1, -1)) -> void:
	var nz := clampf(z, 1.0, MAX_ZOOM)
	if keep_screen.x >= 0.0:
		# keep the map point under the cursor in place
		var r := _map_rect()
		var rel := (keep_screen - r.position) / r.size
		map_zoom = nz
		var r2 := _map_rect()
		var rel2 := (keep_screen - r2.position) / r2.size
		map_center += rel - rel2
	else:
		map_zoom = nz
	_clamp_center()
	queue_redraw()


func reset_view() -> void:
	map_zoom = 1.0
	map_center = Vector2(0.5, 0.5)
	queue_redraw()


func _clamp_center() -> void:
	var half := 0.5 / map_zoom
	map_center.x = clampf(map_center.x, half, 1.0 - half)
	map_center.y = clampf(map_center.y, half, 1.0 - half)


func build(wm: WorldMap) -> void:
	map_tex = make_texture(wm)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if zoomable else CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


static func make_texture(wm: WorldMap) -> ImageTexture:
	return ImageTexture.create_from_image(TerrainView.make_color_image(wm, true))


func _process(_delta: float) -> void:
	if visible:
		if game != null and game.sim != null and game.sim.states != null and _tex_version != game.sim.states.version:
			_tex_version = game.sim.states.version
			_terr_tex = make_state_texture(game.sim, true) if size.x >= 300.0 else null
			_border_tex = make_state_texture(game.sim, false)
		if game != null and game.sim != null and game.sim.world != null and _road_version != game.sim.road_version:
			_road_t -= _delta
			if _road_t <= 0.0 or _road_tex == null:
				_road_t = 1.0
				_road_version = game.sim.road_version
				_road_tex = make_road_texture(game.sim)
		queue_redraw()


## Every road and bridge, in the colour of the tribe that built it, with a dark edge so it
## stands out on both the terrain and the territory map.
static func make_road_texture(sim: Sim) -> ImageTexture:
	var wm := sim.world
	var img := Image.create(wm.w, wm.h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var edge := Color(0.05, 0.04, 0.03, 0.75)
	for i in sim.road_tiles.keys():
		var ii := int(i)
		var x := ii % wm.w
		var y := ii / wm.w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx >= 0 and ny >= 0 and nx < wm.w and ny < wm.h and wm.road[ny * wm.w + nx] == 0:
				img.set_pixel(nx, ny, edge)
	for i in sim.road_tiles.keys():
		var ii := int(i)
		var ow := int(sim.road_tiles[i])
		var col := sim.civ(ow).color.lightened(0.2) if ow >= 0 and ow < sim.colonies.size() else Color(0.85, 0.75, 0.55)
		img.set_pixel(ii % wm.w, ii / wm.w, col)
	return ImageTexture.create_from_image(img)


## Political map: every state filled with its owner's colour (unclaimed land in grey) with thin
## borders between states. `fill` false gives just the coloured borders of claimed states, drawn
## over the normal terrain map.
static func make_state_texture(sim: Sim, fill: bool) -> ImageTexture:
	var wm := sim.world
	var sm: StateMap = sim.states
	var img := Image.create(wm.w, wm.h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in wm.h:
		for x in wm.w:
			var i := y * wm.w + x
			var st := sm.ids[i]
			var edge := false
			if st >= 0:
				if x < wm.w - 1 and sm.ids[i + 1] != st:
					edge = true
				elif y < wm.h - 1 and sm.ids[i + wm.w] != st:
					edge = true
				elif x > 0 and sm.ids[i - 1] != st:
					edge = true
				elif y > 0 and sm.ids[i - wm.w] != st:
					edge = true
			var ow := int(sm.owners[st]) if st >= 0 else -1
			if fill:
				var col: Color
				if st < 0:
					col = Color(0.10, 0.16, 0.26)
				elif ow >= 0:
					col = sim.civ(ow).color.darkened(0.55 if edge else 0.12)
				else:
					var base: Color = Defs.TERRAIN[wm.terrain[i]]["color"]
					var g := base.get_luminance() * 0.6 + 0.18
					col = Color(g, g, g * 0.96).darkened(0.35 if edge else 0.0)
				img.set_pixel(x, y, col)
			elif ow >= 0 and edge:
				img.set_pixel(x, y, sim.civ(ow).color)
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.9))
	if map_tex == null or game == null or game.sim == null:
		return
	var sim: Sim = game.sim
	var r := _map_rect()
	if territory_mode and _terr_tex != null:
		draw_texture_rect(_terr_tex, r, false)
	else:
		draw_texture_rect(map_tex, r, false)
		if _border_tex != null:
			draw_texture_rect(_border_tex, r, false)
	var sm: StateMap = sim.states
	var big := size.x >= 300.0
	var k := r.size.x / float(sim.world.w * Defs.TILE)
	if _road_tex != null and not game.picking:
		draw_texture_rect(_road_tex, r, false)
	var fog: Fog = sim.fog
	if fog.on:
		draw_texture_rect(fog.texture, r, false)
	if territory_mode and big:
		var kk := r.size.x / float(sim.world.w)
		var sfs := int(clampf(9.0 + (map_zoom - 1.0) * 1.5, 9.0, 15.0))
		for st in sm.count():
			# zoomed in, every state is named; zoomed out only claimed ones
			if int(sm.owners[st]) < 0 and st != game.selected_state and map_zoom < 2.5:
				continue
			var cp: Vector2 = r.position + (Vector2(sm.centers[st]) + Vector2(0.5, 0.5)) * kk
			if not Rect2(Vector2.ZERO, size).has_point(cp) or not fog.is_explored(sm.centers[st]):
				continue
			# the tribe's own name already sits over its home state
			var home_here := false
			for hc2 in sim.colonies:
				if not hc2.collapsed and sm.at(hc2.home) == st:
					home_here = true
			if home_here:
				continue
			_label_at(cp + Vector2(0, 4), sm.names[st], sfs, Color(1, 1, 1, 0.9), 3)
	if game.selected_state >= 0:
		var bb: Rect2 = sm.bboxes[game.selected_state]
		draw_rect(Rect2(r.position + bb.position * k, bb.size * k), Color(1, 1, 1, 0.9), false, 1.5)
	if show_animals:
		for a in sim.animals:
			if a.alive and (not fog.on or fog.is_explored(sim.world.tile_of(a.pos))):
				draw_rect(Rect2(r.position + a.pos * k, Vector2(1, 1)), Color(0.9, 0.2, 0.2) if a.def()["predator"] else Color(0.9, 0.85, 0.6))
	for c in sim.colonies:
		if c.collapsed:
			continue
		var hc: Vector2 = r.position + sim.world.center_of(c.home) * k
		for b in c.buildings:
			if fog.on and not fog.is_explored(b.center_tile()):
				continue
			draw_rect(Rect2(r.position + b.center() * k - Vector2(1.5, 1.5), Vector2(3, 3)), c.color.darkened(0.2))
		for p in c.people:
			if p.alive and (not fog.on or c.civ_id == 0 or fog.is_explored(sim.world.tile_of(p.pos))):
				draw_circle(r.position + p.pos * k, 2.4 if big else 1.5, c.color.lightened(0.3))
		if fog.on and c.civ_id != 0 and not fog.is_explored(c.home):
			continue
		if c.bandit:
			# outlaw camps: a small black banner, no tribe name
			for b in c.buildings:
				if b.type == "bandit_camp" and fog.is_explored(b.center_tile()):
					var bc: Vector2 = r.position + b.center() * k
					draw_rect(Rect2(bc + Vector2(-3, -9), Vector2(7, 5)), Color(0.05, 0.05, 0.05))
					draw_line(bc + Vector2(-3, -9), bc, Color(0.3, 0.2, 0.1), 1.2)
					if big:
						_label_at(bc + Vector2(0, 12), "Bandits", 11, Color(0.9, 0.55, 0.5), 3)
			continue
		# tribe flag
		var fk := 1.4 if big else 0.8
		var top := hc + Vector2(-4, -16) * fk
		draw_line(hc, top, Color(0.2, 0.15, 0.1), 1.5)
		FlagArt.draw(self, Rect2(top, Vector2(13, 9) * fk), c.flag if not c.flag.is_empty() else FlagArt.default_flag())
		for e in sim.enemies_of(c.civ_id):
			if c.civ_id < e.civ_id:
				var eh: Vector2 = r.position + sim.world.center_of(e.home) * k
				draw_dashed_line(hc, eh, Color(1, 0.25, 0.2, 0.8), 2.0, 6.0)
		if big:
			_label_at(hc + Vector2(0, 16), c.name, int(clampf(14.0 + (map_zoom - 1.0), 14.0, 19.0)), c.color.lightened(0.45), 4)
	if game.picking:
		var sp: Vector2 = r.position + sim.world.center_of(sim.world.spawn) * k
		draw_circle(sp, 4.0, Color(1, 1, 1))
		draw_arc(sp, 7.0, 0, TAU, 20, Color(1, 1, 1), 1.5)
	var vr: Rect2 = game.view_rect
	draw_rect(Rect2(r.position + vr.position * k, vr.size * k), Color(1, 1, 0.6, 0.9), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.55, 0.4, 0.8), false, 1.0)


func _label_at(at: Vector2, text: String, fs: int, col: Color, outline: int) -> void:
	var w := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var o := Vector2(roundf(at.x - w * 0.5), roundf(at.y))
	draw_string_outline(_bold, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.85 * col.a))
	draw_string(_bold, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _map_rect() -> Rect2:
	# keep the world's own shape (the Earth map is much wider than tall)
	var aspect := 1.0
	if game != null and game.sim != null and game.sim.world != null and game.sim.world.h > 0:
		aspect = float(game.sim.world.w) / float(game.sim.world.h)
	elif map_tex != null and map_tex.get_height() > 0:
		aspect = float(map_tex.get_width()) / float(map_tex.get_height())
	var room := size - Vector2(8, 8)
	var fit := Vector2(room.x, room.x / aspect)
	if fit.y > room.y:
		fit = Vector2(room.y * aspect, room.y)
	var base := Rect2((size - fit) * 0.5, fit)
	if not zoomable or map_zoom <= 1.0:
		return base
	var big := fit * map_zoom
	var mid := base.position + base.size * 0.5
	return Rect2(mid - map_center * big, big)


func _gui_input(event: InputEvent) -> void:
	if game == null or game.sim == null:
		return
	var pos := Vector2(-1, -1)
	if zoomable:
		if event is InputEventMouseButton:
			var zb := event as InputEventMouseButton
			if zb.pressed and zb.button_index == MOUSE_BUTTON_WHEEL_UP:
				set_zoom(map_zoom * 1.25, zb.position)
				accept_event()
				return
			if zb.pressed and zb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				set_zoom(map_zoom / 1.25, zb.position)
				accept_event()
				return
			if zb.button_index == MOUSE_BUTTON_RIGHT or zb.button_index == MOUSE_BUTTON_MIDDLE:
				_panning = zb.pressed
				accept_event()
				return
		elif event is InputEventMouseMotion and _panning:
			var pm := event as InputEventMouseMotion
			map_center -= pm.relative / _map_rect().size
			_clamp_center()
			queue_redraw()
			accept_event()
			return
		elif event is InputEventMagnifyGesture:
			set_zoom(map_zoom * (event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
			accept_event()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pos = mm.position
	if pos.x < 0.0:
		return
	var r := _map_rect()
	var rel := (pos - r.position) / r.size
	if rel.x >= 0.0 and rel.y >= 0.0 and rel.x <= 1.0 and rel.y <= 1.0:
		var wp: Vector2 = rel * Vector2(game.sim.world.w, game.sim.world.h) * Defs.TILE
		var is_click := event is InputEventMouseButton
		if territory_mode and is_click and not game.picking:
			game.select_state(game.sim.states.at(game.sim.world.tile_of(wp)))
			accept_event()
			return
		if game.picking and (not is_click or size.x < 300.0):
			game.camera.position = wp      # the small minimap only pans while choosing
		else:
			game.map_clicked(wp)
	accept_event()
