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
  `sp_essential_job_types()` guarantees, after the heads, one each of engineer, security officer,
  doctor, chemist, botanist, cook, bartender, quartermaster and cargo technician, in that order.
- `sp_engineering.dm` — power monitoring and the scripted engine startup (see below).
- `sp_breach.dm` — hull breach detection and RCD repair (see below).
- `sp_botany.dm` — hydroponics helpers: which tray needs what, seed pool, produce and delivery targets.
- `sp_admin_verbs.dm` — Fun tab: "SP: Populate Station", "SP: Spawn Crew (Job)", "SP: Spawn Antagonist
  (Thief)"; Debug tab: "SP: Behaviour Tally".
- `ai/sp_crew_controller.dm` — `/datum/ai_controller/sp_crew` and the `/medical`, `/security`,
  `/engineer` subtypes. Hearing hook, incident routing, attacker memory, `TRAIT_NOHUNGER`.
- `ai/sp_crew_behaviors.dm` — leaves, decorators, targeting strategies and subtree declarations.
- `ai/sp_botanist_behaviors.dm` — the botanist's leaves and subtree declarations.
- `sp_conversation.dm` — conversation topics, standing, and the keyword answers players get.
- `sp_cargo.dm` — the supply request queue, ordering against the cargo budget, and crate handling.
- `sp_curiosity.dm` — roaming destinations, what a character would pocket, and finding lockers and doors.
- `sp_crime.dm` — who can see a crime and what they do about it, shared by the greytide and antagonists.
- `sp_antagonist.dm` — schemes: an AI crew member's hidden goal and the score-keeping for it.
- `ai/sp_antagonist_behaviors.dm` — the antagonist controller and the leaves that pursue a scheme.
- `sp_greytide.dm` — the assistants' haunts and tastes, the prank menu, the tool-storage trips, and the
  malicious streak that smashes a light.
- `ai/sp_greytide_behaviors.dm` — the greytide's gear-up, mischief, rummage and door-trying leaves.
- `sp_chemistry.dm` — planning a medicine back to what the dispenser pours, brewing it a stage at a time,
  and driving the ChemMaster.
- `ai/sp_chemist_behaviors.dm` — the chemist's brewing, patch-printing and delivery leaves.
- `sp_role_takeover.dm` — keeping a job an AI crew member holds open to a joining player, and taking the
  holder off shift when one arrives.
- `sp_bar.dm` — the drinks menu, the two dispensers, and what counts as a made drink.
- `sp_kitchen.dm` — the prep table and counter, the prep-step table, the mixes, and the recipe scan.
- `sp_medical.dm` — where medbay is, triage, picking a treatment for a limb, and the cryo tubes.
- `ai/sp_medical_behaviors.dm` — the patient's side (hold still, come in for a checkup) and the medic's.
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
  4-7 tile distance. Driven by the `sp_scan_threats` leaf running in the tree's parallel branch. A monkey
  only counts once it is fighting or angry (`sp_armed_threat()`): Pun Pun arms themselves with whatever
  turns up behind the bar, and before that rule the crew in the bar shouted for security about it for
  minutes on end.
- `sp_crew_patient` — first thing in every tree: a medic has asked us to hold still, or we are in a working
  cryo tube or on an operating table, so stay put.
- `sp_crew_safety` — below `BB_SP_HURT_THRESHOLD`: shout for a medic, walk to medbay, wait to be seen.
- `sp_crew_checkup` — idle and carrying 15+ brute and burn (or a wound) with a medic on duty: walk to
  medbay, say so, wait to be seen.
- `sp_crew_social` — someone said our first name and nothing else: face them and ask what they want.
- `sp_crew_respond` — somebody said something that wants an answer: give it, unless it is 15 s too late.
  Officers run it below their security work.
- `sp_crew_chatter` — the idle side of talk: greet a newcomer, start a chat and close it, and the odd remark
  over common. Every crew tree runs it.
- `sp_department_wander` — pick a turf in `BB_SP_WANDER_AREAS` (or home area) → JPS move → linger.
- `sp_medical_patient` — pick a patient → walk over → scan them → either take them to cryo or treat
  them limb by limb. See "Medbay" below.
- `sp_medical_cryo_setup` — connect the gas, set the freezer, put a beaker in every tube.
- `sp_medical_surgical_kit` — doctors and the CMO fetch the tools their medkit lacks off a theatre tray.
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
- `sp_greytide_gear_up` — an assistant's trip to Primary Tool Storage for gloves and a tool, three at most.
- `sp_greytide_mischief` — pick a prank from whatever is on offer where they are standing, walk to it and
  pull it, unless an officer is in sight.
- `sp_greytide_rummage` / `sp_greytide_try_door` — the nosier versions of the two curiosity subtrees that
  assistants run in place of the ordinary ones.
- `sp_medical_restock` — a medic who has run low empties a locker or a delivered crate, asks cargo for a
  crate, or asks botany for aloe.
- `sp_chemist_work` — plan a medicine back to the dispenser, brew it a stage at a time at the bench, and
  print the patches.
- `sp_chemist_deliver` — carry the patches to the chemistry fridge and the cryoxadone to the cryo room.
- `sp_bartender_pour` — take a glass to whichever tap holds the next thing the drink needs, and measure
  it in. Most cocktails want something from each of the two dispensers, so this runs twice per glass.
- `sp_bartender_serve` — carry the finished drink to the bar counter and call it out.
- `sp_bartender_glasses` — buy more glasses from the dinnerware vendor when the shelf is bare.

## Conversation and standing (`sp_conversation.dm`)
Two crew who end up near each other with nothing urgent on will hold a short exchange: an opener, an
answer, and sometimes a closing remark. Because both sides are ours, the listener reads the topic
straight off the speaker's controller, so replies actually match what was said. Topics are weighted
and some are job-specific, so an engineer opens with the power and a doctor with medbay.

**An exchange is a handshake, not a guess.** AI crew answer each other only through topics. The opener
moves through `SP_CHAT_*` stages, each set *before* its line is said, because speech goes out through
`INVOKE_ASYNC` and a listener may hear a line before or after the speaker's next statement. A listener takes
a line for an opener only while its speaker is at `SP_CHAT_OPENED`, and marks it heard, so nothing else said
afterwards passes for one. The reply's topic lives in its own key (`BB_SP_CHAT_REPLY_TOPIC`) and is spent as
the reply is said. The replier is then done. The opener has the last word, and only once the partner has
answered, having forgotten the chat before saying it. Before this, a closer could restart the exchange, a
leftover topic answered the next person to speak (players included), and base crew, who never ran the chat
subtree at all, were stuck holding a partner for good after their first reply.

Players are handled from the other direction. What someone says to a crew member in singleplayer is
fairly predictable, so greetings, "what do you do", "where is x", asking for help, thanks and abuse
are matched by keyword and answered in character. Everything is read in whole words (`sp_words()`), so
"they" is not "hey" and "tomorrow" is not "Tom". A crew member answers a line with their first name in
it, and looks up and asks what you want when the name is all there is. A line naming nobody gets one
answer, from the nearest crew member free to give it (`sp_first_to_answer()`), and a line naming somebody
else is left to them. An answer not given within 15 seconds is dropped. Crew also greet a player once
each when they first come near, which no longer waits on the chat cooldown, and make the occasional
remark to the whole station over common.

Every exchange moves how that crew member feels about the person, held in `BB_SP_REPUTATION`, once per
line answered: deciding whether to answer (`sp_speech_intent()`) changes nothing.
Politeness and conversation raise it, an attack drops it sharply. Answers already vary with standing:
a stranger gets "What do you need?", someone they like gets greeted by name, and someone who has been
abusive gets told to ask elsewhere. Asking a crew member to follow you is recognised and refused
politely below the friendly threshold, which is where the follow behaviour will hook in.

None of this outranks an emergency: conversation is the last entry in `sp_crew_core`, so a fight, an
injury or a drawn weapon cuts it off, and being attacked clears the conversation outright. Officers answer
people too, from below their security work, and take nothing up while they have an incident, a suspect,
a prisoner, a briefing or a kit trip in hand.

## Incident reporting chain
1. A crew member is attacked → `on_attacked` sets `BB_SP_ATTACKER`.
2. `sp_report_attack` speaks the report (radio when the crew member wears a headset, otherwise a
   local shout) and stores a structured record in `BB_SP_LAST_INCIDENT`.
3. Every AI crew member hearing that line reads the reporter's record in `on_pre_hear`; the security
   controller turns it into `BB_SP_INCIDENT_TARGET` / `BB_SP_INCIDENT_LOCATION` and acknowledges over
   the security channel.
4. Players get the same effect for free: a call for help sets an incident location for nearby AI security
   (`sp_message_is_distress`). Words of violence count on their own. "Help" and "security" count only when
   the line sounds urgent (an exclamation mark, capitals, the word leading the line, or nothing but
   pleading), never in a calm request: "can you help" used to send every officer in earshot running.

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

### Requests from another department
A line that names botany and a plant they take requests for ("Botany, could you send some aloe up to
medbay?") is heard as a request: they say they will look, and it changes three things until it is
filled. A free tray gets that seed if they have a packet, ahead of the watering, weeding and mutagen
(`sp_find_tray_job()`: in one round the packet sat in a bag for ten minutes while all of that came first),
the trip to the seed vendor buys that packet
if they do not, and the next load of produce goes to a table in the room that asked rather than to the
kitchen, where one of the requested plant is enough to be worth the walk on its own.
`GLOB.sp_requestable_plants` is the list, and aloe is on it because microwaved aloe is the cream medics
treat burns with. The tally counts `botany.request_delivered`.

**Cooked on the way.** A raw leaf handed to a medic is a chore handed over with it, and medbay has no
microwave. A plant with an entry in `GLOB.sp_request_cooked_forms` goes to the nearest working
microwave first (the kitchen's, a wall away from the trays, which a botanist's ID opens), in one leaf at
a time, and what comes out is the delivery: aloe becomes burn cream (`sp_cook_in_microwave()`, tally
`botany.cooked`). A microwave that cannot be reached or gives nothing back is left alone for two minutes,
and the raw plant goes over instead.

**Where it goes.** Where the line says, when it says ("up to medbay" is the medbay lobby,
`sp_named_delivery_area()`), and otherwise where the asker was standing. Medics notice they are out
wherever they happen to be, and in the first round with them roaming one asked from the cargo
warehouse. A table in that room is used when the botanist can reach it, a clear bit of floor when the
room has no table; otherwise the load is left the way cargo leaves a crate, as far as they can get
(`sp_reachable_drop_spot()`), on a table beside that spot or else the floor. Whoever asked is told where
on the radio, and the delivery is left for them by name (`BB_SP_LEFT_FOR_ME`), so that medic goes and
fetches it from wherever it ended up.

## Cargo (`sp_cargo.dm`)
Requests are the point of the department, so they are first-class here. Any AI crew member can call
`sp_request_supplies(pack_type, requester)` and the queue on `SSspacestation_sp` carries it through
pending, ordered and delivered. The quartermaster notices pending requests, orders them against the
cargo budget through a real `/datum/supply_order`, and answers the requester by name on the supply
channel. When the crate comes back, a technician matches it to the request and walks it to the
department that asked rather than dumping it in the bay. The match is on the order number the supply
shuttle stamps on every crate (" - #<id>", `sp_request_for_crate()`), not on the pack's name: a pack and
its crate are often called different things, and medbay's Medical Supplies Crate arrived as a DeForest
Medical crate, matched nothing, and was left in the bay as if nobody wanted it.

A crate is claimed the moment a technician picks it, before the walk over (`sp_crate_claimed()`).
Checking only who was already dragging one left a gap the length of that walk, and every abandoned haul
in every round's log turned out to be two technicians who had picked the same crate and took the pull
off each other until both gave up. Neither steals a pull any more. And crates are only looked for while
the shuttle is docked at the station: away at CentCom its deck is another z-level, and the first round
with the haul's walks logged showed technicians setting off for the mail crate on it at roundstart.

**As far as they can get.** A request is addressed to wherever the asker was standing, and that is
often behind a door the technician cannot open: a doctor in the operating theatre, a chef in the
kitchen. Planned with the technician's own ID there is no route at all, so the walk failed on the spot,
over and over, until the haul timed out in the cargo bay; no crate had ever reached the kitchen.
`sp_reachable_drop_spot()` plans the route as if every door opened, follows it to the first door the
technician's ID does not, and leaves the crate a few tiles short of it on open floor, out of the
doorway (`sp_good_drop_spot()`). They tell the requester where it is on the common channel, and the
request keeps hold of the crate so whoever asked can find it wherever it ended up. The haul's walks
log when they fail, and the tally counts `cargo.delivered`.

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

### Making anything, not just the house menu
`GLOB.sp_cocktails` is the house menu — what a bartender pours when nobody has asked for anything. The
rest of the book is worked out at runtime by `sp_drink_catalogue()`: for every drink reaction in the
game, walk the ingredients back until they are all things one of the two taps holds. That comes to
about seventy drinks on MetaStation, and it means anyone — a player or one of the crew — can name a
drink and get it. The walk recurses, because plenty of drinks are made of other drinks: a cuba libre is
a rum and coke with lime in it, and the reactions cascade on their own once it is all in the glass.

Two things keep the catalogue honest, and both were found by pouring the whole book in a unit test:

- **Ambiguity.** Everything goes in one glass and the reagent system fires whatever reaction it can, so
  a recipe that happens to contain vodka and orange juice makes a screwdriver on the way past whatever
  it was meant to be making. `sp_recipe_is_ambiguous()` drops any drink whose ingredients could form
  some *other* drink — reactions on the intended path excepted, since those are the point. This is what
  removed the Banzai-Tī, which turned into three different cocktails at once.
- **Power.** The taps run off a cell, and `sp_dispense_into()` spends it. Pouring seventy drinks back to
  back runs both machines flat, which in testing looked exactly like broken recipes until the test
  started recharging between rounds of pouring.

Orders are matched on the drink's own name, longest match first so a vodka martini is not served as a
martini. Crew who wander into the bar order off the house menu on their own, which is what gives the
place something to do with no players on.

`GLOB.sp_cocktails` entries each carry the reagent they *become* as well as the parts
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

## Medbay (`sp_medical.dm`)

Medical staff see anybody hurt who has come into medbay, anybody hurt they can see from wherever they
are, and any player who walks into medbay and has not been scanned in the last ten minutes. Somebody down
comes first, then the worst hurt, then the nearest. Two AI medics never take the same patient.

### Looking a patient over
The medic walks up and runs a health analyzer over them, which the patient sees happen. Then
`sp_triage()` decides:

- **Nothing wrong** — "clean bill of health", and on their way.
- **Serious** — in crit, 50+ brute and burn, or 30+ toxin and suffocation (no medkit touches either) — and
  a cryo tube is ready: into the tube.
- **Everything else**, including serious cases when no tube is ready: the medkit.

The medic reads the scan back in plain words ("25 brute, mostly your left arm. Hold still, I'll patch you
up.") and asks an AI patient to hold still (`sp_hold_still`), which puts `sp_crew_patient` in charge of
their tree until the medic is done.

### Treating, a limb at a time
`sp_pick_treatment()` takes the worst limb it can do anything for and the best thing the medic carries for
it, judged by the stack itself (`try_heal_checks`): damage it heals, bleeding it stops, a burn it dresses,
skin it can reach through clothing. Sutures before bruise packs for brute, mesh before ointment for burns.
Gauze is left out — it dresses wounds and heals nothing. Libital and aiuri patches are the fallback, and
go on through clothing a suture cannot.

Two things the old medic got wrong, both found by reading TG's stack code:

- **It always aimed at the chest.** A medkit heals wherever the user is aiming (`zone_selected`), and
  nothing set it for AI crew, so a patient with a cut arm and an unhurt chest got nothing at all. The
  medic now aims at the limb first.
- **Mesh comes sealed.** A full stack from a medkit is still in its packet and refuses to heal until it
  is opened. The medic tears it open (clicks it in hand) before using it.

Sutures and mesh keep going across the body by themselves once started, so one round often does the lot;
the medic waits for their hands to be free before looking again. A patient nothing will help is left
alone for three minutes, and so is one the medic has spent ninety seconds failing to reach.

### Cryo
On MetaStation the cryo room starts the shift not working at all:

- **The gas loop is empty.** Both anesthetic canisters sit on their connector ports unconnected, and a
  tube with under 5 mol of gas turns off and throws its patient straight back out ("Insufficient Gas").
- **The freezer is off**, set to room temperature. Cryoxadone only heals below 273 K.
- **No tube has a beaker.** Four 30u cryoxadone beakers sit on the glass table.

`sp_medical_cryo_setup` does it the way a doctor would: fetch the medical wrench off the table and wrench
a canister onto its port, alt-click the freezer until it reads its coldest (alt-click steps room
temperature → hottest → coldest, so a fresh one takes two), ctrl-click it on, then carry a beaker to each
tube. It announces on the medical channel once everything is done. A tube only uses about 0.04u of
cryoxadone every two seconds, so one beaker lasts roughly 25 minutes of treatment.

Putting somebody in is the ordinary route too: the medic pulls the patient over, alt-clicks the tube open,
drags them onto its tile and alt-clicks it shut. The tube switches itself on once it has an occupant, lets
them out when they are mended, and says so on the medical channel. TG's drag-and-drop only works for a
patient who is incapacitated, so that is used only for somebody out cold who cannot be dragged onto the tile.
The anesthetic mix puts the occupant to sleep, which doubles cryoxadone's effect.

`sp_crew_patient` also stops an AI patient climbing back out. TG's `escape_captivity` subtree treats a
cryo tube as a box to break out of and an operating table as restraints.

### Surgery
Doctors and the CMO operate; paramedics, chemists and the rest do not. Triage sends a patient to the table
for a dislocated or broken bone, and for a serious case when no cryo tube is ready — but only when the
surgeon carries every tool the whole operation needs, so nobody is left cut open halfway.

This build has TG's reworked surgery: no surgery datum, just one operation per click, with each limb's
skin, vessels and bones recorded as flags on the limb. That suits an AI well. `sp_next_operation()` reads
the patient and returns the one next step, so an operation that is interrupted just carries on:

- **Dislocation** — a bonesetter puts it back, no cutting.
- **Hairline fracture** — incise, repair (bonesetter, bone gel or surgical tape), close.
- **Compound fracture** — the wound has already cut the skin: retract, clamp, reset, repair, close.
- **Serious brute and burn** — incise the chest and tend wounds, which loops until that damage is gone.
- **Anything left open** is closed with the cautery before the patient is let up, whatever went wrong.

The patient is strapped to the operating table by the same drag a player uses, which lays them down and
readies every limb (TG's `free_operation`), so no drapes are needed. TG only straps down somebody standing
beside the table, and a patient in tow trails a tile behind the surgeon, so they are stepped up alongside
it first (`sp_bring_alongside`). The first live round failed at exactly that point, twice. The unit test
now starts the patient two tiles from the table.

A surgeon shown a fracture without a bonesetter on them says so, goes to fetch their tools off a theatre
tray and comes back. Anyone else in medical leaves a patient whose only problem is a bone to the surgeons. A jumpsuit is rolled down off the
chest and arms; anything else over the site comes off and goes back on afterwards. Nothing hanging off
the jumpsuit — ID, belt, pockets — is dropped with it.

TG picks the operation off a radial menu whenever more than one fits the tool, and a mob with no client
never gets a menu, so `sp_perform_operation()` finds the operation it wants among those on offer and
starts it the way the menu would. A doctor's medkit has the scalpel, hemostat and cautery;
`sp_medical_surgical_kit` fetches the retractor, bonesetter and bone gel off a theatre surgery tray.

The doctor walks to a tile the tray can be reached from (`sp_reach_spot`), not to "within a tile" of it.
JPS will not end a walk on a diagonal whose two corners are both blocked, though an arm reaches across a
table there, and both trays in MetaStation's theatre sit in a corner between a table and the operating
table. In the second live round a doctor set off for them eight times in fifteen minutes and never arrived,
while the CMO, using the aft room's tray, operated.

Medics with a patient, and a chemist with an order in hand, do not stop to answer chatter
(`busy_with_work()`). A reply outranks the job subtrees and aborts them. An async job such as a brew or an
operation keeps running after the abort while the tree starts it over, so it can end up running twice. In
the third live round the CMO stopped walking a patient to the table to answer a doctor's idle question.

### Restocking
A medic carrying fewer than eight uses of treatment (stack charges plus patches) goes looking for more,
in the order that costs least:

- **A locker or crate in sight** is opened and emptied of stacks, patches and medkits, four things at a
  time. One that has been picked is left for five minutes, whether or not the walk there worked. The
  crate cargo delivers for medbay is found in sight or not: the request keeps hold of it, and it is
  usually left just outside medbay's doors, where a technician's ID stops (`sp_delivered_crates()`).
- **Supplies left for them by name**, botany's burn cream usually, are fetched from wherever the courier
  could put them down, in sight or not (`sp_pick_up_left_supplies()`).
- **Cargo**, at most every ten minutes: a medical supplies crate, through the same request queue the
  rest of the station uses, so the quartermaster orders it and a technician hauls it to medbay. It is
  addressed to the medbay lobby (`sp_medbay_delivery_area()`) rather than wherever the medic is: the
  first medic to ask with the roaming in place asked from the fitness room, and got the crate there.
- **Botany**, at most every ten minutes: aloe, which the botanist microwaves into the burn cream they
  use before bringing it over.

Nobody asks twice: a medic stays quiet while a medical crate is already on order, or while a botanist is
already working on medbay's aloe (`sp_supplies_on_order()`, `sp_plant_requested()`). In the first
restocking round both medics ran dry together and both asked cargo, then both asked botany, ten seconds
apart.

The tally counts `med.restocked`, `med.restock_asked` and `med.botany_asked`.

### Patients
**Seen out.** Medics drag the badly hurt through doors only staff can open, into the cryo tubes and onto
the operating table, and nothing let them out again: a quartermaster who came out of cryo at full health
stood in the cryo room for the rest of the round, unable to walk back to their console, and cargo placed
no orders. A patient let go inside medbay is seen out (`sp_see_out()`): for three minutes their route may
go through medbay's doors, and a medbay door they walk into opens for them as if the desk had buzzed them
through (`sp_buzz_through()`, tally `crew.buzzed_through`). Only medbay's own doors, never a bolted one.

Crew with minor injuries and nothing better to do (`sp_crew_checkup`) walk to medbay when a medic is on
duty, say so, and wait up to two minutes to be seen. The badly hurt do the same from `sp_crew_safety`
straight away. Both now wait until they are treated. The old fixed fifteen-second wait sent a patient back
to their own department every time the safety subtree's cooldown ran.

Patients head for the medbay lobby. The rest of medbay is behind doors only medical staff can open, and
JPS will not path anyone through a door they cannot open. In the first live round, patients picked a spot
on the treatment floor, failed to path there and went back to work. The cut arm and the burned leg never
arrived at all. The medic comes to them in the lobby and takes them through.

## Chemistry (`sp_chemistry.dm`)

The chemist keeps medbay stocked, starting from the basics:

- **Cryoxadone for the tubes** comes first. When the cryo tubes and the cryo room hold under 40u between
  them, the chemist brews a beaker and sets it on the table beside the tubes. The medics' own cryo setup
  loads it when a tube runs dry.
- **Libital and aiuri patches**, the brute and burn patches the medics fall back on, are kept at four of
  each in the chemistry fridge, which medbay reaches into through the wall.

### Why a medicine is planned in stages
A cocktail pours in one go. A medicine cannot. The reactions here run over time and they compete. Libital
is phenol, oxygen and nitrogen. Phenol is water, chlorine and oil, and oil is fuel, carbon and hydrogen.
Pour all of it in together and the hydrogen finds the nitrogen and makes ammonia instead.

`sp_plan_brew()` walks /tg/'s own recipes back to what the chemistry dispenser pours and lays the medicine
out as stages. Each stage adds one reaction's ingredients and lets it finish before the next goes in:

- **Libital:** oil, then phenol, then libital.
- **Aiuri:** ammonia, then aiuri.
- **Cryoxadone:** oil, acetone, mutagen, then cryoxadone.

Two more rules:

- **Nothing else may react in the beaker.** Every stage is checked against every reaction in the game, and a
  stage whose contents would also satisfy some other reaction is refused. The dispenser pours the makings
  of smoke powder and thermite, and a plan that could make either is not one to follow.
- **Whole units only.** The dispenser pours whole units, so the batch is scaled until every addition is a
  whole number (27u of libital is exactly 1u of carbon at the bottom of the tree), then as far as the
  beaker holds.

### Brewing
The chemist works from a bench tile with the dispenser, a heater and a ChemMaster all in reach.
MetaStation builds all three of its benches this way, with a chemist spawn on the standing tile. For each
stage the beaker goes into the dispenser for the additions, then into the heater:

- **Temperature.** The heater holds room temperature when the reaction runs well there, or heats it as
  close to its best as it can with a margin under the point where it overheats. Aiuri is at its best at
  300 K and flashes and bangs at 315 K, so the margin matters.
- **pH.** The heater's buffers keep the pH in range a unit at a time. Libital sours by six and a half pH as
  it forms, and every step made in the acid comes out less pure than the last.

The pH is set before the last ingredient goes in, then held during the reaction. Setting it first is what
counts: aiuri is done in about a second and a half, so a batch that starts at pH 3.6 is over before any
buffer lands. The first test brew of it came out 38% pure.

The unit test brews all three through real machines:

| Medicine | Batch | Purity | Buffer used |
|---|---|---|---|
| Libital | 27u | 98% | about 7u |
| Aiuri | 48u | 100% | about 3u |
| Cryoxadone | 27u | 97% | about 6u |

The heater holds twenty units of each buffer, so the chemist brews in a standard beaker rather than a large
one.

### Keeping the heater's buffers up
Every brew spends buffer. When the bench's heater is under twelve units of either kind, the chemist's next
order is a batch of that buffer (`sp_chem_buffer_wanted`), brewed from the dispenser like any medicine and
drawn into the heater's store the way its draw button does it. Whatever is left of the batch goes down the
ChemMaster. A standard beaker makes 50u of either buffer, basic in two stages (ammonia first) and acidic in
one, and the heater takes all of it; it keeps up to 100u of each.

The second live round showed why this is needed. The chemist brewed libital three times running, each
batch taking about seven units of basic buffer. The aiuri after that had two tenths of a unit left for a
pre-buffer that needs three, and it came out 43% pure. In the unit test, where each brew gets a fresh
heater, the same aiuri is 100%.

A second bug was behind the first. Stock was counted in the fridge only, so patches the chemist was carrying
did not count, and a delivery run that worked still locked a twenty-second pause before the next. Carried
medicine now counts as delivered, and the pause only follows a failed delivery.

Patches come off the ChemMaster, which is driven in code because its print button stops to ask for a name
through a tgui prompt that a mob with no client never answers. Whatever else was in the beaker goes down the
ChemMaster's drain. The chemist is given a beaker and a large beaker to brew in; TG hands them only a dropper.

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
  for ten minutes. What to take is chosen *before* the lid comes up: TG's closets tip their whole
  contents onto the floor as they open, and reading the contents afterwards found an empty box, so
  until this was caught the crew opened lockers all shift and took nothing (`sp_rummage_container()`).
  A locker they had to unlock is locked again behind them (`sp_relock()`): a research director left
  their own unlocked, and the next scientist to wander past helped themselves to a bio hood.
- **Pocketing.** Anything lying on the *floor* that matches their tastes is picked up in passing, on the
  same cooldown as rummaging, so it is the odd find rather than a sweep. Only the floor: what is on a
  table or a rack was put there by somebody, and the chef's ingredients, the chemist's patches and a
  beaker of cryoxadone waiting for a tube are not finds. Nor is the floor of hydroponics or the kitchen,
  where the botanist's harvest lands before it is gathered and the chef stocks up. Something they have
  decided about is left alone for ten minutes.
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

## Crime and witnesses (`sp_crime.dm`)
The greytide's malicious streak and the antagonists ask the same two questions before they do anything
dodgy: who can see me, and what happens if they do? One place answers them.

- `sp_witnesses(culprit)` — everyone awake, sighted and on their feet who can see the culprit.
- `sp_crime_witnesses(culprit)` — the ones who would *tell*: any player, and AI crew whose
  `reports_crimes()` is true. Assistants never grass, and a crew member running a scheme of their own
  (`BB_SP_SCHEME` set) keeps their head down.
- `sp_crime_seen(culprit, crime, description, where)` — rolls each would-tell witness; the first to
  notice calls it out (`sp_call_out_crime`): a shout at the culprit ("Hey! Put that back!"), a hit to
  their standing, and, with a headset, a report to security naming a **suspect and a place** rather than
  an attacker. Crimes are `SP_CRIME_THEFT`, `_VANDALISM`, `_TRESPASS`; the incident record carries
  `SP_INCIDENT_SUSPECT` and `SP_INCIDENT_CRIME` so a suspect with no attacker can route to *investigate*
  rather than *baton*.

**What security does about it.** A report naming an attacker is unchanged: baton, cuffs, "area secure". A
report naming a *suspect* and no attacker goes to `sp_security_confront`, which ranks directly below the
violent response and above everything else an officer does. They walk over and have a word — the line
chosen by the crime ("That is not yours. Hand it over.") — think less of them for it, and write it up
(`sp_file_crime_record()`, tally `sec.confronted` and `sec.recorded`).

The record is the memory, and the ladder is a word, then a word and a note, then an arrest. This fork has
no "suspected" status between None and Arrest, and flagging Arrest puts every secbot on the station onto
somebody over a light tube, so the wanted status is left alone until the record itself shows a pattern.
Past `SP_CRIMES_BEFORE_ARREST` prior crimes the officer calls it in, `sp_mark_for_arrest()` sets
`WANTED_ARREST`, and the suspect becomes an ordinary target for the response above (tally
`sec.arrest_ordered`). Anyone who swings at the officer escalates themselves: the security controller's
`on_attacked` already makes an attacker of them.

Seen in a round at last: `filed Vandalism against Calvin Stern (1 on record)` through to `(4 on record)`,
then `had a word with Calvin Stern about vandalism in Aft Primary Hallway`, then `called an arrest on Calvin
Stern (4 crimes on record)` -- `sec.confronted=1 sec.recorded=4 sec.arrest_ordered=1`. The ladder itself works
end to end. What happens *after* the arrest does not yet, and the two shooting guards above are the reason:
the officer emptied his disabler into a fleeing chef without downing him, so nobody was ever cuffed and the
cell was never reached.

## Command (`ai/sp_hos_behaviors.dm`)
The head of security is the only member of the department who gives orders rather than only taking them, and
has a controller of their own for it. Everyone else in security -- officers, the warden, the detective --
shares `/datum/ai_controller/sp_crew/security`, because `sp_controller_for_job()` maps by department; the head
of security is tested before that, the way the chemist is tested before medical.

**Orders ride the same rails as crime reports.** `sp_issue_order()` writes the order onto the issuer's own
blackboard (`BB_SP_LAST_ORDER`) and *then* says it aloud on the security channel, and `on_pre_hear` reads it
off the speaker at the moment it hears them. Nothing is broadcast to a roster, so an officer out of radio
contact genuinely misses it and a head of security with no headset gives no orders at all. One order per
utterance, because a second would overwrite the first before anybody had read it.

**The alert ladder has no yellow.** This fork is green, blue, red, delta, so heightened-but-not-lethal is blue.
Reports naming an attacker are counted (`BB_SP_VIOLENCE_SEEN`); blue comes after `SP_ALERT_BLUE_AFTER` and red
after `SP_ALERT_RED_AFTER`. Going red is also where lethal force is authorised -- deliberately not at the
briefing, so two orders are never spoken in one breath.

**Briefings.** `sp_hos_call_meeting` names a spot and stands on it; whoever heard walks over and waits there
(`sp_security_meeting`, ranked below an active attacker and above idling). `sp_hos_brief` says one thing per
meeting: arm, under red, or stand down otherwise.

Seen in a round: `Hayden Ann ordered meeting`, two officers logging `took meeting from Hayden Ann`, then
`ordered stand_down` -- `sec.meeting_called=1 sec.meeting_attended=3 sec.briefed=1 sec.order_heard=4`. Three
attendees because the head of security stands on their own spot; four orders heard because two officers each
took two. Arming stayed empty, which is what a green shift should look like.

**Arming is bounded by who holds the keys.** The access rules make this ladder, not a designer picking one:

- *Spawn* -- a disabler in the suit slot, handcuffs, a flash. No baton, which is why `sp_equip_item/baton` had
  been failing since the fork began and officers brawled bare-handed.
- *Their own locker* -- `ACCESS_BRIG`, which officers carry. It holds `/obj/item/storage/belt/security/full`,
  and the baton is in that belt. `sp_find_arm_locker` picks the nearest one it has confirmed holds a belt, and
  clears the order outright if the officer already has a baton anywhere in their contents, which is what makes
  the behaviour stop rather than loop.
- *The armoury* -- `ACCESS_ARMORY`, on exactly two trims in the game: the head of security and the warden. No
  officer can open it, so nothing sends them there.

**Shooting.** Officers have carried a disabler in their suit slot since the fork began and never fired it,
because `sp_attack_target` tests `Adjacent()` before it swings. That test is the leaf's own, not a limit of
the interaction layer: `ai_interact()` only checks both parties exist, then calls `ClickOn()`, and a gun
clicked at something across the room fires at it. So `sp_shoot_target` is a sibling of the melee leaf rather
than new machinery, and the respond tree now runs secured, then incapacitated, then *shoot*, then close and
swing. Shooting until somebody goes down and then cuffing them is how the arrest loop was always meant to
work. With no gun, no line of sight, or a target out of range, the branch fails and the old baton path runs
exactly as before.

Two guards on that leaf were both bought with a round. **It will not fire through anybody**: TG's own ranged
attack checks this and I skipped it as apparatus I did not need, whereupon a briefing gathered the department
onto one spot and an officer shot the head of security in the back on his way to a monkey. She batoned him,
`on_attacked` made an attacker of her, and he downed and cuffed his own commanding officer -- who then spent
the round in `escape_captivity`, which outranks `sp_hos_command`, so she never reached a single command
decision and the alert never rose. One missing guard took out the entire escalation path.

**And an empty gun is not a gun.** A disabler holds twenty shots (`e_cost = LASER_SHOTS(20, ...)`). An officer
who spent them kept pulling the trigger on nothing -- the leaf went on succeeding, so the selector never fell
through -- and then beat a fleeing chef across four rooms with the dead weapon, because `sp_equip_item/baton`
had no baton to find. `can_shoot()` now fails the leaf instead, which hands the problem to the melee branch;
that branch is only any good once the officer has fetched their belt, which today needs an arming order.

`sp_take_arm_kit` equips nothing: the belt goes in the pack, and `sp_equip_item` finds the baton inside it
because `get_all_contents_type()` walks into containers.

### Fetching kit rather than being handed it

`kit_wanted()` on the controller says what a job ought to be carrying and was not handed at spawn, best
first. `TryPossessPawn` raises the same blackboard key an arming order does when that list is non-empty, so
one subtree serves both a roundstart kit and a red alert, and the pick leaf ends it once there is nothing
left worth fetching. Security is the first through: officers go to their own locker for the belt, which is
where the baton lives.

It is three mechanisms, not one, and which a department gets is decided by where its kit actually is:

- **A locker** -- security (`ACCESS_BRIG`, eleven on MetaStation), botany (`ACCESS_HYDROPONICS`, three),
  chemistry (the medicine closet, `ACCESS_MEDICAL`, three).
- **A vendor** -- the kitchen. The knife and rolling pin are stocked by the dinnerware vendor and exist in no
  locker at all. Different code, though SP already drives that vendor for the bartender.
- **Keep handing it over** -- the botanist's watering can exists in no locker, no vendor and no outfit; it is
  a Family Heirloom quirk and a mail reward, neither of which a clientless crew member will ever see.
  Engineering keeps everything, because what it is handed is not kit but station-wide ID access, without
  which JPS will not path an engineer through an airlock to a breach.

**Check before removing a handout.** Four times while working this out a search returned nothing and I read
it as "the item does not exist": the rolling pin (vendor stock is declared `typepath = count`, which a search
for `new /obj/item/...` cannot match), the map (map files place *containers*; contents appear at runtime from
`PopulateContents`), beakers (they come in boxes), and the watering can (found in a list that turned out to be
quirk heirlooms). Three of those were wrong. Removing a handout on the strength of one is how a department
stops working for good -- a botanist sent after a watering can that no locker holds simply never waters
anything again.

**A closed closet is empty.** `PopulateContents()` runs from `dump_contents()` the first time a closet is
opened, not at `Initialize` -- only `populate_contents_immediate()` puts anything inside before that. So
`get_all_contents_type()` on an unopened locker returns nothing, and the check meant to stop officers walking
to a locker with no belt in it rejected all six correct belt lockers on MetaStation instead, and sent nobody
anywhere. `sp_find_arm_locker` now only trusts the contents of a closet somebody has already opened
(`contents_initialized`); an unopened one is worth the walk, and the take leaf fails harmlessly if it turns
out to be bare.

**And opening one empties it onto the floor.** `dump_contents()` populates the closet and then moves every
item to `drop_location()`, so a moment after an officer opens their locker the belt is on the turf beside
them rather than inside the thing they just opened. A leaf that opens a container and then searches *it* will
find nothing, every time; `sp_reachable_item()` looks at what the pawn carries and then at `range(1, pawn)`,
which is why the antagonist's theft leaf uses it and why the kit leaf now does too.

**Which is why `kit_wanted()` names a locker type, not just an item.** Because an unopened closet cannot be
searched, a finder that accepts any unopened closet has no notion of where a thing lives, and the first round
with fetching working showed what that costs: an officer spent five minutes walking to a *pajama wardrobe in
the Dormitories* to look for a security belt, opened it, found nothing, and would have gone on to the next
wrong closet. The rule now is that an unopened closet is taken on its type and an opened one on its contents
-- which also, neatly, is what lets an officer draw an energy gun from an armoury the head of security has
just unlocked, since that closet's contents are known by then.

**And the trip has to be sticky.** With the right lockers finally being chosen, only one officer in three came
back with anything. None of them failed at a locker -- `opened ... but found no ...` never appeared once --
they simply never arrived. The pick leaf re-runs whenever the sequence restarts, which a briefing or an
incident causes constantly, and it chose the *nearest* locker each time: so an officer pulled away mid-journey
retargeted from wherever he now stood. One walked between three security posts in five minutes and reached
none of them. The officer who succeeded was simply the one nobody interrupted. Keeping the existing target
while it is still a plausible source fixes it without reordering the tree, which is right -- a briefing should
outrank fetching a belt; losing the journey every time you are called away should not.

**And the pairing has to name the exact subtype.** MetaStation carries `secure_closet/security` and its
`/cargo`, `/engine`, `/med` and `/science` variants at the departmental posts, plus six `/sec` in the locker
room -- and only `/sec` adds `/obj/item/storage/belt/security/full`. The rest inherit the parent's vest,
helmet, HUD and seclite and no belt at all. Pairing the item with the *family* meant `istype()` matched every
one of them, so an officer walked to Security Post - Medbay, opened the locker, and found nothing he wanted:
`opened security officer's locker but found no /obj/item/storage/belt/security to take`. A type pairing is
only as good as its narrowest correct type.

**And then the answer was that they were simply walking.** With the trip sticky and the right subtype named,
a progress line every thirty seconds finally showed what three rounds of silence had hidden: `still 16 tiles
from security officer's locker`, and fourteen seconds later, `drew security belt`. One officer set off at
06:49:02 and arrived at 06:54:50 -- nearly six minutes for a single locker trip across MetaStation, with
briefings and incidents interrupting throughout. Nothing was broken by then; the rounds had been ending
first. Three officers, three belts, once the round was long enough to contain the walk. Worth remembering
before reading a low count as a fault: check the denominator, and check the clock.

**The armoury rung was aimed at furniture this map has not got.** `sp_hos_find_armoury` looked for
`armory1`, `armory2`, `armory3` and `tac` closets; MetaStation has none of them. It has an armoury *room*
(31 tiles of `/area/station/security/armory`) but the weapons are elsewhere: parsing the map's key blocks
puts all four `/obj/item/gun/energy/laser` either on the same tile as `secure_closet/warden` -- and so inside
it, since a closed closet swallows what sits on its turf -- or on a rack in `/area/station/security/range`.
So the search correctly found nothing for seven rounds, and every explanation offered for that silence
(timing, thrashing, the rung never being reached) was wrong about an assumption nobody had checked.

The warden's locker is now in the target list: `ACCESS_ARMORY`, holding a laser, a full security belt,
zipties and flashbangs. Once the head of security opens it its contents are known, which the kit finder's
"opened closet" branch already handles, so the rung needed a corrected target rather than new machinery.

**And there is no energy gun on this map at all**, which matters twice over. The red-alert extension asked
for an `e_gun` and could never have got one; it now asks for a laser. And `sp_set_fire_mode` is inert here:
a disabler and a laser each carry one casing type, so there is no mode to switch between. It earns its place
only on a map or a round where an actual energy gun turns up, and is kept for that rather than deleted.

The armoury finder had the same thrashing fault and it went unnoticed for six rounds, because the rung that
depends on it had never once fired. What exposed it was the *officer* side working: with red alert up and an
arming order given, an officer reported `no locker they can open holds /obj/item/gun/energy/e_gun` -- exactly
right, since the armoury was still locked and the head of security had never walked over to open it. A stage
that reports itself accurately turned out to be the thing that found the bug in a different stage entirely.

## The cell (`sp_crime.dm`, the jail branch of `sp_security_respond`)
Cuffing somebody used to be the end of it: the officer said "area secure" and walked off. A cuffed prisoner
with something on their record now gets walked to a cell.

**The sentence is read off the record.** `sp_sentence_time()` gives two minutes for each crime already written
down, capped at ten. Somebody with no record serves nothing, which is not a special case: the ladder in
`sp_confront_suspect()` is what puts crimes on a record at all, so anyone who has reached an arrest already
has something to measure. The cap earns its keep -- the brig timer's own `set_timer()` clamps at `MAX_TIMER`
(15 minutes) without a word, and a sentence the machine quietly shortened would read as a bug in the ladder
rather than in the cap. `sp_sentence_escalates` pins that relationship so neither number can drift into it.

**Finding a cell is the awkward half.** A `door_timer` is wall-mounted and collects its doors, flashers and
closets by a shared `id` anywhere within `urange(20)`, which says nothing at all about which side of a door is
inside; areas are no help either, since several cells share `/area/station/security/brig`. The door and the
locker between them do. A brig windoor blocks the edge its `dir` faces, so its own tile and the tile past that
edge are the two sides, and the cell is the side the linked brig locker stands on (`sp_cell_doorway()`). The
first version sent prisoners onto the locker's own tile, which a closed locker makes solid, and jailed nobody.
`sp_free_cell()` skips a cell without a clear doorway. All three MetaStation cells have one: checked against
the map file, each door sits on the corridor tile facing south, with the cell tile beyond it.

**The walk.** `sp_find_cell` takes hold of the prisoner -- `start_pulling`, and `sp_hold_still()`, which has
purchase only on AI crew, so a player walks off and the escort copes instead of assuming compliance. It refuses
a corpse or anybody out of reach, and keeps the prisoner in `BB_SP_PRISONER`, not in the incident key a fresh
report would overwrite. The officer walks onto the inside tile, which leaves the prisoner they are pulling on
the outside one, and steps back out. TG lets a puller swap places with whoever they are pulling
(`can_mobswap_with()`), but not shove a restrained person past the one pulling them, and that shove is what
the first version tried. The swap leaves the officer outside and the prisoner in, `timer_start()` shuts the
door between them, and the record reads Incarcerated. Every way the escort can fail lets go of the prisoner
(`sp_abandon_escort()`), and the incident is closed only if it is still about this prisoner.

Not yet handled, and not yet seen in a live round: a prisoner lying down is not dense, so there is nobody to
swap with; a door that shuts itself during the swap fails the escort; and a report arriving mid-walk still
pulls the officer away, because the branch is gated on the incident key rather than the prisoner.

## Antagonists (`sp_antagonist.dm`, `ai/sp_antagonist_behaviors.dm`)
An antagonist is an ordinary AI crew member carrying a **scheme** (`/datum/sp_scheme` on the blackboard
at `BB_SP_SCHEME`): a goal at odds with the station, and the score-keeping for it. The behaviour tree is
how it is pursued. This is deliberately not TG's `/datum/objective` — those assume a client (an
assassinate objective against a clientless NPC completes on the spot, because no-client reads as AFK) and
the round-end report prints a blank key for a keyless mob.

- `/datum/sp_scheme/steal` — get hold of one item and keep it. The target comes from TG's own steal
  catalogue (`/datum/objective_item`, e.g. the CMO's hypospray), so it is a thing the game already knows
  is on the map, without the objective/uplink machinery. `sp_pick_steal_target()` chooses one that
  exists and this crew member does not already own; `sp_make_thief()` attaches the scheme.
- `/datum/ai_controller/sp_crew/antagonist` (tree `sp_crew_antagonist.bt.json`) wants the scheme's target
  even though it is on no interest list, and stays on task through chatter (`busy_with_work()`).
- `sp_crew_scheme.bt.json` ranks below self-preservation and above idle wandering: find the goal (the
  item, or the locker it is in), walk to it, take it (a `do_after`, witnessed as theft), then lie low.
  Completing a scheme is logged and tallied (`antag.scheme_done`, `antag.stole`), never announced.

Bridging to TG's own antagonist system — so the round counts them, shares codewords and prints a
round-end line — is possible with a silent, uplink-less traitor datum, but it is **off by default**
(`SP_ANTAG_TG_DATUM`): with no client the round-end report shows a blank key and codewords reach a crew
of NPCs. The scheme drives behaviour either way. `SP_DEBUG_ANTAGONIST` turns one crew member into a
thief ninety seconds in; the admin verb **SP: Spawn Antagonist (Thief)** does it on demand.

## Greytide: assistants (`sp_greytide.dm`)
One to three assistants join at roundstart on top of `SP_AUTOPOPULATE` (`SP_ASSISTANTS_MIN` and
`SP_ASSISTANTS_MAX`, 1 and 3 by default). They have no department and no work, and they get everything the
rest of the crew do (patients, drinks, chatter, curiosity), tuned a notch towards mischief:

- **Tool storage first.** Early in the shift they walk to Primary Tool Storage, put on insulated gloves
  (MetaStation only has the budget sort lying about) and pocket a tool. Three trips at most.
- **Nosier.** They rummage twice as often, take up to three things, and leave the locker hanging open. They
  try doors twice as often too, and grumble cheekier when the door says no.
- **Tastes.** Gloves, masks, toys and one tool, on top of the four anyone rolls.
- **Their own kit.** A crayon each, and a bike horn or a rubber duck for about half of them.
- **Somewhere to start.** An assistant who spawns outside their haunts starts in one of them instead
  (`sp_send_to_post()`). One of MetaStation's assistant spawn points is inside the cargo delivery office,
  behind shipping-access doors and delivery flaps, and the assistant who spawned there in the second
  greytide round never got out.

Every three to six minutes an assistant in the mood (60%) looks round for a prank and pulls one of whatever
is on offer where they are standing:

| Prank | What happens | Tally |
|---|---|---|
| Graffiti | a star, a corgi, a heart... in crayon on a hallway, maintenance or commons floor | `tide.graffiti` |
| Lights out | the switch in a room with people in it, "Boo!", six seconds of dark, lights back on | `tide.lights` |
| Knock | two or three knocks on a window into command, security or the AI's rooms, "Let me in!" | `tide.knock` |
| Bell | a desk bell rung a few times from the public side of the counter, "Service!" | `tide.bell` |
| Honk | the horn or the duck, at whoever is nearby | `tide.honk` |
| Vandalism | a lit tube in a public room smashed dark until somebody replaces it — troublemakers only | `tide.vandalism` |

The rules keep it fun. Nobody gets hurt, and nothing gets through a door. Most of the menu breaks nothing
either; the one thing with an edge, a smashed light tube, is off the harmless list. Only some assistants
have that streak (`BB_SP_TROUBLEMAKER`, rolled at spawn, ~45%), it is gated by `SP_GREYTIDE_MALICE` (on by
default), it happens only in the same public rooms the lights-out prank uses, and a witness calls it out
(`sp_crime_seen`, `SP_CRIME_VANDALISM`) like any other crime. Nobody pulls a prank
with an officer in sight (they look again a minute later, when security has walked on), and one turning up
on the way calls it off. Each decision is logged ("is up to something", "not in the mood", "thinks better
of it, with security about", "found nothing to get up to"). The lights always come back on: by
the switch, or, if the assistant has been pulled away, by the prank putting them back itself. The crayon
designs are the friendly end of the menu, with no chalk outlines, runes or slogans, and they are left for a
janitor to clean once there is one. A prank under way is not interrupted by a chat (`busy_with_work()`).
Tool storage trips count as `tide.geared`.

## Taking over a role (`sp_role_takeover.dm`)
The AI crew fill the station's jobs at roundstart, and TG counts them exactly like players: a job they hold
is full, and the join screen greys it out. In a singleplayer game that locked the one real player out of
every head of staff, the bar and the chemistry lab. Now a job held by AI crew is never locked:

- **The join screen** shows it as open, counting only players against it. `IsJobUnavailable` still runs
  every check TG makes (bans, playtime, the latejoin special cases); it just stops treating AI crew as full.
- **Picking it** frees a place just before TG assigns the job, after every check that could still turn
  the player away. The first AI holder goes: a dead one first (their body stays, it just stops counting),
  then one who is idle, and only then one in the middle of a job. A medic going off shift unstraps their
  patient and lets them go.
- **Going off shift** means a line to whoever is nearby ("Looks like my relief is here"), off the manifest
  and the locked records, bank account closed, and gone from the round two seconds later. TG has no way to
  free a job slot at all (no cryo, and nothing decrements `current_positions`), so the clean-up is ours,
  along the lines of the admin "retcon" smite. The tally counts it as `crew.relieved`.

At roundstart none of this comes up: TG gives readied players their jobs before the station is populated,
and the AI crew fill what is left.

## Getting to work
Two things make sure a crew member is where their job is.

`sp_send_to_post()` runs at spawn. `SSticker.PostSetup()` deletes the roundstart landmarks the moment
the populate callback yields, and that race is not reliably won — when it is lost, *every* job falls
back to the arrival shuttle. That is worse than untidy: the shuttle then leaves, taking the whole crew
to a z-level their department is not on, where every job subtree quietly finds nothing to do. So a
crew member who lands at arrivals is put where they were assigned instead.

`sp_crew_commute` is the safety net for everything else. Any crew member standing outside their own
department walks back to it. Every job subtree looks for its work near where it is standing, so without
this a displaced crew member does nothing at all and looks fine doing it.

## Movement
SP crew use `/datum/ai_movement/jps/sp_crew`, which raises the path limit from TG's
`AI_MAX_PATH_LENGTH` (30 tiles, tuned for animals that lose interest after 14) to 220. Without it no
crew member can walk to medbay, the engine room, or an incident on the far side of the station.

Plastic flaps tell the pathfinder that anyone may walk through them, then stop anyone standing up. A crew
member with the access for what lies behind a set of flaps gets routed into them and stands there until the
walk gives up. In the second live round the Head of Personnel did this all shift with a cut arm: their way
to medbay ran through the maintenance flaps in front of the bridge's delivery windoor, so they never
arrived. The module overrides `/obj/structure/plasticflaps/CanAStarPass` so standing mobs are not planned
through flaps.

Animals are the other thing the pathfinder does not see: it ignores mobs, and TG will not swap places with
one in combat mode, which every basic mob is. The Head of Security's giant spider sits in the one gap
between the desk and the security consoles, and in the third live round the HoS spent the whole shift
bumping into their own pet. Crew now step round an animal that will not budge and is not after anybody
(`sp_step_past()`, from the bump handler); the tally counts it as `crew.stepped_past`.

Both of those were invisible at first, because a walk that fails inside a cooldown logs nothing and looks
like somebody who set off and changed their mind. The walks to medbay, to a surgery tray and to the
chemist's bench and drop-off now use `move_to_target/sp_reported`, which logs
`X could not walk to Y at ... from ...` when the walk fails.

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
- `sp_triage` — unhurt goes home, a cut arm gets the medkit, seventy damage goes to cryo only when a tube
  is ready.
- `sp_pick_treatment` — the medic aims at the hurt limb (not the chest) and picks sealed mesh for a burn.
- `sp_treat_a_patient` — a real round through the medic's own clicks: mesh torn open, twenty burn gone.
- `sp_cryo_loading` / `sp_cryo_freezer` — a beaker goes in, a conscious patient is dragged onto the open
  tube and shut in, and the freezer ends up on and at its coldest.
- `sp_brew_plans` — libital, aiuri and cryoxadone plan down to the dispenser in whole units, in 3, 2 and 4
  stages, and the basic and acidic buffers in 2 and 1, all within a 50u beaker.
- `sp_brew` — all three brewed for real through a dispenser and heater, each checked for amount and purity.
- `sp_chem_print` — 27u of libital prints three 9u patches, the rest is drained and the patches picked up.
- `sp_chem_buffer` — an empty heater's first order is basic buffer; both buffers are brewed and drawn into
  the heater, and a topped-up heater wants no more.
- `sp_surgery_plan` — a hairline fracture reads as incise, repair, close, then nothing.
- `sp_surgery_hairline` — the whole operation on a patient in a jumpsuit: strapped down, jumpsuit rolled,
  three operations, bone mended, skin closed, jumpsuit back up, patient let up.
- `sp_surgery_tray_reach` — a tray boxed in by tables is reached from the open diagonal, and that is where
  the doctor is sent to stand.
- `sp_flaps_pathing` — the pathfinder does not plan a standing human through plastic flaps.
- `sp_busy_ignores_chatter` — a doctor with a patient and a chemist with an order do not queue a reply to
  chatter; a doctor with nobody to see still takes it up when spoken to by name.
- `sp_trees_talk` — every crew controller's tree can answer, look up at a name and start a chat, and greeting
  a newcomer is not behind the chat cooldown.
- `sp_speech_whole_words` — "they" is not "hey", "tomorrow" is not "Tom", a bare "hi" is a greeting, and the
  most specific request in a line wins.
- `sp_distress_needs_urgency` — a list of calls for help that must count and calm requests that must not.
- `sp_answer_once` — being thanked moves standing once, as the answer is given; a name alone gets a look up;
  an answer 15 s late is dropped without moving anything.
- `sp_crew_exchange` — two crew hold a whole chat through real speech: the opener is heard once, the reply
  tells the opener it was answered, the closer starts nothing, and neither side is left holding a key.
- `sp_one_answer_per_line` — a hello gets one answer, from the nearer crew member whichever hears it first; a
  hello naming the other one is theirs; a crew member already owing an answer passes it on.
- `sp_security_answers` — an officer mid-arrest does not stop to chat, and a free one answers.
- `sp_role_takeover` — a CMO slot filled by two AI crew: the dead one's place is freed with the body left
  where it is, then the living one goes off shift, off the manifest and the locked records, bank account
  closed, and out of the round.
- `sp_greytide_graffiti` — an assistant draws one of the friendly designs on the floor with their crayon.
- `sp_greytide_bell` — a desk bell rung more than once.
- `sp_greytide_lights` — lights out in a room with somebody else in it, and back on afterwards.
- `sp_greytide_gear` — assistants get their own controller, leave lockers open and take more from them;
  budget insulated gloves go on, a crowbar goes in the bag, and then there is nothing left to want.
- `sp_pocket_from_floor` — a crayon on the floor is picked up; one set out on a table is left alone.
- `sp_medic_restock` — a medic with nothing counts as low, empties the medical crate beside them, and
  does not count as low afterwards.
- `sp_botany_request` — "Botany, send some aloe to medbay" reads as a request, a passing mention of
  aloe does not, and the aloe they carry is what was asked for.
- `sp_rummage_takes` — something a crew member fancies comes out of a locker and onto them, and the
  locker is shut again.
- `sp_rummage_relocks` — a locker they had to unlock is shut and locked again.
- `sp_restock_asks_once` — a medical crate on order, or aloe a botanist is already after, counts as
  asked for; a delivered crate no longer does.
- `sp_crate_matches_order` — a crate is matched to its request by the order number on it: not by a
  number that only ends the same way, and not by the pack's name.
- `sp_crate_claims` — a crate another technician is heading for is left to them.
- `sp_drop_spot_short_of_door` — a delivery behind a door the courier cannot open is left on their
  side of it and out of the doorway; with the access, it goes all the way.
- `sp_medic_finds_delivery` — a crate cargo delivered for medbay is found out of sight; one nobody
  delivered is not.
- `sp_botany_cooks_request` — aloe medbay asked for goes through a real microwave and comes out as the
  burn cream that is then the delivery.
- `sp_medic_takes_left_supplies` — cream left for a medic by name is found out of sight, picked up, and
  crossed off.
- `sp_request_names_destination` — "send some aloe up to medbay" goes to medbay, a request naming
  nowhere goes where the asker stands, and medbay's own asks are addressed to medbay.
- `sp_patient_shown_out` — a patient let go in medbay may route through, and open, medbay's doors for
  a while; not anybody else's, and not before they have been seen.
- `sp_requested_seed_first` — a requested seed goes into an empty tray ahead of a nearer tray that
  wants water, a tray picked too recently is passed over, and once the plant is growing the request
  stops jumping the queue.
- `sp_scheme_steal` — a steal scheme reads incomplete until the pawn carries the target, complete once
  they do, and a schemer does not report crimes.
- `sp_crime_witnesses` — who would tell (not assistants, not schemers); a callout drops standing and, with
  a headset, files a suspect incident with no attacker.
- `sp_break_light` — the malicious greytide's one built behaviour leaves a lit tube dark.
- `sp_steal_target_liftable` — a scheme's target has to be liftable: on the floor or in a closet counts, sealed
  in a box or carried by somebody does not.
- `sp_steal_target_reachable` — and it has to be somewhere this thief can actually walk to: wall the room off
  and the same liftable item stops being a target.
- `sp_security_confronts_suspect` — a report naming a suspect and no attacker sends an officer to have a
  word; one naming an attacker still sets the baton target.
- `sp_crime_record_escalates` — crimes accumulate on the record, somebody with no record is left alone, and
  only a pattern turns the next word into an arrest.
- `sp_order_relay` — an order from the head of security reaches whoever hears it and changes only what it
  names: arming is not permission to kill, standing down puts the lethal weapon away but lets a kit trip
  finish, and nobody takes orders from themselves.
- `sp_arming_finds_nested_baton` — an officer starts with no baton, and one carried belt is enough to put one
  in their hand without unpacking anything. This is the claim the whole arming rung rests on: if the search
  ever stopped walking into containers, fetching a belt would still log and still tally, and the officer would
  still be empty-handed.
- `sp_sentence_escalates` — a cell sentence is measured off the record, two minutes a crime, and a long rap
  sheet is capped rather than unbounded. The last assertion is the one that matters: the cap must stay under
  the brig timer's `MAX_TIMER`, because `set_timer()` clamps without saying so, and a sentence the machine
  quietly shortened would read as a bug in the ladder rather than in the cap.
- `sp_cell_doorway_faces_the_locker` — a timer with nothing linked has no doorway; the cell is the side of
  the door's edge the locker stands on, including a locker level with the door, where plain distance ties;
  and a doorway with something solid in it is no doorway.
- `sp_closed_closet_is_empty` — a freshly built locker reports nothing inside it, and opening it produces the
  belt that was there all along. This pins an assumption about upstream rather than about our own code: the
  locker search may only trust the contents of a closet somebody has opened. If TG ever populates closets at
  Initialize instead, this test fails loudly, where otherwise the symptom would be another silent round in
  which nobody fetches anything and nothing says why.
- `sp_behaviour_trees` — every SP controller points at a tree that was actually compiled.

```
tools\build\build.bat build --define=UNIT_TESTS
<BYOND>\bin\dd.exe tgstation.dmb -close -trusted -verbose -params log-directory=ci > tests.out
```
Use `UNIT_TESTS`, not `CIBUILDING`: the CI build splits the tests across maps and silently skips these.
`PASS`/`FAIL` lines go to stdout, so capture it; `data/logs/ci/clean_run.lk` says `Success!` when the
whole suite passed. The full suite takes a while, so while working on a few tests, put
`TEST_FOCUS(/datum/unit_test/...)` lines at the bottom of the test file to run just those, and take them
out again afterwards. The station is not populated in a unit-test build. The tests run with a round going,
and seventeen AI crew getting on with their shift in the background made TG's own tests
nondeterministic. SP's tests build whatever they need themselves. Stop any running server first — a live `dd.exe` holds `tgstation.rsc` open and the
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

Medbay adds `med.scanned`, `med.treated`, `med.cryo_setup`, `med.cryo_loaded`, `med.cryo_discharged` (and
`med.cryo_lost`), `med.surgical_kit`, `med.surgery` and `med.operations`, plus `crew.checkup` and
`crew.seen_to` from the patients' side. `SP_DEBUG_MEDICAL_PATIENTS` hurts four crew ninety seconds in, so
all of medbay can be watched in one round:

- a cut arm and a burned leg, for the medkit
- a serious case, for cryo
- a broken arm, for the table

The chemist adds `chem.brewed` (batches), `chem.patches` (printed), `chem.stocked` (put in the fridge),
`chem.cryoxadone` (beakers left in cryo) and `chem.buffer` (units drawn into the heater).


**A headless run ends in a segfault, and it means nothing.** `dd.exe` reports every test, prints
`Shutdown complete` with each subsystem closing in order, and then the process dies on final teardown. The
results above it are complete and trustworthy -- there are no runtimes and no hard-deletion warnings before
it. Worth knowing before you go looking for a crash in your own code, as I did.
## Headless test loop
```
tools\build\build.bat build
<BYOND>\bin\dd.exe tgstation.dmb 7777 -trusted -close -logself -params log-directory=sp_test
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
- Overridden from inside the module rather than edited in place: `/obj/structure/plasticflaps/CanAStarPass`
  (`ai/sp_crew_behaviors.dm`), so JPS stops planning standing mobs through flaps they cannot cross; and
  `/mob/dead/new_player/IsJobUnavailable`, `/datum/controller/subsystem/job/assign_role` and
  `/datum/latejoin_menu/ui_data` (`sp_role_takeover.dm`), so jobs held by AI crew stay open to players.

## Known limitations
- Crew wander randomly inside their areas; no schedules or work objects yet.
- Breach repair patches floors only. Broken walls, windows and airlocks are left alone, and nobody
  re-pressurises the room afterwards.
- Threat detection is line-of-sight and weapon-in-hand only; concealed weapons do not scare anyone.
- Security uses melee and cuffs, never the disabler in their suit slot.
- Cargo never sells anything, works the mining or materials markets, or handles the express console;
  there are no miners yet. Crates are dragged, so a technician moves one at a time, and a haul that
  has not finished within two minutes is abandoned where it stands rather than blocking the
  quartermaster's paperwork behind it. Nobody goes back for an abandoned crate.
- Machine lookups here deliberately avoid `oview()`. It is sight-limited, so a console one room away
  behind a wall is invisible and the quartermaster would never find their own desk.
- Botanists do not compost, fight pests, or use grafts and the DNA manipulator.
- An antagonist has not yet been seen completing a theft in a live round. The scheme attaches, picks a
  target and reports honestly when it cannot reach one, and the parts are unit-tested, but the whole
  chain — walk to it, take it, keep it — is still unproven in play. Two rounds' worth of reasons are
  written up in `docs/02-antagonist-plan.md`.
- Schemes can only steal, and only from TG's own steal catalogue filtered down to things actually
  liftable (out on a turf, or in a closet this thief can open). Most of that catalogue is deliberately
  locked away, so the choice is narrow. Sabotage, framing and escape-with-the-loot are not written.
- The cell has never actually been used in a round. Reaching it organically wants three witnessed crimes by
  the same person, and the greytide spaces mischief minutes apart behind a coin-flip of a troublemaker roll,
  so a short round cannot get there. What has been proven is the parts: the sentence ladder, the landmark
  guard, and that none of it throws. The walk itself resists a unit test -- pulling, `Move_Pulled()` and
  `timer_start()` all want a real cell with linked doors and a locker, which the test map has not got.
- None of the escalation above red has been seen in a round yet. The alert ladder, the armoury, the arming
  order and the fire-mode switch are built and tested, but a quiet shift never reaches red, so what has
  actually been watched end to end is a briefing and a stand down. `SP_DEBUG_SECURITY_ALARM` exists to force
  the rest; until a round runs with it, treat the red-alert path as compiled rather than proven.
- The lawyer takes no orders at all, being in `/datum/job_department/service` rather than security, and so
  running the ordinary crew controller with no security behaviour on it.
- Antagonist theft still does not fire on a fresh station, but the reason is now measured rather than
  guessed. The funnel logs where it closed -- `52 catalogued, 15 on the map, 12 with a copy somewhere, 1
  liftable, none of those reachable` -- and then retries that one at a budget nobody could exceed and again
  with every door open: `ablative trenchcoat in Armory, 13 tiles off, budget 220: 21 steps with every door
  open, so it is access`. Not the catalogue, not the lift rule, not the path budget, all of which were
  theorised and all of which were wrong. TG's steal list is a challenge built for a player traitor with an
  emag; a crew member who can open only what their own ID opens will correctly find nothing on it.
- Security's answer to a petty crime stops at a word and a note. An officer confronts a witnessed thief,
  files it, and a pattern on the record becomes an arrest — but they will not demand the stolen item back,
  search anybody, or do anything with the brig, so a thief who keeps walking keeps the loot.
- The greytide's malicious streak is one behaviour (a smashed light tube). Emptying a locker and stashing
  the loot, prying a door, and slips in the hallway are planned, not built.
- Mutagen reliably pushes a plant's instability into the 20-50 band, where stat mutations happen. A
  full species change needs it sustained above 60, which competes with the plant stabilising between
  doses, so new species are occasional rather than routine.
- No hunger/sleep handling (trait-suppressed).
- Without a chemist on the station nobody refills cryoxadone, so the cryo tubes run on whatever beakers the
  round started with.
- Surgery covers bones and tending serious damage. No organ repair, prosthetics or reattached limbs, no
  defibrillation or blood transfusions, and no anesthetic: TG does not penalise operating on somebody
  awake, so patients simply feel it.
- Only brute, burn and bleeding are treated with the medkit. Toxin and suffocation go to cryo or nowhere.
- The chemist makes the basics only: libital and aiuri patches and cryoxadone. No multiver, epinephrine or
  pills, and nothing needing the grinder, cold recipes or catalysts.
- The chemist only tops up the heater at the bench they are brewing at, and only once it runs low. The
  other two benches keep the twenty units each that they started with.
- Medics do not yet collect patches from the chemistry fridge. They treat with what they carry, and players
  can take from the fridge.
- Conversation has no dialogue trees yet: crew answer one line at a time rather than tracking a
  thread with a player, and standing is not yet spent on anything (following, favours, access). The plan
  for branching NPC-NPC and NPC-player dialogue is in `docs/01-dialogue-plan.md`; the chat bugs it listed to
  fix first (its milestone M0) are fixed.
- Nothing an assistant does gets through a door, starts a fight, or puts anything in anybody's face.
  Hacking, slips and lube are antagonist territory rather than theirs.

## Next
- The janitor, and the clown.
- Written dialogue lines, on the engine sketched in `docs/01-dialogue-plan.md` (M1 and M2), which is where
  the seven hard-coded topics stop being hard-coded.
- The security gaps above: the three cases the cell escort cannot handle yet, and the warden's side of the
  brig, which is a session of its own.
