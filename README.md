# Spacestation SP

**A singleplayer branch of [/tg/station](https://github.com/tgstation/tgstation).**

Space Station 13 is at its best with a station full of people. Spacestation SP is an attempt to keep
that when there is only one of you: the station is populated by AI crew who hold real jobs and actually
do them, and you play one person among them — with admin powers, because someone has to keep the lights
on.

This is a working fork, not a finished game. It runs, the crew work their shifts, and new departments and
behaviours land regularly.

---

## What the crew actually do

None of this is scripted set dressing. Each crew member is a client-less human running a behaviour tree,
using the same machines, tools and doors a player would, and the log says what they managed:

- **Engineering** — set up the supermatter coolant loop, bring the engine online, watch it, and patch
  hull breaches with an RCD in an EVA suit.
- **Medbay** — triage the injured, treat wounds limb by limb, set up and load the cryo tubes, and perform
  surgery. The chemist brews medicine in stages, presses patches, and stocks the fridge.
- **Cargo** — take supply requests over the radio, order them against the cargo budget, run the shuttle,
  and drag the crates to whoever asked (leaving them at the door when their ID does not open it).
- **Service** — the chef cuts, mixes, bakes and serves; the bartender takes drink orders and pours them;
  the botanist plants, waters, weeds, harvests, buys seeds and breeds mutations.
- **Security** — respond to incident reports, chase down whoever is swinging at people, and cuff them.
- **Everybody** — wander their department, hold conversations with each other, answer players by name,
  form opinions of people, go through lockers that are not theirs, and try doors they have no access to.

And, increasingly, some of them are up to no good: a greytide of assistants with a menu of pranks and the
occasional smashed light, and the beginnings of antagonists who pursue a hidden goal while everyone else
works.

## How it works

Everything SP-specific lives in **[`code/modules/spacestation_sp/`](code/modules/spacestation_sp/)** plus
one defines file, so the fork can be rebased onto upstream without unpicking it from the rest of the
codebase. That folder has [its own detailed README](code/modules/spacestation_sp/README.md) covering
every department, the behaviour trees, the known limitations, and — deliberately — the bugs that were
hard to find, so the next person does not have to find them twice.

Behaviour lives in JSON behaviour trees (`ai/*.bt.json`) compiled at build time, with the leaves,
decorators and helpers in DM beside them.

## Running it

You need [BYOND](https://www.byond.com/) 516.1685 or newer.

```
tools\build\build.bat build
<BYOND>\bin\dd.exe tgstation.dmb 7777 -trusted -close -logself
```

Then connect to `byond://127.0.0.1:7777`. Local settings go in `config/dev_overrides.txt`, which is
gitignored; copy [`docs/dev_overrides.example.txt`](docs/dev_overrides.example.txt) to start. The useful
knobs are `SP_AUTOPOPULATE` (how many AI crew to spawn), `SP_ASSISTANTS_MIN`/`MAX` (the greytide), and
`AUTOADMIN` so you can actually administrate your own station.

## Testing

Emergent crew are miserable to verify by playing: you start a round, wait, grep the log hoping for a
line, and silence tells you nothing about whether a behaviour is broken or merely has not come up yet.
So the bar here is two things together:

- **Unit tests** — `tools\build\build.bat build --define=UNIT_TESTS`, then run the `.dmb` headless. The SP
  suite asserts the deterministic half: is that sandwich finished, does that reagent come out of that tap,
  is a requested crate matched to its request, does a witness report a theft.
- **A live round** — with the `SP: tally:` line the subsystem prints every couple of minutes, counting
  what the crew actually managed (`chef.served=16`, `med.restocked=1`, `tide.graffiti=5`).

A feature is not done here until both say so.

## Documentation

- [The SP module README](code/modules/spacestation_sp/README.md) — the real reference: every department,
  how the trees are laid out, the testing loop, and the known limitations.
- [`docs/`](docs/) — the design and planning notes: the original analysis, the dialogue plan, and the
  antagonist plan.

## Relationship to upstream

This is a fork of /tg/station, built on a 2026-09 snapshot. All of the upstream game is here and
unchanged except where SP needed a hook; the singleplayer work is additive. Bug reports about the base
game belong [upstream](https://github.com/tgstation/tgstation), not here.

| Upstream | Link |
| --- | --- |
| /tg/station code | https://github.com/tgstation/tgstation |
| Website | https://tgstation13.org |
| Wiki | https://tgstation13.org/wiki/Main_Page |
| Codedocs | https://codedocs.tgstation13.org/ |
| Getting started with development | https://hackmd.io/@tgstation/HJ8OdjNBc#tgstation-Development-Guide |
| Building | [tools/build/README.md](tools/build/README.md) |
| Running a server | [.github/guides/RUNNING_A_SERVER.md](.github/guides/RUNNING_A_SERVER.md) |

## LICENSE

All code after [commit 333c566b88108de218d882840e61928a9b759d8f on 2014/12/31 at 4:38 PM PST](https://github.com/tgstation/tgstation/commit/333c566b88108de218d882840e61928a9b759d8f) is licensed under [GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).

All code before [commit 333c566b88108de218d882840e61928a9b759d8f on 2014/12/31 at 4:38 PM PST](https://github.com/tgstation/tgstation/commit/333c566b88108de218d882840e61928a9b759d8f) is licensed under [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html).
(Including tools unless their readme specifies otherwise.)

See LICENSE and GPLv3.txt for more details.

The TGS DMAPI is licensed as a subproject under the MIT license.

See the footer of [code/\_\_DEFINES/tgs.dm](./code/__DEFINES/tgs.dm) and [code/modules/tgs/LICENSE](./code/modules/tgs/LICENSE) for the MIT license.

All assets including icons and sound are under a [Creative Commons 3.0 BY-SA license](https://creativecommons.org/licenses/by-sa/3.0/) unless otherwise indicated.
