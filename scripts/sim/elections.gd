class_name Elections
extends RefCounted
## Every tribe elects its leader.
##  - Until the Bronze Age the adults choose a Chief. Elders and the skilled are favoured and
##    a Chief may serve any number of terms.
##  - From the Bronze Age on the tribe elects a President from up to three nominees,
##    for at most two terms in a row.
## Elections are held every `election_years` calendar years, when the leader dies, and when
## the tribe enters the Bronze Age. The leader's best trade gives the whole tribe a work bonus.

const MIN_VOTER_AGE := 16.0
const MIN_CANDIDATE_AGE := 18.0
const PRESIDENT_TERMS := 2


static func title_for(c: Colony) -> String:
	return "President" if c.era_i >= 2 else "Chief"


static func leader(sim: Sim, c: Colony) -> Human:
	if c.leader_id < 0:
		return null
	var p := sim.person(c.leader_id)
	if p == null or not p.alive or p.civ_id != c.civ_id:
		return null
	return p


## Hourly check for each tribe.
static func update(sim: Sim, c: Colony) -> void:
	if c.collapsed or c.population() == 0:
		return
	var now := sim.time.cal_years()
	var cur := leader(sim, c)
	if c.unrest_until > 0.0 and now >= c.unrest_until:
		c.unrest_until = -1.0
		c.invalidate_bonus()
		if c.civ_id == 0:
			sim.emit_signal("event", "The unrest over the stolen election has died down.", "good")
	var why := ""
	if c.leader_id >= 0 and cur == null:
		var old := sim.person(c.leader_id)
		why = "after the death of %s %s" % [c.leader_title, old.name] if old != null else "after losing their leader"
	elif c.leader_title != "" and c.leader_title != title_for(c):
		why = "for the first President"
	elif c.leader_id < 0:
		why = "for the first %s" % title_for(c)
	elif now >= c.next_election:
		why = ""
	else:
		return
	hold(sim, c, why)


## Runs an election now.
static func hold(sim: Sim, c: Colony, why := "") -> void:
	var now := sim.time.cal_years()
	var title := title_for(c)
	var voters: Array = []
	for p in c.living():
		if p.age_years() >= MIN_VOTER_AGE and not p.at_sea():
			voters.append(p)
	if voters.is_empty():
		# only children left: the eldest leads until there are voters
		var eldest: Human = null
		for p in c.living():
			if eldest == null or p.age_years() > eldest.age_years():
				eldest = p
		_install(sim, c, eldest, title, now, [], "")
		return
	var cands := _nominees(sim, c, title)
	if cands.is_empty():
		cands = [voters[0]]
	# the player's backed candidate is always on the ballot (if eligible)
	if c.civ_id == 0:
		var bk := sim.person(c.backed_id)
		if bk != null and bk.alive and bk.civ_id == c.civ_id and not cands.has(bk) and eligible(c, bk, title):
			cands.append(bk)
	var tally := {}
	for cand in cands:
		tally[cand.id] = 0
	for v in voters:
		var best: Human = null
		var best_s := -1e9
		for cand in cands:
			var sc := _appeal(sim, c, cand, title) + _kin_pull(v, cand) + sim.rng.randf_range(0.0, 6.0) + support(c, cand.id)
			if v == cand:
				sc += 4.0
			if sc > best_s:
				best_s = sc
				best = cand
		tally[best.id] = int(tally[best.id]) + 1
	var results: Array = []
	for cand in cands:
		results.append([cand.id, cand.name, int(tally[cand.id])])
	results.sort_custom(func(x, y): return int(x[2]) > int(y[2]))
	var winner := sim.person(int(results[0][0]))
	# a rigged count: the backed candidate "wins" — unless someone notices
	if c.civ_id == 0 and c.rigged:
		var bk := sim.person(c.backed_id)
		if bk != null and cands.has(bk):
			var real_votes := int(tally[bk.id])
			var fake := maxi(real_votes, int(voters.size() * 0.6) + 1)
			for r in results:
				if int(r[0]) == bk.id:
					r[2] = fake
			results.sort_custom(func(x, y): return int(x[2]) > int(y[2]))
			winner = bk
			if sim.rng.randf() < rig_catch_chance(c, voters.size()):
				c.unrest_until = now + 3.0
				c.invalidate_bonus()
				sim.emit_signal("event", "The rigged count was discovered! %s only had %d real votes. The tribe is in unrest for 3 years: work 15%% slower and fewer children." % [bk.name, real_votes], "bad")
			else:
				sim.emit_signal("event", "Nobody noticed the rigged count.", "info")
	if c.civ_id == 0:
		c.campaign.clear()
		c.rigged = false
		c.backed_id = -1
	_install(sim, c, winner, title, now, results, why)


static func _install(sim: Sim, c: Colony, winner: Human, title: String, now: float, results: Array, why: String) -> void:
	if winner == null:
		return
	var same := winner.id == c.leader_id and c.leader_title == title
	c.leader_terms = c.leader_terms + 1 if same else 1
	c.leader_id = winner.id
	c.leader_title = title
	c.elections_held += 1
	c.next_election = now + Config.rule("election_years")
	c.leader_fx = _fx_for(winner, title)
	c.invalidate_bonus()
	var total := 0
	for r in results:
		total += int(r[2])
	c.last_election = {"year": sim.time.year(), "title": title, "results": results, "voters": total}
	var votes := int(results[0][2]) if not results.is_empty() else 0
	var trade := _best_job(winner)
	var tail := ""
	if trade != "":
		tail = " %ss work 10%% faster under them." % Defs.JOB_NAMES.get(trade, trade)
	var who := "your tribe" if c.civ_id == 0 else "the %s" % c.name
	var reason := ""
	if why.begins_with("after"):
		reason = " " + why
	var role := "first %s" % title if why.begins_with("for the") else title
	var count := " with %d of %d votes" % [votes, total] if results.size() > 1 else ""
	var text := ""
	if same:
		text = "%s was re-elected %s of %s%s.%s" % [winner.name, title, who, count, tail]
	elif title == "Chief":
		text = "%s was chosen as %s of %s%s%s.%s" % [winner.name, role, who, reason, count, tail]
	else:
		text = "%s was elected %s of %s%s%s.%s" % [winner.name, role, who, reason, count, tail]
	text = text[0].to_upper() + text.substr(1)
	if c.civ_id == 0:
		sim.emit_signal("event", text, "good")
	elif sim.have_met(0, c.civ_id) and title == "President":
		sim.emit_signal("event", "%s is the new President of the %s." % [winner.name, c.name], "info")


# ---------------------------------------------------------------- the player's influence
## Extra pull a candidate has with every voter from the player's backing and campaigning.
static func support(c: Colony, pid: int) -> float:
	var v := float(c.campaign.get(pid, 0.0))
	if c.backed_id == pid:
		v += 2.0
	return v


static func eligible(c: Colony, p: Human, title: String) -> bool:
	if p.age_years() < MIN_CANDIDATE_AGE or p.at_sea():
		return false
	return not (title == "President" and p.id == c.leader_id and c.leader_title == "President" and c.leader_terms >= PRESIDENT_TERMS)


## Who is likely to stand at the next election (no dice rolled), for the Colony panel.
static func preview(sim: Sim, c: Colony) -> Array:
	var title := title_for(c)
	var pool: Array = []
	for p in c.living():
		if eligible(c, p, title):
			pool.append([_appeal(sim, c, p, title), p])
	pool.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var out: Array = []
	for e in pool.slice(0, 4 if title == "Chief" else 3):
		out.append(e[1])
	var bk := sim.person(c.backed_id)
	if bk != null and bk.alive and not out.has(bk) and eligible(c, bk, title):
		out.append(bk)
	return out


## Rough share of the vote each candidate would get now (for the panel).
static func forecast(sim: Sim, c: Colony) -> Dictionary:
	var cands := preview(sim, c)
	var out := {}
	if cands.is_empty():
		return out
	for cand in cands:
		out[cand.id] = 0.0
	var voters := 0
	for v in c.living():
		if v.age_years() < MIN_VOTER_AGE:
			continue
		voters += 1
		var best: Human = null
		var bs := -1e9
		for cand in cands:
			var sc := _appeal(sim, c, cand, title_for(c)) + _kin_pull(v, cand) + support(c, cand.id) + 3.0 + (4.0 if v == cand else 0.0)
			if sc > bs:
				bs = sc
				best = cand
		out[best.id] = float(out[best.id]) + 1.0
	if voters > 0:
		for k in out.keys():
			out[k] = float(out[k]) / voters
	return out


const CAMPAIGN_COST := 30        # Talents per rally
const GIFT_FOOD := 15            # food handed out per round of gifts


## Spend Talents on a rally for a candidate.
static func campaign_talents(sim: Sim, c: Colony, pid: int) -> String:
	if c.money < CAMPAIGN_COST:
		return "A rally costs %d %s." % [CAMPAIGN_COST, Defs.MONEY_NAME]
	c.money -= CAMPAIGN_COST
	c.campaign[pid] = float(c.campaign.get(pid, 0.0)) + 3.0
	c.backed_id = pid
	return ""


## Hand out food to the voters in a candidate's name.
static func campaign_gifts(sim: Sim, c: Colony, pid: int) -> String:
	var have := 0.0
	for f in Defs.EAT_ORDER:
		have += c.count(f)
	if have < GIFT_FOOD:
		return "You need %d food to hand out." % GIFT_FOOD
	var left := float(GIFT_FOOD)
	for f in Defs.EAT_ORDER:
		if left <= 0.0:
			break
		left -= c.take(f, left)
	c.campaign[pid] = float(c.campaign.get(pid, 0.0)) + 2.0
	c.backed_id = pid
	return ""


## Chance a rigged count is found out: bigger tribes and later ages have more watchful eyes.
static func rig_catch_chance(c: Colony, voters: int) -> float:
	return clampf(0.25 + 0.08 * c.era_i + 0.02 * voters, 0.25, 0.85)


## Candidates: everyone of age for a Chief (the top few by standing); for a President, up to
## three nominees, never someone who already served two terms in a row.
static func _nominees(sim: Sim, c: Colony, title: String) -> Array:
	var pool: Array = []
	for p in c.living():
		if p.age_years() < MIN_CANDIDATE_AGE or p.at_sea():
			continue
		if title == "President" and p.id == c.leader_id and c.leader_title == "President" and c.leader_terms >= PRESIDENT_TERMS:
			continue
		pool.append([_appeal(sim, c, p, title) + sim.rng.randf_range(0.0, 3.0), p])
	pool.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var n := 4 if title == "Chief" else 3
	var out: Array = []
	for e in pool.slice(0, n):
		out.append(e[1])
	# a sitting leader who may run again is always on the ballot
	var cur := leader(sim, c)
	if cur != null and not out.has(cur) and cur.age_years() >= MIN_CANDIDATE_AGE:
		if not (title == "President" and c.leader_terms >= PRESIDENT_TERMS):
			out.append(cur)
	return out


## How attractive someone is as a leader.
static func _appeal(sim: Sim, c: Colony, p: Human, title: String) -> float:
	var sk := 0.0
	for k in p.skills.keys():
		sk += float(p.skills[k])
	var a := p.age_years()
	var s := minf(sk, 40.0) * 0.4 + p.health * 0.03 + p.children.size() * 0.8
	if title == "Chief":
		s += clampf(a - 20.0, 0.0, 40.0) * 0.2         # the tribe trusts its elders
	else:
		s += clampf(a - 25.0, 0.0, 25.0) * 0.12 - maxf(0.0, a - 65.0) * 0.3
		if p.job in ["trader", "researcher", "healer"]:
			s += 2.0
	if p.is_sick():
		s -= 4.0
	if p.id == c.leader_id:
		s += 2.5                                        # incumbents are known
	return s


## Family and partners stick together at the vote.
static func _kin_pull(v: Human, cand: Human) -> float:
	if v.partner_id == cand.id:
		return 8.0
	if v.mother_id == cand.id or v.father_id == cand.id or cand.mother_id == v.id or cand.father_id == v.id:
		return 6.0
	if (v.mother_id != -1 and v.mother_id == cand.mother_id) or (v.father_id != -1 and v.father_id == cand.father_id):
		return 4.0
	if v.job == cand.job:
		return 1.5
	return 0.0


static func _best_job(p: Human) -> String:
	var best := ""
	var bv := 0.5
	for k in p.skills.keys():
		if Defs.JOB_NAMES.has(k) and float(p.skills[k]) > bv:
			bv = float(p.skills[k])
			best = k
	return best


## A Chief lifts the tribe's work in their own trade by 10%; a President by 10% plus 4% for all work.
static func _fx_for(p: Human, title: String) -> Dictionary:
	var fx := {}
	var j := _best_job(p)
	if j != "":
		fx["work_" + j] = 0.10
	if title == "President":
		fx["work_all"] = 0.04
	return fx
