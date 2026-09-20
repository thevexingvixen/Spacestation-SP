# Spacestation SP — Plan: malicious greytide and the antagonist foundation

Date: 2026-09-13. Status: first slice built. The crime/witness layer and the malicious greytide are
**confirmed in play**; the antagonist scheme assigns and reports correctly but has **not yet completed a
theft in a live round**. The rest is the roadmap.

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

## 5. Security's response to a crime (built)

The incident chain already carries a suspect and a crime now. Security's tree branches:

- **Attacker** (someone is being hit): the existing baton-and-cuff response, unchanged.
- **Suspect, no attacker** (a crime was witnessed): walk to the scene, find the named suspect, and — for
  a first offence — *confront* rather than beat: demand the stolen item back, or just move them on. Only
  escalate to the baton if they resist or are already `WANTED_ARREST`.
- **Records.** A witnessed crime can raise `wanted_status` on the suspect's security record
  (`/datum/crime`, `update_matching_security_huds`), so an officer who meets them later already knows.

This keeps the baton for people who hit people, which is the current, working behaviour, and gives the
softer crimes a proportionate answer.

**Built.** `sp_security_confront` sits directly below the violent response: the officer walks to the named
suspect, says something chosen by the crime, thinks less of them, and files it (`sp_file_crime_record()`).
The wanted status is deliberately not touched on a first offence — this fork has no "suspected" status
between None and Arrest, and Arrest sets every secbot on the station onto them — so the ladder is a word,
then a word and a note, then an arrest once the record passes `SP_CRIMES_BEFORE_ARREST`. Resisting needs no
special case: hitting the officer makes an attacker of you through the existing `on_attacked`. Still to do
here: having the officer actually demand the stolen item back rather than only say so.

## 6. Testing

Unit tests (deterministic, the accepted proof alongside the live tally):

- `sp_witness_*` — who counts as a witness (sighted, awake, in range; assistants and schemers do not
  tell), and that a callout adjusts reputation and files a suspect incident.
- `sp_scheme_steal` — a steal scheme reads incomplete until the pawn holds the target, complete after.
- `sp_break_light` — a lit tube in a public area is a valid malicious target and goes dark when broken.
- Live: `SP_GREYTIDE_MALICE` on and an antagonist spawned by an admin verb, watched for `tide.vandalism`,
  `crime.*_seen`, `antag.scheme_done`, and security acknowledging a suspect report.

## 6a. What the first two live rounds showed

Both rounds ran clean (no SP runtimes). The greytide half worked; the antagonist half was where the
interesting failures were, and all of them were the same mistake wearing different hats.

**Confirmed working.** Troublemaker assistants smashed light tubes, a bystander noticed, and it reached
security as a place rather than a name: `tide.vandalism=2`, `crime.vandalism_seen=1`, and in the log
*"Security, I just saw Evangeline Mccune smash a light in Central Primary Hallway."*

**Targets were picked because they existed, not because anyone could have them.** The first antagonist
was a mime told to steal the medal of captaincy, which spawns inside a locked lockbox in the captain's
quarters with the only other copy pinned to the captain. The second was a paramedic sent after the head
of security's laser gun, which `populate_contents_immediate()` creates inside a locker with
`req_access = list(ACCESS_HOS)`. Selection now requires an instance that is actually liftable: out on a
turf, or in a closet this particular thief can open (`sp_can_be_lifted(candidate, thief)`).

**It failed silently.** The goal search returned nothing and said nothing, every three seconds, which in
a log is indistinguishable from an antagonist who has not started. There is now a rate-limited line
("cannot get at what they are after"), and the troublemaker roll is logged either way, so a round with no
vandalism in it can no longer be confused with a round that had nobody inclined to any.

**The harness put them where they could not act.** Spawned ninety seconds in, the debug antagonist lands
on the arrival shuttle, which is its own z-level; everything worth stealing is on the station below, so
the scheme correctly found nothing. The debug helper now moves them onto the station.

Two unrelated bugs surfaced the same way, both from walks that now report their failures: the
quartermaster walked at the bridge's supply console (which no cargo ID opens) every forty-five seconds
and never placed an order, and patients dragged into medbay could not get out until `sp_see_out()` was
added — the latter visible as `crew.buzzed_through=12`.

## 7. Order of work

1. **This session:** crime/witness layer; one malicious greytide behaviour (break a light); the scheme
   datum and steal scheme; the antagonist controller and one theft behaviour; an admin verb to make an
   antagonist; unit tests; a live round. No commit.
2. Malicious greytide: locker-emptying, door-prying, slips.
3. Security's proportionate response to suspects (§5), and security records.
4. More schemes: sabotage (an antag engineer scramming the engine), framing, escape-with-the-loot.
5. The TG-traitor bridge behind `SP_ANTAG_TG_DATUM`, once there are players to see codewords and a
   round-end report worth printing.

## 8. Why the thief finds nothing, measured rather than argued

Four rounds of theories, three of them confidently wrong, and then the log simply said it:

    no steal target for Angela Robinson: 52 catalogued, 15 on the map, 12 with a copy somewhere,
    1 liftable, none of those reachable
    out of reach: ablative trenchcoat in Armory, 13 tiles off, budget 220: 21 steps with every
    door open, so it is access

The funnel counts every stage, and when it closes it retries the survivor at a budget nobody could exceed and
then again with every station door open. Thirteen tiles away. Twenty-one steps once the doors open. A budget
of two hundred and twenty. **It is access**, and it was never anything else.

What was believed on the way there, and why each was wrong:

- *The catalogue is all difficulty 3-4, so nothing is liftable.* The census was accurate and the conclusion
  was not: items were liftable. They were behind doors.
- *Widen into the spy pool.* Those are heads' kit and security weapons, which live in the same locked rooms.
- *The 220-tile path budget is too small for a station.* It was never within sight of binding.

The lesson is the one this module keeps relearning: a stage that fails silently gets diagnosed by argument,
and argument is wrong most of the time. The funnel cost a few lines and settled in one round what four rounds
of reasoning could not.

The fork, for whoever picks this up:

1. **Target what a crew member can actually walk to.** `sp_reachable_steal_item()` already tests the path with
   the thief's own access -- the trouble is how little survives it. This means sourcing targets outside TG's
   steal catalogue: ordinary valuables lying about in public rooms.
2. **Teach thieves through doors.** Hacking, breaking, following somebody who has the access. Much larger, and
   it makes an antagonist genuinely different from ordinary crew rather than just differently motivated.

Option 1 makes theft happen. Option 2 makes theft interesting. They are not exclusive, and 1 is the smaller
half of a day's work while 2 is its own session.
