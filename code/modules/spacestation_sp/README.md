# Spacestation SP module

Singleplayer additions to /tg/station. Everything SP-specific lives in this folder (plus
`code/__DEFINES/spacestation_sp.dm`) so the fork can be rebased onto upstream.

## Files
- `sp_config.dm` — config entries: `SP_AUTOPOPULATE <n>`, `SP_ENGINE_SIMULATED_OUTPUT <kW>`,
  `SP_ENGINE_REAL_EMITTERS` (experimental).
- `sp_subsystem.dm` — `SSspacestation_sp`: tracks AI crew, hooks round start for auto-populate,
  runs the 10-second engine watchdog (telemetry, anti-vacuum guard, scram, simulated output).
- `sp_crew_spawner.dm` — client-less human crew creation via `SSjob.equip_rank`, manifest injection,
  AI attach. `sp_controller_for_job()` picks the controller by department;
  `sp_essential_job_types()` guarantees one engineer, one security officer and one doctor.
- `sp_engineering.dm` — power monitoring and the scripted engine startup (see below).
- `sp_breach.dm` — hull breach detection and RCD repair (see below).
- `sp_botany.dm` — hydroponics helpers: which tray needs what, seed pool, produce and delivery targets.
- `sp_admin_verbs.dm` — Fun tab: "SP: Populate Station", "SP: Spawn Crew (Job)".
- `ai/sp_crew_controller.dm` — `/datum/ai_controller/sp_crew` and the `/medical`, `/security`,
  `/engineer` subtypes. Hearing hook, incident routing, attacker memory, `TRAIT_NOHUNGER`.
- `ai/sp_crew_behaviors.dm` — leaves, decorators, targeting strategies and subtree declarations.
- `ai/sp_botanist_behaviors.dm` — the botanist's leaves and subtree declarations.
- `sp_conversation.dm` — conversation topics, standing, and the keyword answers players get.
- `sp_cargo.dm` — the supply request queue, ordering against the cargo budget, and crate handling.
- `sp_curiosity.dm` — roaming destinations, what a character would pocket, and finding lockers and doors.
- `sp_bar.dm` — the drinks menu, the two dispensers, and what counts as a made drink.
- `sp_kitchen.dm` — the prep table and counter, the prep-step table, the mixes, and the recipe scan.
- `ai/sp_social_behaviors.dm` — the leaves that carry a conversation.
- `ai/sp_cargo_behaviors.dm` — the quartermaster's paperwork and the technicians' hauling.
- `ai/sp_chef_behaviors.dm` — the chef's stocking, prep, mixing, cooking and serving leaves.
- `ai/sp_curiosity_behaviors.dm` — the idle leaves every job shares: roam, rummage, try a door.
- `ai/sp_bartender_behaviors.dm` — the bartender's pouring, serving and glassware leaves.

## Behaviour trees (`ai/*.bt.json`, compiled into `build/behavior_trees/`)
- `sp_crew_core` — shared priority ladder: escape captivity > defense > safety > threat > social.
- `sp_crew_defense` — attacked: report over radio (or shout if no headset), then flee; memory expires
  after 20 s.
- `sp_crew_threat` — someone nearby holds a weapon and is not security/command: warn them and keep a
  4-7 tile distance. Driven by the `sp_scan_threats` leaf running in the tree's parallel branch.
- `sp_crew_safety` — below `BB_SP_HURT_THRESHOLD`: shout for a medic, walk to medbay.
- `sp_crew_social` — someone said our first name: face them and answer.
- `sp_department_wander` — pick a turf in `BB_SP_WANDER_AREAS` (or home area) → JPS move → linger.
- `sp_medical_treat` — patient with ≥10 brute/burn → equip matching stack → walk over → apply.
- `sp_security_respond` — suspect: equip baton, close in, attack; once they are down, cuff them;
  once restrained or dead, announce "area secure" and clear. With only a location, walk there and
  look around for 8 s.
- `sp_engineer_power` — power check → say so → walk to the engine room → run the loop setup →
  wait 40 s → bring the engine online.
- `sp_engineer_repair` — find the nearest breach → announce it → put on EVA gear → open internals →
  equip the RCD → walk to a safe tile beside the hole → lay plating over it.
- `sp_botanist_tend` — find the tray that most wants attention → put the right thing in hand → walk
  over → work it. Harvest beats everything else, then clearing dead plants, weeding, watering and
  finally planting an empty tray.
- `sp_botanist_gather` — harvesting drops produce at the botanist's feet, so this picks it up and
  stows it in their bag.
- `sp_botanist_deliver` — once carrying five or more, leave a couple out as samples in hydroponics
  (at most once every four minutes), then carry the rest to a kitchen table and say so on the
  service channel.
- `sp_botanist_refill` — top the watering can up at a water tank when it runs dry.
- `sp_qm_order` — walk to a cargo console and put the outstanding requests on the order list, or a
  standing restock when nobody has asked for anything.
- `sp_qm_shuttle` — send the supply shuttle out with the orders, and call it back with the goods.
- `sp_cargo_haul` — drag a crate off the shuttle, to the department that requested it if it was
  asked for, otherwise into the cargo bay.
- `sp_chef_stock` — carry ingredients out of the fridges, cabinets and off the kitchen floor and pile
  them on one prep table. Also the unload half: an armful in hand always goes down before more is
  fetched.
- `sp_chef_mix` — take a bowl to the sink for water, back to the table for flour, and let the reaction
  make dough. Cheese is the same trip without the sink.
- `sp_chef_prep` — one rung of the cooking tree: cut with a knife, flatten with a rolling pin, or carry
  something to the griddle, the oven or the processor and switch it on.
- `sp_chef_collect` — take what has finished out of the oven and off the griddle, and switch the
  griddle off behind them.
- `sp_chef_cook` — stand at the prep table and craft whatever the pile currently supports.
- `sp_chef_serve` — carry a finished dish to the counter, set it down, and say so on the service channel.
- `sp_chef_supply` — when the kitchen has been picked clean, put a food crate on cargo's list.
- `sp_crew_rummage` — open a locker or crate in sight and pocket anything that takes their fancy.
- `sp_crew_try_door` — walk up to a door they have no access to and try it anyway.
- `sp_crew_roam` — wander off to somewhere else on the station for a while.
- `sp_bartender_pour` — take a glass to whichever tap holds the next thing the drink needs, and measure
  it in. Most cocktails want something from each of the two dispensers, so this runs twice per glass.
- `sp_bartender_serve` — carry the finished drink to the bar counter and call it out.
- `sp_bartender_glasses` — buy more glasses from the dinnerware vendor when the shelf is bare.

## Conversation and standing (`sp_conversation.dm`)
Two crew who end up near each other with nothing urgent on will hold a short exchange: an opener, an
answer, and sometimes a closing remark. Because both sides are ours, the listener reads the topic
straight off the speaker's controller, so replies actually match what was said. Topics are weighted
and some are job-specific, so an engineer opens with the power and a doctor with medbay.

Players are handled from the other direction. What someone says to a crew member in singleplayer is
fairly predictable, so greetings, "what do you do", "where is x", asking for help, thanks and abuse
are matched by keyword and answered in character. Crew also greet a player once each when they first
come near, and make the occasional remark to the whole station over common.

Every exchange moves how that crew member feels about the person, held in `BB_SP_REPUTATION`.
Politeness and conversation raise it, an attack drops it sharply. Answers already vary with standing:
a stranger gets "What do you need?", someone they like gets greeted by name, and someone who has been
abusive gets told to ask elsewhere. Asking a crew member to follow you is recognised and refused
politely below the friendly threshold, which is where the follow behaviour will hook in.

None of this outranks an emergency: conversation is the last entry in `sp_crew_core`, so a fight, an
injury or a drawn weapon cuts it off, and being attacked clears the conversation outright.

## Incident reporting chain
1. A crew member is attacked → `on_attacked` sets `BB_SP_ATTACKER`.
2. `sp_report_attack` speaks the report (radio when the crew member wears a headset, otherwise a
   local shout) and stores a structured record in `BB_SP_LAST_INCIDENT`.
3. Every AI crew member hearing that line reads the reporter's record in `on_pre_hear`; the security
   controller turns it into `BB_SP_INCIDENT_TARGET` / `BB_SP_INCIDENT_LOCATION` and acknowledges over
   the security channel.
4. Players get the same effect for free: a shout containing "help", "attack", "security" etc. sets an
   incident location for nearby AI security (`sp_message_is_distress`).

## Engine startup (`sp_engineering.dm`)
`sp_run_engine_setup()` performs the standard /tg/ cold-loop procedure, restricted to machines inside
`/area/station/engineering/supermatter`: connect and open the nitrogen canisters, run the loop pumps
at max pressure (bypass/mix pumps untouched), turn on filters, drop the freezers to their minimum,
raise the chamber vents' pressure bound so the chamber actually fills, and set the chamber scrubbers
to scrub waste gases only. It also maxes every station SMES and sets solar tracking to auto.

By default the crystal is **not** energized. Once the chamber holds ≥400 moles of ≥90% nitrogen the
engineer declares the engine online and `SSspacestation_sp` feeds
`SP_ENGINE_SIMULATED_OUTPUT` kW into the engine-room SMES units every watchdog tick. This keeps the
lights on reliably without depending on a perfectly tuned coolant loop.

Setting `SP_ENGINE_REAL_EMITTERS` switches to real emitters: circulation is enabled once the chamber
is full, and the emitters only fire when it is ≥600 moles, ≥90% nitrogen and below 200 K. This is
experimental — on MetaStation the waste side of the loop still needs tuning, and the watchdog will
scram the emitters as the crystal heats.

The watchdog always runs: it disables circulation if the chamber drops below 250 moles (a vacuum
around an energized crystal superheats instantly), pauses the emitters for 2 minutes at the first
temperature warning, and scrams for 10 minutes with a radio call if integrity starts falling.

## Hull breaches (`sp_breach.dm`)
A breach is a space turf inside a station area that still has a real floor next to it. Solar arrays,
external maintenance and space catwalks are made of space turfs with no adjacent floor, so they never
match; `GLOB.sp_breach_area_blacklist` covers anything else that is open by design.

`SSspacestation_sp` walks a twelfth of the station's areas every five seconds, so a full sweep is
spread over about a minute and costs almost nothing per tick. Patched turfs drop out of the cache on
the next pass.

Engineers carry an RCD already; SP additionally issues them an EVA softsuit and helmet
(`equip_extra_gear` on the engineer controller), because patching a vented room means standing in
vacuum and TG only gives them a hardhat. Plating over space costs 3 RCD matter and is instant, so one
RCD is good for roughly 50 tiles.

Two obstacles had to be cleared for any of this to work, and both are worth knowing about:
- **Access.** JPS will not path through a door the pawn cannot open, and breaches happen behind locked
  doors, so AI engineers are granted station-wide access on their ID in `equip_extra_gear`.
- **Firelocks.** A breach slams every firelock around it shut, and a closed firelock is dense, so
  pathfinding refused to route into the damaged room at all. `/obj/machinery/door/firedoor/CanAStarPass`
  now lets pathfinding through an unwelded firelock, and the crew controller opens one when it bumps
  into it (`on_bump`), which is what a person does anyway.

Damage that genuinely cannot be walked to (a room sealed behind blast doors, say) is written off after
90 seconds and ignored for five minutes, so engineers get back to work instead of looping on it.

`SP_DEBUG_BREACH_COUNT <n>` punches n holes in a random room a minute after round start, for
exercising the behaviour in headless tests. Leave it at 0 for real play. Uncomment `SP_BREACH_DEBUG`
in `code/_compile_options.dm` for verbose target/move/failure logging.

## Botany (`sp_botany.dm`)
`sp_tray_job()` decides what a tray needs, in priority order: harvest, clear a dead plant, weed above
level 2, water below level 30, or plant if it is empty. Every one of those is done through the same
interaction a player uses, so trays, seeds and produce behave exactly as they normally would.

TG only gives botanists an apron and a plant analyser; the hoe and watering can are family heirlooms
most characters never roll. `equip_extra_gear` hands them a cultivator, a full watering can and two
packets each of six seed types drawn at random from `GLOB.sp_botany_seed_pool`. The pool is weighted
towards things the chef can cook, with a tail of the botanist's own interests, so the garden differs
every round. Whether any of it is legal is Security's problem, not botany's.

### Seeds, buying and experiments
Three slower errands sit between delivery and tending in the botanist's tree, each on its own cooldown:
- `sp_botanist_extract` — produce whose species they hold no packet of is carried to a seed extractor
  and turned into seeds, which is how a botanist locks in something new. They also fall back to
  seeding whatever they have when down to their last few packets.
- `sp_botanist_shop` — buys a packet of something they have never grown from the MegaSeed Servitor,
  paid for out of their own wages via their ID's bank account.
- `sp_botanist_experiment` — pours a full beaker of unstable mutagen into a growing plant that has
  somewhere to mutate to. They commit to one tray and keep returning to it, because instability only
  pays off near 60 and dosing whatever is nearest would never finish an experiment.

SP issues four large beakers of mutagen in the starting kit. Chemistry normally supplies this and
botanists only get it in the mail, so without it they could never deliberately breed anything.

## Cargo (`sp_cargo.dm`)
Requests are the point of the department, so they are first-class here. Any AI crew member can call
`sp_request_supplies(pack_type, requester)` and the queue on `SSspacestation_sp` carries it through
pending, ordered and delivered. The quartermaster notices pending requests, orders them against the
cargo budget through a real `/datum/supply_order`, and answers the requester by name on the supply
channel. When the crate comes back, a technician matches it to the request and walks it to the
department that asked rather than dumping it in the bay.

With nothing requested, the quartermaster keeps the shuttle earning its keep with a small standing
restock (`GLOB.sp_cargo_standing_order`): food, medical supplies, engineering equipment, janitorial
supplies and hydroponics gear.

Cargo is staffed as an essential job, because the chef and the rest of the station depend on it.
`SP_DEBUG_SUPPLY_REQUEST` has a random crew member raise a request two minutes in, for testing the
path without waiting for a department to want something.

## The kitchen (`sp_kitchen.dm`)
/tg/'s cooking is a tech tree, not a list of recipes. Almost nothing worth eating can be assembled
straight from what a kitchen starts with: raw stock has to be cut, ground, mixed, baked and grilled
into components first, and only then does the crafting menu have anything to offer. A chef that only
knew how to craft would stand at a full table and make two things all shift.

So the chef works the tree from the bottom, using the same interactions a player does.

**The prep table** is the kitchen table with the most cooking machinery beside it, and everything hangs
off that choice. Crafting only sees one tile around the crafter, so the table the ingredients are piled
on decides which recipes are possible at all — and on MetaStation the winner is the table wedged
between the two ovens, which puts them in reach too.

**The counter** is a kitchen table with an open tile on the other side that is not the kitchen. That is
the serving hatch on any map that has one; on MetaStation it picks out exactly the row of tables the
bar stools face.

**The rungs** are `GLOB.sp_kitchen_prep_steps`: an ingredient, an operation, and what comes out. /tg/
hangs these transformations off elements and components on the ingredients themselves, so they cannot
be enumerated from an item — poking every ingredient with every tool to find out would be both slow and
absurd, so the rungs worth climbing are written down. The `result` is only used to know when to stop.
Between them they produce cutlets and patties, bread and buns, cheese wedges, boiled eggs and cut
produce, which is most of what the craftable dishes are actually made of. A slab of monkey meat is
worth nothing on its own and becomes a burger four rungs later.

**The mixes** (`GLOB.sp_kitchen_mixes`) are the one part of the tree crafting cannot reach: dough and
cheese are chemical reactions in a bowl, not recipes. The chef carries a bowl to the sink for water,
back to the table for the flour, and the reaction fires on its own. Without this there is no dough,
which means no bread, no buns and no sandwiches.

**The cooking** is not a menu. `sp_craftable_recipes()` runs /tg/'s own `check_contents` against
everything within reach and returns what would actually work, so what comes out depends on what botany
grew and what cargo delivered. Finished dishes are preferred, but half-made things get crafted too —
a raw calzone goes back on the pile and the oven rung finishes it.

**Serving** is the point of all of it. A dish counts as finished when it took crafting to make, is not
itself an ingredient in one of the prep steps, is not flagged `RAW`, and is not something the oven would
improve — dough, batter and a raw pizza all fail that last one.

That last test is `sp_bakes_into_something()`, and it is not "does it have a bakeable component". Every
food in /tg/ has one: `/obj/item/food/make_bakeable()` gives everything a default bake into a burned
mess. What separates dough from dinner is whether the bake is a *positive* one. Testing for the
component alone classified every sandwich the chef made as an unfinished ingredient, and nothing ever
reached the counter. Being *grillable* is deliberately not disqualifying either — a cheese sandwich can
become a grilled cheese, and an available upgrade does not make something an ingredient.

Dishes go out on the counter with a line on the service channel, and the chef stops once eight are
stacked up uneaten.

`SP_DEBUG_KITCHEN_STOCK` lays a set of ready-made components on the prep table a minute in, so the
cooking and serving half can be watched without first sitting through the whole cutting, mixing and
baking chain.

**Running dry** goes through cargo: when the worktop is not stocked, the chef is carrying nothing, and
there is no fridge, cabinet or pile left in the kitchen with anything in it, the chef
raises a `/datum/supply_pack/organic/food` request through `sp_request_supplies()` and asks cargo for it
over the supply channel. The quartermaster orders it, a technician walks the crate to the kitchen, and
the chef takes it apart again. Six minutes between requests, so one slow shuttle run does not turn into
a queue of crates.

TG issues a chef an apron, a hat and a moustache. The knife, the rolling pin and the bowls are all
things a real kitchen already owns or a character rolls as a family heirloom, so `equip_extra_gear`
hands them over — bowls in particular are the gate, since a great many recipes want one and the
dinnerware vendor charges most of a paycheck each.

### Two things that cost a while to find
**Click delay.** `ClickOn()` silently drops anything that arrives within a decisecond of the last
click. Every SP behaviour before the chef clicked at most once per tick, so this never came up; the
chef needs three clicks to bake something (open the oven, put the tray in, shut the door) and only the
first was landing. `sp_chef_click()` waits out `next_click` first, which is why the chef's machine work
runs in `perform_async()` — it has to be allowed to sleep.

**The oven clock.** Baking only counts while the door is shut, and the default bake is two minutes. A
chef who opened the oven every time they had one more thing to add stopped the clock over and over and
never got bread out. The oven is now loaded in one go and left alone until it is empty again;
`sp_machine_room()` is what enforces that, and it is also why the prep steps carry a batch rather than
a single ingredient.

Uncomment `SP_KITCHEN_DEBUG` in `code/_compile_options.dm` for a running commentary on what the chef
tried and why it did not work, which is how both of those turned up.

### Staffing
The cook is an essential job, so `sp_populate_station()` fills the post before filling out the rest of
the crew. There are seven heads of staff and seven essential jobs, and heads are placed first, so
`SP_AUTOPOPULATE` below 14 will leave departments empty — the dev config ships at 16.

## The bar (`sp_bar.dm`)
Drinks are much easier than food. A cocktail is a chemical reaction rather than a crafting recipe, and
the bar's two dispensers between them hold every base spirit and mixer, so there is no tech tree: pick
a drink, put a glass under the tap, measure the parts in, and the reaction does the rest. What takes
the walking is that a gin and tonic needs gin from one dispenser and tonic from the other, so most
drinks are two trips.

`GLOB.sp_cocktails` is the menu, and each entry carries the reagent it *becomes* as well as the parts
that go in. That second field is not decoration: the reaction consumes the gin and the tonic to make
the gin and tonic, so a glass that has just been made correctly contains neither, and asking "is it
still short of gin?" answers yes forever. `sp_drink_ready()` asks the question the right way round.
Without it the bartender tops the same glass up until the end of the shift and never serves anything.

The dispenser has no clientless route through its interface, so `sp_dispense_into()` reproduces what
pressing the button does — including spending the cell charge, which is what stops a bartender pouring
out of an unpowered machine. Getting the glass in and out is real clicking: in with the glass in hand,
out with a right-click.

TG gives a bartender a bowtie, sunglasses and a box of beanbag shells, and the station has no drinking
glasses on it anywhere, so `equip_extra_gear` hands over two boxes and they buy more from the kitchen's
dinnerware vendor when those run out.

## Idle curiosity (`sp_curiosity.dm`)
What a crew member does when they have nothing to do, shared by every job because it is character
rather than work. It sits below the job subtrees and above the department wander, so it never competes
with actual work — and above `sp_department_wander` so it beats pacing the same room.

- **Roaming.** Every five minutes or so they take a trip somewhere else on the station — a hallway, the
  bar, the dorms, maintenance — stand about for twenty seconds, and drift back when the department
  wander next picks a turf at home.
- **Rummaging.** A shut locker, crate or box in *sight* (`oview`, so only what they could actually have
  noticed) that is unlocked or opens to their ID gets opened, looked through, and shut again. Each
  character rolls four tastes from `GLOB.sp_interest_pool` at spawn, so one has a weakness for hats and
  another walks off with every screwdriver they find, and they are consistent about it all shift. They
  take at most two things and leave the container as they found it. Searched containers are left alone
  for ten minutes.
- **Trying doors.** Every few minutes they walk up to a door they have no access to and try it. The
  door refuses — that is the whole point — and they grumble about it and move on. A door found locked
  is left alone for fifteen minutes.

### Groundwork for greytide and antagonists
The three decisions that separate a nosy crew member from a greytider are all overridable on
`/datum/ai_controller/sp_crew`:

- `wants_item(thing)` — ordinary crew take what matches their own tastes and nothing on
  `GLOB.sp_interest_blacklist` (IDs, guns, organs). An antagonist wants rather more.
- `may_rummage()` / `may_try_doors()` — whether to bother at all.
- `on_door_denied(door)` — base crew complain out loud and walk away. This is where prying, welding or
  hacking goes.

Ordinary crew also shut lockers behind them, which a greytider will not: a corridor of hanging-open
lockers is a tell, and skipping that one line is most of the visual difference.

## Movement
SP crew use `/datum/ai_movement/jps/sp_crew`, which raises the path limit from TG's
`AI_MAX_PATH_LENGTH` (30 tiles, tuned for animals that lose interest after 14) to 220. Without it no
crew member can walk to medbay, the engine room, or an incident on the far side of the station.

## Launching (`RUN_SP.cmd`)

Use the launcher rather than double-clicking `tgstation.dmb`. It gets two things right:

- **Trusted security.** Dream Daemon defaults to *Safe* on a fresh install, and at Safe BYOND raises a
  "Safety check: allow access to ..." dialog for every file the game reads — hundreds of them at
  startup, because each AI crew member loads several compiled behaviour trees. rust_g and dreamluau
  cannot load at all. `/tg/station` requires Trusted (`RUNNING_A_SERVER.md`, `.tgs.yml`), so the
  launcher passes `-trusted`. The GUI's Security dropdown is the equivalent for a manual launch;
  `cfg/daemon.txt` does *not* govern command-line launches.
- **Port 7777.** See the note at the bottom of this file.

`RUN_SP.cmd [port]` finds BYOND through the registry and starts the server; connect Dream Seeker to
`byond://127.0.0.1:7777`.

## Local dev config
`config/dev_overrides.txt` (gitignored; copy from `../../docs/dev_overrides.example.txt`) enables
AUTOADMIN, a 10 s lobby, `RESUME_AFTER_INITIALIZATIONS` for headless tests, `SP_AUTOPOPULATE`, and
the engine settings.

## Testing

There are two loops, and the first one is the one to reach for.

### Unit tests (fast, deterministic, gives a verdict)
`code/modules/unit_tests/spacestation_sp.dm`. Emergent crew are miserable to check by playing: you
start a round, wait, grep the log for a hopeful string, and silence tells you nothing — a behaviour
that is broken and a behaviour that has not come up yet look identical. Every bug that has actually
bitten this module has lived in ordinary deterministic logic, so that is what these assert:

- `sp_finished_dish` — a cheese sandwich is dinner, dough is not, a bread slice is a component, raw
  meat is raw. This is the exact rule that once classified every sandwich as an ingredient and left the
  counter empty for a whole session.
- `sp_prep_steps` / `sp_kitchen_mixes` / `sp_cocktails` — the data tables are real typepaths, the tools
  named are actually tools, and every drink on the bar menu comes out of a tap the bar actually has.
- `sp_pour_a_drink` — pours a gin and tonic out of both dispensers and asserts the reaction fired.
- `sp_cook_a_dish` — stands a chef beside bread and cheese, asserts a cheese sandwich is craftable,
  crafts it, and asserts the result is servable. The whole pipeline, in milliseconds.
- `sp_curiosity` — tastes are respected, IDs are never pocketed, interests roll without duplicates.
- `sp_behaviour_trees` — every SP controller points at a tree that was actually compiled.

```
tools\build\build.bat build --define=CIBUILDING
E:\games\BYOND\bin\dd.exe tgstation.dmb -close -trusted -verbose -params log-directory=ci > tests.out
```
`PASS`/`FAIL` lines go to stdout, so capture it; `data/logs/ci/clean_run.lk` says `Success!` when the
whole suite passed. Stop any running server first — a live `dd.exe` holds `tgstation.rsc` open and the
compile fails with a confusing "cannot find file" on an unrelated resource.

### Live rounds (for what only emerges in play)
Some things genuinely only show up with a station running — pathing, whether a chef can reach the
coldroom, whether anybody ever walks past a locker. For those, `SSspacestation_sp` keeps a tally of
everything the crew actually manage and prints it every two minutes:

```
SP: tally: bar.served=2 chef.cooked=7 chef.served=3 crew.door_refused=11 crew.pocketed=1
```

That is the difference between "nothing happened" and an answer. `crew.door_refused=11` with
`crew.pocketed=0` says door-trying works and rummaging does not, which is a bug report rather than a
shrug. The same counts are on the Debug tab as **SP: Behaviour Tally**, and in `stat_entry`.

## Headless test loop
```
tools\build\build.bat build
E:\games\BYOND\bin\dd.exe tgstation.dmb 7777 -trusted -close -logself -params log-directory=sp_test
```
Then read `data/logs/sp_test/{game,runtime}.log`; SP lines are prefixed `SP:`. Kill `dd.exe` before
recompiling, and touch a changed file if the build says "Skipping 'dm' (up to date)".

Use port 7777, not 1337: Razer Synapse's RzSDKServer listens on `127.0.0.1:1337`, and a loopback-bound
socket beats Dream Daemon's wildcard bind, so clients reach Razer and fail the BYOND handshake while
the game server logs nothing at all.

## Upstream touch points (keep this list short)
- `code/controllers/master.dm` — do not sleep the world after init when
  `RESUME_AFTER_INITIALIZATIONS` is set.
- `code/game/machinery/doors/firedoor.dm` — `CanAStarPass` so AI can path through unwelded firelocks.
- `code/datums/station_traits/{neutral,positive}_traits.dm` — null-guard the client argument, which
  AI crew do not have (two traits were throwing a runtime per spawned crew member).
- `code/_compile_options.dm` — the optional `SP_BREACH_DEBUG` and `SP_KITCHEN_DEBUG` flags.
- `tgstation.dme` — include lines for this module.

## Known limitations
- Crew wander randomly inside their areas; no schedules or work objects yet.
- Breach repair patches floors only. Broken walls, windows and airlocks are left alone, and nobody
  re-pressurises the room afterwards.
- Threat detection is line-of-sight and weapon-in-hand only; concealed weapons do not scare anyone.
- Security uses melee and cuffs, never the disabler in their suit slot.
- Cargo never sells anything, works the mining or materials markets, or handles the express console;
  there are no miners yet. Crates are dragged, so a technician moves one at a time, and a haul that
  has not finished within two minutes is abandoned where it stands rather than blocking the
  quartermaster's paperwork behind it.
- Machine lookups here deliberately avoid `oview()`. It is sight-limited, so a console one room away
  behind a wall is invisible and the quartermaster would never find their own desk.
- Botanists do not compost, fight pests, or use grafts and the DNA manipulator.
- Mutagen reliably pushes a plant's instability into the 20-50 band, where stat mutations happen. A
  full species change needs it sustained above 60, which competes with the plant stabilising between
  doses, so new species are occasional rather than routine.
- No hunger/sleep handling (trait-suppressed).
- Conversation has no dialogue trees yet: crew answer one line at a time rather than tracking a
  thread with a player, and standing is not yet spent on anything (following, favours, access).
