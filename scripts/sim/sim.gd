class_name Sim
extends RefCounted
## The world simulation. Owns the world grid, the clock, weather, wildlife and every civilization,
## and advances them in fixed steps. Rendering and UI only read from it.
## Civilization 0 is the player's tribe; all others are run entirely by CivAI.

signal event(text: String, kind: String)       # kind: info / good / bad / warn
signal tile_changed(tile: Vector2i)
signal buildings_changed()
signal milestone(id: String)

var world: WorldMap
var paths: Pathfinder
var colonies: Array = []       # Colony, index == civ_id
var colony: Colony             # the player's tribe (colonies[0])
var started := false           # tribes have been founded (after the player picks a start)
var people_all: Array = []     # every human of every tribe
var people_by_id := {}
var buildings_by_id := {}
var contacts := {}             # "a:b" -> true once two tribes have met
var relations := {}            # "a:b" -> -100..100
var wars := {}                 # "a:b" -> {"since": day, "dead": {civ_id: n}}
var peace_offers := {}         # civ_id -> true: AI tribes offering the player peace
var name_rng := RandomNumberGenerator.new()   # names differ between games, even on the same seed
var animals: Array = []
var ships: Array = []
var next_ship_id := 1
var sea := AStarGrid2D.new()   # navigation grid for boats
var predators: Array = []      # cached subset of animals that hunt
var time := TimeSystem.new()
var weather := WeatherSystem.new()
var rng := RandomNumberGenerator.new()
var claims := {}               # tile index (or -building id) -> human id
var building_tiles := {}       # tile index -> building id
var active_rect := Rect2i(0, 0, 0, 0)   # tiles near the camera: simulated at full detail
var next_id := 1
var next_animal_id := 1
var next_bid := 1
var used_names := {}
var _last_day := 0
var _hour_acc := 0.0
var _cleanup_t := 0.0
var _weather_msg_day := -1
var _last_season := 0
var debug_log := false
var prof := {}
var tower_shots: Array = []     # [from, to, time left] for drawing arrows
var states: StateMap            # territory states
var claims_in_progress := {}    # civ id -> state id being claimed
var access := {}                # "a>b" -> calendar year until which a's Billies may cross b's land
var access_denied := {}         # "a>b" -> calendar year before which a won't ask b again
var access_asks: Array = []     # AI tribes waiting for the player's answer on passage
var trespass_cd := {}           # "a>b" -> sim time of the next possible incident roll
var fog := Fog.new()
var defect_asks: Array = []     # groups from other tribes asking to join the player (Politics)
var alliances := {}             # "a:b" -> calendar year the alliance was made
var deal_offers: Array = []     # offers from AI tribes waiting for the player (Deals)
var next_deal_id := 1
var play_secs := 0.0            # real seconds played while unpaused (diplomacy waits)
var diplo_cd := {}              # "a>b:kind" -> play_secs when that request may be made again
var stumps := {}                # tile index -> [tree type, sim day felled]: trees that will grow back
var road_tiles := {}            # tile index -> civ id of the tribe that built it
var road_version := 0           # bumped whenever a road is laid or taken up (maps redraw)
var history: Array = []         # [date text, text, kind]: the world history (pause menu)
var fx: Array = []              # combat visuals waiting to be drawn (see Fx)
var fx_on := false              # set by the game while people are drawn
var land_scale := 1.0           # wildlife numbers scale with the amount of land


# ================================================================ setup
## Generates the world and its wildlife. Tribes are founded later with found_tribes().
func new_world(seed_value: int, size: int) -> void:
	world = WorldGen.generate(seed_value, size)
	paths = Pathfinder.new()
	paths.setup(world)
	_setup_sea()
	states = StateMap.build(world, seed_value)
	rng.seed = seed_value + 99
	name_rng.randomize()
	weather.setup(seed_value)
	colony = Colony.new()          # placeholder until the player picks a start
	colony.home = world.spawn
	fog.setup(world, false)        # no fog while choosing a start
	_spawn_animals()
	refresh_predators()
	_last_day = time.day()
	_last_season = time.season()


## Checks whether a tile is an acceptable place to found the player's tribe. "" = ok.
func start_problem(t: Vector2i) -> String:
	if not world.inb(t):
		return "That's outside the world."
	if t.x < 6 or t.y < 6 or t.x > world.w - 7 or t.y > world.h - 7:
		return "Too close to the edge of the world."
	var ter := world.t_at(t)
	if Defs.TERRAIN[ter]["cost"] <= 0.0 or ter == Defs.T.RIVER:
		return "Your people can't live on %s." % Defs.terrain_name(ter).to_lower()
	return ""


func water_distance(t: Vector2i, max_r := 20) -> int:
	for r in range(0, max_r + 1):
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if absi(ox) != r and absi(oy) != r:
					continue
				var q := t + Vector2i(ox, oy)
				if world.inb(q) and world.is_fresh(q):
					return r
	return -1


func found_tribes(player_tile: Vector2i, ai_count: int) -> void:
	colonies.clear()
	people_all.clear()
	people_by_id.clear()
	colony = _found_colony(0, player_tile)
	colony.name = Config.tribe_name
	colony.flag = Config.flag.duplicate()
	var homes: Array = [player_tile]
	var min_d := maxf(30.0, world.w / 5.0)
	for i in ai_count:
		var spot := _pick_ai_spot(homes, min_d)
		if spot.x < 0:
			break
		homes.append(spot)
		_found_colony(colonies.size(), spot)
	# wild predators don't start right on top of a camp
	for a in animals:
		if a.alive and bool(a.def()["predator"]):
			for h in homes:
				if a.pos.distance_to(world.center_of(h)) < 14.0 * Defs.TILE:
					a.alive = false
					a.meat_left = 0
	_cleanup_animals()
	Bandits.spawn_camps(self, homes)
	fog.setup(world, Config.fog_of_war)
	fog.reveal(player_tile, Fog.START_R)
	started = true
	var first: Human = colony.people[0]
	var second: Human = colony.people[1]
	if colony.people.size() <= 2:
		emit_signal("event", "%s and %s awaken in an untamed land. Find water, food and shelter." % [first.name, second.name], "info")
	else:
		emit_signal("event", "%s, %s and %d others awaken in an untamed land. Find water, food and shelter." % [first.name, second.name, colony.people.size() - 2], "info")
	_hook_history()
	chronicle("%s: the first camp is made." % colony.name, "good")
	if colonies.size() > 1:
		emit_signal("event", "Rumours speak of %d other tribes somewhere in this land." % (colonies.size() - 1), "info")


# ================================================================ world history
func _hook_history() -> void:
	if not event.is_connected(_record_history):
		event.connect(_record_history)


func _record_history(text: String, kind: String) -> void:
	if kind.begins_with("major") or text.begins_with("Your tribe has perished"):
		chronicle(text, kind)


## Writes a line into the world history.
func chronicle(text: String, kind := "info") -> void:
	if not history.is_empty() and str(history[-1][1]) == text:
		return
	history.append([time.date_text(), text, kind])
	if history.size() > 600:
		history = history.slice(history.size() - 600)


func _found_colony(civ_id: int, home: Vector2i) -> Colony:
	var c := Colony.new()
	c.civ_id = civ_id
	if civ_id == 0 or not Config.mixed_races:
		c.race = Config.player_race
	else:
		c.race = name_rng.randi_range(0, maxi(0, Config.races.size() - 1))
	var taken := {}
	for oc in colonies:
		taken[oc.name] = true
	c.name = Names.tribe(name_rng, c.race, taken)
	if civ_id < Defs.TRIBE_COLORS.size():
		c.color = Defs.TRIBE_COLORS[civ_id]
	else:
		c.color = Color.from_hsv(name_rng.randf(), 0.65, 0.95)
	c.flag = FlagArt.random_flag(name_rng, c.color)
	c.is_player = civ_id == 0
	c.home = home
	c.money = Config.rule("start_money")
	c.research_share = Config.rule("research_share")
	c.auto_expand = true
	c.auto_roads = true
	colonies.append(c)
	var hs := states.at(home)
	if hs >= 0 and states.owners[hs] < 0:
		states.set_owner(hs, civ_id)
	# clear a small camp area
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var q := home + Vector2i(ox, oy)
			if world.inb(q) and world.res_type[world.idx(q)] != Defs.R.BERRY_BUSH and world.res_type[world.idx(q)] != Defs.R.NONE:
				world.res_type[world.idx(q)] = Defs.R.NONE
				world.res_amount[world.idx(q)] = 0
				paths.refresh_tile(q)
				emit_signal("tile_changed", q)
	var base := world.center_of(home)
	var n := clampi(int(Config.rule("start_people")), 2, 10)
	var jobs := ["laborer", "gatherer", "hunter", "gatherer", "woodcutter", "builder", "laborer", "hunter", "gatherer", "laborer"]
	var k := 0
	while k < n:
		var off := Vector2(rng.randf_range(-14, 14), rng.randf_range(-10, 10))
		var m := _make_human(c, "M", rng.randf_range(18.0, 24.0) * Defs.AGE_YEAR_DAYS, base + off + Vector2(-6, 0))
		m.job = jobs[k % jobs.size()]
		m.skills = {"hunter": 2.0, "woodcutter": 1.0}
		k += 1
		if k >= n:
			break
		var f := _make_human(c, "F", rng.randf_range(18.0, 23.0) * Defs.AGE_YEAR_DAYS, base + off + Vector2(6, 0))
		f.job = jobs[k % jobs.size()]
		f.skills = {"gatherer": 2.0, "healer": 1.0}
		m.partner_id = f.id
		f.partner_id = m.id
		k += 1
	return c


func _announce_techs() -> void:
	for id in colony.just_researched:
		var td: Dictionary = Defs.TECHS[id]
		var extra := ""
		var unl: Array = td.get("unlocks", [])
		if not unl.is_empty():
			extra = " Unlocks: %s." % ", ".join(PackedStringArray(unl.map(func(b): return str(Defs.BUILDINGS[b]["name"]))))
		emit_signal("event", "New technology: %s!%s" % [td["name"], extra], "major_good")
	colony.just_researched.clear()


## A new AI tribe founded mid-game (a breakaway group) at `home`, with no people yet.
func new_tribe(home: Vector2i, race: int) -> Colony:
	var c := Colony.new()
	c.civ_id = colonies.size()
	c.race = race
	var taken := {}
	for oc in colonies:
		taken[oc.name] = true
	c.name = Names.tribe(name_rng, c.race, taken)
	c.color = Defs.TRIBE_COLORS[c.civ_id] if c.civ_id < Defs.TRIBE_COLORS.size() else Color.from_hsv(name_rng.randf(), 0.65, 0.95)
	c.flag = FlagArt.random_flag(name_rng, c.color)
	c.home = home
	c.research_share = Config.rule("research_share")
	c.auto_expand = true
	c.auto_roads = true
	colonies.append(c)
	var hs := states.at(home)
	if hs >= 0 and int(states.owners[hs]) < 0:
		states.set_owner(hs, c.civ_id)
	return c


func _pick_ai_spot(homes: Array, min_d: float) -> Vector2i:
	var good := [Defs.T.PLAINS, Defs.T.GRASSLAND, Defs.T.VALLEY, Defs.T.FOREST, Defs.T.DENSE_FOREST, Defs.T.RAINFOREST, Defs.T.BEACH,
		Defs.T.SAVANNA, Defs.T.STEPPE, Defs.T.ALPINE]
	var margin := 10
	var d := min_d
	for attempt in 9000:
		if attempt > 0 and attempt % 3000 == 0:
			d *= 0.7
		var p := Vector2i(rng.randi_range(margin, world.w - margin), rng.randi_range(margin, world.h - margin))
		if not good.has(int(world.t_at(p))):
			continue
		var t := world.base_temp[world.idx(p)]
		if attempt < 6000 and (t < 3.0 or t > 26.0):
			continue
		var ok := true
		for h in homes:
			if Vector2(p).distance_to(Vector2(h)) < d:
				ok = false
				break
		if ok and WorldGen.has_fresh_water_near(world, p, 8):
			return p
	return Vector2i(-1, -1)


func _make_human(c: Colony, gender: String, age_days: float, pos: Vector2) -> Human:
	var p := Human.new()
	p.id = next_id
	next_id += 1
	p.civ_id = c.civ_id
	p.gender = gender
	p.age_days = age_days
	p.pos = pos
	p.race = c.race
	p.name = _unique_name(gender, c.race)
	p.offset = Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
	p.think_t = rng.randf_range(0.0, 1.0)
	c.register(p)
	people_all.append(p)
	people_by_id[p.id] = p
	return p


func _unique_name(gender: String, race := 0) -> String:
	var n := Names.person(name_rng, gender, race, used_names)
	if used_names.has(n):
		var k := 2
		while used_names.has("%s %s" % [n, _roman(k)]):
			k += 1
		n = "%s %s" % [n, _roman(k)]
	used_names[n] = true
	return n


func _roman(n: int) -> String:
	var vals := [10, 9, 5, 4, 1]
	var syms := ["X", "IX", "V", "IV", "I"]
	var s := ""
	for i in vals.size():
		while n >= vals[i]:
			s += syms[i]
			n -= vals[i]
	return s


func _spawn_animals() -> void:
	var land := 0
	for i in world.w * world.h:
		if Defs.TERRAIN[world.terrain[i]]["cost"] > 0.0:
			land += 1
	land_scale = float(land) / 42000.0 * Config.rule("animal_density")
	var scale := land_scale
	for sp in Defs.ANIMALS.keys():
		var d: Dictionary = Defs.ANIMALS[sp]
		var target := int(float(d["count"]) * scale)
		var placed := 0
		var tries := 0
		while placed < target and tries < target * 80:
			tries += 1
			var t := Vector2i(rng.randi_range(2, world.w - 3), rng.randi_range(2, world.h - 3))
			if not _animal_tile_ok(sp, t):
				continue
			var herd := rng.randi_range(1, int(d["herd"]))
			for k in herd:
				spawn_animal(sp, world.center_of(t) + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)), rng.randf_range(1.0, 6.0) * Defs.AGE_YEAR_DAYS)
				placed += 1


func _animal_tile_ok(sp: String, t: Vector2i) -> bool:
	var d: Dictionary = Defs.ANIMALS[sp]
	if d.get("flying", false):
		return world.inb(t)
	if not world.animal_walkable(t):
		return false
	var biomes: Array = d["biomes"]
	return biomes.is_empty() or biomes.has(world.t_at(t))


func spawn_animal(sp: String, pos: Vector2, age := 0.0) -> Animal:
	var a := Animal.new()
	a.id = next_animal_id
	next_animal_id += 1
	a.init_species(sp)
	a.pos = pos
	a.target = pos
	a.age_days = age
	a.think_t = rng.randf_range(0.0, 2.0)
	animals.append(a)
	return a


func animal(aid: int) -> Animal:
	for a in animals:
		if a.id == aid:
			return a
	return null


# ================================================================ lookups
func civ(civ_id: int) -> Colony:
	if civ_id >= 0 and civ_id < colonies.size():
		return colonies[civ_id]
	return colony


func col_of(p: Human) -> Colony:
	return civ(p.civ_id)


func person(pid: int) -> Human:
	return people_by_id.get(pid, null)


func building(bid: int) -> Building:
	return buildings_by_id.get(bid, null)


## Sends a message to the player only if it concerns the player's tribe.
func notify(civ_id: int, text: String, kind: String) -> void:
	if civ_id == 0:
		emit_signal("event", text, kind)
	elif debug_log and (text.contains("died") or text.contains("birth")):
		print("  [%s] %s" % [civ(civ_id).name, text])


func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func have_met(a: int, b: int) -> bool:
	return contacts.has(_key(a, b))


func relation(a: int, b: int) -> float:
	return float(relations.get(_key(a, b), 0.0))


static func relation_label(v: float) -> String:
	if v >= 40.0:
		return "Friendly"
	if v >= 10.0:
		return "Cordial"
	if v > -15.0:
		return "Neutral"
	if v > -40.0:
		return "Wary"
	return "Hostile"


# ================================================================ environment queries
func season_temp() -> float:
	return time.season_temp()


func diurnal() -> float:
	return 4.0 * cos((time.hour() - 15.0) / 24.0 * TAU) - 1.0


## Air temperature (°C) at a tile right now.
func temp_at(t: Vector2i) -> float:
	if not world.inb(t):
		return 10.0
	return world.base_temp[world.idx(t)] + season_temp() + diurnal() + weather.temp_offset()


func is_cold_season_tile(i: int) -> bool:
	return world.base_temp[i] + Defs.SEASON_TEMP[3] < 0.5


# ================================================================ main step
func step(dt: float) -> void:
	fog.update(self, dt)
	if not colony.just_researched.is_empty():
		_announce_techs()
	var want_scale := Config.rule("calendar_speed")
	if absf(want_scale - time.scale) > 0.0001:
		time.set_scale(want_scale)
	time.advance(dt)
	var hours := dt / Defs.HOUR
	_hour_acc += hours
	var was := weather.state
	if weather.update(hours, time.season(), temp_at(colony.home) < 1.0):
		if weather.state != was and _weather_msg_day != time.day() and (weather.state == WeatherSystem.W.STORM or weather.state == WeatherSystem.W.SNOW):
			_weather_msg_day = time.day()
			emit_signal("event", "%s rolls in over the land." % ("A storm" if weather.state == WeatherSystem.W.STORM else "Snowfall"), "warn")
	if not started:
		return
	var _t0 := Time.get_ticks_usec()
	for c in colonies:
		var player: bool = c.civ_id == 0
		for p in c.people:
			if not p.alive:
				continue
			if player or active_rect.has_point(world.tile_of(p.pos)):
				HumanAI.update(self, p, dt)
			else:
				# distant tribes are simulated in coarser steps
				p.lod_acc += dt
				if p.lod_acc >= 0.3:
					HumanAI.update(self, p, p.lod_acc)
					p.lod_acc = 0.0
		for b in c.buildings:
			if b.is_lit():
				b.fuel = maxf(0.0, b.fuel - hours * 0.6 / (1.0 + c.bonus("fuel")))
				if b.fuel <= 0.0 and (time.is_night() or temp_at(c.home) < 8.0):
					notify(c.civ_id, "A campfire has burned out in the cold. Someone needs to bring wood or sticks.", "warn")
	var _t1 := Time.get_ticks_usec()
	for a in animals:
		AnimalAI.update(self, a, dt)
	var _t2 := Time.get_ticks_usec()
	_update_ships(dt)
	_update_towers(dt)
	var _t3 := Time.get_ticks_usec()
	prof["humans"] = float(prof.get("humans", 0.0)) + (_t1 - _t0) / 1000.0
	prof["animals"] = float(prof.get("animals", 0.0)) + (_t2 - _t1) / 1000.0
	prof["towers"] = float(prof.get("towers", 0.0)) + (_t3 - _t2) / 1000.0
	_cleanup_t += dt
	if _cleanup_t > 5.0:
		_cleanup_t = 0.0
		_cleanup_animals()
	if _hour_acc >= 1.0:
		_hour_acc -= 1.0
		var _t4 := Time.get_ticks_usec()
		_hourly()
		prof["hourly"] = float(prof.get("hourly", 0.0)) + (Time.get_ticks_usec() - _t4) / 1000.0
	if time.day() != _last_day:
		_last_day = time.day()
		_daily()


func _hourly() -> void:
	var yrs := time.cal_years()
	for c in colonies:
		c.now_years = yrs
		if c.collapsed or c.bandit:
			continue
		Survival.hourly(self, c)
		_produce(c)
		CivAI.update(self, c)
		Elections.update(self, c)
	Bandits.hourly(self)
	_check_contacts()
	Borders.check_trespass(self)
	Deals.expire(self)
	Milestones.check(self)


## Hourly output of production buildings.
func _produce(c: Colony) -> void:
	for b in c.buildings:
		if not b.built:
			continue
		match b.type:
			"research_table":
				# materials on the table are slowly used up (visual only; KP is earned on delivery)
				b.stored = maxf(0.0, b.stored - 2.0)
			"well":
				c.add("water", minf(6.0, maxf(0.0, c.water_capacity() - c.count("water"))))
			"harbor":
				if b.ship_order >= 0:
					b.ship_progress += 1.0 / float(Defs.SHIP_TYPES[b.ship_order]["hours"])
					if b.ship_progress >= 1.0:
						_launch_ship(c, b)


func _cleanup_animals() -> void:
	var keep: Array = []
	for a in animals:
		if a.alive or (a.carcass_t < Defs.DAY_SECONDS * 1.5 and a.meat_left > 0):
			keep.append(a)
	animals = keep
	refresh_predators()


func refresh_predators() -> void:
	predators.clear()
	for a in animals:
		if a.alive and bool(a.def()["predator"]):
			predators.append(a)


func _daily() -> void:
	for c in colonies.duplicate():
		Politics.daily(self, c)
	for i in _border_blocked:
		if int(claims.get(i, 0)) == -7:
			claims.erase(i)
	_border_blocked.clear()
	var season := time.season()
	if season != _last_season:
		_last_season = season
		_on_new_season(season)
	for c in colonies:
		if c.collapsed or c.bandit:
			continue
		Survival.daily(self, c)
		_farms(c, season)
		# a trickle of Talents from crafts and beachcombing keeps money moving between tribes
		c.money += Config.rule("shell_income") * c.population()
	_drift_relations()
	_regrow(season)
	_regrow_trees(season)
	AnimalAI.daily(self)


func _on_new_season(season: int) -> void:
	match season:
		0:
			emit_signal("event", "Spring arrives. Plants grow again and animals return. (Year %d)" % time.year(), "good")
		1:
			emit_signal("event", "Summer: warm days and plenty of food. People will drink more water.", "info")
		2:
			var fd := colony.food_days()
			emit_signal("event", "Fall has come. Harvest, hunt and dry meat — winter is %d days away. Food stored: %.1f days." % [time.days_to_winter(), fd], "warn")
		3:
			emit_signal("event", "Winter! Natural food is scarce. Keep fires burning and eat from stores.", "bad")


func _regrow(season: int) -> void:
	var grow_berry := season == 0 or season == 1
	var grow_mush := season == 0 or season == 2
	for i in world.regrow_tiles:
		var r := world.res_type[i]
		if r == Defs.R.NONE:
			continue
		var maxa: int = Defs.RES[r]["amount"]
		var amt := world.res_amount[i]
		if amt >= maxa:
			continue
		var add := 0
		if (r == Defs.R.BERRY_BUSH or r == Defs.R.FRUIT_BUSH) and grow_berry:
			add = 3
		elif (r == Defs.R.BERRY_BUSH or r == Defs.R.FRUIT_BUSH) and season == 2 and rng.randf() < 0.5:
			add = 1
		elif r == Defs.R.MUSHROOM and grow_mush:
			add = 1
		elif r == Defs.R.GRASS and season != 3:
			add = 1
		elif r == Defs.R.STICKS and rng.randf() < 0.3:
			add = 1                     # branches keep falling
		if add > 0:
			world.res_amount[i] = mini(maxa, amt + add)
			if amt == 0:
				emit_signal("tile_changed", Vector2i(i % world.w, i / world.w))


func _farms(c: Colony, season: int) -> void:
	for b in c.buildings:
		if b.type != "farm" or not b.built:
			continue
		if b.crop_stage == 1:
			if season == 3:
				b.crop_stage = 0
				b.crop_growth = 0.0
				notify(c.civ_id, "Frost killed unharvested crops in a garden plot.", "bad")
			else:
				# seasons pass 5x faster than daily life, so crops grow faster to fit in a summer
				b.crop_growth += (0.06 if season < 2 else 0.035) + (0.025 if b.tended else 0.0)
				if b.crop_growth >= 1.0:
					b.crop_stage = 2
		b.tended = false


# ================================================================ contact between tribes
var _reach_cache := {}


## True if people can walk between two tribes' homes (same landmass). Cached.
func land_reachable(a: Colony, b: Colony) -> bool:
	var k := "%d,%d>%d,%d" % [a.home.x, a.home.y, b.home.x, b.home.y]
	if _reach_cache.has(k):
		return _reach_cache[k]
	var s := world.walkable_near(a.home, 4)
	var g := world.walkable_near(b.home, 4)
	var ok := s.x >= 0 and g.x >= 0 and not paths.astar.get_id_path(s, g, false).is_empty()
	_reach_cache[k] = ok
	return ok


## Tribes a trader from `c` could walk to and trade with.
func trade_partners(c: Colony) -> Array:
	var out: Array = []
	for o in colonies:
		if o == c or o.collapsed or o.bandit or o.population() == 0:
			continue
		if have_met(c.civ_id, o.civ_id) and relation(c.civ_id, o.civ_id) <= -40.0:
			continue
		if land_reachable(c, o) or (c.has_built("harbor") and _nearest_sea(o.home, 20).x >= 0):
			out.append(o)
	return out


## Sells goods carried by a trader of `seller` to `buyer` and buys back what the seller's tribe
## needs. Returns the goods bought (to carry home).
func do_trade(p: Human, seller: Colony, buyer: Colony) -> Dictionary:
	var rel := relation(seller.civ_id, buyer.civ_id)
	var mood := 1.0 + rel / 250.0
	var earned := 0.0
	var sold := PackedStringArray()
	for item in p.carrying.keys():
		var amt := float(p.carrying[item])
		var base := float(Defs.BASE_PRICE.get(item, 1.0))
		var demand := clampf(1.7 - buyer.count(item) / 40.0, 0.5, 2.0)
		var price := base * demand * mood
		var afford := floori(buyer.money / maxf(0.01, price))
		var n := mini(int(amt), afford)
		if n <= 0:
			continue
		buyer.money -= n * price
		buyer.add(item, n)
		earned += n * price
		p.carrying[item] = amt - n
		sold.append("%d %s" % [n, Defs.item_name(item).to_lower()])
	for item in p.carrying.keys():
		if float(p.carrying[item]) < 0.5:
			p.carrying.erase(item)
	seller.money += earned
	# buy what home needs: ores for research, or food when short
	var bought := {}
	var spent := 0.0
	var wants: Array = []
	for ore in seller.ore_needed().keys():
		wants.append(ore)
	if seller.food_days() < 4.0:
		wants.append_array(["dried_meat", "cooked_meat", "crops", "berries", "fish", "raw_meat"])
	var room := 20 - int(p.carry_total())
	for item in wants:
		if room <= 0:
			break
		var spare := floori(buyer.count(item) - (12.0 if not Defs.FOOD.has(item) else buyer.living().size() * 4.0))
		if spare <= 0:
			continue
		var price := float(Defs.BASE_PRICE.get(item, 1.0)) * 1.25 / mood
		var budget := seller.money * 0.5
		var n := mini(mini(spare, room), floori(budget / maxf(0.01, price)))
		if n <= 0:
			continue
		buyer.take(item, n)
		buyer.money += n * price
		seller.money -= n * price
		spent += n * price
		bought[item] = int(bought.get(item, 0)) + n
		room -= n
	# trade warms relations and counts as meeting
	var k := _key(seller.civ_id, buyer.civ_id)
	if not contacts.has(k):
		contacts[k] = true
		relations[k] = rng.randf_range(0.0, 15.0)
		if seller.civ_id == 0 or buyer.civ_id == 0:
			var other := buyer if seller.civ_id == 0 else seller
			emit_signal("event", "A trader has made contact with the %s!" % other.name, "good")
	relations[k] = minf(100.0, float(relations.get(k, 0.0)) + 2.0)
	var bought_txt := PackedStringArray()
	for item in bought.keys():
		bought_txt.append("%d %s" % [bought[item], Defs.item_name(item).to_lower()])
	if sold.is_empty() and bought.is_empty():
		var why := "The %s had no %s left to buy %s's goods." % [buyer.name, Defs.MONEY_NAME, p.name]
		if seller.civ_id == 0:
			emit_signal("event", why, "warn")
		return bought
	var line := "%s sold %s to the %s for %d %s" % [p.name, ", ".join(sold) if not sold.is_empty() else "nothing", buyer.name, int(earned), Defs.MONEY_NAME]
	if not bought.is_empty():
		line += " and bought %s for %d" % [", ".join(bought_txt), int(spent)]
	seller.trade_log.append(line + ".")
	if seller.trade_log.size() > 12:
		seller.trade_log.pop_front()
	buyer.trade_log.append("A trader from the %s: %s." % [seller.name, line])
	if buyer.trade_log.size() > 12:
		buyer.trade_log.pop_front()
	if seller.civ_id == 0:
		emit_signal("event", line + ".", "good" if earned > 0.0 else "info")
	elif buyer.civ_id == 0:
		emit_signal("event", "A trader from the %s sold you %s for %d %s." % [seller.name, ", ".join(sold) if not sold.is_empty() else "nothing", int(earned), Defs.MONEY_NAME], "info")
	return bought


func _check_contacts() -> void:
	for a in colonies:
		if a.collapsed or a.bandit:
			continue
		for b in colonies:
			if b.civ_id <= a.civ_id or b.collapsed or b.bandit or have_met(a.civ_id, b.civ_id):
				continue
			if _tribes_touch(a, b) or _tribes_touch(b, a):
				var k := _key(a.civ_id, b.civ_id)
				contacts[k] = true
				relations[k] = rng.randf_range(-10.0, 15.0)
				if a.civ_id == 0 or b.civ_id == 0:
					var other: Colony = b if a.civ_id == 0 else a
					emit_signal("event", "Your people have met the %s! They seem %s." % [other.name, relation_label(relations[k]).to_lower()], "good")


## True if any member of `a` has wandered into `b`'s territory.
func _tribes_touch(a: Colony, b: Colony) -> bool:
	var r := (b.territory() + 4.0) * Defs.TILE
	var home := world.center_of(b.home)
	for p in a.people:
		if p.alive and p.pos.distance_squared_to(home) < r * r:
			return true
	return false


## Fighting sours relations between two tribes (and counts as meeting them).
func on_tribes_clash(a: int, b: int) -> void:
	if a == b or civ(a).bandit or civ(b).bandit:
		return
	var k := _key(a, b)
	contacts[k] = true
	var before := float(relations.get(k, 0.0))
	var after := maxf(-100.0, before - 6.0)
	relations[k] = after
	if (a == 0 or b == 0) and before > -40.0 and after <= -40.0:
		var other := civ(b if a == 0 else a)
		emit_signal("event", "The %s are now hostile to your tribe!" % other.name, "bad")


func _drift_relations() -> void:
	for k in contacts.keys():
		var parts: PackedStringArray = str(k).split(":")
		var a := civ(int(parts[0]))
		var b := civ(int(parts[1]))
		if a.collapsed or b.collapsed:
			continue
		var d := Vector2(a.home).distance_to(Vector2(b.home))
		var v := float(relations.get(k, 0.0))
		if d < a.territory() + b.territory():
			v -= 2.0        # competing for the same land
		else:
			v += (20.0 - v) * 0.05
		relations[k] = clampf(v + rng.randf_range(-1.5, 1.5), -100.0, 100.0)


# ================================================================ resources
func deplete_unit(t: Vector2i) -> void:
	var i := world.idx(t)
	world.res_amount[i] = maxi(0, world.res_amount[i] - 1)
	if world.res_amount[i] <= 0:
		var r := world.res_type[i]
		if not Defs.RES[r]["regrow"]:
			note_stump(i, r)
			world.res_type[i] = Defs.R.NONE
			paths.refresh_tile(t)
		emit_signal("tile_changed", t)


## A tree was cut down here: it will grow back in time, unless something is built on the spot.
func note_stump(i: int, r: int) -> void:
	if r in Defs.TREES:
		stumps[i] = [r, time.day()]


## Daily in spring and summer: felled trees grow back where the ground is still free.
func _regrow_trees(season: int) -> void:
	if stumps.is_empty() or (season != 0 and season != 1):
		return
	var need := Config.rule("tree_regrow_days")
	for i in stumps.keys():
		var e: Array = stumps[i]
		var ii := int(i)
		# a structure or road on the spot: the tree is gone for good
		if building_tiles.has(ii) or world.road[ii] != 0:
			stumps.erase(i)
			continue
		if world.res_type[ii] != Defs.R.NONE:
			stumps.erase(i)
			continue
		if float(time.day() - int(e[1])) < need or _road_planned(ii) or claims.has(ii) or rng.randf() > 0.35:
			continue
		var r := int(e[0])
		world.res_type[ii] = r
		world.res_amount[ii] = int(Defs.RES[r]["amount"])
		var q := Vector2i(ii % world.w, ii / world.w)
		paths.refresh_tile(q)
		emit_signal("tile_changed", q)
		stumps.erase(i)


func claim(t: Vector2i, pid: int) -> void:
	claims[world.idx(t)] = pid


## Marks a tile as off-limits for a day (it lies across a border the tribe may not cross).
var _border_blocked: Array = []
func border_block(t: Vector2i) -> void:
	if not world.inb(t):
		return
	var i := world.idx(t)
	if not claims.has(i):
		claims[i] = -7
		_border_blocked.append(i)


func release_claims(pid: int) -> void:
	for k in claims.keys():
		if claims[k] == pid:
			claims.erase(k)


# ================================================================ buildings
## "" if `type` can be placed at `t`. Pass a colony to also check that it can afford it.
func can_place(c: Colony, type: String, t: Vector2i) -> String:
	var d: Dictionary = Defs.BUILDINGS[type]
	var s: Vector2i = d["size"]
	for y in s.y:
		for x in s.x:
			var q := t + Vector2i(x, y)
			if not world.inb(q):
				return "Outside the world."
			var i := world.idx(q)
			var ter := world.terrain[i]
			if Defs.TERRAIN[ter]["cost"] <= 0.0 or ter == Defs.T.RIVER:
				return "Can't build on %s." % Defs.terrain_name(ter)
			if building_tiles.has(i):
				return "Something is already built here."
			if type != "gate" and (world.road[i] != 0 or _road_planned(i)):
				return "Roads can't be built over (only a gate can stand on a road)."
			var r := world.res_type[i]
			if r in Defs.TREES or r == Defs.R.BOULDER or r == Defs.R.LARGE_STONE or r == Defs.R.BERRY_BUSH \
					or r == Defs.R.FRUIT_BUSH or r >= Defs.R.COPPER_ORE and r <= Defs.R.IRON_ORE:
				return "Clear the %s first." % Defs.RES[r]["name"]
	if c != null and states != null:
		var so := states.owner_at(t)
		if so >= 0 and so != c.civ_id and not c.cheat:
			return "This land belongs to the %s." % civ(so).name
	if type == "harbor" and dock_tile_for(t, s).x < 0:
		return "A harbor must be built on the shore, touching the sea."
	if type == "mine" and not _rocky_near(t, s):
		return "Mines must be dug into hills, rock or a mountainside."
	if c != null and not c.is_unlocked(type):
		return "Research %s first." % Defs.TECHS[str(d["tech"])]["name"]
	return ""


## The hut or house a sleeping person is lying in (null when they sleep outdoors).
func indoors(p: Human) -> Building:
	if not p.sleeping:
		return null
	var b := building_at(world.tile_of(p.pos))
	if b != null and b.built and b.housing() > 0:
		return b
	return null


func _road_planned(i: int) -> bool:
	for oc in colonies:
		if oc.road_marks.has(i):
			return true
	return false


func _rocky_near(t: Vector2i, s: Vector2i) -> bool:
	for y in range(t.y - 2, t.y + s.y + 2):
		for x in range(t.x - 2, t.x + s.x + 2):
			var q := Vector2i(x, y)
			if world.inb(q):
				var ter := world.t_at(q)
				if ter == Defs.T.HILLS or ter == Defs.T.ROCKY or ter == Defs.T.MOUNTAIN:
					return true
	return false


func place_building(c: Colony, type: String, t: Vector2i) -> Building:
	if can_place(c, type, t) != "":
		return null
	var b := Building.new()
	b.id = next_bid
	next_bid += 1
	b.civ_id = c.civ_id
	b.type = type
	b.tile = t
	c.buildings.append(b)
	buildings_by_id[b.id] = b
	_register_building_tiles(b)
	if c.civ_id == 0:
		fog.reveal(b.center_tile(), Fog.BUILDING_R)
	var z := Defs.zone_for(type)
	b.zoned = z > 0 and int(c.zones.get(world.idx(b.center_tile()), 0)) == z
	if c.cheat:
		b.tier = c.best_wall_tier()
		finish_building(b)         # cheat mode: free and instant
	emit_signal("buildings_changed")
	return b


# ================================================================ town planning: zones & roads
## Updates which buildings stand in the zone that suits them.
func refresh_zones(c: Colony) -> void:
	for b in c.buildings:
		var z := Defs.zone_for(b.type)
		b.zoned = z > 0 and int(c.zones.get(world.idx(b.center_tile()), 0)) == z
	c.invalidate_bonus()


## Paints (zone 1-3) or erases (0) a zone over a rectangle of tiles. Returns tiles changed.
func paint_zone(c: Colony, t0: Vector2i, t1: Vector2i, zone: int) -> int:
	var n := 0
	for y in range(mini(t0.y, t1.y), maxi(t0.y, t1.y) + 1):
		for x in range(mini(t0.x, t1.x), maxi(t0.x, t1.x) + 1):
			var q := Vector2i(x, y)
			if not world.inb(q) or Defs.TERRAIN[world.terrain[world.idx(q)]]["cost"] <= 0.0:
				continue
			var i := world.idx(q)
			if zone == 0:
				if c.zones.erase(i):
					n += 1
			elif int(c.zones.get(i, 0)) != zone:
				c.zones[i] = zone
				n += 1
	refresh_zones(c)
	return n


## Whether a road can go on this tile: land (not a building) or, as a bridge, a lake or river.
func road_ok(q: Vector2i) -> bool:
	if not world.inb(q):
		return false
	var i := world.idx(q)
	if building_tiles.has(i) or world.road[i] != 0:
		return false
	if world.bridgeable(q):
		return true
	return Defs.TERRAIN[world.terrain[i]]["cost"] > 0.0


## Marks a road plan along tiles; trees and bushes in the way are marked for clearing.
func plan_road(c: Colony, tiles: Array) -> int:
	var n := 0
	for q in tiles:
		if not road_ok(q):
			continue
		var i := world.idx(q)
		if not c.road_marks.has(i):
			c.road_marks[i] = true
			n += 1
		var rt := world.res_type[i]
		if rt != Defs.R.NONE and not (rt >= Defs.R.COPPER_ORE and rt <= Defs.R.IRON_ORE):
			c.clear_marks[i] = true
	return n


func lay_road(c: Colony, i: int) -> void:
	c.road_marks.erase(i)
	if world.road[i] != 0:
		return
	var q := Vector2i(i % world.w, i / world.w)
	world.road[i] = 2 if world.bridgeable(q) else 1
	road_tiles[i] = c.civ_id
	road_version += 1
	paths.refresh_tile(q)
	if world.road[i] == 2:
		_reach_cache.clear()          # a bridge can join two lands


var last_removed_roads: Array = []    # [tile index, civ id] of built roads the last remove_roads() took up


## Removes road plans and roads in a box. Your own roads (and unowned ones) go at once;
## roads of a tribe you are at war with are marked, and your Billies go and tear them up.
func remove_roads(c: Colony, t0: Vector2i, t1: Vector2i) -> int:
	var n := 0
	last_removed_roads = []
	for y in range(mini(t0.y, t1.y), maxi(t0.y, t1.y) + 1):
		for x in range(mini(t0.x, t1.x), maxi(t0.x, t1.x) + 1):
			var q := Vector2i(x, y)
			if not world.inb(q):
				continue
			var i := world.idx(q)
			if c.road_marks.erase(i):
				n += 1
			if world.road[i] == 0:
				continue
			var owner := int(road_tiles.get(i, -1))
			var oc := civ(owner) if owner >= 0 else null
			if owner == c.civ_id or oc == null or oc.collapsed:
				last_removed_roads.append([i, owner])
				remove_road_tile(i)
				n += 1
			elif at_war(c.civ_id, owner) and not c.wreck_marks.has(i):
				c.wreck_marks[i] = true
				n += 1
	return n


## Takes up one finished road or bridge tile.
func remove_road_tile(i: int) -> void:
	if world.road[i] == 0:
		return
	var q := Vector2i(i % world.w, i / world.w)
	world.road[i] = 0
	road_tiles.erase(i)
	road_version += 1
	paths.refresh_tile(q)
	_reach_cache.clear()


## Lays a road tile again (undo in the town planner).
func restore_road_tile(i: int, owner: int) -> void:
	if world.road[i] != 0 or building_tiles.has(i):
		return
	var q := Vector2i(i % world.w, i / world.w)
	world.road[i] = 2 if world.bridgeable(q) else 1
	road_tiles[i] = owner
	road_version += 1
	paths.refresh_tile(q)
	_reach_cache.clear()


## A Billy at war tore up an enemy road tile.
func wreck_road(c: Colony, i: int) -> void:
	var owner := int(road_tiles.get(i, -1))
	remove_road_tile(i)
	c.wreck_marks.erase(i)
	if owner == 0 and c.civ_id != 0 and rng.randf() < 0.25:
		emit_signal("event", "The %s are tearing up your roads!" % c.name, "warn")


func _register_building_tiles(b: Building) -> void:
	for q in b.tiles():
		var i := world.idx(q)
		building_tiles[i] = b.id
		if world.res_type[i] != Defs.R.NONE:
			world.res_type[i] = Defs.R.NONE
			world.res_amount[i] = 0
			paths.refresh_tile(q)
			emit_signal("tile_changed", q)
		if b.def().get("blocks", false):
			world.blocked[i] = 1


func demolish(b: Building) -> void:
	var c := civ(b.civ_id)
	var cost: Dictionary = b.cost()
	if b.built:
		for k in cost.keys():
			c.add(k, floorf(float(cost[k]) * 0.5))
	else:
		for k in b.delivered.keys():
			c.add(k, float(b.delivered[k]))      # cancelled blueprint: everything delivered comes back
	for q in b.tiles():
		var i := world.idx(q)
		building_tiles.erase(i)
		world.blocked[i] = 0
		if world.wall[i] == 1:
			world.wall[i] = 0
			paths.refresh_tile(q)
	for pid in b.occupants:
		var p := person(int(pid))
		if p != null:
			p.bed_id = -1
	c.buildings.erase(b)
	buildings_by_id.erase(b.id)
	c.invalidate_bonus()
	emit_signal("buildings_changed")


func building_at(t: Vector2i) -> Building:
	if not world.inb(t):
		return null
	var i := world.idx(t)
	if not building_tiles.has(i):
		return null
	return building(int(building_tiles[i]))


func finish_building(b: Building) -> void:
	b.built = true
	b.progress = float(b.def()["work"])
	b.hp = -1.0
	if b.type == "campfire":
		b.fuel = 12.0
	if b.type == "wall":
		for q in b.tiles():
			world.wall[world.idx(q)] = 1
			paths.refresh_tile(q)
	civ(b.civ_id).invalidate_bonus()
	if b.type != "wall" and b.type != "gate":
		notify(b.civ_id, "%s completed." % b.display_name(), "good")
	emit_signal("buildings_changed")


## Damage to a structure from an enemy. Returns true if it was destroyed.
func damage_building(b: Building, dmg: float, attacker_civ: int) -> bool:
	if b == null:
		return false
	var c := civ(b.civ_id)
	if b.hp < 0.0:
		b.hp = b.max_hp()
	b.hp -= dmg
	last_attacker_civ = attacker_civ
	if attacker_civ >= 0 and attacker_civ != b.civ_id:
		on_tribes_clash(attacker_civ, b.civ_id)
	if b.hp > 0.0:
		return false
	var who := civ(attacker_civ).name if attacker_civ >= 0 else "the enemy"
	notify(c.civ_id, "The %s destroyed your %s!" % [who, b.display_name()], "bad")
	if attacker_civ == 0:
		emit_signal("event", "Your soldiers destroyed the %s's %s." % [c.name, b.display_name()], "good")
	destroy_building(b)
	return true


## Removes a structure without refunding anything (destroyed in war).
var last_attacker_civ := -1


func destroy_building(b: Building) -> void:
	var c := civ(b.civ_id)
	if b.type == "bandit_camp":
		Bandits.camp_destroyed(self, b, last_attacker_civ)
	for q in b.tiles():
		var i := world.idx(q)
		building_tiles.erase(i)
		world.blocked[i] = 0
		if world.wall[i] == 1:
			world.wall[i] = 0
			paths.refresh_tile(q)
	for pid in b.occupants:
		var p := person(int(pid))
		if p != null:
			p.bed_id = -1
	c.buildings.erase(b)
	buildings_by_id.erase(b.id)
	c.invalidate_bonus()
	emit_signal("buildings_changed")


# ================================================================ territory states
## How many states a tribe can hold: one, plus one for every three people.
func state_limit(c: Colony) -> int:
	return 999 if c.cheat else 1 + c.population() / 3


func capital_state(c: Colony) -> int:
	return states.at(c.home)


## "" if `civ_id` may claim state s now.
func claim_problem(civ_id: int, s: int) -> String:
	if s < 0:
		return "That's the sea."
	var c := civ(civ_id)
	var owner := int(states.owners[s])
	if owner == civ_id:
		return "%s is already yours." % states.names[s]
	if owner >= 0:
		if not at_war(civ_id, owner):
			return "%s belongs to the %s. You must be at war with them to take it." % [states.names[s], civ(owner).name]
		if s == capital_state(civ(owner)):
			return "That's the %s's homeland — it can't be taken." % civ(owner).name
	if not states.owned_by(civ_id).is_empty() and not states.borders_civ(s, civ_id) and not c.cheat:
		return "%s doesn't border your land." % states.names[s]
	if owner < 0 and states.owned_by(civ_id).size() >= state_limit(c):
		return "Your tribe is too small to hold more land (one state per 3 people)."
	return ""


func claim_state(s: int, civ_id: int) -> void:
	var before := int(states.owners[s])
	states.set_owner(s, civ_id)
	var c := civ(civ_id)
	if civ_id == 0:
		emit_signal("event", ("Your people have claimed %s!" if before < 0 else "Your soldiers have captured %s from the %s!") % ([states.names[s]] if before < 0 else [states.names[s], civ(before).name]), "major_good" if before >= 0 else "good")
	elif before == 0:
		emit_signal("event", "The %s have captured %s from you!" % [c.name, states.names[s]], "major_bad")
	elif have_met(0, civ_id) and before >= 0:
		emit_signal("event", "The %s captured %s from the %s." % [c.name, states.names[s], civ(before).name], "major")
	if before >= 0:
		on_tribes_clash(civ_id, before)


# ================================================================ monolith & cheats
## Skips calendar years at the Monolith: costs knowledge, ages nobody.
func skip_years(c: Colony, years: int) -> String:
	if not c.has_built("monolith"):
		return "Build a Monolith first."
	var cost := years * Config.rule("monolith_kp")
	if c.knowledge < cost and not c.cheat:
		return "You need %d KP to skip %d year%s." % [int(cost), years, "" if years == 1 else "s"]
	if not c.cheat:
		c.knowledge -= cost
	time.skip_days += float(years * Defs.YEAR_DAYS)
	for oc in colonies:
		oc.now_years = time.cal_years()
	if c.civ_id == 0:
		emit_signal("event", "The Monolith hums: %d year%s pass in the blink of an eye. It is now %s." % [years, "" if years == 1 else "s", time.date_text()], "good")
	return ""


## Cheat code: free and instant building, every tech researched, every building unlocked.
func toggle_cheats(c: Colony) -> void:
	c.cheat = not c.cheat
	if c.cheat:
		for id in Defs.TECH_ORDER:
			c.researched[id] = true
		for b in c.buildings:
			if not b.built:
				finish_building(b)
		c.invalidate_bonus()
		emit_signal("event", "CHEATS ON: everything unlocked, building is free and instant.", "good")
	else:
		emit_signal("event", "Cheats off.", "info")
	emit_signal("buildings_changed")


# ================================================================ war & diplomacy
func at_war(a: int, b: int) -> bool:
	if a == b:
		return false
	if a >= 0 and b >= 0 and a < colonies.size() and b < colonies.size() and (colonies[a].bandit or colonies[b].bandit):
		return true          # outlaws are everyone's enemy
	return wars.has(_key(a, b))


## Tribes at war with `a`. The outlaw band counts only when `with_bandits` is set
## (for fighting); diplomacy, war lists and peace never include it.
func enemies_of(a: int, with_bandits := false) -> Array:
	var out: Array = []
	var me := civ(a)
	for c in colonies:
		if c.collapsed or not at_war(a, c.civ_id):
			continue
		if (c.bandit or me.bandit) and not with_bandits:
			continue
		out.append(c)
	return out


## "" if `a` may declare war on `b`.
func war_problem(a: int, b: int) -> String:
	var ca := civ(a)
	if a == b:
		return "You can't declare war on yourself."
	if civ(b).collapsed:
		return "That tribe is gone."
	if at_war(a, b):
		return "You're already at war."
	if Deals.allied(self, a, b):
		return "You are allied. Break the alliance first."
	if ca.era_i < 2:
		return "Wars can only be declared from the Bronze Age."
	return ""


func declare_war(a: int, b: int, border_incident := false) -> bool:
	var why := war_problem(a, b)
	if why != "" and not (border_incident and not at_war(a, b) and not civ(b).collapsed and a != b):
		return false
	var k := _key(a, b)
	contacts[k] = true
	relations[k] = -100.0
	wars[k] = {"since": time.day(), "dead": {}}
	var ca := civ(a)
	var cb := civ(b)
	if a == 0:
		emit_signal("event", "You have declared war on the %s!" % cb.name, "major_bad")
	elif b == 0:
		emit_signal("event", "The %s have declared war on you! Arm your soldiers and man the walls." % ca.name, "major_bad")
	elif have_met(0, a) or have_met(0, b):
		emit_signal("event", "War! The %s have attacked the %s." % [ca.name, cb.name], "major")
	_call_allies(a, b)
	return true


func _call_allies(a: int, b: int) -> void:
	if at_war(a, b):
		Deals.call_allies(self, a, b)


var test_no_peace := false
func make_peace(a: int, b: int) -> void:
	var k := _key(a, b)
	if not wars.has(k) or test_no_peace:
		return
	wars.erase(k)
	relations[k] = -20.0
	peace_offers.erase(a)
	peace_offers.erase(b)
	for p in people_all:
		if p.alive and (p.civ_id == a or p.civ_id == b) and str(p.task.get("type", "")) in ["attack", "raid"]:
			p.task = {}
			p.path = []
	if a == 0 or b == 0:
		emit_signal("event", "Peace has been made with the %s." % civ(b if a == 0 else a).name, "major_good")
	elif have_met(0, a) or have_met(0, b):
		emit_signal("event", "The %s and the %s have made peace." % [civ(a).name, civ(b).name], "major")


## Chance (0..1) that `b` accepts a peace offer from `a` right now.
func peace_chance(a: int, b: int) -> float:
	var k := _key(a, b)
	if not wars.has(k):
		return 0.0
	var w: Dictionary = wars[k]
	var days := float(time.day() - int(w["since"]))
	var lost_b := float((w["dead"] as Dictionary).get(str(b), 0))
	var lost_a := float((w["dead"] as Dictionary).get(str(a), 0))
	var str_a := military_strength(civ(a))
	var str_b := military_strength(civ(b))
	var ch := 0.15 + days * 0.01 + lost_b * 0.08 - lost_a * 0.03
	ch += (str_a - str_b) / maxf(10.0, str_a + str_b) * 0.4
	if civ(a).has_built("capitol"):
		ch += 0.15
	if days < 3.0:
		ch -= 0.3
	return clampf(ch, 0.02, 0.95)


func offer_peace(a: int, b: int) -> bool:
	if Deals.wait_left(self, a, b, "peace") > 0.0:
		if a == 0:
			emit_signal("event", "You must wait %s before offering peace to the %s again." % [Deals.wait_text(self, a, b, "peace"), civ(b).name], "warn")
		return false
	Deals.start_wait(self, a, b, "peace")
	if rng.randf() < peace_chance(a, b):
		make_peace(a, b)
		return true
	if a == 0:
		emit_signal("event", "The %s refused your offer of peace." % civ(b).name, "warn")
	return false


## Rough fighting strength: soldiers with weapons count most.
func military_strength(c: Colony) -> float:
	var v := 0.0
	for p in c.living():
		if p.job == "soldier":
			v += 3.0 + (float(Defs.WEAPONS[p.weapon]["dmg"]) / 6.0 if p.weapon != "" else 0.0) + p.skill("soldier") * 0.5
		elif p.is_adult():
			v += 0.5
	for b in c.buildings:
		if b.built and (b.type == "wall" or b.def().has("shoots")):
			v += 0.3 if b.type == "wall" else 2.0
	return v


## Towers shoot at enemies at war (and predators) within range.
var _tower_acc := 0.0
## Towers, lookouts and siege engines shoot at whatever is in range: towers at enemy people
## (and predators), siege engines at enemy buildings first.
func _update_towers(dt: float) -> void:
	_tower_acc += dt
	if _tower_acc < 0.2 and tower_shots.is_empty():
		return
	dt = _tower_acc
	_tower_acc = 0.0
	for c in colonies:
		if c.collapsed:
			continue
		var foes: Array = []
		var foes_done := false
		for b in c.buildings:
			if not b.built or not b.def().has("shoots"):
				continue
			b.shoot_cd -= dt
			if b.shoot_cd > 0.0:
				continue
			if not foes_done:
				foes = enemies_of(c.civ_id, true)
				foes_done = true
			var sh: Dictionary = b.def()["shoots"]
			var rng_px := float(sh["range"]) * Defs.TILE
			var center: Vector2 = b.center()
			var ammo := str(sh.get("ammo", "arrow"))
			var flight := 0.7 if ammo == "boulder" else 0.25
			if bool(sh.get("siege", false)):
				var tb: Building = null
				var bd := rng_px * rng_px
				for oc in foes:
					for ob in oc.buildings:
						if not ob.built:
							continue
						var d2: float = ob.center().distance_squared_to(center)
						if d2 < bd:
							bd = d2
							tb = ob
				if tb != null:
					b.shoot_cd = float(sh["cd"])
					tower_shots.append([center, tb.center(), flight, ammo, flight])
					Fx.smash(self, tb.center(), center)
					damage_building(tb, float(sh["dmg"]), c.civ_id)
					continue
			var target: Human = null
			var best := rng_px * rng_px
			for oc in foes:
				for p in oc.people:
					if not p.alive or p.at_sea():
						continue
					var d: float = p.pos.distance_squared_to(center)
					if d < best:
						best = d
						target = p
			if target != null:
				b.shoot_cd = float(sh["cd"])
				tower_shots.append([center, target.pos, flight, ammo, flight])
				if rng.randf() < 0.7:
					target.health -= float(sh["dmg"]) * (1.0 - minf(0.6, col_of(target).bonus("defense")))
					Fx.hit(self, target.pos, target.pos + Vector2(0, -20), float(sh["dmg"]), "pierce")
					Fx.hurt(target, target.pos + Vector2(0, -20))
					if target.health <= 0.0:
						kill(target, "shot from a %s of the %s" % [b.display_name().to_lower(), c.name])
				continue
			if bool(sh.get("siege", false)):
				continue
			for a in predators:
				if a.alive and a.pos.distance_squared_to(center) < rng_px * rng_px:
					b.shoot_cd = float(sh["cd"])
					tower_shots.append([center, a.pos, flight, ammo, flight])
					AnimalAI.damage(self, a, float(sh["dmg"]), null)
					break
	var keep: Array = []
	for t in tower_shots:
		t[2] = float(t[2]) - dt
		if float(t[2]) > 0.0:
			keep.append(t)
	tower_shots = keep


# ================================================================ ships
func _setup_sea() -> void:
	sea = AStarGrid2D.new()
	sea.region = Rect2i(0, 0, world.w, world.h)
	sea.cell_size = Vector2(1, 1)
	sea.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	sea.update()
	for y in world.h:
		for x in world.w:
			var t := world.terrain[y * world.w + x]
			var ok := t == Defs.T.OCEAN or t == Defs.T.DEEP_OCEAN or t == Defs.T.LAKE or t == Defs.T.RIVER
			if not ok:
				sea.set_point_solid(Vector2i(x, y), true)


func is_sea(t: Vector2i) -> bool:
	return world.inb(t) and not sea.is_point_solid(t)


func ship(sid: int) -> Ship:
	for sh in ships:
		if sh.id == sid:
			return sh
	return null


func ship_capacity(sh: Ship) -> int:
	return sh.capacity(civ(sh.civ_id))


## Open water next to a harbor's footprint (where its ships are launched). (-1,-1) if none.
func dock_tile_for(t: Vector2i, s: Vector2i) -> Vector2i:
	for y in range(t.y - 1, t.y + s.y + 1):
		for x in range(t.x - 1, t.x + s.x + 1):
			var q := Vector2i(x, y)
			if world.inb(q):
				var ter := world.t_at(q)
				if ter == Defs.T.OCEAN or ter == Defs.T.DEEP_OCEAN:
					return q
	return Vector2i(-1, -1)


## Best ship type this tribe can build.
func best_ship_kind(c: Colony) -> int:
	return mini(Defs.SHIP_TYPES.size() - 1, int(c.bonus("ship_kind")))


## Starts building a ship at a harbor. "" on success, otherwise the reason.
func order_ship(c: Colony, b: Building, kind: int) -> String:
	if not b.built or b.type != "harbor":
		return "The harbor isn't finished yet."
	if b.ship_order >= 0:
		return "This harbor is already building a ship."
	if kind > best_ship_kind(c):
		return "Research more shipbuilding first."
	var cost: Dictionary = Defs.SHIP_TYPES[kind]["cost"]
	if not c.has_cost(cost):
		return "Needs " + Defs.cost_text(cost) + "."
	c.pay(cost)
	b.ship_order = kind
	b.ship_progress = 0.0
	return ""


const SHIP_NAMES := ["Driftwood", "Swift Otter", "Salt Wind", "Grey Gull", "Sea Fang", "Dawn Runner", "Tide Walker", "Storm Petrel",
	"Long Reach", "Whale Song", "Far Shore", "Kelp Rider"]


func _launch_ship(c: Colony, b: Building) -> void:
	var dock := dock_tile_for(b.tile, b.size())
	var sh := Ship.new()
	sh.id = next_ship_id
	next_ship_id += 1
	sh.civ_id = c.civ_id
	sh.kind = b.ship_order
	sh.pos = world.center_of(dock if dock.x >= 0 else b.tile)
	sh.name = SHIP_NAMES[(sh.id - 1) % SHIP_NAMES.size()]
	ships.append(sh)
	b.ship_order = -1
	b.ship_progress = 0.0
	notify(c.civ_id, "The %s has been launched! Select it, then right-click water to sail or a shore to land." % sh.label(), "good")


## Orders a ship to a tile. Water: sail there. Land: sail to the nearest coast and put everyone ashore.
func sail_to(sh: Ship, t: Vector2i) -> String:
	if not world.inb(t):
		return "That's outside the world."
	var from := world.tile_of(sh.pos)
	if not is_sea(from):
		from = _nearest_sea(from, 3)
	var goal := t
	sh.unload_at = Vector2i(-1, -1)
	if not is_sea(t):
		goal = _nearest_sea(t, 8)
		if goal.x < 0:
			return "Ships can't reach that place — pick a spot near the shore."
		sh.unload_at = t
	var pts := sea.get_id_path(from, goal, true)
	if pts.is_empty():
		return "There's no way to sail there."
	sh.path = Array(pts).slice(1)
	if sh.path.is_empty() and sh.unload_at.x >= 0:
		_unload(sh)
	return ""


func _nearest_sea(t: Vector2i, r: int) -> Vector2i:
	return world.find_nearest(t, r, func(q: Vector2i) -> bool: return is_sea(q))


func _update_ships(dt: float) -> void:
	for sh in ships:
		sh.anim += dt
		var c := civ(sh.civ_id)
		sh.idle_t = 0.0 if not sh.path.is_empty() else sh.idle_t + dt
		if not sh.path.is_empty():
			var budget: float = sh.speed(c) * Defs.TILE * dt
			while budget > 0.0 and not sh.path.is_empty():
				var target: Vector2 = world.center_of(sh.path[0])
				var d: Vector2 = target - sh.pos
				var dist: float = d.length()
				if dist > 0.01:
					sh.heading = lerp_angle(sh.heading, d.angle(), 0.25)
				if dist <= budget:
					sh.pos = target
					sh.path.pop_front()
					budget -= dist
				else:
					sh.pos += d / dist * budget
					budget = 0.0
			if sh.path.is_empty() and sh.unload_at.x >= 0:
				_unload(sh)
		elif not sh.passengers.is_empty() and sh.idle_t > Defs.HOUR * 24.0:
			# a ship left idle for hours lets parched or starving passengers go ashore
			for pid in sh.passengers:
				var q := person(int(pid))
				if q != null and (q.thirst < 8.0 or q.hunger < 8.0):
					_unload(sh)
					break
		for pid in sh.passengers:
			var p := person(int(pid))
			if p != null:
				p.pos = sh.pos


## Puts every passenger ashore near the ship and walks them to the chosen spot.
func _unload(sh: Ship) -> void:
	var here := world.tile_of(sh.pos)
	var land := world.find_nearest(here, 4, func(q: Vector2i) -> bool: return world.walkable(q) and world.t_at(q) != Defs.T.RIVER)
	if land.x < 0:
		notify(sh.civ_id, "The %s found no place to land here." % sh.label(), "warn")
		sh.unload_at = Vector2i(-1, -1)
		return
	var target := sh.unload_at if sh.unload_at.x >= 0 else land
	var n := 0
	for pid in sh.passengers:
		var p := person(int(pid))
		if p == null:
			continue
		p.aboard = -1
		p.pos = world.center_of(land) + Vector2(n % 3 - 1, n / 3) * 5.0
		HumanAI.order_move(self, p, target)
		n += 1
	sh.passengers.clear()
	sh.unload_at = Vector2i(-1, -1)
	if n > 0:
		notify(sh.civ_id, "%d people went ashore from the %s." % [n, sh.label()], "info")


func unload_now(sh: Ship) -> void:
	sh.unload_at = Vector2i(-1, -1)
	_unload(sh)


# ================================================================ people
func give_birth(mother: Human) -> void:
	var c := col_of(mother)
	var father := person(mother.partner_id)
	var g := "M" if rng.randf() < 0.5 else "F"
	var baby := _make_human(c, g, 0.0, mother.pos + Vector2(4, 2))
	baby.mother_id = mother.id
	baby.father_id = father.id if father != null else -1
	baby.job = "child"
	baby.hunger = 80.0
	mother.children.append(baby.id)
	if father != null:
		father.children.append(baby.id)
		if Survival.related(mother, father) and rng.randf() < Config.rule("kin_frailty"):
			baby.frail = true
	mother.health = maxf(10.0, mother.health - 8.0)
	c.births += 1
	notify(c.civ_id, "%s gave birth to a %s named %s!" % [mother.name, "boy" if g == "M" else "girl", baby.name], "good")


func kill(p: Human, cause: String) -> void:
	if not p.alive:
		return
	var c := col_of(p)
	if debug_log and cause == "dehydration":
		var tl := world.tile_of(p.pos)
		print("   DEHYD %s civ%d task=%s state=%s tile=%s water=%.0f path=%d thirst=%.0f" % [p.name, p.civ_id, p.task.get("type", "-"), p.state, tl, c.count("water"), p.path.size(), p.thirst])
	for k in wars.keys():
		var parts: PackedStringArray = str(k).split(":")
		if parts[0] == str(p.civ_id) or parts[1] == str(p.civ_id):
			var dead: Dictionary = wars[k]["dead"]
			dead[str(p.civ_id)] = int(dead.get(str(p.civ_id), 0)) + 1
	p.alive = false
	p.cause = cause
	p.task = {}
	p.path = []
	p.sleeping = false
	release_claims(p.id)
	c.deaths += 1
	if p.bed_id >= 0:
		var b := building(p.bed_id)
		if b != null:
			b.occupants.erase(p.id)
	var partner := person(p.partner_id)
	if partner != null:
		partner.partner_id = -1
	if p.aboard >= 0:
		var sh := ship(p.aboard)
		if sh != null:
			sh.passengers.erase(p.id)
		p.aboard = -1
	notify(c.civ_id, "%s (%d) has died — %s." % [p.name, int(p.age_years()), cause], "bad")
	if c.population() == 0:
		c.collapsed = true
		for st in states.owned_by(c.civ_id):
			states.set_owner(st, -1)
		for k in wars.keys():
			var parts: PackedStringArray = str(k).split(":")
			if parts[0] == str(c.civ_id) or parts[1] == str(c.civ_id):
				wars.erase(k)
		if c.civ_id == 0:
			emit_signal("event", "Your tribe has perished. Its story ends here.", "bad")
		elif have_met(0, c.civ_id):
			emit_signal("event", "The %s have perished. Their camp lies empty." % c.name, "major")
		else:
			emit_signal("event", "Travellers whisper that a distant tribe, the %s, has vanished." % c.name, "info")


# ================================================================ save / load
func to_dict() -> Dictionary:
	var an: Array = []
	for a in animals:
		an.append(a.to_dict())
	var cols: Array = []
	for c in colonies:
		cols.append(c.to_dict())
	return {
		"version": 3, "seed": world.seed_value, "size": world.w, "time": time.t, "skip_days": time.skip_days, "cal_scale": time.scale,
		"weather": weather.to_dict(), "colonies": cols, "animals": an,
		"contacts": contacts.keys(), "relations": relations.duplicate(), "wars": wars.duplicate(true),
		"config": Config.to_dict(), "state_owner": Array(states.owners),
		"res_type": world.res_type, "res_amount": world.res_amount, "fish": world.fish,
		"next_id": next_id, "next_animal_id": next_animal_id, "next_bid": next_bid,
		"ships": ships.map(func(sh): return sh.to_dict()), "next_ship_id": next_ship_id,
		"used_names": used_names.keys(), "rng": rng.state, "last_day": _last_day,
		"defect_asks": defect_asks.duplicate(true), "borders": Borders.to_dict(self), "play_secs": play_secs, "diplo_cd": diplo_cd.duplicate(), "roads": road_tiles.keys(), "road_civ": road_tiles.values(), "history": history.duplicate(true), "stumps_i": stumps.keys(), "stumps_v": stumps.values(), "deals": Deals.to_dict(self), "fog": fog.to_save(),
	}


func from_dict(d: Dictionary) -> void:
	if d.has("config"):
		Config.from_dict(d["config"])
	world = WorldGen.generate(int(d["seed"]), int(d["size"]))
	world.res_type = d["res_type"]
	world.res_amount = d["res_amount"]
	world.fish = d["fish"]
	world.fish_day.fill(int(float(d["time"])))
	world.build_regrow_list()
	time.t = float(d["time"])
	time.skip_days = float(d.get("skip_days", 0.0))
	time.scale = float(d.get("cal_scale", TimeSystem.CAL_SCALE))
	weather.setup(world.seed_value)
	weather.from_dict(d["weather"])
	colonies.clear()
	var col_data: Array = d.get("colonies", [])
	if col_data.is_empty() and d.has("colony"):
		col_data = [d["colony"]]       # version 1 saves had a single tribe
	for cd in col_data:
		var c := Colony.new()
		c.from_dict(cd)
		colonies.append(c)
	colony = colonies[0]
	contacts.clear()
	for k in d.get("contacts", []):
		contacts[k] = true
	relations = d.get("relations", {})
	wars = d.get("wars", {})
	Borders.from_dict(self, d.get("borders", {}))
	Deals.from_dict(self, d.get("deals", {}))
	defect_asks = d.get("defect_asks", [])
	name_rng.randomize()
	animals.clear()
	for ad in d["animals"]:
		animals.append(Animal.from_dict(ad))
	refresh_predators()
	next_id = int(d["next_id"])
	next_animal_id = int(d["next_animal_id"])
	next_bid = int(d["next_bid"])
	used_names.clear()
	for n in d.get("used_names", []):
		used_names[n] = true
	rng.seed = world.seed_value + 99
	rng.state = int(d.get("rng", rng.state))
	_last_day = int(d.get("last_day", time.day()))
	_last_season = time.season()
	building_tiles.clear()
	buildings_by_id.clear()
	people_all.clear()
	people_by_id.clear()
	for c in colonies:
		for b in c.buildings:
			b.civ_id = c.civ_id
			buildings_by_id[b.id] = b
			for q in b.tiles():
				var i := world.idx(q)
				building_tiles[i] = b.id
				if b.def().get("blocks", false):
					world.blocked[i] = 1
				if b.type == "wall" and b.built:
					world.wall[i] = 1
		for p in c.people:
			p.civ_id = c.civ_id
			p.offset = Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			people_all.append(p)
			people_by_id[p.id] = p
	road_tiles.clear()
	var rciv: Array = d.get("road_civ", [])
	var rk: Array = d.get("roads", [])
	for n in rk.size():
		var i := int(rk[n])
		var rq := Vector2i(i % world.w, i / world.w)
		world.road[i] = 2 if world.bridgeable(rq) else 1
		road_tiles[i] = int(rciv[n]) if n < rciv.size() else 0
	road_version += 1
	history = d.get("history", [])
	_hook_history()
	for c in colonies:
		refresh_zones(c)
	fog.from_save(world, d.get("fog", {}))
	play_secs = float(d.get("play_secs", 0.0))
	diplo_cd = d.get("diplo_cd", {})
	stumps.clear()
	var si: Array = d.get("stumps_i", [])
	var sv: Array = d.get("stumps_v", [])
	for k in si.size():
		stumps[int(si[k])] = sv[k]
	paths = Pathfinder.new()
	paths.setup(world)
	_setup_sea()
	states = StateMap.build(world, world.seed_value)
	var so: Array = d.get("state_owner", [])
	if so.size() == states.count():
		for i in so.size():
			states.owners[i] = int(so[i])
	else:
		for c in colonies:
			if not c.collapsed and states.at(c.home) >= 0:
				states.owners[states.at(c.home)] = c.civ_id
	states.version += 1
	for c in colonies:
		c.now_years = time.cal_years()
	ships.clear()
	for sd in d.get("ships", []):
		ships.append(Ship.from_dict(sd))
	next_ship_id = int(d.get("next_ship_id", 1))
	started = true
