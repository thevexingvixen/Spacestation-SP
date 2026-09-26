/**
 * Conversation and standing.
 *
 * What a crew member makes of what somebody says to them, and how they feel about that person. Players get
 * keyword answers to the things they predictably say -- a greeting, "what do you do", "where is x", asking for
 * help, thanks, or abuse -- read in whole words (sp_words()), and a line that opens a written conversation
 * starts one instead (sp_dialogue.dm). Every exchange nudges how the crew member feels about that person,
 * which colours their answers, and at the extremes shows on examine.
 *
 * The seven keyword topics crew once talked about among themselves are dialogue files now, under
 * strings/spacestation_sp/dialogue, with the rest of the written conversations.
 */

/// First name only; crew address each other casually.
/proc/sp_first_name(mob/who)
	if(QDELETED(who))
		return "you"
	var/list/parts = splittext(who.real_name, " ")
	return length(parts) ? parts[1] : who.real_name

/**
 * What a crew member calls somebody to their face: their first name if they know it, whatever they call a stranger
 * if they do not (sp_dialogue_stranger()), and a thing by its name.
 */
/proc/sp_what_we_call(datum/ai_controller/controller, atom/target)
	if(!isliving(target))
		return target?.name
	var/datum/ai_controller/sp_crew/crew_ai = controller
	if(istype(crew_ai) && !sp_knows_name(crew_ai, target))
		return sp_dialogue_stranger(crew_ai.pawn)
	return sp_first_name(target)

/// Another AI crew member nearby who is free to talk.
/proc/sp_find_chat_partner(mob/living/carbon/human/speaker, range = 5)
	for(var/mob/living/carbon/human/candidate in oview(range, speaker))
		var/datum/ai_controller/sp_crew/their_ai = candidate.ai_controller
		if(!istype(their_ai) || !their_ai.free_to_talk(speaker))
			continue
		// Don't interrupt someone already mid-conversation or dealing with something, or take somebody away from a
		// player they have just been talking to. A mime has nothing to say back.
		if(their_ai.blackboard_key_exists(BB_SP_CHAT_PARTNER) || their_ai.blackboard_key_exists(BB_SP_ATTACKER))
			continue
		if(their_ai.engaged_with_player() || !candidate.can_speak())
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

/// Whether a line is somebody giving their own name: "I'm Tom", "my name is Tom", "call me Tom".
/proc/sp_introduces_self(list/words, mob/living/speaker)
	var/first = jointext(sp_words(sp_first_name(speaker)), " ")
	if(length(first) < 2 || !sp_said(words, first))
		return FALSE
	for(var/phrase in list("i m", "i am", "my name", "name s", "call me", "this is"))
		if(sp_said(words, phrase))
			return TRUE
	return FALSE

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
	for(var/phrase in list("the door", "this door", "that door", "let me in", "let me through", "open up"))
		if(sp_said(words, phrase))
			return SP_INTENT_DOOR
	for(var/phrase in list("a doctor", "the doctor", "a medic", "call medbay", "need medbay", "i m hurt", "i am hurt", "i m bleeding"))
		if(sp_said(words, phrase))
			return SP_INTENT_DOCTOR
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
	// Only a name they know. A second round of favours had a passer-by thank the stand-in by a name nobody had told them.
	var/their_name = sp_knows_name(controller, asker) ? sp_first_name(asker) : sp_dialogue_stranger(pawn)
	switch(intent)
		if(SP_INTENT_INSULT)
			sp_adjust_reputation(controller, asker, -3, "insulted us")
			return pick("Charming.", "There's no call for that.", "Right. Noted.")
		if(SP_INTENT_THANKS)
			sp_adjust_reputation(controller, asker, 2, "was polite")
			return pick("Any time.", "No trouble at all.", "Don't mention it, [their_name].")
		// Asking for a favour is a written conversation (ask_follow, ask_door, ask_doctor), which decides who says
		// yes and does it. One lands here only when that conversation cannot be had: nothing to open, no medic about,
		// a favour already in hand.
		if(SP_INTENT_FOLLOW)
			return pick("Not just now, [their_name].", "I'm in the middle of something.")
		if(SP_INTENT_DOOR)
			return pick("Not one I can help you with.", "Can't help you there, sorry.")
		if(SP_INTENT_DOCTOR)
			if(sp_dialogue_hurt(asker))
				return pick("Get yourself to medbay, [their_name].", "Medbay. Now. Go.")
			return pick("You look fine to me.", "Medbay's that way, if you're worried.")
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
