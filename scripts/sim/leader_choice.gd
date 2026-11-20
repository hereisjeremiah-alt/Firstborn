class_name LeaderChoice
extends RefCounted
## When the player leaves a question unanswered for 30 seconds of play, the tribe's leader
## decides it for them, sensibly: friends get passage, fair trades are taken, strong bullies
## are paid off, and the badly sick are sent away when the tribe is big enough to be at risk.

const WAIT := 30.0


static func who(sim: Sim) -> String:
	var ld := Elections.leader(sim, sim.colony)
	if ld == null:
		return "The elders"
	return "%s %s" % [Elections.title_for(sim.colony), ld.name]


## Border passage for another tribe.
static func passage(sim: Sim, cid: int) -> bool:
	return sim.relation(0, cid) >= -10.0 and not sim.at_war(0, cid)


## Unhappy people of another tribe asking to join.
static func defectors(sim: Sim, ask: Dictionary) -> bool:
	return sim.colony.food_days() >= 3.0 or ask.get("people", []).size() <= 2


## A badly sick person: send away when the risk to the rest is real.
static func exile(sim: Sim, ask: Dictionary) -> bool:
	var p := sim.person(int(ask["pid"]))
	if p == null or not p.alive or not p.is_sick():
		return false
	return Survival.death_risk(sim, p) >= 0.25 or sim.colony.population() >= 8


## An envoy's offer: "accept", "decline" or "counter".
static func deal(sim: Sim, o: Dictionary) -> String:
	var from := sim.civ(int(o["from"]))
	var me := sim.colony
	match str(o["type"]):
		"trade":
			var give := _value(o.get("give", {}), 0)
			var want := _value(o.get("want", {}), int(o.get("talents", 0)))
			if Deals._cant_afford(sim, me, o) != "":
				return "decline"
			if give >= want * 0.95:
				return "accept"
			return "counter" if give >= want * 0.7 else "decline"
		"alliance":
			return "accept" if sim.relation(0, from.civ_id) >= 0.0 else "decline"
		"tribute", "land":
			var ratio := sim.military_strength(from) / maxf(1.0, sim.military_strength(me))
			if ratio >= 1.3:
				if Deals._cant_afford(sim, me, o) == "":
					return "accept"
				return "counter"
			return "counter" if ratio >= 0.9 else "decline"
	return "decline"


static func _value(goods: Dictionary, talents: int) -> float:
	var v := float(talents)
	for k in goods.keys():
		v += float(goods[k]) * float(Defs.BASE_PRICE.get(k, 1.0))
	return v


static func deal_word(how: String) -> String:
	return {"accept": "accepted", "decline": "turned down", "counter": "made a counter-offer to"}.get(how, how)
