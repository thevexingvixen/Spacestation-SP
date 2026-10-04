# Spacestation SP — Plan: every antagonist

Date: 2026-09-27. Status: plan. Decided in the review of 2026-09-27: antagonists are the next big build,
starting with the main ones -- traitor, changeling, wizard -- with this plan covering the rest of TG's
roster, the ones that are not human included. `docs/02-antagonist-plan.md` covers the foundation already
built (the crime and witness layer, schemes, the thief) and stays the record of that work.

---

## 1. Where the antagonists stand

- **The foundation works.** An antagonist is an AI crew member with a scheme on the blackboard
  (`/datum/sp_scheme`, `BB_SP_SCHEME`); the scheme is the goal and the score, the behaviour tree pursues it.
  Witnesses see crimes, call them out and report them (`sp_crime.dm`). Security answers with a word, a note on
  the record, an arrest after a pattern, a search, a cell and a warden who lets them out again.
- **The one antagonist rarely acts.** The thief's only scheme is theft from TG's steal catalogue, and every copy
  it could reach is behind a door its own ID does not open. All six brig rounds of 2026-09-26 logged "found
  nothing worth stealing". One theft has ever been seen, on 2026-09-21. `docs/02` §8 measured why: it is access.
- **TG's antagonists mostly never arrive.** Dynamic's midround rulesets for creatures and off-station teams poll
  ghosts (`SSpolling.poll_ghost_candidates`), and a singleplayer station has none, so a blob, a wizard or a
  space dragon simply never happens. Roundstart rulesets pick from players, which is one person or nobody.

## 2. Principles

1. **Every antagonist has two sides.** It can be played by the AI, with the crew and security answering it,
   or by the player, with the crew as victims and witnesses. The station's response is shared by both and is
   built once (§3). Most antagonists get their AI side first; a few are only worth having as the player's
   (below, per antagonist).
2. **Use TG's own powers; drive them from the AI.** Changeling powers are action datums
   (`code/modules/antagonists/changeling/powers/`: absorb, transform, tiny prick stings, fake death and
   regenerate, the arm blade among the mutations). Wizard spells are `/datum/action/cooldown/spell` subtypes
   (111 files under `code/modules/spells/spell_types`). The traitor's uplink and the emag are ordinary items.
   An AI can trigger all of them. What SP adds is deciding when.
3. **Goals stay schemes.** TG's objectives assume a client: an assassinate objective against a clientless mob
   completes on the spot. Schemes need none. The silent TG datum (`SP_ANTAG_TG_DATUM`, off by default) is
   attached where the rest of TG's code needs to see an antagonist -- a changeling's powers live on the
   changeling datum, so for a changeling it is not optional.
4. **Targets they can reach, and the means to reach more.** A scheme is only handed out if its target can be
   got to (`sp_reachable_steal_item()` already asks the pathfinder). Each antagonist then brings its own way
   through doors: the traitor's emag, the changeling's stolen face and ID, the wizard's teleports and knock,
   vents for spiders and xenomorphs, phasing for the revenant.
5. **One antagonist at a time, proved before the next.** Each lands with unit tests, a debug lever
   (`SP_DEBUG_ANTAGONIST <kind>`), a live round and tallies, the way every department has.

## 3. The station's side (built once, used by all)

What the crew do about an antagonist decides whether it is a story or a slaughter. Most of this is missing:

- **Sightings.** A crew member who sees something clearly hostile -- a wizard, an arm blade, a xenomorph, a
  blob -- shouts it, radios it with a place ("There's a wizard in the bar!") and gets away from it. Threat
  reaction today covers a drawn weapon only (`sp_scan_threats`); it needs a notion of *monster*.
- **Bodies.** Nobody notices a corpse today. A body found is reported; a medic comes and carries it to the
  morgue; security treats it as a scene. The detective finally gets a job: go to the scene, look it over
  (fingerprints, the husk that says changeling), and name a suspect.
- **Escalation already exists** and needs wiring to the new reports: sightings and bodies count as violence
  for the HoS's alert ladder, red opens the armoury (built), and lethal orders apply to creatures and
  antagonists caught in the act, never to petty crime (built).
- **Evacuation.** When the station is being lost -- enough dead, a blob past a size, a nuke armed -- the
  captain or the head of personnel calls the shuttle, and crew go to departures. Nobody calls it today.
- **Repairs.** Engineers patch floors only (`sp_breach.dm`). Fireballs, blobs and xenomorph resin want walls,
  windows and airlocks fixed.
- **Revival.** Death is permanent in SP today: no defibrillation, cloning or revival. Since antagonists may
  kill (§9), medics learn to defibrillate somebody recently dead before they go to the morgue.

## 4. The roster

Tiers are the order of work. "AI" is what the AI-run version does; "Player" is what the crew must do when the
player is the antagonist; "Needs" is what SP must build first.

| Antagonist | Kind | Tier | AI | Player | Needs |
|---|---|---|---|---|---|
| Traitor | Crew infiltrator | 1 | Steals with an emag; later kills when alone and hides the body | Witnesses report, the owner misses the item, security investigates | Emag use; "alone with them" test; body reports |
| Changeling | Crew infiltrator | 1 | Stings and absorbs somebody alone, wears their face and ID, fights with the arm blade when cornered | Husks are noticed; somebody "not themselves" | The TG datum on an AI; identity and memory rules; husk reports |
| Wizard | Off-station solo | 1 | Teleports in, casts from a small loadout, pursues a scheme, leaves | Sightings, red alert, lasers | Arrival without a ghost; spell use; the monster response |
| Heretic | Crew infiltrator | 2 | Gathers influences, sacrifices targets | Bodies, rituals seen | Influence reach; the sacrifice loop |
| Blood cult | Crew conversion | 2 | Draws runes, converts at them, summons | Converted crew turn; security raids | Conversion as a controller swap; team goals |
| Revolution | Crew conversion | 2 | Head revs flash crew, converted crew hunt the heads | Heads defend, the station splits | Sides among the crew; heads who fight back |
| Blood brothers | Crew pair | 2 | Two thieves who share a goal and cover for each other | As traitor | Shared schemes |
| Spies | Crew | 2 | Steal to bounties and hand them in | As traitor | A bounty scheme |
| Obsessed | Crew | 2 | Stalks one person, takes photos, kills | The target's fear | A "follow unseen" behaviour |
| Nuclear operatives | Off-station team | 3 | Assault for the disk, arm the nuke | The whole station fights or evacuates | Team AI; the disk; the nuke; evacuation |
| Clown operatives | Off-station team | 3 | As nuclear operatives, with bananas | As nuclear operatives | As nuclear operatives |
| Pirates | Off-station team | 3 | Board, rob cargo's credits, leave | Security repels them | Boarding; a ship |
| Space ninja | Off-station solo | 3 | Stealth objectives | Sightings | Stealth use |
| Abductors | Off-station pair | 3 | Snatch crew, experiment, return them | Missing crew come back changed | Teleport pads; a returned-crew loop |
| Spiders | Creature | 4 | TG's own spider AI already runs; they spread and web | Flee, report, burn webs | The monster response; spawning without ghosts |
| Xenomorphs | Creature | 4 | Queen, facehuggers, a hive; through vents | Flee, fight, evacuate | An alien controller (TG gives carbon aliens none) |
| Blob | Creature | 4 | An overmind places and grows | Engineers and security fight it back | An overmind controller; repairs |
| Revenant | Creature | 4 | Harvests the dead, defiles lights and machines | Salt, holy water, the chaplain | Bodies; the chaplain's job |
| Morph | Creature | 4 | Disguises as things, eats the unwary | Suspicious objects | Disguise choice |
| Nightmare | Creature | 4 | Breaks lights, hunts in the dark | Keep the lights on | Light repair |
| Space dragon | Creature | 4 | Opens rifts, carp pour in | Close the rifts | Rift response |
| Voidwalker | Creature | 4 | Takes people into space | Stay away from windows | Rescue from space |
| Slaughter demon | Creature | 4 | Blood-crawls and kills | Clean the blood | The janitor matters |
| Blood worms, venus human traps, sentient creatures, pyro slimes, syndicate monkeys, shades | Creatures | 4 | Mostly TG basic-mob AI with SP spawning | As spiders | The monster response |
| Malf AI | Silicon | Later | Takes over the station | Card the AI, cut the power | Silicons: SP spawns none yet |
| Fugitives and hunters, paradox and evil clones, survivalists, highlander, wishgranter, greentext, Santa, valentines, nations, magic servants, brainwashed, hypnotised, ERT, battlecruiser, ash walkers | Events and admin | Later | Case by case | Case by case | Mostly admin events; ash walkers are lavaland's |

## 5. Tier 1 in detail

### Traitor

The traitor is the one most rounds would have, and the most natural for the player to be.

- **AI side, first cut.** A scheme picked from targets the thief can reach *with an emag*. `docs/02` §8 found
  TG's steal list "a challenge built for a player traitor with an emag"; giving the AI traitor one is the missing
  half. The emag is used on the doors and lockers in the way (`ai_interact`, which is what a click does). The
  theft is still witnessed or not by the existing layer, so the station's response is already there.
- **Second cut: killing.** A kill scheme: follow the target at a distance, strike only when nobody would see
  (`sp_witnesses()` is empty), hide the body in a locker or in maintenance, and go back to work. This needs
  §3's body reports to have any answer at all, and the lethality decision in §9.
- **Uplink.** A short list of what an AI would buy, rather than the whole catalogue: the emag, a stealthy
  weapon, one escape tool. Telecrystals stay TG's.
- **Player side.** The crew's half is mostly built: witnesses and callouts, reports, the confrontation ladder,
  searches and evidence. Missing: an owner noticing their item is gone and saying so, and a detective who
  investigates a scene rather than only officers answering a report.
- **Proof.** Unit tests for target choice with and without an emag, the emag opening a door the thief could
  not, and "alone" meaning alone; a live round where theft happens without a debug nudge (`antag.stole`).

### Changeling

- **AI side.** The silent TG changeling datum on an AI crew member, so the powers exist. The loop: find
  somebody alone, sting them quiet (the tiny prick stings), absorb them, and take their face and ID with
  transform. With the victim's ID comes the victim's access, which is how a changeling gets through doors.
  Cornered, it grows the arm blade and fights; losing, it fakes death and regenerates.
- **Identity is the interesting part.** Crew memory is keyed by `real_name` (`sp_memory_key()`), so a
  changeling wearing a victim's face inherits every crew member's standing with the victim. That is the
  changeling fantasy working, and it wants two rules: somebody who saw the victim die, or finds the husk, knows
  better; and a changeling seen changing shape is a monster sighting on the spot.
- **Player side.** Absorbing AI crew leaves husks; crew who find one report it; the detective's look at a husk
  names it a changeling; security then goes lethal against that one person. The player can also borrow the
  crew's own memory of their victim to talk their way past people.
- **Proof.** Unit tests for the "alone" test, the absorb-then-transform sequence, identity and memory
  transfer, and a husk being reported; a live round where a changeling absorbs somebody and walks around as them.

### Wizard

- **Arrival.** TG spawns the wizard in the Wizard Den off-station. The AI wizard picks a small loadout from the
  spellbook (fireball, blink, knock, ethereal jaunt, a summon) and teleports to a public spot, which needs no
  ghost -- the midround ruleset's only obstacle is the ghost poll.
- **AI side.** A scheme (steal, cause chaos, kill a head), spells cast by triggering their actions, knock and
  blink through doors, jaunt away when hurt, and a teleport home when done or losing.
- **The station.** This is the first big set piece: sightings, the HoS's ladder to red, the armoury open,
  lasers, casualties, repairs to what the fireballs broke, and perhaps an evacuation. Most of §3 is exercised by
  one wizard, which is why it comes third rather than first.
- **Player side.** The player as wizard gets a station that screams, runs, reports and shoots back.
- **Proof.** Unit tests for loadout choice and each spell the AI uses; a live round from arrival to the
  wizard's end, with `sec.alert_raised`, `sec.went_lethal` and whatever the wizard broke in the tally.

## 6. Later tiers, in brief

- **Tier 2, the crew turned against itself.** Heretics, the blood cult, revolutionaries, blood brothers,
  spies, the obsessed. What they share is conversion or coordination: an AI crew member changing sides mid-shift
  (swapping or layering a controller), teams with a shared scheme, and a station that splits. The revolution
  also needs heads of staff who fight back, which command does not do today.
- **Tier 3, visitors.** Nuclear and clown operatives, pirates, the space ninja, abductors. They need team AI,
  boarding from off-station, and the one thing only the nuke brings: a station that must evacuate or die.
- **Tier 4, creatures.** Many already have TG basic-mob AI (the giant spiders do; carbon xenomorphs do not).
  The SP work is mostly spawning them without a ghost poll and the crew's response to monsters in §3. Creatures
  that need a mind of their own -- the blob's overmind, the xenomorph queen -- get SP controllers.
- **Later.** The malfunctioning AI waits on silicons, which SP does not spawn. The rest are admin events and are
  taken case by case, if ever.

## 7. How antagonists get onto the station

- **Dynamic, fed by the AI crew.** Roundstart and midround rulesets pick from players and ghosts. SP offers its
  AI crew as candidates for the crew antagonists (traitor, changeling, heretic, cult, revolution, brothers,
  spies, obsessed), and spawns the off-station ones and the creatures directly with an AI on them where a ruleset
  would have polled ghosts. A config key sets how much happens in a round: one antagonist by default (§9).
- **The player.** TG's own antagonist preferences decide whether dynamic may make the player an antagonist;
  the AI side decides nothing there.
- **Debug levers.** `SP_DEBUG_ANTAGONIST <kind>` spawns one of each kind ninety seconds in, for live rounds, as
  the thief lever does now.

## 8. Order of work

1. **Traitor, first cut:** the emag, reachable targets with it, theft without a debug nudge. One session.
2. **The station's side, first part:** bodies found and reported; a medic tries the defibrillator, then
   carries the body to the morgue; the detective investigates a scene; sightings as incidents. One or two
   sessions.
3. **Traitor, second cut:** the kill scheme, alone-ness, hiding a body. One session.
4. **Changeling.** One or two sessions.
5. **Wizard,** with the station's side, second part: the monster response, repairs to walls and windows, and
   evacuation. Two sessions.
6. **Dynamic feeding AI candidates,** so antagonists arrive without debug levers. One session.
7. Then tier 2, tier 3 and tier 4, one antagonist per session or two, each taken in the order the station's
   side can answer it.

## 9. Settled on 2026-09-27

1. **AI antagonists may kill crew, and medbay gains revival.** Kill schemes, absorbs and fireballs are allowed.
   The station's side (§3, §8 step 2) therefore includes defibrillation: a medic who finds a body recently dead
   tries to bring them back before it goes to the morgue, so one antagonist does not quietly empty a department.
2. **The AI side comes first** for every antagonist: the AI plays it and the crew answer it, which proves the
   station's response that the player's own antagonist play then also gets.
3. **One antagonist a round by default**, chosen through dynamic from the AI crew (§7), with a config key to
   turn it up or off.
