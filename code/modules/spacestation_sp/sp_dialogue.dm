/**
 * Written dialogue: conversations kept as data rather than as string lists in code.
 *
 * A dialogue is a small graph of nodes, one json file each, in strings/spacestation_sp/dialogue. Each node
 * that speaks it, the lines it may use, and where the conversation can go next. Roles are bound to real crew
 * when a thread starts: a role naming jobs only takes somebody holding one of them, a role naming none takes
 * anybody. Everything a file can ask about or change is a closed vocabulary, checked as the file loads and
 * again in a unit test, so a typo is a failed test rather than a conversation that quietly never happens.
 *
 * This is the first slice of docs/01-dialogue-plan.md M1: crew to crew, no player-facing choices yet. Both
 * sides are ours, so one thread speaks for both of them, and the listener's own hearing ignores the lines --
 * a line only counts as an opener while its speaker is at SP_CHAT_OPENED, which a thread never sets.
 */

/// A dialogue, as read from one file.
/datum/sp_dialogue
	/// Identifier, which is also what the repeat guard and the log use.
	var/id
	/// How likely this one is when several fit the pair.
	var/weight = 1
	/// role name -> list("job" = list of titles). No titles means anybody may play it.
	var/list/roles = list()
	/// The node the thread starts on.
	var/start
	/// node id -> the node.
	var/list/nodes = list()

/// A dialogue two crew members are in the middle of.
/datum/sp_dialogue_thread
	var/datum/sp_dialogue/dialogue
	/// role name -> mob.
	var/list/cast = list()
	/// The node whose line is said next, or null when the thread is done.
	var/current
	/// When that line is due.
	var/next_due = 0
	/// How many lines have been said, so a file that loops cannot talk forever.
	var/lines_said = 0

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
 * Every edge has to lead to a node that exists or to the end, every node has to be spoken by a declared
 * role, and every placeholder has to be one that can actually be filled in. A dialogue that fails any of
 * that is not loaded at all: half a conversation is worse than none, and the unit test names the file.
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
	dialogue.weight = raw["weight"] || 1
	dialogue.start = raw["start"]
	dialogue.roles = islist(raw["roles"]) ? raw["roles"] : list()
	dialogue.nodes = islist(raw["nodes"]) ? raw["nodes"] : list()
	if(!istext(dialogue.id) || !length(dialogue.id))
		problems += "it has no id"
	if(length(dialogue.roles) != 2)
		problems += "it has [length(dialogue.roles)] roles, and a thread is between two people"
	if(!length(dialogue.nodes))
		problems += "it has no nodes"
	else if(!(dialogue.start in dialogue.nodes))
		problems += "it starts at [dialogue.start || "nowhere"], which is not one of its nodes"
	if(SP_DIALOGUE_END in dialogue.nodes)
		problems += "it has a node called [SP_DIALOGUE_END], which is the word that ends a thread"
	for(var/node_id in dialogue.nodes)
		var/list/node = dialogue.nodes[node_id]
		if(!islist(node))
			problems += "node [node_id] is not an object"
			continue
		if(!(node["speaker"] in dialogue.roles))
			problems += "node [node_id] is spoken by [node["speaker"] || "nobody"], which is not one of its roles"
		if(!length(node["lines"]))
			problems += "node [node_id] has no lines"
		for(var/line in node["lines"])
			for(var/placeholder in sp_dialogue_placeholders(line))
				if(!sp_dialogue_placeholder_known(placeholder, dialogue))
					problems += "node [node_id] uses %[placeholder]%, which is not a placeholder"
		for(var/list/edge in node["next"])
			if(!islist(edge))
				problems += "node [node_id] has an edge that is not an object"
				continue
			if(edge["to"] != SP_DIALOGUE_END && !(edge["to"] in dialogue.nodes))
				problems += "node [node_id] leads to [edge["to"] || "nowhere"], which is not a node"
			if(!isnull(edge["weight"]) && edge["weight"] <= 0)
				problems += "node [node_id] has an edge weighted [edge["weight"]]"
			for(var/test in edge["if"])
				if(!(test in GLOB.sp_dialogue_conditions))
					problems += "node [node_id] asks about [test], which is not a condition"
		for(var/list/effect in node["effects"])
			if(!islist(effect))
				problems += "node [node_id] has an effect that is not an object"
				continue
			for(var/kind in effect)
				if(!(kind in GLOB.sp_dialogue_effects))
					problems += "node [node_id] does [kind], which is not an effect"
	return length(problems) ? null : dialogue

/// What a file may ask about, and what it may change. Both are deliberately short.
GLOBAL_LIST_INIT(sp_dialogue_conditions, list("random", "standing"))
GLOBAL_LIST_INIT(sp_dialogue_effects, list("standing"))

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

/// Whether a placeholder is one we can fill: the area, or a role's first name or job.
/proc/sp_dialogue_placeholder_known(placeholder, datum/sp_dialogue/dialogue)
	if(placeholder == "AREA")
		return TRUE
	for(var/role in dialogue.roles)
		if(placeholder == "[uppertext(role)]_FIRST" || placeholder == "[uppertext(role)]_JOB")
			return TRUE
	return FALSE

// --- Casting and picking -----------------------------------------------------------------------------

/// Whether somebody can play a role: one naming jobs wants one of those, one naming none takes anybody.
/proc/sp_dialogue_role_fits(datum/sp_dialogue/dialogue, role, mob/living/carbon/human/who)
	if(QDELETED(who))
		return FALSE
	var/list/wanted = dialogue.roles[role]
	var/list/jobs = islist(wanted) ? wanted["job"] : null
	if(!length(jobs))
		return TRUE
	return (who.mind?.assigned_role?.title in jobs)

/**
 * Binds a dialogue's two roles to two crew, or null when it does not fit them. Either of them can be the
 * one who walked over: a janitor stopping a clown is the same conversation as a clown stopping a janitor.
 */
/proc/sp_cast_dialogue(datum/sp_dialogue/dialogue, mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	var/list/role_names = list()
	for(var/role in dialogue.roles)
		role_names += role
	if(length(role_names) != 2)
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

/// A dialogue these two could have now, avoiding whatever either of them has been through lately.
/proc/sp_pick_dialogue(mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	var/datum/ai_controller/sp_crew/our_ai = starter?.ai_controller
	var/datum/ai_controller/sp_crew/their_ai = partner?.ai_controller
	var/list/recent = (our_ai?.blackboard[BB_SP_RECENT_DIALOGUE] || list()) + (their_ai?.blackboard[BB_SP_RECENT_DIALOGUE] || list())
	var/list/all = sp_all_dialogues()
	var/list/weighted = list()
	for(var/id in all)
		if(id in recent)
			continue
		var/datum/sp_dialogue/candidate = all[id]
		if(isnull(sp_cast_dialogue(candidate, starter, partner)))
			continue
		weighted[candidate] = candidate.weight
	return length(weighted) ? pick_weight(weighted) : null

/// Starts a thread. The first line is said on the next tick rather than this one.
/proc/sp_begin_dialogue(datum/sp_dialogue/dialogue, mob/living/carbon/human/starter, mob/living/carbon/human/partner)
	var/list/cast = sp_cast_dialogue(dialogue, starter, partner)
	if(isnull(cast))
		return null
	var/datum/sp_dialogue_thread/thread = new
	thread.dialogue = dialogue
	thread.cast = cast
	thread.current = dialogue.start
	thread.next_due = world.time
	return thread

// --- Running it --------------------------------------------------------------------------------------

/**
 * Says the line this thread is up to, and works out the next one. Returns FALSE when the thread is over,
 * which is also what a pair who have walked apart, or one of them being in no state to talk, comes to.
 */
/datum/sp_dialogue_thread/proc/advance()
	if(isnull(current) || lines_said >= SP_DIALOGUE_MAX_LINES || !sp_dialogue_still_talking(src))
		return FALSE
	var/list/node = dialogue.nodes[current]
	if(!islist(node))
		return FALSE
	var/mob/living/carbon/human/speaker = cast[node["speaker"]]
	if(QDELETED(speaker))
		return FALSE
	speaker.face_atom(sp_dialogue_other(src, speaker))
	sp_crew_speak(speaker, sp_dialogue_fill(src, pick(node["lines"]), speaker))
	lines_said++
	sp_record("talk.line")
	for(var/list/effect in node["effects"])
		sp_dialogue_effect(src, effect)
	current = sp_dialogue_next(src, node["next"])
	next_due = world.time + (node["wait"] ? (node["wait"] SECONDS) : SP_DIALOGUE_GAP)
	return !isnull(current)

/// Whoever is not the speaker.
/proc/sp_dialogue_other(datum/sp_dialogue_thread/thread, mob/speaker)
	for(var/role in thread.cast)
		var/mob/who = thread.cast[role]
		if(who != speaker)
			return who
	return null

/// Everybody in the cast is alive, conscious, and still within earshot of the other.
/proc/sp_dialogue_still_talking(datum/sp_dialogue_thread/thread)
	var/mob/living/carbon/human/anchor
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		if(QDELETED(who) || who.stat != STABLE)
			return FALSE
		if(isnull(anchor))
			anchor = who
			continue
		if(get_dist(anchor, who) > SP_DIALOGUE_RANGE || !can_see(anchor, who, SP_DIALOGUE_RANGE))
			return FALSE
	return TRUE

/// Fills a line in: the area, and each role's first name and job.
/proc/sp_dialogue_fill(datum/sp_dialogue_thread/thread, line, mob/speaker)
	var/area/here = get_area(speaker)
	line = replacetext(line, "%AREA%", here ? here.name : "the station")
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		line = replacetext(line, "%[uppertext(role)]_FIRST%", sp_first_name(who))
		line = replacetext(line, "%[uppertext(role)]_JOB%", who?.mind?.assigned_role?.title || "crew")
	return line

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

/// A roll of the dice, or what one role thinks of the other. That is the whole vocabulary for now.
/proc/sp_dialogue_conditions_hold(datum/sp_dialogue_thread/thread, list/tests)
	if(!islist(tests))
		return TRUE
	for(var/kind in tests)
		switch(kind)
			if("random")
				if(!prob(tests[kind]))
					return FALSE
			if("standing")
				var/list/pairs = tests[kind]
				for(var/pair in pairs)
					if(!sp_dialogue_standing_holds(thread, pair, pairs[pair]))
						return FALSE
			else
				return FALSE
	return TRUE

/// "janitor->other": ">=4" -- what the first one thinks of the second, against a threshold.
/proc/sp_dialogue_standing_holds(datum/sp_dialogue_thread/thread, pair, requirement)
	var/list/sides = splittext(pair, "->")
	if(length(sides) != 2)
		return FALSE
	var/mob/living/carbon/human/judge = thread.cast[sides[1]]
	var/mob/living/carbon/human/about = thread.cast[sides[2]]
	var/datum/ai_controller/sp_crew/controller = judge?.ai_controller
	if(!istype(controller) || QDELETED(about))
		return FALSE
	var/standing = sp_reputation(controller, about)
	if(findtext(requirement, ">=") == 1)
		return standing >= text2num(copytext(requirement, 3))
	if(findtext(requirement, "<=") == 1)
		return standing <= text2num(copytext(requirement, 3))
	return standing == text2num(requirement)

/// Standing only, for now: memory is the next milestone rather than this one.
/proc/sp_dialogue_effect(datum/sp_dialogue_thread/thread, list/effect)
	for(var/kind in effect)
		if(kind != "standing")
			continue
		var/list/pairs = effect[kind]
		for(var/pair in pairs)
			var/list/sides = splittext(pair, "->")
			if(length(sides) != 2)
				continue
			var/mob/living/carbon/human/judge = thread.cast[sides[1]]
			var/mob/living/carbon/human/about = thread.cast[sides[2]]
			var/datum/ai_controller/sp_crew/controller = judge?.ai_controller
			if(istype(controller) && !QDELETED(about))
				sp_adjust_reputation(controller, about, pairs[pair], "talked it over")

/// Remembers that this pair have had this one, so they do not have it again straight afterwards.
/proc/sp_dialogue_remember(datum/sp_dialogue_thread/thread)
	for(var/role in thread.cast)
		var/mob/living/carbon/human/who = thread.cast[role]
		var/datum/ai_controller/sp_crew/controller = who?.ai_controller
		if(!istype(controller))
			continue
		var/list/recent = (controller.blackboard[BB_SP_RECENT_DIALOGUE] || list()).Copy()
		recent += thread.dialogue.id
		while(length(recent) > SP_DIALOGUE_MEMORY)
			recent.Cut(1, 2)
		// A list on the blackboard has to be written with override: set_blackboard_key will not replace one.
		controller.override_blackboard_key(BB_SP_RECENT_DIALOGUE, recent)
