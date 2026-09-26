# Spacestation SP — Plan: branching dialogue, NPC↔NPC and NPC↔player

Date: 2026-09-11, updated 2026-09-24. Status: M0 to M3 built, M2 and M4's favours built 2026-09-24 (see §4);
still to do are rumours spreading between crew and M5, the sidecar. Sections 1 to 3 are the plan as written.

This builds on the conversation system in `code/modules/spacestation_sp/sp_conversation.dm`,
`ai/sp_social_behaviors.dm` and the hearing path in `ai/sp_crew_controller.dm`. The first section is an
honest account of what that system does today, because several of its bugs have to be fixed before
anything is built on top of it.

---

## 1. What exists today

**Status, 2026-09-22:** M0, M1 and M3 are built. Dialogue lives in json files with a closed, validated
vocabulary; crew have memory; a player replies by clicking links, can start a conversation with Talk to, and
is learned by name through introduction or by having their ID read up close. The detail is in
`code/modules/spacestation_sp/README.md` under "Written dialogue". What follows is the state before M0, kept
for the record of what was fixed.

**AI↔AI chat.** Seven topics are hard-coded as `/datum/sp_topic` subtypes: shift, food, gossip, engineering,
medical, security and botany. Each has openers, replies and sometimes closers.

- **Exchange:** one exchange is an opener, a reply, and maybe a closer — two or three lines.
- **Who starts it:** the initiator picks a topic by job (weighted). The partner is the first eligible AI
  crew member within five tiles.
- **How the reply matches:** the listener's `consider_conversation` copies the topic off the initiator's
  controller, so the reply fits the opener.
- **Cooldowns:** 90 s between chats. Station-wide remarks over common every 8 minutes, 25% chance.

**NPC↔player.** Players get no dialogue, only single-line answers.

- **Keyword answers:** `sp_speech_intent()` reads a line in whole words (`sp_words()`) into one of eight
  intents: insults, thanks, "follow me", "who are you", "where", help, "how are you" and greetings. The most
  specific match wins, and `sp_answer_for()` turns it into a line.
- **Name detection:** a crew member answers when their first name is a word in the line, and asks what you
  want when it is the only thing in it. A line naming nobody is answered by the nearest crew member free to
  talk; one naming somebody else is left to them. An answer not given within 15 s is dropped.
- **Greeting:** new arrivals are greeted once each.

**Standing.**

- **Storage:** a per-crew score from -10 to +10 for each mob, in `BB_SP_REPUTATION`.
- **Changes:** insult -3, thanks +2, hello +1, a spoken closer +1, being attacked -6. Each moves once per
  line answered.
- **Uses:** only three answer branches read it. It never decays and isn't shown to the player.

**Not there yet:**

- no threads longer than three lines
- no memory (`BB_SP_HEARD` is recorded and never read)
- no player choices
- nothing an NPC says ever leads to anything they do

### Bugs fixed before building on it (M0, done 2026-09-16)

All eight are fixed and pinned by unit tests: `sp_trees_talk`, `sp_speech_whole_words`,
`sp_distress_needs_urgency`, `sp_answer_once`, `sp_crew_exchange`, `sp_one_answer_per_line` and
`sp_security_answers`. Each entry says what was wrong, then how it was fixed.

1. **Base crew never chat at all.** This includes the Captain, HoP, RD, scientists and janitor:
   `sp_crew.bt.json` has no `sp_crew_chatter`.
   - After their first AI exchange as a *listener*, `TOPIC` and `PARTNER` stay set for good, because they
     never run the closer that clears them.
   - A set `PARTNER` then keeps them out of every future chat.
   - *Fixed:* `sp_crew.bt.json` runs `sp_crew_chatter`, and a listener never holds `PARTNER` or `TOPIC` now.
2. **A leftover `TOPIC` hijacks the next answer.** `sp_say_reply` doesn't clear it, so the next person to
   speak to them, a player included, gets a topic reply instead of an answer.
   - *Fixed:* a reply's topic has its own key, `BB_SP_CHAT_REPLY_TOPIC`, spent as the reply is said.
3. **A closer can restart the exchange.** It's spoken while `PARTNER` and `TOPIC` are still set, so the
   listener treats it as a new opener. It can loop while the 60% closer roll keeps succeeding.
   - *Fixed:* the opener moves through `SP_CHAT_*` stages, each set before its line is said, since speech goes
     out through `INVOKE_ASYNC`. A listener takes a line as an opener only at `SP_CHAT_OPENED` and marks it
     heard. The opener forgets the chat before saying the closer.
4. **The replier also gets a closer**, contrary to the code's own comment.
   - *Fixed:* replying no longer sets `PARTNER`. The opener closes, and only once the partner has answered.
5. **Standing changes twice** for lines that don't use the crew member's name: `sp_answer_for` runs once as
   a probe and again for the real answer.
   - *Fixed:* the probe is `sp_speech_intent()`, which changes nothing; `sp_answer_for()` runs once.
6. **Substring matching trips over itself:**
   - "hey" matches "they"; "Tom" matches "tomorrow".
   - A bare "hi" is missed.
   - "can you help" also sends security running (distress words).
   - *Fixed:* all of it reads whole words. For distress, words of violence count on their own, but "help"
     and "security" need urgency (an exclamation mark, capitals, the word leading the line, or bare pleading)
     and never count in a calm request.
7. **Unanswered and unreachable paths:**
   - Security never answers anyone: their tree has no `sp_crew_core`, so no respond subtree.
   - `sp_crew_social` is dead code: nothing sets `BB_SP_ATTENTION_TARGET`. So saying only a crew member's
     name gets silence.
   - *Fixed:* security and the HoS run `sp_crew_respond` below their security work, taking nothing up while
     on duty. A name alone sets `BB_SP_ATTENTION_TARGET`, and `sp_crew_social` asks what they want.
8. **The first greeting can take up to 90 s**, because it shares the chat cooldown with failed partner
   searches.
   - *Fixed:* greeting a newcomer sits outside the chat cooldown.

Also fixed along the way: AI crew no longer answer other crew's replies, closers or remarks (only an
opener aimed at them), an unnamed player line gets one answer rather than one from everyone in earshot,
and an opener whose partner never answered does not close into silence.

(`busy_with_work()` stops a chat reply from interrupting a medic or a chemist mid-job, and, since M0, an
officer on duty.)

---

## 2. Goals

- **Threads, not lines.** Conversations of several turns that branch on who is talking, where, what has
  happened, and how they feel about each other. This applies both NPC↔NPC and NPC↔player.
- **Choices without typing.**
  - The player can pick a reply from options.
  - Free speech keeps working for players who prefer to type.
- **Memory.**
  - who has met whom, and whether they know each other's names
  - what they have talked about, so there are no repeats
  - favours, grudges and promises
- **Context.** Job, place, time into the shift, injuries, and things that just happened: the lights went
  out, a prank, surgery, a fight.
- **Consequences.** Standing and memory change behaviour. A friendly engineer opens a door for you, a
  doctor comes when you call them by name, security keeps an eye on the assistant who asked for all access
  twice.
- **Content as data.** Dialogue lives in JSON, validated by unit tests, not in `.dm` string lists.
- **Deterministic first.** The engine and all content work with no model calls. The Python sidecar can
  add generated lines later, within a budget, and always has static lines to fall back on.

---

## 3. Design

### 3.1 Content: dialogue files

A dialogue is a small graph of nodes, stored under `strings/spacestation_sp/dialogue/*.json` and loaded
once at init.

```json
{
  "id": "hop_all_access",
  "roles": {
    "asker": {"job": ["Assistant"]},
    "hop":   {"job": ["Head of Personnel"]}
  },
  "where": ["hop_line", "hop_office"],
  "start": "ask",
  "nodes": {
    "ask": {
      "speaker": "asker",
      "lines": ["Any chance of all access, %HOP_FIRST%?", "I need all access. For science."],
      "next": [
        {"to": "refuse", "weight": 3},
        {"to": "tease", "weight": 1, "if": {"standing": {"hop->asker": ">=4"}}}
      ]
    },
    "refuse": {
      "speaker": "hop",
      "lines": ["No.", "Not a chance.", "Ask me again and you're on the list."],
      "effects": [{"remember": {"hop": "asked_for_aa"}}],
      "next": [{"to": "plead", "if": {"memory": {"hop": "!asked_for_aa_twice"}}}, {"to": "end"}]
    },
    "plead": {
      "speaker": "asker",
      "lines": ["Maintenance access? Please?"],
      "next": [{"to": "end"}]
    },
    "tease": {
      "speaker": "hop",
      "lines": ["You again. Here's a lollipop instead."],
      "effects": [{"give": {"from": "hop", "to": "asker", "item": "/obj/item/food/lollipop"}}],
      "next": [{"to": "end"}]
    }
  }
}
```

**Node fields:**

- **`speaker`:** a role.
- **`lines`:** placeholders are `%NAME%`, `%FIRST%` (the partner's first name if known, otherwise "mate" or
  their job), `%JOB%`, `%AREA%` and `%<ROLE>_FIRST%`.
- **`if`:** conditions.
- **`effects`** (a closed list):
  - standing ±
  - remember a fact
  - set a flag
  - give an item
  - start a behaviour: follow, go to, open a door we have access to, call someone on the radio
- **`next`:** weighted edges, each with its own `if`.
- **`wait`:** seconds before the next line.
- **`timeout_to`:** the node to jump to if the other side goes quiet.
- **`options`:** for player-facing nodes, `[{"text": "...", "to": "...", "if": ...}]`.

**Conditions** are a small closed vocabulary, not code:

- `job`, `department`
- `standing` (between two roles)
- `memory` (fact or flag set or unset)
- `place` (area type or tag)
- `hurt`
- `holding` (item type)
- `time_into_shift`
- `recent_event` (an event tag from the last N minutes)
- `random` (a percentage)

Every file is validated at load and in a unit test. The test checks that:

- every `to` exists;
- every role in a line or effect is bound;
- every placeholder is known;
- every condition key is valid;
- every node can be reached.

### 3.2 Runtime: threads

- **`/datum/sp_dialogue`:** the parsed, validated definition.
- **`/datum/sp_thread`:** a running conversation. It holds the dialogue, the mob bound to each role, the
  current node, the lines said so far, when it started, when the last line was, and the player's pending
  options.
- **Where threads live:** the initiator's controller holds the thread in `BB_SP_THREAD`. Every participant
  gets `BB_SP_IN_THREAD` pointing at it. Turn-taking is read from the thread, not inferred from what was
  heard.
- **New subtree:** `sp_crew_converse` replaces chatter's opener/reply/closer. Each tick it checks whether
  it is our turn in our thread, then walks within two tiles, faces the partner, says the line with
  `sp_crew_speak`, applies the effects, and advances. Lines are still spoken aloud, so players and other
  crew hear them the ordinary way.
- **Ending:** a thread ends at an `end` node, on timeout, when a participant leaves range or becomes
  `busy_with_work()`, or when anything in `sp_crew_core` fires, such as an attack or a threat. It lasts at
  most a couple of minutes.
- **Cooldowns** are per pair and per dialogue, so the same two don't repeat themselves.

### 3.3 NPC↔NPC

**Starting a thread.**

- An idle crew member picks a partner in range, then a dialogue that both can play by role and whose
  conditions hold.
- The choice is weighted towards what they haven't discussed with this person recently.
- The existing seven topics are ported first as three-node dialogues, so nothing is lost.

**First content that ties into what the crew already do:**

- **Bartender and patron:** order → comment → tip or tab. Builds on the bar.
- **Doctor and patient:** after treatment, advice; on a second visit, "You again?" Builds on medbay.
- **Chef and botanist:** "Any tomatoes?" → a produce request. Builds on the existing delivery.
- **Assistant and HoP:** the all-access request, as above. Builds on greytide.
- **Security and assistant:** "Move along", or a warning after a prank was seen. Builds on greytide and
  sets a watch flag.
- **Engineer and engineer:** shift handover — "Engine's up, I've set the SMES." Builds on engineering.
- **Rumours:** "Did you hear the lights went out in the bar?" Built from recent events, so the station
  talks about itself.

### 3.4 NPC↔player

There are three ways in, all ending up in the same thread runtime.

1. **Free speech, done properly.**
   - `sp_answer_for` becomes an intent classifier: word-boundary matching, synonyms, and addressing by name
     or by facing and proximity.
   - Intents such as `greet`, `thank`, `insult`, `ask_job`, `ask_directions`, `ask_help`, `request_follow`
     and `ask_about_<topic>` are dialogue entry points.
   - "Where's medbay?" gets real directions from the NPC's own position ("down the hall, past the bar, on
     your left"), not a stock non-answer.
2. **Clickable replies.**
   - When an NPC's line in a thread is addressed to the player, the player's chat shows two to four options
     under it as links, e.g. `[Sure] [Not now] [Who's asking?]`.
   - A click calls back into the thread through `Topic()`, following the PDA "(Reply)" link
     (`messenger_program.dm`).
   - The player's character then says the option aloud, so everyone nearby hears it through the same
     hearing path, and the thread moves on.
   - The handler checks that `usr` is the player bound in the thread, is still in range, and that the
     thread and option are still current. Options expire after 30 s.
3. **A "Talk to" verb** (right-click on an AI crew member). It opens a short list of what they'll talk
   about (`tgui_input_list`, called async), in the style of TG's trader component radial. This is for
   players who want to start a conversation rather than wait for one.

**What NPCs know about the player:**

- They don't know your name until you say it or they read your ID.
- They remember whether they have met you, what you asked, and whether you helped.
- Standing colours tone, greetings, and whether they will do things for you.

### 3.5 Memory

- **`BB_SP_MEMORY`:** keyed by person. That is `real_name` for crew, and the mind for players, so a new body
  doesn't reset everything. Each entry holds:
  - whether they know the name
  - times talked
  - recent dialogue ids (a ring of 5)
  - facts and flags
  - favours owed
  - promises
- **Station events:** a short-lived log of tags (`lights_out:bar`, `graffiti:central_hall`,
  `surgery:<name>`, `fight:<area>`) with a timestamp. Greytide pranks, medbay and security already have the
  hooks to write it. Rumour dialogues read it.
- **Unused data gets used:** `BB_SP_HEARD` either feeds this or is removed.

### 3.6 Later: the Python sidecar

A node can say `"generate": {"style": "grumpy engineer", "max_words": 18}` in place of fixed lines.

- **Request:** the engine asks the sidecar for one line, sending the speaker's persona, the last three
  lines, relevant memory, and the node's intent.
- **Limits:** strictly rate-limited and cached, with the node's static `lines` as the fallback.
- **Testing:** the engine stays deterministic in unit tests; generation is off there.

---

## 4. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | Fix the bugs in §1 (**done 2026-09-16**) | Unit tests cover `sp_answer_for` (word boundaries), a full AI exchange with no stuck keys, and base crew chatting; security answers |
| M1 | Engine (**done 2026-09-22**) | JSON loader and validator, thread runtime for NPC↔NPC, the seven topics ported; a unit test runs a thread between two AI crew line by line |
| M2 | NPC↔NPC content (**done 2026-09-24**) | 10–15 dialogues from §3.3 with standing and memory effects; live tally `talk.threads`, `talk.finished`, `talk.abandoned` |
| M3 | NPC↔player (**built 2026-09-22, played by the stand-in 2026-09-23**) | Intents, clickable replies, the Talk verb, player memory, 5–8 player dialogues (introductions, directions, help, follow requests) |
| M4 | Consequences (**favours built 2026-09-24**) | Favours and follow behaviour; standing-gated help (doors, fetching a doctor); rumours spreading |
| M5 | Sidecar | `generate` nodes behind a budget, off by default |

**Done 2026-09-24:** M2 and most of M4. Conversations started by what the crew do -- the bartender and whoever ordered
(`served`), a medic and the patient they just patched (`treated`, and "You again?" the second time), botany and the
cook over a delivery (`delivered`, where the cook's ask for tomatoes becomes a real request) -- plus the Head of
Personnel and the all-access request, two engineers handing over, and security having a word with the assistant who
pulled a prank, which needed station events to remember who as well as where. Players get their own versions at
the bar, in medbay and at the HoP's desk. M4's favours are effects that start a behaviour: follow, open a door we
have access to, fetch something from our department, and call medbay on the radio, each gated by standing in its
dialogue file and costing a point of it. Rumours spreading between crew is the part of M4 not built. A player also
comes before small talk now: Talk to or naming somebody breaks off a chat with a colleague.

**Done 2026-09-20:** the first slice of M1, plus the janitor and the clown it was written alongside.
Dialogues are json files under `strings/spacestation_sp/dialogue`, read and checked at load and in a unit
test; roles are cast by job; a thread runs crew to crew, a line at a time, with weighted branches, a dice
roll and standing as conditions, and standing as the one effect. Four dialogues are written. Still to do
in M1: memory (`BB_SP_MEMORY`), the rest of the condition vocabulary, and moving the seven keyword topics
into files. Player choices remain M3.

**Done 2026-09-22:** the rest of M1 -- memory, the whole condition and effect vocabulary, reachability checks,
and the seven keyword topics as files -- and M3: reply links under the NPC's line, the Talk to verb, player
dialogues (introductions, what they do, asking for a hand, the shift, rumours), names learned by introduction
or from an ID read up close, and standing shown on examine at the extremes. Not built from the plan then: effects
that start a behaviour (follow, go to, open a door, call on the radio) -- built 2026-09-24 as favours, all but
"go to" -- directions worked out from where the crew member stands, and a debug verb that dumps memory.

---

## 5. Testing

- **Unit:**
  - every dialogue file validates;
  - conditions evaluate correctly;
  - a thread between two `consistent` humans runs node by node with the right speakers and effects;
  - timeouts end threads;
  - a simulated option click advances the thread and is refused for the wrong `usr` or an expired option;
  - memory is written and read back.
- **Live:** tallies for threads started, finished and abandoned, and options offered and chosen, plus a
  debug verb that dumps one crew member's memory and current thread.

---

## 6. Questions for you (answered 2026-09-22)

1. **Player replies.** Links under the NPC's line. Built.
2. **What NPCs know about you.** Your name only once you introduce yourself or they stand close enough to read
   your ID. Built.
3. **Tone.** Light, with dry office humour by default, and grimmer where a department suits it: security
   suspicious, medical gallows humour, engineering fatalistic.
4. **Standing.** Shown only at the extremes: "seems to like you" or "seems wary of you" on examine, and felt
   the rest of the time. Built.
