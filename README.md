<h1 align="center">Spacestation SP</h1>

<p align="center"><b>Space Station 13 for one player.</b><br>
A singleplayer fork of <a href="https://github.com/tgstation/tgstation">/tg/station</a> in which AI crew hold real jobs and actually do them.</p>

<p align="center">
  <img alt="122 unit tests passing" src="https://img.shields.io/badge/unit_tests-122_passing-2f7d46">
  <img alt="16 AI controllers" src="https://img.shields.io/badge/AI_controllers-16-1c6b86">
  <img alt="75 behaviour trees" src="https://img.shields.io/badge/behaviour_trees-75-1c6b86">
  <img alt="34 dialogue files" src="https://img.shields.io/badge/dialogue_files-34-1c6b86">
  <img alt="Map: MetaStation" src="https://img.shields.io/badge/map-MetaStation-56656a">
  <img alt="BYOND 516.1685 or newer" src="https://img.shields.io/badge/BYOND-516.1685+-56656a">
</p>

---

Space Station 13 is at its best with a station full of people. Spacestation SP keeps that when there is only
one of you. The engine gets started, the kitchen serves, medbay patches people up, security makes arrests and
the bar pours drinks, all by AI crew using the same machines, tools and doors a player would. You join as one
person among them, take any job you like, and talk to the rest.

This is a working fork, not a finished game. It runs, the crew work their shifts, and new departments and
behaviours land regularly.

## At a glance

| | |
|---:|---|
| **16,146** | lines of SP code, kept in its own module |
| **122** | unit tests, all passing |
| **16** | AI controllers, one per kind of job |
| **75** | behaviour trees |
| **34** | written dialogue files, checked as they load |
| **5** | small code edits to /tg/station itself |

## What the crew do

None of this is scripted set dressing. Each crew member is a client-less human running a behaviour tree, and
the round log counts what they managed.

| Department | What they do | Status |
|---|---|---|
| **Engineering**<br><sub>Engineers, atmos techs, the CE</sub> | Bring the engine up and keep the power on. Suit up and patch hull breaches with the RCD. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Security**<br><sub>Officers, HoS, warden</sub> | A word, a note on the record, an arrest once there is a pattern. Stun and cuff, pat down, walk them to a cell and file the evidence. The HoS raises the alert, calls briefings and orders arming. The warden lets prisoners out on time and keeps the armoury. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Medbay**<br><sub>Doctors, CMO, chemist</sub> | Triage, limb-by-limb treatment, cryo, and surgery on bones and wounds. The chemist brews patches and cryoxadone. Medics restock from lockers, cargo and botany, and come when somebody calls medbay for you. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Service**<br><sub>Botanist, cook, bartender, janitor, clown</sub> | Grow and deliver produce and take requests. Cook the recipe tree onto the counter. Mix drinks to order. Mop the station. Honk, and leave peels only where they are funny. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Cargo**<br><sub>Quartermaster, technicians</sub> | Order what departments ask for against the budget, run the shuttle, and haul each crate to whoever asked. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Assistants**<br><sub>One to three greytiders</sub> | Gear up at tool storage, rummage, try doors, pull harmless pranks. One with a streak smashes a light. | ![Seen live](https://img.shields.io/badge/seen_live-2f7d46) |
| **Antagonists**<br><sub>A thief, so far</sub> | A hidden scheme to steal something worth taking. Usually it is behind a door they cannot open. This is the next big build. | ![Partial](https://img.shields.io/badge/partial-b24a1c) |
| **Everyone else**<br><sub>Science, captain, HoP, detective, chaplain and others</sub> | Wander, chat and do favours. No work of their own yet. | ![Not built](https://img.shields.io/badge/not_built-6b7478) |

## What you can do

- **Take any job.** A job an AI holds stays open on the join screen. Pick it and the AI goes off shift.
- **Talk to people.** Crew introduce themselves, remember your name once you give it or they read your ID, and
  hold written conversations. When it is your turn, your replies appear as links under their line. Right-click
  a crew member and choose **Talk to** to start one yourself.
- **Earn favours.** Be decent to somebody and they will come with you, open a door their ID opens and yours does
  not, fetch you something from their department, or call medbay when you are hurt.
- **Get into trouble.** Witnesses call out what they see. Security starts with a word, keeps a record, and
  arrests on a pattern: cuffs, a search, a cell with a timer, and a warden who lets you out when it runs down.
- **Run the place.** You have admin powers, because someone has to keep the lights on.

> The player's side has been driven end to end by an automated stand-in player in live rounds. It has had very
> little time with real players, so expect rough edges, and reports are welcome.

## Playing it

You need [BYOND](https://www.byond.com/) 516.1685 or newer, on Windows.

```
tools\build\build.bat build
<BYOND>\bin\dd.exe tgstation.dmb 7777 -trusted -close -logself
```

Then connect to `byond://127.0.0.1:7777`. `RUN_SP.cmd` does the second step for you.

Local settings go in `config/dev_overrides.txt`, which is gitignored; copy
[`docs/dev_overrides.example.txt`](docs/dev_overrides.example.txt) to start. The useful ones:

| Setting | What it does |
|---|---|
| `SP_AUTOPOPULATE <n>` | How many AI crew to spawn. 17 is quiet; 32 fills the station. |
| `SP_ASSISTANTS_MIN` / `MAX` | How many greytide assistants join them. |
| `AUTOADMIN` | Makes you an admin on your own station. |

## How it is proved

- **Unit tests.** 122 SP tests in a `UNIT_TESTS` build pin the logic, and every bug found in play gets one.
- **Live rounds.** Headless rounds with 32 AI crew, with the tally the game prints of what actually happened.

From one 17-minute round with nobody at the keyboard:

```
service   chef.served=22 bar.served=18 jani.cleaned=24 botany.request_delivered=1 clown.honk=8
medbay    med.cryo_setup=7 chem.patches=11 med.surgical_kit=3 med.restocked=2
cargo     cargo.delivered=1
security  sec.searched=1 sec.confiscated=1 sec.evidence_filed=1 sec.jailed=1 warden.released=1
talk      talk.thread=74 talk.finished=72 talk.line=158
```

## What is missing

| | |
|---|---|
| **Antagonists rarely act** | The one thief usually finds nothing it can reach. Fixing this is next. |
| **Half the station has no work** | Science, command, the detective and others only wander and chat. |
| **No rhythm to a shift** | No schedules, meal breaks or needs. Hunger is switched off. |
| **One map** | Cells, the armoury and routes assume MetaStation. |
| **Death is permanent** | Medbay cannot revive anybody yet. |

The full list is in the [module README](code/modules/spacestation_sp/README.md#known-limitations).

## What is next: antagonists

The plan covers every antagonist in /tg/station, the ones that are not human included
([docs/03-antagonists-plan.md](docs/03-antagonists-plan.md)). The AI plays each one first and the crew answer
it; by default a round has one.

| Tier | Antagonists |
|---|---|
| **1** | Traitor, changeling, wizard |
| **2** | Heretic, blood cult, revolution, blood brothers, spies, the obsessed |
| **3** | Nuclear and clown operatives, pirates, space ninja, abductors |
| **4** | Spiders, xenomorphs, blob, revenant, morph, nightmare, space dragon, voidwalker, slaughter demon |
| **Later** | Malfunctioning AI, and the admin events |

Alongside them comes the station's side: bodies found and reported, medics who can revive, a detective who
works the scene, evacuation, and repairs to more than floors.

## How it works

Everything SP-specific lives in **[`code/modules/spacestation_sp/`](code/modules/spacestation_sp/)** plus one
defines file, so the fork can be rebased onto upstream. Behaviour lives in JSON behaviour trees
(`ai/*.bt.json`) compiled at build time, with the leaves and helpers in DM beside them. Conversations are json
files under `strings/spacestation_sp/dialogue`.

- [The SP module README](code/modules/spacestation_sp/README.md) is the real reference: every department, the
  trees, the testing loop, the limitations, and the bugs that were hard to find.
- [`docs/`](docs/) holds the plans: the original analysis, dialogue, and antagonists.

<details>
<summary><b>The build so far</b> (6 to 26 September 2026)</summary>

| Date | What landed |
|---|---|
| 26 Sep | Favours, dialogue tied to work, the warden, searches and evidence |
| 24 Sep | A stand-in for the player, and what it found |
| 22 Sep | Dialogue as a system, and a player who can talk back |
| 20 Sep | The janitor and the clown; security's escalation and cells |
| 13 Sep | Medbay, the greytide, and the beginnings of antagonists |
| 9 Sep | The chef, the bartender, and crew who roam, rummage and try doors |
| 7 Sep | Cargo, botany, hull breach repair, conversation and standing |
| 6 Sep | The AI crew module, on a vanilla /tg/station snapshot |

</details>

## Relationship to upstream

This is a fork of /tg/station, built on a 2026-09 snapshot. All of the upstream game is here and unchanged
except where SP needed a hook; the singleplayer work is additive. Bug reports about the base game belong
[upstream](https://github.com/tgstation/tgstation), not here.

| Upstream | Link |
| --- | --- |
| /tg/station code | https://github.com/tgstation/tgstation |
| Website | https://tgstation13.org |
| Wiki | https://tgstation13.org/wiki/Main_Page |
| Codedocs | https://codedocs.tgstation13.org/ |
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
