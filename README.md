# Firstborn

A 2D top-down survival, colony-management and civilization-building game for **Godot 4.7** (GDScript).
You start with two humans in a randomly generated world and must build a civilization from nothing.

> All art is generated procedurally at startup, so the project has no external assets.

## Running

1. Install Godot **4.7** (standard build; no .NET needed).
2. Open Godot → *Import* → select `project.godot`.
3. Press **F5**. Pick a seed (or leave it empty for a random one), choose how many rival tribes you want, and press **Start New Game**.
4. Choose where your tribe begins: click anywhere on the land (or on the World Map), or use the suggested spot.

The renderer is set to *Compatibility* so it runs on almost any GPU.

## Controls

| Action | Input |
| --- | --- |
| Pan camera | WASD / arrow keys (hold Shift = faster), middle-mouse drag, click the minimap |
| Zoom | Mouse wheel (zooms toward the cursor) |
| Select a person / building / ship / tile | Left click |
| Select several people | Hold left mouse and drag a box (Shift adds to the selection) |
| Move selected people | Right click on the ground (they spread out around the spot) |
| Attack with selected people | Shift + right click on an animal or a person from another tribe |
| Board a ship | Select people, right click the ship |
| Sail / land | Select a ship, right click water to sail, or a distant shore to put everyone ashore |
| Cancel placement / deselect | Right click with nothing selected / Esc |
| Pause / speed 1x 2x 4x 8x 16x 32x | Space / 1 2 3 4 5 6 |
| Build, Jobs, Research, Stockpile, Colony, Help | B, J, R, I, C, H |
| Plan Town (zones & roads) | Z |
| Milestones | G |
| World map | M (mouse wheel zooms, right-drag pans, + / − / Fit buttons) |
| Quick save / quick load | F5 / F9 (slot 1) |
| Game menu (save slots, load, quit) | Esc |
| Demolish selected building | Delete |
| Place several fences in a row | Keep placing (fence mode stays on), or hold Shift for any building |

## What's in the game now

**Music, sound and settings**
- Ten original soundtrack pieces (generated for the game) play in a shuffled order and crossfade smoothly into each other.
  Every button has a soft, clean click.
- **Settings** (main menu and the in-game Menu): **Audio** (master, music and effects volume, click sounds, next track),
  **Game** (show or hide the day/night cycle; hide people and animals at 8x, 16x or 32x speed to keep the frame rate up — 16x by default),
  **Accessibility** (keep steady daylight when zoomed in past a chosen zoom, 85% by default, so the fast day/night cycle doesn't flash).

**Menus**
- Title screen (New Game, Load Game, Quit) over a freshly generated world.
- **New world**: tribe name, your race, seed, size, number of rivals, world preview, and buttons for:
  - **Game Rules** — sliders for births (conception chance, pregnancy length, twins, rest between children), aging
    (adult aging speed, child growth speed, working age), starting people, hunger/thirst, spoilage, illness frequency,
    lethality, contagion and extra risk for children, research (KP per RP, KP from materials, tech cost, default research share),
    work speed, wildlife, starting Talents, daily Talent income and rival aggression. Rules are saved with the game.
  - **Races** — peoples from other worlds: rename them, set their skin colour, add or remove races, choose yours, and
    whether rivals get random races. Each race has its own sound for names.
  - **Flag Designer** — background, pattern (9), pattern colour, emblem (10) and emblem colour. Rival tribes get random flags.
- Names for people and tribes are built from syllables in each race's style (thousands of combinations, never reused),
  so new games no longer repeat the same names.

**Clear Land tool** (toolbar or X)
- Drag a box: every tree, bush, plant and loose stone inside is marked (ore deposits stay). Woodcutters, gatherers,
  laborers and builders cut everything down, carry the wood and goods home and leave a clearing to build on.
  Animals inside the box are marked for the hunters (and predators for soldiers). Shift+drag removes marks.

**Military (from the Stone Age)**
- Research **Weaponsmithing** → **Blacksmith**: smiths forge weapons by age — Stone Club, Stone Spear and Sling (Stone Age),
  Bronze Spear, Bronze Sword and Composite Bow (Bronze Age), Iron Spear, Iron Sword and Crossbow (Iron Age).
  Queue weapons from the blacksmith's panel or leave Auto-forge on to arm unarmed soldiers.
- Research **Warrior Training** → **Training Camp**: only then can people become **Soldiers**. Soldiers drill there,
  take the best weapon from the stockpile, guard the village from predators and enemies, and wear helmets that match their arms.
  Ranged weapons shoot from a distance.
- Research **Defensive Perimeters**: the tribe rings its village with walls and gates (a gate on every side, trees in the way
  are cleared first). Walls block people; only enemies at war are stopped by gates and have to smash them.
  **Stone Walls** (Bronze) and **Fortifications** (Iron) rebuild them stronger. **Watch Posts** (Bronze) and **Arrow Towers** (Iron)
  shoot enemies at war and predators.

**Territory states**
- The land is divided into about a hundred named states that follow coasts and terrain. A tribe owns the state its
  camp stands in and can hold one more state for every three people.
- Unclaimed states next to your land can be claimed by anyone: send a Billy to raise your banner at the state's centre
  (Territory view on the World Map: click a state, then "Send a Billy to claim it"). AI tribes, and your tribe if you
  switch it on in the Jobs panel, claim free land on their own.
- A state another tribe holds can only be taken in a war: your soldiers must reach its centre and hold it with no
  defenders nearby. A tribe's homeland can't be taken. You can't build on another tribe's land.
- State borders are drawn in each owner's colour on the map and the world map; the Map Table's Territory view
  shows the political map with state names.

**Build window**
- The Build menu (B) is a window in the middle of the screen with a tab for each age and structures grouped into
  Homes, Food & Water, Storage & Industry, Knowledge & Civic, and Defense & Military, with costs and what to research.

**Cheat code**
- Hold **Shift** and press **+** five times within two seconds: every tech researched, every building unlocked in any
  age, building is free and instant, and ages can be advanced at once. Enter the code again to switch it off.

**Governments & diplomacy (from the Bronze Age)**
- On entering the Bronze Age you must choose a government: Chiefdom, Monarchy, Theocracy, Council of Elders or City-State.
  In the Iron Age you choose again: Kingdom, Empire, Republic, Democracy or Tyranny. Each has its own bonuses; AI tribes choose too.
- Civics research: **Statecraft** unlocks the **Capitol** (government bonuses +50%, better peace terms), **Cartography** unlocks the
  **Map Table**, which adds a **Territory view** to the World Map showing who holds which land. Also Code of Laws, Coinage,
  Bureaucracy and Philosophy.
- Click a tribe's flag (at its camp, or its name in the Colony panel) to see its race, age, government, relations and strength,
  send gifts, **declare war** (Bronze Age and later), **send your soldiers to attack**, offer or accept peace.
- At war, soldiers march on the enemy, fight its people, break through gates and walls and destroy buildings. AI tribes
  declare wars on tribes they hate, raid their enemies and sue for peace when losing. Wars show as red lines on the world map.

**World generation (seeded, deterministic)**
- The same seed always gives the same world. Worlds come in three sizes (256², 384², 512²).
- Every world has several continents and many small islands in the ocean, with deep ocean, beaches, plains, grasslands, forests and dense forests.
  There are also snow forests, tundra, rainforests, hills, rocky terrain, mountains and snowy peaks, plus
  low (hot) deserts, high (cold) deserts, savanna, steppe, swamps, badlands and alpine meadows.
- Rivers start in the highlands, flow downhill and end in lakes or the sea. Rivers with no outlet pool into small lakes.
- The world also has inland lakes, clean springs and fertile river valleys.
- Temperature depends on latitude and altitude, and moisture varies across the map. Biomes are chosen from both.
- Resources depend on the biome: oak, pine, snowy pine, palm, jungle, acacia and juniper trees; berry and tropical-fruit bushes;
  prickly-pear cactus, dry shrubs, reeds and mushrooms. Desert and plains wildlife includes antelope, bison and camels; swamps have crocodiles.
  Also sticks, small stones, large stones, boulders, tall grass, and copper, tin and iron deposits.
  Ore is richer near mountains.
- The tribe starts somewhere temperate, near fresh water.

**Your tribe**
- Name your tribe on the main menu, and rename it or any of your people in game (Colony panel / info panel).
- Command your people directly: move them, gather them into groups, send them to attack animals or other tribes.
  Ordered people follow orders even when tired or hungry, unless badly hurt. Pathing routes around water and finds the nearest reachable spot.
- Fights sour relations: attack a tribe and its people defend themselves, and they may turn hostile.

**Building with blueprints**
- Placing a building only lays down a blueprint. Builders and laborers carry the materials from storage to the site, then build it.
  Gatherers prioritise anything that's missing. Cancelling a blueprint returns everything delivered.

**Seafaring**
- Research Boatbuilding (Ships, Stone Age) to unlock the Harbor. It must be built on the shore, touching the sea.
- Harbors build Dugout Canoes (3 people), then Sailboats (6) after Sails and Galleys (10) after Galleys.
  Paddles, Star Navigation, Larger Hulls, Sea Charts and Reinforced Hulls make ships faster and roomier.
- Ships sail across oceans, lakes and rivers to other continents and islands.

**Civilizations**
- You choose your tribe's starting spot. Hovering a tile shows how far away fresh water is.
- 0–8 rival AI tribes start elsewhere in the world, in the same primitive state as you, and live by exactly the same survival rules.
  You can watch and inspect them but never control them.
- Every tribe, including yours, is run by a tribe AI ("chief"). It assigns jobs to suit the tribe's size and needs,
  decides what to build next, saves up materials for it and picks a site. You can switch the auto-jobs and auto-build
  options off for your own tribe in the Jobs panel and manage it by hand.
- Tribes discover each other when their people wander into another tribe's territory. Relations drift over time and
  sour when territories overlap.
- Distant tribes keep developing while you're elsewhere: they're simulated in coarser steps to save performance.
- Tribes can starve, freeze or be wiped out by predators and collapse. The Colony panel lists every tribe you've met.

**Research and eras** (full-screen research tree, R)
- Build a **Research Table**. A share of every material your people bring into the stockpile (a slider in the tree, 25% by default)
  is set aside in a research pile. Researchers carry it from the stockpile to the table — never straight from the wild.
- Every unit gives **knowledge points (KP)**, and rarer materials give more: grass 20, sticks 30, wood/stone 60, bones/hides 150,
  copper 400, tin 450, iron 600. Researchers with nothing to carry study at the table for a slow trickle of KP.
- Convert **1,000 KP → 1 research point (RP)** and spend RP on techs. The tree shows eras as columns and categories as rows;
  each tech needs the one before it in its row. Costs rise along each row and jump with every era
  (Caveman 1–2 RP, Stone 4–10, Bronze 8–14, Iron 14–22, plus ore for metal techs).
- There are four eras: **Caveman Age → Stone Age → Bronze Age → Iron Age**, with 70 techs grouped into
  Food, Construction, Medicine, Weapons, Tools and Ships (15–19 per era).
  Once everything in an era is researched, you can advance to the next.
- Bronze and Iron Age techs also need copper, tin or iron ore, which miners dig from deposits or Mines.
- Techs give real bonuses (faster work, better hunting and defence, warmer clothing, bigger harvests, less spoilage, faster healing, more births)
  and unlock buildings: Farm, Granary, Stone Hut, Well, Healer's Hut, Mine, Bronze Workshop, Timber House, Palisade, Stone House and Watchtower.
- Buildings are drawn from directly above as roof plans with sun and shade sides and cast shadows, and look more advanced as a
  tribe moves through the eras (lean-tos → round thatched huts → timber with shingles → masonry with tiled hip roofs and chimneys).
- AI tribes research and advance on their own, at their own pace (they convert KP automatically).

**Talents & trade**
- Every tribe has its own bank of **Talents** (the money), shown in the top bar and the Colony panel.
- The **Trader** job packs the tribe's surplus (materials and spare food), walks to another tribe and sells it there at prices
  set by supply and demand and by how much the two tribes like each other. With Talents in hand the trader buys back ore the
  tribe needs for research, or food when stores are low, and carries it home. Trading improves relations and counts as meeting a tribe.
- Tribes on other landmasses can be reached by sea once you have a Harbor: the trader sails off on a trading voyage.
- AI tribes take up trading too once they reach the Stone Age.

**Calendar and ages**
- The calendar runs 5x faster than daily life: dates, months, years, seasons, the visible day/night cycle and aging all
  move 5x faster, while walking, working, eating and sleeping keep their normal pace.
- To enter the next age a tribe must research everything in its current age **and** pay double the RP of all that
  age's techs (the multiplier is adjustable in Game Rules). The Research Tree's Advance button shows the cost.
- **Monolith** (research Standing Stones, Stone Age): spend 1,000 KP per year to skip calendar years. Nobody ages.

**Leaders & elections**
- Every tribe elects a **Chief** (Caveman and Stone Age) and, from the Bronze Age, a **President** (at most two terms in a row).
- Elections are held every 4 calendar years (Game Rules), when the leader dies, and on entering the Bronze Age.
  Adults vote; family and partners stick together, elders are trusted as Chiefs, the skilled and healthy do well.
- The leader's best trade works 10% faster for the whole tribe; a President also adds 4% to all work.
  The leader wears a gold circlet and is listed in the Colony panel with the last vote.

**Plan Town (Z)**
- Paint **Farming**, **Housing** and **Workshop** zones (drag a box) and lay out **roads** (drag from point to point; one bend).
- A building in the zone that suits it gets bonuses: farms +25% harvest, homes +1 bed and 20% faster rest, blacksmith
  and research 20% faster, and every bonus the building gives is 25% stronger. The building's info panel says which zone it wants.
- Laborers and builders lay planned roads (trees in the way are cleared first). Billies walk about twice as fast on roads,
  and pathfinding prefers them.

**Trading (rewritten)**
- Click another tribe's flag → **Trade** (next to "Go to their camp"). The window lists what they'll sell (price,
  how many they can spare), what they'll buy from you, and up to three **people** they'll part with (a man, a woman,
  a child; they need at least 6 people and decent relations). Pick amounts and press **Send trader**.
- Nothing moves by magic: a Billy with the **Trader** job walks over carrying your goods and the Talents to pay,
  makes the exchange, and walks back with the purchases. Bought people walk to your village on their own.
  A trader carries 30 per trip (10 Talents count as 1); research **Trade Wagons** (Stone Age, Tools) to carry 120.
  Big orders take several trips. Open orders are listed in the window and can be cancelled.
- With an open order and auto-jobs on, someone always takes up the Trader job.
- Accepted envoy trades also become orders your traders carry out.

**Bandits**
- At the start of a game a few outlaw camps (Game Rules: "Bandit camps", default 3) appear in the wilds, at least
  40 tiles from any tribe. All bandits form one outlaw band: at war with everyone, outside diplomacy and territory.
- Every week or so a camp sends two robbers to a nearby village (4+ people) to steal Talents and goods from the stores,
  then they run back. A robbed village is left alone for about 6 days.
- They ambush traders of any tribe who pass within 14 tiles of a camp and steal what they carry (then let them go).
- They only fight when attacked. Camps slowly recruit (up to 5 each). Select a camp → "Send soldiers to destroy it"
  to recover a share of their stash.

**Political happiness (Mood)**
- Every tribe, from the Caveman Age: 0–100%, shown in the top bar and the Colony panel with what makes it up:
  government type (Democracy +10 … Tyranny −15; tribal rule +5 before the Bronze Age), the leader's mandate,
  food, homes, sickness, wars, prosperity, a stolen election, bandit raids, and rising expectations in later ages.
- Below 20% there's a 40% chance each calendar year (both adjustable in Game Rules) that a quarter of the adults
  (with their young children) leave. Half the time they ask to join the friendliest tribe — if that's you, you get a
  card to welcome or refuse them; if refused they may not join or cross into that land — otherwise, or if refused,
  they found a new tribe in free land nearby, taking a share of the stores.

**Bridges** — the road tool lays a bridge across lakes and rivers (3 wood per tile, built plank by plank from the
shore). Bridges can connect lands that couldn't be reached on foot.

**No building on roads** — buildings can't be placed on roads or planned roads (a gate can; the automatic wall
builder puts a gate where a road crosses the wall line).

**Big announcements** — wars, peace, alliances, captured land, new ages, leaders dying, election day, election
results, people leaving, bandit raids and ambushes appear in large banners at the top of the screen.

**Settings** (main menu and in-game): a **Game Rules** tab with every rule, editable mid-game; and on the Game tab,
**Calendar speed** — how fast dates and the clock move (5x by default; changing it never makes the date jump).

**Fog of war** (world creation option) — only the land around your camp is known at first; your Billies and
buildings uncover the map (main view, minimap and World Map). Saved with the game.

**Monolith** — a plain grey standing stone with carved year notches on a ring of small stones.

**Milestones (G)** — 27 goals in five groups (Survival, Growth, Knowledge, Diplomacy, War), each with a reward in
Talents, KP or RP: first fire, first child, 10/25/50 people, roads, zoned buildings, 25 techs, each new age, a Monolith,
first contact, 500 Talents, 5 deals, an alliance, 3 elections, a Capitol, 5 Warriors + 3 Archers, first blood, 6 states, a ship…

**Soldiers**
- Two kinds: **Warriors** (clubs, flint axes, spears, swords) and **Archers** (slings, hunting bows, composite bows,
  crossbows, longbows). Archers only take ranged weapons from the stockpile, Warriors only close-combat ones, and the
  Blacksmith forges for whoever is unarmed.
- **Training Camp** or **Mercenary Hall**: "Train Warrior" / "Train Archer" turns a free adult into that soldier.
- **Mercenary Hall** (research Mercenary Pacts, Stone Age): "Hire Warrior" (60 Talents) / "Hire Archer" (80 Talents),
  more in later ages. Hired soldiers arrive armed with the best weapon of the age and join the tribe for good.
- Select a soldier to switch them between Warrior and Archer, or discharge them. Auto-jobs never undo soldiers you made.
- AI tribes hire mercenaries when they're rich and threatened.

**Diplomacy deals**
- AI tribes send envoys: trade offers, alliance proposals, demands for tribute and demands for land. A card at the top of
  the screen lets you Accept, Decline or **Counter** (ask 30% more, ask for a gift, offer half, pay instead of giving land);
  it shows the chance they agree. Refusing a demand from a stronger tribe can start a war; ignored demands count as refused.
- From a rival's flag: propose an alliance, ask for a trade, demand tribute, demand land, break an alliance.
- **Alliances** are defensive: attack one ally and the other joins the war. Allies may cross each other's land.
- AI tribes trade, ally, and make demands of each other too.

**Election influence** (Colony panel)
- See who will stand at the next election and roughly how the vote would go. Click a name to back them.
- Hold a rally (30 Talents) or hand out gifts (15 food) in their name to swing votes.
- Or rig the count: your candidate wins, but there's a 25–85% chance it's discovered (bigger tribes and later ages
  notice more). If caught: 3 years of unrest, work 15% slower and fewer births.

**Borders**
- Billies may only enter another tribe's states with permission (or at war). Job trips, hunts and trade routes that
  would cross foreign land ask for passage first; until it's granted they pick something else.
- Rival tribes ask **you** before crossing your land (a card at the top of the screen: Allow for 10 years / Refuse).
  You can ask them from their flag, and revoke passage you granted.
- A Billy **caught** on foreign land without permission (seen by the owners or near their buildings) can start a war:
  30% in the Caveman Age, +10% for every later age (the higher age of the two tribes). Trespassers on your land are reported to you.

**Families**
- Close relatives (siblings, parent and child) may become partners (Game Rules: on by default); strangers are still preferred.
  Children of close kin have a 30% chance (adjustable) of being born frail: slower at work and more likely to die of illness.

**Combat effects**
- Strikes lunge toward the target; the one hit flashes red and is knocked back. Slashes, spear thrusts, club impacts,
  claw and bite rakes, blood spray and stains, dust from misses, chips from walls, and floating damage numbers up close.
  People and animals alike. Not drawn at high speed (derender) or when zoomed far out.
- Researchers can **auto-convert** KP into RP and **auto-research** the cheapest tech (checkboxes in the Research Tree).

**Calendar**
- Real-world calendar: 365-day years, 12 months, and seasons of three months (Spring Mar–May, Summer Jun–Aug, Fall Sep–Nov, Winter Dec–Feb).
  A game starts on March 1.
- Adults age one "life year" every 40 calendar days; children grow up three times faster. Pregnancy lasts 45 work days,
  twins happen, and children start helping at age 6 (all adjustable in Game Rules).
- Winter lasts three months: stockpile food, dry meat, use granaries and cold storage. Gatherers dig roots when nothing else grows.

**Markers**
- A coloured dot above every person (in their tribe's colour) and a waving flag with the tribe's name at every camp.
  Both stay the same size on screen, so you can follow everyone from far above. Flags also show on the minimap and the World Map.

**People and colony**
- Every person has a name, age, gender, health, hunger, thirst, energy, warmth, skills, a job, family ties and an illness status.
- There are 10 jobs: Gatherer, Hunter, Builder, Farmer, Fisherman, Woodcutter, Miner, Cook, Healer and General Laborer.
- People work their own job first. When it has no work, they help with other jobs in the order of tribe priority (1–5) set in the Jobs panel.
- Skills improve with practice, and higher skill means faster work.
- Adults pair up and have children when there is food and shelter. Pregnancy lasts 8 days.
- Infants are fed by the tribe and follow their mother. Children play until age 8, then help as gatherers.
- People age through these stages: Infant, Child, Youth, Adult, Elder. Elders can die of old age.

**Survival**
- Food: berries, mushrooms, fruit, raw and cooked meat and fish, dried meat, and vegetables.
  Each food has its own nutrition value and spoils at its own rate.
  Spoilage is faster in summer and slower in winter. Storage Areas slow it further, and dried meat barely spoils at all.
- Water: drink from rivers, lakes and springs, or from water that laborers carry to the stockpile.
  Lake water carries the highest disease risk, rivers less, and springs are safe.
- Illness: common cold, influenza (autumn/winter), fever, food poisoning (raw meat or fish), dysentery and typhoid (dirty water),
  wound infection and tetanus (wounds, bites), rabies (wolf/jaguar/fox bites), pneumonia (a cold or flu that turns bad in the cold),
  measles (once in a lifetime), malaria (hot swamps and rainforests at night), tuberculosis (a year-long illness) and plague
  (big Bronze/Iron Age settlements).
- Each illness has a chance of killing, played out over a week, a month or a year depending on the illness — from <1% for a cold
  to near-certain for rabies. The info panel shows each sick person's current chance. Children under 6 and elders are at
  much higher risk (children can and do die). Healers, a Healer's Hut, medicine techs and rest lower the risk.
  Contagious illnesses spread between people standing close together; sanitation techs slow that.
- Temperature: each tile has its own air temperature, set by biome, season, time of day and weather.
  Campfires, shelters and hide clothing (made automatically from spare hides) keep people warm.
  Freezing, starving and dehydration all damage health.

**Time, seasons, weather**
- A full day/night cycle: morning, day, evening and night, with smooth lighting changes.
  Campfires light up the dark, and people sleep at night.
- There are four seasons of three months each. Each season changes temperature, berry and mushroom regrowth, animal breeding and fishing.
- In winter, snow covers cold regions: tiles turn white, pines get snow and oaks lose their leaves.
  Autumn trees turn orange.
- Weather: clear, cloudy, rain, storms with lightning, and snow. Rain and snow make people wet and cold.
- Winter preparation: fall warns you about food stores. Drying racks preserve meat, and laborers stockpile firewood.
  Campfires burn wood, and a fire that runs out of fuel goes dark and cold.

**Buildings**
- Campfire, Primitive Shelter, Storage Area, Sleeping Area, Drying Rack, Hunting Camp, Wild Garden Plot and Primitive Fence.
- Every building costs resources and needs construction work from a Builder or Laborer. Demolishing refunds 50%.
- Farm plots are planted in spring/summer, tended, and harvested for vegetables. Frost kills crops left unharvested.

**Wildlife**
- Rabbits, deer, boar, mountain goats, wolves, bears, jaguars and birds.
- Animals wander their home biomes, graze, drink, flee from people and predators, and breed in spring and summer.
- Wolves, bears and jaguars hunt prey. Hungry wolves and big cats may stalk people, mostly at night.
  Bears defend their space, and boars fight back when hunted.
- Overhunting thins out local populations. Animals migrate back in from far away when a species gets too rare.
- Hunters track, spear, butcher and haul meat, hides and bones. Carcasses left by predators can also be butchered.

**Interface**
- Top bar: population, food (with days of supply), water, wood, stone, sticks, colony health,
  season, date, clock, temperature, weather and speed controls.
- Event feed for births, deaths, illness, attacks, seasons and warnings.
- Panels: Build, Jobs and work priorities, Stockpile, Colony overview (people, births/deaths, era, memorial), and Help.
- An info panel for the selected person (need bars, illness, family, skills, carrying), building, or the tile under the cursor.
- A minimap and a full world map with wildlife. Click either to jump the camera there.

**Save system**
- 3 save slots plus quick save/load.
- Saves the seed, world size, resource changes, fish stocks, people, family links, buildings, stockpile,
  job priorities, animals, time, season and weather. Loading restores the world as it was.

## Project structure

```
project.godot
scenes/
  main_menu.tscn        title screen
  game.tscn             game scene (everything else is built in code)
scripts/
  autoload/config.gd    passes seed / size / load slot between scenes
  autoload/art.gd       procedural pixel-art: terrain atlas, trees, rocks, icons, light texture
  world/defs.gd         ALL game data: terrain, resources, items, food, jobs, buildings, animals, illnesses
  world/world_map.gd    flat packed-array world grid + spatial queries
  world/world_gen.gd    seeded generation (biomes, rivers, lakes, springs, valleys, resources, spawn)
  world/pathfinder.gd   weighted AStarGrid2D pathfinding
  sim/sim.gd            simulation core: clock, weather, daily/hourly ticks, buildings, births, deaths, save data
  sim/time_system.gd    days, hours, seasons, years, lighting colour
  sim/weather_system.gd seasonal weather
  sim/human.gd          person data
  sim/human_ai.gd       needs → own job → priority fallback task system
  sim/survival.gd       needs, warmth, illness, eating, drinking, spoilage, pairing, pregnancy, aging
  sim/animal.gd         animal data
  sim/animal_ai.gd      wildlife behaviour, predators, breeding, migration, LOD
  sim/colony.gd         a civilization: people, buildings, stockpile, AI settings
  sim/civ_ai.gd         tribe AI: job assignment, building planning, site selection, research
  sim/ship.gd           boats: capacity, speed, passengers
  sim/building.gd       building data
  sim/elections.gd      Chiefs, Presidents and votes
  sim/borders.gd        right of passage, requests and trespass incidents
  sim/fx.gd             combat visual effects queue
  sim/military.gd       training and hiring Warriors and Archers
  sim/deals.gd          trade offers, alliances, tribute and land demands, counter-offers
  sim/milestones.gd     the 27 milestones and their rewards
  sim/trade.gd          the player's trade orders and the trader's trips
  sim/bandits.gd        outlaw camps, robberies and ambushes
  sim/politics.gd       political happiness, splits and new tribes
  sim/fog.gd            fog of war
  render/terrain_view.gd    crisp pixel-art ground (terrain.gdshader: dithered tile edges, zoom-adaptive pixel size) + seasonal snow
  render/resource_layer.gd  chunked resource drawing (only changed chunks redraw)
  render/entity_layer.gd    people, animals, buildings, selection, build ghost
  render/weather_overlay.gd rain / snow / storm / lightning
  render/map_view.gd        minimap + world map
  render/camera_controller.gd
  ui/hud.gd, ui/main_menu.gd, ui/ui_theme.gd
  save/save_system.gd
```

Tuning lives almost entirely in `scripts/world/defs.gd`. That includes day length, season length, yields, food values, building costs, animal stats and illness rates.

## Performance notes

- The world grid is stored in packed arrays, and pathfinding uses Godot's native `AStarGrid2D`.
- The ground is a single texture (one pixel per tile) blended and shaded on the GPU.
- Resources are drawn in 16×16-tile chunks. Only the chunk that changes is redrawn, and off-screen chunks are culled.
- Animals and rival tribes outside the camera area are simulated in coarse steps (level of detail).
- When fully zoomed out, people and animals aren't drawn at all — only their icons and the tribe flags.
- Regrowth only scans tiles that can regrow, fish stocks recover lazily, and wildlife density uses spatial buckets, so big maps stay fast.
- The simulation runs in fixed sub-steps, so 8x speed behaves the same as 1x.

## Not in the game yet

- Alliances and trade treaties, conquering or annexing tribes, and tribes founding extra settlements.
- Naval warfare; AI tribes don't build ships yet.
- Sound, animation and sprite art.

## Round D additions

- **Lumber Yard & Lumberer** (research *Lumber Yard*, Caveman Age): lumberers fell whole trees, drag the log to the yard and chop each one into 14 sticks.
  Felled trees grow back after a while (World rule *Tree regrow days*), but never where a building or road now stands.
- **Fanfare** plays when your tribe elects a new leader.
- **Diplomacy waits**: after asking another tribe for an alliance, passage, peace or a deal, you (and the AI) must wait 5 minutes of play time before asking that tribe for the same thing again. Buttons show the time left.
- **Day/night** shading is always hidden at 8x speed or faster.
- **Jobs window**: a centered window with a card per job (description, workers, priority stars, assign/remove) and a people list.
- **Randomize sliders** buttons in the main-menu rule pages and in Settings › Game Rules.
- **Age of consent** rule (People): 18–21, default 18.
- **Saves**: the pause menu has separate *Save Game…* and *Load Game…* pages.
- **Tech announcements**: every new technology shows a banner at the top of the screen with what it unlocks.

## Round E additions

- **Research**: the Convert button and tooltips use the KP-per-RP rule from Game Rules. New *Auto-advance age* option. Auto-convert, auto-research and auto-claim land start switched on.
- **Saves**: 6 slots. The pause menu's *Main Menu* asks "Are you sure?" first. New *World History* page lists wars, peace, ages, leaders, techs and fallen tribes.
- **Roads**: every tribe (yours too, toggle in Plan Town) lays roads from its buildings to the nearest road or campfire. Roads show on the World Map and Territory view in the builder's colour.
  At war, the *Remove road* tool marks an enemy's roads and your Billies tear them up; AI tribes do the same to yours.
- **Plan Town**: Ctrl+Z / Ctrl+Y (and Undo / Redo buttons). Zones stay visible while placing buildings. Tribes build into painted zones of the right kind first.
- **Sleeping**: Billies go inside their hut or house to sleep (z's float over the roof).
- **War structures** (Military row, every age): Rock Lookout, War Drum Circle (Caveman); Sling Platform, Ram Shed (Stone); Bronze Bastion, Catapult (Bronze); Ballista Tower, Trebuchet (Iron).
  Lookouts and towers shoot enemies and predators; drums, rams and siege engines boost soldiers or hurl boulders at enemy buildings.
- **Long illnesses**: Dementia (45+, worse with age, forgets tasks, harmful from 70), Obesity (makes diabetes 25% likelier), Type 2 Diabetes.
- **Music**: 10 new pieces (20 in all), including brass marches (*March of the Tribe*, *Bronze Legion*, *War Horns*), still shuffled. A chime plays when you research a tech by hand.

## Round F additions

- **Music**: 10 more pieces (30 in all), mostly marches and brass: *Drums of the Host*, *The Chief's Return*, *Shield Wall*, *Copper Crown*, *March to the Sea*, *Iron Vanguard*, *Standard Bearers*, *Victory Feast*, *Border Watch*, *The Last Legion*.
- **Road networks**: tribes lay a main street through the village (bending around buildings), then lanes from each building's door to the nearest street, then a highway to a nearby ally or friendly tribe. Billies build roads outward from roads already laid, so streets appear whole. Stuck plans are dropped.
- **Allied roads**: allies help build each other's planned roads where they cross their own land.
- **Splits**: a group that breaks away always includes at least one man and one woman (couples stay together).
- **Civil war**: when half or more of a tribe's adults dislike their leader, the tribe may split (Game Rules: yearly chance). Rebels take the far half of the land and its buildings and go to war with the loyalists. The Colony panel shows the share against the leader.
- **Sending the sick away**: your tribe asks whether a badly sick, contagious person should be sent away. AI tribes decide themselves.
- **Bonus buildings** (2 per age, expensive, each kind counts at most twice): Shaman's Circle, Great Hearth, Flint Works, Stone Calendar, Marketplace, Bathhouse, Academy, Iron Foundry.
- **Trading distance**: World settings *Trading distance* (default 250 tiles) and *Extra distance with Trade Wagons* (default +200).
