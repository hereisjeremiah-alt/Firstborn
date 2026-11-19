class_name Survival
extends RefCounted
## Needs, temperature, illness, eating/drinking, food spoilage, aging, pairing and births.
## Written against Colony/Human so AI civilizations can run through exactly the same rules.

const COMFORT_TEMP := 5.0   # hide-clad cavemen tolerate cool weather


static func tick(sim: Sim, p: Human, dt: float) -> void:
	if sim.civ(p.civ_id).bandit:
		Bandits.keep_fed(p, dt)
		return
	var hours := dt / Defs.HOUR
	var days := hours / 24.0
	var t := sim.world.tile_of(p.pos)
	var temp := sim.temp_at(t)
	var young := p.age_years() < 12.0
	var mult := 0.6 if young else 1.0
	if p.at_sea():
		mult *= 0.25        # at sea: resting and living on provisions

	# --- hunger / thirst / energy
	var hunger_rate := Config.rule("hunger_rate") * mult * (1.2 if temp < 0.0 else 1.0)
	if p.pregnant_days >= 0.0:
		hunger_rate *= 1.25
	p.hunger = maxf(0.0, p.hunger - hunger_rate * hours)
	var thirst_rate := 3.8 * Config.rule("hunger_rate") * mult * (1.6 if temp > 30.0 else (1.25 if sim.time.season() == 1 else 1.0))
	p.thirst = maxf(0.0, p.thirst - thirst_rate * hours)
	if p.sleeping:
		var bed: Building = null
		if p.bed_id >= 0:
			bed = sim.building(p.bed_id)
		var rate := 13.0 if bed != null and bed.built else 9.0
		if bed != null and bed.zoned:
			rate *= 1.2           # a quiet housing quarter
		if p.is_sick():
			rate *= 1.2
		p.energy = minf(100.0, p.energy + rate * hours)
	else:
		p.energy = maxf(0.0, p.energy - 4.0 * hours)

	# infants are fed and watered by the tribe
	if p.age_years() < 3.0:
		if p.hunger < 60.0:
			eat_from_stock(sim, p)
			if p.hunger < 60.0:
				var mom := sim.person(p.mother_id)
				if mom == null or not mom.alive:
					mom = null
					for q in sim.col_of(p).living():
						if q.is_adult():
							mom = q
							break
				if mom != null:
					p.hunger = minf(100.0, p.hunger + 20.0)
					mom.hunger = maxf(0.0, mom.hunger - 10.0)
		if p.thirst < 60.0:
			if sim.col_of(p).count("water") >= 0.5:
				sim.col_of(p).take("water", 0.5)
				p.thirst = minf(100.0, p.thirst + 40.0)
			else:
				# nursed by the mother — or anyone in the tribe if she is gone
				var nurse := sim.person(p.mother_id)
				if nurse == null or not nurse.alive:
					nurse = null
					for q in sim.col_of(p).living():
						if q.is_adult():
							nurse = q
							break
				if nurse != null:
					p.thirst = minf(100.0, p.thirst + 40.0)
					nurse.thirst = maxf(0.0, nurse.thirst - 12.0)

	# --- warmth
	var eff := temp
	var near_fire := false
	for f in sim.col_of(p).lit_fires():
		if f.center().distance_squared_to(p.pos) < pow(4.5 * Defs.TILE, 2):
			near_fire = true
			break
	if near_fire:
		eff += 16.0
	if p.clothed:
		eff += 8.0 + sim.col_of(p).bonus("warmth")
	if p.age_years() < 3.0:
		var mother := sim.person(p.mother_id)
		if mother != null and mother.alive and mother.pos.distance_to(p.pos) < 2.5 * Defs.TILE:
			eff += 10.0          # carried and kept warm
	var sheltered := false
	if p.sleeping and p.bed_id >= 0:
		var b := sim.building(p.bed_id)
		if b != null and b.built:
			sheltered = bool(b.def().get("warm", false))
			eff += 12.0 if sheltered else 5.0
	if not sheltered:
		var here_b := sim.building_at(t)
		if here_b != null and here_b.built and bool(here_b.def().get("warm", false)):
			sheltered = true
			eff += 12.0
	p.wet = sim.weather.is_wet() and not sheltered and not near_fire
	if p.wet:
		eff -= 4.0
	if eff >= COMFORT_TEMP:
		p.warmth = minf(100.0, p.warmth + (eff - COMFORT_TEMP + 4.0) * 0.9 * hours)
	else:
		p.warmth = maxf(0.0, p.warmth - (COMFORT_TEMP - eff) * 0.32 * hours)

	# --- health
	var dmg := 0.0
	var why := ""
	if p.hunger <= 0.0:
		dmg += 1.4 * hours
		why = "starvation"
	if p.thirst <= 0.0:
		dmg += 2.6 * hours
		why = "dehydration"
	if p.warmth < 10.0:
		dmg += (10.0 - p.warmth) * 0.05 * hours
		why = "freezing cold"
	if temp > 38.0 and p.thirst < 30.0:
		dmg += 0.8 * hours
		why = "heat stroke"
	if p.is_sick():
		var ill: Dictionary = Defs.ILLNESS[p.illness["type"]]
		var resting: bool = p.sleeping or p.task.get("type", "") == "rest"
		dmg += float(ill["drain"]) * days * (0.6 if resting else 1.0)
		if why == "":
			why = str(ill["name"]).to_lower()
		var cure := (1.5 if resting else 1.0) * (1.0 + sim.col_of(p).bonus("medicine")) * (1.4 if sim.col_of(p).has_built("healer_hut") else 1.0)
		p.illness["days"] = float(p.illness["days"]) - days * cure
		if float(p.illness["days"]) <= 0.0:
			sim.notify(p.civ_id, "%s recovered from %s." % [p.name, ill["name"]], "good")
			if ill.get("lifelong", false) and not p.illness["type"] in p.immunities:
				p.immunities.append(p.illness["type"])
			p.illness = {}
			p.immune_days = 6.0
	if dmg > 0.0:
		p.health -= dmg
	elif p.hunger > 35.0 and p.thirst > 35.0 and p.warmth > 35.0:
		p.health = minf(100.0, p.health + (1.4 if p.sleeping else 0.6) * hours)
	p.immune_days = maxf(0.0, p.immune_days - days)

	# --- age
	# children grow up three times faster than adults age, so the tribe gets new workers sooner
	# aging follows the calendar, which runs TimeSystem.CAL_SCALE times faster than daily life
	p.age_days += days * sim.time.scale * (Config.rule("child_growth") if p.age_years() < 16.0 else Config.rule("aging_speed"))

	if p.health <= 0.0:
		sim.kill(p, why if why != "" else "poor health")


# ---------------------------------------------------------------- eating & drinking
## Eats from the shared stockpile until satisfied. Returns true if anything was eaten.
static func eat_from_stock(sim: Sim, p: Human) -> bool:
	var ate := false
	for item in Defs.EAT_ORDER:
		while p.hunger < 92.0 and sim.col_of(p).count(item) >= 1.0:
			sim.col_of(p).take(item, 1.0)
			eat_item(sim, p, item)
			ate = true
		if p.hunger >= 92.0:
			break
	# half-units left at the end of the pile
	if not ate:
		for item in Defs.EAT_ORDER:
			var c := sim.col_of(p).count(item)
			if c > 0.05:
				sim.col_of(p).take(item, c)
				p.hunger = minf(100.0, p.hunger + float(Defs.FOOD[item]["nut"]) * c)
				ate = true
				break
	return ate


static func eat_item(sim: Sim, p: Human, item: String) -> void:
	var f: Dictionary = Defs.FOOD.get(item, {"nut": 8.0, "sick": 0.0})
	p.hunger = minf(100.0, p.hunger + float(f["nut"]))
	if sim.rng.randf() < float(f["sick"]) * 0.35 * Config.rule("illness_freq"):
		infect(sim, p, "food_poisoning", "eating %s" % Defs.item_name(item).to_lower())


static func drink_at(sim: Sim, p: Human, water_tile: Vector2i) -> void:
	p.thirst = 100.0
	var ter := sim.world.t_at(water_tile) if sim.world.inb(water_tile) else Defs.T.RIVER
	var chance := 0.0
	if ter == Defs.T.LAKE:
		chance = 0.01
	elif ter == Defs.T.RIVER:
		chance = 0.005
	if sim.weather.is_wet():
		chance *= 1.5
	chance *= 1.0 - minf(0.85, sim.col_of(p).bonus("water_safety"))
	if sim.rng.randf() < chance * Config.rule("illness_freq"):
		infect(sim, p, "typhoid" if sim.rng.randf() < 0.1 else "dysentery", "drinking dirty water")


static func infect(sim: Sim, p: Human, type: String, reason := "", force := false) -> void:
	if not p.alive or type in p.immunities:
		return
	if (p.is_sick() or p.immune_days > 0.0) and not force:
		return
	var d: Dictionary = Defs.ILLNESS[type]
	p.illness = {"type": type, "days": float(d["days"]) * sim.rng.randf_range(0.8, 1.3), "treated": -10.0}
	var why := (" from " + reason) if reason != "" else ""
	var risk := death_risk(sim, p)
	var kind := "bad"
	sim.notify(p.civ_id, "%s fell ill with %s%s (%s chance of death within %s)." % [p.name, d["name"], why, pct_text(risk), Defs.illness_window(type)], kind)


## Chance this person dies of their current illness before it runs its course, given their age
## and the care they get. Children under 6 and elders are much more vulnerable.
static func death_risk(sim: Sim, p: Human) -> float:
	if not p.is_sick():
		return 0.0
	var d: Dictionary = Defs.ILLNESS[p.illness["type"]]
	var r := float(d["death"])
	var age := p.age_years()
	if age < 6.0:
		r *= float(d.get("child", 1.0)) * Config.rule("child_risk")
	elif age < 12.0:
		r *= 1.2
	elif age >= 55.0:
		r *= 1.7
	elif age >= 45.0:
		r *= 1.25
	if p.health < 40.0:
		r *= 1.3
	if p.frail:
		r *= 1.5
	var c := sim.col_of(p)
	var care := 1.0 - minf(0.6, c.bonus("medicine") + c.bonus("heal") * 0.5)
	if c.has_built("healer_hut"):
		care *= 0.8
	if sim.time.t - float(p.illness.get("treated", -10.0)) < 1.5:
		care *= 0.6
	if p.sleeping:
		care *= 0.85
	if p.illness["type"] == "rabies":
		care = maxf(care, 0.97)       # nothing ancient medicine can do
	return clampf(r * care * Config.rule("illness_lethality"), 0.0, 0.99)


static func pct_text(r: float) -> String:
	if r < 0.01:
		return "<1%"
	return "%d%%" % int(round(r * 100.0))


# ---------------------------------------------------------------- periodic
static func hourly(sim: Sim, c: Colony) -> void:
	var people := c.living()
	var freq := Config.rule("illness_freq")
	for p in people:
		# catching a cold when freezing or soaked
		if p.warmth < 30.0 or (p.wet and p.warmth < 60.0):
			if sim.rng.randf() < 0.02 * freq:
				infect(sim, p, "cold", "the cold")
		# random fever
		if sim.rng.randf() < 0.00025 * freq:
			infect(sim, p, "fever")
		# flu season (late autumn & winter)
		var season := sim.time.season()
		if (season == 3 or season == 2) and sim.rng.randf() < 0.0004 * freq:
			infect(sim, p, "flu", "the flu season")
		# measles (once in a lifetime)
		if sim.rng.randf() < 0.00008 * freq:
			infect(sim, p, "measles")
		# tuberculosis, worse in crowded camps
		if sim.rng.randf() < 0.000015 * (1.0 + people.size() / 12.0) * freq:
			infect(sim, p, "tuberculosis")
		# plague: only in big Bronze/Iron Age settlements
		if c.era_i >= 2 and people.size() >= 14 and sim.rng.randf() < 0.000006 * freq:
			infect(sim, p, "plague", "rats in the stores")
		# malaria: mosquitoes in hot, wet lowlands at night
		if sim.time.is_night() and p.aboard < 0:
			var tile := sim.world.tile_of(p.pos)
			if sim.world.inb(tile):
				var ter := sim.world.t_at(tile)
				if (ter == Defs.T.SWAMP or ter == Defs.T.RAINFOREST) and sim.world.base_temp[sim.world.idx(tile)] > 18.0 and sim.rng.randf() < 0.004 * freq:
					infect(sim, p, "malaria", "mosquito bites")
		if p.is_sick():
			var typ: String = p.illness["type"]
			# a cold or flu can turn into pneumonia when the sick person stays cold
			if (typ == "cold" or typ == "flu") and p.warmth < 35.0 and sim.rng.randf() < 0.006:
				infect(sim, p, "pneumonia", "a chill on the lungs", true)
			# chance of dying this hour, so the illness's total risk plays out over its course
			var risk := death_risk(sim, p)
			if risk > 0.0:
				var hours := float(Defs.ILLNESS[p.illness["type"]]["days"]) * 24.0
				var hz := 1.0 - pow(1.0 - risk, 1.0 / hours)
				if sim.rng.randf() < hz:
					sim.kill(p, str(Defs.ILLNESS[p.illness["type"]]["name"]).to_lower())
					continue
		# contagion
		if p.is_sick():
			var spread: float = Defs.ILLNESS[p.illness["type"]]["spread"] * (1.0 - minf(0.8, c.bonus("sanitation"))) * Config.rule("contagion")
			if spread > 0.0:
				for q in people:
					if q != p and not q.is_sick() and q.pos.distance_squared_to(p.pos) < pow(2.5 * Defs.TILE, 2):
						if sim.rng.randf() < spread:
							infect(sim, q, p.illness["type"], "%s" % p.name)


static func daily(sim: Sim, c: Colony) -> void:
	var season := sim.time.season()
	# --- food spoilage
	var mod := 1.0 - c.preservation()
	mod *= [1.0, 1.25, 0.6, 0.12][season] * Config.rule("spoilage")
	var lost := 0.0
	for f in Defs.FOOD.keys():
		var have := c.count(f)
		if have <= 0.0:
			continue
		var gone := have * float(Defs.FOOD[f]["spoil"]) * mod
		c.take(f, gone)
		lost += gone
	if lost >= 3.0:
		sim.notify(c.civ_id, "%d units of food spoiled. Storage and drying racks slow this down." % int(lost), "warn")

	# --- storage overflow (materials beyond capacity rot or get lost)
	var cap := c.storage_capacity()
	var total := c.material_total()
	if total > cap * 1.15:
		var excess := total - cap
		for k in c.stock.keys():
			if k == "water" or Defs.FOOD.has(k):
				continue
			c.stock[k] = c.count(k) * (1.0 - 0.1 * excess / total)
		sim.notify(c.civ_id, "Storage is overflowing — build a Storage Area.", "warn")
	if c.count("water") > c.water_capacity():
		c.stock["water"] = c.water_capacity()

	var people := c.living()
	# --- hide clothing: spare hides are sewn into warm clothes
	for p in people:
		if not p.clothed and c.count("hides") >= 1.0:
			c.take("hides", 1.0)
			p.clothed = true
			sim.notify(c.civ_id, "%s now wears warm hide clothing." % p.name, "info")
	# --- old age
	for p in people:
		var a: float = p.age_years()
		if a > 55.0 and sim.rng.randf() < (a - 55.0) * 0.0015:
			sim.kill(p, "old age")
	people = c.living()

	# --- pairing
	var singles_m: Array = []
	var singles_f: Array = []
	for p in people:
		if p.partner_id == -1 and p.age_years() >= 16.0 and p.age_years() < 50.0:
			if p.gender == "M":
				singles_m.append(p)
			else:
				singles_f.append(p)
	for m in singles_m:
		for f in singles_f:
			if f.partner_id != -1 or m.partner_id != -1:
				continue
			var chance := 0.3
			if _related(m, f):
				if Config.rule("allow_kin") < 0.5:
					continue
				chance = 0.12        # family is allowed, but strangers are still preferred
			if sim.rng.randf() < chance:
				m.partner_id = f.id
				f.partner_id = m.id
				sim.notify(c.civ_id, "%s and %s have become partners." % [m.name, f.name], "good")

	# --- pregnancy & birth
	var pop := people.size()
	var housing := c.housing()
	for p in people:
		if p.gender != "F":
			continue
		if p.pregnant_days >= 0.0:
			p.pregnant_days += 1.0
			if p.pregnant_days >= Config.rule("pregnancy_days"):
				sim.give_birth(p)
				if sim.rng.randf() < Config.rule("twin_chance"):
					sim.give_birth(p)          # twins!
				p.pregnant_days = -Config.rule("birth_recovery") - 0.01   # recovery before the next child
			continue
		if p.pregnant_days < -1.0:
			p.pregnant_days += 1.0
			continue
		if p.partner_id == -1 or p.age_years() < 16.0 or p.age_years() > 46.0:
			continue
		var partner := c.person(p.partner_id)
		if partner == null or not partner.alive:
			continue
		if p.health < 45.0 or p.hunger < 25.0 or p.is_sick():
			continue
		if c.food_days() < 0.6:
			continue
		# room to grow: the first children can be raised in the open, after that shelter is needed
		if pop >= housing + 4:
			continue
		var chance := (0.22 if season != 3 else 0.10) * maxf(0.1, 1.0 + c.bonus("fertility")) * Config.rule("birth_chance")
		if sim.rng.randf() < chance:
			p.pregnant_days = 0.0
			sim.notify(c.civ_id, "%s is expecting a child." % p.name, "good")

	# --- children come of age
	for p in people:
		if p.job == "child" and p.age_years() >= Config.rule("work_age"):
			p.job = "gatherer"
			sim.notify(c.civ_id, "%s is old enough to help the tribe and becomes a Gatherer." % p.name, "info")

	# --- winter warning
	if season == 2 and sim.time.days_to_winter() <= 60 and sim.time.day() % 3 == 0:
		var need := float(pop) * 20.0
		if c.food_days() * pop < need:
			sim.notify(c.civ_id, "Winter is near and food stores are low (%.1f days). Hunt, gather and dry meat!" % c.food_days(), "warn")


static func related(a: Human, b: Human) -> bool:
	return _related(a, b)


static func _related(a: Human, b: Human) -> bool:
	if a.mother_id == b.id or a.father_id == b.id or b.mother_id == a.id or b.father_id == a.id:
		return true
	if a.mother_id != -1 and a.mother_id == b.mother_id:
		return true
	if a.father_id != -1 and a.father_id == b.father_id:
		return true
	return false
