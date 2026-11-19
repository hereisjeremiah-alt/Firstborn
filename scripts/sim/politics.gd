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
## A group of unhappy people leaves.
static func split(sim: Sim, c: Colony) -> void:
	var adults: Array = []
	for p in c.living():
		if p.age_years() >= 16.0 and p.id != c.leader_id and not p.at_sea():
			adults.append(p)
	if adults.size() < 4:
		return
	adults.shuffle()
	var n := clampi(roundi(adults.size() * SPLIT_SHARE), 2, 12)
	var group: Array = adults.slice(0, n)
	# their young children come with them
	for p in c.living():
		if p.age_years() < 14.0 and not group.has(p):
			for g in group:
				if p.mother_id == g.id or p.father_id == g.id:
					group.append(p)
					break
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
