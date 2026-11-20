extends Node2D
## Game scene controller: builds the world view, lets the player choose a starting location,
## steps the simulation, handles input, day/night lighting, seasonal visuals, campfire lights,
## saving and loading.

const MAX_STEP := 0.1   # largest simulation step (real seconds × speed)

var sim: Sim
var terrain: TerrainView
var resources: ResourceLayer
var entities: EntityLayer
var camera: CameraController
var canvas_mod: CanvasModulate
var hud: HUD
var fog_sprite: Sprite2D
var weather_overlay: WeatherOverlay
var light_root: Node2D
var lights := {}            # building id -> PointLight2D

var speed := 1.0
var paused := false
var menu_paused := false
var spectating := false      # the player's tribe is gone: watch only
var picking := false        # choosing where the tribe starts
var reveal_all := true      # all tribes are shown on maps (flags are visible from above)
var selected_human_id := -1
var selected_building_id := -1
var selected_ids: Array = []     # your people under command
var selected_ship_id := -1
var selected_civ_id := -1        # a tribe picked by clicking its flag (diplomacy)
var selected_state := -1         # a territory state picked on the Territory map
var _cheat_presses: Array = []   # times of recent Shift+Plus presses
var _light_mix := 1.0            # 1 = showing the day/night cycle, 0 = frozen at daylight
var tool_mode := ""              # "clear": drag a box to clear land
var clear_dragging := false
var clear_start := Vector2.ZERO
var dragging := false
var drag_start := Vector2.ZERO
var order_marker := Vector2.ZERO
var order_marker_col := Color.WHITE
var order_marker_t := 0.0
var build_mode := ""
var hover_tile := Vector2i(-1, -1)
var place_tile := Vector2i(-1, -1)
var view_rect := Rect2()

var _season_shown := -1
var _pending_events: Array = []
var _ready_done := false
var _args: PackedStringArray


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	for a in _args:
		if a.begins_with("--seed="):
			Config.seed_value = int(a.substr(7))
		if a == "--earth":
			Config.earth_mode = true
	var loading_layer := CanvasLayer.new()
	add_child(loading_layer)
	var lbl := Label.new()
	lbl.text = "Generating world…"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_layer.add_child(lbl)
	await get_tree().process_frame
	await get_tree().process_frame

	sim = Sim.new()
	sim.event.connect(_on_event)
	sim.tile_changed.connect(_on_tile_changed)
	sim.buildings_changed.connect(_sync_lights)
	var cam_data: Array = []
	if _args.has("--loadtest"):
		Config.load_slot = 2
	var loaded := false
	if Config.load_slot >= 0:
		var d := SaveSystem.load_data(Config.load_slot)
		Config.load_slot = -1
		if d.is_empty():
			_pending_events.append(["That save could not be read — starting a new world.", "bad"])
		else:
			sim.from_dict(d)
			cam_data = d.get("camera", [])
			loaded = true
			_pending_events.append(["Game loaded. Welcome back.", "good"])
	if not loaded:
		sim.new_world(Config.seed_value, Config.world_size, Config.earth_mode)
	_build_scene(cam_data)
	loading_layer.queue_free()
	_ready_done = true
	if not loaded:
		_begin_picking()
	if _args.has("--autotest"):
		_autotest()
	elif _args.has("--shots"):
		_shots()
	elif _args.has("--earthshots"):
		_earth_shots()
	elif _args.has("--forgeshot"):
		_forge_shot()
	elif _args.has("--cmdtest"):
		_cmdtest()


func _build_scene(cam_data: Array) -> void:
	var T := float(Defs.TILE)
	terrain = TerrainView.new()
	add_child(terrain)
	resources = ResourceLayer.new()
	add_child(resources)
	light_root = Node2D.new()
	add_child(light_root)
	entities = EntityLayer.new()
	entities.game = self
	add_child(entities)
	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.scale = Vector2(T, T)
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(fog_sprite)
	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)
	camera = CameraController.new()
	camera.bounds = Rect2(0, 0, sim.world.w * T, sim.world.h * T)
	add_child(camera)
	camera.make_current()

	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 5
	add_child(weather_layer)
	weather_overlay = WeatherOverlay.new()
	weather_overlay.game = self
	weather_layer.add_child(weather_overlay)

	hud = HUD.new()
	add_child(hud)
	hud.setup(self)

	terrain.build(sim.world)
	for t in terrain.apply_snow(sim):
		sim.paths.refresh_tile(t)
	resources.build(sim.world)
	resources.set_season(sim.time.season())
	_season_shown = sim.time.season()
	hud.rebuild_maps()
	_sync_lights()

	if cam_data.size() >= 3:
		camera.position = Vector2(float(cam_data[0]), float(cam_data[1]))
		camera.target_zoom = float(cam_data[2])
		camera.zoom = Vector2(camera.target_zoom, camera.target_zoom)
	else:
		camera.position = sim.world.center_of(sim.colony.home)
	for e in _pending_events:
		hud.push_event(e[0], e[1])
	_pending_events.clear()


# ================================================================ choosing the start
func _begin_picking() -> void:
	picking = true
	camera.target_zoom = 0.9
	camera.position = sim.world.center_of(sim.world.spawn)
	hud.show_picker(true)


## Called for clicks on the world or on a map while choosing a start.
func try_start_at(t: Vector2i) -> void:
	var err := sim.start_problem(t)
	if err != "":
		hud.push_event(err, "warn")
		return
	sim.found_tribes(t, Config.ai_tribes)
	picking = false
	hud.show_picker(false)
	camera.position = sim.world.center_of(t)
	camera.target_zoom = 2.2
	hud.rebuild_maps()
	_sync_lights()


func use_suggested_start() -> void:
	try_start_at(sim.world.spawn)


## Clicks on the minimap / world map land here.
func map_clicked(world_pos: Vector2) -> void:
	if picking:
		try_start_at(sim.world.tile_of(world_pos))
	else:
		camera.position = world_pos


# ================================================================ frame loop
func _process(delta: float) -> void:
	if not _ready_done:
		return
	var vs := get_viewport_rect().size / camera.zoom
	view_rect = Rect2(camera.get_screen_center_position() - vs * 0.5, vs)
	var T := float(Defs.TILE)
	sim.active_rect = Rect2i(floori(view_rect.position.x / T) - 20, floori(view_rect.position.y / T) - 20,
		ceili(view_rect.size.x / T) + 40, ceili(view_rect.size.y / T) + 40)
	hover_tile = sim.world.tile_of(get_global_mouse_position())
	var ft: Texture2D = sim.fog.texture if sim.fog.on else null
	if fog_sprite.texture != ft:
		fog_sprite.texture = ft
	if build_mode != "":
		var sz: Vector2i = Defs.BUILDINGS[build_mode]["size"]
		place_tile = hover_tile - Vector2i(sz.x / 2, sz.y / 2)

	if sim.started and not paused and not menu_paused and sim.colony.population() > 0:
		var turbo := 1.0
		for a in _args:
			if a == "--turbo":
				turbo = 8.0
			elif a.begins_with("--turbo="):
				turbo = float(a.substr(8))
		var total := minf(delta, 0.1) * speed * turbo
		if total > 0.0:
			sim.play_secs += minf(delta, 0.1) * turbo        # real play time (diplomacy waits)
			var steps := ceili(total / MAX_STEP)
			var dt := total / steps
			for i in steps:
				sim.step(dt)

	if sim.time.season() != _season_shown:
		_on_season_visual()
	# day/night: hidden (constant daylight) when switched off or when zoomed in close
	var want := 0.0 if Settings.hide_day_night(camera.zoom.x, speed) else 1.0
	_light_mix = move_toward(_light_mix, want, delta * 2.0)
	canvas_mod.color = Color(1, 1, 1).lerp(sim.time.light_color(), _light_mix)
	# resource sprites fade out when zoomed far out so the map stays readable
	var z := camera.zoom.x
	terrain.set_zoom(z)
	resources.visible = z > 0.55
	resources.modulate.a = clampf((z - 0.55) / 0.5, 0.0, 1.0)
	_update_lights()
	order_marker_t = maxf(0.0, order_marker_t - delta * 1.5)
	if sim.started and (sim.colony.population() == 0 or sim.colony.collapsed) and not spectating:
		hud.show_game_over()


func _on_season_visual() -> void:
	_season_shown = sim.time.season()
	for t in terrain.apply_snow(sim):
		sim.paths.refresh_tile(t)
	resources.set_season(_season_shown)
	hud.rebuild_maps()


func _on_event(text: String, kind: String) -> void:
	if hud == null:
		_pending_events.append([text, kind])
	else:
		hud.push_event(text, kind)


func _on_tile_changed(t: Vector2i) -> void:
	if resources != null:
		resources.tile_changed(t)


# ================================================================ lights
func _sync_lights() -> void:
	if light_root == null:
		return
	var alive_ids := {}
	for c in sim.colonies:
		for b in c.buildings:
			if b.type == "campfire":
				alive_ids[b.id] = true
				if not lights.has(b.id):
					var l := PointLight2D.new()
					l.texture = Art.light_tex
					l.texture_scale = 1.3
					l.color = Color(1.0, 0.7, 0.4)
					l.position = b.center()
					l.energy = 0.0
					light_root.add_child(l)
					lights[b.id] = l
	for id in lights.keys():
		if not alive_ids.has(id):
			lights[id].queue_free()
			lights.erase(id)


func _update_lights() -> void:
	var dark := sim.time.darkness() * _light_mix
	var t := Time.get_ticks_msec() / 1000.0
	for id in lights.keys():
		var b := sim.building(int(id))
		var l: PointLight2D = lights[id]
		if b == null or not b.is_lit():
			l.energy = 0.0
			continue
		var flicker := 1.0 + sin(t * 9.0 + id) * 0.06 + sin(t * 23.0 + id * 2.0) * 0.04
		l.energy = (0.25 + dark * 1.1) * flicker


# ================================================================ input
func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.shift_pressed and (k.keycode == KEY_PLUS or k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD):
			_cheat_key()
			return
		if (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_Z:
			if k.shift_pressed:
				plan_redo()
			else:
				plan_undo()
			return
		if (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_Y:
			plan_redo()
			return
		if spectating and not k.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_M, KEY_H, KEY_F9]:
			return
		match k.keycode:
			KEY_ESCAPE:
				if tool_mode != "":
					set_tool("")
				elif build_mode != "":
					cancel_build()
				elif hud.worldmap_panel.visible:
					hud.toggle_worldmap()
				elif hud.is_panel_open():
					hud.close_panel()
				else:
					hud.toggle_pause_menu()
			KEY_SPACE:
				set_speed(0.0 if not paused else speed)
			KEY_1:
				set_speed(1.0)
			KEY_2:
				set_speed(2.0)
			KEY_3:
				set_speed(4.0)
			KEY_4:
				set_speed(8.0)
			KEY_5:
				set_speed(16.0)
			KEY_6:
				set_speed(32.0)
			KEY_R:
				if not picking:
					hud.toggle_panel("research")
			KEY_B:
				if not picking:
					hud.toggle_build_window()
			KEY_J:
				if not picking:
					hud.toggle_panel("jobs")
			KEY_I:
				hud.toggle_panel("stock")
			KEY_C:
				hud.toggle_panel("colony")
			KEY_H:
				hud.toggle_panel("help")
			KEY_M:
				hud.toggle_worldmap()
			KEY_X:
				if not picking:
					set_tool("" if tool_mode == "clear" else "clear")
			KEY_Z:
				if not picking:
					hud.toggle_planner()
			KEY_K:
				hud.toggle_forge()
			KEY_G:
				hud.toggle_panel("milestones")
			KEY_F5:
				if sim.started and save_slot(0):
					hud.push_event("Quick-saved to slot 1.", "good")
			KEY_F9:
				load_slot(0)
			KEY_DELETE:
				demolish_selected()
		return
	if menu_paused:
		return
	if spectating and event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return                   # watching only: no selecting, ordering or building
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var gmp := get_global_mouse_position()
		if tool_mode != "" and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				clear_start = gmp
				clear_dragging = true
			elif clear_dragging:
				clear_dragging = false
				if tool_mode == "clear":
					_apply_clear(clear_rect(), Input.is_key_pressed(KEY_SHIFT))
				else:
					_apply_plan(clear_start, gmp)
			return
		if tool_mode != "" and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			set_tool("")
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if picking:
					try_start_at(hover_tile)
				elif build_mode != "":
					_try_place()
				else:
					drag_start = gmp
					dragging = true
			elif dragging:
				dragging = false
				if drag_start.distance_to(gmp) * camera.zoom.x > 8.0:
					_box_select(Rect2(drag_start, gmp - drag_start).abs(), Input.is_key_pressed(KEY_SHIFT))
				else:
					_select_at(gmp, Input.is_key_pressed(KEY_SHIFT))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if build_mode != "":
				cancel_build()
			elif selected_ship_id >= 0:
				_command_ship(gmp)
			elif not selected_ids.is_empty():
				_command(gmp, Input.is_key_pressed(KEY_SHIFT))
			else:
				clear_selection()


## Shift + Plus five times within two seconds toggles cheat mode.
func _cheat_key() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_cheat_presses.append(now)
	while not _cheat_presses.is_empty() and now - float(_cheat_presses[0]) > 2.0:
		_cheat_presses.pop_front()
	if _cheat_presses.size() >= 5:
		_cheat_presses.clear()
		sim.toggle_cheats(sim.colony)
		hud.refresh_build_window()


func select_state(st: int) -> void:
	clear_selection()
	selected_state = st


func select_civ(cid: int) -> void:
	clear_selection()
	selected_civ_id = cid


func clear_selection() -> void:
	selected_ids.clear()
	selected_human_id = -1
	selected_building_id = -1
	selected_ship_id = -1
	selected_civ_id = -1
	selected_state = -1


func set_tool(t: String) -> void:
	tool_mode = t
	clear_dragging = false
	if t != "":
		cancel_build()
	if t == "clear":
		hud.push_event("Clear land: drag a box over trees, bushes, stones or animals. Shift+drag removes marks. Right-click or Esc to stop.", "info")


## Tiles of an L-shaped road from a to b (along x first, then y).
func road_tiles_between(a: Vector2, b: Vector2) -> Array:
	var t0 := sim.world.tile_of(a)
	var t1 := sim.world.tile_of(b)
	var out: Array = []
	var sx := 1 if t1.x >= t0.x else -1
	for x in range(t0.x, t1.x + sx, sx):
		out.append(Vector2i(x, t0.y))
	var sy := 1 if t1.y >= t0.y else -1
	for y in range(t0.y + sy, t1.y + sy, sy):
		out.append(Vector2i(t1.x, y))
	return out


# ---------------------------------------------------------------- town planner undo / redo
var plan_undo_stack: Array = []
var plan_redo_stack: Array = []


func _plan_state() -> Dictionary:
	var c := sim.colony
	return {"z": c.zones.duplicate(), "r": c.road_marks.duplicate(), "w": c.wreck_marks.duplicate(), "c": c.clear_marks.duplicate()}


func _set_plan_state(st: Dictionary) -> void:
	var c := sim.colony
	c.zones = (st["z"] as Dictionary).duplicate()
	c.road_marks = (st["r"] as Dictionary).duplicate()
	c.wreck_marks = (st["w"] as Dictionary).duplicate()
	c.clear_marks = (st["c"] as Dictionary).duplicate()
	sim.refresh_zones(c)


func plan_undo() -> void:
	if plan_undo_stack.is_empty():
		hud.push_event("Nothing to undo in the town plan.", "info")
		return
	var e: Dictionary = plan_undo_stack.pop_back()
	_set_plan_state(e["before"])
	for r in e["removed"]:
		sim.restore_road_tile(int(r[0]), int(r[1]))
	plan_redo_stack.append(e)
	hud.push_event("Undid: %s  (Ctrl+Y to redo)" % e["what"], "info")


func plan_redo() -> void:
	if plan_redo_stack.is_empty():
		hud.push_event("Nothing to redo in the town plan.", "info")
		return
	var e: Dictionary = plan_redo_stack.pop_back()
	_set_plan_state(e["after"])
	for r in e["removed"]:
		sim.remove_road_tile(int(r[0]))
	plan_undo_stack.append(e)
	hud.push_event("Redid: %s" % e["what"], "info")


## Applies a zone, road or road-removal drag from the town planner (undoable).
func _apply_plan(a: Vector2, b: Vector2) -> void:
	var before := _plan_state()
	sim.last_removed_roads = []
	_apply_plan_inner(a, b)
	var after := _plan_state()
	var removed: Array = sim.last_removed_roads.duplicate() if tool_mode == "unroad" else []
	if after.hash() == before.hash() and removed.is_empty():
		return
	var what := "road plan"
	if tool_mode.begins_with("zone"):
		what = "erase zone" if tool_mode == "zone0" else "%s zone" % Defs.ZONES[int(tool_mode.substr(4))]["name"]
	elif tool_mode == "unroad":
		what = "remove roads"
	plan_undo_stack.append({"before": before, "after": after, "removed": removed, "what": what})
	if plan_undo_stack.size() > 60:
		plan_undo_stack.pop_front()
	plan_redo_stack.clear()


func _apply_plan_inner(a: Vector2, b: Vector2) -> void:
	var c := sim.colony
	if tool_mode.begins_with("zone"):
		var z := int(tool_mode.substr(4))
		var n := sim.paint_zone(c, sim.world.tile_of(a), sim.world.tile_of(b), z)
		if z == 0:
			hud.push_event("Erased %d zoned tiles." % n, "info")
		elif n > 0:
			hud.push_event("Painted %d tiles as a %s zone." % [n, Defs.ZONES[z]["name"]], "info")
	elif tool_mode == "road":
		var n := sim.plan_road(c, road_tiles_between(a, b))
		if n > 0:
			hud.push_event("Planned %d tiles of road. Laborers and builders will lay it (trees in the way get cleared first)." % n, "info")
	elif tool_mode == "unroad":
		var n := sim.remove_roads(c, sim.world.tile_of(a), sim.world.tile_of(b))
		var wr := c.wreck_marks.size()
		hud.push_event("Removed %d road tiles%s." % [n, (" (enemy roads are marked: your soldiers and laborers will tear them up)" if wr > 0 else "")], "info")


## Rectangle of the clearing box being dragged (world pixels).
func clear_rect() -> Rect2:
	return Rect2(clear_start, get_global_mouse_position() - clear_start).abs()


## Marks every plant and loose stone in the box for clearing (ore deposits stay), and every
## animal in it for the hunters. Shift removes marks instead.
func _apply_clear(r: Rect2, remove: bool) -> void:
	var t0 := sim.world.tile_of(r.position)
	var t1 := sim.world.tile_of(r.end)
	var n := 0
	for y in range(t0.y, t1.y + 1):
		for x in range(t0.x, t1.x + 1):
			var q := Vector2i(x, y)
			if not sim.world.inb(q):
				continue
			var i := sim.world.idx(q)
			var rt := sim.world.res_type[i]
			if remove:
				if sim.colony.clear_marks.erase(i):
					n += 1
				continue
			if rt == Defs.R.NONE or (rt >= Defs.R.COPPER_ORE and rt <= Defs.R.IRON_ORE):
				continue
			if not sim.colony.clear_marks.has(i):
				sim.colony.clear_marks[i] = true
				n += 1
	var na := 0
	for a in sim.animals:
		if a.alive and r.has_point(a.pos):
			if remove:
				sim.colony.hunt_marks.erase(a.id)
			else:
				sim.colony.hunt_marks[a.id] = true
				na += 1
	if remove:
		hud.push_event("Removed %d clearing marks." % n, "info")
	elif n + na > 0:
		var txt := "Marked %d tiles to clear" % n
		if na > 0:
			txt += " and %d animals to hunt" % na
		hud.push_event(txt + ". Woodcutters, gatherers, laborers and builders will see to it.", "info")


## The tribe whose camp flag is under the cursor (for diplomacy), or null.
func _pick_flag(world_pos: Vector2) -> Colony:
	var k := clampf(1.0 / camera.zoom.x, 0.45, 6.0)
	for c in sim.colonies:
		if c.collapsed or c.bandit:
			continue
		if sim.fog.on and c.civ_id != 0 and not sim.fog.is_explored(c.home):
			continue
		var base := sim.world.center_of(c.home) + Vector2(-Defs.TILE * 1.5, -Defs.TILE)
		var top := base + Vector2(0, -34.0 * k)
		var r := Rect2(top - Vector2(4, 2) * k, Vector2(28.0, 18.0) * k).merge(Rect2(top, Vector2(4.0 * k, 34.0 * k)))
		if r.has_point(world_pos):
			return c
	return null


func _pick_human(world_pos: Vector2) -> Human:
	var best: Human = null
	var best_d := pow(10.0 / camera.zoom.x + 6.0, 2)
	for p in sim.people_all:
		if not p.alive or p.aboard >= 0:
			continue
		var d: float = (p.pos + Vector2(0, -3)).distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func _pick_animal(world_pos: Vector2) -> Animal:
	var best: Animal = null
	var best_d := pow(12.0 / camera.zoom.x + 6.0, 2)
	for a in sim.animals:
		if not a.alive or a.def().get("flying", false):
			continue
		var d: float = a.pos.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


func _pick_ship(world_pos: Vector2) -> Ship:
	for sh in sim.ships:
		if sh.pos.distance_to(world_pos) < 14.0 / minf(camera.zoom.x, 1.0) + 6.0:
			return sh
	return null


func _select_at(world_pos: Vector2, add: bool) -> void:
	if sim.fog.on and not sim.fog.is_explored(sim.world.tile_of(world_pos)):
		if not add:
			clear_selection()
		return
	var fc := _pick_flag(world_pos)
	if fc != null and not add:
		clear_selection()
		selected_civ_id = fc.civ_id
		return
	var best := _pick_human(world_pos)
	if not add:
		clear_selection()
	if best != null:
		selected_human_id = best.id
		if best.civ_id == 0 and not selected_ids.has(best.id):
			selected_ids.append(best.id)
		return
	var sh := _pick_ship(world_pos)
	if sh != null:
		selected_ids.clear()
		selected_ship_id = sh.id
		return
	var b := sim.building_at(sim.world.tile_of(world_pos))
	if b != null:
		selected_building_id = b.id


## Drag a box with the left mouse button to select several of your people.
func _box_select(r: Rect2, add: bool) -> void:
	if not add:
		clear_selection()
	for p in sim.colony.living():
		if p.aboard < 0 and r.has_point(p.pos) and not selected_ids.has(p.id):
			selected_ids.append(p.id)
	if not selected_ids.is_empty():
		selected_human_id = selected_ids[0]


## Right-click with people selected: move there, board a ship, or (Shift) attack what's under the cursor.
func _command(world_pos: Vector2, attack: bool) -> void:
	var people: Array = []
	for pid in selected_ids:
		var p := sim.person(int(pid))
		if p != null and p.alive and p.aboard < 0:
			people.append(p)
	if people.is_empty():
		return
	if attack:
		var target_h := _pick_human(world_pos)
		if target_h != null and target_h.civ_id != 0:
			for p in people:
				HumanAI.order_attack(sim, p, "human", target_h.id)
			_mark_order(target_h.pos, Color(1, 0.3, 0.25))
			return
		var target_a := _pick_animal(world_pos)
		if target_a != null:
			for p in people:
				HumanAI.order_attack(sim, p, "animal", target_a.id)
			_mark_order(target_a.pos, Color(1, 0.3, 0.25))
			return
		var target_b := sim.building_at(sim.world.tile_of(world_pos))
		if target_b != null and target_b.civ_id != 0:
			for p in people:
				HumanAI.order_attack(sim, p, "building", target_b.id)
			_mark_order(target_b.center(), Color(1, 0.3, 0.25))
			return
	var sh := _pick_ship(world_pos)
	if sh != null and sh.civ_id == 0:
		var boarded := 0
		for p in people:
			if HumanAI.order_board(sim, p, sh):
				boarded += 1
		_mark_order(sh.pos, Color(0.5, 0.8, 1.0))
		if boarded < people.size():
			hud.push_event("The %s only has room for %d." % [sh.label(), sim.ship_capacity(sh)], "warn")
		return
	# move in a loose formation around the clicked tile
	var center := sim.world.tile_of(world_pos)
	var spots := _formation(center, people.size())
	for i in people.size():
		HumanAI.order_move(sim, people[i], spots[i])
	_mark_order(world_pos, Color(0.5, 1.0, 0.5))


func _formation(center: Vector2i, n: int) -> Array:
	var out: Array = []
	var r := 0
	while out.size() < n and r < 12:
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if maxi(absi(ox), absi(oy)) != r or out.size() >= n:
					continue
				var t := center + Vector2i(ox, oy)
				if sim.world.walkable(t):
					out.append(t)
		r += 1
	while out.size() < n:
		out.append(center)
	return out


func _command_ship(world_pos: Vector2) -> void:
	var sh := sim.ship(selected_ship_id)
	if sh == null or sh.civ_id != 0:
		selected_ship_id = -1
		return
	var err := sim.sail_to(sh, sim.world.tile_of(world_pos))
	if err != "":
		hud.push_event(err, "warn")
	else:
		_mark_order(world_pos, Color(0.5, 0.8, 1.0))


func _mark_order(at: Vector2, col: Color) -> void:
	order_marker = at
	order_marker_col = col
	order_marker_t = 1.0


func select_human(pid: int, focus := false) -> void:
	clear_selection()
	selected_human_id = pid
	var p := sim.person(pid)
	if p != null and p.civ_id == 0:
		selected_ids.append(pid)
	if focus and p != null:
		camera.position = p.pos


func _try_place() -> void:
	var err := sim.can_place(sim.colony, build_mode, place_tile)
	if err != "":
		hud.push_event(err, "warn")
		return
	var b := sim.place_building(sim.colony, build_mode, place_tile)
	if b != null:
		if b.type == "wall" or b.type == "gate":
			b.tier = sim.colony.best_wall_tier()
		hud.push_event("Blueprint placed: %s. Your people will bring %s and build it." % [b.display_name(), Defs.cost_text(b.cost())], "info")
	if not (build_mode == "fence" or build_mode == "wall" or Input.is_key_pressed(KEY_SHIFT)):
		cancel_build()


# ================================================================ actions used by the HUD
func set_speed(s: float) -> void:
	if s <= 0.0:
		paused = true
	else:
		paused = false
		speed = s


func start_build(type: String) -> void:
	build_mode = type
	hud.close_panel()


func cancel_build() -> void:
	build_mode = ""


func demolish_selected() -> void:
	if selected_building_id < 0:
		return
	var b := sim.building(selected_building_id)
	if b != null and b.civ_id == 0:
		sim.demolish(b)
		hud.push_event("%s demolished." % b.def()["name"], "info")
	elif b != null:
		hud.push_event("That belongs to the %s — you can't tear it down." % sim.civ(b.civ_id).name, "warn")
	selected_building_id = -1
	_sync_lights()


func save_slot(slot: int) -> bool:
	if not sim.started:
		return false
	return SaveSystem.save(slot, sim, camera.position, camera.target_zoom)


func load_slot(slot: int) -> void:
	if SaveSystem.info(slot).is_empty():
		hud.push_event("Slot %d is empty." % (slot + 1), "warn")
		return
	Config.load_game(slot)
	get_tree().reload_current_scene()


func go_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================================================================ headless smoke test
## `godot --headless res://scenes/game.tscn -- --autotest [--turbo] [--loadtest]`
## Test: jump every tribe to the Bronze Age with an army's worth of people and materials, make
## the rivals aggressive, and watch walls, weapons, soldiers, wars and raids play out.
func _setup_wartest() -> void:
	Config.rules["ai_aggression"] = 3.0
	for c in sim.colonies:
		c.era_i = 2
		c.era = Defs.ERAS[2]
		for e in [0, 1]:
			for id in Defs.techs_of_era(e):
				c.researched[id] = true
		for id in ["stone_walls", "watch_posts", "statecraft", "cartography", "irrigation"]:
			c.researched[id] = true
		c.invalidate_bonus()
		for k in ["wood", "stone", "sticks", "grass"]:
			c.add(k, 400)
		c.add("copper_ore", 40)
		c.add("tin_ore", 30)
		c.add("hides", 30)
		c.add("dried_meat", 300)
		c.add("water", 30)
		for k in 8:
			var pp := sim._make_human(c, "M" if k % 2 == 0 else "F", 20.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(sim.rng.randf_range(-20, 20), sim.rng.randf_range(-20, 20)))
			pp.job = "laborer"
		c.gov_pending = true
	# everyone knows everyone and dislikes them
	for a in sim.colonies:
		for b in sim.colonies:
			if a.civ_id < b.civ_id:
				var k: String = sim._key(a.civ_id, b.civ_id)
				sim.contacts[k] = true
				sim.relations[k] = -70.0


func lbp_clear(c: Colony) -> void:
	for q in c.living():
		q.carrying.erase("log")


## Lumber yard, lumberers, regrowing trees, waits, tech announcements: `-- --autotest --lumbertest`
func _lumber_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		Config.rules["tree_regrow_days"] = 3.0
		c.researched["lumbering"] = true
		c.add("wood", 100)
		c.add("stone", 50)
		var site := CivAI.find_site(sim, c, "lumber_yard")
		var y := sim.place_building(c, "lumber_yard", site)
		sim.finish_building(y)
		c.auto_jobs = false
		var lb: Human = c.living()[0]
		lb.job = "lumberer"
		lb.task = {}
		_nt["sticks0"] = c.count("sticks")
		print("LT yard at ", site, " lumberer=", lb.name, " allowed=", c.job_allowed("lumberer"))
		# a road and a building on stumps: those trees must not come back
		var tt := sim.world.find_resource(c.home + Vector2i(6, 6), 30, {Defs.R.TREE: true, Defs.R.PINE: true}, sim.claims)
		if tt.x >= 0:
			var ti := sim.world.idx(tt)
			sim.note_stump(ti, sim.world.res_type[ti])
			sim.world.res_type[ti] = Defs.R.NONE
			sim.world.road[ti] = 1
			sim.road_tiles[ti] = 0
			_nt["road_stump"] = ti
		# waits
		print("LT wait before=", Deals.wait_left(sim, 0, 1, "alliance"), " propose=", Deals.player_propose(sim, 1, "alliance"), " second='", Deals.player_propose(sim, 1, "alliance"), "' left=", int(Deals.wait_left(sim, 0, 1, "alliance")))
		# tech announcement
		c.research_points = 999
		for id in Defs.techs_of_era(0):
			if c.tech_available(id) and c.can_afford_tech(id):
				c.research(id)
				break
	if i >= 3 and i <= 25 and i % 2 == 1:
		var lb: Human = null
		for q in c.living():
			if q.job == "lumberer":
				lb = q
		print("LT t%d lumberer=%s carry=%s sticks=+%d stumps=%d logs=%d road_stump_back=%s" % [i, lb.state if lb != null else "-", lb.carrying if lb != null else {}, int(c.count("sticks") - float(_nt["sticks0"])),
			sim.stumps.size(), int(c.count("log")), str(sim.world.res_type[int(_nt.get("road_stump", 0))] != Defs.R.NONE)])


## Round H: custom weapons, Easy Birth, spectating, Earth: `-- --autotest --htest [--earth]`
var _ht := {}
func _h_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		if sim.world.earth:
			var counts := {}
			for t in sim.world.terrain:
				var nm: String = Defs.TERRAIN[t]["name"]
				counts[nm] = int(counts.get(nm, 0)) + 1
			print("HT earth %dx%d: %s" % [sim.world.w, sim.world.h, counts])
			for place in [["London", 51.5, -0.1], ["Cairo", 30.0, 31.2], ["Amazon", -3.0, -60.0], ["Sahara", 23.0, 10.0], ["Himalaya", 28.0, 86.0], ["Siberia", 62.0, 100.0], ["Caspian", 42.0, 50.5], ["Atlantic", 30.0, -40.0], ["Iowa", 42.0, -93.5], ["Outback", -25.0, 132.0], ["Greenland", 75.0, -40.0]]:
				var q := EarthGen.latlon_to_tile(sim.world, place[1], place[2])
				print("HT  %s -> %s" % [place[0], Defs.TERRAIN[sim.world.t_at(q)]["name"]])
			print("HT tribes at: ", sim.colonies.map(func(o): return EarthGen.tile_to_latlon(sim.world, o.home).round()))
		# a custom weapon: design, save, forge, use
		c.researched["smithing_bench"] = true
		var d := Smithing.starter("spear")
		var id := Smithing.save_design(sim, d)
		print("HT design ", id, " ", Defs.weapon(id))
		var bad := Smithing.starter("longsword")
		print("HT longsword needs level ", Smithing.evaluate(bad)["level"], " we have ", Smithing.level(c))
		for k in ["wood", "stone", "hides", "bones"]:
			c.add(k, 50)
		var site := CivAI.find_site(sim, c, "smithing_bench")
		var b := sim.place_building(c, "smithing_bench", site)
		sim.finish_building(b)
		c.weapon_orders.append(id)
		c.weapon_orders.append(id)
		for k in 3:
			sim._make_human(c, "M" if k % 2 == 0 else "F", (22.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 4, 6))
		var sm: Human = c.living().filter(func(q): return q.is_adult())[0]
		sm.job = "smith"
		_ht["id"] = id
		_ht["smith"] = sm.id
		# Easy Birth: every woman in the world, followed over time
		_ht["women"] = {}
	if i == 17:
		print("HT game over shown=%s" % hud.gameover_shown)
		hud.start_spectating()
		print("HT spectating=%s, visible tool buttons=%s" % [spectating, hud.toolbar_box.get_children().filter(func(b): return b.visible).map(func(b): return b.text)])
	if i == 18:
		print("HT world still running after the end: day %d, tribes alive %d" % [sim.time.day(), sim.colonies.filter(func(o): return not o.collapsed and not o.bandit and o.population() > 0).size()])
	if i >= 3 and i % 3 == 0:
		var id2 := str(_ht.get("id", ""))
		var owed := 0
		var due := 0
		var women := 0
		var births := 0
		for oc in sim.colonies:
			if oc.collapsed or oc.bandit:
				continue
			for q in oc.living():
				if q.gender == "F" and q.age_years() >= 18.0:
					women += 1
					if q.pregnant_days >= 0.0:
						_ht["preg"] = int(_ht.get("preg", 0)) + 1
					births += q.births
					if q.births < Survival.easy_birth_required(oc) and q.age_years() < 45.0:
						owed += 1
						if Survival.easy_birth_due(oc, q, oc.population(), oc.housing()):
							due += 1
		var pops := sim.colonies.filter(func(o): return not o.collapsed and not o.bandit).map(func(o): return o.population())
		var sm2 := sim.person(int(_ht.get("smith", -1)))
		print("HT t%d: stock of %s = %d, orders %d, smith=%s | women %d, births %d, owed %d (due %d) pregnant-samples %d | pops %s" % [i, id2, int(c.count(id2)), c.weapon_orders.size(),
			sm2.state if sm2 != null else "-", women, births, owed, due, int(_ht.get("preg", 0)), pops])
		_ht["preg"] = 0
		if i == 9 and c.count(id2) >= 1.0:
			# arm a fighter and check damage against a person and an animal
			var f: Human = c.living().filter(func(q): return q.is_adult())[0]
			c.take(id2, 1)
			f.weapon = id2
			print("HT armed %s: vs people %.1f, vs animals %.1f (unarmed vs animals %.1f), reach %.2f" % [f.name, HumanAI.strike_damage(sim, f, false),
				HumanAI.strike_damage(sim, f, true), 10.0 + f.skill("hunter") + c.bonus("hunt_dmg"), HumanAI.weapon_reach(f)])
		if i == 15:
			for q in c.living():
				sim.kill(q, "test")
		if i == 12:
			save_slot(5)
			var s2 := Sim.new()
			s2.from_dict(SaveSystem.load_data(5))
			print("HT reload: earth=%s size %dx%d designs=%d weapon name=%s" % [s2.world.earth, s2.world.w, s2.world.h, s2.custom_weapons.size(), Defs.weapon(id2)["name"]])


## Round G: presets, killings and war, monthly war parties, conquest, leaders at home, leader
## answers unanswered questions, armor: `-- --autotest --gtest`
var _gt := {}
func _g_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		var saved := Config.rules.duplicate()
		for pn in Config.PRESETS.keys():
			Config.apply_preset(pn)
			print("GT preset %s: hunger=%.2f aggr=%.2f cal=%.1f work=%.2f people=%d" % [pn, Config.rule("hunger_rate"), Config.rule("ai_aggression"), Config.rule("calendar_speed"), Config.rule("work_speed"), int(Config.rule("start_people"))])
		Config.rules = saved
		var ais: Array = sim.colonies.filter(func(o): return o.civ_id != 0 and not o.bandit and not o.collapsed)
		var a: Colony = ais[0]
		var b: Colony = ais[1]
		# war chance from killings
		var wars := 0
		var lwars := 0
		for k in 400:
			sim.wars.erase(sim._key(a.civ_id, b.civ_id))
			Warfare.on_kill(sim, a.civ_id, b.civ_id, "Test", false, false)
			if sim.at_war(a.civ_id, b.civ_id):
				wars += 1
			sim.wars.erase(sim._key(a.civ_id, b.civ_id))
			Warfare.on_kill(sim, a.civ_id, b.civ_id, "Test", true, false)
			if sim.at_war(a.civ_id, b.civ_id):
				lwars += 1
		sim.wars.erase(sim._key(a.civ_id, b.civ_id))
		print("GT war after a killing: %d%%, after a leader killing: %d%%" % [wars / 4, lwars / 4])
		# conquest by killing the leader in a war
		for k in 4:
			sim._make_human(b, "M" if k % 2 == 0 else "F", (25.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(b.home) + Vector2(k * 4, 6))
		Elections.hold(sim, b, "test")
		sim.contacts[sim._key(a.civ_id, b.civ_id)] = true
		sim.declare_war(a.civ_id, b.civ_id, true)
		b.money = 77.0
		var bl := sim.person(b.leader_id)
		var ap: Human = a.living().filter(func(q): return q.is_adult())[0]
		var a_pop := a.population()
		var b_pop := b.population()
		var b_states := sim.states.owned_by(b.civ_id).size()
		var a_money := a.money
		print("GT leader of %s: %s; far tile allowed=%s; home allowed=%s" % [b.name, bl.name if bl != null else "none",
			HumanAI.leader_may_go(sim, bl, a.home) if bl != null else false, HumanAI.leader_may_go(sim, bl, b.home) if bl != null else false])
		if bl != null:
			bl.health = 1.0
			HumanAI.hit_human(sim, ap, bl, 50.0)
		print("GT conquest: %s collapsed=%s; %s pop %d -> %d (took %d), money %+d, states %d (+%d)" % [b.name, b.collapsed, a.name, a_pop, a.population(), b_pop - 1,
			int(a.money - a_money), sim.states.owned_by(a.civ_id).size(), b_states])
		# monthly war parties: you vs the nearest tribe
		var o: Colony = null
		for oc in sim.colonies:
			if oc.civ_id != 0 and not oc.bandit and not oc.collapsed and oc != a:
				o = oc
				break
		_gt["o"] = o.civ_id
		sim.contacts[sim._key(0, o.civ_id)] = true
		sim.declare_war(0, o.civ_id, true)
		sim.test_no_peace = true
		for k in 3:
			sim._make_human(c, "M", (24.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 4, 6))
			sim._make_human(o, "M", (24.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(o.home) + Vector2(k * 4, 6))
		sim.war_month = -1
		Warfare.daily(sim)
		var raiding := c.living().filter(func(q): return str(q.task.get("type", "")) == "raid").size()
		var their := o.living().filter(func(q): return str(q.task.get("type", "")) == "raid").size()
		print("GT war parties: ours %d marching, theirs %d marching (sent %d / %d)" % [raiding, their, c.war_parties_sent, o.war_parties_sent])
		# armor
		c.researched["hide_armor"] = true
		c.researched["wicker_shields"] = true
		c.invalidate_bonus()
		var fighter: Human = c.living().filter(func(q): return str(q.task.get("type", "")) == "raid")[0] if raiding > 0 else c.living()[0]
		print("GT armor tier %d, cut for a fighter %.2f, for a non-fighter %.2f" % [Warfare.armor_tier(c), Warfare.armor_cut(sim, fighter),
			Warfare.armor_cut(sim, c.living().filter(func(q): return not Warfare.is_fighter(q))[0])])
		# unanswered questions
		sim.access_asks.append(a.civ_id if not a.collapsed else o.civ_id)
		hud._refresh_passage()
		hud._tick_popups(10.0)
		var still := sim.access_asks.size()
		hud._tick_popups(25.0)
		print("GT passage ask open after 10s: %d, after 35s: %d" % [still, sim.access_asks.size()])
		var sick: Human = c.living()[0]
		Survival.infect(sim, sick, "plague", "test", true)
		sick.health = 20.0
		sim.exile_asks.append({"pid": sick.id})
		hud._refresh_exile()
		hud._tick_popups(31.0)
		print("GT exile ask left: %d, sick still in tribe: %s" % [sim.exile_asks.size(), c.person(sick.id) != null])
	if i > 2 and i % 4 == 0:
		var o2 := sim.civ(int(_gt.get("o", 1)))
		print("GT t%d: at war=%s, our raiders=%d, their raiders=%d, parties %d/%d, our pop %d, their pop %d, collapsed %s/%s" % [i, sim.at_war(0, o2.civ_id),
			c.living().filter(func(q): return str(q.task.get("type", "")) == "raid").size(), o2.living().filter(func(q): return str(q.task.get("type", "")) == "raid").size(),
			c.war_parties_sent, o2.war_parties_sent, c.population(), o2.population(), c.collapsed, o2.collapsed])


## Round F: road networks, allied road building, splits, civil war, sending the sick away,
## bonus buildings, trade range: `-- --autotest --ftest`
var _ft := {}
func _road_parts(civ_id: int) -> Array:
	# number of separate road pieces a tribe has, and its tile count
	var tiles := {}
	for k in sim.road_tiles.keys():
		if int(sim.road_tiles[k]) == civ_id:
			tiles[int(k)] = true
	var seen := {}
	var parts := 0
	for k in tiles.keys():
		if seen.has(k):
			continue
		parts += 1
		var stack: Array = [k]
		seen[k] = true
		while not stack.is_empty():
			var t: int = stack.pop_back()
			for d in [1, -1, sim.world.w, -sim.world.w]:
				var n: int = t + d
				if tiles.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
	return [parts, tiles.size()]


func _f_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		var o: Colony = null
		var bd := 1e9
		for oc in sim.colonies:
			if oc.civ_id != 0 and not oc.bandit and not oc.collapsed and sim.land_reachable(c, oc) and Vector2(oc.home).distance_to(Vector2(c.home)) < bd:
				bd = Vector2(oc.home).distance_to(Vector2(c.home))
				o = oc
		_ft["o"] = o.civ_id
		print("FT trade range ", Trade.max_range(c), " dist to nearest ", int(bd), " problem='", Trade.problem(sim, o.civ_id), "'")
		c.researched["pack_carts"] = true
		print("FT with wagons ", Trade.max_range(c))
		# bonus buildings: two count, a third is refused
		c.researched["spirit_lore"] = true
		c.add("wood", 500)
		c.add("stone", 500)
		c.add("bones", 100)
		c.add("hides", 100)
		var h0 := c.bonus("heal")
		for k in 3:
			var site := CivAI.find_site(sim, c, "shaman_circle")
			var why := sim.can_place(c, "shaman_circle", site)
			var b := sim.place_building(c, "shaman_circle", site) if why == "" else null
			if b != null:
				sim.finish_building(b)
			print("FT shaman circle #", k + 1, " placed=", b != null, " why='", why, "'")
		c.invalidate_bonus()
		print("FT heal bonus ", h0, " -> ", c.bonus("heal"))
		# alliance and a shared road
		sim.contacts[sim._key(0, o.civ_id)] = true
		Deals.make_alliance(sim, 0, o.civ_id)
		var n := CivAI.highway(sim, o, c)
		var n2 := CivAI.highway(sim, c, o)
		print("FT our highway to the ally: ", n2, " tiles, in their land: ", c.road_marks.keys().filter(func(k): return sim.states.owner_at(Vector2i(int(k) % sim.world.w, int(k) / sim.world.w)) == o.civ_id).size())
		print("FT highway planned by ", o.name, ": ", n, " tiles, in our land: ", o.road_marks.keys().filter(func(k): return sim.states.owner_at(Vector2i(int(k) % sim.world.w, int(k) / sim.world.w)) == 0).size())
		# splits need a man and a woman
		for k in 8:
			sim._make_human(o, "M" if k < 7 else "F", (20.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(o.home) + Vector2(k * 4, 6))
		var g := Politics.pick_group(sim, o.living().filter(func(q): return q.is_adult()), 4)
		print("FT split group genders: ", g.map(func(q): return q.gender))
		var men_only := o.living().filter(func(q): return q.is_adult() and q.gender == "M")
		print("FT men-only group: ", Politics.pick_group(sim, men_only, 4).size())
		# civil war in another tribe
		var cw: Colony = null
		for oc in sim.colonies:
			if oc.civ_id != 0 and oc != o and not oc.bandit and not oc.collapsed:
				cw = oc
				break
		if cw != null:
			for k in 10:
				sim._make_human(cw, "M" if k % 2 == 0 else "F", (20.0 + k * 2) * Defs.AGE_YEAR_DAYS, sim.world.center_of(cw.home) + Vector2(k * 4, 6))
			Elections.hold(sim, cw, "test")
			cw.approval = 5.0
			var before := sim.colonies.size()
			print("FT dislike share ", cw.name, " = ", Politics.dislike_share(sim, cw), " states=", sim.states.owned_by(cw.civ_id).size())
			Politics.civil_war(sim, cw)
			if sim.colonies.size() > before:
				var nw: Colony = sim.colonies[-1]
				print("FT civil war: ", cw.name, " pop ", cw.population(), " vs rebels ", nw.name, " pop ", nw.population(), " at_war=", sim.at_war(cw.civ_id, nw.civ_id), " rebel states=", sim.states.owned_by(nw.civ_id).size(), " rebel buildings=", nw.buildings.size())
			else:
				print("FT civil war did not start")
		# a badly sick person with something catching
		for k in 3:
			sim._make_human(c, "M" if k % 2 == 0 else "F", (22.0 + k) * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 4, 6))
		var sick: Human = c.living()[0]
		Survival.infect(sim, sick, "plague", "test", true)
		sick.health = 30.0
		for k in 30:
			Quarantine.hourly(sim, c)
		print("FT sick ", sick.name, " alive=", sick.alive, " cause=", sick.cause, " in tribe=", c.person(sick.id) != null, " sorrow=", c.exile_sorrow)
	if i >= 4 and i % 4 == 0:
		var line := "FT t%d roads:" % i
		for oc in sim.colonies:
			if oc.collapsed or oc.bandit:
				continue
			var rp := _road_parts(oc.civ_id)
			line += " %s=%d tiles/%d pieces" % [oc.name.substr(0, 8), rp[1], rp[0]]
		var helpers := 0
		for q in c.living():
			if str(q.state).contains(" with the "):
				helpers += 1
		var o2 := sim.civ(int(_ft.get("o", 1)))
		var theirs := 0
		for q in o2.living():
			if str(q.state).contains(" with the "):
				theirs += 1
		print(line, " | ally marks=", o2.road_marks.size(), " our helpers=", helpers, " their helpers=", theirs, " our marks=", c.road_marks.size(), " shared tiles laid=", sim.shared_road_tiles)


## Round E: AI roads, road wrecking, war structures, chronic conditions, sleeping indoors,
## planner undo/redo, world history: `-- --autotest --etest`
var _et := {}
func _e_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		var o: Colony = null
		var bd := 1e9
		for oc in sim.colonies:
			if oc.civ_id != 0 and not oc.bandit and Vector2(oc.home).distance_to(Vector2(c.home)) < bd:
				bd = Vector2(oc.home).distance_to(Vector2(c.home))
				o = oc
		_et["o"] = o.civ_id
		for k in ["wood", "stone", "hides", "copper_ore", "iron_ore"]:
			c.add(k, 300)
		for t in ["lookout_perches", "war_drums", "catapults", "bastions"]:
			c.researched[t] = true
		c.invalidate_bonus()
		for t in ["lookout_perch", "catapult", "war_drum_circle"]:
			var site := CivAI.find_site(sim, c, t)
			var b := sim.place_building(c, t, site)
			if b != null:
				sim.finish_building(b)
				_et[t] = b.id
			print("ET placed ", t, " at ", site, " ok=", b != null)
		print("ET soldier bonus=", c.bonus("soldier"), " siege=", c.bonus("siege"))
		# an enemy storehouse within catapult range, and an enemy road near our camp
		sim.contacts[sim._key(0, o.civ_id)] = true
		sim.declare_war(0, o.civ_id, true)
		var cat := sim.building(int(_et.get("catapult", -1)))
		if cat != null:
			for r in range(4, 13):
				var t2 := cat.tile + Vector2i(r, 2)
				print("ET enemy site ", t2, " '", sim.can_place(null, "storage", t2), "'")
				if sim.can_place(null, "storage", t2) == "":
					var eb := sim.place_building(o, "storage", t2)
					if eb != null:
						sim.finish_building(eb)
						_et["enemy_b"] = eb.id
						print("ET enemy storage hp ", eb.cur_hp())
						break
		var rt := road_tiles_between(sim.world.center_of(c.home + Vector2i(-8, 8)), sim.world.center_of(c.home + Vector2i(4, 8)))
		var laid := 0
		for q in rt:
			if sim.road_ok(q):
				sim.lay_road(o, sim.world.idx(q))
				laid += 1
		var n := sim.remove_roads(c, c.home + Vector2i(-8, 7), c.home + Vector2i(4, 9))
		print("ET enemy road laid=", laid, " marked=", n, " wreck_marks=", c.wreck_marks.size())
		# chronic conditions
		var ppl := c.living()
		ppl[0].conditions["dementia"] = 45.0
		ppl[0].age_days = 72.0 * Defs.AGE_YEAR_DAYS
		if ppl.size() > 1:
			ppl[1].conditions["dementia"] = 45.0
			ppl[1].age_days = 58.0 * Defs.AGE_YEAR_DAYS
			ppl[1].conditions["diabetes"] = 50.0
			ppl[1].conditions["obesity"] = 50.0
		_et["dem"] = ppl[1].id if ppl.size() > 1 else ppl[0].id
		print("ET dementia lvl=", ppl[0].dementia_level(), " harmful=", ppl[0].dementia_harmful(), " can_work=", ppl[0].can_work(), " label=", Conditions.label(ppl[0]))
		# undo / redo of a zone
		tool_mode = "zone2"
		var z0 := c.zones.size()
		_apply_plan(sim.world.center_of(c.home + Vector2i(10, 10)), sim.world.center_of(c.home + Vector2i(13, 13)))
		var z1 := c.zones.size()
		plan_undo()
		var z2 := c.zones.size()
		plan_redo()
		print("ET undo zones ", z0, " -> ", z1, " undo ", z2, " redo ", c.zones.size())
		tool_mode = ""
		_et["confused"] = 0
	if i == 12:
		save_slot(5)
		var s2 := Sim.new()
		s2.from_dict(SaveSystem.load_data(5))
		var conds := 0
		for q in s2.colony.people:
			conds += q.conditions.size()
		var owners := {}
		for k in s2.road_tiles.keys():
			owners[s2.road_tiles[k]] = true
		print("ET reload roads=", s2.road_tiles.size(), "/", sim.road_tiles.size(), " owners=", owners.keys(), " hist=", s2.history.size(), "/", sim.history.size(),
			" conds=", conds, " auto=", [s2.colony.auto_convert, s2.colony.auto_research, s2.colony.auto_expand, s2.colony.auto_roads, s2.colony.auto_advance], " wreck=", s2.colony.wreck_marks.size())
	if i > 2:
		var dp := sim.person(int(_et.get("dem", -1)))
		if dp != null and dp.state.begins_with("Forgot"):
			_et["confused"] = int(_et["confused"]) + 1
	if i >= 3 and i % 3 == 0:
		var by := {}
		for k in sim.road_tiles.keys():
			by[sim.road_tiles[k]] = int(by.get(sim.road_tiles[k], 0)) + 1
		var marks := {}
		for oc in sim.colonies:
			if not oc.road_marks.is_empty():
				marks[oc.civ_id] = oc.road_marks.size()
		var eb := sim.building(int(_et.get("enemy_b", -1)))
		var indoors := 0
		var asleep := 0
		for q in c.living():
			if q.sleeping:
				asleep += 1
				if sim.indoors(q) != null:
					indoors += 1
		print("ET t%d roads by civ=%s plans=%s wreck=%d enemy_b_hp=%s shots=%s confused_ticks=%d asleep=%d indoors=%d hist=%d" % [i, by, marks, c.wreck_marks.size(),
			str(eb.cur_hp()) if eb != null else "gone", sim.tower_shots.map(func(t): return t[3] if t.size() > 3 else "arrow"), int(_et["confused"]), asleep, indoors, sim.history.size()])


## Trade orders, bandits, splits, bridges, road blocking, calendar speed, fog: `-- --autotest --newtest`
var _nt := {}
func _new_test(i: int) -> void:
	var c := sim.colony
	var o: Colony = sim.colonies[1]
	var bd := 1e9
	for oc in sim.colonies:
		if oc.civ_id != 0 and not oc.bandit and sim.land_reachable(c, oc) and Vector2(oc.home).distance_to(Vector2(c.home)) < bd:
			bd = Vector2(oc.home).distance_to(Vector2(c.home))
			o = oc
	if i == 2:
		c.money = 600.0
		for k in ["wood", "stone", "sticks", "hides"]:
			c.add(k, 200)
		o.add("wood", 300)
		o.add("crops", 200)
		o.money = 500.0
		for k in 6:
			sim._make_human(o, "M" if k % 2 == 0 else "F", (8.0 + k * 6.0) * Defs.AGE_YEAR_DAYS, sim.world.center_of(o.home) + Vector2(k * 6, 4))
		sim.contacts[sim._key(0, o.civ_id)] = true
		sim.relations[sim._key(0, o.civ_id)] = 30.0
		for oc in sim.colonies:
			print("NT reach ", oc.name, " ", sim.land_reachable(c, oc), " home ", oc.home, " walk ", sim.world.walkable_near(oc.home, 4))
		var tr: Human = c.living()[0]
		tr.job = "trader"
		tr.task = {}
		var sale := Trade.people_for_sale(sim, o)
		print("NT market: wood avail=", Trade.available(o, "wood"), " price=", Trade.buy_price(sim, o, "wood"), " stone sell=", Trade.sell_price(sim, o, "stone"), " people=", sale.map(func(q): return "%s(%d)" % [q.name, Trade.person_price(o, q)]), " cap=", Trade.capacity(c))
		var err := Trade.place_order(sim, o.civ_id, {"wood": 40}, {"stone": 20}, [sale[0].id] if not sale.is_empty() else [])
		print("NT order='", err, "' orders=", c.trade_orders.size(), " money=", int(c.money))
		_nt["buy_person"] = sale[0].id if not sale.is_empty() else -1
		_nt["wood0"] = c.count("wood")
		# road blocking + bridge
		var rt := road_tiles_between(sim.world.center_of(c.home + Vector2i(3, -6)), sim.world.center_of(c.home + Vector2i(3, 6)))
		sim.plan_road(c, rt)
		print("NT can build on planned road: '", sim.can_place(c, "campfire", rt[2]), "'")
		var lake := Vector2i(-1, -1)
		for r in range(3, 40):
			for dx in range(-r, r + 1):
				for dy in [-r, r]:
					var q := c.home + Vector2i(dx, dy)
					if lake.x < 0 and sim.world.bridgeable(q) and sim.world.walkable(q + Vector2i(-1, 0)):
						lake = q
		if lake.x >= 0:
			var across := road_tiles_between(sim.world.center_of(lake + Vector2i(-1, 0)), sim.world.center_of(lake + Vector2i(4, 0)))
			print("NT bridge planned ", sim.plan_road(c, across), " tiles at ", lake)
			_nt["lake"] = lake
		# calendar speed change keeps the date
		var before := sim.time.cal()
		Config.rules["calendar_speed"] = 10.0
		sim.step(0.0)
		print("NT calendar before %.3f after %.3f scale=%.1f" % [before, sim.time.cal(), sim.time.scale])
		Config.rules["calendar_speed"] = 5.0
		# fog
		sim.fog.setup(sim.world, true)
		sim.fog.reveal(c.home, Fog.START_R)
		var n := 0
		for b in sim.fog.explored:
			n += b
		print("NT fog explored tiles=", n, " home explored=", sim.fog.is_explored(c.home), " far=", sim.fog.is_explored(Vector2i(1, 1)))
	if i == 4:
		# bandits: a robbery and an ambush
		var bc := Bandits.band(sim)
		print("NT bandits: ", bc.name if bc != null else "none", " camps=", bc.buildings.size() if bc != null else 0, " people=", bc.population() if bc != null else 0, " at_war(0,band)=", sim.at_war(0, bc.civ_id) if bc != null else false)
		if bc != null:
			for k in 3:
				sim._make_human(c, "M", 25.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home))
			var robber: Human = bc.living()[0]
			robber.pos = sim.world.center_of(c.home) + Vector2(60, 0)
			print("NT rob start=", Bandits.start_rob(sim, robber, c), " money before=", int(c.money))
			_nt["robber"] = robber.id
		# politics: force splits
		o.approval = 5.0
		o.defect_year = -1
		for k in 4:
			sim._make_human(o, "M" if k % 2 == 0 else "F", 30.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(o.home))
		var before_n := sim.colonies.size()
		Politics.split(sim, o)
		print("NT AI split: colonies %d -> %d, asks=%d" % [before_n, sim.colonies.size(), sim.defect_asks.size()])
		for k in 4:
			sim._make_human(c, "M" if k % 2 == 0 else "F", 30.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home))
		c.approval = 5.0
		var pop0 := c.population()
		Politics.split(sim, c)
		print("NT player split: pop %d -> %d, colonies=%d" % [pop0, c.population(), sim.colonies.size()])
		print("NT approval parts: ", Politics.target(sim, c))
	if i == 6:
		var ok = save_slot(3)
		var d := SaveSystem.load_data(3)
		var s2 := Sim.new()
		s2.from_dict(d)
		var b2 := Bandits.band(s2)
		print("NT roundtrip save=", ok, " colonies=", s2.colonies.size(), " fog_on=", s2.fog.on, " explored_same=", s2.fog.explored == sim.fog.explored,
			" orders=", s2.colony.trade_orders.size(), " bandits=", b2.population() if b2 != null else -1, " roads=", s2.road_tiles.size(),
			" bridges=", s2.road_tiles.keys().filter(func(k): return s2.world.road[int(k)] == 2).size(), " approval=", int(s2.colony.approval), " scale=", s2.time.scale)
	if i >= 5 and i <= 60:
		var tr: Human = null
		for q in c.living():
			if q.job == "trader":
				tr = q
		var od := "none" if c.trade_orders.is_empty() else Trade.describe(sim, c.trade_orders[0])
		var bp := sim.person(int(_nt.get("buy_person", -1)))
		var rob := sim.person(int(_nt.get("robber", -1)))
		var trs := c.people.filter(func(q): return q.job == "trader" or q.task_memory.has("order"))
		if not trs.is_empty():
			var t0: Human = trs[0]
			print("   NT trader %s alive=%s job=%s carry=%s money=%d mem=%s" % [t0.name, t0.alive, t0.job, t0.carrying, int(t0.task_memory.get("trade_money", 0)), t0.task_memory.keys()])
		print("NT t%d trader=%s order=%s money=%d wood=+%d bought=%s robber=%s roads=%d bridges=%d" % [i, tr.state if tr != null else "-", od, int(c.money),
			int(c.count("wood") - float(_nt["wood0"])), (sim.col_of(bp).name if bp != null else "-"), (rob.state if rob != null and rob.alive else "-"),
			sim.road_tiles.size(), sim.road_tiles.keys().filter(func(k): return sim.world.road[int(k)] == 2).size()])


## Soldiers, roads, zones, election influence, deals and milestones: `-- --autotest --dealtest`
func _deal_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		c.era_i = 2
		c.era = Defs.ERAS[2]
		for e in [0, 1]:
			for id in Defs.techs_of_era(e):
				c.researched[id] = true
		c.invalidate_bonus()
		c.money = 2000.0
		for k in ["wood", "stone", "sticks", "hides", "grass"]:
			c.add(k, 300)
		for t in ["training_camp", "mercenary_hall", "blacksmith", "house"]:
			var site := CivAI.find_site(sim, c, t)
			var b := sim.place_building(c, t, site)
			if b != null:
				sim.finish_building(b)
		for k in 4:
			sim._make_human(c, "M" if k % 2 == 0 else "F", 25.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 8, 10))
		print("DT train problem='", Military.train_problem(c), "'")
		var w := Military.train(sim, c, "warrior")
		var a := Military.train(sim, c, "archer")
		var hw := Military.hire(sim, c, "warrior")
		var ha := Military.hire(sim, c, "archer")
		print("DT trained ", w.name, "/", w.soldier_kind, " ", a.name, "/", a.soldier_kind, "  hired ", hw.name, " ", hw.weapon, " | ", ha.name, " ", ha.weapon, " money=", int(c.money))
		print("DT best weapons: warrior era1=", Defs.best_weapon_for("warrior", 1), " archer era1=", Defs.best_weapon_for("archer", 1), " archer era3=", Defs.best_weapon_for("archer", 3))
		c.add("short_bow", 1)
		c.add("flint_axe", 1)
		# zones & roads
		var hb: Building = null
		for b in c.buildings:
			if b.type == "house":
				hb = b
		var n := sim.paint_zone(c, c.home - Vector2i(12, 12), c.home + Vector2i(12, 12), 2)
		print("DT zone tiles=", n, " house zoned=", hb.zoned if hb != null else "-", " housing=", c.housing())
		var rt := road_tiles_between(sim.world.center_of(c.home + Vector2i(3, 3)), sim.world.center_of(c.home + Vector2i(15, 9)))
		print("DT road planned=", sim.plan_road(c, rt), " cost plain vs road=", sim.world.cost_at(c.home + Vector2i(20, 20)))
		# elections
		var cands := Elections.preview(sim, c)
		var pick: Human = cands[cands.size() - 1]
		c.backed_id = pick.id
		print("DT forecast before=", Elections.forecast(sim, c), " backing ", pick.name)
		print("DT rally=", Elections.campaign_talents(sim, c, pick.id), " gifts=", Elections.campaign_gifts(sim, c, pick.id))
		print("DT forecast after=", Elections.forecast(sim, c))
		c.rigged = true
		Elections.hold(sim, c)
		print("DT leader now ", Elections.leader(sim, c).name, " (backed ", pick.name, ") unrest=", c.in_unrest(), " rigged reset=", not c.rigged)
		# deals
		for o in sim.colonies:
			if o.civ_id != 0:
				sim.contacts[sim._key(0, o.civ_id)] = true
				sim.contacts[sim._key(1, o.civ_id)] = true
				o.add("wood", 200)
				o.money += 300
		var t := Deals.make_trade(sim, sim.colonies[1], c)
		print("DT trade offer: ", t)
		t["from"] = 1
		Deals.offer_player(sim, t)
		sim.relations[sim._key(0, 1)] = 80.0
		print("DT propose alliance: '", Deals.player_propose(sim, 1, "alliance"), "' allied=", Deals.allied(sim, 0, 1))
		Deals.make_alliance(sim, 0, 1)
		sim.relations[sim._key(0, 2)] = -80.0
		sim.civ(2).era_i = 2
		print("DT civ2 attacks player: ", sim.declare_war(2, 0), " wars=", sim.wars.keys())
		print("DT demand tribute from civ3: '", Deals.player_propose(sim, 3, "tribute"), "'")
		Deals.offer_player(sim, {"from": 3, "type": "tribute", "talents": 50, "want": {}})
		print("DT deals made=", c.deals_made, " pending=", sim.deal_offers.size())
	if i >= 3 and i <= 9:
		var armed := PackedStringArray()
		for q in c.soldiers():
			armed.append("%s:%s:%s" % [q.name.substr(0, 5), q.soldier_kind, q.weapon])
		print("DT t%d roads=%d marks=%d soldiers=%s milestones=%d" % [i, sim.road_tiles.size(), c.road_marks.size(), armed, c.milestones.size()])
	if i == 10:
		print("DT milestones: ", c.milestones.keys())


## Borders, elections, kin partners and the age cost: `-- --autotest --civtest`
func _civ_test(i: int) -> void:
	var c := sim.colony
	var o: Colony = sim.colonies[1]
	if i == 2:
		print("CT age cost era0=", c.era_advance_cost(), " complete=", c.era_complete(), " rp=", c.research_points)
		for id in Defs.techs_of_era(0):
			c.researched[id] = true
		c.research_points = c.era_advance_cost() - 1
		print("CT can_advance with 1 RP short: ", c.can_advance_era())
		c.research_points += 1
		print("CT can_advance: ", c.can_advance_era(), " -> ", c.advance_era(), " rp left=", c.research_points, " era=", c.era)
		# a rival's state right next to ours, then walk a Billy in
		var home_s := sim.states.at(c.home)
		var nb: int = int((sim.states.neighbors[home_s] as Dictionary).keys()[0])
		sim.states.set_owner(nb, o.civ_id)
		sim.contacts[sim._key(0, o.civ_id)] = true
		var p: Human = c.living()[0]
		var dest := sim.paths.open_near(sim.states.centers[nb], 3)
		# make sure someone of theirs is there to see it
		var watcher: Human = o.living()[0]
		watcher.pos = sim.world.center_of(dest) + Vector2(20, 0)
		print("CT trespass: walking ", p.name, " into ", sim.states.names[nb], " access=", Borders.has_access(sim, 0, o.civ_id), " war chance=", Borders.war_chance(sim, 0, o.civ_id), " order=", HumanAI.order_move(sim, p, dest))
		# AI asks the player (auto-answered yes in tests), AI asks AI
		Borders.request(sim, o.civ_id, 0)
		Borders.request(sim, 2, o.civ_id)
		print("CT access 1>0=", Borders.has_access(sim, o.civ_id, 0), " 2>1=", Borders.has_access(sim, 2, o.civ_id), " grant chance=", Borders.grant_chance(sim, 2, o.civ_id))
		# a job path into foreign land is refused
		var q: Human = c.living()[1]
		q.task = {"type": "harvest", "prio": HumanAI.PRIO_JOB}
		print("CT job path into their land allowed=", HumanAI._go(sim, q, dest))
		q.task = {}
		q.path = []
		Borders.revoke(sim, 0, o.civ_id)
		sim.access_denied["0>%d" % o.civ_id] = 1e9
	if i >= 3 and i <= 12:
		var p: Human = c.living()[0]
		var w2: Human = o.living()[0]
		var nb2: int = int(sim.claims_in_progress.get(-99, -1))
		for st in sim.states.owned_by(o.civ_id):
			if (sim.states.neighbors[sim.states.at(c.home)] as Dictionary).has(st):
				nb2 = st
		if nb2 >= 0 and i % 3 == 0:
			p.pos = sim.world.center_of(sim.paths.open_near(sim.states.centers[nb2], 3))
			p.task_memory.erase("tres")
			sim.trespass_cd.clear()
		w2.pos = p.pos + Vector2(30, 0)
		Borders.check_trespass(sim)
		print("CT   %s at %s (state %s) tres=%s wars=%s" % [p.name, sim.world.tile_of(p.pos), sim.states.names[sim.states.at(sim.world.tile_of(p.pos))], p.task_memory.get("tres", -1), sim.wars.keys()])
	if i == 14:
		# elections: an early vote, then the Bronze Age forces a presidential one
		c.next_election = 0.0
		Elections.update(sim, c)
		c.era_i = 2
		c.era = Defs.ERAS[2]
		Elections.update(sim, c)
		for k in 3:
			Elections.hold(sim, c)
		print("CT leader ", c.leader_title, " ", Elections.leader(sim, c).name, " terms=", c.leader_terms, " fx=", c.leader_fx, " last=", c.last_election)
		# kin partners: siblings may pair
		var kids := 0
		var sib_a: Human = null
		var sib_b: Human = null
		for pp in c.living():
			for qq in c.living():
				if pp != qq and pp.gender != qq.gender and Survival.related(pp, qq):
					sib_a = pp
					sib_b = qq
		print("CT related pair found=", sib_a != null, " allow_kin=", Config.rule("allow_kin"))
		# leader dies -> new election
		var ld := Elections.leader(sim, c)
		sim.kill(ld, "test")
		Elections.update(sim, c)
		print("CT after death: ", c.leader_title, " ", Elections.leader(sim, c).name if Elections.leader(sim, c) != null else "-")


func _feature_test(i: int) -> void:
	var c := sim.colony
	if i == 2:
		print("FT states: total ", sim.states.count(), " mine ", sim.states.owned_by(0).map(func(x): return sim.states.names[x]), " limit ", sim.state_limit(c))
		print("FT years in era %.2f needed %.1f  date %s  cal_years %.2f" % [c.years_in_era(), c.years_needed(), sim.time.date_text(), sim.time.cal_years()])
		# claim a free neighbouring state
		for st in sim.states.count():
			if sim.claim_problem(0, st) == "":
				var who: Human = c.living()[0]
				print("FT claim ", sim.states.names[st], " ok=", HumanAI.order_claim(sim, who, st))
				break
	if i == 4:
		for k in 5:
			_cheat_key()
		var b := sim.place_building(c, "monolith", CivAI.find_site(sim, c, "monolith"))
		print("FT cheat=", c.cheat, " techs=", c.researched.size(), "/", Defs.TECH_ORDER.size(), " monolith built=", b != null and b.built, " can_advance=", c.can_advance_era())
		for k in 5:
			_cheat_key()
		print("FT cheat after second code=", c.cheat, " can_advance=", c.can_advance_era())
		c.knowledge = 12000.0
		print("FT skip 10: '", sim.skip_years(c, 10), "' date ", sim.time.date_text(), " kp ", c.knowledge, " years_in_era %.1f" % c.years_in_era())
	if i == 12 or i == 20 or i == 30:
		print("FT %d: mine %s claims %s owners %s" % [i, sim.states.owned_by(0).map(func(x): return sim.states.names[x]), sim.claims_in_progress, Array(sim.states.owners).filter(func(o): return o >= 0).size()])


var _raid_target: Colony
var _raider: Colony
var _raid_squad: Array = []
var _gate_id := -1
func _raid_setup() -> void:
	var best_d := 1e9
	for a in sim.colonies:
		for o in sim.colonies:
			if o != a and sim.land_reachable(a, o):
				var d := Vector2(o.home).distance_to(Vector2(a.home))
				if d < best_d:
					best_d = d
					_raid_target = o
					_raider = a
	if _raid_target == null:
		print("RAID: no reachable target")
		return
	for k in 8:
		var pp := sim._make_human(_raider, "M", 22.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(_raider.home))
		pp.job = "soldier"
		pp.weapon = ["bronze_sword", "bronze_spear", "bow"][k % 3]
		pp.skills = {"soldier": 5.0}
		pp.health = 100.0
	sim.declare_war(_raider.civ_id, _raid_target.civ_id)
	var sol: Array = _raider.soldiers()
	var wall: Building = null
	for b in _raid_target.buildings:
		if b.type == "gate" and b.built:
			wall = b
	for k in sol.size():
		if k < 3 and wall != null:
			sol[k].pos = sim.world.center_of(wall.tile) + Vector2(-60, 0)
			HumanAI.order_attack(sim, sol[k], "building", wall.id)
			_raid_squad.append(sol[k])
	for q in _raid_squad:
		q.health = 100000.0
	sim.test_no_peace = true
	_raider.auto_jobs = false
	_gate_id = wall.id if wall != null else -1
	print("RAID: gate target ", _gate_id)
	print("RAID: %s attacking %s dist %d" % [_raider.name, _raid_target.name, int(best_d)])


func _raid_report(i: int) -> void:
	if _raid_target == null:
		return
	var states := {}
	for q in _raider.soldiers():
		states[q.state.substr(0, 26)] = int(states.get(q.state.substr(0, 26), 0)) + 1
	var gates := 0
	for b in _raid_target.buildings:
		if b.type == "gate":
			gates += 1
	var gt: Building = sim.building(_gate_id)
	print("gates left ", gates, " gate hp ", gt.cur_hp() if gt != null else -1.0)
	for q in _raid_squad:
		var tp: Vector2 = HumanAI._target_pos(sim, str(q.task.get("kind", "")), int(q.task.get("target", -1))) if q.task.has("kind") else Vector2.ZERO
		print("   squad %s alive=%s job=%s task=%s kind=%s tgt=%s dist=%.0f path=%d prio=%s" % [q.name, q.alive, q.job, q.task.get("type", "-"), q.task.get("kind", "-"), q.task.get("target", "-"), tp.distance_to(q.pos) / 16.0, q.path.size(), q.task.get("prio", "-")])
	print("RAID %d: target pop %d buildings %d | raider soldiers %d %s | wars %s" % [i, _raid_target.population(), _raid_target.buildings.size(), _raider.soldiers().size(), states, sim.wars.keys()])


func _wartest_report(i: int) -> void:
	var line := "WAR %d:" % i
	for c in sim.colonies:
		var walls := 0
		var wb := 0
		for b in c.buildings:
			if b.type == "wall" or b.type == "gate":
				if b.built:
					walls += 1
				else:
					wb += 1
		var armed := 0
		for q in c.soldiers():
			if q.weapon != "":
				armed += 1
		line += " %s[p%d sol%d arm%d wpn%d walls%d/%d b%d gov=%s str%d]" % [c.name.substr(0, 4), c.population(), c.soldiers().size(), armed, c.weapons_in_stock(), walls, wb, c.buildings.size(), c.government.substr(0, 4), int(sim.military_strength(c))]
	print(line, " wars=", sim.wars.keys(), " clears=", sim.colony.clear_marks.size(), " prof=", sim.prof)
	sim.prof.clear()
	var jobs := {}
	for q in sim.colonies[1].living():
		jobs[q.job] = int(jobs.get(q.job, 0)) + 1
	var bs: Building = null
	for b in sim.colonies[1].buildings:
		if b.type == "blacksmith":
			bs = b
	print("    civ1 jobs=", jobs, " blacksmith=", (("built=%s craft=%s auto=%s" % [bs.built, bs.craft, bs.auto_craft]) if bs != null else "none"), " soldiers_allowed=", sim.colonies[1].job_allowed("soldier"))
	for q in sim.colony.living().slice(0, 0):
		var dp := sim.colony.drop_point(q.pos)
		print("    %s thirst=%.0f hunger=%.0f task=%s prio=%s state=%s path=%d  tile=%s dp=%s pathlen=%d solid_here=%s water=%d" % [q.name, q.thirst, q.hunger, q.task.get("type", "-"), q.task.get("prio", "-"), q.state, q.path.size(), sim.world.tile_of(q.pos), dp, sim.paths.find_path(sim.world.tile_of(q.pos), dp).size(), sim.paths.astar.is_point_solid(sim.world.tile_of(q.pos)), int(sim.colony.count("water"))])


func _autotest() -> void:
	sim.event.connect(func(t, k): print("  [EVENT] ", t))
	sim.debug_log = true
	if picking:
		use_suggested_start()
	set_speed(8.0)
	print("tribes: ", sim.colonies.size())
	var secs := 60
	for a in _args:
		if a.begins_with("--secs="):
			secs = int(a.substr(7))
	if _args.has("--wartest"):
		_setup_wartest()
	for i in secs:
		await get_tree().create_timer(1.0).timeout
		CivAI.auto_research(sim, sim.colony)
		if _args.has("--wartest"):
			_wartest_report(i)
		if _args.has("--featuretest"):
			_feature_test(i)
		if _args.has("--civtest"):
			_civ_test(i)
		if _args.has("--dealtest"):
			_deal_test(i)
		if _args.has("--newtest"):
			_new_test(i)
		if _args.has("--lumbertest"):
			_lumber_test(i)
		if _args.has("--etest"):
			_e_test(i)
		if _args.has("--ftest"):
			_f_test(i)
		if _args.has("--gtest"):
			_g_test(i)
		if _args.has("--htest"):
			_h_test(i)
		if _args.has("--raidtest") and i == 2:
			_raid_setup()
		if _args.has("--raidtest") and i > 2:
			_raid_report(i)
		for cc2 in sim.colonies:
			for q in cc2.living():
				if q.aboard < 0 and not sim.world.walkable(sim.world.tile_of(q.pos)):
					print("   IN WATER %s civ%d task=%s/%s state=%s tile=%s" % [q.name, q.civ_id, q.task.get("type", "-"), q.task.get("dest", "-"), q.state, sim.world.tile_of(q.pos)])
		if i % 5 != 0:
			continue
		var line := "%s |" % sim.time.date_text().substr(0, 6)
		for c in sim.colonies:
			var built := 0
			for b in c.buildings:
				if b.built:
					built += 1
			line += " %s: p%d f%.0f b%d e%d r%d kp%d rp%d $%d |" % [c.name.substr(0, 5), c.population(), c.food_units(), built, c.era_i, c.researched.size(), int(c.knowledge), int(c.research_points), int(c.money)]
		print(line)
		var gov := "   leaders:"
		for c in sim.colonies:
			var ld := Elections.leader(sim, c)
			gov += " %s=%s %s(t%d, next %.1f)" % [c.name.substr(0, 5), c.leader_title, ld.name if ld != null else "-", c.leader_terms, c.next_election]
		print(gov, "  access=", sim.access.size(), " denied=", sim.access_denied.size(), " wars=", sim.wars.keys(), " fx=", sim.fx.size(), " yr=%.2f" % sim.time.cal_years())
		var dbg := ""
		for b in sim.colony.buildings:
			dbg += "%s%s " % [b.type.substr(0, 6), "" if b.built else "*"]
			if b.type == "research_table":
				dbg += "(stored %.0f) " % b.stored
		var jobs := {}
		for p in sim.colony.living():
			jobs[p.job] = int(jobs.get(p.job, 0)) + 1
		var cc := sim.colony
		print("   player: ", dbg, jobs, " want=", cc.want_build, " stock w%d s%d st%d g%d cu%d sn%d fe%d" % [int(cc.count("wood")), int(cc.count("sticks")), int(cc.count("stone")), int(cc.count("grass")), int(cc.count("copper_ore")), int(cc.count("tin_ore")), int(cc.count("iron_ore"))], " ore_need=", cc.ore_needed())
		if i == 30:
			print("save ok: ", save_slot(2))
		if i == 20 and _args.has("--tradetest"):
			for tc in sim.colonies:
				if sim.trade_partners(tc).is_empty():
					continue
				for q in tc.living():
					if q.is_adult():
						q.job = "trader"
						tc.auto_jobs = false
						tc.add("wood", 60)
						tc.add("hides", 20)
						print("   TRADER: ", q.name, " of ", tc.name, " partners=", sim.trade_partners(tc).map(func(o): return o.name))
						break
				break
		if _args.has("--tradetest") and i % 10 == 0:
			for tc in sim.colonies:
				for q in tc.living():
					if q.job == "trader":
						print("   trader %s: %s carrying=%s money=%d log=%s wood=%d short=%d hides=%d fd=%.1f" % [q.name, q.state, q.carrying, int(tc.money), tc.trade_log.slice(-2), int(tc.count("wood")), int(tc.shortfall("wood")), int(tc.count("hides")), tc.food_days()])
	var jobs := {}
	for p in sim.colony.living():
		jobs[p.job] = int(jobs.get(p.job, 0)) + 1
	print("player jobs: ", jobs)
	print("AUTOTEST DONE")
	get_tree().quit()


## Renders screenshots for visual checks: `godot res://scenes/game.tscn -- --shots`
func _forge_shot() -> void:
	use_suggested_start()
	await get_tree().create_timer(1.0).timeout
	var c := sim.colony
	c.researched["smithing_bench"] = true
	c.researched["weaponsmithing"] = true
	c.researched["weaponsmithing_3"] = true
	for t in ["spear", "knife", "short_sword"]:
		Smithing.save_design(sim, Smithing.starter(t))
	hud.toggle_forge()
	hud.forge_ui._on_type("short_sword")
	hud.forge_ui._on_template()
	await _snap("/tmp/shots/44_weapons.png", 1.0)
	get_tree().quit()


## Pictures of the Earth mode: `-- --earth --earthshots`
func _earth_shots() -> void:
	var dir := "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	use_suggested_start()
	set_speed(1.0)
	for i in 3:
		await get_tree().create_timer(1.0).timeout
	hud.toggle_worldmap()
	await _snap(dir + "/46_earth_map.png", 1.0)
	hud.toggle_worldmap()
	for spot in [["47_earth_nile", 27.0, 31.5], ["48_earth_alps", 46.5, 9.5]]:
		camera.position = sim.world.center_of(EarthGen.latlon_to_tile(sim.world, spot[1], spot[2]))
		await _snap(dir + "/%s.png" % spot[0], 0.35)
	get_tree().quit()


func _shots() -> void:
	var dir := "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	use_suggested_start()
	set_speed(8.0)
	for i in 6:
		await get_tree().create_timer(1.0).timeout
	sim.time.t = floorf(sim.time.t) + 1.45
	var c := sim.colony
	# showcase: one of each building, finished, plus a blueprint and a ship
	for t in ["shelter", "storage", "research_table", "granary", "stone_hut", "house", "well", "workshop", "healer_hut", "stone_house", "watchtower"]:
		var site := CivAI.find_site(sim, c, t)
		if site.x >= 0:
			var b := sim.place_building(c, t, site)
			if b != null:
				sim.finish_building(b)
	var bp := sim.place_building(c, "house", CivAI.find_site(sim, c, "house"))
	if bp != null:
		bp.delivered = {"wood": 12}
	var sea_t := sim._nearest_sea(c.home, 30)
	selected_ship_id = 101
	if sea_t.x >= 0:
		for k in 3:
			var sh := Ship.new()
			sh.id = 100 + k
			sh.kind = k
			sh.pos = sim.world.center_of(sim._nearest_sea(c.home + Vector2i(k * 3, k * 2), 30))
			sh.heading = 0.4 * k
			sh.name = "Test"
			ships_demo(sh)
	set_speed(0.0)
	camera.position = sim.world.center_of(c.home)
	for p in c.living():
		selected_ids.append(p.id)
	dragging = true
	drag_start = sim.world.center_of(c.home) + Vector2(-60, -40)
	await _snap(dir + "/1_village_stone.png", 2.4)
	dragging = false
	c.era_i = 3
	await _snap(dir + "/2_village_iron.png", 2.4)
	if sea_t.x >= 0:
		camera.position = sim.world.center_of(sea_t)
		await _snap(dir + "/3_ships.png", 2.4)
	camera.position = sim.world.center_of(c.home)
	await _snap(dir + "/4_far_icons.png", 0.4)
	await _snap(dir + "/6_terrain_far.png", 0.15)
	await _snap(dir + "/7_terrain_mid.png", 0.8)
	var desert := sim.world.find_nearest(c.home, 200, func(q: Vector2i) -> bool:
		return sim.world.t_at(q) == Defs.T.DESERT or sim.world.t_at(q) == Defs.T.HIGH_DESERT or sim.world.t_at(q) == Defs.T.SAVANNA)
	if desert.x >= 0:
		camera.position = sim.world.center_of(desert)
		await _snap(dir + "/8_desert.png", 1.2)
		camera.position = sim.world.center_of(c.home)
	c.era_i = 1
	c.era = Defs.ERAS[1]
	for id in Defs.techs_of_era(0):
		c.researched[id] = true
	for id in ["pottery", "boatbuilding"]:
		if Defs.TECHS.has(id):
			c.researched[id] = true
	c.knowledge = 3420.0
	c.research_points = 7.0
	c.research_stock = {"wood": 12.0, "bones": 4.0, "copper_ore": 2.0}
	hud.toggle_panel("research")
	await _snap(dir + "/5_research.png", 1.6)
	hud.close_panel()
	hud.toggle_build_window()
	await _snap(dir + "/5b_build_window.png", 1.6)
	hud.close_panel()
	hud._open_settings()
	await _snap(dir + "/5c_settings.png", 1.6)
	hud.close_panel()
	await _military_shots(dir)
	print("SHOTS DONE")
	get_tree().quit()


## Bronze Age showcase: walls and gates, blacksmith, training camp, capitol, armed soldiers,
## a war with a rival, the territory map, diplomacy and the government choice.
func _military_shots(dir: String) -> void:
	var c := sim.colony
	c.era_i = 2
	c.era = Defs.ERAS[2]
	for e in [0, 1]:
		for id in Defs.techs_of_era(e):
			c.researched[id] = true
	for id in ["stone_walls", "watch_posts", "statecraft", "cartography"]:
		c.researched[id] = true
	c.invalidate_bonus()
	for k in ["wood", "stone", "sticks", "grass"]:
		c.add(k, 500)
	c.add("copper_ore", 40)
	c.add("tin_ore", 30)
	for t in ["blacksmith", "training_camp", "capitol", "map_table"]:
		var site := CivAI.find_site(sim, c, t)
		if site.x >= 0:
			var b := sim.place_building(c, t, site)
			if b != null:
				sim.finish_building(b)
	# a squad of soldiers with bronze-age arms
	var weapons := ["bronze_sword", "bronze_spear", "bow", "bronze_spear", "stone_spear", "sling"]
	for k in 6:
		var pp := sim._make_human(c, "M" if k % 2 == 0 else "F", 22.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 9 - 24, 26))
		pp.job = "soldier"
		pp.weapon = weapons[k]
		pp.skills = {"soldier": 4.0}
	c.wall_ring = 10
	for q in CivAI._ring(c.home, 10):
		if sim.world.inb(q) and sim.world.res_type[sim.world.idx(q)] != Defs.R.NONE:
			sim.world.res_type[sim.world.idx(q)] = Defs.R.NONE
			sim.world.res_amount[sim.world.idx(q)] = 0
			sim.paths.refresh_tile(q)
			_on_tile_changed(q)
	selected_ship_id = -1
	for k in 40:
		CivAI.plan_defenses(sim, c)
		for b in c.buildings:
			if not b.built and (b.type == "wall" or b.type == "gate"):
				sim.finish_building(b)
	var foe: Colony = sim.colonies[1] if sim.colonies.size() > 1 else null
	if foe != null:
		sim.contacts[sim._key(0, foe.civ_id)] = true
		sim.declare_war(0, foe.civ_id)
		for k in 3:
			var ep := sim._make_human(foe, "M", 22.0 * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(150 + k * 10, -30))
			ep.job = "soldier"
			ep.weapon = "stone_club"
	c.government = "monarchy"
	camera.position = sim.world.center_of(c.home)
	set_speed(1.0)
	for k in 20:
		await get_tree().process_frame
	await _snap(dir + "/9_walls_army.png", 1.3)
	await _snap(dir + "/10_walls_far.png", 0.6)
	# diplomacy panel for the enemy
	if foe != null:
		clear_selection()
		selected_civ_id = foe.civ_id
		hud._refresh_info()
		await _snap(dir + "/11_diplomacy.png", 1.3)
	clear_selection()
	# territory map
	hud.toggle_worldmap()
	hud._on_territory_toggle()
	for k in 10:
		await get_tree().process_frame
	await _snap(dir + "/12_territory.png", 1.3)
	hud.worldmap.set_zoom(3.0, hud.worldmap.size * 0.5)
	hud.worldmap.map_center = (Vector2(c.home) + Vector2(0.5, 0.5)) / float(sim.world.w)
	hud.worldmap._clamp_center()
	await _snap(dir + "/12b_territory_zoomed.png", 1.3)
	hud.worldmap.reset_view()
	hud.toggle_worldmap()
	# clearing marks
	tool_mode = "clear"
	var t0 := sim.world.tile_of(sim.world.center_of(c.home) + Vector2(-260, -200))
	_apply_clear(Rect2(sim.world.center_of(t0), Vector2(160, 110)), false)
	camera.position = sim.world.center_of(t0) + Vector2(80, 55)
	await _snap(dir + "/13_clear_marks.png", 1.6)
	tool_mode = ""
	camera.position = sim.world.center_of(c.home)
	# government choice
	c.government = ""
	c.gov_pending = true
	hud._show_gov_dialog()
	await _snap(dir + "/14_government.png", 1.3)
	hud.gov_layer.visible = false
	c.gov_pending = false
	c.government = "monarchy"
	# a brawl up close: soldiers against raiders, with combat effects; FPS counter on
	Settings.show_fps = true
	var spot := sim.world.center_of(c.home) + Vector2(40, 60)
	var mine: Array = []
	var theirs: Array = []
	for k in 4:
		var a := sim._make_human(c, "M", 24.0 * Defs.AGE_YEAR_DAYS, spot + Vector2(-14, k * 10 - 15))
		a.job = "soldier"
		a.weapon = ["bronze_sword", "bronze_spear", "stone_club", "bronze_sword"][k]
		mine.append(a)
		if foe != null:
			var b := sim._make_human(foe, "M", 24.0 * Defs.AGE_YEAR_DAYS, spot + Vector2(14, k * 10 - 15))
			b.job = "soldier"
			b.weapon = "stone_club"
			b.health = 400.0
			theirs.append(b)
	for k in mine.size():
		if k < theirs.size():
			HumanAI.order_attack(sim, mine[k], "human", theirs[k].id)
			HumanAI.order_attack(sim, theirs[k], "human", mine[k].id)
	# and a wolf after a hunter
	var wolf_pos := spot + Vector2(0, 70)
	var hunter := sim._make_human(c, "F", 24.0 * Defs.AGE_YEAR_DAYS, wolf_pos + Vector2(-12, 0))
	hunter.job = "hunter"
	var w := Animal.new()
	w.id = sim.next_animal_id
	sim.next_animal_id += 1
	w.species = "wolf"
	w.pos = wolf_pos + Vector2(10, 0)
	w.health = 300.0
	sim.animals.append(w)
	sim.refresh_predators()
	w.prey_id = hunter.id
	w.prey_is_human = true
	w.state = "chase"
	camera.position = spot + Vector2(0, 20)
	camera.target_zoom = 3.4
	camera.zoom = Vector2(3.4, 3.4)
	set_speed(1.0)
	for k in 150:
		await get_tree().process_frame
		if k > 60 and sim.fx.size() >= 8:
			break
	get_viewport().get_texture().get_image().save_png(dir + "/15_fight.png")
	print("saved fight, fx=", sim.fx.size())
	for k in 25:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir + "/15b_fight.png")
	# frozen mid-animation samples of every effect, for a visual check
	set_speed(0.0)
	sim.fx.clear()
	var base := spot + Vector2(-60, 40)
	var styles := ["slash", "pierce", "blunt", "bite"]
	for k in 4:
		var at := base + Vector2(k * 34, 0)
		Fx.hit(sim, at, at + Vector2(-12, 0), 14.0, styles[k], true, Color(0.95, 0.7, 0.35))
	Fx.miss(sim, base + Vector2(0, 40), base + Vector2(-12, 40))
	Fx.smash(sim, base + Vector2(60, 40), base + Vector2(40, 40))
	for e in sim.fx:
		e["dur"] = float(e["dur"]) * 40.0
		e["t0"] = Fx.now() - float(e["dur"]) * 0.3
	camera.position = base + Vector2(50, 20)
	camera.zoom = Vector2(4.5, 4.5)
	camera.target_zoom = 4.5
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir + "/15c_fx_samples.png")
	sim.fx.clear()
	# rivals asking to cross
	if foe != null:
		sim.make_peace(0, foe.civ_id)
		sim.access_asks.append(foe.civ_id)
	for k in 4:
		await get_tree().process_frame
	await _snap(dir + "/16_passage.png", 2.6)
	sim.access_asks.clear()
	# --- town plan: zones and roads around the village, the planner palette
	c.money = 900.0
	var hall_site := CivAI.find_site(sim, c, "mercenary_hall")
	var hall := sim.place_building(c, "mercenary_hall", hall_site)
	if hall != null:
		sim.finish_building(hall)
	sim.paint_zone(c, c.home + Vector2i(-9, -7), c.home + Vector2i(-2, 2), 2)
	sim.paint_zone(c, c.home + Vector2i(2, -7), c.home + Vector2i(9, 0), 3)
	sim.paint_zone(c, c.home + Vector2i(-9, 4), c.home + Vector2i(9, 9), 1)
	var rd := road_tiles_between(sim.world.center_of(c.home + Vector2i(-12, 2)), sim.world.center_of(c.home + Vector2i(12, -6)))
	rd.append_array(road_tiles_between(sim.world.center_of(c.home + Vector2i(0, 2)), sim.world.center_of(c.home + Vector2i(0, 12))))
	for q in rd:
		if sim.road_ok(q):
			var ri := sim.world.idx(q)
			sim.world.res_type[ri] = Defs.R.NONE
			_on_tile_changed(q)
			sim.lay_road(c, ri)
	sim.plan_road(c, road_tiles_between(sim.world.center_of(c.home + Vector2i(12, -6)), sim.world.center_of(c.home + Vector2i(18, -14))))
	hud.toggle_planner()
	camera.position = sim.world.center_of(c.home)
	await _snap(dir + "/18_town_plan.png", 1.5)
	hud.toggle_planner()
	# --- mercenary hall info with hire buttons
	if hall != null:
		clear_selection()
		selected_building_id = hall.id
		camera.position = hall.center()
		hud._refresh_info()
		await _snap(dir + "/19_mercenary_hall.png", 2.4)
		Military.hire(sim, c, "archer")
		Military.hire(sim, c, "warrior")
	clear_selection()
	# --- milestones panel
	hud.toggle_panel("milestones")
	await _snap(dir + "/20_milestones.png", 1.5)
	# --- colony panel: election influence
	for k in 4:
		sim._make_human(c, "F" if k % 2 == 0 else "M", (30.0 + k * 9.0) * Defs.AGE_YEAR_DAYS, sim.world.center_of(c.home) + Vector2(k * 7, 4))
	var cands := Elections.preview(sim, c)
	if cands.size() > 1:
		c.backed_id = cands[1].id
		c.campaign[cands[1].id] = 3.0
	hud.toggle_panel("colony")
	await _snap(dir + "/21_election.png", 1.5)
	hud.close_panel()
	# --- a deal card
	if foe != null:
		var o2: Colony = sim.colonies[2] if sim.colonies.size() > 2 else foe
		sim.contacts[sim._key(0, o2.civ_id)] = true
		sim.debug_log = false
		Deals.offer_player(sim, {"from": o2.civ_id, "type": "tribute", "talents": 60, "want": {}})
		await _snap(dir + "/22_deal_card.png", 1.5)
		sim.deal_offers.clear()
		clear_selection()
		selected_civ_id = foe.civ_id
		hud._refresh_info()
		await _snap(dir + "/23_diplomacy_actions.png", 1.5)
		clear_selection()
	# --- trade window
	var tp: Colony = null
	for oc in sim.colonies:
		if oc.civ_id != 0 and not oc.bandit and not oc.collapsed:
			tp = oc
			break
	if tp != null:
		sim.contacts[sim._key(0, tp.civ_id)] = true
		if sim.at_war(0, tp.civ_id):
			sim.make_peace(0, tp.civ_id)
		sim.relations[sim._key(0, tp.civ_id)] = 25.0
		tp.add("wood", 120)
		tp.add("crops", 90)
		tp.add("copper_ore", 30)
		for k in 6:
			sim._make_human(tp, "M" if k % 2 == 0 else "F", (9.0 + k * 6.0) * Defs.AGE_YEAR_DAYS, sim.world.center_of(tp.home))
		sim._reach_cache["%d,%d>%d,%d" % [c.home.x, c.home.y, tp.home.x, tp.home.y]] = true
		hud.open_trade(tp.civ_id)
		(hud.trade_spins["buy:wood"] as SpinBox).value = 40
		if hud.trade_spins.has("sell:stone"):
			(hud.trade_spins["sell:stone"] as SpinBox).value = 25
		for pid in hud.trade_people.keys():
			(hud.trade_people[pid] as CheckBox).button_pressed = true
			break
		await _snap(dir + "/24_trade_window.png", 2.0)
		hud.close_panel()
	# --- monolith, bridge, bandit camp, announcements
	c.researched["standing_stones"] = true
	var ms := CivAI.find_site(sim, c, "monolith")
	var mono := sim.place_building(c, "monolith", ms)
	if mono != null:
		sim.finish_building(mono)
		camera.position = mono.center()
		c.researched["lumbering"] = true
		var lsite := CivAI.find_site(sim, c, "lumber_yard")
		for rr in range(4, 40):
			if lsite.x >= 0:
				break
			for dx in range(-rr, rr + 1):
				var cand := c.home + Vector2i(dx, rr)
				if sim.can_place(c, "lumber_yard", cand) == "":
					lsite = cand
					break
		var ly := sim.place_building(c, "lumber_yard", lsite)
		if ly != null:
			sim.finish_building(ly)
			var lbp: Human = c.living()[0]
			lbp.pos = ly.center() + Vector2(0, 26)
			lbp.carrying = {"log": 1}
			lbp.task = {}
			camera.position = ly.center()
			await _snap(dir + "/25b_lumber_yard.png", 3.5)
			camera.position = mono.center()
		await _snap(dir + "/25_monolith.png", 3.0)
		lbp_clear(c)
	# --- jobs window and the save page
	c.auto_jobs = false
	hud.toggle_jobs_window()
	await _snap(dir + "/32_jobs.png", 2.0)
	hud.close_panel()
	hud.toggle_pause_menu()
	hud._fill_pause_menu("", "save")
	await _snap(dir + "/33_saves.png", 2.0)
	hud._fill_pause_menu("", "history")
	await _snap(dir + "/35_history.png", 2.0)
	hud._fill_pause_menu("", "confirm_menu")
	await _snap(dir + "/36_confirm.png", 2.0)
	hud.toggle_pause_menu()
	# --- war structures of every age
	var wpos := c.home + Vector2i(-14, -14)
	for r in range(0, 40):
		var ok := true
		for yy in range(-1, 6):
			for xx in range(-1, 34):
				var q := c.home + Vector2i(-16 + xx, 14 + r + yy)
				if not sim.world.walkable(q) or sim.building_tiles.has(sim.world.idx(q)) or sim.world.road[sim.world.idx(q)] != 0:
					ok = false
		if ok:
			wpos = c.home + Vector2i(-16, 14 + r)
			break
	for yy in range(-1, 6):
		for xx in range(-1, 34):
			var qi := sim.world.idx(wpos + Vector2i(xx, yy))
			if sim.world.res_type[qi] != Defs.R.NONE:
				sim.world.res_type[qi] = Defs.R.NONE
				_on_tile_changed(wpos + Vector2i(xx, yy))
	var wx := 0
	for t in ["lookout_perch", "war_drum_circle", "sling_platform", "ram_shed", "bastion", "catapult", "ballista_tower", "trebuchet"]:
		c.researched[str(Defs.BUILDINGS[t]["tech"])] = true
		var placed: Building = null
		for dy in range(0, 2):
			for dx in range(0, 3):
				if placed != null:
					break
				var cand := wpos + Vector2i(wx + dx, dy)
				if sim.can_place(c, t, cand) == "":
					placed = sim.place_building(c, t, cand)
			if placed != null:
				break
		if placed != null:
			sim.finish_building(placed)
			wx += placed.size().x + 1
	c.invalidate_bonus()
	camera.position = sim.world.center_of(wpos + Vector2i(wx / 2, 2))
	await _snap(dir + "/34_war_structures.png", 2.2)
	# --- bonus buildings of every age
	var bpos := wpos + Vector2i(0, 7)
	for yy in range(-1, 6):
		for xx in range(-1, 34):
			var q2 := bpos + Vector2i(xx, yy)
			if sim.world.inb(q2):
				var qi2 := sim.world.idx(q2)
				if sim.world.res_type[qi2] != Defs.R.NONE:
					sim.world.res_type[qi2] = Defs.R.NONE
					_on_tile_changed(q2)
	var bx := 0
	for t in ["shaman_circle", "great_hearth", "flint_works", "stone_calendar", "marketplace", "bathhouse", "academy", "iron_foundry"]:
		c.researched[str(Defs.BUILDINGS[t]["tech"])] = true
		var pb: Building = null
		for dy in range(0, 3):
			for dx in range(0, 3):
				if pb == null and sim.can_place(c, t, bpos + Vector2i(bx + dx, dy)) == "":
					pb = sim.place_building(c, t, bpos + Vector2i(bx + dx, dy))
		if pb != null:
			sim.finish_building(pb)
			bx += pb.size().x + 1
	camera.position = sim.world.center_of(bpos + Vector2i(bx / 2, 1))
	await _snap(dir + "/42_bonus_buildings.png", 2.0)
	# --- the tribe asks to send a sick person away
	var sp: Human = c.living()[0]
	Survival.infect(sim, sp, "plague", "rats", true)
	sp.health = 30.0
	sim.exile_asks.append({"pid": sp.id})
	hud._refresh_exile()
	camera.position = sp.pos
	await _snap(dir + "/43_exile.png", 1.6)
	sim.exile_asks.clear()
	hud._refresh_exile()
	# --- research tree header
	hud.toggle_research()
	await _snap(dir + "/37_research.png", 1.0)
	hud.close_panel()
	# --- zones visible in build mode, and the planner with undo
	sim.paint_zone(c, c.home + Vector2i(6, -4), c.home + Vector2i(12, 2), 1)
	sim.paint_zone(c, c.home + Vector2i(-12, 4), c.home + Vector2i(-5, 9), 2)
	sim.paint_zone(c, c.home + Vector2i(2, 6), c.home + Vector2i(8, 11), 3)
	camera.position = sim.world.center_of(c.home)
	start_build("storage")
	await _snap(dir + "/38_build_zones.png", 1.2)
	cancel_build()
	hud.toggle_planner()
	await _snap(dir + "/39_planner.png", 1.2)
	hud.toggle_planner()
	# --- the Weapons designer with a few designs, and a Billy holding one
	for t in Smithing.LEVEL_TECHS:
		c.researched[t] = true
	var ids: Array = []
	for t in ["spear", "short_sword", "longsword"]:
		var dsn := Smithing.starter(t)
		if t == "short_sword":
			for k in dsn["handle"].size():
				if int(dsn["handle"][k]) > 0 and k > 9:
					dsn["handle"][k] = Smithing.code(11, (k % 3))      # gold-wrapped grip
		ids.append(Smithing.save_design(sim, dsn))
	hud.toggle_forge()
	hud.forge_ui._on_type("short_sword")
	hud.forge_ui._on_template()
	hud.forge_ui.name_edit.text = "Sun Blade"
	await _snap(dir + "/44_weapons.png", 1.0)
	hud.toggle_forge()
	var holder: Human = c.living()[0]
	holder.weapon = ids[1]
	holder.job = "soldier"
	camera.position = holder.pos
	await _snap(dir + "/45_custom_weapon_held.png", 4.0)
	# --- roads on the world map, in each tribe's colour
	for oc in sim.colonies:
		if oc.collapsed or oc.bandit:
			continue
		for q in road_tiles_between(sim.world.center_of(oc.home + Vector2i(-10, 3)), sim.world.center_of(oc.home + Vector2i(12, -8))):
			if sim.road_ok(q):
				sim.lay_road(oc, sim.world.idx(q))
	hud.toggle_worldmap()
	hud.worldmap._road_tex = null
	await _snap(dir + "/40_worldmap_roads.png", 1.0)
	hud.worldmap.territory_mode = true
	hud.worldmap._tex_version = -1
	hud.worldmap.set_zoom(3.0)
	hud.worldmap.map_center = Vector2(c.home) / Vector2(sim.world.w, sim.world.h)
	await _snap(dir + "/41_territory_roads.png", 1.0)
	hud.worldmap.set_zoom(1.0)
	hud.worldmap.territory_mode = false
	hud.toggle_worldmap()
	var lake := Vector2i(-1, -1)
	for r in range(3, 60):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var q := c.home + Vector2i(dx, dy)
				if lake.x < 0 and sim.world.bridgeable(q) and sim.world.walkable(q + Vector2i(-1, 0)):
					lake = q
	if lake.x >= 0:
		for q in road_tiles_between(sim.world.center_of(lake + Vector2i(-4, 0)), sim.world.center_of(lake + Vector2i(6, 0))):
			if sim.road_ok(q):
				var bi := sim.world.idx(q)
				if not sim.world.bridgeable(q):
					sim.world.res_type[bi] = Defs.R.NONE
					_on_tile_changed(q)
				sim.lay_road(c, bi)
		camera.position = sim.world.center_of(lake + Vector2i(1, 0))
		await _snap(dir + "/26_bridge.png", 3.0)
	var band := Bandits.band(sim)
	if band != null:
		for b in band.buildings:
			if b.type == "bandit_camp":
				camera.position = b.center()
				selected_building_id = b.id
				hud._refresh_info()
				break
		hud.push_event("Bandits raided your stores and got away with 31 Talents, 12 Animal Hides!", "major_bad")
		hud.push_event("Election day! The tribe votes for a new Chief.", "major")
		await _snap(dir + "/27_bandit_camp.png", 3.0)
		clear_selection()
	# --- settings: game rules tab
	hud._open_settings()
	var sw := hud.settings_layer.find_children("*", "TabContainer", true, false)
	if not sw.is_empty():
		(sw[0] as TabContainer).current_tab = 1
		await _snap(dir + "/28_settings_game.png", 1.5)
		hud._open_settings()
		await get_tree().process_frame
		var sw2 := hud.settings_layer.find_children("*", "TabContainer", true, false)
		for t2 in sw2:
			if is_instance_valid(t2) and not t2.is_queued_for_deletion():
				(t2 as TabContainer).current_tab = 2
		await _snap(dir + "/29_settings_rules.png", 1.5)
	hud.close_panel()
	# --- fog of war
	sim.fog.setup(sim.world, true)
	sim.fog.reveal(c.home, Fog.START_R + 6)
	for p in c.living():
		sim.fog.reveal(sim.world.tile_of(p.pos), Fog.PEOPLE_R)
	sim.fog.texture.update(sim.fog.image)
	camera.position = sim.world.center_of(c.home)
	await _snap(dir + "/30_fog.png", 0.8)
	hud.toggle_worldmap()
	await _snap(dir + "/31_fog_worldmap.png", 1.0)
	hud.toggle_worldmap()
	sim.fog.setup(sim.world, false)
	await _snap(dir + "/17_far_names.png", 0.45)


func ships_demo(sh: Ship) -> void:
	sim.ships.append(sh)


func _snap(path: String, z: float) -> void:
	set_speed(0.0)
	camera.target_zoom = z
	camera.zoom = Vector2(z, z)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


## Scripted check of blueprints, harbor, ships, boarding, sailing and attack orders.
func _cmdtest() -> void:
	sim.event.connect(func(t, k): print("  [EVENT] ", t))
	# start on a coast
	var coast := sim.world.find_nearest(sim.world.spawn, 120, func(q: Vector2i) -> bool:
		return sim.start_problem(q) == "" and sim.dock_tile_for(q + Vector2i(3, 0), Vector2i(2, 2)).x >= 0 and sim.can_place(null, "harbor", q + Vector2i(3, 0)) == "")
	print("coast start: ", coast)
	try_start_at(coast)
	var c := sim.colony
	c.auto_build = false
	c.researched["boatbuilding"] = true
	c.invalidate_bonus()
	for k in ["wood", "stone", "sticks", "grass"]:
		c.add(k, 120.0)
	var b := sim.place_building(c, "harbor", coast + Vector2i(3, 0))
	print("harbor blueprint: ", b != null, " needs ", b.needs())
	set_speed(8.0)
	for i in 120:
		await get_tree().create_timer(0.5).timeout
		if b.built:
			break
	print("harbor built: ", b.built, " delivered ", b.delivered)
	print("order canoe: '", sim.order_ship(c, b, 0), "'")
	for i in 120:
		await get_tree().create_timer(0.5).timeout
		if not sim.ships.is_empty():
			break
	print("ships: ", sim.ships.size())
	if sim.ships.is_empty():
		get_tree().quit()
		return
	var sh: Ship = sim.ships[0]
	var people := c.living().filter(func(p): return p.is_adult())
	for p in people:
		print("  board ", p.name, ": ", HumanAI.order_board(sim, p, sh))
	set_speed(1.0)
	for i in 240:
		await get_tree().process_frame
		if sh.passengers.size() >= people.size():
			break
	print("aboard: ", sh.passengers.size())
	# find land on another landmass: a land tile far away whose nearby sea is reachable
	var far := Vector2i(-1, -1)
	for attempt in 3000:
		var q := Vector2i(sim.rng.randi_range(10, sim.world.w - 10), sim.rng.randi_range(10, sim.world.h - 10))
		if Vector2(q).distance_to(Vector2(coast)) > 60 and sim.world.walkable(q) and sim._nearest_sea(q, 3).x >= 0 \
				and sim.paths.astar.get_id_path(coast, q, false).is_empty():
			far = q
			break
	print("far shore (other landmass): ", far)
	print("sail: '", sim.sail_to(sh, far), "' path ", sh.path.size())
	for i in 200:
		await get_tree().create_timer(0.5).timeout
		if sh.path.is_empty():
			break
	await get_tree().create_timer(1.0).timeout
	print("after voyage: aboard ", sh.passengers.size(), " ship at ", sim.world.tile_of(sh.pos))
	for p in people:
		print("  ", p.name, " at ", sim.world.tile_of(p.pos), " dist to far ", Vector2(sim.world.tile_of(p.pos)).distance_to(Vector2(far)), " state ", p.state)
	# attack the nearest animal
	var p0: Human = people[0]
	var prey: Animal = null
	var bd := 1e18
	for a in sim.animals:
		if a.alive and a.def()["huntable"] and a.pos.distance_squared_to(p0.pos) < bd:
			bd = a.pos.distance_squared_to(p0.pos)
			prey = a
	print("attack ", prey.species, " at dist ", sqrt(bd) / 16.0, ": ", HumanAI.order_attack(sim, p0, "animal", prey.id))
	for i in 80:
		await get_tree().create_timer(0.5).timeout
		if not prey.alive:
			break
	print("prey dead: ", not prey.alive, " attacker hp ", int(p0.health))
	# move order far away (pathing check)
	var dest := sim.world.tile_of(p0.pos) + Vector2i(25, 18)
	print("move order: ", HumanAI.order_move(sim, p0, dest))
	for i in 80:
		await get_tree().create_timer(0.5).timeout
		if str(p0.task.get("type", "")) == "order" and not p0.task.get("moving", false):
			break
	print("moved to ", sim.world.tile_of(p0.pos), " target ", dest, " state ", p0.state)
	print("CMDTEST DONE")
	get_tree().quit()
