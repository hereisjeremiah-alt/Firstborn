class_name AnimalAI
extends RefCounted
## Wildlife behaviour: wander, graze, drink, flee, hunt, fight back and breed.
## Animals far from the camera are updated in coarse steps (level-of-detail simulation).

const MAX_ANIMALS := 1100


static func update(sim: Sim, a: Animal, dt: float) -> void:
	if not a.alive:
		a.carcass_t += dt
		return
	var tile := sim.world.tile_of(a.pos)
	if not sim.active_rect.has_point(tile):
		a.lod_acc += dt
		if a.lod_acc < 0.6:
			return
		dt = a.lod_acc
		a.lod_acc = 0.0
	_tick(sim, a, dt)


static func _tick(sim: Sim, a: Animal, dt: float) -> void:
	var d := a.def()
	var hours := dt / Defs.HOUR
	a.anim += dt
	a.attack_cd = maxf(0.0, a.attack_cd - dt)
	a.age_days += hours / 24.0
	a.hunger = maxf(0.0, a.hunger - 3.0 * hours)
	a.thirst = maxf(0.0, a.thirst - 3.5 * hours)
	if a.hunger <= 0.0 or a.thirst <= 0.0:
		a.health -= 1.5 * hours
		if a.health <= 0.0:
			_die(sim, a)
			return
	a.think_t -= dt
	if a.think_t <= 0.0:
		a.think_t = sim.rng.randf_range(0.45, 0.8)
		_think(sim, a, d)
	_act(sim, a, d, dt)


static func _think(sim: Sim, a: Animal, d: Dictionary) -> void:
	var predator := bool(d["predator"])
	var flying := bool(d.get("flying", false))
	if not predator:
		var threat := _fear(sim, a, flying)
		if threat.x < 1e8:
			var away := (a.pos - threat).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT.rotated(sim.rng.randf() * TAU)
			for k in 5:
				var cand := a.pos + away.rotated((k - 2) * 0.5) * 6.0 * Defs.TILE
				if flying or sim.world.animal_walkable(sim.world.tile_of(cand)):
					a.target = cand
					a.moving = true
					a.state = "flee"
					return
			return
		if a.state == "flee":
			a.state = "wander"
			a.moving = false
	else:
		_predator_think(sim, a, d)
		if a.state == "chase":
			return
	if flying:
		if not a.moving and a.wait <= 0.0:
			a.target = a.pos + Vector2(sim.rng.randf_range(-1, 1), sim.rng.randf_range(-1, 1)) * 8.0 * Defs.TILE
			a.target = a.target.clamp(Vector2.ZERO, Vector2(sim.world.w, sim.world.h) * Defs.TILE)
			a.moving = true
		return
	# needs
	if a.thirst < 35.0 and a.state != "drink":
		var here := sim.world.tile_of(a.pos)
		var w := sim.world
		var water := w.find_nearest(here, 10, func(q: Vector2i) -> bool: return w.is_water(q) and w.t_at(q) != Defs.T.DEEP_OCEAN)
		if water.x >= 0:
			var shore := w.shore_of(water)
			if shore.x >= 0:
				a.state = "drink"
				a.target = w.center_of(shore)
				a.moving = true
				return
		a.thirst = 60.0   # assume it found a puddle somewhere
	if not predator and a.hunger < 40.0 and a.state == "wander" and not a.moving:
		a.state = "graze"
		a.wait = sim.rng.randf_range(3.0, 6.0)
		return
	if a.state == "wander" and not a.moving and a.wait <= 0.0:
		_pick_wander(sim, a, d)


static func _pick_wander(sim: Sim, a: Animal, d: Dictionary) -> void:
	var biomes: Array = d["biomes"]
	for k in 4:
		var cand := a.pos + Vector2(sim.rng.randf_range(-1, 1), sim.rng.randf_range(-1, 1)) * 5.0 * Defs.TILE
		var ct := sim.world.tile_of(cand)
		if not sim.world.animal_walkable(ct):
			continue
		if k < 3 and not biomes.is_empty() and not biomes.has(sim.world.t_at(ct)):
			continue
		a.target = cand
		a.moving = true
		return
	a.wait = sim.rng.randf_range(1.0, 3.0)


## Position of the scariest nearby thing, or (1e9, 1e9) if nothing.
static func _fear(sim: Sim, a: Animal, flying: bool) -> Vector2:
	var human_r := (3.0 if flying else (7.0 if a.hunted_by != -1 else 4.0)) * Defs.TILE
	var best := Vector2(1e9, 1e9)
	var best_d := 1e18
	for p in sim.people_all:
		if not p.alive:
			continue
		var dd: float = p.pos.distance_squared_to(a.pos)
		if dd < human_r * human_r and dd < best_d:
			best_d = dd
			best = p.pos
	if flying:
		return best
	if a.threat_id != -1:
		var t := sim.person(a.threat_id)
		if t != null and t.alive and t.pos.distance_to(a.pos) < 9.0 * Defs.TILE:
			return t.pos
		a.threat_id = -1
	var pr := 5.0 * Defs.TILE
	for o in sim.predators:
		if not o.alive or o == a:
			continue
		var prey: Array = o.def().get("prey", [])
		if not prey.has(a.species):
			continue
		var dd: float = o.pos.distance_squared_to(a.pos)
		if dd < pr * pr and dd < best_d:
			best_d = dd
			best = o.pos
	return best


static func _predator_think(sim: Sim, a: Animal, d: Dictionary) -> void:
	# validate current prey
	if a.prey_id != -1:
		var ppos := _prey_pos(sim, a)
		if ppos.x > 1e8 or ppos.distance_to(a.pos) > 12.0 * Defs.TILE:
			a.prey_id = -1
			a.prey_is_human = false
			a.state = "wander"
		else:
			a.state = "chase"
			a.target = ppos
			a.moving = true
			return
	var night := sim.time.is_night()
	# bears defend their space
	if a.species == "bear":
		for p in sim.people_all:
			if not p.alive:
				continue
			if p.pos.distance_to(a.pos) < 1.6 * Defs.TILE and sim.rng.randf() < 0.12 and not _near_fire(sim, p.pos):
				_target_human(sim, a, p)
				return
	if a.hunger < 55.0:
		var prey: Array = d.get("prey", [])
		var best: Animal = null
		var best_d := pow(10.0 * Defs.TILE, 2)
		for o in sim.animals:
			if not o.alive or not prey.has(o.species):
				continue
			var dd: float = o.pos.distance_squared_to(a.pos)
			if dd < best_d:
				best_d = dd
				best = o
		if best != null:
			a.prey_id = best.id
			a.prey_is_human = false
			a.state = "chase"
			a.target = best.pos
			a.moving = true
			return
	# hungry wolves and big cats may stalk people, mostly at night
	if a.species != "bear" and (a.hunger < 12.0 or (night and a.hunger < 25.0)):
		for p in sim.people_all:
			if not p.alive:
				continue
			if p.pos.distance_to(a.pos) < 5.0 * Defs.TILE and not _near_fire(sim, p.pos):
				_target_human(sim, a, p)
				return


static func _target_human(sim: Sim, a: Animal, p: Human) -> void:
	if a.prey_id != p.id or not a.prey_is_human:
		sim.notify(p.civ_id, "A %s is attacking %s!" % [a.def()["name"].to_lower(), p.name], "bad")
	a.prey_id = p.id
	a.prey_is_human = true
	a.state = "chase"
	a.target = p.pos
	a.moving = true


static func _prey_pos(sim: Sim, a: Animal) -> Vector2:
	if a.prey_is_human:
		var p := sim.person(a.prey_id)
		if p != null and p.alive:
			return p.pos
		return Vector2(1e9, 1e9)
	var o := sim.animal(a.prey_id)
	if o != null and o.alive:
		return o.pos
	return Vector2(1e9, 1e9)


static func _act(sim: Sim, a: Animal, d: Dictionary, dt: float) -> void:
	if a.wait > 0.0:
		a.wait -= dt
		if a.state == "graze":
			a.hunger = minf(100.0, a.hunger + 20.0 * dt / 3.0)
			if a.wait <= 0.0:
				a.state = "wander"
		return
	if a.state == "chase":
		var ppos := _prey_pos(sim, a)
		if ppos.x > 1e8:
			a.state = "wander"
			a.prey_id = -1
			return
		a.target = ppos
		if a.pos.distance_to(ppos) <= 1.1 * Defs.TILE:
			a.moving = false
			if a.attack_cd <= 0.0:
				a.attack_cd = 1.5
				_attack(sim, a, d)
			return
	if not a.moving:
		return
	var flying := bool(d.get("flying", false))
	var mult := 0.5
	if a.state == "flee" or a.state == "chase":
		mult = 1.45
	elif flying:
		mult = 1.0
	var speed := float(d["speed"]) * Defs.TILE * mult
	var to := a.target - a.pos
	var dist := to.length()
	var step := speed * dt
	if dist <= step:
		a.pos = a.target
		_arrive(sim, a)
		return
	var next := a.pos + to / dist * step
	if not flying and not sim.world.animal_walkable(sim.world.tile_of(next)):
		a.moving = false
		a.wait = 0.5
		if a.state == "drink":
			_arrive(sim, a)
		return
	a.pos = next
	if absf(to.x) > 0.5:
		a.facing = signf(to.x)


static func _arrive(sim: Sim, a: Animal) -> void:
	a.moving = false
	match a.state:
		"drink":
			a.thirst = 100.0
			a.state = "wander"
			a.wait = sim.rng.randf_range(1.0, 2.0)
		"flee":
			a.state = "wander"
		"wander":
			a.wait = sim.rng.randf_range(1.0, 5.0)


static func _attack(sim: Sim, a: Animal, d: Dictionary) -> void:
	if a.prey_is_human:
		var p := sim.person(a.prey_id)
		if p == null or not p.alive:
			a.prey_id = -1
			a.state = "wander"
			return
		var dmg := float(d["danger"]) * sim.rng.randf_range(0.4, 0.9) * (1.0 - minf(0.6, sim.col_of(p).bonus("defense")))
		p.health -= dmg
		Fx.lunge(a, p.pos)
		Fx.hit(sim, p.pos, a.pos, dmg, "bite")
		Fx.hurt(p, a.pos)
		var bite := "a %s bite" % a.def()["name"].to_lower()
		if a.species in ["wolf", "jaguar", "fox"] and sim.rng.randf() < 0.015:
			Survival.infect(sim, p, "rabies", bite)
		elif sim.rng.randf() < 0.02:
			Survival.infect(sim, p, "tetanus", bite)
		elif sim.rng.randf() < 0.25:
			Survival.infect(sim, p, "infection", bite)
		if p.health <= 0.0:
			sim.kill(p, "killed by a %s" % a.def()["name"].to_lower())
			a.prey_id = -1
			a.prey_is_human = false
			a.state = "wander"
			a.hunger = 100.0
			return
		# people fight back
		if p.can_work():
			var fight := 6.0 + p.skill("hunter") * 1.5 + sim.col_of(p).bonus("fight")
			if p.job == "hunter":
				fight += 8.0
			var back := fight * sim.rng.randf_range(0.5, 1.2)
			Fx.lunge(p, a.pos)
			var sty := Fx.style_of(p)
			Fx.hit(sim, a.pos, p.pos, back, sty[0], true, sty[1])
			damage(sim, a, back, p)
		if a.species == "bear" and sim.rng.randf() < 0.4:
			a.prey_id = -1
			a.prey_is_human = false
			a.state = "wander"
		return
	var o := sim.animal(a.prey_id)
	if o == null or not o.alive:
		a.prey_id = -1
		a.state = "wander"
		return
	var od := float(d["danger"]) * sim.rng.randf_range(0.8, 1.4)
	o.health -= od
	Fx.lunge(a, o.pos)
	Fx.hit(sim, o.pos, a.pos, od, "bite")
	Fx.hurt(o, a.pos)
	if o.health <= 0.0:
		_die(sim, o)
		o.meat_left = maxi(0, o.meat_left - 3)
		a.hunger = 100.0
		a.prey_id = -1
		a.state = "wander"
		a.wait = 4.0
	else:
		o.threat_id = -1
		o.think_t = 0.0


## Damage dealt by a person (hunting or self-defence).
static func damage(sim: Sim, a: Animal, dmg: float, attacker: Human) -> void:
	a.health -= dmg
	Fx.hurt(a, attacker.pos if attacker != null else a.pos + Vector2(0, -10))
	if a.health <= 0.0:
		_die(sim, a)
		if attacker != null:
			sim.notify(attacker.civ_id, "%s brought down a %s." % [attacker.name, a.def()["name"].to_lower()], "good")
		return
	if float(a.def()["danger"]) > 0.0 and attacker != null:
		a.prey_id = attacker.id
		a.prey_is_human = true
		a.state = "chase"
		a.target = attacker.pos
		a.moving = true
	else:
		alarm(sim, a, attacker)


static func alarm(sim: Sim, a: Animal, by: Human) -> void:
	if by != null:
		a.threat_id = by.id
	a.think_t = 0.0
	a.wait = 0.0


static func _die(sim: Sim, a: Animal) -> void:
	a.alive = false
	a.moving = false
	a.carcass_t = 0.0
	a.state = "dead"


# ---------------------------------------------------------------- daily population dynamics
static func daily(sim: Sim) -> void:
	var season := sim.time.season()
	var scale := sim.land_scale
	var counts := {}
	var alive_list: Array = []
	for a in sim.animals:
		if a.alive:
			counts[a.species] = int(counts.get(a.species, 0)) + 1
			alive_list.append(a)
	# old age
	for a in alive_list:
		if a.age_days > Defs.AGE_YEAR_DAYS * 9.0 and sim.rng.randf() < 0.02:
			_die(sim, a)
	# breeding in spring and summer
	if season <= 1 and alive_list.size() < MAX_ANIMALS:
		# density buckets (8x8 tiles) instead of comparing every animal with every other
		var buckets := {}
		for o in alive_list:
			var oc := Vector2i(o.pos / (8.0 * Defs.TILE))
			var key := "%s|%d|%d" % [o.species, oc.x, oc.y]
			buckets[key] = int(buckets.get(key, 0)) + 1
		var born: Array = []
		for a in alive_list:
			if not a.alive or a.age_days < Defs.AGE_YEAR_DAYS or a.hunger < 40.0:
				continue
			var chance := 0.03 if season == 0 else 0.015
			if a.species == "rabbit":
				chance *= 2.0
			if sim.rng.randf() > chance:
				continue
			var base := float(Defs.ANIMALS[a.species]["count"]) * scale
			if int(counts.get(a.species, 0)) >= int(base * 1.6):
				continue
			var local := 0
			var cell := Vector2i(a.pos / (8.0 * Defs.TILE))
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					local += int(buckets.get("%s|%d|%d" % [a.species, cell.x + ox, cell.y + oy], 0))
			if local >= 8:
				continue
			born.append([a.species, a.pos])
			counts[a.species] = int(counts.get(a.species, 0)) + 1
		for b in born:
			sim.spawn_animal(b[0], b[1] + Vector2(sim.rng.randf_range(-8, 8), sim.rng.randf_range(-8, 8)), 0.0)
	# migration keeps the wider world alive when an area is hunted out
	var homes: Array = []
	for c in sim.colonies:
		homes.append(Vector2(c.home))
	for sp in Defs.ANIMALS.keys():
		var base := float(Defs.ANIMALS[sp]["count"]) * scale
		if int(counts.get(sp, 0)) >= int(base * 0.3):
			continue
		for attempt in 200:
			var t := Vector2i(sim.rng.randi_range(2, sim.world.w - 3), sim.rng.randi_range(2, sim.world.h - 3))
			if _near_any(Vector2(t), homes, 45.0) or not sim._animal_tile_ok(sp, t):
				continue
			for k in int(Defs.ANIMALS[sp]["herd"]):
				sim.spawn_animal(sp, sim.world.center_of(t), Defs.AGE_YEAR_DAYS * 2.0)
			break
	sim.refresh_predators()


static func _near_any(p: Vector2, homes: Array, d: float) -> bool:
	for h in homes:
		if p.distance_to(h) < d:
			return true
	return false


## Wild animals keep away from burning campfires and watchtowers.
static func _near_fire(sim: Sim, pos: Vector2) -> bool:
	var r2 := pow(7.0 * Defs.TILE, 2)
	for c in sim.colonies:
		for b in c.buildings:
			if b.is_lit() and b.center().distance_squared_to(pos) < r2:
				return true
			if b.built and b.type == "watchtower" and b.center().distance_to(pos) < 12.0 * Defs.TILE:
				return true
	return false
