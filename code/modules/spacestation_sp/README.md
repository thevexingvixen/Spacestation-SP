# Spacestation SP module

Singleplayer additions to /tg/station. Everything SP-specific lives in this folder (plus
`code/__DEFINES/spacestation_sp.dm`) so the fork can be rebased onto upstream.

## Files
- `sp_config.dm` — config entries. `SP_AUTOPOPULATE <n>` spawns `n` AI crew at round start.
- `sp_subsystem.dm` — `SSspacestation_sp`: tracks AI crew, hooks round start for auto-populate.
- `sp_crew_spawner.dm` — `sp_spawn_crew_member(job)` and `sp_populate_station(count)`: client-less
  human crew creation using the normal `SSjob.equip_rank` path, manifest injection, and AI attach.
- `sp_admin_verbs.dm` — Fun tab: "SP: Populate Station", "SP: Spawn Crew (Job)".
- `ai/sp_crew_controller.dm` + `ai/sp_crew.bt.json` — the base crew behavior tree
  (escape captivity > wander) with ambient chatter running in parallel.

## Local dev config
`config/dev_overrides.txt` (gitignored; copy from `../../docs/dev_overrides.example.txt` at the
project root) enables AUTOADMIN, a 10 s lobby, and `RESUME_AFTER_INITIALIZATIONS` so headless
test rounds start with no client connected.

## Upstream touch points (keep this list short)
- `code/controllers/master.dm` — do not put the world to sleep after init when
  `RESUME_AFTER_INITIALIZATIONS` is set (the vanilla order slept the world before it could resume).
- `tgstation.dme` — include lines for this module.
