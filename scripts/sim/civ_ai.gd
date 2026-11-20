class_name CivAI
extends RefCounted
## The "chief" of a tribe. Runs once per game hour for every civilization:
##  - assigns jobs to fit the tribe's size and needs
##  - decides what to build next, saves materials for it and picks a sensible site
## AI tribes always use it. The player's tribe uses it while auto-jobs / auto-build are on.

const JOB_ORDER := ["gatherer", "hunter", "laborer", "researcher", "smith", "soldier", "builder", "healer", "cook", "woodcutter", "lumberer", "fisherman", "farmer", "miner", "trader"]


static func update(sim: Sim, c: Colony) -> void:
	if c.collapsed or c.population() == 0:
		return
	if c.auto_jobs:
		assign_jobs(sim, c)
	if c.auto_build:
		plan_buildings(sim, c)
		plan_defenses(sim, c)
	if c.auto_expand:
		expand(sim, c)
	if c.auto_roads:
		plan_roads(sim, c)
	if not c.is_player or c.auto_build:
		mark_enemy_roads(sim, c)
	if not c.is_player:
		Military.ai_hire(sim, c)
		Deals.ai_turn(sim, c)
		auto_research(sim, c)
		if c.gov_pending:
			choose_government(sim, c)
		diplomacy(sim, c)
	else:
		# the player's researchers can convert knowledge and pick techs on their own
		if c.auto_convert:
			c.convert_knowledge()
		if c.auto_research:
			research_cheapest(c)
		if c.auto_advance and c.can_advance_era() and c.advance_era():
			sim.emit_signal("event", "Your tribe has entered the %s! New research and buildings are available." % c.era, "major_good")
			sim.emit_signal("buildings_changed")
		if c.gov_pending and sim.debug_log:
			choose_government(sim, c)        # headless tests pick for the player


## AI tribes spend research points on the cheapest available tech and advance eras when they can.
static func auto_research(sim: Sim, c: Colony) -> void:
	c.convert_knowledge()
	if c.can_advance_era():
		c.advance_era()
		if sim.have_met(0, c.civ_id):
			sim.emit_signal("event", "The %s have entered the %s!" % [c.name, c.era], "major")
		return
	var best := ""
	var best_cost := 1e9
	for id in Defs.techs_of_era(c.era_i):
		if not c.tech_available(id):
			continue
		var cost := float(Defs.tech_rp(id))
		if cost < best_cost:
			best_cost = cost
			best = id
	if best != "":
		c.research(best)


static func research_cheapest(c: Colony) -> void:
	var best := ""
	var best_cost := 1e9
	for id in Defs.techs_of_era(c.era_i):
		if c.tech_available(id) and c.can_afford_tech(id) and Defs.tech_rp(id) < best_cost:
			best_cost = Defs.tech_rp(id)
			best = id
	if best != "":
		c.research(best)


## Sends someone to claim the nearest free state next to the tribe's land (and, at war,
## soldiers to seize an enemy's border state).
static func expand(sim: Sim, c: Colony) -> void:
	if sim.claims_in_progress.has(c.civ_id) or sim.rng.randf() > 0.06:
		return
	var home_px := sim.world.center_of(c.home)
	var best := -1
	var best_d := 1e18
	var war_target := false
	var foes := sim.enemies_of(c.civ_id)
	for s in sim.states.count():
		var owner := int(sim.states.owners[s])
		if owner == c.civ_id:
			continue
		var enemy := owner >= 0 and foes.has(sim.civ(owner))
		if owner >= 0 and not enemy:
			continue
		if sim.claim_problem(c.civ_id, s) != "":
			continue
		var d := sim.world.center_of(sim.states.centers[s]).distance_squared_to(home_px)
		if d > pow(70.0 * Defs.TILE, 2):
			continue
		if enemy:
			d *= 0.5
		if d < best_d:
			best_d = d
			best = s
			war_target = enemy
	if best < 0:
		return
	var people: Array = []
	for q in c.living():
		if not q.is_adult() or q.task.get("prio", 0) > HumanAI.PRIO_JOB:
			continue
		if war_target != (q.job == "soldier" and q.weapon != ""):
			continue
		people.append(q)
	if people.is_empty():
		return
	people.sort_custom(func(a, b): return a.pos.distance_squared_to(home_px) < b.pos.distance_squared_to(home_px))
	var n := mini(3 if war_target else 1, people.size())
	for i in n:
		HumanAI.order_claim(sim, people[i], best, HumanAI.PRIO_RAID if war_target else HumanAI.PRIO_JOB + 3)


# ================================================================ jobs
static func desired_jobs(sim: Sim, c: Colony, n: int) -> Dictionary:
	var fd := c.food_days()
	var season := sim.time.season()
	var pend := c.unbuilt_count()
	var want := {}
	want["laborer"] = (1 if n >= 4 else 0) + n / 8
	want["hunter"] = (1 if n >= 2 else 0) + n / 7 + (1 if fd < 2.0 and n >= 4 else 0)
	want["gatherer"] = 1 + (1 if fd < 3.0 and n >= 4 else 0) + n / 6
	want["builder"] = (1 if pend > 0 and n >= 4 else 0) + (1 if pend > 1 and n >= 9 else 0)
	want["healer"] = 1 if n >= 7 or (c.sick_count() > 0 and n >= 4) else 0
	want["cook"] = 1 if n >= 5 and (c.raw_food() >= 3.0 or c.has_built("drying_rack")) else 0
	want["woodcutter"] = (1 if n >= 5 else 0) + (1 if season >= 2 and n >= 9 else 0)
	want["lumberer"] = ((1 if n >= 4 else 0) + (1 if n >= 12 else 0)) if c.job_allowed("lumberer") else 0
	want["fisherman"] = 1 if n >= 6 else 0
	want["farmer"] = mini(n / 4, c.count_type("farm", false))
	want["miner"] = (1 if n >= 12 else 0) + (1 if c.count_type("mine", false) > 0 and n >= 7 else 0) \
		+ (1 if not c.ore_needed().is_empty() and n >= 3 else 0)
	want["researcher"] = (1 if c.count_type("research_table", false) > 0 and n >= 3 else 0) + (1 if n >= 10 else 0)
	want["trader"] = 1 if n >= 7 and c.era_i >= 1 and not sim.trade_partners(c).is_empty() else 0
	if c.is_player:
		# open trade orders always get a trader; without orders the player's traders have nothing to do
		want["trader"] = (1 if not c.trade_orders.is_empty() else 0) + (1 if c.trade_orders.size() >= 3 else 0)
	var war := not sim.enemies_of(c.civ_id).is_empty()
	if c.job_allowed("soldier"):
		var aggr := Config.rule("ai_aggression") if not c.is_player else 1.0
		var warlike: bool = c.government != "" and Defs.GOVERNMENTS[c.government]["ai"] == "warlike"
		var tense := false
		if c.era_i >= 2:
			for o in sim.colonies:
				if o != c and not o.collapsed and sim.have_met(c.civ_id, o.civ_id) and sim.relation(c.civ_id, o.civ_id) < -45.0:
					tense = true
		want["soldier"] = int(float(n) / (3.0 if war else (5.0 if tense else 10.0)) * (1.5 if warlike else 1.0) * clampf(aggr, 0.5, 2.0)) + (1 if n >= 6 else 0)
	if c.job_allowed("smith"):
		var unarmed := 0
		for q in c.soldiers():
			if q.weapon == "":
				unarmed += 1
		want["smith"] = 1 if unarmed > 0 or n >= 10 or war else 0
	return want


static func assign_jobs(sim: Sim, c: Colony) -> void:
	_assign_jobs(sim, c)
	# the player's open trade orders always have a trader
	if c.is_player and not c.trade_orders.is_empty() and c.living().filter(func(q): return q.job == "trader").is_empty():
		var pick: Human = null
		for q in c.living():
			if q.can_work() and q.is_adult() and q.job in ["laborer", "gatherer", "woodcutter", "hunter", "builder"] and not q.drafted:
				if pick == null or q.skill("trader") > pick.skill("trader"):
					pick = q
		if pick != null:
			pick.job = "trader"
			pick.task = {}
			sim.notify(0, "%s took up the Trader job to carry out your trade orders." % pick.name, "info")


static func _assign_jobs(sim: Sim, c: Colony) -> void:
	var workers: Array = []
	var keep_trader := c.is_player and not c.trade_orders.is_empty()
	for p in c.living():
		if p.drafted and p.job == "soldier":
			continue
		if keep_trader and p.job == "trader":
			continue          # busy with the player's trade orders
		if p.can_work():
			workers.append(p)
	var n := workers.size()
	if n == 0:
		return
	var want := desired_jobs(sim, c, n)
	# fill slots in priority order until everyone has one
	var slots: Array = []
	var order: Array = JOB_ORDER.duplicate()
	if not sim.enemies_of(c.civ_id).is_empty():
		order.erase("soldier")
		order.insert(2, "soldier")     # at war: soldiers come right after food
	if not c.ore_needed().is_empty():
		order.erase("miner")
		order.insert(2, "miner")       # research is blocked on ore: mining comes first
	for j in order:
		for k in int(want.get(j, 0)):
			slots.append(j)
	slots = slots.slice(0, n)
	while slots.size() < n:
		slots.append("gatherer")
	var target := {}
	for j in slots:
		target[j] = int(target.get(j, 0)) + 1
	# keep people who already do a needed job
	var have := {}
	var free: Array = []
	for p in workers:
		if int(target.get(p.job, 0)) > int(have.get(p.job, 0)):
			have[p.job] = int(have.get(p.job, 0)) + 1
		else:
			free.append(p)
	# hand out the remaining slots to the most skilled free person
	for j in order:
		while int(have.get(j, 0)) < int(target.get(j, 0)) and not free.is_empty():
			var best: Human = free[0]
			for q in free:
				if q.skill(j) > best.skill(j):
					best = q
			free.erase(best)
			if best.job != j:
				best.job = j
				if j == "soldier":
					best.soldier_kind = Military.balanced_kind(c)
				if int(best.task.get("prio", 0)) <= HumanAI.PRIO_JOB:
					best.task = {}
					best.path = []
					sim.release_claims(best.id)
			have[j] = int(have.get(j, 0)) + 1


# ================================================================ construction
static func next_building(sim: Sim, c: Colony) -> String:
	var pop := c.population()
	var season := sim.time.season()
	var fires := c.count_type("campfire")
	var stores := c.count_type("storage") + c.count_type("granary")
	var housing := 0
	for b in c.buildings:
		housing += int(b.def()["housing"])     # include ones still being built
	var home_type := c.best_housing_type()
	if fires == 0:
		return "campfire"
	if housing < pop + 1:
		return home_type
	if stores == 0 and pop >= 2:
		return "storage"
	if c.count_type("research_table") == 0 and pop >= 3:
		return "research_table"
	for t in ["drying_rack", "well", "hunting_camp", "lumber_yard", "healer_hut", "workshop", "training_camp", "blacksmith", "map_table", "capitol"]:
		var min_pop := 4
		if t == "training_camp" or t == "blacksmith":
			min_pop = 6 if sim.enemies_of(c.civ_id).is_empty() else 3
		elif t == "capitol":
			min_pop = 9
		elif t == "map_table":
			min_pop = 6
		if c.is_unlocked(t) and c.count_type(t) == 0 and pop >= min_pop:
			if t == "drying_rack" and season == 0:
				continue
			if t == "hunting_camp" and c.count("hides") < 1.0:
				continue
			return t
	if c.is_unlocked("mine") and c.count_type("mine") == 0 and (pop >= 6 or not c.ore_needed().is_empty()) and find_site(sim, c, "mine").x >= 0:
		return "mine"
	if c.is_unlocked("granary") and c.count_type("granary") == 0 and pop >= 6:
		return "granary"
	if c.count("hides") >= 4.0 and c.count_type("bedding") < pop / 4:
		return "bedding"
	if c.is_unlocked("farm") and pop >= 4 and season <= 1 and c.count_type("farm") < 1 + pop / 6:
		return "farm"
	if c.is_unlocked("watchtower") and c.count_type("watchtower") < (2 if pop >= 14 else 1) and pop >= 8:
		return "watchtower"
	if c.is_unlocked("arrow_tower") and c.count_type("arrow_tower") < 2 + pop / 10 and pop >= 8:
		return "arrow_tower"
	# the best defensive post the tribe knows, and a few war structures
	var war := not sim.enemies_of(c.civ_id).is_empty()
	for dt in ["ballista_tower", "bastion", "sling_platform", "lookout_perch"]:
		if c.is_unlocked(dt):
			if pop >= 6 and c.count_type(dt) < (1 if pop < 12 else 2) + (1 if war else 0):
				return dt
			break
	if c.is_unlocked("war_drum_circle") and c.count_type("war_drum_circle") == 0 and (pop >= 8 or war):
		return "war_drum_circle"
	if c.is_unlocked("ram_shed") and c.count_type("ram_shed") == 0 and (pop >= 12 or war) and pop >= 6:
		return "ram_shed"
	if war and pop >= 8:
		for st in ["trebuchet", "catapult"]:
			if c.is_unlocked(st):
				if c.count_type(st) == 0:
					return st
				break
	# bonus buildings: one of each once the tribe is settled, a second when it's big
	for bt in ["shaman_circle", "great_hearth", "flint_works", "stone_calendar", "marketplace", "bathhouse", "academy", "iron_foundry"]:
		if c.is_unlocked(bt) and pop >= 8 and c.count_type(bt) < (2 if pop >= 18 else 1):
			return bt
	if fires < 1 + pop / 10:
		return "campfire"
	if stores < 1 + pop / 12:
		return "granary" if c.is_unlocked("granary") else "storage"
	if housing < pop + 3:
		return home_type
	return ""


static func plan_buildings(sim: Sim, c: Colony) -> void:
	var pop := c.population()
	var max_pending := 1 if pop < 8 else 2
	var pending := 0
	for b in c.buildings:
		if not b.built and b.type != "wall" and b.type != "gate":
			pending += 1
	if pending >= max_pending:
		c.want_build = ""
		return
	var type := next_building(sim, c)
	c.want_build = type
	if type == "":
		return
	var site := find_site(sim, c, type)
	if site.x < 0:
		return
	var b := sim.place_building(c, type, site)
	if b != null:
		c.want_build = ""
		sim.notify(c.civ_id, "The tribe decided to build a %s." % b.def()["name"], "info")


# ================================================================ walls
## Once Defensive Perimeters is researched the tribe rings its village with a wall and gates
## (built a few segments at a time), clears trees in the way, and later rebuilds the wall in
## stone and fortified stone as research allows.
static func plan_defenses(sim: Sim, c: Colony) -> void:
	if not c.is_unlocked("wall") or c.population() < 5:
		return
	if c.wall_ring == 0:
		var far := 6
		for b in c.buildings:
			if b.type == "farm" or b.type == "mine" or b.type == "harbor":
				continue          # fields and mines may lie outside the walls
			for q in b.tiles():
				far = maxi(far, maxi(absi(q.x - c.home.x), absi(q.y - c.home.y)))
		c.wall_ring = clampi(far + 3, 8, 18)
	c.wall_tier = c.best_wall_tier()
	_upgrade_walls(sim, c)
	var pending := 0
	for b in c.buildings:
		if not b.built and (b.type == "wall" or b.type == "gate"):
			pending += 1
	if pending >= 6:
		return
	var R := c.wall_ring
	var placed := 0
	# each side gets its gate first; walls on a side are only laid once its gate is planned,
	# so the village is never sealed in
	var sides := [[Vector2i(1, 0), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(1, 0)], [Vector2i(0, -1), Vector2i(1, 0)]]
	for sd in sides:
		var normal: Vector2i = sd[0]
		var along: Vector2i = sd[1]
		var tiles: Array = []
		for k in range(-R + 1, R):
			tiles.append(c.home + normal * R + along * k)
		var has_gate := false
		var open_tiles: Array = []
		for q in tiles:
			if not sim.world.inb(q):
				continue
			var nb := sim.building_at(q)
			if nb != null and nb.type == "gate":
				has_gate = true
			var ter := sim.world.t_at(q)
			if Defs.TERRAIN[ter]["cost"] > 0.0 and ter != Defs.T.RIVER and ter != Defs.T.MOUNTAIN and ter != Defs.T.PEAK:
				open_tiles.append(q)
		if open_tiles.is_empty():
			continue                # water or mountains guard this side
		if not has_gate:
			# the open tile closest to the middle of the side
			open_tiles.sort_custom(func(x, y): return Vector2(x).distance_squared_to(Vector2(c.home + normal * R)) < Vector2(y).distance_squared_to(Vector2(c.home + normal * R)))
			for q in open_tiles:
				if sim.building_tiles.has(sim.world.idx(q)):
					continue
				var why := sim.can_place(c, "gate", q)
				if why.begins_with("Clear"):
					c.clear_marks[sim.world.idx(q)] = true
					continue
				if why != "":
					continue
				var g := sim.place_building(c, "gate", q)
				if g != null:
					g.tier = c.wall_tier
					has_gate = true
					placed += 1
				break
		if not has_gate:
			continue
		var corner_tiles: Array = tiles.duplicate()
		corner_tiles.append(c.home + normal * R + along * R)
		corner_tiles.append(c.home + normal * R - along * R)
		for q in corner_tiles:
			if placed >= 6 - pending:
				return
			if not sim.world.inb(q) or sim.building_tiles.has(sim.world.idx(q)):
				continue
			var ter := sim.world.t_at(q)
			if Defs.TERRAIN[ter]["cost"] <= 0.0 or ter == Defs.T.RIVER or ter == Defs.T.MOUNTAIN or ter == Defs.T.PEAK:
				continue           # water and mountains are natural walls
			var why := sim.can_place(c, "wall", q)
			if why.begins_with("Clear"):
				c.clear_marks[sim.world.idx(q)] = true      # cut the tree down first
				continue
			var wtype := "wall"
			if why.begins_with("Roads"):
				# a road runs through the wall line: put a gate across it instead
				wtype = "gate"
				why = sim.can_place(c, "gate", q)
			if why != "":
				continue
			var b := sim.place_building(c, wtype, q)
			if b != null:
				b.tier = c.wall_tier
				placed += 1


static func _ring(center: Vector2i, r: int) -> Array:
	var out: Array = []
	for x in range(-r, r + 1):
		out.append(center + Vector2i(x, -r))
	for y in range(-r + 1, r + 1):
		out.append(center + Vector2i(r, y))
	for x in range(r - 1, -r - 1, -1):
		out.append(center + Vector2i(x, r))
	for y in range(r - 1, -r, -1):
		out.append(center + Vector2i(-r, y))
	return out


## Masons rebuild one finished wall or gate per hour at the best level research allows.
static func _upgrade_walls(sim: Sim, c: Colony) -> void:
	var best := c.best_wall_tier()
	for b in c.buildings:
		if b.built and (b.type == "wall" or b.type == "gate") and b.tier < best:
			var cost: Dictionary = Defs.WALL_TIERS[best]["wall_cost" if b.type == "wall" else "gate_cost"]
			if c.has_cost(cost):
				c.pay(cost)
				b.tier = best
				b.hp = -1.0
				sim.emit_signal("buildings_changed")
			return


# ================================================================ government & diplomacy
static func choose_government(sim: Sim, c: Colony) -> void:
	var opts := Defs.governments_of_era(c.era_i)
	if opts.is_empty():
		c.gov_pending = false
		return
	var pick: String = opts[sim.rng.randi() % opts.size()]
	c.government = pick
	c.gov_pending = false
	c.invalidate_bonus()
	if c.civ_id != 0 and sim.have_met(0, c.civ_id):
		sim.emit_signal("event", "The %s have become a %s." % [c.name, Defs.GOVERNMENTS[pick]["name"]], "info")


## AI tribes declare war on tribes they hate (once in the Bronze Age), raid their enemies and
## sue for peace when a war goes badly.
static func diplomacy(sim: Sim, c: Colony) -> void:
	if sim.rng.randf() > 0.08:
		return
	var mine := sim.military_strength(c)
	var warlike: bool = c.government != "" and Defs.GOVERNMENTS[c.government]["ai"] == "warlike"
	var aggr := Config.rule("ai_aggression") * (1.6 if warlike else 1.0)
	# start wars
	if c.era_i >= 2 and sim.enemies_of(c.civ_id).is_empty() and aggr > 0.0:
		for o in sim.colonies:
			if o == c or o.collapsed or not sim.have_met(c.civ_id, o.civ_id):
				continue
			var rel := sim.relation(c.civ_id, o.civ_id)
			var theirs := sim.military_strength(o)
			if rel < -45.0 and mine > theirs * 1.1 and c.soldiers().size() >= 2 and sim.rng.randf() < 0.05 * aggr:
				sim.declare_war(c.civ_id, o.civ_id)
				break
	for e in sim.enemies_of(c.civ_id):
		var theirs := sim.military_strength(e)
		# losing badly or tired of war: ask for peace
		if mine < theirs * 0.7 or sim.rng.randf() < 0.02:
			if e.civ_id == 0:
				if not sim.peace_offers.has(c.civ_id):
					sim.peace_offers[c.civ_id] = true
					sim.emit_signal("event", "The %s offer peace. Open their flag (Colony panel or click their camp flag) to accept." % c.name, "info")
			elif sim.rng.randf() < sim.peace_chance(c.civ_id, e.civ_id):
				sim.make_peace(c.civ_id, e.civ_id)
				continue
		# raid: send two thirds of the armed soldiers
		var armed: Array = []
		for q in c.soldiers():
			if q.weapon != "" and q.health > 60.0 and str(q.task.get("type", "")) != "raid":
				armed.append(q)
		if armed.size() >= 2 and mine >= theirs * 0.8 and sim.rng.randf() < 0.35:
			var n := maxi(2, armed.size() * 2 / 3)
			for i in n:
				HumanAI.order_raid(sim, armed[i], e.civ_id, HumanAI.PRIO_RAID)
			if e.civ_id == 0:
				sim.emit_signal("event", "Warriors of the %s are marching on your village!" % c.name, "major_bad")


## Finds a free spot near the tribe's home, leaving a walkway around every building.
## Buildings go into a zone of the right kind first when the tribe has painted one.
static func find_site(sim: Sim, c: Colony, type: String) -> Vector2i:
	var sz: Vector2i = Defs.BUILDINGS[type]["size"]
	if type == "catapult" or type == "trebuchet":
		var fs := _front_site(sim, c, type, sz)
		if fs.x >= 0:
			return fs
	var zs := _zone_site(sim, c, type, sz)
	if zs.x >= 0:
		return zs
	var r0 := 1
	var r1 := 12
	if type == "farm":
		r0 = 5
		r1 = 16
	elif type == "mine":
		r0 = 2
		r1 = 22
	elif type == "campfire":
		r0 = 1
		r1 = 6
	for r in range(r0, r1 + 1):
		var ring: Array = []
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if absi(ox) == r or absi(oy) == r:
					ring.append(c.home + Vector2i(ox, oy))
		ring.shuffle()
		for center in ring:
			var t: Vector2i = center - Vector2i(sz.x / 2, sz.y / 2)
			if sim.can_place(null, type, t) != "":
				continue
			var so := sim.states.owner_at(t)
			if so >= 0 and so != c.civ_id:
				continue
			if not _has_clearance(sim, t, sz):
				continue
			return t
	return Vector2i(-1, -1)


static func _has_clearance(sim: Sim, t: Vector2i, sz: Vector2i) -> bool:
	for y in range(t.y - 1, t.y + sz.y + 1):
		for x in range(t.x - 1, t.x + sz.x + 1):
			var q := Vector2i(x, y)
			if not sim.world.inb(q):
				return false
			if sim.building_tiles.has(sim.world.idx(q)):
				return false
	return true


## A spot whose middle lies inside a zone that suits the building (nearest home first).
static func _zone_site(sim: Sim, c: Colony, type: String, sz: Vector2i) -> Vector2i:
	var z := Defs.zone_for(type)
	if z <= 0 or c.zones.is_empty():
		return Vector2i(-1, -1)
	var cands: Array = []
	for i in c.zones.keys():
		if int(c.zones[i]) == z:
			cands.append(Vector2i(int(i) % sim.world.w, int(i) / sim.world.w))
	if cands.is_empty():
		return Vector2i(-1, -1)
	var home := c.home
	cands.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(home)) < Vector2(b).distance_squared_to(Vector2(home)))
	var tries := 0
	for center in cands:
		tries += 1
		if tries > 500:
			break
		var t: Vector2i = center - Vector2i(sz.x / 2, sz.y / 2)
		if sim.can_place(null, type, t) != "":
			continue
		var so := sim.states.owner_at(t)
		if so >= 0 and so != c.civ_id:
			continue
		if not _has_clearance(sim, t, sz):
			continue
		return t
	return Vector2i(-1, -1)


# ================================================================ roads
const ROAD_SKIP := ["wall", "gate", "fence", "monolith", "farm"]


## The tribe grows a street network the way a real village would: first a main street through
## the camp (bending around buildings), then lanes from each building's door to the nearest
## street, and later a highway to a nearby ally or trading partner. A new road is only planned
## once the last one is built, so roads appear as whole streets instead of scattered bits.
static func plan_roads(sim: Sim, c: Colony) -> void:
	if sim.rng.randf() < 0.01:
		c.road_tried.clear()        # look again now and then (roads get torn up, buildings move)
	if not c.road_marks.is_empty():
		# a plan nobody has worked on for a long while (blocked, out of reach) is dropped
		if not c.is_player and sim.time.day() - c.road_plan_day > 25:
			c.road_marks.clear()
		return
	if c.population() < 3 or sim.rng.randf() > 0.3:
		return
	c.road_plan_day = sim.time.day()
	var hub := c.home + Vector2i(0, 2)
	var fire := c.nearest_building(sim.world.center_of(c.home), "campfire")
	if fire != null and fire.built:
		hub = fire.tile + Vector2i(0, fire.size().y)
	var built: Array = c.buildings.filter(func(b): return b.built and not ROAD_SKIP.has(b.type))
	if built.size() < 3:
		return
	# 1) the main street: across the village through the hub, along whichever axis is longer
	if not c.road_tried.has(-1):
		c.road_tried[-1] = true
		var lo := Vector2i(hub)
		var hi := Vector2i(hub)
		for b in built:
			lo = Vector2i(mini(lo.x, b.tile.x), mini(lo.y, b.tile.y))
			hi = Vector2i(maxi(hi.x, b.tile.x + b.size().x), maxi(hi.y, b.tile.y + b.size().y))
		var a: Vector2i
		var z: Vector2i
		if hi.x - lo.x >= hi.y - lo.y:
			a = Vector2i(lo.x - 2, hub.y)
			z = Vector2i(hi.x + 2, hub.y)
		else:
			a = Vector2i(hub.x, lo.y - 2)
			z = Vector2i(hub.x, hi.y + 2)
		a = _road_free_near(sim, a)
		z = _road_free_near(sim, z)
		if a.x >= 0 and z.x >= 0:
			var p1 := route(sim, c, a, {sim.world.idx(hub): true}, 30)
			var p2 := route(sim, c, z, {sim.world.idx(hub): true}, 30)
			var street: Array = p1.duplicate()
			street.append_array(p2)
			if sim.plan_road(c, street) > 0:
				return
	# 2) lanes: the nearest building without a road reaches the nearest street
	built.sort_custom(func(x, y): return Vector2(x.tile).distance_squared_to(Vector2(hub)) < Vector2(y.tile).distance_squared_to(Vector2(hub)))
	for b in built:
		if c.road_tried.has(b.id):
			continue
		c.road_tried[b.id] = true
		if _road_next_to(sim, b):
			continue
		var door := _door_tile(sim, b)
		if door.x < 0:
			continue
		var goals := _road_goals(sim, c)
		goals[sim.world.idx(hub)] = true
		var lane := route(sim, c, door, goals, 24)
		if not lane.is_empty() and sim.plan_road(c, lane) > 0:
			return
	# 3) a highway to the nearest ally or trading partner (once the tribe is settled)
	if c.population() >= 10 and c.era_i >= 1:
		var best: Colony = null
		var bd := 75.0
		for o in sim.colonies:
			if o == c or o.collapsed or o.bandit or c.road_tried.has(-100 - o.civ_id):
				continue
			if not (Deals.allied(sim, c.civ_id, o.civ_id) or (sim.have_met(c.civ_id, o.civ_id) and sim.relation(c.civ_id, o.civ_id) > 10.0)):
				continue
			var d := Vector2(o.home).distance_to(Vector2(c.home))
			if d < bd:
				bd = d
				best = o
		if best != null:
			c.road_tried[-100 - best.civ_id] = true
			highway(sim, c, best)


## Plans a road along the walking route between two villages, through land the tribe may build
## on (its own, unclaimed, or an ally's). Allies help build the part in their land.
static func highway(sim: Sim, c: Colony, o: Colony) -> int:
	var to := sim.world.walkable_near(o.home + Vector2i(0, 3), 4)
	if to.x < 0:
		return 0
	# start from the tribe's own road nearest the other village, so the highway grows out of a street
	var from := sim.world.walkable_near(c.home + Vector2i(0, 3), 4)
	var fd := 1e18
	for i in sim.road_tiles.keys():
		if int(sim.road_tiles[i]) != c.civ_id:
			continue
		var q := Vector2i(int(i) % sim.world.w, int(i) / sim.world.w)
		var d := Vector2(q).distance_squared_to(Vector2(to))
		if d < fd and sim.world.walkable(q):
			fd = d
			from = q
	if from.x < 0:
		return 0
	var raw := sim.paths.find_path(from, to)
	if raw.is_empty():
		return 0
	# walking paths step diagonally; a road needs side-by-side tiles, so fill in each corner
	var path: Array = [from]
	for q in raw:
		var last: Vector2i = path[-1]
		if q.x != last.x and q.y != last.y:
			var c1 := Vector2i(q.x, last.y)
			var c2 := Vector2i(last.x, q.y)
			path.append(c1 if sim.road_ok(c1) or sim.world.road[sim.world.idx(c1)] != 0 else c2)
		path.append(q)
	var tiles: Array = []
	for q in path:
		var so := sim.states.owner_at(q)
		if so >= 0 and so != c.civ_id and not Deals.allied(sim, c.civ_id, so):
			break                    # stop where land they may not build on begins: no gaps
		if sim.building_tiles.has(sim.world.idx(q)) and sim.building_at(q).type != "gate":
			continue
		tiles.append(q)
	var n := sim.plan_road(c, tiles)
	c.road_plan_day = sim.time.day()
	if n > 0 and (c.civ_id == 0 or o.civ_id == 0 or sim.have_met(0, c.civ_id)):
		if c.civ_id == 0 or o.civ_id == 0:
			sim.emit_signal("event", "A road is being laid between your village and the %s." % (o.name if c.civ_id == 0 else c.name), "good")
	return n


## Every finished road tile of the tribe (and its allies): what a new lane may join.
static func _road_goals(sim: Sim, c: Colony) -> Dictionary:
	var goals := {}
	for i in sim.road_tiles.keys():
		var ow := int(sim.road_tiles[i])
		if ow == c.civ_id or Deals.allied(sim, c.civ_id, ow):
			goals[int(i)] = true
	return goals


static func _road_free_near(sim: Sim, q: Vector2i) -> Vector2i:
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := q + Vector2i(dx, dy)
				if sim.world.inb(t) and (sim.road_ok(t) or sim.world.road[sim.world.idx(t)] != 0):
					return t
	return Vector2i(-1, -1)


## Cheapest connected route from `from` to any goal tile, within `radius` tiles: around
## buildings, preferring flat land over bridges and following existing roads for free.
## Returns only the tiles that still need a road.
static func route(sim: Sim, c: Colony, from: Vector2i, goals: Dictionary, radius: int) -> Array:
	var w := sim.world.w
	var start := sim.world.idx(from)
	if goals.has(start):
		return []
	var dist := {start: 0}
	var prev := {}
	var buckets: Array = [[start]]
	var found := -1
	var cur := 0
	while cur < buckets.size():
		var bucket: Array = buckets[cur]
		if bucket.is_empty():
			cur += 1
			continue
		var i: int = bucket.pop_back()
		if int(dist.get(i, 1 << 30)) < cur:
			continue
		if goals.has(i):
			found = i
			break
		var q := Vector2i(i % w, i / w)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = q + d
			if absi(n.x - from.x) > radius or absi(n.y - from.y) > radius or not sim.world.inb(n):
				continue
			var ni := sim.world.idx(n)
			var step := 0
			if sim.world.road[ni] != 0:
				step = 1 if not goals.has(ni) else 0
			elif goals.has(ni):
				step = 1
			elif sim.road_ok(n):
				var so := sim.states.owner_at(n)
				if so >= 0 and so != c.civ_id and not Deals.allied(sim, c.civ_id, so):
					continue
				step = 4 if sim.world.bridgeable(n) else 2
				if sim.world.res_type[ni] != Defs.R.NONE:
					step += 1        # trees in the way have to be cut first
			else:
				continue
			var nd := cur + step
			if nd < int(dist.get(ni, 1 << 30)):
				dist[ni] = nd
				prev[ni] = i
				while buckets.size() <= nd:
					buckets.append([])
				buckets[nd].append(ni)
	if found < 0:
		return []
	var out: Array = []
	var k := found
	if sim.world.road[k] == 0 and sim.road_ok(Vector2i(k % w, k / w)):
		out.append(Vector2i(k % w, k / w))
	while k != start:
		k = int(prev[k])
		if sim.world.road[k] == 0:
			out.append(Vector2i(k % w, k / w))
	return out


static func _road_next_to(sim: Sim, b: Building) -> bool:
	var s := b.size()
	for y in range(b.tile.y - 1, b.tile.y + s.y + 1):
		for x in range(b.tile.x - 1, b.tile.x + s.x + 1):
			var q := Vector2i(x, y)
			if sim.world.inb(q) and sim.world.road[sim.world.idx(q)] != 0:
				return true
	return false


## A free tile just outside the building, preferring the side facing down (its door).
static func _door_tile(sim: Sim, b: Building) -> Vector2i:
	var s := b.size()
	for q in [b.tile + Vector2i(s.x / 2, s.y), b.tile + Vector2i(s.x, s.y / 2), b.tile + Vector2i(-1, s.y / 2), b.tile + Vector2i(s.x / 2, -1)]:
		if sim.road_ok(q):
			return q
	return Vector2i(-1, -1)


## At war, tribes send Billies to tear up the enemy's roads near their own land.
static func mark_enemy_roads(sim: Sim, c: Colony) -> void:
	if sim.rng.randf() > 0.25:
		return
	var foes := sim.enemies_of(c.civ_id)
	if foes.is_empty():
		if not c.wreck_marks.is_empty() and not c.is_player:
			c.wreck_marks.clear()
		return
	if c.is_player or c.wreck_marks.size() >= 4:
		return          # the player picks roads to wreck with the Remove road tool
	var ids := {}
	for f in foes:
		ids[f.civ_id] = true
	var home := c.home
	var cands: Array = []
	for i in sim.road_tiles.keys():
		if not ids.has(int(sim.road_tiles[i])):
			continue
		var q := Vector2i(int(i) % sim.world.w, int(i) / sim.world.w)
		var d := Vector2(q).distance_to(Vector2(home))
		if d < 45.0:
			cands.append([d, int(i)])
	cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for k in mini(4, cands.size()):
		c.wreck_marks[int(cands[k][1])] = true


## A spot on the tribe's own land as close as possible to the nearest enemy village.
static func _front_site(sim: Sim, c: Colony, type: String, sz: Vector2i) -> Vector2i:
	var foe: Colony = null
	var fd := 1e18
	for e in sim.enemies_of(c.civ_id):
		var d := Vector2(e.home).distance_squared_to(Vector2(c.home))
		if d < fd:
			fd = d
			foe = e
	if foe == null:
		return Vector2i(-1, -1)
	var dir := (Vector2(foe.home) - Vector2(c.home)).normalized()
	for step in range(22, 4, -2):
		var center := c.home + Vector2i(roundi(dir.x * step), roundi(dir.y * step))
		for off in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var t: Vector2i = center + off - Vector2i(sz.x / 2, sz.y / 2)
			if sim.can_place(null, type, t) != "":
				continue
			var so := sim.states.owner_at(t)
			if so != c.civ_id:
				continue
			if not _has_clearance(sim, t, sz):
				continue
			return t
	return Vector2i(-1, -1)
