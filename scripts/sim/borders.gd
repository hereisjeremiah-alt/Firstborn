class_name Borders
extends RefCounted
## Right of passage between tribes.
##  - A tribe's Billies may only enter another tribe's states with permission (or at war).
##  - AI tribes ask each other; a tribe that wants to cross the player's land asks the player.
##  - A Billy caught on foreign land without permission may start a war:
##    30% in the Caveman Age, +10% for every age after that.

const ACCESS_YEARS := 10.0     # calendar years a grant of passage lasts
const DENY_YEARS := 3.0        # calendar years before a refused tribe asks again
const SEE_PEOPLE := 10.0       # tiles: the owners notice trespassers this close to one of them
const SEE_BUILDING := 8.0      # tiles: ... or this close to one of their buildings
const ROLL_COOLDOWN := 1.0     # sim days between incident rolls for the same pair of tribes


static func _k(a: int, b: int) -> String:
	return "%d>%d" % [a, b]


## True when `a`'s people may walk on `b`'s land.
static func has_access(sim: Sim, a: int, b: int) -> bool:
	if a == b or b < 0 or sim.at_war(a, b) or Deals.allied(sim, a, b):
		return true
	return float(sim.access.get(_k(a, b), -1.0)) > sim.time.cal_years()


static func access_years_left(sim: Sim, a: int, b: int) -> float:
	return maxf(0.0, float(sim.access.get(_k(a, b), -1.0)) - sim.time.cal_years())


## Owner of the land at `tile` that `civ_id` is not allowed onto, or -1.
static func forbidden_owner(sim: Sim, civ_id: int, tile: Vector2i) -> int:
	var o := sim.states.owner_at(tile)
	if o < 0 or o == civ_id or has_access(sim, civ_id, o):
		return -1
	return o


## Checks a planned path; returns the first owner whose land it would cross without permission.
## Land of the state the walker starts in is ignored (they may always walk back out).
static func path_blocker(sim: Sim, civ_id: int, from: Vector2i, path: Array) -> int:
	var start_state := sim.states.at(from)
	var n := path.size()
	var i := 0
	while i < n:
		var t: Vector2i = path[i]
		if sim.states.at(t) != start_state:
			var o := forbidden_owner(sim, civ_id, t)
			if o >= 0:
				return o
		i += 2 if i < n - 2 else 1
	return -1


## Tribe `a` asks tribe `b` for passage. AI tribes answer at once; the player is asked in a dialog.
static func request(sim: Sim, a: int, b: int, by_player := false) -> void:
	if has_access(sim, a, b):
		return
	var k := _k(a, b)
	var now := sim.time.cal_years()
	if float(sim.access_denied.get(k, -1.0)) > now and not by_player:
		return
	if Deals.wait_left(sim, a, b, "passage") > 0.0:
		if by_player:
			sim.emit_signal("event", "You must wait %s before asking the %s for passage again." % [Deals.wait_text(sim, a, b, "passage"), sim.civ(b).name], "warn")
		return
	Deals.start_wait(sim, a, b, "passage")
	var ca := sim.civ(a)
	var cb := sim.civ(b)
	if ca == null or cb == null or ca.collapsed or cb.collapsed:
		return
	if b == 0:
		# an AI tribe asks the player
		if not sim.access_asks.has(a):
			sim.access_asks.append(a)
			sim.access_denied[k] = now + 0.5     # don't re-ask while the question is open
			sim.emit_signal("event", "The %s ask permission for their Billies to cross your land." % ca.name, "info")
			if sim.debug_log:
				answer(sim, a, true)
		return
	var ok := sim.rng.randf() < grant_chance(sim, a, b)
	if ok:
		grant(sim, a, b)
	else:
		sim.access_denied[k] = now + DENY_YEARS
	if a == 0:
		if ok:
			sim.emit_signal("event", "The %s allow your Billies to cross their land for %d years." % [cb.name, int(ACCESS_YEARS)], "good")
		else:
			sim.emit_signal("event", "The %s refused your Billies passage through their land." % cb.name, "warn")


## Chance an AI tribe `b` lets `a` through.
static func grant_chance(sim: Sim, a: int, b: int) -> float:
	var rel := sim.relation(a, b)
	var ch := 0.55 + rel / 100.0 * 0.4
	var cb := sim.civ(b)
	if cb.government != "" and Defs.GOVERNMENTS[cb.government]["ai"] == "warlike":
		ch -= 0.15
	ch -= (Config.rule("ai_aggression") - 1.0) * 0.1
	return clampf(ch, 0.05, 0.95)


static func grant(sim: Sim, a: int, b: int) -> void:
	sim.access[_k(a, b)] = sim.time.cal_years() + ACCESS_YEARS
	sim.access_denied.erase(_k(a, b))
	var key := sim._key(a, b)
	sim.relations[key] = clampf(sim.relation(a, b) + 3.0, -100.0, 100.0)


## The player's answer to tribe `a` asking for passage.
static func answer(sim: Sim, a: int, yes: bool) -> void:
	sim.access_asks.erase(a)
	var ca := sim.civ(a)
	if yes:
		grant(sim, a, 0)
		sim.emit_signal("event", "You allowed the %s to cross your land for %d years." % [ca.name, int(ACCESS_YEARS)], "info")
	else:
		sim.access_denied[_k(a, 0)] = sim.time.cal_years() + DENY_YEARS
		var key := sim._key(a, 0)
		sim.relations[key] = clampf(sim.relation(a, 0) - 5.0, -100.0, 100.0)
		sim.emit_signal("event", "You refused the %s passage. Their Billies will keep out of your land." % ca.name, "info")


static func revoke(sim: Sim, a: int, b: int) -> void:
	sim.access.erase(_k(a, b))


## Chance a trespass incident starts a war: 30% plus 10% per age (the higher age of the two tribes).
static func war_chance(sim: Sim, a: int, b: int) -> float:
	var era := maxi(sim.civ(a).era_i, sim.civ(b).era_i)
	return clampf(Config.rule("trespass_war") + 0.1 * era, 0.0, 1.0)


## Hourly: finds Billies standing on land they have no right to be on.
static func check_trespass(sim: Sim) -> void:
	for p in sim.people_all:
		if not p.alive or p.at_sea():
			continue
		var tile := sim.world.tile_of(p.pos)
		var owner := forbidden_owner(sim, p.civ_id, tile)
		if owner < 0:
			p.task_memory.erase("tres")
			continue
		var s := sim.states.at(tile)
		if int(p.task_memory.get("tres", -1)) == s:
			continue          # this crossing has already been dealt with
		var oc := sim.civ(owner)
		if not _seen(sim, p, oc):
			continue
		p.task_memory["tres"] = s
		_incident(sim, p, oc, s)


static func _seen(sim: Sim, p: Human, oc: Colony) -> bool:
	var r2 := pow(SEE_PEOPLE * Defs.TILE, 2)
	for q in oc.people:
		if q.alive and not q.at_sea() and q.pos.distance_squared_to(p.pos) < r2:
			return true
	var t := sim.world.tile_of(p.pos)
	for b in oc.buildings:
		if Vector2(b.center_tile()).distance_to(Vector2(t)) < SEE_BUILDING:
			return true
	return false


static func _incident(sim: Sim, p: Human, oc: Colony, s: int) -> void:
	var a := p.civ_id
	var b := oc.civ_id
	var ca := sim.civ(a)
	var key := sim._key(a, b)
	sim.contacts[key] = true
	sim.relations[key] = clampf(sim.relation(a, b) - 4.0, -100.0, 100.0)
	var place: String = sim.states.names[s]
	if b == 0:
		# on the player's land: the player decides what to do about it
		sim.emit_signal("event", "%s of the %s was caught trespassing in %s without your permission. You may declare war on them from their flag." % [p.name, ca.name, place], "warn")
		return
	var ck := _k(a, b)
	if sim.time.t < float(sim.trespass_cd.get(ck, -1.0)):
		return
	sim.trespass_cd[ck] = sim.time.t + ROLL_COOLDOWN
	var ch := war_chance(sim, a, b)
	if sim.rng.randf() < ch:
		var who := "Your Billy %s" % p.name if a == 0 else "%s of the %s" % [p.name, ca.name]
		if a == 0 or sim.have_met(0, b):
			sim.emit_signal("event", "%s was caught trespassing in %s!" % [who, place], "bad")
		sim.declare_war(b, a, true)
	elif a == 0:
		sim.emit_signal("event", "The %s caught your Billy %s trespassing in %s. They let it go this time (%d%% chance of war)." % [oc.name, p.name, place, roundi(ch * 100.0)], "warn")


# ---------------------------------------------------------------- save
static func to_dict(sim: Sim) -> Dictionary:
	return {"access": sim.access.duplicate(), "denied": sim.access_denied.duplicate(), "asks": sim.access_asks.duplicate()}


static func from_dict(sim: Sim, d: Dictionary) -> void:
	sim.access = d.get("access", {})
	sim.access_denied = d.get("denied", {})
	sim.access_asks.clear()
	for a in d.get("asks", []):
		sim.access_asks.append(int(a))
