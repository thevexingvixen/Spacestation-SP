/**
 * Conversation and standing.
 *
 * Two AI crew who find themselves near each other with nothing urgent to do will strike up a short
 * exchange: an opener, an answer, sometimes a closing remark. Because both sides are ours, the
 * listener can read the topic straight off the speaker's controller, so the replies actually match
 * what was said instead of being generic noise.
 *
 * Players get the same machinery from the other direction. What someone is likely to say to a crew
 * member in singleplayer is fairly predictable -- a greeting, "what do you do", "where is x", asking
 * for help, thanks, or abuse -- so those are matched by keyword and answered in character. Every
 * exchange nudges how the crew member feels about that person, which is the groundwork for the
 * standing system: be decent to a crew member and they will warm to you.
 *
 * None of this outranks an emergency. Conversation sits below the core subtree, so a fight, an
 * injury or somebody drawing a weapon cuts it off mid-sentence.
 */

/// Something two crew members can talk about.
/datum/sp_topic
	/// Identifier, for the log.
	var/id = "smalltalk"
	/// How likely this is to come up.
	var/weight = 1
	/// Job titles that raise this topic. Null means anyone.
	var/list/opener_jobs
	/// Lines that start it. "%TARGET%" becomes the other person's first name.
	var/list/openers = list()
	/// Lines that answer it.
	var/list/replies = list()
	/// Optional last word from whoever opened.
	var/list/closers = list()

/datum/sp_topic/shift
	id = "shift"
	weight = 3
	openers = list(
		"Long one today, %TARGET%?",
		"How's your shift going, %TARGET%?",
		"You been on since the start, %TARGET%?",
		"Quiet so far. Suspiciously quiet.",
	)
	replies = list(
		"Same as every shift. Ask me again in an hour.",
		"Can't complain. Well, I can, but I won't.",
		"Busy enough. Better than standing around.",
		"Don't say quiet. You'll jinx it.",
	)
	closers = list(
		"Fair enough.",
		"Ha. Yeah.",
		"Well, back to it.",
	)

/datum/sp_topic/food
	id = "food"
	weight = 2
	openers = list(
		"Has the kitchen put anything out yet, %TARGET%?",
		"I'd kill for a decent meal right now.",
		"%TARGET%, do you know if there's anything left in the kitchen?",
	)
	replies = list(
		"There was something earlier. Probably gone by now.",
		"Last I looked it was empty. Botany's been dropping things off, though.",
		"Go check. I'm not your errand runner.",
	)
	closers = list(
		"Worth a look, thanks.",
		"Figures.",
	)

/datum/sp_topic/gossip
	id = "gossip"
	weight = 2
	openers = list(
		"You hear about what happened in maintenance, %TARGET%?",
		"Command's been quiet today. Never a good sign.",
		"%TARGET%, is it me or has the clown been unusually calm?",
	)
	replies = list(
		"I heard something. Didn't get the details.",
		"I try not to ask. Makes the shift shorter.",
		"Give it time. It never lasts.",
	)
	closers = list(
		"That's the station for you.",
		"Suppose so.",
	)

/datum/sp_topic/engineering
	id = "engineering"
	weight = 3
	opener_jobs = list("Station Engineer", "Chief Engineer", "Atmospheric Technician")
	openers = list(
		"Power's holding steady, %TARGET%. For now.",
		"If the lights flicker, %TARGET%, that's on me and I'm sorry.",
		"Engine's behaving itself today.",
	)
	replies = list(
		"Good. I'd rather not do this shift in the dark.",
		"Long may it last.",
		"Let me know if it stops behaving.",
	)

/datum/sp_topic/medical
	id = "medical"
	weight = 3
	opener_jobs = list("Medical Doctor", "Chief Medical Officer", "Paramedic", "Coroner")
	openers = list(
		"You're looking well, %TARGET%. Keep it that way, I'm busy.",
		"Medbay's clear at the moment. Don't ruin it.",
		"%TARGET%, if anything starts hurting, come and see me before it gets worse.",
	)
	replies = list(
		"I'll bear that in mind.",
		"No promises.",
		"You'll be the first to know.",
	)

/datum/sp_topic/security
	id = "security"
	weight = 3
	opener_jobs = list("Security Officer", "Head of Security", "Warden", "Detective")
	openers = list(
		"Seen anything worth reporting, %TARGET%?",
		"Keep your ID visible and we'll get along fine.",
		"Nothing to report so far. Let's keep it that way.",
	)
	replies = list(
		"Nothing from me.",
		"All quiet where I've been.",
		"You'll hear about it if I do.",
	)

/datum/sp_topic/botany
	id = "botany"
	weight = 3
	opener_jobs = list("Botanist")
	openers = list(
		"I've got something new coming up in the trays, %TARGET%.",
		"There's produce on the table in hydroponics if you want any.",
		"%TARGET%, do me a favour and don't touch the tray at the back.",
	)
	replies = list(
		"What is it this time?",
		"I might take you up on that.",
		"I wasn't going to. Now I want to.",
	)
	closers = list(
		"You'll see.",
		"Help yourself.",
	)

/// All topics, built once.
/proc/sp_all_topics()
	var/static/list/topics
	if(isnull(topics))
		topics = list()
		for(var/topic_type in subtypesof(/datum/sp_topic))
			topics += new topic_type
	return topics

/// A topic this crew member might raise, weighted, respecting job restrictions.
/proc/sp_pick_topic(mob/living/carbon/human/speaker)
	var/job_title = speaker.mind?.assigned_role?.title
	var/list/weighted = list()
	for(var/datum/sp_topic/topic as anything in sp_all_topics())
		if(length(topic.opener_jobs) && !(job_title in topic.opener_jobs))
			continue
		weighted[topic] = topic.weight
	return length(weighted) ? pick_weight(weighted) : null

/// First name only; crew address each other casually.
/proc/sp_first_name(mob/who)
	if(QDELETED(who))
		return "you"
	var/list/parts = splittext(who.real_name, " ")
	return length(parts) ? parts[1] : who.real_name

/// Another AI crew member nearby who is free to talk.
/proc/sp_find_chat_partner(mob/living/carbon/human/speaker, range = 5)
	for(var/mob/living/carbon/human/candidate in oview(range, speaker))
		if(candidate.stat != STABLE || candidate == speaker)
			continue
		var/datum/ai_controller/sp_crew/their_ai = candidate.ai_controller
		if(!istype(their_ai))
			continue
		// Don't interrupt someone already mid-conversation or dealing with something.
		if(their_ai.blackboard_key_exists(BB_SP_CHAT_PARTNER) || their_ai.blackboard_key_exists(BB_SP_ATTACKER))
			continue
		if(!can_see(speaker, candidate, range))
			continue
		return candidate
	return null

// --- Standing ---------------------------------------------------------------------------------

/// How this crew member feels about someone. 0 is a stranger.
/proc/sp_reputation(datum/ai_controller/sp_crew/controller, mob/who)
	if(QDELETED(who))
		return 0
	var/list/book = controller.blackboard[BB_SP_REPUTATION]
	return LAZYACCESS(book, who) || 0

/// Nudges how this crew member feels about someone, and says so if it crosses a line.
/proc/sp_adjust_reputation(datum/ai_controller/sp_crew/controller, mob/who, amount, reason)
	if(QDELETED(who) || !amount)
		return
	var/before = sp_reputation(controller, who)
	var/after = clamp(before + amount, -10, 10)
	controller.set_blackboard_key_assoc_lazylist(BB_SP_REPUTATION, who, after)
	if(before < SP_REP_FRIENDLY && after >= SP_REP_FRIENDLY)
		log_sp("[controller.pawn] now thinks well of [who] ([reason])")
	else if(before > SP_REP_HOSTILE && after <= SP_REP_HOSTILE)
		log_sp("[controller.pawn] has taken a dislike to [who] ([reason])")

/**
 * What a crew member says back to a person, based on what they said and how they feel about them.
 * Returns null when nothing said warrants an answer.
 */
/proc/sp_answer_for(datum/ai_controller/sp_crew/controller, mob/asker, message)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !istext(message))
		return null
	var/lowered = LOWER_TEXT(message)
	var/standing = sp_reputation(controller, asker)
	var/job_title = pawn.mind?.assigned_role?.title || "crew"
	var/their_name = sp_first_name(asker)

	// Abuse. Costs them standing and gets short shrift.
	for(var/insult in list("idiot", "shut up", "stupid", "useless", "moron"))
		if(findtext(lowered, insult))
			sp_adjust_reputation(controller, asker, -3, "insulted us")
			return pick("Charming.", "There's no call for that.", "Right. Noted.")

	// Thanks and compliments earn goodwill.
	for(var/kind in list("thank", "thanks", "cheers", "good job", "well done", "nice work", "appreciate"))
		if(findtext(lowered, kind))
			sp_adjust_reputation(controller, asker, 2, "was polite")
			return pick("Any time.", "No trouble at all.", "Don't mention it, [their_name].")

	// Greetings.
	for(var/hello in list("hello", "hi ", "hey", "greetings", "good morning", "howdy"))
		if(findtext(lowered, hello))
			sp_adjust_reputation(controller, asker, 1, "said hello")
			if(standing >= SP_REP_FRIENDLY)
				return pick("Good to see you, [their_name].", "[their_name]! How are you?")
			return pick("Hello.", "Hey there.", "Afternoon.")

	// Asking what they do or who they are.
	if(findtext(lowered, "what do you do") || findtext(lowered, "your job") || findtext(lowered, "who are you"))
		return "I'm [pawn.real_name], [job_title]."

	// Asking where they work, or where something is.
	if(findtext(lowered, "where"))
		var/area/here = get_area(pawn)
		if(findtext(lowered, "you") || findtext(lowered, "work"))
			return "I work out of [here ? here.name : "wherever they put me"]."
		return pick("Couldn't tell you offhand.", "Try asking someone from that department.", "No idea, sorry.")

	// Asking for help.
	if(findtext(lowered, "help") || findtext(lowered, "can you"))
		if(standing <= SP_REP_HOSTILE)
			return pick("Ask someone else.", "I'm busy.")
		return pick("What do you need?", "If it's quick, sure.", "I can try.")

	// Being asked to come along. The standing system is what will eventually decide this properly.
	if(findtext(lowered, "follow me") || findtext(lowered, "come with"))
		if(standing >= SP_REP_FRIENDLY)
			return "Alright, [their_name], lead on."
		return pick("I've got work to do.", "Maybe later, I'm in the middle of something.")

	// How are you.
	if(findtext(lowered, "how are you") || findtext(lowered, "you alright") || findtext(lowered, "you ok"))
		if(pawn.health < pawn.maxHealth * 0.7)
			return "Been better, honestly."
		return pick("Fine, thanks.", "Can't complain.", "Getting on with it.")

	return null
