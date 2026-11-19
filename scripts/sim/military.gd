class_name Military
extends RefCounted
## Making soldiers: train one of your own people at a Training Camp or Mercenary Hall, or hire an
## armed newcomer at a Mercenary Hall for Talents. Two kinds: Warriors (close combat) and Archers (ranged).


static func hire_cost(c: Colony, kind: String) -> int:
	return int(float(Defs.SOLDIER_KINDS[kind]["hire"]) * (1.0 + 0.5 * maxi(0, c.era_i - 1)))


static func kind_name(kind: String) -> String:
	return str(Defs.SOLDIER_KINDS.get(kind, Defs.SOLDIER_KINDS["warrior"])["name"])


## "" if the tribe can train a soldier now.
static func train_problem(c: Colony) -> String:
	if not c.job_allowed("soldier"):
		return "Build a Training Camp or a Mercenary Hall first."
	if _pick_recruit(c) == null:
		return "Nobody is free to train (adults who aren't soldiers already)."
	return ""


## The best person to turn into a soldier: a healthy adult in the least important job.
static func _pick_recruit(c: Colony) -> Human:
	var rank := {"laborer": 0, "gatherer": 1, "woodcutter": 2, "fisherman": 3, "hunter": 4, "builder": 5, "miner": 6,
		"farmer": 7, "cook": 8, "trader": 9, "researcher": 10, "healer": 11, "smith": 12}
	var best: Human = null
	var best_v := 1e9
	for p in c.living():
		if p.job == "soldier" or not p.is_adult() or p.age_years() > 55.0 or p.at_sea():
			continue
		var v = float(rank.get(p.job, 5)) * 10.0 - p.health * 0.05 - p.skill("soldier") * 2.0 - p.skill("hunter")
		if p.pregnant_days >= 0.0:
			v += 50.0
		if v < best_v:
			best_v = v
			best = p
	return best


static func train(sim: Sim, c: Colony, kind: String) -> Human:
	if train_problem(c) != "":
		return null
	var p := _pick_recruit(c)
	p.job = "soldier"
	p.soldier_kind = kind
	p.drafted = true
	if int(p.task.get("prio", 0)) <= HumanAI.PRIO_JOB:
		p.task = {}
		p.path = []
		sim.release_claims(p.id)
	sim.notify(c.civ_id, "%s has become %s %s.%s" % [p.name, "an" if kind == "archer" else "a", kind_name(kind),
		"" if c.best_stock_weapon(kind) != "" else " The Blacksmith will forge them a weapon."], "good")
	return p


## "" if the tribe can hire a soldier of this kind now.
static func hire_problem(c: Colony, kind: String) -> String:
	if not c.has_built("mercenary_hall"):
		return "Build a Mercenary Hall first (research Mercenary Pacts)."
	if c.money < hire_cost(c, kind):
		return "You need %d %s." % [hire_cost(c, kind), Defs.MONEY_NAME]
	return ""


## A hired sword arrives at the Mercenary Hall, armed and ready.
static func hire(sim: Sim, c: Colony, kind: String) -> Human:
	if hire_problem(c, kind) != "":
		return null
	var hall := c.nearest_building(sim.world.center_of(c.home), "mercenary_hall")
	c.money -= hire_cost(c, kind)
	var g := "M" if sim.rng.randf() < 0.7 else "F"
	var at := hall.center() + Vector2(sim.rng.randf_range(-10, 10), Defs.TILE * 1.4)
	var p := sim._make_human(c, g, sim.rng.randf_range(20.0, 34.0) * Defs.AGE_YEAR_DAYS, at)
	p.job = "soldier"
	p.soldier_kind = kind
	p.drafted = true
	p.hired = true
	p.weapon = Defs.best_weapon_for(kind, c.era_i)
	p.skills = {"soldier": sim.rng.randf_range(3.0, 6.0)}
	p.clothed = true
	sim.notify(c.civ_id, "%s, a hired %s with a %s, joins your tribe." % [p.name, kind_name(kind).to_lower(),
		Defs.WEAPONS[p.weapon]["name"].to_lower() if p.weapon != "" else "bare fists"], "good")
	return p


## Sends a soldier back to ordinary work.
static func discharge(sim: Sim, p: Human) -> void:
	var c := sim.col_of(p)
	if p.weapon != "":
		c.add(p.weapon, 1)
		p.weapon = ""
	p.job = "laborer"
	p.drafted = false
	p.task = {}
	p.path = []
	sim.notify(c.civ_id, "%s put down their arms and went back to work." % p.name, "info")


## Kind for a new soldier so a tribe keeps about one Archer for every two Warriors.
static func balanced_kind(c: Colony) -> String:
	var w := c.soldiers("warrior").size()
	var a := c.soldiers("archer").size()
	return "archer" if a * 2 < w else "warrior"


## AI tribes hire when they're rich and threatened.
static func ai_hire(sim: Sim, c: Colony) -> void:
	if not c.has_built("mercenary_hall") or sim.rng.randf() > 0.1:
		return
	var threatened := not sim.enemies_of(c.civ_id).is_empty()
	var kind := balanced_kind(c)
	if c.money >= hire_cost(c, kind) * (1.5 if threatened else 4.0) and c.soldiers().size() < c.population() / 2:
		hire(sim, c, kind)
