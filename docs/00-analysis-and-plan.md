# Spacestation SP — Session 1: Analysis of TGStation + BYOND, and a Plan

Date: 2026-09-05
Scope: read-only survey of the BYOND install and the /tg/station snapshot. No project files changed.

---

## 1. Environment status

| Item | Found | Needed | Status |
|---|---|---|---|
| BYOND install | 515.1625 (Jan 2024) | >= 516.1659 (TG hard-errors below this); 516.1685 is the pinned version in `dependencies.sh` / `.tgs.yml`; 516.1660 is explicitly blacklisted | **BLOCKER — upgrade BYOND** |
| TG snapshot | zip of `tgstation-master`, no `.git`, changelogs through 2026-09, PRs ~97722 | — | fine, but see git note below |
| Node | 24.14.1 on PATH | build.bat vendors its own Node + bun anyway | ok |
| bun | not installed | tgui needs bun (1.2.16 in `tgui/package.json`, 1.3.5 in `dependencies.sh`) | build script downloads it |
| Python | 3.14 | 3.11 wanted only for mapmerge tooling | ok for now |
| rust_g.dll 6.2.0, dreamluau.dll 0.1.2 | shipped in repo root | — | ok (32-bit, matches BYOND) |
| SQL | not set up | not required: `ADMIN_LEGACY_SYSTEM` is already on in `config/config.txt` | ok |

### BYOND lookup by the build script
`tools/build/lib/byond.ts` finds `dm.exe` in this order: `DM_EXE` env var, `tools/build/dm_versions.json` (entry with `default: true`), `C:\Program Files\BYOND`, `C:\Program Files (x86)\BYOND`, then the registry key `HKLM\Software\Dantom\BYOND\installpath`. Installing 516 somewhere other than the default location is fine if we either point `DM_EXE` at its `bin\dm.exe` or create `dm_versions.json`.

Download: https://www.byond.com/download/build/516 — pick **516.1685** (not 516.1660).

### Git note
The snapshot has no history. Recommendation: `git init` in `tgstation-master`, commit the vanilla snapshot as the baseline, then do all SP work on a branch. Later we can add `https://github.com/tgstation/tgstation` as `upstream` for rebasing.

### Compile/run facts
- `BUILD.cmd` -> `tools/build/build.bat build` (builds tgui with bun, then `dm.exe tgstation.dme`). ~7,450 `.dm` files; expect several minutes per compile. Iteration cost is real, which is where dreamluau (runtime Lua) helps during development.
- `RUN_SERVER.cmd` -> builds then starts Dream Daemon. Security level must be **Trusted** (native DLLs).
- Build defines worth knowing (`tools/build/build_flags.json`): `AUTOSTART_GAME`, `FORCE_MAP`, `SKIP_LAVALAND`, `SKIP_SPACE_LEVELS`, `MINIMAL_CENTCOM`, `DISABLE_DREAMLUAU`. The `LOW_MEMORY` preset = runtimestation + no lavaland/space ruins.

---

## 2. Singleplayer admin setup (what TG already gives us)

- **Admin without SQL:** `config/config.txt` has `ADMIN_LEGACY_SYSTEM` on and `AUTOADMIN_RANK Game Master`. Uncommenting `AUTOADMIN` gives every connecting client Game Master. Alternative: add `yourckey = Game Master` to `config/admins.txt`.
- **Local overrides without dirtying the repo:** create `config/dev_overrides.txt` (see `config/dev_overrides_readme.txt`). Applied after `config.txt`.
- **Lobby:** `LOBBY_COUNTDOWN 120` (set to ~10), or compile with `AUTOSTART_GAME`.
- **Maps:** `config/maps.txt` has `minplayers` gates (Meta 25, Delta 50, Tram/Nebula 35). Kilostation (`maxplayers 40`) and Runtime Station (debug, tiny) are eligible at pop 1. Override via `FORCE_MAP` define or edit `maps.txt`.
- **Round start with 1 player:** `SSticker` -> `SSdynamic.select_roundstart_antagonists()` -> `SSjob.divide_occupations()`. Nothing requires more than one ready player. Dynamic tiers all have `min_pop = 0`; with pop 1 you'll get Greenshift/Low Chaos and **no antagonists**, because rulesets only consider `/mob/dead/new_player` with a client (see `trim_candidates` in `code/controllers/subsystem/dynamic/_dynamic_ruleset.dm`). AI crew will never be antag candidates through vanilla dynamic; that has to be ours (Section 4).

---

## 3. What TG already has for NPC crew

### 3.1 The AI controller / behavior-tree framework (`code/datums/ai/`)
- `/datum/ai_controller` attaches to any `/mob/living` (`mob.ai_controller`). State lives in a string-keyed **blackboard**. Behavior is a **behavior tree** loaded from JSON (`*.bt.json`), with Selector / Sequence / Parallel / Subtree composites, decorators (signal-observing conditions), and leaf `ai_behavior` nodes. Docs: `code/datums/ai/README.md`, `code/datums/ai/learn_ai.md`. A VS Code extension ("BehaviorTreeG") is the intended editor; CI checks compiled trees (`.github/workflows/check_bt_compiled.yml`).
- Ticked by `SSai_controllers` (plans every 0.25 s, has per-controller cost tracking) and `SSai_movement`. Movement strategies: `ai_movement_jps` (real pathfinding), `basic_avoidance`, `dumb`. JPS takes an **access list** and `controller.get_access()` defaults to `pawn.get_access()`, so an NPC wearing an ID card paths through doors it has access to. Ventcrawl and space handling are already parameters.
- **Humans already accept AI controllers.** `/mob/living/carbon/human/monkeybrain` uses `/datum/ai_controller/monkey`. The monkey tree (`code/datums/ai/monkey/`, ~400 lines of nodes) already does: pick up items from ground, pickpocket, find best weapon, attack, disposal-stuffing, serve food (Pun Pun bartender), idle emotes. That is our template for a humanoid crew controller.
- **Reusable generic leaves** (`code/datums/ai/generic_behaviors/`): `move_to_target`, `pick_up`, `use_in_hand`, `use_on_object`, `give`, `grab_target`, `drag_target`, `stuff_in_disposal`, `attack_obstacles`, `acquire_target`, `acquire_injured_target`, `speech` (random_speech; calls `pawn.say(..., forced = "AI Controller")`), `perform_emote`, `random_walk`, `resist`, `break_out_of_object`, `wait`, `set_bb_key`, `write_on_paper`, `find_flee_location`. Bot subtrees: `bot_patrol`, `bot_respond_to_summon`, `bot_salute_authority`.
- Humanoid combat NPCs already exist as `/mob/living/basic`: `trooper/*` (ranged + melee, Syndicate/NT/pirate/Russian), `revolutionary` (shouts slogans, picks weapons). These are *basic* mobs (simple health, no organs); real crew should be `/mob/living/carbon/human` so medical, forensics, IDs, and antag mechanics all work.
- Admin tooling exists: `admin_ai_templates.dm` lets an admin slap a hostile/ranged controller onto any living mob via VV. Good for early testing.

### 3.2 Gaps for "crew" NPCs (things we must write)
- **No hearing hook.** No AI code registers `COMSIG_MOVABLE_HEAR` or overrides `Hear()`. Needed so NPCs can react to speech/radio (and to feed an LLM).
- **No job-routine trees** (janitor, doctor, sec, engineer...). Only monkey/pet/bot/hostile behaviors.
- **No client-less crew spawner.** `job.get_spawn_mob()` and `apply_prefs_job()` assume a client and qdel the mob otherwise. But `SSjob.equip_rank(mob, job, null)` is null-client safe, `job.get_roundstart_spawn_point()` exists, and `mind_initialize()` works without a key. So a spawner is: `new /mob/living/carbon/human(spawn_turf)` -> randomize appearance/name -> `mind_initialize()` -> `mind.set_assigned_role(job)` -> `SSjob.equip_rank(...)` -> manifest injection -> attach `/datum/ai_controller/crew/<job>`.
- **Antag assignment for NPCs.** `mind.add_antag_datum(/datum/antagonist/traitor)` is mind-based and should work client-less, but objective/uplink generation needs verification. Dynamic must be bypassed or subclassed.
- **Sanity/needs.** TG humans have mood, hunger, sleep. NPCs need a "maintenance" subtree (eat, go to medbay when hurt, flee fire/vacuum) or trait exemptions early on.

### 3.3 External-integration surfaces (for the LLM route)
- **rust_g HTTP** — `code/datums/http.dm`: `/datum/http_request` with `begin_async()` / `is_complete()` / `into_response()`. Non-blocking. This is the natural bridge from DM to a local sidecar.
- **`SStts`** (`code/controllers/subsystem/tts.dm`) is a complete worked example of a subsystem that queues HTTP requests to a local server, caps concurrency (`max_concurrent_requests = 4`), times out, and tracks latency. Copy its shape for an `SSagent_bridge`.
- **`world/Topic`** (`code/game/world.dm`, handlers in `code/datums/world_topic.dm`) for inbound pushes from a sidecar, if ever needed. Polling from DM is simpler and avoids exposing Topic.
- **dreamluau** (`code/modules/admin/verbs/lua/`, `lua/SS13.lua`): admin-run Luau with full access to datums/procs, timers, signals. Hot-scriptable mob control without recompiling. Excellent for prototyping behaviors and for an "LLM writes Lua" experiment, though the production controller should be DM.

---

## 4. Two approaches, and the recommended hybrid

### A. Programmed behaviors (behavior trees)
Pros: zero API cost, deterministic, runs at 0.25 s cadence, framework and dozens of leaves already exist. Cons: every job routine is hand-written; conversation is canned; complex tasks (atmos, construction, chemistry) are expensive to encode.

Suggested tiers:
- **Tier 0 ambient crew:** spawn in department, wander within department areas, idle emotes/lines, react to being attacked (fight/flee), seek medbay when hurt, head to arrivals/evac when the shuttle is called.
- **Tier 1 job routines (start with 3):** Security (patrol via `bot_patrol` logic, arrest = `grab_target` + cuffs on flagged targets), Medical (`acquire_injured_target` + apply medkit via `use_on_object`), Bartender (Pun Pun's `monkey_serve_food` is nearly done). Then Janitor (mop decals), Cargo, Chef.
- **Tier 2 antagonists:** traitor tree = pick objective target, acquire weapon (`monkey_find_weapon`), wait until alone with target, attack, hide body (`drag_target` + `stuff_in_disposal` or maintenance), avoid security. This is the core singleplayer loop (player as detective/sec/captain investigates).

### B. LLM-driven agents
DM can't sensibly call Claude directly, so: DM -> rust_g async HTTP -> local **sidecar** (Python, Anthropic SDK) -> Claude with tool use -> JSON commands -> DM executes. Observation payload per agent: location/area, visible mobs and items, inventory, health, recent hearing log, objectives, radio traffic. Command vocabulary: `goto(area|atom)`, `say(text, channel)`, `pick_up(item)`, `use(item, target)`, `attack(mob)`, `follow(mob)`, `wait`. Commands are *high-level*; the behavior tree executes them.

Cost sketch (order of magnitude, for budgeting only): 10 agents deciding every 30 s for a 60-minute round is about 1,200 calls. With prompt caching and a Sonnet-class model for crew and Opus-class only for the 1–2 antagonists (or a single "director" agent), this is affordable for playtesting but not free. Haiku 4.5 is fine for ambient chatter.

### Recommended: hybrid, BT first
1. Build the behavior-tree crew (A) as the *motor layer*. It is needed regardless: the LLM must issue commands to something that can walk through doors and hold a toolbox.
2. Add the sidecar bridge (B) as an *intent layer* on top: initially one LLM-driven traitor plus a director that assigns goals, and only later talkative crew. Everything the LLM does maps to a BT command, so a failed API call degrades to autonomous BT behavior.

---

## 5. Roadmap

**Phase 0 — Toolchain (blocking).** Install BYOND 516.1685; point the build at it (`DM_EXE` or `tools/build/dm_versions.json`); run `BUILD.cmd`; `git init` + baseline commit; run `RUN_SERVER.cmd`, connect with Dream Seeker, confirm 0 errors and that Dream Daemon is on Trusted.

**Phase 1 — Singleplayer config.** `config/dev_overrides.txt` with `AUTOADMIN`, `LOBBY_COUNTDOWN 10`; choose map (Runtime Station for fast iteration, MetaStation for real play); verify a 1-player round starts and the admin panel works. Try the existing admin AI templates on a spawned human to feel the framework.

**Phase 2 — Client-less crew spawner.** New module `code/modules/spacestation_sp/` with an `SSsp_crew` subsystem or admin verb "Populate Station (N)". Spawns humans at job spawn points, equips via `SSjob.equip_rank`, injects into the manifest, attaches `/datum/ai_controller/crew`. Base tree = Tier 0 ambient behavior. Deliverable: a station that feels inhabited.

**Phase 3 — Job trees.** Security, Medical, Bartender first. Add the hearing hook (`COMSIG_MOVABLE_HEAR` -> blackboard "recent_heard") so crew respond to "help" and to radio.

**Phase 4 — SP antagonist director.** Subsystem that, at round start and midround, picks AI crew and applies antag datums (traitor first), bypassing dynamic's client checks. Traitor BT as in Tier 2. This is the first genuinely playable milestone.

**Phase 5 — LLM bridge prototype.** Python sidecar + `SSagent_bridge` modeled on `SStts`. One LLM-driven agent; measure latency, cost, and behavior quality. Then a director agent and 2–3 conversational crew.

---

## 6. Decisions (2026-09-06)
1. **Admin:** `AUTOADMIN` in a local, gitignored `config/dev_overrides.txt` (committed copy: `docs/dev_overrides.example.txt`).
2. **BYOND:** upgraded to 516.1687; the registry key points at the install, so the build script finds it unaided. Blocker cleared.
3. **API budget is small.** Consequence for Phase 5: put as much agent logic as possible in the Python sidecar (state tracking, heuristics, batching, prompt caching, deciding *when* a model call is even needed). The model is reserved for director-level decisions and on-demand dialogue; behavior trees do everything second-to-second.
4. **Repo:** local git initialised. `main` = vanilla baseline commit, `spacestation-sp` = working branch. Private GitHub remote is the user's to-do.
5. **Map:** no `default` line exists in `config/maps.txt`, so TG falls back to the code default (MetaStation). Left as-is for now; Runtime Station via `FORCE_MAP` when we need fast iteration.

---

## 7. Progress log

### 2026-09-06 — Phases 0, 1 and 2 done
- **Phase 0 (toolchain):** BYOND 516.1687 found via registry. `BUILD.cmd` succeeds: 0 errors, 0 warnings, ~100 s total (tgui ~15 s, DM ~65 s). Git: `main` = vanilla baseline, `spacestation-sp` = work branch.
- **Phase 1 (SP config):** `config/dev_overrides.txt` (AUTOADMIN, 10 s lobby, no map vote, RESUME_AFTER_INITIALIZATIONS, SP_AUTOPOPULATE 12). Headless server (`dd.exe tgstation.dmb 1337 -trusted -close -logself -params log-directory=sp_test`) initializes in ~54 s on MetaStation. Found and fixed an upstream quirk in `code/controllers/master.dm`: the world was put to sleep one tick *before* the resume flag was applied, so a client-less server never left the lobby. Rounds now start headless (dynamic tier 2, "Roundstart: No rulesets to pick from!" as predicted with 0 players).
- **Phase 2 (AI crew):** new module `code/modules/spacestation_sp/` (see its README). Headless test: 12 AI crew spawned across Captain, HoP, CE, CMO, Curator, Detective, Botanist, Miner, Lawyer, Cook, Assistant, Engineer, each in the right office; behavior trees tick (crew wander and speak their ambient lines, logged as `GAME-SAY ... FORCED by AI Controller`); 0 runtime errors. Admin verbs "SP: Populate Station" and "SP: Spawn Crew (Job)" under the Fun tab.
- **Known limits of the base crew tree:** they wander randomly (not within their department yet), have no hearing, no needs handling, and no job behaviour. The manifest log stays empty at round start because manifest logging happens per player join; records themselves are injected.

### 2026-09-06 (later) — Phase 3 first cut done
- **Department wandering** (`sp_department_wander`): pick a walkable turf in the crew member's own area (or a per-job area list), JPS-path there, linger. Security patrols hallways + security; medical staff roam medbay rooms.
- **Hearing:** `Hear()` returns early for client-less mobs, so the controller listens on `COMSIG_MOVABLE_PRE_HEAR`, keeps the last 12 heard lines in `BB_SP_HEARD` (the future sidecar's observation feed), and sets an attention target when someone says the crew member's first name; the social subtree faces them and answers.
- **Safety:** below 60 health → shout for a medic (30 s cooldown), walk to medbay, wait. Hunger is trait-suppressed for now.
- **Medical:** `sp_medical_treat` finds anyone with ≥10 brute/burn in view, pulls the matching suture/mesh out of the doctor's own medkit, walks adjacent and applies it.
- **Headless test:** 12 crew, medical/security controllers chosen by department, crew observed changing rooms inside their departments, 0 runtime errors. Not yet exercised headless: hearing/greeting, medical treatment, medbay run (need a player or a scripted injury).
- **Join problem (open):** Dream Seeker logs in as Guest ("problem reaching byond.com") and the server never sees the connection (no `access.log`, no `isbanned()`), so the handshake dies inside BYOND before TG code runs. hub.byond.com ports 6001/20002 are reachable from this machine and no firewall rules or AV detections mention BYOND. Most likely the pager is simply not logged in; first thing to try is signing into the pager and joining again.

### 2026-09-06 (evening) — Threat reaction, incident reporting, and the engineer
- **Essential jobs guaranteed.** `sp_populate_station` now fills heads, then one engineer, one security officer and one doctor, then everyone else. Also fixed an index bug that skipped a job whenever one was removed from the rotation.
- **Weapon awareness.** A `sp_scan_threats` leaf runs continuously and flags any conscious, visible human holding a gun, a melee weapon or anything with force ≥12, unless they are security or command. The crew then warn them by name and back off to a 4-7 tile band.
- **Attack reporting.** Being hit stores the attacker, and the crew report it over the radio when they wear a headset, or shout it locally when they do not. The report carries a structured record so any AI who hears it knows the attacker and the location.
- **Security response.** Security hearing a report (or a player shouting "help") acknowledges on the security channel, walks to the scene, equips a baton, closes in and attacks. Once the suspect is incapacitated they cuff them, then announce the area is secure. Attacking a security officer directly makes them the suspect.
- **Engineer keeps the lights on.** When the main engine is inactive or more than 20% of station APCs drop below 30% charge, the engineer says so over the engineering channel, walks to the engine room and runs the /tg/ cold-loop setup: nitrogen canisters connected and opened, loop pumps at max, filters on, freezers at minimum, chamber vents' pressure bound raised, chamber scrubbers set to waste gases only, every SMES maxed and solars on auto tracking.
- **Simulated engine output by default.** Energizing the crystal reliably needs a tuned waste loop, and early tests delaminated it (integrity fell from 100% to 27% in four minutes). So the crystal stays cold: once the chamber holds ≥400 moles of ≥90% nitrogen the engineer declares the engine online and the subsystem feeds `SP_ENGINE_SIMULATED_OUTPUT` kW (default 1500) into the engine-room SMES units. `SP_ENGINE_REAL_EMITTERS` enables the real thing for later tuning.
- **Watchdog.** Disables circulation if the chamber falls below 250 moles, pauses emitters for 2 minutes on the first temperature warning, and scrams for 10 minutes with a radio call if integrity drops.
- **Headless test:** 12 crew with the essential three present, both engineers ran the loop setup, engine online after ~40 s, SMES charge climbing 325 → 373 MJ over five minutes, crystal at 100% integrity, 0 runtime errors.

### 2026-09-07 — Hull breach repair
- **Detection.** A breach is a space turf inside a station area that still has a real floor next to it. Solar arrays and catwalks are made of space turfs with no adjacent floor, so they never match, and an area blacklist covers the rest. `SSspacestation_sp` walks a twelfth of the station's areas per five-second tick, so a full sweep costs almost nothing.
- **Repair.** Engineers announce the breach on the engineering channel, put on the EVA softsuit and helmet SP now issues them, open their emergency oxygen, take out the RCD every engineer already spawns with, walk to a safe tile beside the hole and lay plating over it. Plating on space costs 3 matter and is instant, so one RCD patches about 50 tiles; when it runs dry they say so.
- **Long-range pathfinding fix.** TG caps AI paths at 30 tiles (`AI_MAX_PATH_LENGTH`), which is fine for animals that lose interest after 14 tiles but left crew unable to reach anything across the station. SP crew now use a JPS movement datum with a 220-tile limit. This silently fixes medbay runs, security response and engine trips too.
- **Debug tool.** `SP_DEBUG_BREACH_COUNT <n>` punches n holes in a random room a minute after round start, so the behaviour can be exercised headlessly.

### Port conflict that broke local joins
Razer Synapse's `RzSDKServer` listens on `127.0.0.1:1337`. A loopback-bound socket beats Dream Daemon's wildcard bind, so `byond://127.0.0.1:1337` connects to Razer and fails the BYOND handshake while the game server logs nothing. **Run the server on another port (7777).**

### 2026-09-07 — Botanist
The AI botanist runs a full crop cycle. It picks the tray that most wants attention (harvest first,
then dead plants, weeds, water, then planting an empty tray), puts the right tool or seed packet in
hand, walks over and works it. Harvested produce lands at their feet, so they gather it up, leave a
couple of samples out on a hydroponics table every few minutes, and carry batches of five or more to
a kitchen table for the chef, announcing it on the service channel. The watering can gets refilled at
a water tank when it runs dry.

TG only issues botanists an apron and a plant analyser, so SP hands them a hoe, a full watering can
and two packets each of six seed types drawn at random from a weighted pool. The pool leans towards
things a chef can cook with a tail of the botanist's own interests, so the garden is different every
round. Verified headless: one botanist planted eight trays with six crops and began harvesting, with
zero runtime errors.

### 2026-09-07 — Deeper botany, then conversation
Botanists now buy seed varieties they have never grown from the MegaSeed Servitor out of their own
wages, carry produce whose species they lack packets of to a seed extractor, and run mutagen
experiments. They commit to one tray for an experiment and keep returning to it, because instability
only pays off near 60 and dosing whatever is nearest would never finish anything. Species changes are
occasional rather than routine, since plants stabilise between doses; stat mutations are common.

Conversation followed. Two crew near each other with nothing urgent on hold a real exchange, with the
listener reading the topic off the speaker's controller so replies match what was said. Players get
keyword answers to the things they predictably ask, get greeted once on arrival, and hear the odd
station-wide remark. Every exchange moves a standing score that already colours the answers, and
being attacked cuts a conversation off outright.

### Roadmap (user's plan, 2026-09-07)
1. ~~**Botanist** — grow and harvest plants, leave produce for the chef.~~ Done.
1b. ~~Seed vendor, seed extractor, mutations.~~ Done.
1c. ~~Conversation when a player or crewmember is near, with standing underneath it.~~ Done.
2. ~~**Cargo / Quartermaster.**~~ Done. Requests are first-class: any crew member calls
   `sp_request_supplies()`, the QM orders it against the cargo budget and answers by name on the
   supply channel, and a technician walks the crate to the department that asked. With nothing
   requested the QM keeps a small standing restock moving. Miners are deliberately out of scope.
3. ~~**Chef.** Cooks with botany's produce plus what cargo brings, and puts finished food on the
   counter. Draws its supplies through the cargo request queue.~~ Done.
4. ~~**Bartender** — serve drinks.~~ Done.
5. ~~**Janitor** — mop decals and clean up.~~ Done, with the clown: the janitor fetches a mop, keeps it
   wet and works through the map's decals; the clown honks, leaves peels where they are only funny, and
   asks botany for more bananas.
6. ~~**Security** — use the disabler instead of melee, and jail suspects in the brig.~~ Done to the cell
   door: the confrontation ladder (a word, a note on the record, an arrest), the head of security's
   command layer, kit fetched from the department's own lockers, and a sentence served in a cell. The
   warden's side of the brig is deliberately left for its own session.
7. **Antagonist / grey-tide assistant behaviour** — the SP antagonist director. Greytide assistants are
   done; the antagonist foundation (schemes rather than TG objectives) is in place, and theft is still
   held up by what a crew member's own ID can open.
8. **Python sidecar** — reads `BB_SP_HEARD` and station state, few high-value model calls.
9. **Dialogue trees + spending standing** — player conversations that track a thread, and crew
   agreeing to follow someone they think well of. The bug list that came first (`01-dialogue-plan.md`
   M0) is done, and so are M1 and M3: memory, a closed and validated vocabulary, reply links and a Talk verb.
   What is left is spending standing on things crew will do for you.

Also outstanding: tune the real supermatter loop so `SP_ENGINE_REAL_EMITTERS` can become the default.

### 2026-09-23 — A stand-in for the player

With nobody free to sit at the keyboard, the player's side of conversation was tested by a tool that plays it:
the stand-in (`sp_stand_in.dm`), a body the crew treat as a player, which pays a scripted visit in a live round,
logs everything it hears as a player's-eye transcript, and clicks reply links through the same `Topic()` call a
real click ends in. Its third visit passed 13 of 14 checks -- introduced, named, Talk to, a hand offered and
remembered, "He seems to like you" on examine, the ID read up close, a rumour about a real fight. Two things it
found that no unit test could: a busy crew member greeted by name said nothing at all (now they say so), and a
hello heard from further off than a conversation can run started one that died on its first line (now it gets
a line called back). What only a real client can show is the chat window drawing a link and BYOND delivering
the click.

Two more visits checked the fixes. The fourth passed 14 of 15: its one failure was the stand-in's own doing (its
ID was read during the test of silence, so it now puts the ID away for that step), and it showed three crew
introducing themselves to it at once, which is now one conversation at a time. The fifth passed 7 of 10, and
all three failures have one cause that a real player would meet too: idle crew-to-crew chat takes people away
from a player standing beside them. A geneticist finished an introduction and was pulled into a colleague's
small talk 0.3 seconds later; a mime started two with other crew within eight seconds of being greeted by
name. Talk to
refuses anybody already in a conversation, so both menus came up empty, and the third failure (no warmth on
examine) followed because the offer of a hand never happened. The same visit showed two smaller things: a crew
member who had just been introduced still added the newcomer line "Didn't see you come in.", because the
greeting remembers only greetings it made itself; and a mime cast in a conversation says nothing at all, since
TG will not let a mime speak.

### Next steps (recommended 2026-09-23)

1. **Players before small talk** (small, and first). Talk to, or a line naming somebody, ends that person's
   crew-to-crew chat and starts the player's; work still comes first, with the brush-off. An introduction,
   however it started, counts as the newcomer greeting. Mimes stay out of spoken parts until M2 can give them
   pantomime. Spending standing needs this: a crew member asked to follow you cannot be one the next idle chat
   takes away. The stand-in's fifth visit is the test.
2. **Spend standing: crew who do things for you.** Conversations change how people feel about you and nothing
   else yet. The plan's effects that start a behaviour -- follow you, open a door they have access to, fetch
   something from their department, call somebody on the radio -- turn standing into something you can use.
   This closes the loop the dialogue work opened, and the stand-in can test each one.
3. **M2: dialogue tied to what the crew already do.** Bartender and patron, doctor and patient ("You again?"),
   chef and botanist, the HoP and the all-access request, security and the assistant seen pranking. Mostly
   files; station events need to record who as well as where for the last one.
4. **The warden and the brig.** Prisoners now reach cells; a warden to hold them, release them when the timer
   runs out and keep the armoury, plus searches and confiscation so a thief stops keeping the loot.
5. **Five minutes with a real client**, whenever convenient: the only unverified piece of the player side.
6. **Housekeeping:** an intermittent lavaland runtime in upstream atmospherics gets blamed on whichever long SP
   test is running (usually `sp_brew`); and the module README has grown past fifteen hundred lines and wants
   splitting by department.

Later: the Python sidecar, layering generated lines over the static ones the dialogue engine falls back to;
miners and wider chemistry; antagonists who sabotage, frame and escape.

### 2026-09-22 — Dialogue as a system

Conversations are data with a closed vocabulary, crew remember people, and a player can finally talk back: by
clicking a reply under an NPC's line, or by starting a conversation with the Talk to verb. The seven topics the
crew shared became dialogue files, the station now gossips about what actually happened on it, and a player's
name is learned by introduction or by having an ID read up close. 94 SP tests pass. None of the player side has
been seen with a real client yet; that is the next thing to do.

### 2026-09-21 — Six rounds, spent proving it

The three things that were built but never played all work now, and none of them worked first time. A
prisoner was arrested and locked in a cell (49 seconds, door swap and all); the janitor cleans (thirteen
stains in five minutes); written dialogue runs between crew all shift. Every failure on the way was found by
watching a round rather than by reading code, and two of them could not have been unit-tested at all:

- **An arrest turned the department into a brawl.** The suspect radios that the officer hit them, every other
  officer believes it, and they fight each other while the suspect walks away. No arrest reached a cell until
  a report naming the arresting officer was dropped.
- **The janitor never waited for its own mopping.** TG cleans through `INVOKE_ASYNC`, so the click returns
  at once; checking two milliseconds later and walking off cancelled the very action it had started.
- Two starvation bugs: unreachable litter outranking every stain, and a locked room being written off one
  decal at a time.

The diagnostics added along the way are the reason the last three were found in one round each: a behaviour
that does nothing should say why.

### 2026-09-20 (later) — The janitor, the clown, and dialogue as data

The janitor and the clown are in, and conversations have started moving out of code and into json files
under `strings/spacestation_sp/dialogue` (the first slice of `01-dialogue-plan.md` M1: crew to crew,
checked at load and by a unit test, four dialogues written). The three jobs interlock on purpose -- the
clown drops peels, the janitor picks them up, and botany grows the bananas.

### 2026-09-20 — Where things stand

`code/modules/spacestation_sp/README.md` is the detailed account; this is the shape of it. Since 09-07:
cargo and the quartermaster, the chef, the bar, medbay (triage, treatment, cryo and surgery) and the
chemist, players taking over any AI-held job as they join, greytide assistants, the antagonist foundation,
and security — the confrontation ladder, the head of security's command layer, kit fetched rather than
handed out, and cells. Conversation's M0 bug list is fixed and covered by tests. Sixty-five SP unit tests
pass.

Next session: the janitor and the clown, and the first written dialogue lines.

## 8. Key file index
- Version gate: `code/__byond_version_compat.dm`; pins: `dependencies.sh`, `.tgs.yml`
- Build: `BUILD.cmd`, `RUN_SERVER.cmd`, `tools/build/build.ts`, `tools/build/lib/byond.ts`, `tools/build/build_flags.json`
- Config: `config/config.txt`, `config/game_options.txt`, `config/admins.txt`, `config/maps.txt`, `config/dynamic.toml`, `config/dev_overrides_readme.txt`
- Round flow: `code/controllers/subsystem/ticker.dm`, `code/controllers/subsystem/job.dm`, `code/controllers/subsystem/dynamic/`
- Jobs: `code/modules/jobs/job_types/_job.dm` (`get_roundstart_spawn_point`, `get_spawn_mob`), `SSjob.equip_rank`
- Spawn path (client version to mirror): `code/modules/mob/dead/new_player/new_player.dm` `create_character`
- AI framework: `code/datums/ai/_ai_controller.dm`, `_ai_bt_*.dm`, `README.md`, `learn_ai.md`; subsystems `code/controllers/subsystem/ai_controllers.dm`, `movement/`, `pathfinder.dm`
- Humanoid AI templates: `code/datums/ai/monkey/`, `code/modules/mob/living/basic/trooper/`, `code/modules/mob/living/basic/revolutionary.dm`, `code/datums/ai/basic_mobs/admin_ai_templates.dm`
- Pathfinding with access: `code/__HELPERS/paths/path.dm` (`get_path_to(..., access=...)`)
- Speech/hearing: `code/modules/mob/living/living_say.dm` (`say`, `Hear`), `code/game/say.dm`
- Antagonists: `code/modules/antagonists/traitor/datum_traitor.dm`, `code/modules/antagonists/_common/`
- External bridge: `code/datums/http.dm`, `code/__DEFINES/rust_g.dm`, `code/controllers/subsystem/tts.dm`, `code/game/world.dm` (`Topic`), `code/datums/world_topic.dm`
- Lua: `code/modules/admin/verbs/lua/README.md`, `lua/SS13.lua`, `config/lua.txt`
