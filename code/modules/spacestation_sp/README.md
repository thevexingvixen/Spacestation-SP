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
- `sp_admin_verbs.dm` — Fun tab: "SP: Populate Station", "SP: Spawn Crew (Job)".
- `ai/sp_crew_controller.dm` — `/datum/ai_controller/sp_crew` and the `/medical`, `/security`,
  `/engineer` subtypes. Hearing hook, incident routing, attacker memory, `TRAIT_NOHUNGER`.
- `ai/sp_crew_behaviors.dm` — leaves, decorators, targeting strategies and subtree declarations.

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

## Local dev config
`config/dev_overrides.txt` (gitignored; copy from `../../docs/dev_overrides.example.txt`) enables
AUTOADMIN, a 10 s lobby, `RESUME_AFTER_INITIALIZATIONS` for headless tests, `SP_AUTOPOPULATE`, and
the engine settings.

## Headless test loop
```
tools\build\build.bat build
E:\games\BYOND\bin\dd.exe tgstation.dmb 1337 -trusted -close -logself -params log-directory=sp_test
```
Then read `data/logs/sp_test/{game,runtime}.log`; SP lines are prefixed `SP:`. Kill `dd.exe` before
recompiling, and touch a changed file if the build says "Skipping 'dm' (up to date)".

## Upstream touch points (keep this list short)
- `code/controllers/master.dm` — do not sleep the world after init when
  `RESUME_AFTER_INITIALIZATIONS` is set.
- `tgstation.dme` — include lines for this module.

## Known limitations
- Crew wander randomly inside their areas; no schedules or work objects yet.
- No hull-breach repair yet: engineers manage power only.
- Threat detection is line-of-sight and weapon-in-hand only; concealed weapons do not scare anyone.
- Security uses melee and cuffs, never the disabler in their suit slot.
- No hunger/sleep handling (trait-suppressed).
