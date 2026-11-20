class_name HumanAI
extends RefCounted
## Utility/priority-driven behaviour for every person: needs first, then their job,
## then whatever job the tribe has ranked as most important. Each person holds one task at a time.

const PRIO_FLEE := 100
const PRIO_ORDER := 90       # direct orders from the player (or a tribe defending itself)
const PRIO_DRINK := 80
const PRIO_EAT := 75
const PRIO_SLEEP := 60
const PRIO_WARM := 55
const PRIO_REST := 50
const PRIO_DEFEND := 70     # soldiers turning on enemies near them
const PRIO_RAID := 30       # AI tribes sending soldiers against an enemy (resumed after needs)
const PRIO_JOB := 10
const PRIO_IDLE := 0

const HARVEST_LABEL := {
	"wood": "Chopping wood", "sticks": "Gathering sticks", "stone": "Collecting stone", "grass": "Cutting grass",
	"berries": "Picking berries", "mushrooms": "Picking mushrooms", "fruit": "Picking fruit",
	"copper_ore": "Mining copper ore", "tin_ore": "Mining tin ore", "iron_ore": "Mining iron ore",
}


# ================================================================ main update
static func update(sim: Sim, p: Human, dt: float) -> void:
	_update(sim, p, dt)


static func _update(sim: Sim, p: Human, dt: float) -> void:
	Survival.tick(sim, p, dt)
	if not p.alive:
		return
	if p.aboard >= 0:
		var sh := sim.ship(p.aboard)
		if sh == null:
			p.aboard = -1
		else:
			p.state = "Aboard the %s" % sh.label()
			return
	p.anim += dt
	p.attack_cd = maxf(0.0, p.attack_cd - dt)
	if p.sleeping:
		_sleep_tick(sim, p, dt)
		return
	p.think_t -= dt
	if p.think_t <= 0.0:
		p.think_t = 0.5
		_check_interrupts(sim, p)
	if p.task.is_empty():
		_choose_task(sim, p)
	if not p.task.is_empty():
		_run(sim, p, dt)


static func _check_interrupts(sim: Sim, p: Human) -> void:
	if p.job == "bandit":
		Bandits.interrupts(sim, p)
		return
	var cur := int(p.task.get("prio", 0))
	if p.task.get("type", "") == "voyage" and p.thirst > 5.0 and p.hunger > 5.0:
		return                    # at sea: nothing to do but wait for landfall
	if cur == PRIO_ORDER and p.health > 25.0:
		return                    # following orders: stay on task unless badly hurt
	if not sim.enemies_of(p.civ_id, true).is_empty() and p.can_work():
		var foe := _nearby_enemy(sim, p, 9.0)
		if foe != null:
			if p.job == "soldier" and p.health > 30.0 and cur < PRIO_DEFEND and str(p.task.get("type", "")) != "attack":
				if order_attack(sim, p, "human", foe.id, PRIO_DEFEND):
					return
			elif p.job != "soldier" and cur < PRIO_FLEE and foe.pos.distance_to(p.pos) < 5.0 * Defs.TILE and str(p.task.get("type", "")) != "attack":
				if _set_task(sim, p, "flee", sim.col_of(p).drop_point(p.pos), PRIO_FLEE, {"label": "Fleeing from the %s!" % sim.col_of(foe).name}):
					return
	if cur < PRIO_FLEE:
		var threat := _nearby_threat(sim, p, 5.0)
		if threat != null and (p.job != "hunter" or p.health < 45.0 or threat.def()["danger"] > 20.0):
			var home := sim.col_of(p).drop_point(p.pos)
			if _set_task(sim, p, "flee", home, PRIO_FLEE, {"label": "Fleeing from a %s!" % threat.def()["name"].to_lower()}):
				return
	if p.age_years() < 3.0:
		return
	if p.thirst < 22.0 and cur < PRIO_DRINK:
		if _task_drink(sim, p):
			return
	if p.hunger < 22.0 and cur < PRIO_EAT:
		if _task_eat(sim, p):
			return
	if cur < PRIO_SLEEP and (p.energy < 12.0 or (sim.time.is_night() and p.energy < 85.0)):
		if _task_sleep(sim, p):
			return
	if p.warmth < 35.0 and cur < PRIO_WARM:
		if _task_warm(sim, p):
			return
	if _severely_sick(p) and cur < PRIO_REST:
		_task_rest(sim, p)


static func _choose_task(sim: Sim, p: Human) -> void:
	if p.job == "bandit":
		Bandits.plan(sim, p)
		return
	var a := p.age_years()
	if a < 3.0:
		_task_follow_parent(sim, p)
		return
	if p.thirst < 50.0 and _task_drink(sim, p):
		return
	if p.hunger < 50.0 and _task_eat(sim, p):
		return
	if sim.time.is_night() and p.energy < 95.0 and _task_sleep(sim, p):
		return
	if p.warmth < 50.0 and _task_warm(sim, p):
		return
	if _severely_sick(p) and _task_rest(sim, p):
		return
	if _on_trade_trip(p) and _plan_trade(sim, p):
		return
	if p.task_memory.has("raid_civ") and p.job == "soldier" and p.health > 50.0:
		# back on the march after eating, drinking or sleeping
		var rc := int(p.task_memory["raid_civ"])
		var rp := int(p.task_memory.get("raid_prio", PRIO_RAID))
		if sim.at_war(p.civ_id, rc) or rp == PRIO_ORDER:
			if order_raid(sim, p, rc, rp):
				return
		p.task_memory.erase("raid_civ")
	if p.carry_total() > 0:
		_start_haul(sim, p)
		if not p.task.is_empty():
			return
	if not p.can_work():
		_task_wander(sim, p, 4)
		return
	# anyone keeps a dying fire going, and adults pitch in on construction half the time
	if p.is_adult() and _plan_refuel(sim, p, 10.0):
		return
	if p.is_adult() and p.job != "builder" and sim.rng.randf() < 0.5 and _plan_build(sim, p):
		p.task["helping"] = "builder"
		return
	if p.is_adult() and not sim.col_of(p).clear_marks.is_empty() and p.job in ["woodcutter", "laborer", "gatherer", "builder", "miner"] \
			and sim.rng.randf() < 0.7 and _plan_clear(sim, p):
		return
	if p.is_adult() and not sim.col_of(p).wreck_marks.is_empty() and not p.job in ["researcher", "healer", "trader", "cook"] \
			and sim.rng.randf() < 0.5 and _plan_wreck(sim, p):
		return
	if p.is_adult() and _has_road_work(sim, sim.col_of(p)) and p.job in ["laborer", "builder", "gatherer", "woodcutter"] \
			and sim.rng.randf() < 0.6 and _plan_road(sim, p):
		return
	if p.is_adult() and p.job != "researcher" and sim.rng.randf() < 0.25 and _plan_research(sim, p, true):
		p.task["helping"] = "researcher"
		return
	if _plan_job(sim, p, p.job):
		return
	# own job has nothing to do: help with the tribe's highest-priority work
	var jobs: Array = Defs.JOBS.duplicate()
	jobs.sort_custom(func(x, y): return int(sim.col_of(p).job_priority.get(x, 3)) > int(sim.col_of(p).job_priority.get(y, 3)))
	for j in jobs:
		if j == p.job or j == "soldier" or j == "trader":
			continue
		if a < 14.0 and not (j == "gatherer" or j == "laborer"):
			continue
		if _plan_job(sim, p, j):
			p.task["helping"] = j
			return
	_task_wander(sim, p, 4)


## How much a person can carry (baskets and the like add to it).
static func _cap(sim: Sim, p: Human) -> int:
	return p.carry_capacity() + int(sim.col_of(p).bonus("carry"))


## Work speed for a job: the person's own ability times the tribe's technology.
static func _wm(sim: Sim, p: Human, job: String) -> float:
	return p.work_mult(job) * sim.col_of(p).work_bonus(job)


static func _plan_job(sim: Sim, p: Human, job: String) -> bool:
	match job:
		"gatherer":
			return _plan_gather(sim, p)
		"woodcutter":
			return _plan_harvest(sim, p, Defs.TREES, "woodcutter")
		"lumberer":
			return _plan_lumber(sim, p) or _plan_labor(sim, p)
		"miner":
			var need := sim.col_of(p).ore_needed()
			if not need.is_empty():
				var ores: Array = []
				for k in need.keys():
					ores.append({"copper_ore": Defs.R.COPPER_ORE, "tin_ore": Defs.R.TIN_ORE, "iron_ore": Defs.R.IRON_ORE}[k])
				if _plan_harvest(sim, p, ores, "miner"):
					return true
			return _plan_mine(sim, p) or _plan_harvest(sim, p, Defs.MINE_RES, "miner")
		"hunter":
			return _plan_hunt(sim, p)
		"fisherman":
			return _plan_fish(sim, p)
		"builder":
			return _plan_build(sim, p)
		"farmer":
			return _plan_farm(sim, p)
		"cook":
			return _plan_cook(sim, p)
		"healer":
			return _plan_heal(sim, p)
		"laborer":
			return _plan_labor(sim, p)
		"researcher":
			return _plan_research(sim, p, false)
		"trader":
			return _plan_trade(sim, p) or _plan_labor(sim, p)
		"smith":
			return _plan_smith(sim, p)
		"soldier":
			return _plan_soldier(sim, p)
	return false


# ================================================================ task plumbing
static func _set_task(sim: Sim, p: Human, type: String, dest: Vector2i, prio: int, extra := {}) -> bool:
	_abort(sim, p)
	var t := {"type": type, "prio": prio, "dest": dest, "moving": false, "work": 0.0, "label": type.capitalize()}
	t.merge(extra, true)
	p.task = t
	p.state = str(t["label"])
	if not _go(sim, p, dest):
		p.task = {}
		return false
	return true


## A tribe's leader stays inside its own borders (or close to home before it has any land).
static func leader_may_go(sim: Sim, p: Human, dest: Vector2i) -> bool:
	var c := sim.col_of(p)
	if c.leader_id != p.id or c.bandit:
		return true
	if Vector2(dest).distance_to(Vector2(c.home)) <= 10.0:
		return true
	var so := sim.states.owner_at(dest)
	if so == c.civ_id:
		return true
	if so < 0 and sim.states.owned_by(c.civ_id).is_empty() and Vector2(dest).distance_to(Vector2(c.home)) <= 18.0:
		return true
	return false


static func _go(sim: Sim, p: Human, dest: Vector2i) -> bool:
	var from := sim.world.tile_of(p.pos)
	if from == dest:
		p.path = []
		p.task["moving"] = false
		return true
	if not leader_may_go(sim, p, dest):
		return false
	var path := sim.paths.find_path(from, dest)
	if path.is_empty():
		return false
	if _needs_passage(p):
		var o := Borders.path_blocker(sim, p.civ_id, from, path)
		if o >= 0:
			# foreign land without permission: ask for passage and pick something else for now
			Borders.request(sim, p.civ_id, o)
			sim.border_block(dest)
			return false
	p.path = path
	p.task["moving"] = true
	return true


## Whether this task must respect other tribes' borders. Fights, flight, thirst and hunger don't
## stop at a border, and neither do the player's own direct orders.
static func _needs_passage(p: Human) -> bool:
	var ty := str(p.task.get("type", ""))
	if ty in ["attack", "raid", "flee", "board", "rob", "bandit_home", "wreck"] or p.job == "bandit":
		return false
	var prio := int(p.task.get("prio", 0))
	if ty == "claim":
		return p.civ_id != 0 or prio < PRIO_ORDER
	return prio < PRIO_REST


static func _abort(sim: Sim, p: Human) -> void:
	if not p.task.is_empty():
		if p.task.has("aid"):
			var a := sim.animal(int(p.task["aid"]))
			if a != null:
				if a.hunted_by == p.id:
					a.hunted_by = -1
				if a.claimed_by == p.id:
					a.claimed_by = -1
	sim.release_claims(p.id)
	p.task = {}
	p.path = []


static func _done(sim: Sim, p: Human) -> void:
	_abort(sim, p)
	p.state = "Idle"


## Moves along the current path. Returns true on arrival.
static func _follow(sim: Sim, p: Human, dt: float, speed_bonus := 1.0) -> bool:
	var budget := dt
	var guard := 0
	while not p.path.is_empty() and budget > 0.0 and guard < 64:
		guard += 1
		var nt: Vector2i = p.path[0]
		var ni := sim.world.idx(nt)
		if sim.world.blocked[ni] == 1 and sim.building_tiles.has(ni):
			var gb := sim.building(int(sim.building_tiles[ni]))
			if gb != null and gb.type == "gate" and gb.built and sim.at_war(gb.civ_id, p.civ_id):
				p.task["blocked_by"] = gb.id     # enemies can't pass a gate: they must break it
				return false
		var target := sim.world.center_of(nt) + p.offset
		var cost := sim.world.cost_at(sim.world.tile_of(p.pos))
		if cost <= 0.0:
			cost = 1.0
		var speed := Defs.WALK_SPEED * Defs.TILE * p.speed_mult() * speed_bonus / maxf(1.0, cost)
		var d := target - p.pos
		var dist := d.length()
		if absf(d.x) > 0.5:
			p.facing = signf(d.x)
		if dist <= speed * budget or dist < 0.01:
			p.pos = target
			p.path.pop_front()
			budget -= dist / speed
		else:
			p.pos += d / dist * speed * budget
			budget = 0.0
	return p.path.is_empty()


static func _run(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var type := str(t["type"])
	p.state = str(t.get("label", type))
	# dementia: now and then they stop in the middle of a task, having forgotten what it was
	if p.conditions.has("dementia") and int(t.get("prio", 0)) >= PRIO_JOB and int(t.get("prio", 0)) < PRIO_RAID and type != "confused":
		if sim.rng.randf() < (0.004 + 0.02 * p.dementia_level()) * dt:
			_abort(sim, p)
			p.task = {"type": "confused", "prio": PRIO_JOB + 5, "moving": false, "work": 0.0,
				"wait": sim.rng.randf_range(3.0, 8.0), "label": "Forgot what they were doing"}
			p.state = "Forgot what they were doing"
			return
	if type == "confused":
		t["work"] = float(t["work"]) + dt
		if float(t["work"]) >= float(t["wait"]):
			_done(sim, p)
		return
	if type == "hunt":
		_do_hunt(sim, p, dt)
		return
	if type == "heal":
		_do_heal(sim, p, dt)
		return
	if type == "attack":
		_do_attack(sim, p, dt)
		return
	if type == "raid":
		_do_raid(sim, p, dt)
		return
	if t.get("moving", false):
		# stuck detection: if we barely moved for a while, find a new way round
		t["stuck"] = float(t.get("stuck", 0.0)) + dt
		if float(t["stuck"]) > 2.0:
			var last: Vector2 = t.get("last_pos", Vector2(-9999, -9999))
			t["stuck"] = 0.0
			t["last_pos"] = p.pos
			if last.distance_to(p.pos) < 3.0:
				p.offset = Vector2.ZERO
				if not _go(sim, p, t["dest"]):
					_done(sim, p)
					return
		var bonus := 1.35 if type == "flee" else 1.0
		if not _follow(sim, p, dt, bonus):
			return
		t["moving"] = false
	match type:
		"harvest":
			_do_harvest(sim, p, dt)
		"wreck":
			_do_wreck(sim, p, dt)
		"haul":
			_do_haul(sim, p)
		"drink_stock":
			_do_drink_stock(sim, p)
		"drink_src":
			Survival.drink_at(sim, p, t["src"])
			_done(sim, p)
		"melt_snow":
			t["work"] = float(t["work"]) + dt
			if float(t["work"]) > 3.0:
				p.thirst = maxf(p.thirst, 80.0)
				_done(sim, p)
		"eat_stock":
			Survival.eat_from_stock(sim, p)
			_done(sim, p)
			if p.hunger < 45.0:
				_task_forage(sim, p)
		"sleep":
			if not p.sleeping:
				_go_inside(sim, p)
			p.sleeping = true
			p.state = "Sleeping"
		"rest":
			p.sleeping = true
			p.state = "Resting (sick)"
		"warm":
			t["work"] = float(t["work"]) + dt
			if p.warmth >= 85.0 or float(t["work"]) > 25.0:
				_done(sim, p)
		"flee":
			_done(sim, p)
		"board":
			_do_board(sim, p)
		"order":
			# arrived where the player sent us: hold the position for a while
			t["work"] = float(t["work"]) + dt
			p.state = "Holding position"
			if float(t["work"]) > 25.0:
				_done(sim, p)
		"wander", "follow":
			t["work"] = float(t["work"]) + dt
			if float(t["work"]) >= float(t.get("wait", 2.0)):
				_done(sim, p)
		"butcher":
			_do_butcher(sim, p, dt)
		"fish":
			_do_fish(sim, p, dt)
		"build":
			_do_build(sim, p, dt)
		"deliver":
			_do_deliver(sim, p)
		"farm":
			_do_farm(sim, p, dt)
		"cook", "dry":
			_do_cook(sim, p, dt)
		"refuel":
			_do_refuel(sim, p)
		"fetch_water":
			_do_fetch_water(sim, p, dt)
		"dig":
			_do_dig(sim, p, dt)
		"feed_research":
			_do_feed_research(sim, p)
		"trade_go":
			_do_trade(sim, p)
		"voyage":
			_do_voyage(sim, p, dt)
		"study":
			_do_study(sim, p, dt)
		"mine_work":
			_do_mine(sim, p, dt)
		"clear":
			_do_clear(sim, p, dt)
		"road":
			_do_road(sim, p, dt)
		"fell":
			_do_fell(sim, p, dt)
		"saw":
			_do_saw(sim, p, dt)
		"rob":
			Bandits.do_rob(sim, p)
		"bandit_home":
			Bandits.do_home(sim, p)
		"forge":
			_do_forge(sim, p, dt)
		"train":
			_do_train(sim, p, dt)
		"equip":
			_do_equip(sim, p)
		"claim":
			_do_claim(sim, p, dt)
		_:
			_done(sim, p)


# ================================================================ needs tasks
static func _task_drink(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var dp := c.drop_point(p.pos)
	var here := sim.world.tile_of(p.pos)
	if c.count("water") >= 1.0 and Vector2(dp).distance_to(Vector2(here)) < 40.0:
		return _set_task(sim, p, "drink_stock", dp, PRIO_DRINK, {"label": "Drinking"})
	var src := nearest_fresh_water(sim, here, 30)
	if src.x < 0:
		# far from water (deserts, long trips): head back to the stockpile, look further, or melt snow
		if c.count("water") >= 1.0:
			return _set_task(sim, p, "drink_stock", dp, PRIO_DRINK, {"label": "Heading home for water"})
		src = nearest_fresh_water(sim, here, 90)
		if src.x < 0:
			var snow := sim.world.find_nearest(here, 10, func(q: Vector2i) -> bool: return sim.world.snowy[sim.world.idx(q)] == 1 and not sim.paths.astar.is_point_solid(q))
			if snow.x >= 0:
				return _set_task(sim, p, "melt_snow", snow, PRIO_DRINK, {"label": "Melting snow to drink"})
			return false
	var shore := sim.world.shore_of(src)
	if shore.x < 0:
		return false
	var label := "Drinking from the %s" % Defs.terrain_name(sim.world.t_at(src)).to_lower()
	return _set_task(sim, p, "drink_src", shore, PRIO_DRINK, {"src": src, "label": label})


static func _do_drink_stock(sim: Sim, p: Human) -> void:
	while p.thirst < 95.0 and sim.col_of(p).count("water") >= 1.0:
		sim.col_of(p).take("water", 1.0)
		p.thirst = minf(100.0, p.thirst + 50.0)
	_done(sim, p)
	if p.thirst < 60.0:
		var src := nearest_fresh_water(sim, sim.world.tile_of(p.pos), 40)
		if src.x >= 0 and sim.world.shore_of(src).x >= 0:
			_set_task(sim, p, "drink_src", sim.world.shore_of(src), PRIO_DRINK, {"src": src, "label": "Drinking"})


static func nearest_fresh_water(sim: Sim, from: Vector2i, radius: int) -> Vector2i:
	var w := sim.world
	return w.find_nearest(from, radius, func(q: Vector2i) -> bool: return w.is_fresh(q) and w.shore_of(q).x >= 0)


static func _task_eat(sim: Sim, p: Human) -> bool:
	# eat what we're carrying first
	for item in Defs.EAT_ORDER:
		while p.hunger < 85.0 and int(p.carrying.get(item, 0)) > 0:
			p.carrying[item] = int(p.carrying[item]) - 1
			if int(p.carrying[item]) <= 0:
				p.carrying.erase(item)
			Survival.eat_item(sim, p, item)
	if p.hunger >= 60.0:
		return false
	if sim.col_of(p).food_units() >= 0.5:
		return _set_task(sim, p, "eat_stock", sim.col_of(p).drop_point(p.pos), PRIO_EAT, {"label": "Eating"})
	return _task_forage(sim, p)


static func _task_forage(sim: Sim, p: Human) -> bool:
	var types := {}
	for r in Defs.FOOD_RES:
		types[r] = true
	var tile := sim.world.find_resource(sim.world.tile_of(p.pos), 32, types, sim.claims)
	if tile.x < 0:
		return _plan_dig_roots(sim, p, true)
	if _set_task(sim, p, "harvest", tile, PRIO_EAT, {"tile": tile, "job": "gatherer", "types": types, "eat": true, "label": "Foraging for food"}):
		sim.claim(tile, p.id)
		return true
	return false


static func _find_bed(sim: Sim, p: Human) -> Building:
	if p.bed_id >= 0:
		var b := sim.building(p.bed_id)
		if b != null and b.built:
			return b
		p.bed_id = -1
	for b in sim.col_of(p).buildings:
		if b.built and b.housing() > 0 and b.occupants.size() < b.housing():
			b.occupants.append(p.id)
			p.bed_id = b.id
			return b
	return null


static func _task_sleep(sim: Sim, p: Human) -> bool:
	if _on_trade_trip(p) or p.task_memory.has("raid_civ"):
		# traders on the road and soldiers on campaign camp where they are
		return _set_task(sim, p, "sleep", sim.world.tile_of(p.pos), PRIO_SLEEP, {"label": "Camping on the road"})
	var dest := _rest_spot(sim, p)
	return _set_task(sim, p, "sleep", dest, PRIO_SLEEP, {"label": "Going to sleep"})


static func _rest_spot(sim: Sim, p: Human) -> Vector2i:
	var bed := _find_bed(sim, p)
	if bed != null:
		return bed.center_tile()
	var fire := sim.col_of(p).nearest_building(p.pos, "campfire")
	var base := fire.tile if fire != null else sim.col_of(p).home
	var spot := base + Vector2i(sim.rng.randi_range(-2, 2), sim.rng.randi_range(-2, 2))
	if spot == base:
		spot += Vector2i(1, 1)
	if not sim.world.walkable(spot):
		spot = sim.world.walkable_near(spot, 3)
	return spot if spot.x >= 0 else base


## A person who reached their hut or house goes in and lies down inside it.
static func _go_inside(sim: Sim, p: Human) -> void:
	if p.bed_id < 0:
		return
	var b := sim.building(p.bed_id)
	if b == null or not b.built or b.housing() <= 0:
		return
	if b.center().distance_to(p.pos) > Defs.TILE * 3.0:
		return
	var k := b.occupants.find(p.id)
	var slot := Vector2(float((maxi(0, k) % 3) - 1) * 3.0, float(maxi(0, k) / 3) * 2.0 - 1.0)
	p.pos = b.center() + slot
	p.path = []


static func _sleep_tick(sim: Sim, p: Human, dt: float) -> void:
	var resting := str(p.task.get("type", "")) == "rest"
	p.state = "Resting (sick)" if resting else "Sleeping"
	p.think_t -= dt
	var wake := false
	if p.think_t <= 0.0:
		p.think_t = 1.0
		if _nearby_threat(sim, p, 3.0) != null:
			wake = true
	if p.thirst < 15.0 or p.hunger < 15.0:
		wake = true
	if resting:
		if not _severely_sick(p) and p.energy > 60.0:
			wake = true
	else:
		if not sim.time.is_night() and p.energy >= 90.0:
			wake = true
		if p.energy >= 100.0 and sim.time.hour() > 5.0 and sim.time.hour() < 21.0:
			wake = true
	if wake:
		p.sleeping = false
		_done(sim, p)


static func _task_warm(sim: Sim, p: Human) -> bool:
	var best: Building = null
	var best_d := 1e18
	for f in sim.col_of(p).lit_fires():
		var d: float = f.center().distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = f
	if best == null:
		var sh := sim.col_of(p).nearest_building(p.pos, "shelter")
		if sh == null:
			return false
		return _set_task(sim, p, "warm", sh.center_tile(), PRIO_WARM, {"label": "Sheltering from the cold"})
	var spot := best.tile + Vector2i(sim.rng.randi_range(-1, 1), sim.rng.randi_range(-1, 1))
	if spot == best.tile:
		spot.y += 1
	return _set_task(sim, p, "warm", spot, PRIO_WARM, {"label": "Warming up by the fire"})


static func _severely_sick(p: Human) -> bool:
	return p.is_sick() and bool(Defs.ILLNESS[p.illness["type"]]["severe"])


static func _task_rest(sim: Sim, p: Human) -> bool:
	return _set_task(sim, p, "rest", _rest_spot(sim, p), PRIO_REST, {"label": "Going to rest (sick)"})


static func _task_wander(sim: Sim, p: Human, radius: int) -> void:
	var here := sim.world.tile_of(p.pos)
	var center := sim.col_of(p).home
	if Vector2(here).distance_to(Vector2(center)) < 12.0:
		center = here
	var dest := center + Vector2i(sim.rng.randi_range(-radius, radius), sim.rng.randi_range(-radius, radius))
	if not sim.world.walkable(dest):
		dest = here
	_set_task(sim, p, "wander", dest, PRIO_IDLE, {"label": "Idle" if p.can_work() else "Playing", "wait": sim.rng.randf_range(1.5, 4.0)})
	if p.task.is_empty():
		p.task = {"type": "wander", "prio": PRIO_IDLE, "moving": false, "work": 0.0, "wait": 2.0, "label": "Idle"}


static func _task_follow_parent(sim: Sim, p: Human) -> void:
	var mom := sim.person(p.mother_id)
	if mom == null or not mom.alive:
		mom = sim.person(p.father_id)
	if mom != null and mom.alive:
		if mom.sleeping and sim.world.tile_of(mom.pos).distance_squared_to(sim.world.tile_of(p.pos)) <= 2:
			if sim.indoors(mom) != null:
				p.pos = mom.pos + Vector2(3, 1)       # the little ones sleep inside with their parents
			p.sleeping = true
			p.task = {"type": "sleep", "prio": PRIO_SLEEP, "label": "Sleeping"}
			return
		var dest := sim.world.tile_of(mom.pos)
		if _set_task(sim, p, "follow", dest, PRIO_IDLE, {"label": "Following %s" % mom.name, "wait": 1.0}):
			return
	if sim.time.is_night():
		p.sleeping = true
		p.task = {"type": "sleep", "prio": PRIO_SLEEP, "label": "Sleeping"}
		return
	_task_wander(sim, p, 2)


static func _nearby_threat(sim: Sim, p: Human, radius_tiles: float) -> Animal:
	var r2 := pow(radius_tiles * Defs.TILE, 2)
	for a in sim.animals:
		if not a.alive:
			continue
		var d: Dictionary = a.def()
		if float(d["danger"]) <= 0.0:
			continue
		var hostile: bool = (a.prey_is_human and a.prey_id == p.id) or bool(d["predator"])
		if hostile and a.pos.distance_squared_to(p.pos) < r2:
			return a
	return null


# ================================================================ gathering / harvesting
static func _plan_gather(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var fd := c.food_days()
	var options: Array = []
	options.append([4.0 if fd < 1.0 else (3.0 if fd < 2.5 else (1.5 if fd < 6.0 else (0.8 if fd < 12.0 else 0.3))), Defs.FOOD_RES])
	options.append([(1.3 if c.count("sticks") < 25.0 else 0.3) + (1.6 if c.shortfall("sticks") > 0.0 else 0.0), [Defs.R.STICKS]])
	options.append([(1.1 if c.count("stone") < 20.0 else 0.25) + (1.6 if c.shortfall("stone") > 0.0 else 0.0), [Defs.R.SMALL_STONES]])
	options.append([(1.0 if c.count("grass") < 20.0 else 0.25) + (1.6 if c.shortfall("grass") > 0.0 else 0.0), [Defs.R.GRASS]])
	if c.shortfall("wood") > 0.0 or c.count("wood") < 4.0:
		options.append([2.2 if c.shortfall("wood") > 0.0 else 0.8, Defs.TREES])
	# weighted random order: urgent needs usually win, but materials still get gathered
	for o in options:
		o[0] = float(o[0]) * sim.rng.randf_range(0.4, 1.0)
	options.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	for o in options:
		if _plan_harvest(sim, p, o[1], "gatherer"):
			return true
		# no berries or mushrooms (e.g. in winter): dig for roots instead
		if o[1] == Defs.FOOD_RES and float(o[0]) > 0.6 and _plan_dig_roots(sim, p, false):
			return true
	return false


## Roots and tubers can be dug from open ground all year — the winter fallback food.
static func _plan_dig_roots(sim: Sim, p: Human, eat: bool) -> bool:
	var home := sim.col_of(p).home if not eat else sim.world.tile_of(p.pos)
	var ok := [Defs.T.PLAINS, Defs.T.GRASSLAND, Defs.T.VALLEY, Defs.T.FOREST, Defs.T.HILLS, Defs.T.RAINFOREST, Defs.T.TUNDRA,
		Defs.T.SAVANNA, Defs.T.STEPPE, Defs.T.ALPINE, Defs.T.SWAMP, Defs.T.HIGH_DESERT]
	for attempt in 12:
		var t := home + Vector2i(sim.rng.randi_range(-12, 12), sim.rng.randi_range(-12, 12))
		if not sim.world.inb(t) or not ok.has(int(sim.world.t_at(t))):
			continue
		var i := sim.world.idx(t)
		if sim.world.res_type[i] != Defs.R.NONE or sim.building_tiles.has(i) or sim.claims.has(i):
			continue
		if _set_task(sim, p, "dig", t, PRIO_EAT if eat else PRIO_JOB, {"eat": eat, "label": "Digging for roots"}):
			sim.claim(t, p.id)
			return true
	return false


static func _plan_harvest(sim: Sim, p: Human, types_list: Array, job: String) -> bool:
	var types := {}
	for r in types_list:
		types[r] = true
	var origin := sim.col_of(p).home
	var tile := sim.world.find_resource(origin, Defs.HOME_RADIUS, types, sim.claims)
	if tile.x < 0:
		return false
	var item: String = Defs.RES[sim.world.res_type[sim.world.idx(tile)]]["item"]
	var label: String = HARVEST_LABEL.get(item, "Gathering")
	if job == "miner" and item == "stone":
		label = "Mining stone"
	if _set_task(sim, p, "harvest", tile, PRIO_JOB, {"tile": tile, "job": job, "types": types, "label": label}):
		sim.claim(tile, p.id)
		return true
	return false


static func _do_harvest(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var tile: Vector2i = t["tile"]
	var w := sim.world
	var i := w.idx(tile)
	var r := w.res_type[i]
	var types: Dictionary = t["types"]
	if r == Defs.R.NONE or w.res_amount[i] <= 0 or not types.has(r):
		sim.claims.erase(i)
		if p.carry_total() < _cap(sim, p) and _retarget_harvest(sim, p):
			return
		_after_harvest(sim, p)
		return
	var rd: Dictionary = Defs.RES[r]
	var job := str(t["job"])
	t["work"] = float(t["work"]) + dt * _wm(sim, p, job)
	if float(t["work"]) < float(rd["work"]):
		return
	t["work"] = float(t["work"]) - float(rd["work"])
	sim.deplete_unit(tile)
	var item := str(rd["item"])
	if t.get("eat", false):
		Survival.eat_item(sim, p, item)
		if p.hunger >= 88.0:
			_done(sim, p)
		return
	p.add_carry(item, 1)
	if rd.has("bonus") and sim.rng.randf() < 0.25:
		p.add_carry(str(rd["bonus"]), 1)
	p.gain_skill(job, 0.02)
	if p.carry_total() >= _cap(sim, p):
		sim.claims.erase(i)
		_start_haul(sim, p)


## Looks for another resource of the same kind close by, to fill up before hauling.
static func _retarget_harvest(sim: Sim, p: Human) -> bool:
	var t := p.task
	var here := sim.world.tile_of(p.pos)
	var next := sim.world.find_resource(here, 6, t["types"], sim.claims)
	if next.x < 0:
		return false
	t["tile"] = next
	t["work"] = 0.0
	sim.claim(next, p.id)
	return _go(sim, p, next)


static func _after_harvest(sim: Sim, p: Human) -> void:
	if p.carry_total() > 0 and not p.task.get("eat", false):
		_start_haul(sim, p)
	else:
		_done(sim, p)


static func _start_haul(sim: Sim, p: Human) -> void:
	var first := ""
	for k in p.carrying.keys():
		first = str(k)
		break
	var dest := sim.col_of(p).drop_point(p.pos, first)
	if not _set_task(sim, p, "haul", dest, PRIO_JOB, {"label": "Carrying %s home" % Defs.item_name(first).to_lower()}):
		# nowhere reachable: drop it
		p.carrying = {}
		_done(sim, p)


static func _do_haul(sim: Sim, p: Human) -> void:
	if p.job == "trader":
		Trade.bank(sim, p)
	for k in p.carrying.keys():
		var amt := float(p.carrying[k])
		if k == "water":
			amt = minf(amt, maxf(0.0, sim.col_of(p).water_capacity() - sim.col_of(p).count("water")))
		sim.col_of(p).deposit(str(k), amt)
	p.carrying = {}
	_done(sim, p)


# ================================================================ hunting
static func _plan_hunt(sim: Sim, p: Human) -> bool:
	var home_px := sim.world.center_of(sim.col_of(p).home)
	var max_d2 := pow(Defs.HOME_RADIUS * Defs.TILE, 2)
	# butcher carcasses first (kills by predators or earlier hunts)
	var carcass: Animal = null
	var best_d := 1e18
	for a in sim.animals:
		if a.alive or a.meat_left <= 0 or a.claimed_by != -1:
			continue
		var dh: float = a.pos.distance_squared_to(home_px)
		if dh > max_d2 * 0.6:
			continue
		var d: float = a.pos.distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			carcass = a
	if carcass != null:
		if _set_task(sim, p, "butcher", sim.world.tile_of(carcass.pos), PRIO_JOB, {"aid": carcass.id, "label": "Butchering a %s" % carcass.def()["name"].to_lower()}):
			carcass.claimed_by = p.id
			return true
	var prey: Animal = null
	best_d = 1e18
	var marks := sim.col_of(p).hunt_marks
	for a in sim.animals:
		if not a.alive or not bool(a.def()["huntable"]) or a.hunted_by != -1:
			continue
		var marked := marks.has(a.id)
		if not marked and a.pos.distance_squared_to(home_px) > max_d2:
			continue
		if Borders.forbidden_owner(sim, p.civ_id, sim.world.tile_of(a.pos)) >= 0:
			continue
		var d: float = a.pos.distance_squared_to(p.pos) * (0.02 if marked else 1.0)
		if d < best_d:
			best_d = d
			prey = a
	if prey == null:
		return false
	if _set_task(sim, p, "hunt", sim.world.tile_of(prey.pos), PRIO_JOB, {"aid": prey.id, "repath": 1.0, "time": 0.0, "label": "Hunting a %s" % prey.def()["name"].to_lower()}):
		prey.hunted_by = p.id
		return true
	return false


static func _do_hunt(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var a := sim.animal(int(t["aid"]))
	t["time"] = float(t["time"]) + dt
	if a == null or float(t["time"]) > 80.0:
		_done(sim, p)
		return
	if not a.alive:
		var tile := sim.world.tile_of(a.pos)
		if a.claimed_by == -1 and _set_task(sim, p, "butcher", tile, PRIO_JOB, {"aid": a.id, "label": "Butchering a %s" % a.def()["name"].to_lower()}):
			a.claimed_by = p.id
		else:
			_done(sim, p)
		return
	var dist := p.pos.distance_to(a.pos)
	var reach := 2.6 * Defs.TILE
	if dist <= reach:
		p.path = []
		p.facing = signf(a.pos.x - p.pos.x) if absf(a.pos.x - p.pos.x) > 0.5 else p.facing
		if p.attack_cd <= 0.0:
			p.attack_cd = 1.6
			var hc := sim.col_of(p)
			var hit := 0.42 + p.skill("hunter") * 0.03 + (0.1 if hc.has_built("hunting_camp") else 0.0) + hc.bonus("hunt_hit")
			Fx.lunge(p, a.pos)
			if sim.rng.randf() < hit:
				var hd := 14.0 + p.skill("hunter") + hc.bonus("hunt_dmg")
				Fx.hit(sim, a.pos, p.pos, hd, "pierce")
				AnimalAI.damage(sim, a, hd, p)
				p.gain_skill("hunter", 0.15)
			else:
				Fx.miss(sim, a.pos, p.pos)
				AnimalAI.alarm(sim, a, p)
		return
	if a.pos.distance_to(sim.world.center_of(sim.col_of(p).home)) > Defs.HOME_RADIUS * Defs.TILE * 1.4:
		_done(sim, p)
		return
	t["repath"] = float(t["repath"]) - dt
	if float(t["repath"]) <= 0.0 or p.path.is_empty():
		t["repath"] = 1.0
		# prey running onto another tribe's land: most hunters let it go, a reckless few follow
		if Borders.forbidden_owner(sim, p.civ_id, sim.world.tile_of(a.pos)) >= 0 and not t.get("reckless", false):
			if sim.rng.randf() < 0.85:
				_done(sim, p)
				return
			t["reckless"] = true
		var path := sim.paths.find_path(sim.world.tile_of(p.pos), sim.world.tile_of(a.pos))
		if path.is_empty():
			_done(sim, p)
			return
		p.path = path
	_follow(sim, p, dt, 1.2)


static func _do_butcher(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var a := sim.animal(int(t["aid"]))
	if a == null or a.alive or a.meat_left <= 0:
		_after_harvest(sim, p)
		return
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "hunter")
	p.state = "Butchering"
	if float(t["work"]) < 4.0:
		return
	if a.meat_left > 0:
		p.add_carry("raw_meat", a.meat_left)
	if a.hide_left > 0:
		p.add_carry("hides", a.hide_left)
	if a.bone_left > 0:
		p.add_carry("bones", a.bone_left)
	a.meat_left = 0
	a.hide_left = 0
	a.bone_left = 0
	a.carcass_t = Defs.DAY_SECONDS * 10.0
	_start_haul(sim, p)


# ================================================================ fishing
static func _plan_fish(sim: Sim, p: Human) -> bool:
	var w := sim.world
	var claims := sim.claims
	var day := sim.time.day()
	var winter := sim.time.season() == 3
	var spot := w.find_nearest(sim.col_of(p).home, Defs.HOME_RADIUS, func(q: Vector2i) -> bool:
		if not w.is_water(q):
			return false
		var qi := w.idx(q)
		return w.fish_level(qi, day, winter) >= 1.0 and not claims.has(qi) and w.shore_of(q).x >= 0)
	if spot.x < 0:
		return false
	if _set_task(sim, p, "fish", w.shore_of(spot), PRIO_JOB, {"water": spot, "time": 0.0, "label": "Fishing"}):
		sim.claim(spot, p.id)
		return true
	return false


static func _do_fish(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var water: Vector2i = t["water"]
	var wi := sim.world.idx(water)
	t["time"] = float(t["time"]) + dt
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "fisherman")
	if float(t["work"]) >= 3.0:
		t["work"] = 0.0
		var chance := (clampf(sim.world.fish[wi] / 8.0, 0.15, 0.75) + p.skill("fisherman") * 0.02) * (1.0 + sim.col_of(p).bonus("fish"))
		if sim.time.season() == 3:
			chance *= 0.6
		if sim.rng.randf() < chance:
			p.add_carry("fish", 1)
			sim.world.fish[wi] = maxf(0.0, sim.world.fish[wi] - 1.0)
			p.gain_skill("fisherman", 0.05)
	if int(p.carrying.get("fish", 0)) >= 6 or float(t["time"]) > 45.0 or sim.world.fish[wi] < 0.5:
		_after_harvest(sim, p)


# ================================================================ building
## Blueprints: first carry the missing materials from the stockpile to the site, then build.
static func _plan_build(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var build_b: Building = null
	var deliver_b: Building = null
	var bd := 1e18
	var dd := 1e18
	for b in c.buildings:
		if b.built:
			continue
		var d: float = b.center().distance_squared_to(p.pos)
		if b.supplied():
			if d < bd:
				bd = d
				build_b = b
		elif d < dd and _can_supply(c, b):
			dd = d
			deliver_b = b
	if build_b != null:
		return _set_task(sim, p, "build", build_b.center_tile(), PRIO_JOB, {"bid": build_b.id, "label": "Building %s" % build_b.def()["name"]})
	if deliver_b != null:
		# take what's needed (up to what one person can carry) from the stockpile
		var load := {}
		var room := _cap(sim, p) + 8
		var need := deliver_b.needs()
		for k in need.keys():
			if room <= 0:
				break
			var amt := mini(room, mini(ceili(float(need[k])), floori(c.count(k))))
			if amt > 0:
				c.take(k, float(amt))
				load[k] = amt
				room -= amt
		if load.is_empty():
			return false
		var stock_at := c.drop_point(p.pos)
		p.carrying = load
		if _set_task(sim, p, "deliver", deliver_b.center_tile(), PRIO_JOB, {"bid": deliver_b.id, "from": stock_at,
				"label": "Bringing materials for the %s" % deliver_b.def()["name"]}):
			return true
		for k in load.keys():
			c.add(k, float(load[k]))
		p.carrying = {}
	return false


static func _can_supply(c: Colony, b: Building) -> bool:
	var need := b.needs()
	for k in need.keys():
		if c.count(k) >= 1.0:
			return true
	return false


static func _do_deliver(sim: Sim, p: Human) -> void:
	var b := sim.building(int(p.task["bid"]))
	if b == null or b.built:
		_start_haul(sim, p)          # site is gone: take the goods back
		return
	var need := b.needs()
	for k in p.carrying.keys():
		var give := minf(float(p.carrying[k]), float(need.get(k, 0.0)))
		if give > 0.0:
			b.delivered[k] = float(b.delivered.get(k, 0.0)) + give
			p.carrying[k] = int(p.carrying[k]) - int(give)
	for k in p.carrying.keys():
		if int(p.carrying[k]) <= 0:
			p.carrying.erase(k)
	if p.carry_total() > 0:
		_start_haul(sim, p)
	else:
		_done(sim, p)


static func _do_build(sim: Sim, p: Human, dt: float) -> void:
	var b := sim.building(int(p.task["bid"]))
	if b == null or b.built or not b.supplied():
		_done(sim, p)
		return
	b.progress += dt * _wm(sim, p, "builder")
	p.gain_skill("builder", 0.005)
	if b.progress >= float(b.def()["work"]):
		sim.finish_building(b)
		_done(sim, p)


# ================================================================ farming
static func _plan_farm(sim: Sim, p: Human) -> bool:
	var season := sim.time.season()
	for b in sim.col_of(p).buildings:
		if b.type != "farm" or not b.built:
			continue
		var action := ""
		if b.crop_stage == 2:
			action = "harvest"
		elif b.crop_stage == 0 and season <= 1:
			action = "plant"
		elif b.crop_stage == 1 and not b.tended:
			action = "tend"
		if action == "":
			continue
		var labels := {"harvest": "Harvesting crops", "plant": "Planting seeds", "tend": "Tending the garden"}
		if _set_task(sim, p, "farm", b.center_tile(), PRIO_JOB, {"bid": b.id, "action": action, "label": labels[action]}):
			return true
	return false


static func _do_farm(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var b := sim.building(int(t["bid"]))
	if b == null:
		_done(sim, p)
		return
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "farmer")
	if float(t["work"]) < 6.0:
		return
	p.gain_skill("farmer", 0.1)
	match str(t["action"]):
		"plant":
			b.crop_stage = 1
			b.crop_growth = 0.0
			_done(sim, p)
		"tend":
			b.tended = true
			_done(sim, p)
		"harvest":
			b.crop_stage = 0
			b.crop_growth = 0.0
			p.add_carry("crops", int((12 + p.skill("farmer")) * (1.0 + sim.col_of(p).bonus("farm")) * (1.25 if b.zoned else 1.0)))
			_start_haul(sim, p)


# ================================================================ cooking & preservation
static func _plan_cook(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	if c.raw_food() < 1.0:
		return false
	var rack := c.nearest_building(p.pos, "drying_rack")
	var fire: Building = null
	for f in c.lit_fires():
		fire = f
		break
	if rack != null and (sim.time.season() >= 2 or c.raw_food() >= 6.0 or fire == null):
		return _set_task(sim, p, "dry", rack.tile, PRIO_JOB, {"label": "Drying meat for storage"})
	if fire != null:
		var spot := fire.tile + Vector2i(0, 1)
		return _set_task(sim, p, "cook", spot, PRIO_JOB, {"bid": fire.id, "label": "Cooking at the fire"})
	return false


static func _do_cook(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var c := sim.col_of(p)
	var drying := str(t["type"]) == "dry"
	if not drying:
		var fire := c.building(int(t.get("bid", -1)))
		if fire == null or not fire.is_lit():
			_done(sim, p)
			return
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "cook")
	var per := 2.0 if drying else 2.5
	if float(t["work"]) < per:
		return
	t["work"] = float(t["work"]) - per
	t["made"] = int(t.get("made", 0)) + 1
	p.gain_skill("cook", 0.05)
	if c.count("raw_meat") >= 1.0:
		c.take("raw_meat", 1.0)
		c.add("dried_meat" if drying else "cooked_meat", 1.0)
	elif c.count("fish") >= 1.0:
		c.take("fish", 1.0)
		c.add("dried_meat" if drying else "cooked_fish", 1.0)
	if c.raw_food() < 1.0 or int(t["made"]) >= 8:
		_done(sim, p)


# ================================================================ healing
static func _plan_heal(sim: Sim, p: Human) -> bool:
	var best: Human = null
	var best_score := -1.0
	for q in sim.col_of(p).living():
		if q == p:
			continue
		var needs := false
		if q.is_sick() and sim.time.t - float(q.illness.get("treated", -10.0)) > 0.8:
			needs = true
		elif q.health < 55.0 and not q.is_sick():
			needs = true
		if not needs:
			continue
		var score: float = 100.0 - q.health
		if score > best_score:
			best_score = score
			best = q
	if best == null:
		return false
	return _set_task(sim, p, "heal", sim.world.tile_of(best.pos), PRIO_JOB, {"pid": best.id, "repath": 1.5, "label": "Treating %s" % best.name})


static func _do_heal(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var q := sim.person(int(t["pid"]))
	if q == null or not q.alive or (not q.is_sick() and q.health >= 55.0):
		_done(sim, p)
		return
	if p.pos.distance_to(q.pos) <= 1.5 * Defs.TILE:
		p.path = []
		t["work"] = float(t["work"]) + dt * _wm(sim, p, "healer")
		p.state = "Treating %s" % q.name
		if float(t["work"]) >= 4.0:
			var skill := p.skill("healer") * (1.0 + sim.col_of(p).bonus("heal")) + sim.col_of(p).bonus("heal") * 6.0
			if q.is_sick():
				q.illness["days"] = float(q.illness["days"]) - (1.2 + skill * 0.1)
				q.illness["treated"] = sim.time.t
			q.health = minf(100.0, q.health + 10.0 + skill)
			p.gain_skill("healer", 0.2)
			sim.notify(p.civ_id, "%s treated %s with herbs and care." % [p.name, q.name], "info")
			_done(sim, p)
		return
	t["repath"] = float(t["repath"]) - dt
	if float(t["repath"]) <= 0.0 or p.path.is_empty():
		t["repath"] = 1.5
		var path := sim.paths.find_path(sim.world.tile_of(p.pos), sim.world.tile_of(q.pos))
		if path.is_empty():
			_done(sim, p)
			return
		p.path = path
	_follow(sim, p, dt)


# ================================================================ laborers
static func _plan_labor(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	# 1. keep the fires burning
	if _plan_refuel(sim, p, 16.0):
		return true
	# 2. fetch water
	var want_water := minf(c.water_capacity(), c.population() * 3.0 + 4.0)
	if c.count("water") < want_water:
		var src := nearest_fresh_water(sim, c.home, 40)
		if src.x >= 0:
			var shore := sim.world.shore_of(src)
			if shore.x >= 0 and _set_task(sim, p, "fetch_water", shore, PRIO_JOB, {"src": src, "label": "Fetching water"}):
				return true
	# 3. construction
	if _plan_build(sim, p):
		return true
	# 4. firewood, more in the cold half of the year
	var want_wood := c.population() * 6.0 + (25.0 if sim.time.season() >= 2 else 8.0)
	if (c.count("wood") < want_wood or c.shortfall("wood") > 0.0) and _plan_harvest(sim, p, Defs.TREES, "woodcutter"):
		return true
	# 5. general gathering
	return _plan_gather(sim, p)


static func _plan_refuel(sim: Sim, p: Human, below: float) -> bool:
	var c := sim.col_of(p)
	if c.count("wood") < 1.0 and c.count("sticks") < 2.0:
		return false
	# fires matter when it's cold or the evening is coming
	var hr := sim.time.hour()
	if sim.temp_at(c.home) >= 14.0 and hr > 7.0 and hr < 15.0:
		return false
	for b in c.buildings:
		if b.type == "campfire" and b.built and b.fuel < below and not sim.claims.has(-b.id):
			# don't burn wood the tribe is saving for construction unless the fire is out
			var cold := sim.time.season() == 3 or sim.temp_at(c.home) < 6.0
			if b.fuel > 0.0 and not cold and (c.shortfall("wood") > 0.0 or c.shortfall("sticks") > 0.0):
				continue
			if _set_task(sim, p, "refuel", b.tile + Vector2i(1, 0), PRIO_JOB, {"bid": b.id, "label": "Adding firewood"}):
				sim.claims[-b.id] = p.id
				return true
	return false


static func _do_refuel(sim: Sim, p: Human) -> void:
	var c := sim.col_of(p)
	var b := c.building(int(p.task["bid"]))
	if b != null:
		var was_out := b.fuel <= 0.0
		var need := maxf(0.0, 36.0 - b.fuel)
		# sticks first, logs only if needed
		var sticks := c.take("sticks", minf(5.0, floorf(need / 3.0)))
		b.fuel += sticks * 3.0
		need = maxf(0.0, 36.0 - b.fuel)
		if need >= 8.0 and (c.shortfall("wood") <= 0.0 or sim.time.season() == 3):
			var wood := c.take("wood", minf(3.0, floorf(need / 8.0)))
			b.fuel += wood * 8.0
		elif b.fuel <= 0.0:
			b.fuel += c.take("wood", 1.0) * 8.0
		if was_out and b.fuel > 0.0:
			sim.notify(p.civ_id, "%s relit a campfire." % p.name, "info")
	_done(sim, p)


static func _do_fetch_water(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["work"] = float(t["work"]) + dt
	if float(t["work"]) < 2.0:
		return
	p.add_carry("water", 8)
	_start_haul(sim, p)


# ================================================================ research
static func _plan_research(sim: Sim, p: Human, feed_only := false) -> bool:
	var c := sim.col_of(p)
	var table := c.nearest_building(p.pos, "research_table")
	if table == null:
		return false
	# carry materials set aside in the research pile (never straight from the wild)
	var min_pile := 6.0 if feed_only else 1.0
	if c.research_pile_total() >= min_pile:
		var load := c.take_research_load(int(_cap(sim, p)))
		if not load.is_empty():
			p.carrying = load
			if _set_task(sim, p, "feed_research", table.tile, PRIO_JOB, {"bid": table.id, "label": "Bringing materials to the research table"}):
				return true
			# couldn't get there: put it back on the pile
			for k in load.keys():
				c.research_stock[k] = float(c.research_stock.get(k, 0.0)) + float(load[k])
			p.carrying = {}
	if not feed_only:
		return _set_task(sim, p, "study", table.tile + Vector2i(0, 1), PRIO_JOB, {"bid": table.id, "label": "Studying at the research table"})
	return false


## Knowledge points one carried load is worth at the table.
static func research_kp(sim: Sim, p: Human, load: Dictionary) -> float:
	var kp := 0.0
	for k in load.keys():
		kp += Defs.kp_value(k) * float(load[k])
	var c := sim.col_of(p)
	return kp * (1.0 + c.bonus("research")) * (1.0 + p.skill("researcher") * 0.02)


static func _do_feed_research(sim: Sim, p: Human) -> void:
	var b := sim.building(int(p.task["bid"]))
	var c := sim.col_of(p)
	if b != null and b.built:
		var units := 0.0
		for k in p.carrying.keys():
			units += float(p.carrying[k])
		c.knowledge += research_kp(sim, p, p.carrying)
		b.stored = minf(40.0, b.stored + units)    # visual: materials piled on the table
		p.carrying = {}
		p.gain_skill("researcher", 0.05)
	else:
		for k in p.carrying.keys():
			c.research_stock[k] = float(c.research_stock.get(k, 0.0)) + float(p.carrying[k])
		p.carrying = {}
	_done(sim, p)


## With nothing to carry, researchers study at the table: a slow trickle of knowledge.
static func _do_study(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var b := sim.building(int(t["bid"]))
	if b == null or not b.built:
		_done(sim, p)
		return
	t["work"] = float(t["work"]) + dt
	var c := sim.col_of(p)
	c.knowledge += dt / Defs.HOUR * 30.0 * _wm(sim, p, "researcher") * (1.0 + c.bonus("research")) * (1.2 if b.zoned else 1.0)
	p.gain_skill("researcher", 0.002)
	if float(t["work"]) > 30.0 or (c.research_pile_total() >= 4.0 and float(t["work"]) > 5.0):
		_done(sim, p)


# ================================================================ trade
## Traders pack the tribe's surplus, walk to another tribe, sell it for Talents and buy what
## home needs (ores for research, food in hard times), then carry the purchases home.
static func _plan_trade(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	if c.is_player:
		# the player's traders carry out trade orders (Trade)
		if p.task_memory.has("order") and p.task_memory.has("trade_civ"):
			var po := sim.civ(int(p.task_memory["trade_civ"]))
			if po != null and not po.collapsed and sim.time.t < float(p.task_memory.get("trade_until", 0.0)) and _start_trade_trip(sim, p, c, po):
				return true
			Trade._unpack(sim, p, c)
			return false
		if not p.carrying.is_empty() or float(p.task_memory.get("trade_money", 0.0)) > 0.0:
			return _set_task(sim, p, "haul", c.drop_point(p.pos), PRIO_JOB, {"label": "Bringing goods and Talents home"})
		return Trade.plan_trip(sim, p)
	if not p.carrying.is_empty():
		# interrupted on the way (a drink, a rest): pick the trip up again
		var mem_civ := int(p.task_memory.get("trade_civ", -1))
		if mem_civ >= 0 and sim.time.t < float(p.task_memory.get("trade_until", 0.0)):
			var o := sim.civ(mem_civ)
			if o != null and not o.collapsed and _start_trade_trip(sim, p, c, o):
				return true
		p.task_memory.erase("trade_civ")
		_start_haul(sim, p)
		return true
	if sim.time.t < float(p.task_memory.get("next_trade", 0.0)):
		return false
	var partners := sim.trade_partners(c)
	if partners.is_empty():
		p.task_memory["next_trade"] = sim.time.t + 3.0
		return false
	# goods: the tribe's biggest surplus by value
	var pack := {}
	var room := 20
	var cands: Array = []
	for item in Defs.BASE_PRICE.keys():
		var reserve := 20.0 + c.shortfall(item)
		if Defs.FOOD.has(item):
			if c.food_days() < 6.0:
				continue
			reserve = maxf(8.0, c.count(item) * 0.5)
		var spare := floori(c.count(item) - reserve)
		if spare > 0:
			cands.append([float(Defs.BASE_PRICE[item]) * spare, item, spare])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for e in cands:
		if room <= 0:
			break
		var n := mini(int(e[2]), room)
		c.take(e[1], n)
		pack[e[1]] = n
		room -= n
	if pack.is_empty():
		p.task_memory["next_trade"] = sim.time.t + 1.0
		return false
	# nearest friendly-enough partner, preferring ones with money to spend
	var best: Colony = null
	var best_score := -1e18
	for o in partners:
		var d := Vector2(c.home).distance_to(Vector2(o.home))
		var score := minf(o.money, 200.0) - d * 0.6 + sim.relation(c.civ_id, o.civ_id) * 0.5
		if score > best_score:
			best_score = score
			best = o
	p.carrying = pack
	p.task_memory["trade_civ"] = best.civ_id
	p.task_memory["trade_until"] = sim.time.t + maxf(4.0, Trade.max_range(c) / 30.0)
	if _start_trade_trip(sim, p, c, best):
		p.task_memory["next_trade"] = sim.time.t + 0.5
		return true
	for k in pack.keys():
		c.add(k, float(pack[k]))
	p.carrying = {}
	p.task_memory.erase("trade_civ")
	p.task_memory["next_trade"] = sim.time.t + 2.0
	return false


static func _on_trade_trip(p: Human) -> bool:
	return p.job == "trader" and p.task_memory.has("trade_civ") and (not p.carrying.is_empty() or float(p.task_memory.get("trade_money", 0.0)) > 0.0)


static func _start_trade_trip(sim: Sim, p: Human, c: Colony, best: Colony) -> bool:
	var by_sea := not sim.land_reachable(c, best)
	var dest: Vector2i
	if by_sea:
		var harbor := c.nearest_building(p.pos, "harbor")
		dest = harbor.center_tile() if harbor != null else Vector2i(-1, -1)
		dest = sim.world.walkable_near(dest, 3) if dest.x >= 0 else dest
	else:
		dest = sim.world.walkable_near(best.drop_point(sim.world.center_of(best.home)), 4)
	var label := ("Sailing to trade with the %s" if by_sea else "Trading with the %s") % best.name
	return dest.x >= 0 and _set_task(sim, p, "trade_go", dest, PRIO_JOB, {"civ": best.civ_id, "sea": by_sea, "label": label})


static func _do_trade(sim: Sim, p: Human) -> void:
	var c := sim.col_of(p)
	var other := sim.civ(int(p.task["civ"]))
	if p.task.get("sea", false) and other != null:
		# overseas: board a trading boat at the harbor; the voyage takes time both ways
		var days := clampf(Vector2(c.home).distance_to(Vector2(other.home)) / 120.0, 0.3, 2.5)
		var t := {"type": "voyage", "prio": PRIO_JOB, "dest": sim.world.tile_of(p.pos), "moving": false, "work": 0.0,
			"need": days * Defs.DAY_SECONDS, "phase": "out", "civ": other.civ_id, "label": "On a trading voyage to the %s" % other.name}
		p.task = t
		p.state = str(t["label"])
		return
	if c.is_player and p.task_memory.has("order"):
		p.task_memory.erase("trade_civ")
		if other != null and not other.collapsed:
			Trade.exchange(sim, p, c, other)
			p.gain_skill("trader", 0.05)
		_done(sim, p)
		_set_task(sim, p, "haul", c.drop_point(p.pos), PRIO_JOB, {"label": "Bringing the trade home"})
		return
	var bought := {}
	p.task_memory.erase("trade_civ")
	if other != null and not other.collapsed:
		bought = sim.do_trade(p, c, other)
		p.gain_skill("trader", 0.05)
	for k in bought.keys():
		p.add_carry(k, int(bought[k]))
	_done(sim, p)
	if not p.carrying.is_empty():
		_start_haul(sim, p)


static func _do_voyage(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["work"] = float(t["work"]) + dt
	if float(t["work"]) < float(t["need"]):
		return
	var c := sim.col_of(p)
	if t["phase"] == "out":
		var other := sim.civ(int(t["civ"]))
		if c.is_player and p.task_memory.has("order"):
			if other != null and not other.collapsed:
				Trade.exchange(sim, p, c, other)
			p.task_memory.erase("trade_civ")
		elif other != null and not other.collapsed:
			var bought := sim.do_trade(p, c, other)
			p.gain_skill("trader", 0.05)
			for k in bought.keys():
				p.add_carry(k, int(bought[k]))
		t["phase"] = "back"
		t["work"] = 0.0
		t["label"] = "Sailing home"
		return
	_done(sim, p)
	if not p.carrying.is_empty():
		_start_haul(sim, p)


# ================================================================ claiming territory
## Walk to a state's centre and raise the tribe's banner there.
static func order_claim(sim: Sim, p: Human, s: int, prio := PRIO_ORDER) -> bool:
	if not p.alive or not p.can_work() or p.at_sea():
		return false
	var dest := sim.paths.open_near(sim.states.centers[s], 4)
	if dest.x < 0:
		return false
	p.sleeping = false
	if _set_task(sim, p, "claim", dest, prio, {"state": s, "label": "Going to claim %s" % sim.states.names[s]}):
		sim.claims_in_progress[p.civ_id] = s
		return true
	return false


static func _do_claim(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var s := int(t["state"])
	var why := sim.claim_problem(p.civ_id, s)
	if why != "":
		sim.claims_in_progress.erase(p.civ_id)
		if p.civ_id == 0 and int(t["prio"]) == PRIO_ORDER:
			sim.emit_signal("event", why, "warn")
		_done(sim, p)
		return
	# defenders standing near the banner stop a capture
	var owner := int(sim.states.owners[s])
	if owner >= 0 and _nearest_of(sim, p, sim.civ(owner), 6.0) != null:
		t["label"] = "Fighting for %s" % sim.states.names[s]
		return
	t["label"] = "Raising the banner over %s" % sim.states.names[s]
	t["work"] = float(t["work"]) + dt
	if float(t["work"]) >= 6.0:
		sim.claims_in_progress.erase(p.civ_id)
		sim.claim_state(s, p.civ_id)
		_done(sim, p)


# ================================================================ clearing land
## Plants, bushes and loose stones the player boxed for clearing are cut down and carried home.
static func _plan_clear(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var here := sim.world.tile_of(p.pos)
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	var drop: Array = []
	for i in c.clear_marks.keys():
		var ii := int(i)
		if sim.world.res_type[ii] == Defs.R.NONE or sim.world.res_amount[ii] <= 0 and not Defs.RES[sim.world.res_type[ii]]["regrow"]:
			drop.append(i)
			continue
		if sim.claims.has(ii):
			continue
		var q := Vector2i(ii % sim.world.w, ii / sim.world.w)
		var d := Vector2(q).distance_squared_to(Vector2(here))
		if d < best_d:
			best_d = d
			best = q
	for i in drop:
		c.clear_marks.erase(i)
	if best.x < 0:
		return false
	if _set_task(sim, p, "clear", best, PRIO_JOB + 2, {"tile": best, "label": "Clearing land"}):
		sim.claim(best, p.id)
		return true
	return false


static func _do_clear(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var tile: Vector2i = t["tile"]
	var w := sim.world
	var i := w.idx(tile)
	var c := sim.col_of(p)
	var r := w.res_type[i]
	if r == Defs.R.NONE:
		c.clear_marks.erase(i)
		_after_clear(sim, p)
		return
	var rd: Dictionary = Defs.RES[r]
	var job := "woodcutter" if r in Defs.TREES else "gatherer"
	t["work"] = float(t["work"]) + dt * _wm(sim, p, job)
	if float(t["work"]) < float(rd["work"]) * 2.0:
		return
	var n := clampi(w.res_amount[i], 1, 4)
	if not (r >= Defs.R.COPPER_ORE and r <= Defs.R.IRON_ORE):
		p.add_carry(str(rd["item"]), n)
	sim.note_stump(i, r)
	w.res_type[i] = Defs.R.NONE
	w.res_amount[i] = 0
	sim.paths.refresh_tile(tile)
	sim.emit_signal("tile_changed", tile)
	c.clear_marks.erase(i)
	sim.claims.erase(i)
	p.gain_skill(job, 0.02)
	_after_clear(sim, p)


static func _after_clear(sim: Sim, p: Human) -> void:
	if p.carry_total() >= _cap(sim, p) or sim.col_of(p).clear_marks.is_empty():
		if p.carry_total() > 0:
			_start_haul(sim, p)
		else:
			_done(sim, p)
		return
	if not _plan_clear(sim, p):
		if p.carry_total() > 0:
			_start_haul(sim, p)
		else:
			_done(sim, p)


# ================================================================ lumber
const LOG_STICKS := 14


## Lumberers fell a whole tree, drag the log to the Lumber Yard and cut it into sticks.
static func _plan_lumber(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var yard := c.nearest_building(p.pos, "lumber_yard")
	if yard == null or not yard.built:
		return false
	var at_yard := sim.world.walkable_near(yard.center_tile() + Vector2i(0, 2), 3)
	if at_yard.x < 0:
		return false
	if int(p.carrying.get("log", 0)) > 0:
		return _set_task(sim, p, "saw", at_yard, PRIO_JOB, {"bid": yard.id, "label": "Dragging a log to the lumber yard"})
	if c.count("log") >= 1.0:
		if _set_task(sim, p, "saw", at_yard, PRIO_JOB, {"bid": yard.id, "from_stock": true, "label": "Fetching a log from the pile"}):
			return true
	var types := {}
	for r in Defs.TREES:
		types[r] = true
	var tile := sim.world.find_resource(yard.center_tile(), Defs.HOME_RADIUS, types, sim.claims)
	if tile.x < 0:
		return false
	if _set_task(sim, p, "fell", tile, PRIO_JOB, {"tile": tile, "label": "Felling a tree"}):
		sim.claim(tile, p.id)
		return true
	return false


static func _do_fell(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var tile: Vector2i = t["tile"]
	var w := sim.world
	var i := w.idx(tile)
	var r := w.res_type[i]
	if not (r in Defs.TREES):
		sim.claims.erase(i)
		_done(sim, p)
		return
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "lumberer")
	t["label"] = "Felling a tree"
	if float(t["work"]) < float(Defs.RES[r]["work"]) * 4.0:
		return
	# the whole tree comes down
	sim.note_stump(i, r)
	w.res_type[i] = Defs.R.NONE
	w.res_amount[i] = 0
	sim.paths.refresh_tile(tile)
	sim.emit_signal("tile_changed", tile)
	sim.claims.erase(i)
	p.add_carry("log", 1)
	p.gain_skill("lumberer", 0.05)
	Fx.smash(sim, w.center_of(tile), p.pos)
	_done(sim, p)
	_plan_lumber(sim, p)


static func _do_saw(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var c := sim.col_of(p)
	if t.get("from_stock", false) and int(p.carrying.get("log", 0)) <= 0:
		if c.take("log", 1.0) < 1.0:
			_done(sim, p)
			return
		p.add_carry("log", 1)
		t["from_stock"] = false
	if int(p.carrying.get("log", 0)) <= 0:
		_done(sim, p)
		return
	t["label"] = "Cutting a log into sticks"
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "lumberer")
	if float(t["work"]) < 6.0:
		return
	p.carrying["log"] = int(p.carrying["log"]) - 1
	if int(p.carrying["log"]) <= 0:
		p.carrying.erase("log")
	c.deposit("sticks", LOG_STICKS)
	p.gain_skill("lumberer", 0.03)
	_done(sim, p)


# ================================================================ roads
## Road plans this tribe's Billies may work on: their own, plus an ally's plans that run
## through this tribe's land (allies build shared roads together).
static func _road_plans(sim: Sim, c: Colony) -> Array:
	var out: Array = [c]
	for a in Deals.allies_of(sim, c.civ_id):
		if not a.road_marks.is_empty():
			out.append(a)
	return out


static func _has_road_work(sim: Sim, c: Colony) -> bool:
	if not c.road_marks.is_empty():
		return true
	for a in Deals.allies_of(sim, c.civ_id):
		if not a.road_marks.is_empty():
			return true
	return false


## Builders and laborers lay planned roads (nearest first, once the tile is clear): their own
## tribe's, and an ally's where it crosses their land.
static func _plan_road(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var here := sim.world.tile_of(p.pos)
	var best := Vector2i(-1, -1)
	var best_stand := Vector2i(-1, -1)
	var best_owner: Colony = null
	var best_d := 1e18
	var wood_ok := c.count("wood") >= Defs.BRIDGE_WOOD
	for pc in _road_plans(sim, c):
		var plan: Colony = pc
		var drop: Array = []
		for i in plan.road_marks.keys():
			var ii := int(i)
			var q := Vector2i(ii % sim.world.w, ii / sim.world.w)
			if sim.world.road[ii] != 0 or sim.building_tiles.has(ii):
				drop.append(i)
				continue
			if plan != c and sim.states.owner_at(q) != c.civ_id:
				continue          # allies only help with the part in their own land
			if sim.world.res_type[ii] != Defs.R.NONE or sim.claims.has(ii):
				if plan != c and sim.world.res_type[ii] != Defs.R.NONE:
					c.clear_marks[ii] = true      # clear the ally's road through our land
				continue          # still to be cleared, or someone is on it
			var stand := q
			if sim.world.bridgeable(q):
				# bridges are built plank by plank from the shore (or from the bridge so far)
				if not wood_ok:
					continue
				stand = Vector2i(-1, -1)
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if sim.world.walkable(q + dd):
						stand = q + dd
						break
				if stand.x < 0:
					continue
			var d := Vector2(q).distance_squared_to(Vector2(here))
			if plan != c:
				d *= 1.5          # own roads first
			# roads grow outward from roads already laid, so they come out as whole streets
			for dd2 in [1, -1, sim.world.w, -sim.world.w]:
				var ni2: int = ii + dd2
				if ni2 >= 0 and ni2 < sim.world.road.size() and sim.world.road[ni2] != 0:
					d = d * 0.15 - 4.0
					break
			if d < best_d:
				best_d = d
				best = q
				best_stand = stand
				best_owner = plan
		for i in drop:
			plan.road_marks.erase(i)
	if best.x < 0:
		return false
	var bridge := sim.world.bridgeable(best)
	var label := "Building a bridge" if bridge else "Laying a road"
	if best_owner != c:
		label += " with the %s" % best_owner.name
	if _set_task(sim, p, "road", best_stand, PRIO_JOB + 2, {"tile": best, "plan_civ": best_owner.civ_id, "label": label}):
		sim.claim(best, p.id)
		return true
	return false


static func _do_road(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var tile: Vector2i = t["tile"]
	var i := sim.world.idx(tile)
	var c := sim.col_of(p)
	var plan := sim.civ(int(t.get("plan_civ", c.civ_id)))
	if not plan.road_marks.has(i) or sim.world.res_type[i] != Defs.R.NONE:
		sim.claims.erase(i)
		_done(sim, p)
		return
	var bridge := sim.world.bridgeable(tile)
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "builder")
	if float(t["work"]) < (9.0 if bridge else 4.0):
		return
	if bridge:
		if c.count("wood") < Defs.BRIDGE_WOOD:
			sim.claims.erase(i)
			_done(sim, p)
			return
		c.take("wood", Defs.BRIDGE_WOOD)
	sim.lay_road(plan, i)
	sim.claims.erase(i)
	p.gain_skill("builder", 0.01)
	if plan != c:
		sim.shared_road_tiles += 1
	if plan != c and sim.rng.randf() < 0.02:
		sim.relations[sim._key(c.civ_id, plan.civ_id)] = minf(100.0, sim.relation(c.civ_id, plan.civ_id) + 1.0)
	# keep going along the road while there is more to lay nearby
	if not _plan_road(sim, p):
		_done(sim, p)


## Severe dementia: the person wanders off somewhere, lost.
static func order_wander_off(sim: Sim, p: Human, dest: Vector2i) -> void:
	if int(p.task.get("prio", 0)) >= PRIO_REST:
		return
	_set_task(sim, p, "wander", dest, PRIO_JOB + 6, {"label": "Wandering, lost and confused", "wait": sim.rng.randf_range(4.0, 10.0)})


## At war: walk to the nearest marked enemy road and tear it up.
static func _plan_wreck(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var here := sim.world.tile_of(p.pos)
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	var drop: Array = []
	for i in c.wreck_marks.keys():
		var ii := int(i)
		var owner := int(sim.road_tiles.get(ii, -1))
		if sim.world.road[ii] == 0 or owner < 0 or not sim.at_war(c.civ_id, owner):
			drop.append(i)
			continue
		if sim.claims.has(ii):
			continue
		var q := Vector2i(ii % sim.world.w, ii / sim.world.w)
		var d := Vector2(q).distance_squared_to(Vector2(here))
		if d < best_d:
			best_d = d
			best = q
	for i in drop:
		c.wreck_marks.erase(i)
	if best.x < 0:
		return false
	var stand := best
	if sim.world.road[sim.world.idx(best)] == 2:
		stand = sim.world.walkable_near(best, 2)       # a bridge is hacked apart from its end
		if stand.x < 0:
			stand = best
	if _set_task(sim, p, "wreck", stand, PRIO_JOB + 2, {"tile": best, "label": "Tearing up an enemy road"}):
		sim.claim(best, p.id)
		return true
	return false


static func _do_wreck(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var tile: Vector2i = t["tile"]
	var i := sim.world.idx(tile)
	var c := sim.col_of(p)
	var owner := int(sim.road_tiles.get(i, -1))
	if sim.world.road[i] == 0 or owner < 0 or not sim.at_war(c.civ_id, owner):
		c.wreck_marks.erase(i)
		sim.claims.erase(i)
		_done(sim, p)
		return
	t["work"] = float(t["work"]) + dt
	if float(t["work"]) < 5.0:
		return
	sim.wreck_road(c, i)
	sim.claims.erase(i)
	Fx.smash(sim, sim.world.center_of(tile), p.pos)
	if not _plan_wreck(sim, p):
		_done(sim, p)


# ================================================================ blacksmith
static func _plan_smith(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var b := c.nearest_building(p.pos, "blacksmith")
	var bench := c.nearest_building(p.pos, "smithing_bench")
	# the bench forges custom designs: go there when it's busy or a design is waiting
	if bench != null and bench.built and (bench.craft != "" or c.weapon_orders.any(func(w): return Smithing.is_custom(str(w)))):
		if b == null or b.craft == "" or bench.craft != "":
			b = bench
	if b == null and bench != null:
		b = bench
	if b == null:
		return false
	if b.craft == "":
		var pick := next_weapon(c, b)
		if pick == "":
			return false
		c.pay(Defs.weapon(pick)["cost"])
		b.craft = pick
		b.craft_progress = 0.0
	return _set_task(sim, p, "forge", b.tile + Vector2i(b.size().x, 1), PRIO_JOB, {"bid": b.id, "label": "Forging a %s" % str(Defs.weapon(b.craft)["name"])})


## What the blacksmith should make next: the player's queue first, then (if on auto) weapons
## for soldiers who have none. "" = nothing affordable to do.
static func next_weapon(c: Colony, b: Building) -> String:
	var bench := b.type == "smithing_bench"
	var k := 0
	while k < c.weapon_orders.size():
		var w := str(c.weapon_orders[k])
		if not Defs.is_weapon(w) or (not Smithing.is_custom(w) and int(Defs.weapon(w)["era"]) > c.era_i):
			c.weapon_orders.remove_at(k)
			continue
		if bench and not Smithing.is_custom(w):
			k += 1
			continue          # the bench only makes your own designs
		if c.has_cost(Defs.weapon(w)["cost"]):
			c.weapon_orders.remove_at(k)
			return w
		break
	if not b.auto_craft or bench:
		return ""
	# who needs arming: Archers want ranged weapons, Warriors close ones
	var need_r := 0
	var need_m := 0
	for q in c.soldiers():
		var bad: bool = q.weapon == "" or Defs.weapon_ranged(q.weapon) != (q.soldier_kind == "archer")
		if bad:
			if q.soldier_kind == "archer":
				need_r += 1
			else:
				need_m += 1
	var stock_r := 0
	var stock_m := 0
	for w in Defs.all_weapons():
		if Defs.weapon_ranged(w):
			stock_r += int(c.count(w))
		else:
			stock_m += int(c.count(w))
	need_r -= stock_r
	need_m -= stock_m
	if need_r <= 0 and need_m <= 0:
		# keep a spare of each, and upgrade to this age's arms
		if (stock_r >= 1 and stock_m >= 1) or c.soldiers().is_empty():
			return ""
	var opts: Array = c.forgeable_weapons()
	opts.reverse()                       # newest age first
	var want_ranged := need_r > need_m or (need_r <= 0 and need_m <= 0 and stock_r < 1)
	for w in opts:
		var is_r := float(Defs.weapon(w)["range"]) > 2.0
		if is_r != want_ranged:
			continue
		if c.has_cost(Defs.weapon(w)["cost"]):
			return w
	for w in opts:
		if c.has_cost(Defs.weapon(w)["cost"]):
			return w
	return ""


static func _do_forge(sim: Sim, p: Human, dt: float) -> void:
	var b := sim.building(int(p.task["bid"]))
	var c := sim.col_of(p)
	if b == null or not b.built or b.craft == "":
		_done(sim, p)
		return
	b.craft_progress += dt / Defs.HOUR * _wm(sim, p, "smith") * (1.2 if b.zoned else 1.0)
	p.gain_skill("smith", 0.002)
	p.task["work"] = float(p.task["work"]) + dt
	var w: Dictionary = Defs.weapon(b.craft)
	if b.craft_progress >= float(w["hours"]):
		c.add(b.craft, 1)
		sim.notify(c.civ_id, "The %s forged a %s." % ["smiths" if b.type == "smithing_bench" else "blacksmith", str(w["name"])], "good")
		b.craft = ""
		b.craft_progress = 0.0
		_done(sim, p)
	elif float(p.task["work"]) > 40.0:
		_done(sim, p)


# ================================================================ soldiers
static func _plan_soldier(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	# arm yourself with the best weapon of your kind in the stockpile (an Archer drops a melee weapon for a ranged one)
	var best := c.best_stock_weapon(p.soldier_kind)
	var wrong_kind := p.weapon != "" and Defs.weapon_ranged(p.weapon) != (p.soldier_kind == "archer")
	if best != "" and (p.weapon == "" or wrong_kind or float(Defs.weapon(best)["dmg"]) > float(Defs.weapon(p.weapon)["dmg"]) + 2.0):
		if _set_task(sim, p, "equip", c.drop_point(p.pos), PRIO_JOB, {"weapon": best, "label": "Taking up a %s" % Defs.weapon(best)["name"].to_lower()}):
			return true
	# deal with predators prowling around the village, and animals marked in a clearing box
	var home_px := sim.world.center_of(c.home)
	var r2 := pow((c.territory() + 4.0) * Defs.TILE, 2)
	for a in sim.predators:
		if a.alive and (a.pos.distance_squared_to(home_px) < r2 or c.hunt_marks.has(a.id)):
			if order_attack(sim, p, "animal", a.id, PRIO_JOB + 5):
				return true
	var camp := c.nearest_building(p.pos, "training_camp")
	var hall := c.nearest_building(p.pos, "mercenary_hall")
	if camp == null or (hall != null and hall.center().distance_squared_to(p.pos) < camp.center().distance_squared_to(p.pos)):
		camp = hall
	if camp == null:
		return _plan_labor(sim, p)
	var sz := camp.size()
	var spot := camp.tile + Vector2i(sim.rng.randi_range(0, sz.x - 1), sim.rng.randi_range(0, sz.y - 1))
	var what := "Shooting at targets" if p.soldier_kind == "archer" else "Drilling"
	return _set_task(sim, p, "train", spot, PRIO_JOB, {"bid": camp.id, "label": "%s at the %s" % [what, camp.def()["name"].to_lower()]})


static func _do_train(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["work"] = float(t["work"]) + dt
	var c := sim.col_of(p)
	p.gain_skill("soldier", dt / Defs.HOUR * 0.05 * (1.0 + c.bonus("train")))
	p.anim += dt
	if float(t["work"]) > 25.0:
		_done(sim, p)


static func _do_equip(sim: Sim, p: Human) -> void:
	var c := sim.col_of(p)
	var w := str(p.task.get("weapon", ""))
	if w != "" and c.count(w) >= 1.0:
		c.take(w, 1)
		if p.weapon != "":
			c.add(p.weapon, 1)
		p.weapon = w
		sim.notify(c.civ_id, "%s took up a %s." % [p.name, Defs.weapon(w)["name"].to_lower()], "info")
	_done(sim, p)


# ================================================================ mines
static func _plan_mine(sim: Sim, p: Human) -> bool:
	var mine := sim.col_of(p).nearest_building(p.pos, "mine")
	if mine == null:
		return false
	return _set_task(sim, p, "mine_work", mine.center_tile(), PRIO_JOB, {"bid": mine.id, "label": "Working in the mine"})


static func _do_mine(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "miner")
	if float(t["work"]) < 2.5:
		return
	t["work"] = 0.0
	var era := sim.col_of(p).era_i
	var roll := sim.rng.randf()
	var item := "stone"
	if era >= 2 and roll < 0.12:
		item = "iron_ore"
	elif roll < 0.24:
		item = "copper_ore"
	elif roll < 0.34:
		item = "tin_ore"
	p.add_carry(item, 1)
	p.gain_skill("miner", 0.03)
	if p.carry_total() >= _cap(sim, p):
		_start_haul(sim, p)


static func _do_dig(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["work"] = float(t["work"]) + dt * _wm(sim, p, "gatherer")
	var per := 3.2 if sim.time.season() == 3 else 2.4
	if float(t["work"]) < per:
		return
	t["work"] = float(t["work"]) - per
	if t.get("eat", false):
		Survival.eat_item(sim, p, "roots")
		if p.hunger >= 85.0:
			_done(sim, p)
		return
	p.add_carry("roots", 1)
	p.gain_skill("gatherer", 0.01)
	if p.carry_total() >= _cap(sim, p):
		_start_haul(sim, p)


# ================================================================ player orders & combat
## Sends a person to a tile (player right-click). They hold that spot for a while afterwards.
static func order_move(sim: Sim, p: Human, tile: Vector2i) -> bool:
	if not p.alive:
		return false
	p.sleeping = false
	var dest := tile
	if not sim.world.walkable(dest):
		dest = sim.world.walkable_near(dest, 6)
		if dest.x < 0:
			return false
	if p.carry_total() > 0:
		var c := sim.col_of(p)
		for k in p.carrying.keys():
			c.add(str(k), float(p.carrying[k]))     # drop what they carry into the stores
		p.carrying = {}
	if not leader_may_go(sim, p, dest):
		if p.civ_id == 0:
			sim.emit_signal("event", "%s is your leader and must stay inside your borders." % p.name, "warn")
		return false
	return _set_task(sim, p, "order", dest, PRIO_ORDER, {"label": "Moving (ordered)"})


## kind: "animal" or "human".
static func order_attack(sim: Sim, p: Human, kind: String, target_id: int, prio := PRIO_ORDER) -> bool:
	if not p.alive or not p.can_work():
		return false
	p.sleeping = false
	var tpos := _target_pos(sim, kind, target_id)
	if tpos.x > 1e8:
		return false
	var label := "Attacking"
	if kind == "animal":
		var a := sim.animal(target_id)
		label = "Attacking a %s" % a.def()["name"].to_lower()
	elif kind == "building":
		var b := sim.building(target_id)
		label = "Attacking the %s's %s" % [sim.civ(b.civ_id).name, b.display_name().to_lower()]
	else:
		var q := sim.person(target_id)
		label = ("Defending against %s of the %s" if prio == PRIO_DEFEND else "Attacking %s of the %s") % [q.name, sim.col_of(q).name]
	_abort(sim, p)
	p.task = {"type": "attack", "prio": prio, "kind": kind, "target": target_id, "repath": 0.0, "time": 0.0,
		"work": 0.0, "moving": false, "label": label}
	p.state = label
	return true


## Soldiers march on an enemy tribe: they fight its people, then smash gates, walls and buildings.
static func order_raid(sim: Sim, p: Human, civ_id: int, prio := PRIO_ORDER) -> bool:
	if not p.alive or not p.can_work() or p.at_sea():
		return false
	if sim.col_of(p).leader_id == p.id:
		if p.civ_id == 0:
			sim.emit_signal("event", "%s is your leader and stays inside your borders." % p.name, "warn")
		return false
	var target := sim.civ(civ_id)
	if target == null or target.collapsed:
		return false
	p.sleeping = false
	_abort(sim, p)
	p.task_memory["raid_civ"] = civ_id
	p.task_memory["raid_prio"] = prio
	p.task = {"type": "raid", "prio": prio, "civ": civ_id, "kind": "", "target": -1, "repath": 0.0, "time": 0.0,
		"pick": 0.0, "work": 0.0, "moving": false, "label": "Marching on the %s" % target.name}
	p.state = str(p.task["label"])
	return true


static func _target_pos(sim: Sim, kind: String, target_id: int) -> Vector2:
	if kind == "animal":
		var a := sim.animal(target_id)
		if a != null and a.alive:
			return a.pos
	elif kind == "building":
		var b := sim.building(target_id)
		if b != null:
			return b.center()
	else:
		var q := sim.person(target_id)
		if q != null and q.alive and not q.at_sea():
			return q.pos
	return Vector2(1e9, 1e9)


## Distance from a person to what they're attacking (buildings: to their edge).
static func _target_dist(sim: Sim, p: Human, kind: String, tid: int, tpos: Vector2) -> float:
	if kind == "building":
		var b := sim.building(tid)
		var r := Rect2(Vector2(b.tile) * Defs.TILE, Vector2(b.size()) * Defs.TILE)
		var cx := clampf(p.pos.x, r.position.x, r.end.x)
		var cy := clampf(p.pos.y, r.position.y, r.end.y)
		return p.pos.distance_to(Vector2(cx, cy))
	return p.pos.distance_to(tpos)


## Damage one blow does, from weapon, skill and the tribe's research.
static func strike_damage(sim: Sim, p: Human, vs_animal: bool) -> float:
	var c := sim.col_of(p)
	if p.weapon != "" and not (vs_animal and Smithing.is_custom(p.weapon)):     # custom weapons are for fighting people
		var w: Dictionary = Defs.weapon(p.weapon)
		var dmg := float(w["dmg"]) + p.skill("soldier") * 0.8 + c.bonus("fight")
		if vs_animal:
			dmg += c.bonus("hunt_dmg") * 0.5
		return dmg * (1.0 + (c.bonus("soldier") if p.job == "soldier" else 0.0))
	if vs_animal:
		return 10.0 + p.skill("hunter") + c.bonus("hunt_dmg")
	return 7.0 + p.skill("hunter") * 0.6 + c.bonus("fight") + (p.skill("soldier") * 0.5 if p.job == "soldier" else 0.0)


static func weapon_reach(p: Human) -> float:
	if p.weapon != "" and not (Smithing.is_custom(p.weapon) and str(p.task.get("kind", "")) == "animal"):
		return float(Defs.weapon(p.weapon)["range"])
	return 2.4 if p.job == "hunter" else 1.3


## Moves toward and strikes the task's target. Returns "gone", "hit" or "moving".
static func _engage(sim: Sim, p: Human, t: Dictionary, dt: float) -> String:
	var kind := str(t["kind"])
	var tid := int(t["target"])
	var tpos := _target_pos(sim, kind, tid)
	if tpos.x > 1e8:
		return "gone"
	var c := sim.col_of(p)
	var reach := weapon_reach(p) * Defs.TILE
	if kind == "building":
		reach = maxf(reach, 1.0 * Defs.TILE) if reach < 2.0 * Defs.TILE else minf(reach, 5.0 * Defs.TILE)
	if _target_dist(sim, p, kind, tid, tpos) <= reach:
		p.path = []
		t["moving"] = false
		if absf(tpos.x - p.pos.x) > 0.5:
			p.facing = signf(tpos.x - p.pos.x)
		if p.attack_cd <= 0.0:
			p.attack_cd = 1.4
			var ranged := p.weapon != "" and float(Defs.weapon(p.weapon)["range"]) > 2.0
			if ranged:
				sim.tower_shots.append([p.pos + Vector2(0, -6), tpos, 0.25])
			var skill := p.skill("soldier") if p.job == "soldier" else p.skill("hunter")
			var sty := Fx.style_of(p)
			if not ranged:
				Fx.lunge(p, tpos)
			if kind == "building":
				sim.damage_building(sim.building(tid), strike_damage(sim, p, false) * (0.5 if ranged else 1.0) * (1.0 + sim.col_of(p).bonus("siege")), p.civ_id)
				Fx.smash(sim, tpos, p.pos)
				p.gain_skill("soldier", 0.02)
			elif sim.rng.randf() < 0.55 + skill * 0.03 + (c.bonus("hunt_hit") if kind == "animal" else 0.0):
				if kind == "animal":
					var ad := strike_damage(sim, p, true)
					Fx.hit(sim, tpos, p.pos, ad, sty[0], true, sty[1])
					AnimalAI.damage(sim, sim.animal(tid), ad, p)
					p.gain_skill("hunter", 0.1)
				else:
					hit_human(sim, p, sim.person(tid), strike_damage(sim, p, false))
					if p.job == "soldier":
						p.gain_skill("soldier", 0.1)
			else:
				Fx.miss(sim, tpos, p.pos)
		return "hit"
	t["repath"] = float(t["repath"]) - dt
	if t.has("blocked_by"):
		# a hostile gate is in the way: break it first
		var gid := int(t["blocked_by"])
		t.erase("blocked_by")
		var gb := sim.building(gid)
		if gb != null and kind != "building":
			t["kind"] = "building"
			t["target"] = gid
			t["repath"] = 0.0
			return "moving"
	if float(t["repath"]) <= 0.0 or p.path.is_empty():
		t["repath"] = 0.8
		var goal := sim.world.tile_of(tpos)
		var path := sim.paths.find_path(sim.world.tile_of(p.pos), goal)
		var end_t: Vector2i = path[path.size() - 1] if not path.is_empty() else sim.world.tile_of(p.pos)
		if Vector2(end_t).distance_to(Vector2(goal)) > maxf(2.5, reach / Defs.TILE + 1.5):
			# walled in: attack the nearest enemy wall or gate on the way
			var wall := _enemy_wall_near(sim, p, end_t, 4)
			if wall != null:
				t["kind"] = "building"
				t["target"] = wall.id
				path = sim.paths.find_path(sim.world.tile_of(p.pos), wall.tile)
			elif path.is_empty():
				return "gone"
		if path.is_empty() and kind != "building":
			return "gone"
		p.path = path
		t["moving"] = true
	_follow(sim, p, dt, 1.25)
	return "moving"


static func _enemy_wall_near(sim: Sim, p: Human, around: Vector2i, r: int) -> Building:
	var best: Building = null
	var best_d := 1e9
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var b := sim.building_at(around + Vector2i(ox, oy))
			if b == null or (b.type != "wall" and b.type != "gate") or b.civ_id == p.civ_id:
				continue
			if not sim.at_war(b.civ_id, p.civ_id) and str(p.task.get("type", "")) != "attack":
				continue
			var d := Vector2(b.tile).distance_to(Vector2(sim.world.tile_of(p.pos)))
			if d < best_d:
				best_d = d
				best = b
	return best


static func _do_attack(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	t["time"] = float(t["time"]) + dt
	var tpos := _target_pos(sim, str(t["kind"]), int(t["target"]))
	var far := (250.0 if int(t["prio"]) == PRIO_ORDER else 60.0) * Defs.TILE
	if float(t["time"]) > (600.0 if str(t["kind"]) == "building" or int(t["prio"]) == PRIO_ORDER else 120.0) or (tpos.x < 1e8 and tpos.distance_to(p.pos) > far):
		_done(sim, p)
		return
	if _engage(sim, p, t, dt) == "gone":
		_done(sim, p)


static func _do_raid(sim: Sim, p: Human, dt: float) -> void:
	var t := p.task
	var enemy := sim.civ(int(t["civ"]))
	t["time"] = float(t["time"]) + dt
	if enemy == null or enemy.collapsed or (int(t["prio"]) != PRIO_ORDER and not sim.at_war(p.civ_id, enemy.civ_id)) or float(t["time"]) > 900.0:
		p.task_memory.erase("raid_civ")
		_done(sim, p)
		return
	if p.health < 30.0:
		p.task_memory.erase("raid_civ")
		_set_task(sim, p, "flee", sim.col_of(p).drop_point(p.pos), PRIO_FLEE, {"label": "Retreating home"})
		return
	t["pick"] = float(t["pick"]) - dt
	var cur := _target_pos(sim, str(t["kind"]), int(t["target"])) if str(t["kind"]) != "" else Vector2(1e9, 1e9)
	if cur.x > 1e8 or (float(t["pick"]) <= 0.0 and str(t["kind"]) != "human"):
		t["pick"] = 2.0
		# fight people first, then smash the camp
		var foe := _nearest_of(sim, p, enemy, 12.0)
		if foe != null:
			t["kind"] = "human"
			t["target"] = foe.id
		elif cur.x > 1e8:
			var best: Building = null
			var best_d := 1e18
			for b in enemy.buildings:
				var d = b.center().distance_squared_to(p.pos) * (0.6 if b.def().has("shoots") else 1.0)
				if d < best_d:
					best_d = d
					best = b
			if best == null:
				_done(sim, p)
				return
			t["kind"] = "building"
			t["target"] = best.id
		t["repath"] = 0.0
		t["label"] = "Raiding the %s" % enemy.name
	if _engage(sim, p, t, dt) == "gone":
		t["kind"] = ""
		t["target"] = -1


static func _nearest_of(sim: Sim, p: Human, c: Colony, r_tiles: float) -> Human:
	var best: Human = null
	var best_d := pow(r_tiles * Defs.TILE, 2)
	for q in c.people:
		if not q.alive or q.at_sea():
			continue
		var d = q.pos.distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = q
	return best


## Nearest person of a tribe at war with p's tribe.
static func _nearby_enemy(sim: Sim, p: Human, r_tiles: float) -> Human:
	var best: Human = null
	var best_d := pow(r_tiles * Defs.TILE, 2)
	for ec in sim.enemies_of(p.civ_id, true):
		var q := _nearest_of(sim, p, ec, r_tiles)
		if q != null and q.pos.distance_squared_to(p.pos) < best_d:
			best_d = q.pos.distance_squared_to(p.pos)
			best = q
	return best


## One person strikes another. The victim's tribe takes offence and defends itself.
static func hit_human(sim: Sim, attacker: Human, victim: Human, dmg: float) -> void:
	if victim == null or not victim.alive:
		return
	var vc := sim.col_of(victim)
	dmg *= 1.0 - minf(0.6, vc.bonus("defense"))
	dmg *= 1.0 - Warfare.armor_cut(sim, victim)
	victim.health -= dmg
	var sty := Fx.style_of(attacker)
	Fx.hit(sim, victim.pos, attacker.pos, dmg, sty[0], true, sty[1])
	Fx.hurt(victim, attacker.pos)
	if attacker.job == "bandit" and victim.health > 0.0:
		Bandits.on_hit(sim, attacker, victim)
	if sim.rng.randf() < 0.015:
		Survival.infect(sim, victim, "tetanus", "a wound")
	elif sim.rng.randf() < 0.15:
		Survival.infect(sim, victim, "infection", "a wound")
	sim.on_tribes_clash(attacker.civ_id, victim.civ_id)
	if victim.health <= 0.0 and victim.alive:
		sim.col_of(attacker).enemy_kills += 1
		var was_lead := vc.leader_id == victim.id
		var was_war := sim.at_war(attacker.civ_id, victim.civ_id)
		sim.kill(victim, "killed by %s of the %s" % [attacker.name, sim.col_of(attacker).name])
		if attacker.civ_id == 0:
			sim.emit_signal("event", "%s killed %s of the %s." % [attacker.name, victim.name, vc.name], "warn")
		Warfare.on_kill(sim, attacker.civ_id, vc.civ_id, victim.name, was_lead, was_war)
		return
	# fight back (or run if badly hurt); nearby tribesmates join in
	for q in vc.living():
		if not q.can_work() or q.civ_id == 0 and q != victim:
			continue
		if q.pos.distance_to(victim.pos) > 7.0 * Defs.TILE:
			continue
		if int(q.task.get("prio", 0)) == PRIO_ORDER and str(q.task.get("type", "")) == "attack":
			continue
		if q.health < 30.0 or q.id == vc.leader_id or (q.job != "soldier" and sim.at_war(q.civ_id, attacker.civ_id) and not vc.soldiers().is_empty()):
			var home := vc.drop_point(q.pos)
			_set_task(sim, q, "flee", home, PRIO_FLEE, {"label": "Fleeing!"})
		else:
			order_attack(sim, q, "human", attacker.id, PRIO_DEFEND if q.job == "soldier" else PRIO_ORDER)


## Walk to a ship and climb aboard.
static func order_board(sim: Sim, p: Human, sh: Ship) -> bool:
	if not p.alive or p.aboard >= 0:
		return false
	var pending := 0
	for q in sim.col_of(p).living():
		if str(q.task.get("type", "")) == "board" and int(q.task.get("ship", -1)) == sh.id:
			pending += 1
	if sh.passengers.size() + pending >= sim.ship_capacity(sh):
		return false
	var st := sim.world.tile_of(sh.pos)
	var shore := sim.world.find_nearest(st, 4, func(q: Vector2i) -> bool: return sim.world.walkable(q) and sim.world.t_at(q) != Defs.T.RIVER)
	if shore.x < 0:
		return false
	p.sleeping = false
	return _set_task(sim, p, "board", shore, PRIO_ORDER, {"ship": sh.id, "label": "Boarding the %s" % sh.label()})


static func _do_board(sim: Sim, p: Human) -> void:
	var sh := sim.ship(int(p.task["ship"]))
	if sh == null or sh.pos.distance_to(p.pos) > 4.5 * Defs.TILE or sh.passengers.size() >= sim.ship_capacity(sh):
		sim.notify(p.civ_id, "%s couldn't get aboard." % p.name, "warn")
		_done(sim, p)
		return
	if p.carry_total() > 0:
		for k in p.carrying.keys():
			sim.col_of(p).add(str(k), float(p.carrying[k]))
		p.carrying = {}
	_done(sim, p)
	sh.passengers.append(p.id)
	sh.idle_t = 0.0
	p.aboard = sh.id
	p.pos = sh.pos
