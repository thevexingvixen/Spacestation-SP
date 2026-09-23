// Conversation behaviour: answering people, starting conversations, and the odd remark to the station.

/**
 * Answering somebody, and carrying on a conversation already under way, are urgent and short, so they live in
 * the emergency ladder: ignoring a person who just spoke to you reads worse than almost anything else a crew
 * member can do. Work that turns up still ends a conversation (sp_dialogue_still_talking()).
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
 * Says the one-line answer to something a person said, when nothing they said opens a written conversation
 * (consider_conversation()). The answer is spent whatever happens, and one not given within SP_REPLY_STALE is
 * not given at all.
 */
/datum/bt_node/ai_behavior/sp_say_reply

/datum/bt_node/ai_behavior/sp_say_reply/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/asker = controller.blackboard[BB_SP_CHAT_REPLY_DUE]
	var/heard = controller.blackboard[BB_SP_CHAT_HEARD]
	var/asked_at = controller.blackboard[BB_SP_CHAT_ASKED_AT]
	controller.clear_blackboard_key(BB_SP_CHAT_REPLY_DUE)
	controller.clear_blackboard_key(BB_SP_CHAT_HEARD)
	controller.clear_blackboard_key(BB_SP_CHAT_ASKED_AT)
	if(!istype(pawn) || QDELETED(asker) || (!isnull(asked_at) && world.time - asked_at > SP_REPLY_STALE))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/line = sp_answer_for(controller, asker, heard)
	if(isnull(line))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(asker)
	sp_crew_speak(pawn, replacetext(line, "%TARGET%", sp_first_name(asker)))
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Conversations ------------------------------------------------------------------------------

/**
 * Picks a nearby crew member and a written dialogue the two of them can have (sp_dialogue.dm). The thread
 * then runs from the respond subtree, which is also where a conversation a player started runs from.
 */
/datum/bt_node/ai_behavior/sp_start_chat
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_start_chat/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || controller.blackboard_key_exists(BB_SP_THREAD) || controller.blackboard_key_exists(BB_SP_IN_THREAD))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/carbon/human/partner = sp_find_chat_partner(pawn)
	if(isnull(partner))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(isnull(sp_start_thread(controller, sp_pick_dialogue(pawn, partner), pawn, partner)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Plays a thread a line at a time: both sides of a crew conversation, or the crew member's side of one with a
 * player, waiting on the player's reply when it is their turn and taking silence as an answer when it lapses.
 * Fails when there is no thread, so the answering branch behind it runs instead.
 */
/datum/bt_node/ai_behavior/sp_run_dialogue

/datum/bt_node/ai_behavior/sp_run_dialogue/perform(seconds_per_tick, datum/ai_controller/controller)
	var/datum/sp_dialogue_thread/thread = controller.blackboard[BB_SP_THREAD]
	if(isnull(thread))
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_FAILED
	if(length(thread.pending_options))
		if(world.time <= thread.options_expire && sp_dialogue_still_talking(thread))
			return AI_BEHAVIOR_DELAY // their turn: waiting on a click
		thread.expire()
	if(world.time < thread.next_due)
		return AI_BEHAVIOR_DELAY
	if(thread.advance())
		return AI_BEHAVIOR_DELAY
	var/said = thread.lines_said
	sp_end_dialogue(controller, thread)
	return AI_BEHAVIOR_DELAY | (said ? AI_BEHAVIOR_SUCCEEDED : AI_BEHAVIOR_FAILED)

// --- Noticing people --------------------------------------------------------------------------

/**
 * Greets a player who has come near, once each, so the station acknowledges you. Somebody they have not met
 * gets a proper introduction where one is written; anybody else a line. It sits outside the chat cooldown in
 * the tree: sharing that with failed partner searches held a newcomer's hello back by up to 90 s.
 */
/datum/bt_node/ai_behavior/sp_greet_newcomer
	time_between_perform = 4 SECONDS

/datum/bt_node/ai_behavior/sp_greet_newcomer/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || controller.blackboard_key_exists(BB_SP_THREAD) || controller.blackboard_key_exists(BB_SP_IN_THREAD))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/greeted = controller.blackboard[BB_SP_GREETED]
	for(var/mob/living/carbon/human/nearby in oview(4, pawn))
		if(isnull(nearby.client) || nearby.stat != STABLE)
			continue // only players get a hello; crew talk to each other through threads
		if(LAZYACCESS(greeted, nearby))
			continue
		if(!can_see(pawn, nearby, 4))
			continue
		controller.set_blackboard_key_assoc_lazylist(BB_SP_GREETED, nearby, TRUE)
		pawn.face_atom(nearby)
		if(!isnull(sp_start_thread(controller, sp_pick_dialogue(pawn, nearby, "newcomer"), pawn, nearby)))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
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
