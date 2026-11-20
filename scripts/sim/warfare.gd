class_name Warfare
extends RefCounted
## War rules:
##  - A killing between tribes can start a war (Game Rules: 60% for anyone, 90% for a leader).
##  - Tribes at war send an attack party against each other once a month, in every age; tribes
##    without soldiers arm a militia of able adults.
##  - Leaders stay inside their own borders (and run from fights).
##  - Killing an enemy leader, or destroying their Capitol, during a war conquers the whole tribe:
##    the winner takes its people, goods, Talents, land and buildings.
##  - Armor (researched, one kind per age) protects soldiers and war-party fighters.
##  - Long wars wear a tribe down (war weariness hurts mood); victories lift it.

const ARMOR_TECHS := ["hide_armor", "wicker_shields", "bronze_scale", "iron_mail"]
const ARMOR_NAMES := ["Hide armor", "Wicker shields & leather", "Bronze scale armor", "Iron mail"]


## 0 = none, 1..4 = the best armor the tribe has researched.
static func armor_tier(c: Colony) -> int:
	var t := 0
	for k in ARMOR_TECHS.size():
		if c.researched.has(ARMOR_TECHS[k]):
			t = k + 1
	return t


## Fighters wear the tribe's armor: soldiers, and anyone out with a war party.
static func is_fighter(p: Human) -> bool:
	return p.job == "soldier" or p.drafted or str(p.task.get("type", "")) == "raid"


static func armor_cut(sim: Sim, p: Human) -> float:
	if not is_fighter(p):
		return 0.0
	return minf(0.5, sim.col_of(p).bonus("armor"))


# ---------------------------------------------------------------- killings
## Someone of `killer_civ` killed `victim`. `was_leader` and `was_at_war` are taken before the death.
static func on_kill(sim: Sim, killer_civ: int, victim_civ: int, victim_name: String, was_leader: bool, was_at_war: bool) -> void:
	if killer_civ < 0 or killer_civ == victim_civ:
		return
	var kc := sim.civ(killer_civ)
	var vc := sim.civ(victim_civ)
	if kc == null or vc == null or kc.bandit or vc.bandit or vc.collapsed:
		return
	if was_leader and was_at_war:
		conquer(sim, kc, vc, "%s, their leader, fell" % victim_name)
		return
	if sim.at_war(killer_civ, victim_civ):
		return
	var ch := Config.rule("leader_kill_war_chance") if was_leader else Config.rule("kill_war_chance")
	if sim.rng.randf() < ch:
		var why := "their leader %s" % victim_name if was_leader else victim_name
		if victim_civ == 0:
			sim.emit_signal("event", "The %s killed %s! Your people cry out for revenge — it's war." % [kc.name, why], "major_bad")
		elif killer_civ == 0:
			sim.emit_signal("event", "Your people killed %s of the %s. They have declared war on you!" % [why, vc.name], "major_bad")
		sim.declare_war(victim_civ, killer_civ, true)
	elif victim_civ == 0 or killer_civ == 0:
		var other := kc if victim_civ == 0 else vc
		sim.emit_signal("event", "The killing of %s brought anger but no war with the %s — this time." % [victim_name, other.name], "warn")


## A building was destroyed by `attacker_civ`. Losing the Capitol in a war means defeat.
static func on_building_destroyed(sim: Sim, b: Building, attacker_civ: int) -> void:
	if b.type != "capitol" or attacker_civ < 0 or attacker_civ == b.civ_id:
		return
	var vc := sim.civ(b.civ_id)
	var kc := sim.civ(attacker_civ)
	if vc == null or kc == null or vc.collapsed or kc.bandit or not sim.at_war(attacker_civ, b.civ_id):
		return
	conquer(sim, kc, vc, "their Capitol was burned")


## The winner takes everything the loser has: people, goods, Talents, land and buildings.
static func conquer(sim: Sim, winner: Colony, loser: Colony, why: String) -> void:
	if loser.collapsed or winner.collapsed or winner == loser:
		return
	var people: Array = loser.living().filter(func(q): return not q.at_sea())
	var n_people := people.size()
	var talents := int(loser.money)
	winner.money += loser.money
	loser.money = 0.0
	for item in loser.stock.keys():
		var v := loser.count(item)
		if v > 0.0:
			winner.add(item, loser.take(item, v))
	var lands := 0
	for st in sim.states.owned_by(loser.civ_id):
		sim.states.set_owner(st, winner.civ_id)
		lands += 1
	for b in loser.buildings.duplicate():
		loser.buildings.erase(b)
		b.civ_id = winner.civ_id
		b.occupants.clear()
		winner.buildings.append(b)
	for i in sim.road_tiles.keys():
		if int(sim.road_tiles[i]) == loser.civ_id:
			sim.road_tiles[i] = winner.civ_id
	sim.road_version += 1
	for q in people:
		q.weapon = ""
		if q.job == "soldier":
			q.job = "laborer"
	Politics.move_people(sim, people, loser, winner)
	loser.collapsed = true
	loser.leader_id = -1
	for k in sim.wars.keys():
		var parts: PackedStringArray = str(k).split(":")
		if parts[0] == str(loser.civ_id) or parts[1] == str(loser.civ_id):
			sim.wars.erase(k)
	winner.approval = minf(100.0, winner.approval + 10.0)
	winner.victories += 1
	winner.invalidate_bonus()
	sim.emit_signal("buildings_changed")
	var text := "The %s conquered the %s (%s): %d people, %d %s and %d lands now belong to them." % [
		winner.name, loser.name, why, n_people, talents, Defs.MONEY_NAME, lands]
	if loser.civ_id == 0:
		sim.emit_signal("event", "Your tribe has been conquered by the %s — %s. Your people now live under their rule." % [winner.name, why], "major_bad")
		sim.emit_signal("event", "Your tribe has perished. Its story ends here.", "bad")
	elif winner.civ_id == 0:
		sim.emit_signal("event", "VICTORY! You conquered the %s (%s). Their %d people, %d %s, goods and %d lands are yours!" % [
			loser.name, why, n_people, talents, Defs.MONEY_NAME, lands], "major_good")
	elif sim.have_met(0, winner.civ_id) or sim.have_met(0, loser.civ_id):
		sim.emit_signal("event", text, "major")
	else:
		sim.chronicle(text, "major")


# ---------------------------------------------------------------- monthly war parties
## Called every day: on the first day of each calendar month, every tribe at war sends a party.
static func daily(sim: Sim) -> void:
	var month := sim.time.year() * 12 + sim.time.month()
	if month == sim.war_month:
		return
	sim.war_month = month
	if Config.rule("war_parties") < 0.5:
		return
	for k in sim.wars.keys():
		var parts: PackedStringArray = str(k).split(":")
		var a := sim.civ(int(parts[0]))
		var b := sim.civ(int(parts[1]))
		if a == null or b == null or a.collapsed or b.collapsed:
			continue
		send_party(sim, a, b)
		send_party(sim, b, a)


## Picks the attack party: armed soldiers first; a tribe without enough soldiers arms a militia
## of healthy adults (never the leader, never mothers-to-be).
static func party_for(sim: Sim, c: Colony) -> Array:
	var out: Array = []
	for q in c.soldiers():
		if q.health > 50.0 and not q.at_sea() and q.id != c.leader_id:
			out.append(q)
	var keep_home := 1 if out.size() >= 3 else 0
	out = out.slice(0, maxi(0, out.size() - keep_home))
	if out.size() < 2:
		var militia: Array = []
		for q in c.living():
			if out.has(q) or q.id == c.leader_id or not q.is_adult() or q.health < 60.0 or q.at_sea():
				continue
			if q.pregnant_days >= 0.0 or q.age_years() > 55.0 or q.job in ["healer", "researcher"]:
				continue
			militia.append(q)
		militia.sort_custom(func(x, y): return (1 if x.gender == "M" else 0) > (1 if y.gender == "M" else 0))
		var want := clampi(c.adults_count() / 4, 2, 6) - out.size()
		for q in militia.slice(0, maxi(0, want)):
			out.append(q)
	return out


static func send_party(sim: Sim, c: Colony, target: Colony) -> int:
	var party := party_for(sim, c)
	if party.size() < 2:
		return 0
	var sent := 0
	for q in party:
		if HumanAI.order_raid(sim, q, target.civ_id, HumanAI.PRIO_RAID):
			sent += 1
	if sent == 0:
		return 0
	c.war_parties_sent += 1
	if c.civ_id == 0:
		sim.emit_signal("event", "A war party of %d sets out against the %s!" % [sent, target.name], "major")
	elif target.civ_id == 0:
		sim.emit_signal("event", "A war party of %d %s warriors is marching on your village!" % [sent, c.name], "major_bad")
	return sent


# ---------------------------------------------------------------- weariness
## Months a tribe has been at war (its longest current war).
static func war_months(sim: Sim, c: Colony) -> float:
	var longest := 0.0
	for k in sim.wars.keys():
		var parts: PackedStringArray = str(k).split(":")
		if parts[0] == str(c.civ_id) or parts[1] == str(c.civ_id):
			var since := float(sim.wars[k].get("since", sim.time.day()))
			longest = maxf(longest, (sim.time.t - since) * sim.time.scale / 30.0)
	return longest
