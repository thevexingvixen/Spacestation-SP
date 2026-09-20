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
		var/datum/ai_controller/sp_crew/their_ai = candidate.ai_controller
		if(!istype(their_ai) || !their_ai.free_to_talk(speaker))
			continue
		// Don't interrupt someone already mid-conversation or dealing with something.
		if(their_ai.blackboard_key_exists(BB_SP_CHAT_PARTNER) || their_ai.blackboard_key_exists(BB_SP_ATTACKER))
			continue
		if(!can_see(speaker, candidate, range))
			continue
		return candidate
	return null

// --- Reading what was said ----------------------------------------------------------------------

/**
 * A line as lower-case words with the punctuation gone. Everything that reads speech matches whole words from
 * this: matching substrings heard "hey" in "they" and "Tom" in "tomorrow", and missed a bare "hi". say() has
 * html-escaped the line, so an apostrophe arrives as "&#39;", and it breaks words like any other mark.
 */
/proc/sp_words(message)
	var/list/words = list()
	if(!istext(message))
		return words
	// The double quote comes from ascii2text() because a literal one inside this list would need escaping.
	var/static/list/marks = list("&#39;", "&quot;", "&amp;", "&lt;", "&gt;", ".", ",", "!", "?", ";", ":", "'", "-", "(", ")", "*", "~", "/", ascii2text(34))
	var/lowered = LOWER_TEXT(message)
	for(var/mark in marks)
		lowered = replacetext(lowered, mark, " ")
	for(var/word in splittext(lowered, " "))
		if(length(word))
			words += word
	return words

/// Whether a phrase of one or more words appears, as whole words, in a line from sp_words().
/proc/sp_said(list/words, phrase)
	return findtext(" [jointext(words, " ")] ", " [phrase] ") != 0

/// Whether a line addresses someone by first name, as a whole word: "Tom" is not in "tomorrow".
/proc/sp_named(list/words, mob/who)
	if(QDELETED(who))
		return FALSE
	var/first = jointext(sp_words(sp_first_name(who)), " ")
	return length(first) >= 3 && sp_said(words, first)

/**
 * What somebody saying this to a crew member wants, as far as keywords can tell, or null when nothing in it
 * wants an answer. The first match wins, most specific first: "can you follow me" asks to be followed rather
 * than for help, and "hi, how are you" is asking after them more than greeting them.
 *
 * Reading changes nothing. Each line is read twice, once to decide whether to answer and once for the answer,
 * and standing used to move both times; sp_answer_for() moves it, once.
 */
/proc/sp_speech_intent(list/words)
	if(!length(words))
		return null
	for(var/phrase in list("idiot", "shut up", "stupid", "useless", "moron"))
		if(sp_said(words, phrase))
			return SP_INTENT_INSULT
	for(var/phrase in list("thank", "thanks", "thx", "cheers", "good job", "well done", "nice work", "appreciate", "appreciated"))
		if(sp_said(words, phrase))
			return SP_INTENT_THANKS
	for(var/phrase in list("follow me", "come with", "come along"))
		if(sp_said(words, phrase))
			return SP_INTENT_FOLLOW
	for(var/phrase in list("what do you do", "your job", "who are you"))
		if(sp_said(words, phrase))
			return SP_INTENT_WHO
	if("where" in words)
		for(var/about_them in list("you", "your", "work", "working"))
			if(about_them in words)
				return SP_INTENT_WHERE_WORK
		return SP_INTENT_WHERE
	for(var/phrase in list("help", "can you", "could you"))
		if(sp_said(words, phrase))
			return SP_INTENT_HELP
	for(var/phrase in list("how are you", "you alright", "you ok", "you okay", "how you doing", "how are things"))
		if(sp_said(words, phrase))
			return SP_INTENT_WELLBEING
	for(var/phrase in list("hello", "hi", "hey", "hiya", "heya", "howdy", "greetings", "good morning", "good afternoon", "good evening"))
		if(sp_said(words, phrase))
			return SP_INTENT_GREETING
	return null

/**
 * Whether we should be the one to answer a line that names nobody. A player's "hello" in a room of five crew
 * got five hellos back. Now the nearest crew member free to talk answers, a tie going to whichever sorts first,
 * and a line naming somebody else nearby is left to them. Listeners decide one after another, which is why
 * free_to_talk() still counts someone who has just taken up this same line.
 */
/proc/sp_first_to_answer(mob/living/carbon/human/listener, mob/living/speaker, list/words)
	var/our_dist = get_dist(listener, speaker)
	for(var/mob/living/carbon/human/other in get_hearers_in_view(7, speaker))
		if(other == listener || other == speaker)
			continue
		if(sp_named(words, other))
			return FALSE
		var/datum/ai_controller/sp_crew/their_ai = other.ai_controller
		if(!istype(their_ai) || !their_ai.free_to_talk(speaker))
			continue
		var/their_dist = get_dist(other, speaker)
		if(their_dist < our_dist || (their_dist == our_dist && sorttext(REF(other), REF(listener)) == 1))
			return FALSE
	return TRUE

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
 * What a crew member says back to someone, from what they said and how the crew member feels about them, or
 * null when nothing needs an answer. Called once for each line answered, as the answer is given, so this is
 * where what was said moves standing.
 */
/proc/sp_answer_for(datum/ai_controller/sp_crew/controller, mob/asker, message)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return null
	var/intent = sp_speech_intent(sp_words(message))
	if(isnull(intent))
		return null
	var/standing = sp_reputation(controller, asker)
	var/their_name = sp_first_name(asker)
	switch(intent)
		if(SP_INTENT_INSULT)
			sp_adjust_reputation(controller, asker, -3, "insulted us")
			return pick("Charming.", "There's no call for that.", "Right. Noted.")
		if(SP_INTENT_THANKS)
			sp_adjust_reputation(controller, asker, 2, "was polite")
			return pick("Any time.", "No trouble at all.", "Don't mention it, [their_name].")
		if(SP_INTENT_FOLLOW)
			// The standing system is what will eventually decide this properly.
			if(standing >= SP_REP_FRIENDLY)
				return "Alright, [their_name], lead on."
			return pick("I've got work to do.", "Maybe later, I'm in the middle of something.")
		if(SP_INTENT_WHO)
			var/job_title = pawn.mind?.assigned_role?.title || "crew"
			return "I'm [pawn.real_name], [job_title]."
		if(SP_INTENT_WHERE_WORK)
			var/area/here = get_area(pawn)
			return "I work out of [here ? here.name : "wherever they put me"]."
		if(SP_INTENT_WHERE)
			return pick("Couldn't tell you offhand.", "Try asking someone from that department.", "No idea, sorry.")
		if(SP_INTENT_HELP)
			if(standing <= SP_REP_HOSTILE)
				return pick("Ask someone else.", "I'm busy.")
			return pick("What do you need?", "If it's quick, sure.", "I can try.")
		if(SP_INTENT_WELLBEING)
			if(pawn.health < pawn.maxHealth * 0.7)
				return "Been better, honestly."
			return pick("Fine, thanks.", "Can't complain.", "Getting on with it.")
		if(SP_INTENT_GREETING)
			sp_adjust_reputation(controller, asker, 1, "said hello")
			if(standing >= SP_REP_FRIENDLY)
				return pick("Good to see you, [their_name].", "[their_name]! How are you?")
			return pick("Hello.", "Hey there.", "Afternoon.")
	return null
