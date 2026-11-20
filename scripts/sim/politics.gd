class_name Politics
extends RefCounted
## Political happiness: how content a tribe's people are with how they're ruled (0-100%).
## Tracked from the Caveman Age for every tribe. It drifts each day toward a target made of:
## the government type (or tribal rule before the Bronze Age), the leader, food, homes,
## health, wars, prosperity, a stolen election, and rising expectations in later ages.
## Below 20% (Game Rules), there's a 40% chance each calendar year that a group splits off:
## they ask to join another tribe and, if refused (they may not join or cross), found their own.

const SPLIT_SHARE := 0.25


static func target(sim: Sim, c: Colony) -> Dictionary:
	var parts := {}
	parts["Base contentment"] = 55.0
	if c.government != "":
		var g: Dictionary = Defs.GOVERNMENTS[c.government]
		parts["%s" % g["name"]] = float(g.get("approval", 0))
	else:
		parts["Tribal rule"] = 5.0
	var ld := Elections.leader(sim, c)
	if ld == null:
		parts["No leader"] = -10.0
	elif not c.last_election.is_empty():
		var res: Array = c.last_election.get("results", [])
		var tot := int(c.last_election.get("voters", 0))
		if res.size() > 1 and tot > 0:
			var share := float(res[0][2]) / tot
			if share >= 0.6:
				parts["Popular leader"] = 6.0
			elif share < 0.45:
				parts["Leader won narrowly"] = -4.0
	var fd := c.food_days()
	if fd < 1.0:
		parts["Starving"] = -25.0
	elif fd < 3.0:
		parts["Food is short"] = -10.0
	elif fd >= 10.0:
		parts["Full food stores"] = 6.0
	var pop := c.population()
	var homes := c.housing()
	if pop > homes:
		parts["Not enough homes"] = -minf(20.0, float(pop - homes) * 3.0)
	elif pop > 0:
		parts["Everyone has a home"] = 4.0
	var sick := 0
	for p in c.living():
		if p.is_sick():
			sick += 1
	if pop > 0 and float(sick) / pop > 0.2:
		parts["Sickness"] = -10.0
	var wars := sim.enemies_of(c.civ_id).filter(func(e): return not e.bandit).size()
	if wars > 0:
		var warlike = c.government != "" and Defs.GOVERNMENTS[c.government]["ai"] == "warlike"
		parts["At war"] = -minf(18.0, wars * 6.0) * (0.5 if warlike else 1.0)
	if pop > 0 and c.money / pop >= 20.0:
		parts["Prosperity"] = 4.0
	if c.in_unrest():
		parts["Stolen election"] = -30.0
	if c.era_i > 0:
		parts["People expect more"] = -3.0 * c.era_i
	if c.recent_robbed > 0.0:
		parts["Robbed by bandits"] = -6.0
	if c.exile_sorrow > 0.0:
		parts["Sent one of their own away"] = -5.0
	var wm := Warfare.war_months(sim, c)
	if wm >= 1.0:
		parts["War weariness (%d months at war)" % int(wm)] = -minf(15.0, 2.0 + wm * 1.5)
	if c.victories > 0:
		parts["Proud of past victories"] = minf(8.0, 4.0 * c.victories)
	return parts


static func target_value(parts: Dictionary) -> float:
	var v := 0.0
	for k in parts.keys():
		v += float(parts[k])
	return clampf(v, 0.0, 100.0)


## Once per simulation day for every tribe.
static func daily(sim: Sim, c: Colony) -> void:
	if c.bandit or c.collapsed or c.population() == 0:
		return
	c.approval_parts = target(sim, c)
	var tv := target_value(c.approval_parts)
	c.approval = clampf(c.approval + (tv - c.approval) * 0.3, 0.0, 100.0)
	c.recent_robbed = maxf(0.0, c.recent_robbed - 1.0)
	c.exile_sorrow = maxf(0.0, c.exile_sorrow - 1.0)
	c.dislike_share = dislike_share(sim, c)
	if c.dislike_share >= 0.5 and c.adults_count() >= 6 and sim.time.cal_years() >= c.civil_war_after \
			and sim.rng.randf() < Config.rule("civil_war_chance") * sim.time.scale / 365.0:
		civil_war(sim, c)
		return
	var year := int(sim.time.cal_years())
	if year > c.defect_year:
		c.defect_year = year
		if c.approval < Config.rule("defect_below") * 100.0 and sim.rng.randf() < Config.rule("defect_chance"):
			split(sim, c)


static func mood_word(v: float) -> String:
	if v >= 75.0:
		return "Content"
	if v >= 50.0:
		return "Satisfied"
	if v >= 35.0:
		return "Grumbling"
	if v >= 20.0:
		return "Restless"
	return "On the brink"


# ---------------------------------------------------------------- splitting
## A group of adults to leave together: always at least one man and one woman (couples stay
## together), up to `n` people. Empty when that isn't possible.
static func pick_group(sim: Sim, pool: Array, n: int) -> Array:
	var men: Array = pool.filter(func(q): return q.gender == "M")
	var women: Array = pool.filter(func(q): return q.gender == "F")
	if men.is_empty() or women.is_empty():
		return []
	pool = pool.duplicate()
	pool.shuffle()
	var group: Array = []
	# start with a couple if there is one, otherwise any man and any woman
	var first_m: Human = null
	var first_f: Human = null
	for q in pool:
		if q.gender == "M" and q.partner_id >= 0:
			var pt := sim.person(q.partner_id)
			if pt != null and pool.has(pt):
				first_m = q
				first_f = pt
				break
	if first_m == null:
		first_m = men[sim.rng.randi() % men.size()]
		first_f = women[sim.rng.randi() % women.size()]
	group.append(first_m)
	group.append(first_f)
	for q in pool:
		if group.size() >= n:
			break
		if group.has(q):
			continue
		group.append(q)
		var pt2 := sim.person(q.partner_id)
		if pt2 != null and pool.has(pt2) and not group.has(pt2):
			group.append(pt2)
	return group


## Adds the young children of anyone in the group.
static func add_children(c: Colony, group: Array) -> void:
	for p in c.living():
		if p.age_years() < 14.0 and not group.has(p):
			for g in group:
				if p.mother_id == g.id or p.father_id == g.id:
					group.append(p)
					break


## A group of unhappy people leaves (always at least a man and a woman).
static func split(sim: Sim, c: Colony) -> void:
	var adults: Array = []
	for p in c.living():
		if p.age_years() >= 16.0 and p.id != c.leader_id and not p.at_sea():
			adults.append(p)
	if adults.size() < 4:
		return
	var n := clampi(roundi(adults.size() * SPLIT_SHARE), 2, 12)
	var group := pick_group(sim, adults, n)
	if group.size() < 2:
		return
	add_children(c, group)
	var ids: Array = group.map(func(p): return p.id)
	# try to join the friendliest tribe they could walk to
	var best: Colony = null
	var best_v := -1e9
	for o in sim.colonies:
		if o == c or o.bandit or o.collapsed or o.population() == 0 or not sim.land_reachable(c, o):
			continue
		var v = sim.relation(c.civ_id, o.civ_id) + sim.rng.randf_range(0.0, 30.0) + o.approval * 0.3
		if v > best_v:
			best_v = v
			best = o
	if best != null and sim.rng.randf() < 0.5:
		if best.civ_id == 0:
			# they must ask the player first
			sim.defect_asks.append({"from": c.civ_id, "people": ids})
			sim.emit_signal("event", "%d unhappy people of the %s ask to join your tribe." % [ids.size(), c.name], "major")
			if sim.debug_log:
				answer(sim, sim.defect_asks[0], true)
			return
		if sim.rng.randf() < 0.65:
			_announce_leave(sim, c, group, "join the " + best.name)
			move_people(sim, group, c, best)
			return
		if c.civ_id == 0 or sim.have_met(0, c.civ_id):
			sim.emit_signal("event", "The %s refused to take in a group leaving the %s." % [best.name, c.name], "info")
	found_tribe(sim, c, group)


## The player's answer to people asking to join.
static func answer(sim: Sim, ask: Dictionary, yes: bool) -> void:
	sim.defect_asks.erase(ask)
	var c := sim.civ(int(ask["from"]))
	var group: Array = []
	for pid in ask["people"]:
		var p := sim.person(int(pid))
		if p != null and p.alive and p.civ_id == c.civ_id:
			group.append(p)
	if group.is_empty():
		return
	if yes:
		move_people(sim, group, c, sim.colony)
		sim.emit_signal("event", "%d people from the %s join your tribe and are on their way." % [group.size(), c.name], "major_good")
	else:
		sim.emit_signal("event", "You turned them away. They will not cross into your land.", "info")
		found_tribe(sim, c, group)


static func _announce_leave(sim: Sim, c: Colony, group: Array, what: String) -> void:
	var lead: Human = group[0]
	if c.civ_id == 0:
		sim.emit_signal("event", "Unrest! %d of your people, led by %s, have left to %s." % [group.size(), lead.name, what], "major_bad")
	elif sim.have_met(0, c.civ_id):
		sim.emit_signal("event", "%d unhappy people have left the %s to %s." % [group.size(), c.name, what], "major")


## Moves people from one tribe to another and sends them walking to their new home.
static func move_people(sim: Sim, group: Array, from: Colony, to: Colony) -> void:
	for p in group:
		var hp: Human = p
		if hp.partner_id >= 0:
			var partner := sim.person(hp.partner_id)
			if partner != null and not group.has(partner):
				partner.partner_id = -1
				hp.partner_id = -1
		sim.release_claims(hp.id)
		if hp.carry_total() > 0:
			for k in hp.carrying.keys():
				from.add(str(k), float(hp.carrying[k]))
			hp.carrying = {}
		from.unregister(hp)
		hp.civ_id = to.civ_id
		to.register(hp)
		hp.job = "gatherer" if hp.is_adult() else hp.job
		hp.drafted = false
		hp.bed_id = -1
		hp.task = {}
		hp.path = []
		hp.task_memory = {}
		if hp.weapon != "" and hp.job != "soldier":
			to.add(hp.weapon, 1)
			hp.weapon = ""
		HumanAI.order_move(sim, hp, sim.paths.open_near(to.home, 4))
	from.invalidate_bonus()
	to.invalidate_bonus()


## The group founds a new tribe in free land nearby.
static func found_tribe(sim: Sim, c: Colony, group: Array) -> void:
	var spot := _free_spot(sim, c)
	if spot.x < 0:
		if c.civ_id == 0:
			sim.emit_signal("event", "A group wanted to leave, but there is no free land to go to. They stay, grumbling.", "warn")
		return
	var frac := float(group.size()) / maxf(1.0, c.population())
	var n := sim.new_tribe(spot, c.race)
	n.era_i = c.era_i
	n.era = c.era
	n.researched = c.researched.duplicate()
	n.knowledge = 0.0
	n.money = floorf(c.money * frac * 0.5)
	c.money -= n.money
	for item in c.stock.keys():
		var share := floorf(c.count(item) * frac * 0.5)
		if share > 0.0:
			n.add(item, c.take(item, share))
	if n.era_i >= 2:
		CivAI.choose_government(sim, n)
	var key := sim._key(c.civ_id, n.civ_id)
	sim.contacts[key] = true
	sim.relations[key] = -35.0
	if c.civ_id == 0 or sim.have_met(0, c.civ_id):
		sim.contacts[sim._key(0, n.civ_id)] = true
	n.approval = 70.0
	_announce_leave(sim, c, group, "found a new tribe, the " + n.name)
	move_people(sim, group, c, n)


## Free land for a new tribe: the nearest unclaimed state with fresh water, within reach.
static func _free_spot(sim: Sim, c: Colony) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	for s in sim.states.count():
		if int(sim.states.owners[s]) >= 0:
			continue
		var ctr: Vector2i = sim.states.centers[s]
		var d := Vector2(ctr).distance_squared_to(Vector2(c.home))
		if d > 90.0 * 90.0 or d >= best_d:
			continue
		var spot := sim.paths.open_near(ctr, 5)
		if spot.x < 0 or not WorldGen.has_fresh_water_near(sim.world, spot, 10):
			continue
		var from := sim.world.walkable_near(c.home, 4)
		if from.x < 0 or sim.paths.astar.get_id_path(from, spot, false).is_empty():
			continue
		best_d = d
		best = spot
	return best



# ---------------------------------------------------------------- civil war
## How much one adult likes the current leader (below 40: they want them gone). Built from the
## tribe's mood, family ties to the leader or to the runner-up, their own hunger and health,
## and a lasting personal leaning.
static func opinion(sim: Sim, c: Colony, v: Human, ld: Human) -> float:
	var s := c.approval
	s += Elections._kin_pull(v, ld) * 5.0
	if not c.last_election.is_empty():
		var res: Array = c.last_election.get("results", [])
		if res.size() > 1:
			var rival := sim.person(int(res[1][0]))
			if rival != null and rival.alive and rival.civ_id == c.civ_id:
				s -= Elections._kin_pull(v, rival) * 3.0
				if rival == v:
					s -= 40.0
	if v.hunger < 30.0:
		s -= 12.0
	if v.is_sick():
		s -= 5.0
	s += float((v.id * 7919) % 41) - 20.0      # some people just like or dislike them
	if v == ld:
		s += 100.0
	return s


## Share (0..1) of the tribe's adults who don't want the current leader.
static func dislike_share(sim: Sim, c: Colony) -> float:
	var ld := Elections.leader(sim, c)
	if ld == null:
		return 0.0
	var n := 0
	var bad := 0
	for p in c.living():
		if p.age_years() >= 16.0:
			n += 1
			if opinion(sim, c, p, ld) < 40.0:
				bad += 1
	return float(bad) / maxf(1.0, float(n))


## Civil war: the half of the tribe that wants the leader gone breaks away, takes the far half
## of the land (and what stands on it) and fights the loyalists.
static func civil_war(sim: Sim, c: Colony) -> void:
	var ld := Elections.leader(sim, c)
	if ld == null:
		return
	var rebels_pool: Array = []
	for p in c.living():
		if p.age_years() >= 16.0 and p != ld and not p.at_sea() and opinion(sim, c, p, ld) < 40.0:
			rebels_pool.append(p)
	var group := pick_group(sim, rebels_pool, rebels_pool.size() + 4)
	if group.size() < 2:
		return
	add_children(c, group)
	c.civil_war_after = sim.time.cal_years() + 6.0
	# split the land: the rebels take the states farthest from the old home
	var owned: Array = sim.states.owned_by(c.civ_id)
	var home_s := sim.states.at(c.home)
	owned.erase(home_s)
	owned.sort_custom(func(a, b): return Vector2(sim.states.centers[a]).distance_squared_to(Vector2(c.home)) > Vector2(sim.states.centers[b]).distance_squared_to(Vector2(c.home)))
	var take: Array = owned.slice(0, (owned.size() + 1) / 2)
	var spot := Vector2i(-1, -1)
	if not take.is_empty():
		spot = sim.paths.open_near(sim.states.centers[take[0]], 6)
	if spot.x < 0:
		spot = _free_spot(sim, c)
	if spot.x < 0:
		return
	var frac := float(group.size()) / maxf(1.0, c.population())
	var n := sim.new_tribe(spot, c.race)
	n.era_i = c.era_i
	n.era = c.era
	n.researched = c.researched.duplicate()
	n.money = floorf(c.money * frac)
	c.money -= n.money
	for item in c.stock.keys():
		var share := floorf(c.count(item) * frac)
		if share > 0.0:
			n.add(item, c.take(item, share))
	for st in take:
		sim.states.set_owner(st, n.civ_id)
	# buildings on the rebels' land change hands
	var moved: Array = []
	for b in c.buildings:
		var st2 := sim.states.at(b.center_tile())
		if take.has(st2):
			moved.append(b)
	for b in moved:
		c.buildings.erase(b)
		b.civ_id = n.civ_id
		b.occupants.clear()
		n.buildings.append(b)
	if n.era_i >= 2:
		CivAI.choose_government(sim, n)
	n.approval = 65.0
	var key := sim._key(c.civ_id, n.civ_id)
	sim.contacts[key] = true
	sim.relations[key] = -100.0
	if c.civ_id == 0 or sim.have_met(0, c.civ_id):
		sim.contacts[sim._key(0, n.civ_id)] = true
	var title := Elections.title_for(c)
	var head: Human = group[0]
	if c.civ_id == 0:
		sim.emit_signal("event", "CIVIL WAR! Half your people turned against %s %s. %d rebels, led by %s, broke away as the %s and took %d of your lands!" % [
			title, ld.name, group.size(), head.name, n.name, take.size()], "major_bad")
	elif sim.have_met(0, c.civ_id):
		sim.emit_signal("event", "Civil war has torn the %s apart! Rebels against %s %s formed the %s." % [c.name, title, ld.name, n.name], "major")
	else:
		sim.chronicle("Far away, civil war split a tribe in two: the %s were born." % n.name, "major")
	move_people(sim, group, c, n)
	for p in group:
		p.bed_id = -1
	sim.declare_war(n.civ_id, c.civ_id, true)
	c.invalidate_bonus()
	n.invalidate_bonus()
	sim.emit_signal("buildings_changed")
