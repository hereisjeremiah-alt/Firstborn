class_name Conditions
extends RefCounted
## Long-lasting (chronic) conditions, kept apart from short illnesses:
##  - Dementia: only from age 45. It grows worse with age; sufferers stop in the middle of a task,
##    having forgotten what they were doing. From 70 they can no longer work and do harm instead
##    (spoil food in the stores, let fires die, drop what they carry, wander off).
##  - Obesity: from eating well for a long time while doing little hard work. Slower, works a little
##    less, and makes type 2 diabetes 25% more likely. Lean times can take it away again.
##  - Type 2 diabetes: more likely with age (and obesity). Slowly wears health and energy down;
##    a Healer's Hut and healers keep it in check.

const INFO := {
	"dementia": {"name": "Dementia", "desc": "Forgets what they were doing. Gets worse with age; from 70 they do more harm than good."},
	"obesity": {"name": "Obesity", "desc": "Moves 15% slower and works 10% slower. Type 2 diabetes is 25% more likely."},
	"diabetes": {"name": "Type 2 Diabetes", "desc": "Slowly wears down health and energy; worse without a healer."},
}
const DEMENTIA_AGE := 45.0
const DEMENTIA_HARM_AGE := 70.0
const OBESITY_DIABETES := 1.25       # obesity makes diabetes 25% more likely


static func label(p: Human) -> String:
	var parts := PackedStringArray()
	for k in p.conditions.keys():
		var n := str(INFO[k]["name"]) if INFO.has(k) else str(k)
		if k == "dementia":
			n += " (severe)" if p.dementia_harmful() else (" (%d%%)" % roundi(p.dementia_level() * 100.0))
		parts.append(n)
	return ", ".join(parts)


## Once a day for every tribe: new cases, losing weight, and diabetes wearing people down.
static func daily(sim: Sim, c: Colony) -> void:
	var freq := Config.rule("illness_freq")
	var fd := c.food_days()
	var healer := c.has_built("healer_hut") or c.living().any(func(q): return q.job == "healer")
	for p in c.living():
		var a = p.age_years()
		# --- dementia (45+)
		if a >= DEMENTIA_AGE and not p.conditions.has("dementia"):
			var yearly := 0.004 * pow(1.12, a - DEMENTIA_AGE)
			if sim.rng.randf() < yearly / Defs.AGE_YEAR_DAYS * freq:
				p.conditions["dementia"] = a
				sim.notify(c.civ_id, "%s (%d) is growing forgetful — the first signs of dementia." % [p.name, int(a)], "warn")
		# --- obesity: plenty of food, little hard work
		if p.is_adult():
			if not p.conditions.has("obesity"):
				if p.hunger > 80.0 and fd > 8.0:
					var jf := 1.0
					if p.job in ["hunter", "soldier", "laborer", "woodcutter", "lumberer", "miner", "builder", "farmer"]:
						jf = 0.45
					elif p.job in ["researcher", "trader", "cook", "smith", "healer"]:
						jf = 1.6
					if sim.rng.randf() < 0.0018 * jf * freq:
						p.conditions["obesity"] = a
						sim.notify(c.civ_id, "%s has become obese from easy living." % p.name, "info")
			elif (p.hunger < 35.0 or fd < 1.5) and sim.rng.randf() < 0.03:
				p.conditions.erase("obesity")
				sim.notify(c.civ_id, "%s has lost the extra weight." % p.name, "good")
		# --- type 2 diabetes (30+), 25% likelier with obesity
		if a >= 30.0 and not p.conditions.has("diabetes"):
			var yearly2 := 0.006 * pow(1.05, a - 30.0)
			if p.conditions.has("obesity"):
				yearly2 *= OBESITY_DIABETES
			if sim.rng.randf() < yearly2 / Defs.AGE_YEAR_DAYS * freq:
				p.conditions["diabetes"] = a
				sim.notify(c.civ_id, "%s (%d) has developed type 2 diabetes." % [p.name, int(a)], "warn")
		if p.conditions.has("diabetes"):
			var wear := 0.6 * (0.4 if healer else 1.0) * (1.3 if p.conditions.has("obesity") else 1.0)
			p.health = maxf(1.0, p.health - wear)
			if p.health < 25.0 and sim.rng.randf() < (0.004 if healer else 0.012) * Config.rule("illness_lethality"):
				sim.kill(p, "complications of diabetes")
				continue


## Every game hour: diabetics tire faster; people with severe dementia do harm.
static func hourly(sim: Sim, c: Colony) -> void:
	for p in c.living():
		if p.conditions.has("diabetes"):
			p.energy = maxf(0.0, p.energy - 0.35)
		if p.dementia_harmful() and not p.sleeping and sim.rng.randf() < 0.035:
			_harm(sim, c, p)


## Severe dementia: one confused, harmful act.
static func _harm(sim: Sim, c: Colony, p: Human) -> void:
	var roll := sim.rng.randi() % 4
	match roll:
		0:
			var foods: Array = []
			for f in Defs.FOOD.keys():
				if c.count(f) >= 2.0:
					foods.append(f)
			if not foods.is_empty():
				var f: String = foods[sim.rng.randi() % foods.size()]
				var n := minf(c.count(f), float(sim.rng.randi_range(2, 6)))
				c.take(f, n)
				sim.notify(c.civ_id, "%s, confused, rummaged through the stores and spoiled %d %s." % [p.name, int(n), Defs.item_name(f).to_lower()], "warn")
				return
		1:
			for b in c.buildings:
				if b.is_lit() and b.fuel > 2.0 and b.center().distance_to(p.pos) < 20.0 * Defs.TILE:
					b.fuel = 0.5
					sim.notify(c.civ_id, "%s forgot to tend the fire and let it burn low." % p.name, "warn")
					return
		2:
			if p.carry_total() > 0:
				p.carrying = {}
				sim.notify(c.civ_id, "%s wandered off and lost what they were carrying." % p.name, "warn")
				return
	# wander away from the village
	var here := sim.world.tile_of(p.pos)
	var dest := sim.world.walkable_near(here + Vector2i(sim.rng.randi_range(-18, 18), sim.rng.randi_range(-18, 18)), 4)
	if dest.x >= 0:
		HumanAI.order_wander_off(sim, p, dest)
		if sim.rng.randf() < 0.4:
			sim.notify(c.civ_id, "%s wandered away from the village, lost and confused." % p.name, "warn")
