class_name Bandits
extends RefCounted
## Outlaw camps. A few small camps of thieves and robbers appear in the wilds at the start of a
## game (Game Rules: "Bandit camps"). All bandits belong to one outlaw band: not a tribe, at war
## with everyone, never part of diplomacy, territory or trade.
##  - Every few days a camp sends two or three robbers to the nearest village to steal Talents
##    and goods from the stores, then they run back to camp.
##  - They ambush traders passing near a camp and steal what they carry.
##  - Soldiers fight them like any enemy. Destroy a camp to recover its stash.
## Bandits don't need food or sleep; camps slowly recruit new outlaws while they stand.

const PER_CAMP := 3
const MAX_PER_CAMP := 5
const AMBUSH_R := 14.0         # tiles around a camp where traders are ambushed
const RAID_RANGE := 85.0       # tiles: villages this close to a camp get robbed
const PRIO_ROB := 32


static func band(sim: Sim) -> Colony:
	for c in sim.colonies:
		if c.bandit:
			return c
	return null


## At the start of a game, after the tribes are founded.
static func spawn_camps(sim: Sim, homes: Array) -> void:
	var n := int(Config.rule("bandit_camps"))
	if n <= 0:
		return
	var c := Colony.new()
	c.civ_id = sim.colonies.size()
	c.bandit = true
	c.name = "Outlaws"
	c.color = Color(0.25, 0.22, 0.22)
	c.flag = {"bg": Color(0.06, 0.06, 0.06), "fg": Color(0.06, 0.06, 0.06), "pattern": 0, "emblem": 1, "em": Color(0.9, 0.9, 0.85)}
	c.race = Config.player_race
	c.money = 30.0
	sim.colonies.append(c)
	var placed := 0
	for attempt in 6000:
		if placed >= n:
			break
		var t := Vector2i(sim.rng.randi_range(8, sim.world.w - 9), sim.rng.randi_range(8, sim.world.h - 9))
		var near := 1e9
		var ok := true
		for h in homes:
			var d := Vector2(t).distance_to(Vector2(h))
			near = minf(near, d)
			if d < 40.0:
				ok = false
		for b in c.buildings:
			if Vector2(t).distance_to(Vector2(b.tile)) < 30.0:
				ok = false
		if not ok or near > RAID_RANGE - 5.0:
			continue
		if sim.can_place(null, "bandit_camp", t) != "":
			continue
		if sim.world.walkable_near(t + Vector2i(1, 3), 2).x < 0:
			continue
		var b := sim.place_building(c, "bandit_camp", t)
		if b == null:
			continue
		sim.finish_building(b)
		if c.home == Vector2i.ZERO:
			c.home = b.center_tile()
		for k in PER_CAMP:
			_recruit(sim, c, b)
		placed += 1
	if placed == 0:
		sim.colonies.erase(c)


static func _recruit(sim: Sim, c: Colony, camp: Building) -> Human:
	var at := camp.center() + Vector2(sim.rng.randf_range(-14, 14), sim.rng.randf_range(10, 22))
	var p := sim._make_human(c, "M" if sim.rng.randf() < 0.8 else "F", sim.rng.randf_range(19.0, 38.0) * Defs.AGE_YEAR_DAYS, at)
	p.job = "bandit"
	p.clothed = true
	var era := 0
	for oc in sim.colonies:
		if not oc.bandit and not oc.collapsed:
			era = maxi(era, oc.era_i)
	p.weapon = ["stone_club", "flint_axe", "bronze_sword", "iron_sword"][mini(era, 3)] if sim.rng.randf() < 0.7 else \
		["stone_spear", "sling", "bow", "crossbow"][mini(era, 3)]
	p.skills = {"soldier": sim.rng.randf_range(1.0, 4.0)}
	p.task_memory["camp"] = camp.id
	return p


static func camp_of(sim: Sim, p: Human) -> Building:
	var b := sim.building(int(p.task_memory.get("camp", -1)))
	if b != null and b.type == "bandit_camp":
		return b
	# their camp is gone: join the nearest other one
	var c := sim.col_of(p)
	var best: Building = null
	var best_d := 1e18
	for cb in c.buildings:
		if cb.type == "bandit_camp":
			var d = cb.center().distance_squared_to(p.pos)
			if d < best_d:
				best_d = d
				best = cb
	if best != null:
		p.task_memory["camp"] = best.id
	return best


# ---------------------------------------------------------------- daily life
## Bandits never go hungry, thirsty or tired.
static func keep_fed(p: Human, dt: float) -> void:
	p.hunger = 100.0
	p.thirst = 100.0
	p.energy = 100.0
	p.warmth = 100.0
	p.health = minf(100.0, p.health + dt / Defs.HOUR * 1.5)


## What a bandit does when it has nothing on: bring loot home, ambush a trader, or loaf at camp.
static func plan(sim: Sim, p: Human) -> void:
	var camp := camp_of(sim, p)
	if camp == null:
		# no camps left: the outlaws scatter and leave the land
		sim.kill(p, "fled the land")
		return
	if p.carry_total() > 0 or float(p.task_memory.get("loot_money", 0.0)) > 0.0:
		HumanAI._set_task(sim, p, "bandit_home", _camp_spot(sim, camp), PRIO_ROB, {"label": "Running back to camp with loot"})
		return
	var mark := _trader_near(sim, camp)
	if mark != null:
		if HumanAI.order_attack(sim, p, "human", mark.id, PRIO_ROB):
			p.task["label"] = "Ambushing a trader"
			return
	var spot := camp.center_tile() + Vector2i(sim.rng.randi_range(-4, 4), sim.rng.randi_range(-2, 5))
	spot = sim.world.walkable_near(spot, 3)
	if spot.x < 0 or not HumanAI._set_task(sim, p, "wander", spot, HumanAI.PRIO_IDLE, {"label": "Loafing at the bandit camp", "wait": sim.rng.randf_range(4.0, 12.0)}):
		p.task = {"type": "wander", "prio": HumanAI.PRIO_IDLE, "dest": sim.world.tile_of(p.pos), "moving": false, "work": 0.0, "wait": 6.0, "label": "Loafing at the bandit camp"}


static func _camp_spot(sim: Sim, camp: Building) -> Vector2i:
	return sim.world.walkable_near(camp.center_tile() + Vector2i(0, 2), 3)


## A trader of any tribe with goods or Talents passing close to the camp.
static func _trader_near(sim: Sim, camp: Building) -> Human:
	var r2 := pow(AMBUSH_R * Defs.TILE, 2)
	for p in sim.people_all:
		if not p.alive or p.job != "trader" or p.at_sea() or sim.civ(p.civ_id).bandit:
			continue
		if p.carry_total() <= 0 and float(p.task_memory.get("trade_money", 0.0)) <= 0.0:
			continue
		if p.pos.distance_squared_to(camp.center()) < r2:
			return p
	return null


## Bandits fight back when cornered and run when badly hurt (instead of fleeing like villagers).
static func interrupts(sim: Sim, p: Human) -> void:
	var cur := int(p.task.get("prio", 0))
	# bandits are thieves, not killers: they only fight when someone fights them
	if Fx.now() - p.hurt_at > 4.0:
		return
	var foe := HumanAI._nearby_enemy(sim, p, 4.0)
	if foe == null:
		return
	if p.health < 30.0 and cur < HumanAI.PRIO_FLEE:
		var camp := camp_of(sim, p)
		if camp != null:
			HumanAI._set_task(sim, p, "flee", _camp_spot(sim, camp), HumanAI.PRIO_FLEE, {"label": "Running for the hills"})
		return
	if str(p.task.get("type", "")) != "attack" and cur < HumanAI.PRIO_DEFEND:
		HumanAI.order_attack(sim, p, "human", foe.id, HumanAI.PRIO_DEFEND)


## Called when a bandit lands a blow: traders and anyone carrying goods get robbed.
static func on_hit(sim: Sim, bandit: Human, victim: Human) -> void:
	var money := float(victim.task_memory.get("trade_money", 0.0))
	if victim.carry_total() <= 0 and money <= 0.0:
		# nothing to take: an ambusher lets them go (unless this is a real fight)
		if int(bandit.task.get("prio", 0)) == PRIO_ROB:
			HumanAI._done(sim, bandit)
		return
	var got := PackedStringArray()
	for k in victim.carrying.keys():
		bandit.add_carry(str(k), int(victim.carrying[k]))
		got.append("%d %s" % [int(victim.carrying[k]), Defs.item_name(str(k))])
	victim.carrying = {}
	if money > 0.0:
		bandit.task_memory["loot_money"] = float(bandit.task_memory.get("loot_money", 0.0)) + money
		victim.task_memory["trade_money"] = 0.0
		got.append("%d %s" % [int(money), Defs.MONEY_NAME])
	Trade.on_trader_robbed(sim, victim)
	var vc := sim.col_of(victim)
	if vc.civ_id == 0:
		vc.recent_robbed = 5.0
		sim.emit_signal("event", "Bandits ambushed your trader %s and stole %s!" % [victim.name, ", ".join(got) if not got.is_empty() else "everything"], "major_bad")
	# victim runs home, the bandit runs off with the loot
	HumanAI._set_task(sim, victim, "flee", vc.drop_point(victim.pos), HumanAI.PRIO_FLEE, {"label": "Fleeing from bandits"})
	var camp := camp_of(sim, bandit)
	if camp != null:
		HumanAI._set_task(sim, bandit, "bandit_home", _camp_spot(sim, camp), PRIO_ROB, {"label": "Running back to camp with loot"})


# ---------------------------------------------------------------- raids
## Hourly: camps send robbers out now and then, and slowly recruit.
static func hourly(sim: Sim) -> void:
	var c := band(sim)
	if c == null or c.collapsed:
		return
	if c.population() == 0 and not c.buildings.any(func(b): return b.type == "bandit_camp"):
		c.collapsed = true
		return
	for camp in c.buildings.duplicate():
		if camp.type != "bandit_camp":
			continue
		var members: Array = []
		for p in c.people:
			if p.alive and int(p.task_memory.get("camp", -1)) == camp.id:
				members.append(p)
		# recruit about once every 3 days
		if members.size() < MAX_PER_CAMP and sim.rng.randf() < 1.0 / 72.0:
			members.append(_recruit(sim, c, camp))
		# a robbery about once every 6 days per camp, after the first week
		if sim.time.t < 7.0 or sim.rng.randf() > 1.0 / 144.0 * Config.rule("ai_aggression"):
			continue
		var target := _raid_target(sim, camp)
		if target == null:
			continue
		var sent := 0
		target.recent_robbed = 6.0
		for p in members:
			if sent >= 2:
				break
			if int(p.task.get("prio", 0)) <= HumanAI.PRIO_IDLE + 1 and p.health > 60.0:
				if start_rob(sim, p, target):
					sent += 1


static func _raid_target(sim: Sim, camp: Building) -> Colony:
	var best: Colony = null
	var best_d := RAID_RANGE * RAID_RANGE
	for o in sim.colonies:
		# a village that was just robbed is left alone for a while
		if o.bandit or o.collapsed or o.population() < 4 or o.recent_robbed > 0.0:
			continue
		var d := Vector2(camp.center_tile()).distance_squared_to(Vector2(o.home))
		if d < best_d:
			best_d = d
			best = o
	return best


static func start_rob(sim: Sim, p: Human, target: Colony) -> bool:
	var dest := sim.world.walkable_near(target.drop_point(sim.world.center_of(target.home)), 4)
	if dest.x < 0:
		return false
	return HumanAI._set_task(sim, p, "rob", dest, PRIO_ROB, {"civ": target.civ_id, "label": "Sneaking up on the %s" % target.name})


## Arrived at the village stores: grab what they can carry and run.
static func do_rob(sim: Sim, p: Human) -> void:
	var target := sim.civ(int(p.task["civ"]))
	var got := PackedStringArray()
	if target != null and not target.collapsed:
		var cash := floorf(minf(target.money * 0.15, sim.rng.randf_range(15.0, 40.0)))
		if cash > 0.0:
			target.money -= cash
			p.task_memory["loot_money"] = float(p.task_memory.get("loot_money", 0.0)) + cash
			got.append("%d %s" % [int(cash), Defs.MONEY_NAME])
		# the two most valuable goods in store, up to 12 of each
		var cands: Array = []
		for item in target.stock.keys():
			if target.count(item) >= 3.0 and Defs.BASE_PRICE.has(item):
				cands.append([float(Defs.BASE_PRICE[item]) * minf(target.count(item), 12.0), item])
		cands.sort_custom(func(a, b): return a[0] > b[0])
		for e in cands.slice(0, 2):
			var n := int(target.take(e[1], 12.0))
			if n > 0:
				p.add_carry(e[1], n)
				got.append("%d %s" % [n, Defs.item_name(e[1])])
		if not got.is_empty():
			target.recent_robbed = 6.0
			if target.civ_id == 0:
				# one big announcement per raid; the second robber's haul goes to the feed
				var fresh := sim.time.t - target.rob_msg_t > 0.5
				target.rob_msg_t = sim.time.t
				sim.emit_signal("event", "Bandits raided your stores and got away with %s!" % ", ".join(got), "major_bad" if fresh else "bad")
	var camp := camp_of(sim, p)
	HumanAI._done(sim, p)
	if camp != null:
		HumanAI._set_task(sim, p, "bandit_home", _camp_spot(sim, camp), PRIO_ROB, {"label": "Running back to camp with loot"})


static func do_home(sim: Sim, p: Human) -> void:
	var c := sim.col_of(p)
	for k in p.carrying.keys():
		c.add(str(k), float(p.carrying[k]))
	p.carrying = {}
	c.money += float(p.task_memory.get("loot_money", 0.0))
	p.task_memory["loot_money"] = 0.0
	HumanAI._done(sim, p)


## A camp was destroyed: whoever did it recovers part of the stash; its bandits join another camp.
static func camp_destroyed(sim: Sim, camp: Building, by_civ: int) -> void:
	var c := sim.civ(camp.civ_id)
	var camps := 0
	for b in c.buildings:
		if b.type == "bandit_camp" and b != camp:
			camps += 1
	var share := 1.0 / float(camps + 1)
	var winner := sim.civ(by_civ) if by_civ >= 0 else null
	var got := PackedStringArray()
	if winner != null and not winner.bandit:
		var cash := floorf(c.money * share)
		c.money -= cash
		winner.money += cash
		if cash > 0.0:
			got.append("%d %s" % [int(cash), Defs.MONEY_NAME])
		for item in c.stock.keys():
			var n := floorf(c.count(item) * share)
			if n > 0.0:
				winner.add(item, c.take(item, n))
				got.append("%d %s" % [int(n), Defs.item_name(item)])
	if by_civ == 0:
		sim.emit_signal("event", "Your soldiers destroyed a bandit camp!%s" % ((" You recovered " + ", ".join(got) + ".") if not got.is_empty() else ""), "major_good")
