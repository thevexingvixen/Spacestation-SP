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

## Movement
SP crew use `/datum/ai_movement/jps/sp_crew`, which raises the path limit from TG's
`AI_MAX_PATH_LENGTH` (30 tiles, tuned for animals that lose interest after 14) to 220. Without it no
crew member can walk to medbay, the engine room, or an incident on the far side of the station.

## Local dev config
`config/dev_overrides.txt` (gitignored; copy from `../../docs/dev_overrides.example.txt`) enables
AUTOADMIN, a 10 s lobby, `RESUME_AFTER_INITIALIZATIONS` for headless tests, `SP_AUTOPOPULATE`, and
the engine settings.

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
- `code/_compile_options.dm` — the optional `SP_BREACH_DEBUG` flag.
- `tgstation.dme` — include lines for this module.

## Known limitations
- Crew wander randomly inside their areas; no schedules or work objects yet.
- Breach repair patches floors only. Broken walls, windows and airlocks are left alone, and nobody
  re-pressurises the room afterwards.
- Threat detection is line-of-sight and weapon-in-hand only; concealed weapons do not scare anyone.
- Security uses melee and cuffs, never the disabler in their suit slot.
- Botanists do not compost, fight pests, or use grafts and the DNA manipulator.
- Mutagen reliably pushes a plant's instability into the 20-50 band, where stat mutations happen. A
  full species change needs it sustained above 60, which competes with the plant stabilising between
  doses, so new species are occasional rather than routine.
- No hunger/sleep handling (trait-suppressed).
