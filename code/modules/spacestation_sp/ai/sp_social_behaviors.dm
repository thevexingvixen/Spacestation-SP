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
 * Says the answer. For another crew member that is the topic's reply line; for anyone else it is
 * whatever `sp_answer_for` makes of what they said.
 */
/datum/bt_node/ai_behavior/sp_say_reply

/datum/bt_node/ai_behavior/sp_say_reply/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/asker = controller.blackboard[BB_SP_CHAT_REPLY_DUE]
	if(!istype(pawn) || QDELETED(asker))
		controller.clear_blackboard_key(BB_SP_CHAT_REPLY_DUE)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	pawn.face_atom(asker)
	var/line
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_TOPIC]
	if(!isnull(topic) && length(topic.replies))
		line = pick(topic.replies)
	else
		line = sp_answer_for(controller, asker, controller.blackboard[BB_SP_CHAT_HEARD])

	controller.clear_blackboard_key(BB_SP_CHAT_REPLY_DUE)
	controller.clear_blackboard_key(BB_SP_CHAT_HEARD)
	if(isnull(line))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	line = replacetext(line, "%TARGET%", sp_first_name(asker))
	sp_crew_speak(pawn, line)
	// Whoever opened gets to have the last word.
	if(!isnull(topic))
		controller.set_blackboard_key(BB_SP_CHAT_PARTNER, asker)
		controller.set_blackboard_key(BB_SP_CHAT_STAGE, 1)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Starting a conversation --------------------------------------------------------------------

/// Picks a nearby crew member and something to say to them.
/datum/bt_node/ai_behavior/sp_start_chat
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_start_chat/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/carbon/human/partner = sp_find_chat_partner(pawn)
	if(isnull(partner))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/datum/sp_topic/topic = sp_pick_topic(pawn)
	if(isnull(topic) || !length(topic.openers))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_CHAT_PARTNER, partner)
	controller.set_blackboard_key(BB_SP_CHAT_TOPIC, topic)
	controller.set_blackboard_key(BB_SP_CHAT_STAGE, 0)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Says the opening line. The other crew member's hearing hook does the rest.
/datum/bt_node/ai_behavior/sp_say_opener

/datum/bt_node/ai_behavior/sp_say_opener/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/partner = controller.blackboard[BB_SP_CHAT_PARTNER]
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_TOPIC]
	if(!istype(pawn) || QDELETED(partner) || isnull(topic))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(partner)
	var/line = replacetext(pick(topic.openers), "%TARGET%", sp_first_name(partner))
	sp_crew_speak(pawn, line)
	controller.set_blackboard_key(BB_SP_CHAT_STAGE, 1)
	log_sp("[pawn.real_name] started a conversation with [partner.real_name] about [topic.id]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// The last word, if the topic has one, then the conversation is over for both of us.
/datum/bt_node/ai_behavior/sp_say_closer

/datum/bt_node/ai_behavior/sp_say_closer/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/partner = controller.blackboard[BB_SP_CHAT_PARTNER]
	var/datum/sp_topic/topic = controller.blackboard[BB_SP_CHAT_TOPIC]
	if(istype(pawn) && !QDELETED(partner) && !isnull(topic) && length(topic.closers) && prob(60))
		pawn.face_atom(partner)
		sp_crew_speak(pawn, replacetext(pick(topic.closers), "%TARGET%", sp_first_name(partner)))
		// Talking to someone is how strangers stop being strangers.
		sp_adjust_reputation(controller, partner, 1, "had a conversation")
	controller.clear_blackboard_key(BB_SP_CHAT_PARTNER)
	controller.clear_blackboard_key(BB_SP_CHAT_TOPIC)
	controller.clear_blackboard_key(BB_SP_CHAT_STAGE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Noticing people --------------------------------------------------------------------------

/// Greets a player who has come near, once each, so the station acknowledges you.
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
