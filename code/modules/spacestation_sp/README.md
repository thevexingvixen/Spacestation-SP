# Spacestation SP module

Singleplayer additions to /tg/station. Everything SP-specific lives in this folder (plus
`code/__DEFINES/spacestation_sp.dm`) so the fork can be rebased onto upstream.

## Files
- `sp_config.dm` — config entries. `SP_AUTOPOPULATE <n>` spawns `n` AI crew at round start.
- `sp_subsystem.dm` — `SSspacestation_sp`: tracks AI crew, hooks round start for auto-populate.
- `sp_crew_spawner.dm` — `sp_spawn_crew_member(job)` and `sp_populate_station(count)`: client-less
  human crew creation using the normal `SSjob.equip_rank` path, manifest injection, and AI attach.
  `sp_controller_for_job(job)` picks the controller by department (medical, security, else base).
- `sp_admin_verbs.dm` — Fun tab: "SP: Populate Station", "SP: Spawn Crew (Job)".
- `ai/sp_crew_controller.dm` — `/datum/ai_controller/sp_crew` (+ `/medical`, `/security`).
  Hearing hook on `COMSIG_MOVABLE_PRE_HEAR` (client-less mobs never reach `Hear()`), attack memory,
  `TRAIT_NOHUNGER` while controlled (no needs subtree yet).
- `ai/sp_crew_behaviors.dm` — leaves: `sp_pick_wander_turf` (random walkable turf in a set of areas),
  `sp_say` (+ `need_medic`, `greet`), `sp_equip_medical_item`; strategy `sp_treatable_patient`.
- Trees (`ai/*.bt.json`, compiled by the build into `build/behavior_trees/`):
  - `sp_crew` — parallel: [escape captivity > safety > social > department wander > idle walk] with
    ambient chatter as the secondary branch. Also used by the security controller (patrol areas
    come from the blackboard).
  - `sp_crew_medical` — as above plus `sp_medical_treat` before social/wander.
  - `sp_department_wander` — pick turf in `BB_SP_WANDER_AREAS` (or home area) → JPS move → linger.
  - `sp_crew_safety` — health below `BB_SP_HURT_THRESHOLD`: shout for a medic, walk to medbay, wait.
  - `sp_crew_social` — someone said our first name: face them, answer, clear the key.
  - `sp_medical_treat` — find a patient with ≥10 brute/burn, pull the right medical stack out of our
    inventory, walk adjacent, apply it.

## Blackboard keys
See `code/__DEFINES/spacestation_sp.dm`. Heard speech is kept in `BB_SP_HEARD` (last 12 entries:
speaker weakref, name, message, time, radio flag) — this is the observation feed the future LLM
sidecar will read.

## Local dev config
`config/dev_overrides.txt` (gitignored; copy from `../../docs/dev_overrides.example.txt` at the
project root) enables AUTOADMIN, a 10 s lobby, and `RESUME_AFTER_INITIALIZATIONS` so headless
test rounds start with no client connected.

## Headless test loop
```
tools\build\build.bat build
E:\games\BYOND\bin\dd.exe tgstation.dmb 1337 -trusted -close -logself -params log-directory=sp_test
```
Then read `data/logs/sp_test/{game,runtime,dynamic}.log`; SP lines are prefixed `SP:`.
Kill `dd.exe` before recompiling.

## Upstream touch points (keep this list short)
- `code/controllers/master.dm` — do not put the world to sleep after init when
  `RESUME_AFTER_INITIALIZATIONS` is set (the vanilla order slept the world before it could resume).
- `tgstation.dme` — include lines for this module.

## Known limitations
- Crew wander randomly inside their areas; no schedules or work objects yet.
- Hearing only triggers a greeting on first-name mentions; radio is recorded but not acted on.
- No hunger/sleep handling (trait-suppressed); no fight/flee reaction beyond remembering attackers.
- Medical treats brute/burn only, and only what a doctor already carries.
