class_name Defs
extends RefCounted
## Static game data: terrain, resources, items, buildings, animals, illnesses, jobs.

const TILE := 16
const DAY_SECONDS := 100.0            # real seconds per in-game day at 1x speed
const HOUR := DAY_SECONDS / 24.0      # real seconds per in-game hour at 1x
const YEAR_DAYS := 365               # calendar year
const AGE_YEAR_DAYS := 40.0          # people and animals age one "life year" every 40 days, so generations fit in a game
const START_DOY := 59                # day 0 of a new game is March 1 (day-of-year, 0 = Jan 1)
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const PREGNANCY_DAYS := 45.0
const ERAS := ["Caveman Age", "Stone Age", "Bronze Age", "Iron Age"]
const WALK_SPEED := 2.2               # tiles per (real) second at 1x on cost-1 terrain
const SEASONS := ["Spring", "Summer", "Fall", "Winter"]
const SEASON_TEMP := [0.0, 7.0, -3.0, -14.0]   # typical offsets; the live value follows a smooth yearly curve
const HOME_RADIUS := 48               # how far colonists roam for work

# ---------------------------------------------------------------- terrain
enum T { DEEP_OCEAN, OCEAN, BEACH, PLAINS, GRASSLAND, FOREST, DENSE_FOREST, SNOW_FOREST,
	TUNDRA, RAINFOREST, HILLS, ROCKY, MOUNTAIN, PEAK, LAKE, RIVER, VALLEY, SPRING, SNOWY,
	DESERT, HIGH_DESERT, SAVANNA, STEPPE, SWAMP, BADLANDS, ALPINE }

# cost: 0 = impassable for walkers. fresh: drinkable. water: tile is water.
const TERRAIN := [
	{"name": "Deep Ocean", "color": Color(0.09, 0.20, 0.42), "cost": 0.0, "water": true, "fresh": false},
	{"name": "Ocean", "color": Color(0.14, 0.33, 0.58), "cost": 0.0, "water": true, "fresh": false},
	{"name": "Beach", "color": Color(0.86, 0.80, 0.56), "cost": 1.1, "water": false, "fresh": false},
	{"name": "Plains", "color": Color(0.62, 0.70, 0.36), "cost": 1.0, "water": false, "fresh": false},
	{"name": "Grassland", "color": Color(0.42, 0.66, 0.30), "cost": 1.0, "water": false, "fresh": false},
	{"name": "Forest", "color": Color(0.24, 0.50, 0.22), "cost": 1.3, "water": false, "fresh": false},
	{"name": "Dense Forest", "color": Color(0.15, 0.36, 0.17), "cost": 1.7, "water": false, "fresh": false},
	{"name": "Snow Forest", "color": Color(0.84, 0.88, 0.90), "cost": 1.6, "water": false, "fresh": false},
	{"name": "Tundra", "color": Color(0.78, 0.82, 0.80), "cost": 1.3, "water": false, "fresh": false},
	{"name": "Rainforest", "color": Color(0.10, 0.42, 0.20), "cost": 1.8, "water": false, "fresh": false},
	{"name": "Hills", "color": Color(0.52, 0.56, 0.34), "cost": 1.6, "water": false, "fresh": false},
	{"name": "Rocky Terrain", "color": Color(0.55, 0.52, 0.46), "cost": 1.5, "water": false, "fresh": false},
	{"name": "Mountain", "color": Color(0.43, 0.40, 0.38), "cost": 0.0, "water": false, "fresh": false},
	{"name": "Snowy Peak", "color": Color(0.92, 0.93, 0.96), "cost": 0.0, "water": false, "fresh": false},
	{"name": "Lake", "color": Color(0.22, 0.47, 0.66), "cost": 0.0, "water": true, "fresh": true},
	{"name": "River", "color": Color(0.27, 0.54, 0.74), "cost": 4.0, "water": true, "fresh": true},
	{"name": "Valley", "color": Color(0.36, 0.62, 0.28), "cost": 1.0, "water": false, "fresh": false},
	{"name": "Spring", "color": Color(0.40, 0.72, 0.86), "cost": 0.0, "water": true, "fresh": true},
	{"name": "Snow", "color": Color(0.90, 0.92, 0.95), "cost": 1.4, "water": false, "fresh": false},
	{"name": "Low Desert", "color": Color(0.90, 0.78, 0.52), "cost": 1.25, "water": false, "fresh": false},
	{"name": "High Desert", "color": Color(0.74, 0.66, 0.48), "cost": 1.3, "water": false, "fresh": false},
	{"name": "Savanna", "color": Color(0.76, 0.72, 0.40), "cost": 1.0, "water": false, "fresh": false},
	{"name": "Steppe", "color": Color(0.66, 0.68, 0.46), "cost": 1.0, "water": false, "fresh": false},
	{"name": "Swamp", "color": Color(0.30, 0.40, 0.28), "cost": 2.2, "water": false, "fresh": false},
	{"name": "Badlands", "color": Color(0.70, 0.44, 0.30), "cost": 1.6, "water": false, "fresh": false},
	{"name": "Alpine Meadow", "color": Color(0.50, 0.64, 0.42), "cost": 1.4, "water": false, "fresh": false},
]

# ---------------------------------------------------------------- resources
enum R { NONE, TREE, PINE, SNOW_PINE, PALM, JUNGLE_TREE, BERRY_BUSH, MUSHROOM, STICKS,
	SMALL_STONES, LARGE_STONE, BOULDER, GRASS, COPPER_ORE, TIN_ORE, IRON_ORE, FRUIT_BUSH,
	CACTUS, SHRUB, REEDS, ACACIA, JUNIPER }

# work = real seconds (at 1x, skill 0) to extract one unit. regrow = stays after depletion.
const RES := [
	{"name": "", "job": "", "item": "", "amount": 0, "work": 1.0, "regrow": false, "cost": 0.0},
	{"name": "Oak Tree", "job": "woodcutter", "item": "wood", "amount": 8, "work": 1.5, "bonus": "sticks", "regrow": false, "cost": 0.6},
	{"name": "Pine Tree", "job": "woodcutter", "item": "wood", "amount": 7, "work": 1.4, "bonus": "sticks", "regrow": false, "cost": 0.6},
	{"name": "Snowy Pine", "job": "woodcutter", "item": "wood", "amount": 7, "work": 1.6, "bonus": "sticks", "regrow": false, "cost": 0.6},
	{"name": "Palm Tree", "job": "woodcutter", "item": "wood", "amount": 5, "work": 1.3, "bonus": "fruit", "regrow": false, "cost": 0.4},
	{"name": "Jungle Tree", "job": "woodcutter", "item": "wood", "amount": 10, "work": 1.7, "bonus": "sticks", "regrow": false, "cost": 0.8},
	{"name": "Berry Bush", "job": "gatherer", "item": "berries", "amount": 8, "work": 0.7, "regrow": true, "cost": 0.3},
	{"name": "Mushrooms", "job": "gatherer", "item": "mushrooms", "amount": 3, "work": 0.6, "regrow": true, "cost": 0.0},
	{"name": "Sticks & Branches", "job": "gatherer", "item": "sticks", "amount": 4, "work": 0.5, "regrow": true, "cost": 0.0},
	{"name": "Small Stones", "job": "gatherer", "item": "stone", "amount": 3, "work": 0.6, "regrow": false, "cost": 0.0},
	{"name": "Large Stone", "job": "miner", "item": "stone", "amount": 8, "work": 1.6, "regrow": false, "cost": 0.5},
	{"name": "Boulder", "job": "miner", "item": "stone", "amount": 18, "work": 2.2, "regrow": false, "cost": 1.5},
	{"name": "Tall Grass", "job": "gatherer", "item": "grass", "amount": 4, "work": 0.5, "regrow": true, "cost": 0.0},
	{"name": "Copper Deposit", "job": "miner", "item": "copper_ore", "amount": 10, "work": 2.6, "regrow": false, "cost": 1.0},
	{"name": "Tin Deposit", "job": "miner", "item": "tin_ore", "amount": 8, "work": 2.6, "regrow": false, "cost": 1.0},
	{"name": "Iron Deposit", "job": "miner", "item": "iron_ore", "amount": 10, "work": 3.0, "regrow": false, "cost": 1.0},
	{"name": "Fruit Bush", "job": "gatherer", "item": "fruit", "amount": 7, "work": 0.7, "regrow": true, "cost": 0.3},
	{"name": "Prickly Pear Cactus", "job": "gatherer", "item": "fruit", "amount": 4, "work": 1.0, "regrow": true, "cost": 0.5},
	{"name": "Dry Shrub", "job": "gatherer", "item": "sticks", "amount": 4, "work": 0.6, "regrow": true, "cost": 0.2},
	{"name": "Reeds", "job": "gatherer", "item": "grass", "amount": 6, "work": 0.5, "regrow": true, "cost": 0.2},
	{"name": "Acacia Tree", "job": "woodcutter", "item": "wood", "amount": 6, "work": 1.5, "bonus": "sticks", "regrow": false, "cost": 0.5},
	{"name": "Juniper", "job": "woodcutter", "item": "wood", "amount": 4, "work": 1.3, "bonus": "sticks", "regrow": false, "cost": 0.4},
]
const TREES := [R.TREE, R.PINE, R.SNOW_PINE, R.PALM, R.JUNGLE_TREE, R.ACACIA, R.JUNIPER]
const FOOD_RES := [R.BERRY_BUSH, R.MUSHROOM, R.FRUIT_BUSH, R.CACTUS]
const MINE_RES := [R.BOULDER, R.LARGE_STONE, R.COPPER_ORE, R.TIN_ORE, R.IRON_ORE, R.SMALL_STONES]

# ---------------------------------------------------------------- items
const ITEM_NAMES := {
	"wood": "Wood", "sticks": "Sticks", "stone": "Stone", "grass": "Grass Fiber",
	"hides": "Animal Hides", "bones": "Bones", "berries": "Berries", "mushrooms": "Mushrooms",
	"fruit": "Tropical Fruit", "raw_meat": "Raw Meat", "fish": "Raw Fish",
	"cooked_meat": "Cooked Meat", "cooked_fish": "Cooked Fish", "dried_meat": "Dried Meat",
	"crops": "Vegetables", "roots": "Roots & Tubers", "water": "Water", "copper_ore": "Copper Ore", "tin_ore": "Tin Ore",
	"iron_ore": "Iron Ore",
	"stone_club": "Stone Club", "stone_spear": "Stone Spear", "sling": "Sling", "bronze_spear": "Bronze Spear",
	"bronze_sword": "Bronze Sword", "bow": "Composite Bow", "iron_spear": "Iron Spear", "iron_sword": "Iron Sword", "crossbow": "Crossbow",
}
const MATERIALS := ["wood", "sticks", "stone", "grass", "hides", "bones", "copper_ore", "tin_ore", "iron_ore"]

# nut = hunger restored per unit. spoil = fraction lost per day. sick = illness chance when eaten.
const FOOD := {
	"berries": {"nut": 8.0, "spoil": 0.07, "sick": 0.0},
	"mushrooms": {"nut": 8.0, "spoil": 0.12, "sick": 0.03},
	"fruit": {"nut": 10.0, "spoil": 0.07, "sick": 0.0},
	"raw_meat": {"nut": 16.0, "spoil": 0.22, "sick": 0.18},
	"fish": {"nut": 14.0, "spoil": 0.26, "sick": 0.14},
	"cooked_meat": {"nut": 30.0, "spoil": 0.11, "sick": 0.0},
	"cooked_fish": {"nut": 26.0, "spoil": 0.13, "sick": 0.0},
	"dried_meat": {"nut": 26.0, "spoil": 0.015, "sick": 0.0},
	"crops": {"nut": 14.0, "spoil": 0.03, "sick": 0.0},
	"roots": {"nut": 6.0, "spoil": 0.02, "sick": 0.0},
}
const EAT_ORDER := ["cooked_fish", "cooked_meat", "berries", "fruit", "mushrooms", "crops", "roots", "dried_meat", "fish", "raw_meat"]
const DAILY_FOOD := 24.0   # hunger points one adult needs per day

# ---------------------------------------------------------------- jobs
const JOBS := ["laborer", "gatherer", "hunter", "builder", "farmer", "fisherman", "woodcutter", "miner", "cook", "healer", "researcher", "trader", "smith", "soldier"]
# jobs that need a building before anyone can take them
const JOB_NEEDS := {"smith": "blacksmith", "soldier": "training_camp"}
const JOB_NAMES := {
	"laborer": "General Laborer", "gatherer": "Gatherer", "hunter": "Hunter", "builder": "Builder",
	"farmer": "Farmer", "fisherman": "Fisherman", "woodcutter": "Woodcutter", "miner": "Miner",
	"cook": "Cook", "healer": "Healer", "researcher": "Researcher", "trader": "Trader", "smith": "Blacksmith", "soldier": "Soldier",
}

# ---------------------------------------------------------------- town planning
## Zones the player paints. A building standing in the zone that suits it gets bonuses.
const ZONES := {
	1: {"name": "Farming", "color": Color(0.55, 0.85, 0.30), "cats": ["Food & Water"],
		"desc": "Farms yield 25% more; food buildings' bonuses are 25% stronger."},
	2: {"name": "Housing", "color": Color(0.95, 0.75, 0.35), "cats": ["Homes"],
		"desc": "Homes hold 1 more person and their sleepers rest 20% faster."},
	3: {"name": "Workshop", "color": Color(0.45, 0.70, 1.0), "cats": ["Storage & Industry", "Knowledge & Civic"],
		"desc": "Work at industry and knowledge buildings is 20% faster; their bonuses are 25% stronger."},
}
const BRIDGE_WOOD := 3           # wood per bridge tile
const ROAD_SPEED_COST := 0.5      # path cost on a road (plains are 1.0): about twice as fast


## Zone (1-3) a building type belongs in, or 0.
static func zone_for(type: String) -> int:
	for cat in BUILD_CATEGORIES:
		if (cat[1] as Array).has(type):
			for z in ZONES.keys():
				if (ZONES[z]["cats"] as Array).has(cat[0]):
					return int(z)
	return 0

# kinds of structure, for the build window
const BUILD_CATEGORIES := [
	["Homes", ["shelter", "bedding", "stone_hut", "house", "stone_house"]],
	["Food & Water", ["campfire", "drying_rack", "hunting_camp", "farm", "granary", "well"]],
	["Storage & Industry", ["storage", "mine", "workshop", "blacksmith", "harbor"]],
	["Knowledge & Civic", ["research_table", "healer_hut", "monolith", "map_table", "capitol"]],
	["Defense & Military", ["fence", "wall", "gate", "training_camp", "mercenary_hall", "watchtower", "arrow_tower"]],
]


## The age a building belongs to (the age of the tech that unlocks it).
static func building_era(type: String) -> int:
	var tech := str(BUILDINGS[type].get("tech", ""))
	return int(TECHS[tech]["era"]) if tech != "" else 0


# ---------------------------------------------------------------- research economy
# Knowledge points (KP) one unit of a material gives when carried from the stockpile to a
# Research Table. Rarer materials are worth more.
const KP_VALUE := {"grass": 20, "sticks": 30, "wood": 60, "stone": 60, "bones": 150, "hides": 150,
	"copper_ore": 400, "tin_ore": 450, "iron_ore": 600}
const KP_PER_RP := 1000        # knowledge points needed for one research point
const RESEARCH_SHARE_DEFAULT := 0.25
# research point cost of a tech: era base + its step along its category's chain in that era x era increment
const TECH_ERA_BASE := [1.0, 4.0, 8.0, 14.0]
const TECH_ERA_INC := [0.5, 2.0, 3.0, 4.0]

# ---------------------------------------------------------------- trade & money
const MONEY_NAME := "Talents"
const MONEY_START := 100.0
# base price in Talents of one unit, before supply & demand
const BASE_PRICE := {"wood": 1.0, "sticks": 0.5, "stone": 1.0, "grass": 0.4, "hides": 3.0, "bones": 2.0,
	"copper_ore": 6.0, "tin_ore": 7.0, "iron_ore": 9.0, "berries": 1.0, "mushrooms": 1.0, "fruit": 1.2,
	"raw_meat": 1.5, "fish": 1.4, "cooked_meat": 2.5, "cooked_fish": 2.3, "dried_meat": 3.0, "crops": 1.4, "roots": 0.8}

# ---------------------------------------------------------------- buildings
const BUILD_ORDER := ["campfire", "shelter", "storage", "research_table", "bedding", "drying_rack", "hunting_camp", "fence",
	"farm", "granary", "stone_hut", "well", "healer_hut", "mine",
	"harbor", "blacksmith", "training_camp", "wall", "gate", "monolith", "workshop", "house", "map_table", "capitol", "watchtower",
	"stone_house", "arrow_tower"]
# tech: research needed to unlock. warm: sleeping/standing inside keeps people warm. storage / water_cap / preserve:
# stockpile bonuses. blocks: stops animals. guard: wild animals keep away (tiles).
const BUILDINGS := {
	"bandit_camp": {"name": "Bandit Camp", "size": Vector2i(3, 3), "cost": {}, "work": 1.0, "housing": 0,
		"desc": "A ragged camp of thieves and robbers. Destroy it to recover their stash."},
	"campfire": {"name": "Campfire", "size": Vector2i(1, 1), "cost": {"wood": 4, "stone": 4}, "work": 12.0, "housing": 0,
		"desc": "Light, warmth and cooking. Needs firewood to keep burning."},
	"shelter": {"name": "Primitive Shelter", "size": Vector2i(2, 2), "cost": {"wood": 10, "sticks": 12, "grass": 10}, "work": 30.0, "housing": 3, "warm": true,
		"desc": "Houses 3. Sleeping inside keeps people warm and dry."},
	"storage": {"name": "Storage Area", "size": Vector2i(2, 2), "cost": {"wood": 6, "sticks": 10}, "work": 20.0, "housing": 0,
		"storage": 150, "water_cap": 20, "preserve": 0.3, "desc": "+150 storage, +20 water. Food spoils 30% slower."},
	"research_table": {"name": "Research Table", "size": Vector2i(2, 1), "cost": {"wood": 8, "stone": 6}, "work": 15.0, "housing": 0,
		"desc": "Researchers bring materials from the stockpile here and turn them into knowledge."},
	"bedding": {"name": "Sleeping Area", "size": Vector2i(2, 1), "cost": {"grass": 12, "hides": 2}, "work": 10.0, "housing": 2,
		"desc": "Sleeps 2. Better rest than bare ground."},
	"drying_rack": {"name": "Drying Rack", "size": Vector2i(1, 1), "cost": {"sticks": 10, "grass": 4}, "work": 10.0, "housing": 0, "tech": "meat_drying",
		"desc": "Cooks dry raw meat and fish into long-lasting dried meat."},
	"hunting_camp": {"name": "Hunting Camp", "size": Vector2i(2, 2), "cost": {"wood": 8, "sticks": 6, "hides": 1}, "work": 20.0, "housing": 0, "tech": "hunting_lore",
		"desc": "Hunters drop meat, hides and bones here. Improves hunting."},
	"fence": {"name": "Primitive Fence", "size": Vector2i(1, 1), "cost": {"sticks": 3}, "work": 3.0, "housing": 0, "blocks": true,
		"desc": "Keeps wild animals out."},
	"farm": {"name": "Farm Plot", "size": Vector2i(3, 3), "cost": {"sticks": 6, "stone": 2}, "work": 12.0, "housing": 0, "tech": "agriculture",
		"desc": "Farmers plant in spring/summer and harvest vegetables."},
	"granary": {"name": "Granary", "size": Vector2i(2, 2), "cost": {"wood": 15, "stone": 20}, "work": 35.0, "housing": 0, "tech": "pottery",
		"storage": 250, "preserve": 0.25, "desc": "Clay pots and a raised floor: +250 storage, food spoils slower."},
	"stone_hut": {"name": "Stone Hut", "size": Vector2i(2, 2), "cost": {"stone": 30, "wood": 10, "grass": 10}, "work": 45.0, "housing": 5, "warm": true, "tech": "stone_huts",
		"desc": "Houses 5. Thick stone walls keep the cold out."},
	"well": {"name": "Well", "size": Vector2i(1, 1), "cost": {"stone": 20, "wood": 6}, "work": 30.0, "housing": 0, "water_cap": 30, "tech": "wells",
		"desc": "Clean water right in the village: fills the water store every hour."},
	"healer_hut": {"name": "Healer's Hut", "size": Vector2i(2, 2), "cost": {"wood": 15, "grass": 15, "stone": 10}, "work": 30.0, "housing": 0, "tech": "herbalism",
		"desc": "Sick people recover much faster."},
	"mine": {"name": "Mine", "size": Vector2i(2, 2), "cost": {"wood": 20, "stone": 10}, "work": 40.0, "housing": 0, "tech": "mining",
		"desc": "Dug into hills or rock. Miners bring up stone and ore without using up deposits."},
	"workshop": {"name": "Bronze Workshop", "size": Vector2i(2, 2), "cost": {"wood": 25, "stone": 15, "copper_ore": 4}, "work": 45.0, "housing": 0, "tech": "bronze_working",
		"work_all": 0.1, "desc": "Smiths keep everyone's tools sharp: all work 10% faster."},
	"house": {"name": "Timber House", "size": Vector2i(3, 2), "cost": {"wood": 30, "stone": 10}, "work": 50.0, "housing": 6, "warm": true, "tech": "timber_houses",
		"desc": "Houses 6. A proper home with a hearth."},
	"blacksmith": {"name": "Blacksmith", "size": Vector2i(2, 2), "cost": {"wood": 20, "stone": 15}, "work": 35.0, "housing": 0, "tech": "weaponsmithing",
		"desc": "Smiths forge weapons for your soldiers — better ones in every age."},
	"training_camp": {"name": "Training Camp", "size": Vector2i(3, 3), "cost": {"wood": 25, "sticks": 10, "stone": 10}, "work": 35.0, "housing": 0, "tech": "warrior_training",
		"desc": "Lets you make Soldiers. Soldiers drill here between battles and get better at fighting."},
	"wall": {"name": "Wall", "size": Vector2i(1, 1), "cost": {"wood": 3}, "work": 5.0, "housing": 0, "blocks": true, "wall": true, "tech": "defensive_perimeters",
		"desc": "Stops people and animals. Enemies must break it down. Wooden palisade, stone wall or fortified wall, depending on your research."},
	"gate": {"name": "Gate", "size": Vector2i(1, 1), "cost": {"wood": 6}, "work": 8.0, "housing": 0, "blocks": true, "gate": true, "tech": "defensive_perimeters",
		"desc": "A way through your walls. Your people and friends pass; enemies at war have to smash it."},
	"mercenary_hall": {"name": "Mercenary Hall", "size": Vector2i(3, 2), "cost": {"wood": 30, "stone": 15, "hides": 4}, "work": 40.0, "housing": 0, "tech": "mercenary_pacts",
		"desc": "Hire armed Warriors and Archers for Talents. They join your tribe ready to fight, and drill here like at a Training Camp."},
	"capitol": {"name": "Capitol", "size": Vector2i(3, 3), "cost": {"stone": 60, "wood": 30, "copper_ore": 6}, "work": 80.0, "housing": 0, "tech": "statecraft",
		"work_all": 0.05, "hp": 600, "desc": "Seat of government: your government's bonuses are 50% stronger, +5% work, and rivals take your peace offers seriously."},
	"monolith": {"name": "Monolith", "size": Vector2i(2, 2), "cost": {"stone": 60, "wood": 10}, "work": 60.0, "housing": 0, "tech": "standing_stones",
		"hp": 900, "desc": "A great standing stone that marks the passing of ages. Spend knowledge to skip calendar years (your people don't age)."},
	"map_table": {"name": "Map Table", "size": Vector2i(2, 1), "cost": {"wood": 15, "stone": 5, "hides": 4}, "work": 25.0, "housing": 0, "tech": "cartography",
		"desc": "Charts of the known world. Unlocks the Territory view on the World Map."},
	"arrow_tower": {"name": "Arrow Tower", "size": Vector2i(1, 1), "cost": {"stone": 25, "wood": 10, "iron_ore": 2}, "work": 40.0, "housing": 0, "tech": "arrow_towers",
		"hp": 500, "shoots": {"range": 10.0, "dmg": 14.0, "cd": 1.5}, "desc": "Archers shoot enemies at war and predators within 10 tiles."},
	"stone_house": {"name": "Stone House", "size": Vector2i(3, 2), "cost": {"stone": 40, "wood": 15, "iron_ore": 2}, "work": 60.0, "housing": 8, "warm": true, "tech": "masonry",
		"desc": "Houses 8. Mortared stone and a tiled roof."},
	"harbor": {"name": "Harbor", "size": Vector2i(2, 2), "cost": {"wood": 30, "stone": 10}, "work": 45.0, "housing": 0, "tech": "boatbuilding",
		"desc": "Must touch the sea. Builds ships to carry your people to other shores."},
	"watchtower": {"name": "Watchtower", "size": Vector2i(2, 2), "cost": {"wood": 20, "stone": 20}, "work": 45.0, "housing": 0, "guard": 12.0, "tech": "watch_posts",
		"hp": 300, "shoots": {"range": 8.0, "dmg": 8.0, "cd": 2.0}, "desc": "Lookouts keep predators away (12 tiles) and throw spears at enemies at war (8 tiles)."},
}

# wall and gate strength by fortification level (Defensive Perimeters → Stone Walls → Fortifications)
const WALL_TIERS := [
	{"wall": "Wooden Palisade", "gate": "Palisade Gate", "wall_cost": {"wood": 3}, "gate_cost": {"wood": 6}, "hp": 150},
	{"wall": "Stone Wall", "gate": "Stone Gate", "wall_cost": {"stone": 4}, "gate_cost": {"stone": 6, "wood": 4}, "hp": 400},
	{"wall": "Fortified Wall", "gate": "Fortified Gate", "wall_cost": {"stone": 6, "wood": 1}, "gate_cost": {"stone": 10, "wood": 4, "iron_ore": 1}, "hp": 800},
]

# ---------------------------------------------------------------- weapons (forged at the Blacksmith)
# range in tiles; anything above 2 is a ranged weapon
const WEAPONS := {
	"stone_club": {"name": "Stone Club", "era": 1, "dmg": 10.0, "range": 1.3, "hours": 3.0, "cost": {"wood": 2, "stone": 2}},
	"stone_spear": {"name": "Stone Spear", "era": 1, "dmg": 12.0, "range": 1.7, "hours": 3.0, "cost": {"wood": 3, "stone": 2}},
	"sling": {"name": "Sling", "era": 1, "dmg": 7.0, "range": 5.0, "hours": 2.5, "cost": {"grass": 3, "hides": 1}},
	"flint_axe": {"name": "Flint Axe", "era": 1, "dmg": 13.0, "range": 1.2, "hours": 3.5, "cost": {"wood": 2, "stone": 3}},
	"short_bow": {"name": "Hunting Bow", "era": 1, "dmg": 9.0, "range": 6.5, "hours": 3.5, "cost": {"wood": 3, "sticks": 3, "hides": 1}},
	"bronze_spear": {"name": "Bronze Spear", "era": 2, "dmg": 17.0, "range": 1.7, "hours": 5.0, "cost": {"wood": 2, "copper_ore": 2, "tin_ore": 1}},
	"bronze_sword": {"name": "Bronze Sword", "era": 2, "dmg": 20.0, "range": 1.3, "hours": 6.0, "cost": {"copper_ore": 3, "tin_ore": 2}},
	"bow": {"name": "Composite Bow", "era": 2, "dmg": 11.0, "range": 7.0, "hours": 5.0, "cost": {"wood": 3, "sticks": 2, "grass": 2, "bones": 1}},
	"iron_spear": {"name": "Iron Spear", "era": 3, "dmg": 24.0, "range": 1.7, "hours": 6.0, "cost": {"iron_ore": 2, "wood": 2}},
	"iron_sword": {"name": "Iron Sword", "era": 3, "dmg": 28.0, "range": 1.3, "hours": 7.0, "cost": {"iron_ore": 3, "wood": 1}},
	"crossbow": {"name": "Crossbow", "era": 3, "dmg": 18.0, "range": 8.0, "hours": 7.0, "cost": {"wood": 4, "iron_ore": 1, "sticks": 2}},
	"longbow": {"name": "Longbow", "era": 3, "dmg": 15.0, "range": 10.0, "hours": 6.0, "cost": {"wood": 5, "sticks": 2, "hides": 1}},
}
const WEAPON_ORDER := ["stone_club", "stone_spear", "flint_axe", "sling", "short_bow", "bronze_spear", "bronze_sword", "bow", "iron_spear", "iron_sword", "crossbow", "longbow"]

## Soldier kinds: Warriors fight up close, Archers from range.
const SOLDIER_KINDS := {
	"warrior": {"name": "Warrior", "ranged": false, "hire": 60, "desc": "Short-range fighter: clubs, axes, spears and swords."},
	"archer": {"name": "Archer", "ranged": true, "hire": 80, "desc": "Long-range fighter: slings, bows and crossbows."},
}


static func weapon_ranged(w: String) -> bool:
	return w != "" and float(WEAPONS[w]["range"]) > 2.0


## Best weapon of a kind a tribe of this age can field (hired soldiers arrive with it).
static func best_weapon_for(kind: String, era: int) -> String:
	var best := ""
	var bv := -1.0
	for w in WEAPON_ORDER:
		var wd: Dictionary = WEAPONS[w]
		if int(wd["era"]) > era or weapon_ranged(w) != bool(SOLDIER_KINDS[kind]["ranged"]):
			continue
		var v := float(wd["dmg"]) + float(wd["range"]) * 0.5
		if v > bv:
			bv = v
			best = w
	return best

# ---------------------------------------------------------------- governments (chosen on entering the Bronze and Iron Ages)
const GOVERNMENTS := {
	"chiefdom": {"approval": 0, "name": "Chiefdom", "era": 2, "fx": {"fight": 4.0, "work_hunter": 0.15, "fertility": 0.1}, "ai": "warlike",
		"desc": "A war chief and his kin rule. Stronger warriors and hunters, more children."},
	"monarchy": {"approval": -2, "name": "Monarchy", "era": 2, "fx": {"work_all": 0.08, "defense": 0.05}, "ai": "balanced",
		"desc": "A hereditary king or queen. Steady work and better-protected people."},
	"theocracy": {"approval": 3, "name": "Theocracy", "era": 2, "fx": {"medicine": 0.2, "heal": 0.2, "research": 0.15}, "ai": "peaceful",
		"desc": "Priest-kings speak for the gods. Better healing, temples keep records (research)."},
	"oligarchy": {"approval": 2, "name": "Council of Elders", "era": 2, "fx": {"research": 0.25, "trade": 0.2}, "ai": "peaceful",
		"desc": "The wisest elders decide together. Faster research and shrewder trade."},
	"city_state": {"approval": 3, "name": "City-State", "era": 2, "fx": {"storage": 100.0, "work_builder": 0.2, "trade": 0.1}, "ai": "balanced",
		"desc": "A walled city rules its fields. Faster building, bigger stores, some trade."},
	"kingdom": {"approval": -2, "name": "Kingdom", "era": 3, "fx": {"work_all": 0.1, "defense": 0.1}, "ai": "balanced",
		"desc": "Lords swear to one crown. More work done, sturdier defence."},
	"empire": {"approval": -6, "name": "Empire", "era": 3, "fx": {"fight": 10.0, "train": 0.5, "work_builder": 0.15}, "ai": "warlike",
		"desc": "An emperor and standing armies. Much stronger soldiers who train faster."},
	"republic": {"approval": 6, "name": "Republic", "era": 3, "fx": {"research": 0.3, "trade": 0.25}, "ai": "peaceful",
		"desc": "Elected magistrates and a senate. Great for research and trade."},
	"democracy": {"approval": 10, "name": "Democracy", "era": 3, "fx": {"work_all": 0.12, "research": 0.15, "fertility": 0.15}, "ai": "peaceful",
		"desc": "Citizens vote in the assembly. Everyone works harder, families grow."},
	"tyranny": {"approval": -15, "name": "Tyranny", "era": 3, "fx": {"fight": 6.0, "work_all": 0.15, "fertility": -0.15}, "ai": "warlike",
		"desc": "One strongman rules by fear. Hard work and fierce fighters, but fewer children."},
}


static func governments_of_era(era: int) -> Array:
	var out: Array = []
	for k in GOVERNMENTS.keys():
		if int(GOVERNMENTS[k]["era"]) == era:
			out.append(k)
	return out


# ---------------------------------------------------------------- research
# cost: research points plus optional materials. fx: bonuses (see Colony.bonus). unlocks: buildings.
const TECH_CATEGORIES := ["Food", "Construction", "Medicine", "Weapons", "Tools", "Ships", "Military", "Civics"]
const TECH_ORDER := [
	"foraging_lore", "meat_drying", "fire_cooking", "fire_keeping", "lashing", "storage_pits",
	"herb_lore", "hide_wraps", "clean_water", "sharpened_spears", "throwing_stones", "hunting_lore",
	"stone_choppers", "bone_needles", "digging_sticks", "agriculture", "pottery", "fishing_nets",
	"animal_traps", "stone_huts", "wells", "mining", "woven_baskets", "herbalism",
	"midwifery", "bone_setting", "flint_spears", "slings", "hide_shields", "polished_tools",
	"flint_knapping", "mortar_pestle", "pack_carts", "boatbuilding", "paddles", "irrigation", "seed_selection",
	"salt_curing", "timber_houses", "mudbrick", "organized_labor", "bronze_surgery", "bathing",
	"healing_salves", "bronze_weapons", "bronze_shields", "composite_bows", "bronze_working", "bronze_axes",
	"woven_clothing", "sailing", "navigation", "larger_hulls", "iron_plough", "crop_rotation",
	"smokehouses", "masonry", "engineering", "aqueducts", "medicine", "sanitation",
	"apothecary", "iron_weapons", "iron_armor", "iron_arrowheads", "iron_smelting", "bellows",
	"iron_tool_kits", "galleys", "sea_charts", "reinforced_hulls",
	"weaponsmithing", "warrior_training", "defensive_perimeters", "mercenary_pacts", "stone_walls", "watch_posts", "phalanx",
	"fortifications", "arrow_towers", "legions", "standing_stones", "cartography", "statecraft", "code_of_laws", "coinage", "bureaucracy", "philosophy",
]
const TECHS := {
	"foraging_lore": {"name": "Foraging Lore", "era": 0, "kind": "Food", "cost": {"points": 25}, "fx": {"work_gatherer": 0.2}, "desc": "Knowing which plants feed you: gathering 20% faster."},
	"meat_drying": {"name": "Meat Drying", "era": 0, "kind": "Food", "cost": {"points": 35}, "fx": {}, "unlocks": ["drying_rack"], "desc": "Unlocks the Drying Rack to preserve meat for winter."},
	"fire_cooking": {"name": "Fire Cooking", "era": 0, "kind": "Food", "cost": {"points": 30}, "fx": {"work_cook": 0.3, "preserve": 0.05}, "desc": "Roasting over flames: cooks work faster, food keeps a little longer."},
	"fire_keeping": {"name": "Fire Keeping", "era": 0, "kind": "Construction", "cost": {"points": 25}, "fx": {"fuel": 0.3}, "desc": "Banking embers: campfires burn 30% longer."},
	"lashing": {"name": "Lashing & Binding", "era": 0, "kind": "Construction", "cost": {"points": 30}, "fx": {"work_builder": 0.2}, "desc": "Cords of sinew and fibre: building is 20% faster."},
	"storage_pits": {"name": "Storage Pits", "era": 0, "kind": "Construction", "cost": {"points": 35}, "fx": {"storage": 60.0}, "desc": "Lined pits in the ground: +60 storage."},
	"herb_lore": {"name": "Herb Lore", "era": 0, "kind": "Medicine", "cost": {"points": 30}, "fx": {"heal": 0.25}, "desc": "Soothing leaves and roots: healers are 25% more effective."},
	"hide_wraps": {"name": "Hide Wraps", "era": 0, "kind": "Medicine", "cost": {"points": 35}, "fx": {"warmth": 4.0}, "desc": "Better-cut hide clothing keeps people warmer."},
	"clean_water": {"name": "Clean Water Sense", "era": 0, "kind": "Medicine", "cost": {"points": 30}, "fx": {"water_safety": 0.4}, "desc": "Drink from running water: 40% less waterborne disease."},
	"sharpened_spears": {"name": "Sharpened Spears", "era": 0, "kind": "Weapons", "cost": {"points": 25}, "fx": {"hunt_hit": 0.1, "hunt_dmg": 6.0, "fight": 4.0}, "desc": "Fire-hardened spear points: better hunting and self-defence."},
	"throwing_stones": {"name": "Throwing Stones", "era": 0, "kind": "Weapons", "cost": {"points": 25}, "fx": {"hunt_hit": 0.08}, "desc": "Hunters bring down fleeing prey more often."},
	"hunting_lore": {"name": "Hunting Lore", "era": 0, "kind": "Weapons", "cost": {"points": 40}, "fx": {"hunt_hit": 0.05}, "unlocks": ["hunting_camp"], "desc": "Unlocks the Hunting Camp."},
	"stone_choppers": {"name": "Stone Choppers", "era": 0, "kind": "Tools", "cost": {"points": 30}, "fx": {"work_woodcutter": 0.25, "work_gatherer": 0.1, "work_laborer": 0.15}, "desc": "Sharp-edged rocks: chopping and gathering are faster."},
	"bone_needles": {"name": "Bone Needles", "era": 0, "kind": "Tools", "cost": {"points": 30}, "fx": {"warmth": 2.0, "work_laborer": 0.1}, "desc": "Sewn clothes fit better and keep out the wind."},
	"digging_sticks": {"name": "Digging Sticks", "era": 0, "kind": "Tools", "cost": {"points": 25}, "fx": {"work_gatherer": 0.1, "work_miner": 0.1}, "desc": "Pointed sticks for roots and stones."},
	"agriculture": {"name": "Agriculture", "era": 1, "kind": "Food", "cost": {"points": 150}, "fx": {}, "unlocks": ["farm"], "desc": "Planting seeds on purpose. Unlocks Farm Plots."},
	"pottery": {"name": "Pottery", "era": 1, "kind": "Food", "cost": {"points": 160}, "fx": {"preserve": 0.1}, "unlocks": ["granary"], "desc": "Fired clay pots. Unlocks the Granary; food keeps longer."},
	"fishing_nets": {"name": "Fishing Nets", "era": 1, "kind": "Food", "cost": {"points": 120, "grass": 15}, "fx": {"fish": 0.5}, "desc": "Woven nets: fishermen catch 50% more."},
	"animal_traps": {"name": "Animal Traps", "era": 1, "kind": "Food", "cost": {"points": 130}, "fx": {"hunt_hit": 0.05, "work_hunter": 0.2}, "desc": "Snares and pit traps bring in extra game."},
	"stone_huts": {"name": "Stone Huts", "era": 1, "kind": "Construction", "cost": {"points": 170}, "fx": {}, "unlocks": ["stone_hut"], "desc": "Unlocks the Stone Hut (houses 5)."},
	"wells": {"name": "Well Digging", "era": 1, "kind": "Construction", "cost": {"points": 160}, "fx": {}, "unlocks": ["well"], "desc": "Unlocks the Well: clean water in the village."},
	"mining": {"name": "Mining", "era": 1, "kind": "Construction", "cost": {"points": 180}, "fx": {"work_miner": 0.2}, "unlocks": ["mine"], "desc": "Unlocks the Mine, which produces stone and ore."},
	"woven_baskets": {"name": "Woven Baskets", "era": 1, "kind": "Construction", "cost": {"points": 120, "grass": 10}, "fx": {"carry": 4.0}, "desc": "Everyone can carry 4 more items."},
	"herbalism": {"name": "Herbal Medicine", "era": 1, "kind": "Medicine", "cost": {"points": 170}, "fx": {"heal": 0.4, "medicine": 0.3}, "unlocks": ["healer_hut"], "desc": "Healing plants. Unlocks the Healer's Hut."},
	"midwifery": {"name": "Midwifery", "era": 1, "kind": "Medicine", "cost": {"points": 140}, "fx": {"fertility": 0.25}, "desc": "Safer births: children come more often."},
	"bone_setting": {"name": "Bone Setting", "era": 1, "kind": "Medicine", "cost": {"points": 150}, "fx": {"heal": 0.3}, "desc": "Splints and care for the injured."},
	"flint_spears": {"name": "Flint Spears", "era": 1, "kind": "Weapons", "cost": {"points": 150, "stone": 10}, "fx": {"hunt_hit": 0.1, "hunt_dmg": 8.0, "fight": 6.0}, "desc": "Knapped flint blades on long shafts."},
	"slings": {"name": "Slings & Bolas", "era": 1, "kind": "Weapons", "cost": {"points": 130, "grass": 8}, "fx": {"hunt_hit": 0.08, "hunt_dmg": 4.0}, "desc": "Strike from a distance."},
	"hide_shields": {"name": "Hide Shields", "era": 1, "kind": "Weapons", "cost": {"points": 140, "hides": 4}, "fx": {"defense": 0.1, "fight": 3.0}, "desc": "Stretched hide on a frame: 10% less damage taken."},
	"polished_tools": {"name": "Polished Stone Tools", "era": 1, "kind": "Tools", "cost": {"points": 160, "stone": 10}, "fx": {"work_all": 0.15}, "desc": "Ground and polished axes, adzes and scrapers: all work 15% faster."},
	"flint_knapping": {"name": "Flint Knapping", "era": 1, "kind": "Tools", "cost": {"points": 140}, "fx": {"work_woodcutter": 0.2, "work_miner": 0.2}, "desc": "Razor-sharp flakes for every job."},
	"pack_carts": {"name": "Trade Wagons", "era": 1, "kind": "Tools", "cost": {"points": 150, "wood": 15, "hides": 2}, "fx": {}, "desc": "Traders pull a wagon: they carry four times as many goods and Talents on each trip."},
	"mortar_pestle": {"name": "Mortar & Pestle", "era": 1, "kind": "Tools", "cost": {"points": 120, "stone": 6}, "fx": {"work_cook": 0.3}, "desc": "Grinding grain and herbs: cooks work faster."},
	"boatbuilding": {"name": "Boatbuilding", "era": 1, "kind": "Ships", "cost": {"points": 160, "wood": 10}, "fx": {}, "unlocks": ["harbor"], "desc": "Unlocks the Harbor, where you can build dugout canoes."},
	"paddles": {"name": "Carved Paddles", "era": 1, "kind": "Ships", "cost": {"points": 120}, "fx": {"ship_speed": 0.25}, "desc": "Ships move 25% faster."},
	"irrigation": {"name": "Irrigation", "era": 2, "kind": "Food", "cost": {"points": 300}, "fx": {"farm": 0.5}, "desc": "Channels bring water to the fields: +50% harvests."},
	"seed_selection": {"name": "Seed Selection", "era": 2, "kind": "Food", "cost": {"points": 280}, "fx": {"farm": 0.3}, "desc": "Saving the best seed: +30% harvests."},
	"salt_curing": {"name": "Salt Curing", "era": 2, "kind": "Food", "cost": {"points": 260}, "fx": {"preserve": 0.15}, "desc": "Salted meat and fish keep far longer."},
	"timber_houses": {"name": "Timber Houses", "era": 2, "kind": "Construction", "cost": {"points": 320}, "fx": {}, "unlocks": ["house"], "desc": "Unlocks the Timber House (houses 6)."},
	"mudbrick": {"name": "Mudbrick & Kilns", "era": 2, "kind": "Construction", "cost": {"points": 260}, "fx": {"storage": 80.0, "work_builder": 0.1}, "desc": "Sun-dried and kiln-fired bricks: +80 storage, faster building."},
	"organized_labor": {"name": "Organized Labor", "era": 2, "kind": "Construction", "cost": {"points": 300}, "fx": {"work_builder": 0.3, "research": 0.25}, "desc": "Foremen and scribes: faster building and research."},
	"bronze_surgery": {"name": "Bronze Surgery", "era": 2, "kind": "Medicine", "cost": {"points": 300, "copper_ore": 4}, "fx": {"heal": 0.4}, "desc": "Fine bronze blades for treating wounds."},
	"bathing": {"name": "Bathing & Hygiene", "era": 2, "kind": "Medicine", "cost": {"points": 280}, "fx": {"sanitation": 0.4, "medicine": 0.2}, "desc": "Illness spreads 40% less."},
	"healing_salves": {"name": "Healing Salves", "era": 2, "kind": "Medicine", "cost": {"points": 260}, "fx": {"medicine": 0.3}, "desc": "Ointments speed up recovery."},
	"bronze_weapons": {"name": "Bronze Weapons", "era": 2, "kind": "Weapons", "cost": {"points": 320, "copper_ore": 6, "tin_ore": 4}, "fx": {"hunt_dmg": 10.0, "fight": 10.0, "defense": 0.1}, "desc": "Bronze spearheads, knives and axes."},
	"bronze_shields": {"name": "Bronze Shields", "era": 2, "kind": "Weapons", "cost": {"points": 300, "copper_ore": 6}, "fx": {"defense": 0.15, "fight": 4.0}, "desc": "Polished bronze faces turn blows aside."},
	"composite_bows": {"name": "Composite Bows", "era": 2, "kind": "Weapons", "cost": {"points": 300}, "fx": {"hunt_hit": 0.1, "hunt_dmg": 6.0}, "desc": "Horn and wood bows with real range."},
	"bronze_working": {"name": "Bronze Working", "era": 2, "kind": "Tools", "cost": {"points": 280, "copper_ore": 10, "tin_ore": 6}, "fx": {"work_all": 0.15}, "unlocks": ["workshop"], "desc": "Copper and tin make bronze tools. Unlocks the Bronze Workshop."},
	"bronze_axes": {"name": "Bronze Axes", "era": 2, "kind": "Tools", "cost": {"points": 280, "copper_ore": 4}, "fx": {"work_woodcutter": 0.3, "work_builder": 0.1}, "desc": "Trees come down twice as easily."},
	"woven_clothing": {"name": "Woven Clothing", "era": 2, "kind": "Tools", "cost": {"points": 260, "grass": 20}, "fx": {"warmth": 5.0}, "desc": "Spun and woven cloth under the hides: much warmer."},
	"sailing": {"name": "Sails", "era": 2, "kind": "Ships", "cost": {"points": 300, "grass": 20}, "fx": {"ship_kind": 1.0}, "desc": "Harbors can build Sailboats (6 passengers, faster)."},
	"navigation": {"name": "Star Navigation", "era": 2, "kind": "Ships", "cost": {"points": 280}, "fx": {"ship_speed": 0.3}, "desc": "Ships move 30% faster."},
	"larger_hulls": {"name": "Larger Hulls", "era": 2, "kind": "Ships", "cost": {"points": 260, "wood": 20}, "fx": {"ship_cap": 3.0}, "desc": "Every ship carries 3 more people."},
	"iron_plough": {"name": "Iron Plough", "era": 3, "kind": "Food", "cost": {"points": 500, "iron_ore": 6}, "fx": {"farm": 0.6}, "desc": "Deep ploughing: +60% harvests."},
	"crop_rotation": {"name": "Crop Rotation", "era": 3, "kind": "Food", "cost": {"points": 480}, "fx": {"farm": 0.3}, "desc": "Resting fields grow more: +30% harvests."},
	"smokehouses": {"name": "Smokehouses", "era": 3, "kind": "Food", "cost": {"points": 450}, "fx": {"preserve": 0.15}, "desc": "Smoked meat lasts through any winter."},
	"masonry": {"name": "Stone Masonry", "era": 3, "kind": "Construction", "cost": {"points": 520}, "fx": {}, "unlocks": ["stone_house"], "desc": "Unlocks the Stone House (houses 8)."},
	"engineering": {"name": "Engineering", "era": 3, "kind": "Construction", "cost": {"points": 460}, "fx": {"work_builder": 0.3, "storage": 100.0}, "desc": "Cranes, arches and surveyors: faster building, +100 storage."},
	"aqueducts": {"name": "Aqueducts", "era": 3, "kind": "Construction", "cost": {"points": 480, "stone": 30}, "fx": {"work_laborer": 0.3, "storage": 150.0}, "desc": "Water and goods move easily: laborers faster, +150 storage."},
	"medicine": {"name": "Medicine", "era": 3, "kind": "Medicine", "cost": {"points": 500}, "fx": {"heal": 0.5, "medicine": 0.4, "fertility": 0.2}, "desc": "Better care for the sick and for mothers."},
	"sanitation": {"name": "Sanitation", "era": 3, "kind": "Medicine", "cost": {"points": 460}, "fx": {"sanitation": 0.4, "water_safety": 0.4}, "desc": "Drains and latrines: far less disease."},
	"apothecary": {"name": "Apothecary", "era": 3, "kind": "Medicine", "cost": {"points": 480}, "fx": {"heal": 0.4, "medicine": 0.2}, "desc": "Prepared remedies for every illness."},
	"iron_weapons": {"name": "Iron Weapons", "era": 3, "kind": "Weapons", "cost": {"points": 540, "iron_ore": 8}, "fx": {"hunt_dmg": 12.0, "fight": 14.0, "defense": 0.1}, "desc": "Iron spears, swords and axes."},
	"iron_armor": {"name": "Iron Armor", "era": 3, "kind": "Weapons", "cost": {"points": 520, "iron_ore": 8}, "fx": {"defense": 0.2, "fight": 6.0}, "desc": "Mail and helmets: much less damage taken."},
	"iron_arrowheads": {"name": "Iron Arrowheads", "era": 3, "kind": "Weapons", "cost": {"points": 480, "iron_ore": 4}, "fx": {"hunt_dmg": 8.0, "hunt_hit": 0.05}, "desc": "Arrows that pierce hide and bone."},
	"iron_smelting": {"name": "Iron Smelting", "era": 3, "kind": "Tools", "cost": {"points": 520, "iron_ore": 12}, "fx": {"work_all": 0.2}, "desc": "Iron tools for every trade: all work 20% faster."},
	"bellows": {"name": "Bellows & Forges", "era": 3, "kind": "Tools", "cost": {"points": 480}, "fx": {"work_miner": 0.3, "work_all": 0.05}, "desc": "Hotter fires, better metal."},
	"iron_tool_kits": {"name": "Iron Tool Kits", "era": 3, "kind": "Tools", "cost": {"points": 500, "iron_ore": 6}, "fx": {"work_farmer": 0.3, "work_woodcutter": 0.2}, "desc": "Sickles, saws and hammers of iron."},
	"galleys": {"name": "Galleys", "era": 3, "kind": "Ships", "cost": {"points": 520, "iron_ore": 4}, "fx": {"ship_kind": 1.0}, "desc": "Harbors can build Galleys (10 passengers, fastest)."},
	"sea_charts": {"name": "Sea Charts", "era": 3, "kind": "Ships", "cost": {"points": 460}, "fx": {"ship_speed": 0.3}, "desc": "Ships move 30% faster."},
	"weaponsmithing": {"name": "Weaponsmithing", "era": 1, "kind": "Military", "cost": {"points": 0, "stone": 10}, "fx": {}, "unlocks": ["blacksmith"], "desc": "Unlocks the Blacksmith, which forges weapons for soldiers."},
	"warrior_training": {"name": "Warrior Training", "era": 1, "kind": "Military", "cost": {"points": 0}, "fx": {"fight": 2.0}, "unlocks": ["training_camp"], "desc": "Unlocks the Training Camp. Only there can people become Soldiers."},
	"defensive_perimeters": {"name": "Defensive Perimeters", "era": 1, "kind": "Military", "cost": {"points": 0, "wood": 20}, "fx": {}, "unlocks": ["wall", "gate"], "desc": "Walls and gates. Your people start building a wooden palisade around the village."},
	"mercenary_pacts": {"name": "Mercenary Pacts", "era": 1, "kind": "Military", "cost": {"points": 0, "hides": 4}, "fx": {}, "unlocks": ["mercenary_hall"], "desc": "Unlocks the Mercenary Hall: hire Warriors and Archers for Talents."},
	"stone_walls": {"name": "Stone Walls", "era": 2, "kind": "Military", "cost": {"points": 0, "stone": 30}, "fx": {"wall_tier": 1.0}, "desc": "Walls and gates are rebuilt in stone (400 strength)."},
	"watch_posts": {"name": "Watch Posts", "era": 2, "kind": "Military", "cost": {"points": 0}, "fx": {}, "unlocks": ["watchtower"], "desc": "Unlocks the Watchtower: keeps predators away and throws spears at enemies."},
	"phalanx": {"name": "Phalanx", "era": 2, "kind": "Military", "cost": {"points": 0}, "fx": {"soldier": 0.25, "defense": 0.05}, "desc": "Shield walls and drill: soldiers fight 25% better."},
	"fortifications": {"name": "Fortifications", "era": 3, "kind": "Military", "cost": {"points": 0, "stone": 40, "iron_ore": 4}, "fx": {"wall_tier": 1.0}, "desc": "Thick fortified walls and gates (800 strength)."},
	"arrow_towers": {"name": "Arrow Towers", "era": 3, "kind": "Military", "cost": {"points": 0, "iron_ore": 4}, "fx": {}, "unlocks": ["arrow_tower"], "desc": "Unlocks the Arrow Tower: archers on the walls."},
	"legions": {"name": "Legions", "era": 3, "kind": "Military", "cost": {"points": 0, "iron_ore": 6}, "fx": {"soldier": 0.3, "defense": 0.05, "train": 0.3}, "desc": "Professional, drilled armies: soldiers fight 30% better and train faster."},
	"standing_stones": {"name": "Standing Stones", "era": 1, "kind": "Civics", "cost": {"points": 0, "stone": 20}, "fx": {}, "unlocks": ["monolith"], "desc": "Unlocks the Monolith: spend knowledge to skip years."},
	"cartography": {"name": "Cartography", "era": 2, "kind": "Civics", "cost": {"points": 0, "hides": 4}, "fx": {}, "unlocks": ["map_table"], "desc": "Unlocks the Map Table and the Territory view of the world."},
	"statecraft": {"name": "Statecraft", "era": 2, "kind": "Civics", "cost": {"points": 0}, "fx": {}, "unlocks": ["capitol"], "desc": "Unlocks the Capitol, seat of your government."},
	"code_of_laws": {"name": "Code of Laws", "era": 2, "kind": "Civics", "cost": {"points": 0}, "fx": {"research": 0.1, "work_all": 0.05}, "desc": "Written laws keep order: +10% research, +5% work."},
	"coinage": {"name": "Coinage", "era": 3, "kind": "Civics", "cost": {"points": 0, "copper_ore": 4}, "fx": {"trade": 0.3}, "desc": "Minted coins: traders earn 30% more Talents."},
	"bureaucracy": {"name": "Bureaucracy", "era": 3, "kind": "Civics", "cost": {"points": 0}, "fx": {"research": 0.2, "storage": 100.0}, "desc": "Scribes and ledgers: +20% research, +100 storage."},
	"philosophy": {"name": "Philosophy", "era": 3, "kind": "Civics", "cost": {"points": 0}, "fx": {"research": 0.25}, "desc": "Thinkers question everything: +25% research."},
	"reinforced_hulls": {"name": "Reinforced Hulls", "era": 3, "kind": "Ships", "cost": {"points": 480, "iron_ore": 4}, "fx": {"ship_cap": 5.0}, "desc": "Every ship carries 5 more people."},
}

# ship types a Harbor can build (unlocked by research: Boatbuilding → Sails → Galleys)
const SHIP_TYPES := [
	{"name": "Dugout Canoe", "cap": 3, "speed": 3.2, "hours": 10.0, "cost": {"wood": 20}},
	{"name": "Sailboat", "cap": 6, "speed": 4.5, "hours": 16.0, "cost": {"wood": 35, "grass": 15}},
	{"name": "Galley", "cap": 10, "speed": 5.5, "hours": 24.0, "cost": {"wood": 60, "grass": 20, "iron_ore": 4}},
]


static func techs_of_era(era: int) -> Array:
	var out: Array = []
	for id in TECH_ORDER:
		if int(TECHS[id]["era"]) == era:
			out.append(id)
	return out


# ---------------------------------------------------------------- animals
const ANIMALS := {
	"rabbit": {"name": "Rabbit", "speed": 2.6, "hp": 10.0, "meat": 2, "hide": 1, "bone": 0, "herd": 2, "count": 70,
		"biomes": [T.PLAINS, T.GRASSLAND, T.FOREST, T.VALLEY, T.TUNDRA, T.STEPPE, T.SAVANNA, T.HIGH_DESERT], "predator": false, "danger": 0.0, "huntable": true},
	"deer": {"name": "Deer", "speed": 3.0, "hp": 30.0, "meat": 8, "hide": 2, "bone": 2, "herd": 3, "count": 55,
		"biomes": [T.PLAINS, T.GRASSLAND, T.FOREST, T.DENSE_FOREST, T.VALLEY, T.SNOW_FOREST, T.ALPINE], "predator": false, "danger": 0.0, "huntable": true},
	"boar": {"name": "Boar", "speed": 2.3, "hp": 45.0, "meat": 7, "hide": 1, "bone": 2, "herd": 2, "count": 30,
		"biomes": [T.FOREST, T.DENSE_FOREST, T.RAINFOREST], "predator": false, "danger": 10.0, "huntable": true},
	"goat": {"name": "Mountain Goat", "speed": 2.5, "hp": 25.0, "meat": 5, "hide": 2, "bone": 1, "herd": 3, "count": 25,
		"biomes": [T.HILLS, T.ROCKY, T.TUNDRA, T.BADLANDS, T.ALPINE, T.HIGH_DESERT], "predator": false, "danger": 0.0, "huntable": true},
	"wolf": {"name": "Wolf", "speed": 3.1, "hp": 35.0, "meat": 3, "hide": 2, "bone": 1, "herd": 3, "count": 15,
		"biomes": [T.FOREST, T.SNOW_FOREST, T.TUNDRA, T.DENSE_FOREST, T.STEPPE], "predator": true, "danger": 13.0, "huntable": false,
		"prey": ["rabbit", "deer", "goat"]},
	"bear": {"name": "Bear", "speed": 2.4, "hp": 90.0, "meat": 14, "hide": 3, "bone": 3, "herd": 1, "count": 8,
		"biomes": [T.FOREST, T.DENSE_FOREST, T.SNOW_FOREST, T.HILLS], "predator": true, "danger": 26.0, "huntable": false,
		"prey": ["deer", "boar"]},
	"jaguar": {"name": "Jaguar", "speed": 3.3, "hp": 45.0, "meat": 4, "hide": 2, "bone": 1, "herd": 1, "count": 8,
		"biomes": [T.RAINFOREST, T.SAVANNA], "predator": true, "danger": 18.0, "huntable": false, "prey": ["boar", "deer", "rabbit", "antelope"]},
	"antelope": {"name": "Antelope", "speed": 3.3, "hp": 25.0, "meat": 6, "hide": 2, "bone": 1, "herd": 4, "count": 40,
		"biomes": [T.SAVANNA, T.DESERT, T.HIGH_DESERT, T.STEPPE], "predator": false, "danger": 0.0, "huntable": true},
	"bison": {"name": "Bison", "speed": 2.4, "hp": 70.0, "meat": 16, "hide": 3, "bone": 3, "herd": 5, "count": 30,
		"biomes": [T.STEPPE, T.PLAINS, T.GRASSLAND], "predator": false, "danger": 12.0, "huntable": true},
	"camel": {"name": "Camel", "speed": 2.2, "hp": 50.0, "meat": 12, "hide": 2, "bone": 2, "herd": 3, "count": 18,
		"biomes": [T.DESERT, T.HIGH_DESERT], "predator": false, "danger": 0.0, "huntable": true},
	"crocodile": {"name": "Crocodile", "speed": 2.0, "hp": 70.0, "meat": 10, "hide": 3, "bone": 2, "herd": 1, "count": 12,
		"biomes": [T.SWAMP], "predator": true, "danger": 22.0, "huntable": false, "prey": ["deer", "boar", "antelope", "rabbit"]},
	"bird": {"name": "Bird", "speed": 3.6, "hp": 3.0, "meat": 0, "hide": 0, "bone": 0, "herd": 4, "count": 36,
		"biomes": [], "predator": false, "danger": 0.0, "huntable": false, "flying": true},
}

# ---------------------------------------------------------------- illnesses
# drain = health lost per day. work = productivity multiplier. spread = chance/hour to infect someone close by.
## Illnesses. "death" is the chance (for a healthy adult, untreated) of dying before the illness
## runs its course; "days" is how long it lasts, which decides whether that risk plays out over a
## week, a month or a year. Children under 6 (and "child" x extra for measles) and elders are
## at higher risk. Healers, medicine techs, a Healer's Hut and rest lower it.
## "drain" is health lost per day (weakness), "work" the work speed while ill, "spread" the hourly
## chance to pass it to someone standing close by, "lifelong" = can only be caught once.
const ILLNESS := {
	"cold": {"name": "Common Cold", "days": 5.0, "death": 0.003, "drain": 2.0, "work": 0.85, "spread": 0.05, "severe": false},
	"flu": {"name": "Influenza", "days": 7.0, "death": 0.015, "drain": 5.0, "work": 0.5, "spread": 0.06, "severe": true},
	"fever": {"name": "Fever", "days": 6.0, "death": 0.03, "drain": 6.0, "work": 0.5, "spread": 0.02, "severe": true},
	"food_poisoning": {"name": "Food Poisoning", "days": 3.0, "death": 0.01, "drain": 8.0, "work": 0.5, "spread": 0.0, "severe": true},
	"dysentery": {"name": "Dysentery", "days": 6.0, "death": 0.04, "drain": 7.0, "work": 0.4, "spread": 0.015, "severe": true},
	"infection": {"name": "Wound Infection", "days": 6.0, "death": 0.08, "drain": 6.0, "work": 0.6, "spread": 0.0, "severe": true},
	"pneumonia": {"name": "Pneumonia", "days": 16.0, "death": 0.18, "drain": 5.0, "work": 0.3, "spread": 0.01, "severe": true},
	"measles": {"name": "Measles", "days": 12.0, "death": 0.03, "child": 2.5, "drain": 4.0, "work": 0.5, "spread": 0.08, "severe": true, "lifelong": true},
	"malaria": {"name": "Malaria", "days": 21.0, "death": 0.12, "drain": 3.5, "work": 0.4, "spread": 0.0, "severe": true},
	"typhoid": {"name": "Typhoid Fever", "days": 24.0, "death": 0.12, "drain": 3.5, "work": 0.3, "spread": 0.01, "severe": true},
	"tetanus": {"name": "Tetanus (Lockjaw)", "days": 14.0, "death": 0.35, "drain": 4.0, "work": 0.2, "spread": 0.0, "severe": true},
	"rabies": {"name": "Rabies", "days": 28.0, "death": 0.97, "drain": 2.0, "work": 0.4, "spread": 0.0, "severe": true},
	"tuberculosis": {"name": "Tuberculosis", "days": 240.0, "death": 0.40, "drain": 0.6, "work": 0.6, "spread": 0.004, "severe": false},
	"plague": {"name": "Plague", "days": 14.0, "death": 0.50, "drain": 6.0, "work": 0.2, "spread": 0.05, "severe": true},
}


## "a week" / "a month" / "a year": how long an illness's death risk plays out.
static func illness_window(type: String) -> String:
	var d := float(ILLNESS[type]["days"])
	if d <= 8.0:
		return "a week"
	if d <= 31.0:
		return "a month"
	return "a year"

# ---------------------------------------------------------------- civilizations
# index 0 is always the player's tribe
const TRIBE_NAMES := ["Your Tribe", "River Folk", "Stone Fang", "Red Hand", "Ash Clan", "Moon Eaters", "Wolf Kin", "Sun Callers", "Elk Runners"]
const TRIBE_COLORS := [Color(0.98, 0.84, 0.30), Color(0.30, 0.62, 1.00), Color(0.62, 0.62, 0.70), Color(0.95, 0.28, 0.24),
	Color(0.62, 0.40, 0.85), Color(0.30, 0.85, 0.80), Color(0.98, 0.55, 0.18), Color(0.95, 0.45, 0.75), Color(0.45, 0.85, 0.35)]

const MALE_NAMES := ["Ugo", "Tarak", "Bram", "Oren", "Kael", "Dag", "Rok", "Torv", "Haru", "Esk", "Gorm", "Nuk",
	"Varr", "Ilo", "Sorn", "Brann", "Kito", "Arn", "Mado", "Thul", "Zek", "Orik", "Banu", "Fenn"]
const FEMALE_NAMES := ["Ama", "Lira", "Nessa", "Yara", "Tova", "Mira", "Esha", "Kaia", "Runa", "Sela", "Oda", "Ilka",
	"Vena", "Nala", "Zari", "Inna", "Hela", "Brea", "Suna", "Teka", "Wren", "Olla", "Rhia", "Dena"]


static func terrain_name(t: int) -> String:
	return TERRAIN[t]["name"]


## Research point cost of a tech (rises along each category's chain and with every era).
static func tech_rp(id: String) -> int:
	var t: Dictionary = TECHS[id]
	var era := int(t["era"])
	return maxi(1, int(ceil((TECH_ERA_BASE[era] + tech_step(id) * TECH_ERA_INC[era]) * Config.rule("tech_cost"))))


## Knowledge points needed for one research point (custom rule).
static func kp_per_rp() -> int:
	return int(Config.rule("kp_per_rp"))


## Knowledge points one unit of a material gives (custom rule applied).
static func kp_value(item: String) -> float:
	return float(KP_VALUE.get(item, 10)) * Config.rule("kp_value")


## Name of a wall or gate at a fortification level.
static func wall_name(type: String, tier: int) -> String:
	return str(WALL_TIERS[clampi(tier, 0, 2)][type])


## Position of a tech along its category chain within its era (0 = first).
static func tech_step(id: String) -> int:
	var t: Dictionary = TECHS[id]
	var n := 0
	for o in TECH_ORDER:
		if o == id:
			return n
		var ot: Dictionary = TECHS[o]
		if int(ot["era"]) == int(t["era"]) and str(ot["kind"]) == str(t["kind"]):
			n += 1
	return n


## The tech that must be researched first: the previous one in the same category (any era).
static func tech_prereq(id: String) -> String:
	var t: Dictionary = TECHS[id]
	var prev := ""
	for o in TECH_ORDER:
		if o == id:
			return prev
		if str(TECHS[o]["kind"]) == str(t["kind"]):
			prev = o
	return prev


## Materials (not research points) a tech also needs, e.g. ores.
static func tech_materials(id: String) -> Dictionary:
	var out := {}
	var cost: Dictionary = TECHS[id]["cost"]
	for k in cost.keys():
		if k != "points":
			out[k] = cost[k]
	return out


static func item_name(item: String) -> String:
	return ITEM_NAMES.get(item, item.capitalize())


static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), item_name(k)])
	return ", ".join(parts)
