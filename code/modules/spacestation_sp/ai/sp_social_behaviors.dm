// Conversation behaviour: answering people, striking up exchanges, and the odd remark to the station.

/**
 * Answering somebody is urgent and short, so it lives in the emergency ladder: ignoring a person who
 * just spoke to you reads worse than almost anything else a crew member can do.
 */
/datum/bt_node/subtree/sp_crew_respond
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_respond.bt.json"

/**
 * Starting a conversation, greeting a newcomer and remarking to the station are idle-time behaviour.
 * They sit below the job work: a technician hauling a crate across the station should finish the job
 * before stopping for small talk.
 */
/datum/bt_node/subtree/sp_crew_chatter
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_chatter.bt.json"

// --- Answering --------------------------------------------------------------------------------

/// True when somebody has said something to us that deserves an answer.
/datum/bt_node/decorator/sp_owes_reply

/datum/bt_node/decorator/sp_owes_reply/check_condition(datum/ai_controller/controller)
	return controller.blackboard_key_exists(BB_SP_CHAT_REPLY_DUE)

/**
 * Says the answer: the topic's reply line to another crew member's opener, and whatever `sp_answer_for` makes
 * of anything else.
 *
 * The answer is spent whatever happens, topic and all: a topic left behind used to answer the next person to
 * speak to us, players included. A reply is also the end of our part. The opener has the last word
 * (sp_say_closer), where replying used to hand the replier a closing remark of their own.
 */
/datum/bt_node/ai_behavior/sp_say_reply

/datum/bt_node/ai_behavior/sp_say_reply/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/asker = controller.blackboard[BB_SP_CHAT_REPLY_DUE]
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_REPLY_TOPIC]
	var/heard = controller.blackboard[BB_SP_CHAT_HEARD]
	var/asked_at = controller.blackboard[BB_SP_CHAT_ASKED_AT]
	controller.clear_blackboard_key(BB_SP_CHAT_REPLY_DUE)
	controller.clear_blackboard_key(BB_SP_CHAT_REPLY_TOPIC)
	controller.clear_blackboard_key(BB_SP_CHAT_HEARD)
	controller.clear_blackboard_key(BB_SP_CHAT_ASKED_AT)
	if(!istype(pawn) || QDELETED(asker) || (!isnull(asked_at) && world.time - asked_at > SP_REPLY_STALE))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/line
	if(isnull(topic))
		line = sp_answer_for(controller, asker, heard)
	else if(length(topic.replies))
		line = pick(topic.replies)
		// Tell the opener they were answered, so a closing remark follows something.
		var/datum/ai_controller/sp_crew/their_ai = asker.ai_controller
		if(istype(their_ai) && their_ai.blackboard[BB_SP_CHAT_PARTNER] == pawn && their_ai.blackboard[BB_SP_CHAT_STAGE] == SP_CHAT_OPENER_HEARD)
			their_ai.set_blackboard_key(BB_SP_CHAT_STAGE, SP_CHAT_ANSWERED)
	if(isnull(line))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(asker)
	sp_crew_speak(pawn, replacetext(line, "%TARGET%", sp_first_name(asker)))
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Starting a conversation --------------------------------------------------------------------

/**
 * Picks a nearby crew member and something to say to them.
 *
 * A chat then moves through the SP_CHAT_* stages, each set before the line it belongs to is said: speech goes
 * out through INVOKE_ASYNC, so a listener may hear a line before its speaker's next statement runs, or after.
 */
/datum/bt_node/ai_behavior/sp_start_chat
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_start_chat/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/carbon/human/partner = sp_find_chat_partner(pawn)
	if(isnull(partner))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// A written dialogue if these two have one going spare (sp_dialogue.dm), the old topic exchange if not.
	var/datum/sp_dialogue/dialogue = sp_pick_dialogue(pawn, partner)
	var/datum/sp_dialogue_thread/thread = isnull(dialogue) ? null : sp_begin_dialogue(dialogue, pawn, partner)
	if(!isnull(thread))
		controller.set_blackboard_key(BB_SP_THREAD, thread)
		controller.set_blackboard_key(BB_SP_CHAT_PARTNER, partner)
		controller.set_blackboard_key(BB_SP_CHAT_STAGE, SP_CHAT_PICKED)
		sp_record("talk.thread")
		log_sp("[pawn.real_name] started [dialogue.id] with [partner.real_name]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	var/datum/sp_topic/topic = sp_pick_topic(pawn)
	if(isnull(topic) || !length(topic.openers))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CHAT_PARTNER, partner)
	controller.set_blackboard_key(BB_SP_CHAT_TOPIC, topic)
	controller.set_blackboard_key(BB_SP_CHAT_STAGE, SP_CHAT_PICKED)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Says the opening line. The other crew member's hearing hook does the rest (consider_conversation()).
/datum/bt_node/ai_behavior/sp_say_opener

/datum/bt_node/ai_behavior/sp_say_opener/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/partner = controller.blackboard[BB_SP_CHAT_PARTNER]
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_TOPIC]
	if(!istype(pawn) || QDELETED(partner) || isnull(topic))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(partner)
	controller.set_blackboard_key(BB_SP_CHAT_STAGE, SP_CHAT_OPENED)
	sp_crew_speak(pawn, replacetext(pick(topic.openers), "%TARGET%", sp_first_name(partner)))
	log_sp("[pawn.real_name] started a conversation with [partner.real_name] about [topic.id]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * The last word, if the partner answered and the topic has one; then the conversation is over.
 *
 * The chat is forgotten before anything is said. A closer spoken with partner and topic still set once passed
 * for a fresh opener, and two crew could go on closing at each other for as long as the dice allowed.
 */
/datum/bt_node/ai_behavior/sp_say_closer
	/// Percent chance of a closing remark once the opener has been answered.
	var/closer_chance = 60

/datum/bt_node/ai_behavior/sp_say_closer/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/partner = controller.blackboard[BB_SP_CHAT_PARTNER]
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_TOPIC]
	var/answered = controller.blackboard[BB_SP_CHAT_STAGE] == SP_CHAT_ANSWERED
	controller.clear_blackboard_key(BB_SP_CHAT_PARTNER)
	controller.clear_blackboard_key(BB_SP_CHAT_TOPIC)
	controller.clear_blackboard_key(BB_SP_CHAT_STAGE)
	if(answered && istype(pawn) && !QDELETED(partner) && length(topic?.closers) && prob(closer_chance))
		pawn.face_atom(partner)
		sp_crew_speak(pawn, replacetext(pick(topic.closers), "%TARGET%", sp_first_name(partner)))
		// Talking to someone is how strangers stop being strangers.
		sp_adjust_reputation(controller, partner, 1, "had a conversation")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Noticing people --------------------------------------------------------------------------

/// Greets a player who has come near, once each, so the station acknowledges you. It sits outside the chat
/// cooldown in the tree: sharing that with failed partner searches held a newcomer's hello back by up to 90 s.
/datum/bt_node/ai_behavior/sp_greet_newcomer
	time_between_perform = 4 SECONDS

/datum/bt_node/ai_behavior/sp_greet_newcomer/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/greeted = controller.blackboard[BB_SP_GREETED]
	for(var/mob/living/carbon/human/nearby in oview(4, pawn))
		if(isnull(nearby.client) || nearby.stat != STABLE)
			continue // only players get a hello; crew talk to each other through the topic system
		if(LAZYACCESS(greeted, nearby))
			continue
		if(!can_see(pawn, nearby, 4))
			continue
		controller.set_blackboard_key_assoc_lazylist(BB_SP_GREETED, nearby, TRUE)
		pawn.face_atom(nearby)
		var/job_title = pawn.mind?.assigned_role?.title
		sp_crew_speak(pawn, pick(
			"Afternoon.",
			"Hello there.",
			"Didn't see you come in.",
			"[job_title ? "[job_title]" : "Crew"], if you need anything.",
		))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// An occasional remark to the whole station over common.
/datum/bt_node/ai_behavior/sp_station_yap

/datum/bt_node/ai_behavior/sp_station_yap/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/area/here = get_area(pawn)
	var/job_title = pawn.mind?.assigned_role?.title || "crew"
	sp_crew_speak(pawn, pick(
		"Anyone else's radio crackling, or is it just mine?",
		"[job_title] here, all quiet in [here ? here.name : "my department"].",
		"If someone's taken the spare toolbox, I'd like it back.",
		"Reminder that the kitchen exists and I am hungry.",
		"Whoever keeps leaving doors open, please stop.",
		"Does anyone actually read these announcements?",
	), RADIO_CHANNEL_COMMON)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Written dialogue --------------------------------------------------------------------------

/**
 * Plays a written dialogue, a line at a time.
 *
 * The thread speaks for both sides, so it runs on whoever started it: one line per turn, with the gap the
 * file asked for in between. It ends when the graph runs out, when the pair drift apart, or when a file
 * that loops reaches SP_DIALOGUE_MAX_LINES. Failing when there is no thread is what lets the old topic
 * exchange sit behind this one in the tree.
 */
/datum/bt_node/ai_behavior/sp_run_dialogue

/datum/bt_node/ai_behavior/sp_run_dialogue/perform(seconds_per_tick, datum/ai_controller/controller)
	var/datum/sp_dialogue_thread/thread = controller.blackboard[BB_SP_THREAD]
	if(isnull(thread))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(world.time < thread.next_due)
		return AI_BEHAVIOR_DELAY // mid-conversation, and the next line is not due yet
	if(thread.advance())
		return AI_BEHAVIOR_DELAY
	var/said = thread.lines_said
	var/id = thread.dialogue?.id
	sp_dialogue_remember(thread)
	controller.clear_blackboard_key(BB_SP_THREAD)
	controller.clear_blackboard_key(BB_SP_CHAT_PARTNER)
	controller.clear_blackboard_key(BB_SP_CHAT_TOPIC)
	controller.clear_blackboard_key(BB_SP_CHAT_STAGE)
	qdel(thread)
	sp_record(said ? "talk.finished" : "talk.abandoned")
	log_sp("[controller.pawn] came to the end of [id] after [said] lines")
	return AI_BEHAVIOR_DELAY | (said ? AI_BEHAVIOR_SUCCEEDED : AI_BEHAVIOR_FAILED)

