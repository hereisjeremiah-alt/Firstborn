class_name Names
extends RefCounted
## Procedural names for people, tribes and ships. Every race has its own sound, names are built
## from syllables (thousands of combinations), and a tribe never reuses a name that is already
## taken, so new games no longer show the same few names over and over.

# sound styles; race i uses style i % STYLES.size()
const STYLES := [
	{   # earthy, short (Humans)
		"on": ["b", "d", "g", "k", "t", "r", "m", "n", "h", "s", "v", "br", "dr", "gr", "kr", "th", "sk", "st", "tor", "har", "ul"],
		"vo": ["a", "e", "i", "o", "u", "a", "o", "ai", "ei"],
		"co": ["", "", "n", "r", "k", "g", "m", "l", "rn", "sk", "th", "nd"],
		"m_end": ["", "o", "ek", "an", "ur", "ar", "ok"], "f_end": ["a", "ia", "e", "ra", "ka", "na", "elle", "ya"]},
	{   # harsh, stony (Ashborn)
		"on": ["k", "kh", "g", "gr", "z", "zh", "dr", "x", "t", "r", "v", "sk", "rh"],
		"vo": ["a", "o", "u", "y", "ae", "oa"],
		"co": ["", "k", "z", "x", "rk", "th", "g", "sh", "l"],
		"m_end": ["", "ok", "ax", "uz", "or"], "f_end": ["a", "ya", "ess", "ka", "zha"]},
	{   # flowing, leafy (Verdani)
		"on": ["l", "s", "f", "v", "th", "el", "ae", "n", "m", "sy", "w", "il", "y"],
		"vo": ["a", "e", "i", "ia", "ae", "ei", "y", "io"],
		"co": ["", "", "l", "n", "s", "th", "ll", "r", "wyn"],
		"m_end": ["", "ion", "or", "el", "an"], "f_end": ["a", "ia", "ielle", "wen", "ine", "ra"]},
	{   # watery (Azurai)
		"on": ["m", "n", "q", "w", "sh", "ch", "l", "r", "p", "h", "ny", "aq", "o"],
		"vo": ["a", "o", "u", "ua", "oa", "i", "ai", "ui"],
		"co": ["", "", "n", "m", "l", "sh", "q", "h"],
		"m_end": ["", "u", "ano", "ik", "aq"], "f_end": ["a", "ui", "ama", "ina", "oa"]},
	{   # fiery (Emberkin)
		"on": ["b", "p", "f", "ph", "r", "rr", "t", "k", "ign", "pyr", "sc", "br", "cr", "vr"],
		"vo": ["a", "e", "o", "i", "ae", "ou"],
		"co": ["", "r", "n", "x", "ss", "rn", "ld", "lt"],
		"m_end": ["", "os", "ex", "ar", "us"], "f_end": ["a", "is", "yx", "ena", "ra"]},
	{   # whispering (Duskari)
		"on": ["n", "v", "s", "sh", "z", "m", "dh", "nh", "ve", "sy", "mor", "ny"],
		"vo": ["a", "e", "i", "u", "ae", "ue", "y"],
		"co": ["", "th", "s", "sh", "l", "r", "n", "x"],
		"m_end": ["", "ith", "as", "eth", "ul"], "f_end": ["a", "ith", "ae", "ess", "yra"]},
]

const TRIBE_ADJ := ["River", "Stone", "Red", "Ash", "Moon", "Wolf", "Sun", "Elk", "Iron", "Bright", "Silent", "Storm", "Grey", "Golden",
	"Black", "White", "High", "Deep", "Swift", "Bitter", "Salt", "Thunder", "Frost", "Ember", "Hollow", "Long", "Night", "Dawn",
	"Raven", "Bear", "Fox", "Hawk", "Oak", "Pine", "Reed", "Sand", "Cloud", "Bone", "Flint", "Amber", "Copper", "Wild", "Green",
	"Lake", "Cliff", "Owl", "Boar", "Horse", "Serpent", "Lion", "Star", "Mist", "Rain", "Wind", "Ice", "Blood", "Honey", "Thorn"]
const TRIBE_NOUN := ["Folk", "Fang", "Hand", "Clan", "Eaters", "Kin", "Callers", "Runners", "Walkers", "Born", "Riders", "Keepers",
	"Hunters", "Singers", "Watchers", "Children", "People", "Tribe", "Blood", "Spears", "Shields", "Hearth", "Lodge", "Band",
	"Seekers", "Dancers", "Speakers", "Weavers", "Brothers", "Sisters", "Wardens", "Howlers", "Striders", "Host", "Pack"]


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


static func person(rng: RandomNumberGenerator, gender: String, race := 0, taken := {}) -> String:
	var st: Dictionary = STYLES[posmod(race, STYLES.size())]
	for attempt in 12:
		var n := ""
		var syl := 1 if rng.randf() < 0.45 else 2
		if rng.randf() < 0.08:
			syl = 3
		for k in syl:
			n += _pick(rng, st["on"]) + _pick(rng, st["vo"])
			if k == syl - 1 or rng.randf() < 0.3:
				n += _pick(rng, st["co"])
		n += _pick(rng, st["f_end"] if gender == "F" else st["m_end"])
		n = _tidy(n)
		if n.length() < 3 or n.length() > 10:
			continue
		n = _cap(n)
		if not taken.has(n) or attempt == 11:
			return n
	return _cap(_pick(rng, st["on"]) + _pick(rng, st["vo"]) + str(rng.randi_range(2, 99)))


static func tribe(rng: RandomNumberGenerator, race := 0, taken := {}) -> String:
	for attempt in 30:
		var n := ""
		var roll := rng.randf()
		if roll < 0.55:
			n = "%s %s" % [_pick(rng, TRIBE_ADJ), _pick(rng, TRIBE_NOUN)]
		elif roll < 0.75:
			n = "%s of the %s" % [_pick(rng, ["Kin", "Children", "People", "Clan", "Sons", "Daughters"]), _pick(rng, TRIBE_ADJ)]
		else:
			# a word in the race's own tongue
			var st: Dictionary = STYLES[posmod(race, STYLES.size())]
			var w := _tidy(_pick(rng, st["on"]) + _pick(rng, st["vo"]) + _pick(rng, st["co"]) + _pick(rng, st["vo"]) + _pick(rng, ["n", "r", "th", "", "i", "ai"]))
			n = _cap(w) + (" " + _pick(rng, ["Clan", "Tribe", "Folk", "Kin", "Host"]) if rng.randf() < 0.5 else "")
		if not taken.has(n):
			return n
	return "Tribe %d" % rng.randi_range(10, 999)


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return str(arr[rng.randi() % arr.size()])


## Removes awkward triple letters and double vowels at word joins.
static func _tidy(s: String) -> String:
	var out := ""
	for ch in s:
		if out.length() >= 2 and out[out.length() - 1] == ch and out[out.length() - 2] == ch:
			continue
		out += ch
	return out
