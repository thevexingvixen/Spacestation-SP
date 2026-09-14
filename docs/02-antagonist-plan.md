# Spacestation SP — Plan: malicious greytide and the antagonist foundation

Date: 2026-09-13. Status: first slice being built this session (crime/witness layer, one malicious
greytide behaviour, the scheme datum and one antagonist behaviour). The rest is the roadmap.

This builds on the greytide (`code/modules/spacestation_sp/sp_greytide.dm`), the idle-curiosity
groundwork (`sp_curiosity.dm`), and the incident-reporting chain that already lets AI security respond
to trouble (`ai/sp_crew_behaviors.dm`, `ai/sp_crew_controller.dm`).

---

## 1. The gap this fills

Today's greytide is all harmless: graffiti, lights-out-for-six-seconds, a knock, a bell, a honk. Nothing
is taken, broken, or gets through a door. Security has nothing to do about any of it, and there is no
crew member on the station whose *goal* is at odds with everyone else's.

Two new things:

- **A malicious streak for the greytide** — a notch past a prank. A broken light tube, a locker actually
  emptied and the loot stashed, a door pried where they have no business. Still nobody gets hurt.
- **The antagonist foundation** — the scaffolding a crew member with a hidden agenda needs: a goal, the
  behaviours to pursue it, a way to be seen doing it, and a way for security to respond. One worked
  example (theft-to-objective) built on it this session; sabotage, framing and the rest slot in later.

The connective tissue between them is **crime and witnesses**: the same question — *who can see me, and
what happens if they do?* — governs a greytider prying a door and an antagonist pocketing the captain's
medal. That lives in `sp_crime.dm` and both layers call it.

---

## 2. Crime and witnesses (`sp_crime.dm`, built this session)

One place answers "who would see this, and what do they do about it".

- `sp_witnesses(culprit, range)` — everyone awake, sighted and on their feet who can see the culprit.
- `sp_crime_witnesses(culprit)` — the ones who would *tell*: any player, and AI crew whose
  `reports_crimes()` is true. Assistants never grass (`reports_crimes()` returns FALSE for them), and a
  crew member running a scheme of their own keeps their head down (FALSE while `BB_SP_SCHEME` is set).
- `sp_crime_seen(culprit, crime, description, where, notice_chance)` — rolls each would-tell witness;
  the first to notice calls it out.
- `sp_call_out_crime(...)` — the witness shouts at the culprit ("Hey! Put that back!"), thinks less of
  them (`sp_adjust_reputation`), and, with a headset, reports it to security over the radio as a
  **suspect and a place** rather than an attacker. Crimes are `SP_CRIME_THEFT`, `_VANDALISM`, `_TRESPASS`.

The incident record grew two fields, `SP_INCIDENT_SUSPECT` and `SP_INCIDENT_CRIME`, so security can tell
"go and look at a person near here" from "someone is being beaten right now". A suspect with no attacker
routes to **investigate**, not **baton** (see §5).

---

## 3. Malicious greytide (`sp_greytide.dm`)

A second, rarer tier on top of the prank menu. Only some assistants are troublemakers (a roll at spawn,
`BB_SP_TROUBLEMAKER`), it is gated by a config flag (`SP_GREYTIDE_MALICE`, default on), and every one of
the prank rules still holds: never with security watching, never behind a door they cannot reach, one at
a time, and each decision logged.

Built this session:

- **Break a light tube.** A working light in a public area (hallway, maintenance, commons), smashed with
  something to hand or bare-handed. Goes dark until a crew member replaces the tube. `tide.vandalism`,
  and `sp_crime_seen(... SP_CRIME_VANDALISM ...)` so a witness calls it out.

Planned next, same shape (find target where standing → reach it → do it → witnessed):

- **Empty a locker and stash it.** The malicious end of rummaging: take the lot, not one keepsake, and
  drop it in maintenance rather than carry it. Theft.
- **Pry a door.** Where `on_door_denied` already fires, a troublemaker with a crowbar forces an
  unpowered or unbolted door instead of grumbling. Trespass. (`try_to_crowbar`.)
- **A slip in the hall.** Drop a soap or peel from their kit in a busy hallway. Nuisance, not injury.

## 4. The antagonist foundation (`sp_antagonist.dm`, `ai/sp_antagonist_behaviors.dm`)

### The scheme datum

An antagonist is an ordinary AI crew member with a **scheme** (`/datum/sp_scheme`) on the blackboard at
`BB_SP_SCHEME`. The scheme is the goal and the score-keeping; the behaviour tree is how it is pursued.
This is deliberately *not* TG's `/datum/objective`: those assume a client (assassinate auto-completes
against a clientless NPC, which reads as AFK), and the round-end report prints a blank key for a
mob with no ckey. The scheme is ours, needs no client, and makes no round-end noise.

- `/datum/sp_scheme` — `name`, `desc`, `check_progress(controller)`, `complete`, `announce_done()`.
- `/datum/sp_scheme/steal` — a target from TG's own `/datum/objective_item` catalogue (so "the captain's
  medal", "the CMO's hypospray" are defined and known to exist on the map), plus `check_progress` that
  asks whether the pawn is carrying it. This reuses TG's steal-item bookkeeping without taking on the
  objective/uplink machinery.

`reports_crimes()` already returns FALSE while a scheme is set, so a schemer looks the other way.

### The controller and tree

- `/datum/ai_controller/sp_crew/antagonist` — a crew member (any job) given a scheme. Overrides
  `wants_item()` so the scheme's target is worth taking even though it is on nobody's interest list, and
  overrides the mischief/curiosity gates toward boldness.
- `sp_crew_scheme.bt.json` — a subtree that ranks *below* self-preservation and *above* idle wandering:
  find the scheme's objective, go to it, take it (a `do_after`, witnessed as theft), then lie low. When
  the scheme completes it is announced only to the log and the tally (`antag.scheme_done`), not the crew.

### Bridging to TG's antagonist system (documented, off by default)

For a round where the antagonist should be a "real" traitor — count in the antag list, share codewords,
show in the round-end report — a silent traitor datum can be attached:
`new /datum/antagonist/traitor(give_objectives = FALSE)` with `give_uplink = FALSE`, `silent = TRUE`.
That skips the uplink and TGUI (both need a client) but still registers the antag. It is **off by
default** because the round-end report prints a blank key for a clientless mob and codewords get
broadcast to a station that has no players to hear them. The scheme drives behaviour either way; the
bridge only changes how the rest of TG's code sees the mob. `SP_ANTAG_TG_DATUM` will gate it.

## 5. Security's response to a crime (later this session or next)

The incident chain already carries a suspect and a crime now. Security's tree branches:

- **Attacker** (someone is being hit): the existing baton-and-cuff response, unchanged.
- **Suspect, no attacker** (a crime was witnessed): walk to the scene, find the named suspect, and — for
  a first offence — *confront* rather than beat: demand the stolen item back, or just move them on. Only
  escalate to the baton if they resist or are already `WANTED_ARREST`.
- **Records.** A witnessed crime can raise `wanted_status` on the suspect's security record
  (`/datum/crime`, `update_matching_security_huds`), so an officer who meets them later already knows.

This keeps the baton for people who hit people, which is the current, working behaviour, and gives the
softer crimes a proportionate answer.

## 6. Testing

Unit tests (deterministic, the accepted proof alongside the live tally):

- `sp_witness_*` — who counts as a witness (sighted, awake, in range; assistants and schemers do not
  tell), and that a callout adjusts reputation and files a suspect incident.
- `sp_scheme_steal` — a steal scheme reads incomplete until the pawn holds the target, complete after.
- `sp_break_light` — a lit tube in a public area is a valid malicious target and goes dark when broken.
- Live: `SP_GREYTIDE_MALICE` on and an antagonist spawned by an admin verb, watched for `tide.vandalism`,
  `crime.*_seen`, `antag.scheme_done`, and security acknowledging a suspect report.

## 7. Order of work

1. **This session:** crime/witness layer; one malicious greytide behaviour (break a light); the scheme
   datum and steal scheme; the antagonist controller and one theft behaviour; an admin verb to make an
   antagonist; unit tests; a live round. No commit.
2. Malicious greytide: locker-emptying, door-prying, slips.
3. Security's proportionate response to suspects (§5), and security records.
4. More schemes: sabotage (an antag engineer scramming the engine), framing, escape-with-the-loot.
5. The TG-traitor bridge behind `SP_ANTAG_TG_DATUM`, once there are players to see codewords and a
   round-end report worth printing.
