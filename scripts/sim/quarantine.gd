class_name Quarantine
extends RefCounted
## When someone is badly sick with something that spreads, the tribe worries for everyone else.
## Your tribe asks you whether to send the sick person away; AI tribes decide for themselves.
## Sending someone away stops the spread but saddens the tribe for a while.

const MIN_SPREAD := 0.015     # only illnesses that pass from person to person
const MIN_RISK := 0.12        # ...and only when the sick person is in real danger


## Whether this person is sick enough, and catching enough, that the tribe would want them gone.
static func dangerous(sim: Sim, p: Human) -> bool:
	if not p.is_sick():
		return false
	var ill: Dictionary = Defs.ILLNESS[p.illness["type"]]
	if float(ill["spread"]) < MIN_SPREAD:
		return false
	return Survival.death_risk(sim, p) >= MIN_RISK or (bool(ill["severe"]) and p.health < 45.0)


## Every game hour for every tribe.
static func hourly(sim: Sim, c: Colony) -> void:
	if c.bandit or c.population() < 3:
		return
	for p in c.living():
		if c.exile_asked.has(p.id) or not dangerous(sim, p):
			continue
		if sim.rng.randf() > 0.25:
			continue
		c.exile_asked[p.id] = true
		var ill := str(Defs.ILLNESS[p.illness["type"]]["name"])
		if c.is_player:
			sim.exile_asks.append({"pid": p.id})
			sim.emit_signal("event", "Your people fear %s's %s will spread. They ask whether %s should be sent away." % [p.name, ill.to_lower(), "he" if p.gender == "M" else "she"], "major")
			if sim.debug_log:
				answer(sim, sim.exile_asks[0], true)
		elif sim.rng.randf() < 0.5:
			exile(sim, c, p)
		return


## The player's answer.
static func answer(sim: Sim, ask: Dictionary, yes: bool) -> void:
	sim.exile_asks.erase(ask)
	var p := sim.person(int(ask["pid"]))
	if p == null or not p.alive:
		return
	var c := sim.col_of(p)
	if yes:
		exile(sim, c, p)
	else:
		sim.emit_signal("event", "%s stays with the tribe. Keep healers close and hope it doesn't spread." % p.name, "info")


## Sends a person away for good: they leave the tribe and its lands.
static func exile(sim: Sim, c: Colony, p: Human) -> void:
	var ill := str(Defs.ILLNESS[p.illness["type"]]["name"]).to_lower() if p.is_sick() else "sickness"
	sim.remove_person(p, "sent away (%s)" % ill)
	c.exile_sorrow = 10.0
	if c.is_player:
		sim.emit_signal("event", "%s was sent away from the tribe so the %s won't spread. The tribe is saddened." % [p.name, ill], "warn")
	elif sim.have_met(0, c.civ_id):
		sim.emit_signal("event", "The %s drove out one of their own, sick with %s." % [c.name, ill], "info")
