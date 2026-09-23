/**
 * Written dialogue: conversations kept as data rather than as string lists in code.
 *
 * A dialogue is a small graph of nodes, one json file each, in strings/spacestation_sp/dialogue. Each node names
 * the role that speaks it and what it may say, and where the conversation can go next. Roles are bound to real
 * people when a thread starts: by job, by department, and by whether a player or a crew member plays them.
 * Everything a file can ask about or change is a closed vocabulary (the GLOB lists below), checked as the file
 * loads and again in a unit test, so a typo is a failed test rather than a conversation that quietly never
 * happens.
 *
 * Crew to crew, one thread speaks for both sides. With a player in it, the player's turns are offered as links
 * under the line they answer; a click says the reply aloud through the player's own character and the thread
 * moves on (docs/01-dialogue-plan.md, M1 and M3).
 */

/// A dialogue, as read from one file.
/datum/sp_dialogue
	/// Identifier: the repeat guard, the log and the tests use it.
	var/id
	/// What a player picks it by in the Talk to list. Every dialogue with a player in it has one.
	var/title
	/// What starts it besides the Talk to verb: a player's intent (SP_INTENT_*) or "newcomer".
	var/list/triggers = list()
	/// How likely this one is when several fit.
	var/weight = 1
	/// role name -> list("job" = titles, "department" = names, "player" = TRUE or FALSE).
	var/list/roles = list()
	/// Conditions that must hold for it to start at all.
	var/list/start_if
	/// The node the thread starts on.
	var/start
	/// node id -> the node.
	var/list/nodes = list()

/// A dialogue somebody is in the middle of.
/datum/sp_dialogue_thread
	var/datum/sp_dialogue/dialogue
	/// role name -> mob.
	var/list/cast = list()
	/// The node said next, or null when the thread is done.
	var/current
	/// When the next line is due.
	var/next_due = 0
	/// Lines said so far, player replies included.
	var/lines_said = 0
	/// When it began, so no conversation outlasts SP_DIALOGUE_MAX_TIME.
	var/started_at = 0
	/// The station event a rumour is about, when one was needed to start (the recent_event condition).
	var/list/event
	/// A player's turn: the replies on offer, in order, and when the offer lapses.
	var/list/pending_options
	var/options_expire = 0

/datum/sp_dialogue_thread/Destroy(force)
	GLOB.sp_active_threads -= src
	cast = null
	dialogue = null
	pending_options = null
	event = null
	return ..()

/datum/controller/subsystem/spacestation_sp
	/// Recent happenings, oldest first: things the crew talk about afterwards (sp_station_event()).
	var/list/station_events = list()

/// Every conversation running, so a player talking to one crew member is left to them by the rest.
GLOBAL_LIST_EMPTY(sp_active_threads)

/// Whether somebody is in a conversation with anybody right now.
/proc/sp_in_any_thread(mob/living/who)
	for(var/datum/sp_dialogue_thread/thread as anything in GLOB.sp_active_threads)
		for(var/role in thread.cast)
			if(thread.cast[role] == who)
				return TRUE
	return FALSE

/// What a file may ask about, and what it may change. Both are deliberately closed.
GLOBAL_LIST_INIT(sp_dialogue_conditions, list("random", "standing", "job", "department", "memory", "knows_name", "place", "hurt", "holding", "time_into_shift", "recent_event"))
GLOBAL_LIST_INIT(sp_dialogue_effects, list("standing", "remember", "forget", "learn_name", "event", "give"))
/// What can start a dialogue besides the Talk to verb.
GLOBAL_LIST_INIT(sp_dialogue_triggers, list("newcomer", SP_INTENT_GREETING, SP_INTENT_WHO, SP_INTENT_HELP, SP_INTENT_WELLBEING, SP_INTENT_THANKS, SP_INTENT_INSULT, SP_INTENT_WHERE, SP_INTENT_WHERE_WORK, SP_INTENT_FOLLOW))
/// Departments by the name a file uses.
GLOBAL_LIST_INIT(sp_dialogue_departments, list(
	"Command" = /datum/job_department/command,
	"Security" = /datum/job_department/security,
	"Engineering" = /datum/job_department/engineering,
	"Medical" = /datum/job_department/medical,
	"Science" = /datum/job_department/science,
	"Cargo" = /datum/job_department/cargo,
	"Service" = /datum/job_department/service,
	"Assistant" = /datum/job_department/assistant,
))
/// Places by the short name a file uses. A file may also give an area type outright.
GLOBAL_LIST_INIT(sp_place_tags, list(
	"bar" = /area/station/service/bar,
	"kitchen" = /area/station/service/kitchen,
	"hydroponics" = /area/station/service/hydroponics,
	"service" = /area/station/service,
	"medbay" = /area/station/medical,
	"security" = /area/station/security,
	"engineering" = /area/station/engineering,
	"cargo" = /area/station/cargo,
	"science" = /area/station/science,
	"command" = /area/station/command,
	"hallway" = /area/station/hallway,
	"commons" = /area/station/commons,
	"maintenance" = /area/station/maintenance,
))

// --- Loading and checking ----------------------------------------------------------------------------

/// Every dialogue we ship, read once.
/proc/sp_all_dialogues()
	var/static/list/dialogues
	if(isnull(dialogues))
		dialogues = list()
		for(var/file_name in flist(SP_DIALOGUE_PATH))
			if(!findtext(file_name, ".json"))
				continue
			var/list/problems = list()
			var/datum/sp_dialogue/loaded = sp_read_dialogue(SP_DIALOGUE_PATH + file_name, problems)
			if(isnull(loaded))
				stack_trace("SP dialogue [file_name] was not loaded: [problems.Join("; ")]")
				continue
			dialogues[loaded.id] = loaded
	return dialogues

/**
 * Reads one dialogue file and checks it over, returning it, or null with what was wrong in `problems`.
 *
 * Every edge and reply leads to a node that exists or to the end, every node can be reached, every node is
 * spoken by a declared role -- with lines for crew and replies for a player -- and every condition, effect and
 * placeholder is one the engine knows. A dialogue that fails any of it is not loaded at all: half a
 * conversation is worse than none, and the unit test names the file.
 */
/proc/sp_read_dialogue(path, list/problems)
	if(!fexists(path))
		problems += "there is no such file"
		return null
	var/list/raw
	try
		raw = json_decode(file2text(path))
	catch
		problems += "it is not valid json"
		return null
	if(!islist(raw))
		problems += "it is not a json object"
		return null
	var/datum/sp_dialogue/dialogue = new
	dialogue.id = raw["id"]
	dialogue.title = raw["title"]
	dialogue.weight = raw["weight"] || 1
	dialogue.start = raw["start"]
	dialogue.start_if = raw["if"]
	dialogue.roles = islist(raw["roles"]) ? raw["roles"] : list()
	dialogue.nodes = islist(raw["nodes"]) ? raw["nodes"] : list()
	dialogue.triggers = islist(raw["triggers"]) ? raw["triggers"] : list()
	if(!istext(dialogue.id) || !length(dialogue.id))
		problems += "it has no id"
	if(length(dialogue.roles) != 2)
		problems += "it has [length(dialogue.roles)] roles, and a conversation is between two people"
	var/players = 0
	for(var/role in dialogue.roles)
		var/list/spec = dialogue.roles[role]
		if(!islist(spec))
			problems += "role [role] is not an object"
			continue
		if(spec["player"])
			players++
		for(var/department in spec["department"])
			if(!(department in GLOB.sp_dialogue_departments))
				problems += "role [role] wants the [department] department, which is not one"
	if(players > 1)
		problems += "it has two players in it, and there is only ever one"
	if(players && !istext(dialogue.title))
		problems += "it has a player in it but no title to offer it to them by"
	for(var/trigger in dialogue.triggers)
		if(!(trigger in GLOB.sp_dialogue_triggers))
			problems += "it starts on [trigger], which is not something that happens"
	sp_dialogue_check_tests(dialogue, dialogue.start_if, "its start", problems)
	if(!length(dialogue.nodes))
		problems += "it has no nodes"
	else if(!(dialogue.start in dialogue.nodes))
		problems += "it starts at [dialogue.start || "nowhere"], which is not one of its nodes"
	if(SP_DIALOGUE_END in dialogue.nodes)
		problems += "it has a node called [SP_DIALOGUE_END], which is the word that ends a thread"
	for(var/node_id in dialogue.nodes)
		sp_dialogue_check_node(dialogue, node_id, problems)
	if(!length(problems))
		for(var/node_id in sp_dialogue_unreachable(dialogue))
			problems += "node [node_id] can never be reached"
	return length(problems) ? null : dialogue

/// One node's worth of checks for sp_read_dialogue().
/proc/sp_dialogue_check_node(datum/sp_dialogue/dialogue, node_id, list/problems)
	var/list/node = dialogue.nodes[node_id]
	if(!islist(node))
		problems += "node [node_id] is not an object"
		return
	var/speaker = node["speaker"]
	if(!(speaker in dialogue.roles))
		problems += "node [node_id] is spoken by [speaker || "nobody"], which is not one of its roles"
		return
	if(sp_dialogue_role_is_player(dialogue, speaker))
		// A player's turn is a choice rather than a line: two to four replies, each going somewhere.
		var/list/options = node["options"]
		if(!length(options) || length(options) > 4)
			problems += "node [node_id] is the player's turn and offers [length(options)] replies, not one to four"
		for(var/list/option in options)
			if(!islist(option) || !istext(option["text"]) || !length(option["text"]))
				problems += "node [node_id] has a reply with nothing to say"
				continue
			sp_dialogue_check_line(dialogue, option["text"], "node [node_id]", problems)
			sp_dialogue_check_exit(dialogue, option["to"], "a reply in node [node_id]", problems)
			sp_dialogue_check_tests(dialogue, option["if"], "a reply in node [node_id]", problems)
			sp_dialogue_check_effects(dialogue, option["effects"], "a reply in node [node_id]", problems)
		if(!isnull(node["timeout_to"]))
			sp_dialogue_check_exit(dialogue, node["timeout_to"], "the timeout in node [node_id]", problems)
		return
	if(!length(node["lines"]))
		problems += "node [node_id] has no lines"
	for(var/line in node["lines"])
		sp_dialogue_check_line(dialogue, line, "node [node_id]", problems)
	for(var/list/edge in node["next"])
		if(!islist(edge))
			problems += "node [node_id] has an edge that is not an object"
			continue
		sp_dialogue_check_exit(dialogue, edge["to"], "node [node_id]", problems)
		if(!isnull(edge["weight"]) && (!isnum(edge["weight"]) || edge["weight"] <= 0))
			problems += "node [node_id] has an edge weighted [edge["weight"]]"
		sp_dialogue_check_tests(dialogue, edge["if"], "an edge in node [node_id]", problems)
	sp_dialogue_check_effects(dialogue, node["effects"], "node [node_id]", problems)

/proc/sp_dialogue_check_exit(datum/sp_dialogue/dialogue, destination, where, list/problems)
	if(destination != SP_DIALOGUE_END && !(destination in dialogue.nodes))
		problems += "[where] leads to [destination || "nowhere"], which is not a node"

/proc/sp_dialogue_check_line(datum/sp_dialogue/dialogue, line, where, list/problems)
	if(!istext(line))
		problems += "[where] has a line that is not text"
		return
	for(var/placeholder in sp_dialogue_placeholders(line))
		if(!sp_dialogue_placeholder_known(placeholder, dialogue))
			problems += "[where] uses %[placeholder]%, which is not a placeholder"

/// Whether "a->b" names two of the dialogue's roles.
/proc/sp_dialogue_pair_ok(datum/sp_dialogue/dialogue, pair)
	var/list/sides = splittext(pair, "->")
	return length(sides) == 2 && (sides[1] in dialogue.roles) && (sides[2] in dialogue.roles)

/proc/sp_dialogue_check_tests(datum/sp_dialogue/dialogue, list/tests, where, list/problems)
	if(isnull(tests))
		return
	if(!islist(tests))
		problems += "[where] has an if that is not an object"
		return
	for(var/kind in tests)
		if(!(kind in GLOB.sp_dialogue_conditions))
			problems += "[where] asks about [kind], which is not a condition"
			continue
		var/value = tests[kind]
		switch(kind)
			if("random")
				if(!isnum(value) || value < 0 || value > 100)
					problems += "[where] rolls [value], which is not a percentage"
			if("standing", "memory", "knows_name")
				if(!islist(value))
					problems += "[where] asks about [kind] without saying whose"
					continue
				for(var/pair in value)
					if(!sp_dialogue_pair_ok(dialogue, pair))
						problems += "[where] names [pair] for [kind], which is not two of its roles"
					else if(kind == "standing" && !sp_dialogue_requirement_ok(value[pair]))
						problems += "[where] compares standing against [value[pair]], which is not a comparison"
			if("job", "department", "hurt", "holding")
				if(!islist(value))
					problems += "[where] asks about [kind] without saying whose"
					continue
				for(var/role in value)
					if(!(role in dialogue.roles))
						problems += "[where] asks about [role] for [kind], which is not one of its roles"
					else if(kind == "department")
						for(var/department in value[role])
							if(!(department in GLOB.sp_dialogue_departments))
								problems += "[where] asks about the [department] department, which is not one"
					else if(kind == "holding" && !ispath(text2path(value[role]), /obj/item))
						problems += "[where] asks whether [role] holds [value[role]], which is not an item"
			if("place")
				if(!islist(value))
					problems += "[where] asks about a place without naming one"
					continue
				for(var/place in value)
					if(!(place in GLOB.sp_place_tags) && !ispath(text2path(place), /area))
						problems += "[where] asks about [place], which is not a place"
			if("time_into_shift")
				if(!sp_dialogue_requirement_ok(value))
					problems += "[where] compares the time against [value], which is not a comparison"
			if("recent_event")
				if(!istext(value) && !islist(value))
					problems += "[where] asks after an event without naming one"

/proc/sp_dialogue_check_effects(datum/sp_dialogue/dialogue, list/effects, where, list/problems)
	if(isnull(effects))
		return
	if(!islist(effects))
		problems += "[where] has effects that are not a list"
		return
	for(var/list/effect in effects)
		if(!islist(effect))
			problems += "[where] has an effect that is not an object"
			continue
		for(var/kind in effect)
			if(!(kind in GLOB.sp_dialogue_effects))
				problems += "[where] does [kind], which is not an effect"
				continue
			var/value = effect[kind]
			switch(kind)
				if("standing", "remember", "forget", "learn_name")
					if(!islist(value))
						problems += "[where] does [kind] without saying whose"
						continue
					for(var/pair in value)
						if(!sp_dialogue_pair_ok(dialogue, pair))
							problems += "[where] names [pair] for [kind], which is not two of its roles"
				if("event")
					if(!istext(value))
						problems += "[where] records an event without a name"
				if("give")
					if(!islist(value) || !(value["from"] in dialogue.roles) || !(value["to"] in dialogue.roles) || !ispath(text2path(value["item"]), /obj/item))
						problems += "[where] gives something, but not from one role to another, or not an item"

/// Nodes nothing leads to. A node nobody can reach is a line nobody will ever hear.
/proc/sp_dialogue_unreachable(datum/sp_dialogue/dialogue)
	var/list/seen = list()
	seen[dialogue.start] = TRUE
	var/list/todo = list(dialogue.start)
	while(length(todo))
		var/node_id = todo[length(todo)]
		todo.len--
		var/list/node = dialogue.nodes[node_id]
		if(!islist(node))
			continue
		for(var/next_id in sp_dialogue_exits(node))
			if(isnull(next_id) || next_id == SP_DIALOGUE_END || seen[next_id])
				continue
			seen[next_id] = TRUE
			todo += next_id
	var/list/unreached = list()
	for(var/node_id in dialogue.nodes)
		if(!seen[node_id])
			unreached += node_id
	return unreached

/// Everywhere a node can lead: its edges, its replies, and where silence takes it.
/proc/sp_dialogue_exits(list/node)
	var/list/exits = list()
	for(var/list/edge in node["next"])
		if(islist(edge))
			exits += edge["to"]
	for(var/list/option in node["options"])
		if(islist(option))
			exits += option["to"]
	if(!isnull(node["timeout_to"]))
		exits += node["timeout_to"]
	return exits

/**
 * The %PLACEHOLDERS% in a line.
 *
 * Split on the marker rather than matched: "a %X% and a %Y%" comes apart into "a ", "X", " and a ", "Y", "",
 * so every second piece is a placeholder and an unclosed one simply never appears.
 */
/proc/sp_dialogue_placeholders(line)
	var/list/found = list()
	var/list/parts = splittext(line, "%")
	for(var/i in 2 to length(parts) step 2)
		found += parts[i]
	return found

/// The area, the event a rumour is about, and each role's first name, full name or job.
/proc/sp_dialogue_placeholder_known(placeholder, datum/sp_dialogue/dialogue)
	if(placeholder == "AREA" || placeholder == "EVENT" || placeholder == "EVENT_AREA")
		return TRUE
	for(var/role in dialogue.roles)
		var/upper = uppertext(role)
		if(placeholder == "[upper]_FIRST" || placeholder == "[upper]_NAME" || placeholder == "[upper]_JOB")
			return TRUE
	return FALSE

/// "value against requirement": ">=4", "<2", "=3", or a bare number meaning equal to it.
/proc/sp_dialogue_compare(value, requirement)
	if(isnum(requirement))
		return value == requirement
	if(!istext(requirement))
		return FALSE
	for(var/op in list(">=", "<=", ">", "<", "="))
		if(findtext(requirement, op) != 1)
			continue
		var/number = text2num(copytext(requirement, length(op) + 1))
		if(isnull(number))
			return FALSE
		switch(op)
			if(">=")
				return value >= number
			if("<=")
				return value <= number
			if(">")
				return value > number
			if("<")
				return value < number
		return value == number
	var/plain = text2num(requirement)
	return !isnull(plain) && value == plain

/proc/sp_dialogue_requirement_ok(requirement)
	if(isnum(requirement))
		return TRUE
	if(!istext(requirement))
		return FALSE
	for(var/op in list(">=", "<=", ">", "<", "="))
		if(findtext(requirement, op) == 1)
			return !isnull(text2num(copytext(requirement, length(op) + 1)))
	return !isnull(text2num(requirement))

// --- Who can play what ---------------------------------------------------------------------------------

/// A player, for dialogue: anybody the SP crew controller is not running.
/proc/sp_dialogue_is_player(mob/living/who)
	return !istype(who?.ai_controller, /datum/ai_controller/sp_crew)

/proc/sp_dialogue_role_is_player(datum/sp_dialogue/dialogue, role)
	var/list/spec = dialogue.roles[role]
	return islist(spec) && !!spec["player"]

/// The role the player plays in a thread, if one does.
/proc/sp_dialogue_player_role(datum/sp_dialogue_thread/thread)
	for(var/role in thread.cast)
		if(sp_dialogue_role_is_player(thread.dialogue, role))
			return role
	return null

/// Whether somebody holds a job in any of these departments, by the names a file uses.
/proc/sp_in_departments(mob/living/carbon/human/who, list/names)
	var/datum/job/role = who?.mind?.assigned_role
	if(isnull(role))
		return FALSE
	for(var/name in names)
		if(GLOB.sp_dialogue_departments[name] in role.departments_list)
			return TRUE
	return FALSE

/// Whether somebody can play a role: the right kind of person (player or crew), in the right job or department.
/proc/sp_dialogue_role_fits(datum/sp_dialogue/dialogue, role, mob/living/carbon/human/who)
	if(QDELETED(who))
		return FALSE
	var/list/spec = dialogue.roles[role]
	if(!islist(spec))
		spec = list()
	if(!!spec["player"] != sp_dialogue_is_player(who))
		return FALSE
	var/list/jobs = spec["job"]
	if(length(jobs) && !(who.mind?.assigned_role?.title in jobs))
		return FALSE
	var/list/departments = spec["department"]
	if(length(departments) && !sp_in_departments(who, departments))
		return FALSE
	return TRUE

/**
 * Binds a dialogue's two roles to two people, or null when it does not fit them. Either of them can be the
 * one who walked over: a janitor stopping a clown is the same conversation as a clown stopping a janitor.
 */
/proc/sp_cast_dialogue(datum/sp_dialogue/dialogue, mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	var/list/role_names = list()
	for(var/role in dialogue.roles)
		role_names += role
	if(length(role_names) != 2 || starter == partner)
		return null
	for(var/first in 1 to 2)
		var/starter_role = role_names[first]
		var/partner_role = role_names[3 - first]
		if(!sp_dialogue_role_fits(dialogue, starter_role, starter) || !sp_dialogue_role_fits(dialogue, partner_role, partner))
			continue
		var/list/cast = list()
		cast[starter_role] = starter
		cast[partner_role] = partner
		return cast
	return null

/**
 * A thread for these two, not yet started: cast, and with the dialogue's own start conditions holding. Null
 * when it does not fit them. The first line is said on the next tick rather than this one.
 */
/proc/sp_begin_dialogue(datum/sp_dialogue/dialogue, mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	var/list/cast = sp_cast_dialogue(dialogue, starter, partner)
	if(isnull(cast))
		return null
	var/datum/sp_dialogue_thread/thread = new
	thread.dialogue = dialogue
	thread.cast = cast
	thread.current = dialogue.start
	thread.next_due = world.time
	thread.started_at = world.time
	if(!sp_dialogue_conditions_hold(thread, dialogue.start_if))
		qdel(thread)
		return null
	return thread

/// Whether either of two people has had this one with the other lately.
/proc/sp_dialogue_had_lately(mob/living/first, mob/living/second, id)
	return (id in sp_memory_recent(first?.ai_controller, second)) || (id in sp_memory_recent(second?.ai_controller, first))

/**
 * A dialogue these two could have now, or null. `trigger` picks the ones that start on it (a player's intent,
 * or "newcomer"); with none, it picks from the idle crew-to-crew ones, the ones nothing in particular starts.
 */
/proc/sp_pick_dialogue(mob/living/carbon/human/starter, mob/living/carbon/human/partner, trigger)
	var/list/all = sp_all_dialogues()
	var/list/weighted = list()
	for(var/id in all)
		var/datum/sp_dialogue/candidate = all[id]
		if(isnull(trigger) ? length(candidate.triggers) : !(trigger in candidate.triggers))
			continue
		if(sp_dialogue_had_lately(starter, partner, id))
			continue
		var/datum/sp_dialogue_thread/trial = sp_begin_dialogue(candidate, starter, partner)
		if(isnull(trial))
			continue
		qdel(trial)
		weighted[candidate] = candidate.weight
	return length(weighted) ? pick_weight(weighted) : null

/// What a crew member will talk to this player about, by title: the Talk to list.
/proc/sp_dialogues_for_talk(mob/living/carbon/human/npc, mob/living/carbon/human/player)
	var/list/choices = list()
	var/list/all = sp_all_dialogues()
	for(var/id in all)
		var/datum/sp_dialogue/candidate = all[id]
		if(!istext(candidate.title))
			continue
		var/datum/sp_dialogue_thread/trial = sp_begin_dialogue(candidate, npc, player)
		if(isnull(trial))
			continue
		qdel(trial)
		choices[candidate.title] = candidate
	return choices

/// Starts a conversation run by `controller`, which is the starter's, and tells the partner they are in it.
/proc/sp_start_thread(datum/ai_controller/sp_crew/controller, datum/sp_dialogue/dialogue, mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	if(!istype(controller) || isnull(dialogue) || controller.blackboard_key_exists(BB_SP_THREAD))
		return null
	var/datum/sp_dialogue_thread/thread = sp_begin_dialogue(dialogue, starter, partner)
	if(isnull(thread))
		return null
	GLOB.sp_active_threads += thread
	controller.set_blackboard_key(BB_SP_THREAD, thread)
	controller.set_blackboard_key(BB_SP_CHAT_PARTNER, partner)
	controller.set_blackboard_key(BB_SP_CHAT_ASKED_AT, world.time)
	var/datum/ai_controller/sp_crew/their_ai = partner.ai_controller
	if(istype(their_ai))
		their_ai.set_blackboard_key(BB_SP_IN_THREAD, thread)
	sp_record("talk.thread")
	log_sp("[starter.real_name] started [dialogue.id] with [partner.real_name]")
	return thread

/// Ends a thread, whatever brought it to an end, and lets everybody in it go.
/proc/sp_end_dialogue(datum/ai_controller/sp_crew/controller, datum/sp_dialogue_thread/thread)
	if(QDELETED(thread))
		return
	sp_dialogue_remember(thread)
	for(var/role in thread.cast)
		var/mob/living/who = thread.cast[role]
		var/datum/ai_controller/sp_crew/their_ai = who?.ai_controller
		if(istype(their_ai) && their_ai.blackboard[BB_SP_IN_THREAD] == thread)
			their_ai.clear_blackboard_key(BB_SP_IN_THREAD)
	if(controller?.blackboard[BB_SP_THREAD] == thread)
		controller.clear_blackboard_key(BB_SP_THREAD)
		controller.clear_blackboard_key(BB_SP_CHAT_PARTNER)
	sp_record(thread.lines_said ? "talk.finished" : "talk.abandoned")
	log_sp("[controller?.pawn] came to the end of [thread.dialogue?.id] after [thread.lines_said] lines")
	qdel(thread)

// --- Memory ----------------------------------------------------------------------------------------

/// The key memory is filed under: a player's mind, so a new body does not reset them; a crew member's name.
/proc/sp_memory_key(mob/living/who)
	if(QDELETED(who))
		return null
	if(sp_dialogue_is_player(who) && who.mind)
		return who.mind
	return who.real_name

/**
 * What a crew member remembers of somebody, made on first use. The entry is held by reference on the
 * blackboard, so changing it changes the memory; only the book itself has to be written with override.
 */
/proc/sp_memory_of(datum/ai_controller/sp_crew/controller, mob/living/who, create = TRUE)
	if(!istype(controller))
		return null
	var/key = sp_memory_key(who)
	if(isnull(key))
		return null
	var/list/book = controller.blackboard[BB_SP_MEMORY]
	if(!islist(book))
		if(!create)
			return null
		book = list()
		controller.override_blackboard_key(BB_SP_MEMORY, book)
	var/list/entry = book[key]
	if(!islist(entry))
		if(!create)
			return null
		entry = list()
		entry[SP_MEM_NAME] = FALSE
		entry[SP_MEM_TALKED] = 0
		entry[SP_MEM_RECENT] = list()
		entry[SP_MEM_FACTS] = list()
		book[key] = entry
	return entry

/proc/sp_remembers(datum/ai_controller/sp_crew/controller, mob/living/who, fact)
	var/list/entry = sp_memory_of(controller, who, create = FALSE)
	var/list/facts = entry?[SP_MEM_FACTS]
	return !!facts?[fact]

/proc/sp_remember_fact(datum/ai_controller/sp_crew/controller, mob/living/who, fact)
	var/list/entry = sp_memory_of(controller, who)
	if(islist(entry))
		var/list/facts = entry[SP_MEM_FACTS]
		facts[fact] = TRUE

/proc/sp_forget_fact(datum/ai_controller/sp_crew/controller, mob/living/who, fact)
	var/list/entry = sp_memory_of(controller, who, create = FALSE)
	var/list/facts = entry?[SP_MEM_FACTS]
	facts?.Remove(fact)

/// Dialogue ids had with somebody lately, newest last.
/proc/sp_memory_recent(datum/ai_controller/sp_crew/controller, mob/living/who)
	var/list/entry = sp_memory_of(controller, who, create = FALSE)
	return entry?[SP_MEM_RECENT] || list()

/**
 * Whether a crew member knows somebody's name. The crew know each other; a player they learn by being told,
 * or by standing close enough to read the card on their chest (sp_notice_id()).
 */
/proc/sp_knows_name(datum/ai_controller/sp_crew/controller, mob/living/who)
	if(!istype(controller) || QDELETED(who) || !sp_dialogue_is_player(who))
		return TRUE
	var/list/entry = sp_memory_of(controller, who, create = FALSE)
	return !!entry?[SP_MEM_NAME]

/proc/sp_learn_name(datum/ai_controller/sp_crew/controller, mob/living/who)
	var/list/entry = sp_memory_of(controller, who)
	if(!islist(entry) || entry[SP_MEM_NAME])
		return FALSE
	entry[SP_MEM_NAME] = TRUE
	log_sp("[controller.pawn] now knows [who.real_name] by name")
	return TRUE

/// Reading somebody's ID from beside them, which is how a stranger's name gets learned without asking.
/proc/sp_notice_id(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/who)
	var/mob/living/pawn = controller?.pawn
	if(!istype(who) || QDELETED(pawn) || get_dist(pawn, who) > 1 || sp_knows_name(controller, who))
		return FALSE
	// Worn, or held up to be read. TG's hand_first = FALSE looks at worn cards only, which missed somebody
	// holding their ID out -- the one time they are most plainly asking to be known.
	var/obj/item/card/id/card = who.get_idcard(hand_first = TRUE)
	if(isnull(card) || card.registered_name != who.real_name)
		return FALSE
	return sp_learn_name(controller, who)

/// Remembers that a thread happened, with whom, so the same one is not had again straight away.
/proc/sp_dialogue_remember(datum/sp_dialogue_thread/thread)
	for(var/role in thread.cast)
		var/mob/living/who = thread.cast[role]
		var/datum/ai_controller/sp_crew/controller = who?.ai_controller
		if(!istype(controller))
			continue
		for(var/other_role in thread.cast)
			var/mob/living/other = thread.cast[other_role]
			if(other == who)
				continue
			var/list/entry = sp_memory_of(controller, other)
			if(!islist(entry))
				continue
			entry[SP_MEM_TALKED] = entry[SP_MEM_TALKED] + 1
			var/list/recent = entry[SP_MEM_RECENT]
			recent += thread.dialogue.id
			while(length(recent) > SP_DIALOGUE_MEMORY)
				recent.Cut(1, 2)

// --- Station events ----------------------------------------------------------------------------------

/// Something that happened, for the station to talk about afterwards. Forgotten after SP_EVENT_MEMORY.
/proc/sp_station_event(tag, atom/where)
	if(!istext(tag))
		return
	var/area/place = get_area(where)
	var/list/events = SSspacestation_sp.station_events
	var/list/event = list()
	event[SP_EVENT_TAG] = tag
	event[SP_EVENT_AREA_NAME] = place ? place.name : "somewhere"
	event[SP_EVENT_TIME] = world.time
	events += list(event)
	while(length(events))
		var/list/oldest = events[1]
		if(world.time - oldest[SP_EVENT_TIME] <= SP_EVENT_MEMORY)
			break
		events.Cut(1, 2)

/// The newest event whose tag starts with `tag`, within the last `minutes`, or null.
/proc/sp_recent_event(tag, minutes = 10)
	var/list/events = SSspacestation_sp.station_events
	for(var/i in length(events) to 1 step -1)
		var/list/event = events[i]
		if(world.time - event[SP_EVENT_TIME] > minutes MINUTES)
			break
		if(findtext(event[SP_EVENT_TAG], tag) == 1)
			return event
	return null

// --- Conditions and effects --------------------------------------------------------------------------

/// "a->b" as a list of the first one and the second one, or null if either is missing.
/proc/sp_dialogue_pair(datum/sp_dialogue_thread/thread, pair)
	var/list/sides = splittext(pair, "->")
	if(length(sides) != 2)
		return null
	var/mob/living/judge = thread.cast[sides[1]]
	var/mob/living/about = thread.cast[sides[2]]
	if(QDELETED(judge) || QDELETED(about))
		return null
	return list(judge, about)

/// Hurt enough to show it: below seven tenths of their health, or carrying a wound.
/proc/sp_dialogue_hurt(mob/living/carbon/human/who)
	return istype(who) && (who.health < who.maxHealth * 0.7 || length(who.all_wounds))

/proc/sp_dialogue_holding(mob/living/carbon/human/who, item_type)
	for(var/obj/item/held in who?.held_items)
		if(istype(held, item_type))
			return TRUE
	return FALSE

/// Whether the conversation is happening in one of these places, going by where the first of the cast stands.
/proc/sp_dialogue_place_matches(datum/sp_dialogue_thread/thread, list/places)
	var/mob/living/anchor
	for(var/role in thread.cast)
		anchor = thread.cast[role]
		break
	var/area/here = get_area(anchor)
	if(isnull(here))
		return FALSE
	for(var/place in places)
		var/area_type = GLOB.sp_place_tags[place] || text2path(place)
		if(ispath(area_type, /area) && istype(here, area_type))
			return TRUE
	return FALSE

/// The closed vocabulary a file can ask about. See GLOB.sp_dialogue_conditions.
/proc/sp_dialogue_conditions_hold(datum/sp_dialogue_thread/thread, list/tests)
	if(!islist(tests))
		return TRUE
	for(var/kind in tests)
		var/value = tests[kind]
		switch(kind)
			if("random")
				if(!prob(value))
					return FALSE
			if("standing", "memory", "knows_name")
				for(var/pair in value)
					var/list/sides = sp_dialogue_pair(thread, pair)
					if(isnull(sides))
						return FALSE
					var/mob/living/judge = sides[1]
					var/mob/living/about = sides[2]
					var/datum/ai_controller/sp_crew/judge_ai = judge.ai_controller
					var/wanted = value[pair]
					switch(kind)
						if("standing")
							if(!sp_dialogue_compare(istype(judge_ai) ? sp_reputation(judge_ai, about) : 0, wanted))
								return FALSE
						if("memory")
							var/negated = istext(wanted) && findtext(wanted, "!") == 1
							var/fact = negated ? copytext(wanted, 2) : wanted
							if(sp_remembers(judge_ai, about, fact) == negated)
								return FALSE
						if("knows_name")
							if(sp_knows_name(judge_ai, about) != !!wanted)
								return FALSE
			if("job", "department", "hurt", "holding")
				for(var/role in value)
					var/mob/living/carbon/human/who = thread.cast[role]
					if(QDELETED(who))
						return FALSE
					var/wanted = value[role]
					switch(kind)
						if("job")
							if(!(who.mind?.assigned_role?.title in wanted))
								return FALSE
						if("department")
							if(!sp_in_departments(who, wanted))
								return FALSE
						if("hurt")
							if(sp_dialogue_hurt(who) != !!wanted)
								return FALSE
						if("holding")
							if(!sp_dialogue_holding(who, text2path(wanted)))
								return FALSE
			if("place")
				if(!sp_dialogue_place_matches(thread, value))
					return FALSE
			if("time_into_shift")
				if(!sp_dialogue_compare((world.time - SSticker.round_start_time) / (1 MINUTES), value))
					return FALSE
			if("recent_event")
				var/list/wanted = value
				if(istext(value))
					wanted = list()
					wanted[value] = 10
				var/list/found
				for(var/tag in wanted)
					found = sp_recent_event(tag, wanted[tag])
					if(found)
						break
				if(isnull(found))
					return FALSE
				thread.event = found
			else
				return FALSE
	return TRUE

/// The closed list of what a line can change. See GLOB.sp_dialogue_effects.
/proc/sp_dialogue_effect(datum/sp_dialogue_thread/thread, list/effect)
	for(var/kind in effect)
		var/value = effect[kind]
		switch(kind)
			if("standing", "remember", "forget", "learn_name")
				for(var/pair in value)
					var/list/sides = sp_dialogue_pair(thread, pair)
					if(isnull(sides))
						continue
					var/mob/living/judge = sides[1]
					var/mob/living/about = sides[2]
					var/datum/ai_controller/sp_crew/judge_ai = judge.ai_controller
					if(!istype(judge_ai))
						continue // players keep their own counsel
					switch(kind)
						if("standing")
							sp_adjust_reputation(judge_ai, about, value[pair], "talked it over")
						if("remember")
							sp_remember_fact(judge_ai, about, value[pair])
						if("forget")
							sp_forget_fact(judge_ai, about, value[pair])
						if("learn_name")
							if(value[pair])
								sp_learn_name(judge_ai, about)
			if("event")
				var/mob/living/anchor
				for(var/role in thread.cast)
					anchor = thread.cast[role]
					break
				sp_station_event(value, anchor)
			if("give")
				sp_dialogue_give(thread, value)

/// Hands over something the giver actually carries. Nothing is conjured: no item, no gift, just the line.
/proc/sp_dialogue_give(datum/sp_dialogue_thread/thread, list/details)
	var/mob/living/carbon/human/giver = thread.cast[details["from"]]
	var/mob/living/carbon/human/taker = thread.cast[details["to"]]
	var/item_type = text2path(details["item"])
	if(!istype(giver) || !istype(taker) || !ispath(item_type, /obj/item))
		return FALSE
	var/list/carried = giver.get_all_contents_type(item_type)
	if(!length(carried))
		return FALSE
	var/obj/item/gift = carried[1]
	if(!taker.put_in_hands(gift))
		gift.forceMove(get_turf(taker))
	log_sp("[giver.real_name] gave [gift.name] to [taker.real_name]")
	return TRUE

/// What a station event was, in words, for a rumour to say.
/proc/sp_dialogue_event_phrase(list/event)
	var/static/list/phrases = list(
		"graffiti" = "somebody drawing on the floor",
		"lights" = "the lights going out",
		"vandalism" = "a smashed light",
		"bell" = "somebody leaning on the desk bell",
		"knock" = "somebody banging on the windows",
		"honk" = "somebody honking",
		"peel" = "a banana peel",
		"arrest" = "an arrest",
		"fight" = "a fight",
	)
	var/tag = event?[SP_EVENT_TAG]
	return phrases[tag] || "some trouble"

/// What a crew member calls somebody whose name they do not know. Security are officious about it.
/proc/sp_dialogue_stranger(mob/living/speaker)
	var/list/departments = speaker?.mind?.assigned_role?.departments_list
	if(islist(departments) && (/datum/job_department/security in departments))
		return "citizen"
	return "mate"

/// Fills a line in. A name the speaker does not know comes out as whatever they call a stranger.
/proc/sp_dialogue_fill(datum/sp_dialogue_thread/thread, line, mob/living/speaker)
	var/area/here = get_area(speaker)
	line = replacetext(line, "%AREA%", here ? here.name : "the station")
	line = replacetext(line, "%EVENT_AREA%", thread.event ? thread.event[SP_EVENT_AREA_NAME] : "somewhere")
	line = replacetext(line, "%EVENT%", sp_dialogue_event_phrase(thread.event))
	var/datum/ai_controller/sp_crew/speaker_ai = speaker?.ai_controller
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		var/upper = uppertext(role)
		var/known = who == speaker || !istype(speaker_ai) || sp_knows_name(speaker_ai, who)
		line = replacetext(line, "%[upper]_FIRST%", known ? sp_first_name(who) : sp_dialogue_stranger(speaker))
		line = replacetext(line, "%[upper]_NAME%", known ? who?.real_name : sp_dialogue_stranger(speaker))
		line = replacetext(line, "%[upper]_JOB%", who?.mind?.assigned_role?.title || "crew")
	return line

// --- Running a thread ------------------------------------------------------------------------------

/// Whoever is not the speaker.
/proc/sp_dialogue_other(datum/sp_dialogue_thread/thread, mob/speaker)
	for(var/role in thread.cast)
		var/mob/who = thread.cast[role]
		if(who != speaker)
			return who
	return null

/**
 * Everybody in it is alive, awake, near enough, and has nothing more pressing on. Work that turns up, or
 * somebody going for one of them, ends a conversation: none of this outranks the job or an emergency.
 */
/proc/sp_dialogue_still_talking(datum/sp_dialogue_thread/thread)
	if(world.time - thread.started_at > SP_DIALOGUE_MAX_TIME)
		return FALSE
	var/mob/living/carbon/human/anchor
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		if(QDELETED(who) || who.stat != STABLE)
			return FALSE
		var/datum/ai_controller/sp_crew/their_ai = who.ai_controller
		if(istype(their_ai) && (their_ai.busy_with_work() || their_ai.blackboard_key_exists(BB_SP_ATTACKER)))
			return FALSE
		if(isnull(anchor))
			anchor = who
			continue
		if(get_dist(anchor, who) > SP_DIALOGUE_RANGE || !can_see(anchor, who, SP_DIALOGUE_RANGE))
			return FALSE
	return TRUE

/// Crew in a conversation with a player read their ID if they are close enough to.
/proc/sp_dialogue_notice_ids(datum/sp_dialogue_thread/thread)
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		var/datum/ai_controller/sp_crew/their_ai = who?.ai_controller
		if(!istype(their_ai))
			continue
		for(var/other_role in thread.cast)
			var/mob/living/carbon/human/other = thread.cast[other_role]
			if(other != who && sp_dialogue_is_player(other))
				sp_notice_id(their_ai, other)

/**
 * Says the line this thread is up to and works out the next one, or offers a player their replies. Returns
 * FALSE when the thread is over, which is also what a pair who have drifted apart comes to.
 */
/datum/sp_dialogue_thread/proc/advance()
	if(isnull(current) || lines_said >= SP_DIALOGUE_MAX_LINES || !sp_dialogue_still_talking(src))
		return FALSE
	if(length(pending_options))
		return TRUE // their turn, not ours
	var/list/node = dialogue.nodes[current]
	if(!islist(node))
		return FALSE
	var/mob/living/carbon/human/speaker = cast[node["speaker"]]
	if(QDELETED(speaker))
		return FALSE
	sp_dialogue_notice_ids(src)
	if(sp_dialogue_role_is_player(dialogue, node["speaker"]))
		return offer_options(node, speaker)
	speaker.face_atom(sp_dialogue_other(src, speaker))
	sp_crew_speak(speaker, sp_dialogue_fill(src, pick(node["lines"]), speaker))
	lines_said++
	sp_record("talk.line")
	for(var/list/effect in node["effects"])
		sp_dialogue_effect(src, effect)
	current = sp_dialogue_next(src, node["next"])
	next_due = world.time + (node["wait"] ? (node["wait"] SECONDS) : SP_DIALOGUE_GAP)
	return !isnull(current)

/// The next node, by weight, ignoring any edge whose conditions do not hold.
/proc/sp_dialogue_next(datum/sp_dialogue_thread/thread, list/edges)
	var/list/weighted = list()
	for(var/list/edge in edges)
		if(!sp_dialogue_conditions_hold(thread, edge["if"]))
			continue
		weighted[edge["to"]] = edge["weight"] || 1
	if(!length(weighted))
		return null
	var/chosen = pick_weight(weighted)
	return chosen == SP_DIALOGUE_END ? null : chosen

/// A player's turn: the replies whose conditions hold, offered as links for SP_DIALOGUE_ANSWER_TIME.
/datum/sp_dialogue_thread/proc/offer_options(list/node, mob/living/carbon/human/player)
	pending_options = list()
	for(var/list/option in node["options"])
		if(sp_dialogue_conditions_hold(src, option["if"]))
			pending_options += list(option)
	if(!length(pending_options))
		pending_options = null
		current = node["timeout_to"] == SP_DIALOGUE_END ? null : node["timeout_to"]
		return !isnull(current)
	options_expire = world.time + SP_DIALOGUE_ANSWER_TIME
	// Shown just after the line they answer: speech goes out through INVOKE_ASYNC, and replies arriving above
	// the question they answer read as a bug.
	addtimer(CALLBACK(src, PROC_REF(show_options), player), 0.3 SECONDS)
	return TRUE

/// The replies, as links in the player's chat. A click comes back through Topic().
/datum/sp_dialogue_thread/proc/show_options(mob/living/carbon/human/player)
	if(QDELETED(player) || isnull(player.client) || !length(pending_options))
		return
	var/list/links = list()
	for(var/i in 1 to length(pending_options))
		var/list/option = pending_options[i]
		links += "<a href='byond://?src=[REF(src)];sp_choice=[i]'>&#91;[sp_dialogue_fill(src, option["text"], player)]&#93;</a>"
	to_chat(player, span_notice("Reply: [jointext(links, " ")]"))

/datum/sp_dialogue_thread/Topic(href, list/href_list)
	. = ..()
	if(href_list["sp_choice"])
		choose(usr, text2num(href_list["sp_choice"]))

/**
 * A player picks a reply. Refused for anybody but the player in the thread, for an offer that has lapsed or
 * been replaced, and for a player who has walked off. The reply is said aloud through their own character, so
 * everybody nearby hears it the ordinary way. Returns TRUE if it was taken.
 */
/datum/sp_dialogue_thread/proc/choose(mob/chooser, index)
	var/mob/living/carbon/human/player = cast[sp_dialogue_player_role(src)]
	if(isnull(player) || chooser != player)
		return FALSE
	if(!length(pending_options) || !isnum(index) || index < 1 || index > length(pending_options))
		return FALSE
	if(world.time > options_expire)
		to_chat(player, span_notice("The moment has passed."))
		return FALSE
	if(!sp_dialogue_still_talking(src))
		return FALSE
	var/list/option = pending_options[index]
	pending_options = null
	player.say(sp_dialogue_fill(src, option["text"], player), forced = "SP dialogue reply")
	lines_said++
	sp_record("talk.chose")
	for(var/list/effect in option["effects"])
		sp_dialogue_effect(src, effect)
	current = option["to"] == SP_DIALOGUE_END ? null : option["to"]
	next_due = world.time + SP_DIALOGUE_GAP
	return TRUE

/// The player said nothing in time: silence is an answer, and the file says where it goes.
/datum/sp_dialogue_thread/proc/expire()
	var/list/node = dialogue?.nodes[current]
	pending_options = null
	var/destination = islist(node) ? node["timeout_to"] : null
	current = (isnull(destination) || destination == SP_DIALOGUE_END) ? null : destination
	next_due = world.time
	sp_record("talk.ignored")

// --- Talking to somebody on purpose ----------------------------------------------------------------

/**
 * Talking to a crew member on purpose, rather than waiting for them to start. Right-click them, pick what
 * about, and the conversation runs through the same threads as any other, spoken aloud.
 */
/mob/living/carbon/human/verb/sp_talk_to()
	set name = "Talk to"
	set category = "IC"
	set src in oview(2)
	var/mob/living/carbon/human/player = usr
	if(!istype(player) || player.stat != STABLE)
		return
	var/datum/ai_controller/sp_crew/crew_ai = ai_controller
	if(!istype(crew_ai))
		to_chat(player, span_notice("[src] does not seem to want to talk."))
		return
	if(!crew_ai.free_to_talk(player) || crew_ai.blackboard_key_exists(BB_SP_THREAD))
		to_chat(player, span_notice("[src] is busy."))
		return
	var/list/choices = sp_dialogues_for_talk(src, player)
	if(!length(choices))
		to_chat(player, span_notice("[src] has nothing to say to you just now."))
		return
	var/picked = tgui_input_list(player, "What about?", "Talk to [src]", choices)
	if(isnull(picked) || QDELETED(src) || get_dist(src, player) > 2 || !crew_ai.free_to_talk(player))
		return
	sp_start_thread(crew_ai, choices[picked], src, player)

/// How they regard you shows on examine, but only at the extremes: felt the rest of the time.
/datum/ai_controller/sp_crew/proc/on_examined(datum/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	var/mob/living/carbon/human/human_pawn = pawn
	if(!istype(human_pawn) || !isliving(user) || user == pawn)
		return
	var/standing = sp_reputation(src, user)
	if(standing >= SP_REP_FRIENDLY)
		examine_list += span_notice("[human_pawn.p_They()] seem[human_pawn.p_s()] to like you.")
	else if(standing <= SP_REP_HOSTILE)
		examine_list += span_warning("[human_pawn.p_They()] seem[human_pawn.p_s()] wary of you.")
