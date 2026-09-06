/**
 * Base AI controller for Spacestation SP crew members (real /mob/living/carbon/human pawns).
 *
 * Phase 3 ("ambient crew"): stay alive, escape restraints, go to medbay when hurt, answer people
 * who address us by name, wander our department, and chatter. Job subtypes add work behaviour.
 */
/datum/ai_controller/sp_crew
	ai_movement = /datum/ai_movement/jps
	movement_delay = 0.4 SECONDS
	// Keep planning even when no player is nearby: a singleplayer station should feel alive everywhere.
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew.bt.json"
	blackboard = list(
		BB_SP_HURT_THRESHOLD = 60,
		BB_BASIC_MOB_SPEAK_LINES = list(
			BB_SPEAK_CHANCE = 2,
			BB_EMOTE_SAY = list(
				"Another day, another shift.",
				"Has anyone seen the clown?",
				"I could use a coffee.",
				"Is the shuttle ever going to be on time?",
				"Did you hear that noise from maintenance?",
				"Nanotrasen doesn't pay me enough for this.",
			),
			BB_EMOTE_SEE = list(
				"yawns.",
				"stretches.",
				"looks around.",
			),
		),
	)

/datum/ai_controller/sp_crew/TryPossessPawn(atom/new_pawn)
	if(!ishuman(new_pawn))
		return AI_CONTROLLER_INCOMPATIBLE
	var/mob/living/carbon/human/human_pawn = new_pawn
	if(!HAS_TRAIT(human_pawn, TRAIT_RELAYING_ATTACKER))
		human_pawn.AddElement(/datum/element/relay_attackers)
	RegisterSignal(human_pawn, COMSIG_ATOM_WAS_ATTACKED, PROC_REF(on_attacked))
	RegisterSignal(human_pawn, COMSIG_MOVABLE_PRE_HEAR, PROC_REF(on_pre_hear))
	// Until a proper needs subtree exists, AI crew do not starve. Documented limitation.
	ADD_TRAIT(human_pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
	setup_job_blackboard(human_pawn)
	return ..()

/// Hook for subtypes to seed job-specific blackboard keys (wander areas, lines, ...).
/datum/ai_controller/sp_crew/proc/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	return

/datum/ai_controller/sp_crew/UnpossessPawn(destroy)
	if(!isnull(pawn))
		REMOVE_TRAIT(pawn, TRAIT_NOHUNGER, SP_CREW_TRAIT)
		UnregisterSignal(pawn, list(COMSIG_ATOM_WAS_ATTACKED, COMSIG_MOVABLE_PRE_HEAR, COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/// Remember who hurt us. Later phases use this for fight/flee and for reporting to security.
/datum/ai_controller/sp_crew/proc/on_attacked(datum/source, atom/attacker)
	SIGNAL_HANDLER
	if(!isliving(attacker) || attacker == pawn)
		return
	add_blackboard_key_lazylist(BB_BASIC_MOB_RETALIATE_LIST, attacker)

/**
 * Hearing. /mob/living/Hear() bails out early for client-less mobs, so we listen on the PRE_HEAR
 * signal which fires first. hearing_args is the Hear() argument list, indexed by the HEARING_* defines.
 */
/datum/ai_controller/sp_crew/proc/on_pre_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	var/raw_message = hearing_args[HEARING_RAW_MESSAGE]
	if(QDELETED(speaker) || speaker == pawn || !istext(raw_message) || !length(raw_message))
		return

	var/is_radio = !isnull(hearing_args[HEARING_RADIO_FREQ])
	var/list/entry = list(
		SP_HEARD_SPEAKER = WEAKREF(speaker),
		SP_HEARD_NAME = speaker.name,
		SP_HEARD_MESSAGE = raw_message,
		SP_HEARD_TIME = world.time,
		SP_HEARD_RADIO = is_radio,
	)
	add_blackboard_key_lazylist(BB_SP_HEARD, entry)
	var/list/heard = blackboard[BB_SP_HEARD]
	while(length(heard) > SP_HEARD_MAX)
		remove_from_blackboard_lazylist_key(BB_SP_HEARD, heard[1])
		heard = blackboard[BB_SP_HEARD]

	// Someone nearby said our first name: give them our attention (the social subtree answers).
	if(is_radio || !isliving(speaker))
		return
	var/mob/living/living_pawn = pawn
	var/list/name_parts = splittext(living_pawn.real_name, " ")
	var/first_name = length(name_parts) ? name_parts[1] : living_pawn.real_name
	if(length(first_name) < 3 || !findtext(raw_message, first_name))
		return
	var/greet_ready_at = blackboard[BB_SP_GREET_COOLDOWN]
	if(!isnull(greet_ready_at) && greet_ready_at > world.time)
		return
	set_blackboard_key(BB_SP_GREET_COOLDOWN, world.time + 10 SECONDS)
	set_blackboard_key(BB_SP_ATTENTION_TARGET, speaker)

// --- Able-to-run handling, mirrors /datum/ai_controller/basic_controller for a living pawn ---

/datum/ai_controller/sp_crew/on_stat_changed(mob/living/source, new_stat)
	. = ..()
	update_able_to_run()

/datum/ai_controller/sp_crew/setup_able_to_run()
	. = ..()
	RegisterSignal(pawn, COMSIG_MOB_INCAPACITATE_CHANGED, PROC_REF(update_able_to_run))
	RegisterSignals(pawn, list(COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED), PROC_REF(update_able_to_run))

/datum/ai_controller/sp_crew/clear_able_to_run()
	UnregisterSignal(pawn, list(COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/datum/ai_controller/sp_crew/get_able_to_run()
	. = ..()
	if(. & AI_UNABLE_TO_RUN)
		return .
	var/mob/living/living_pawn = pawn
	if(IS_UNCONSCIOUS_OR_CRIT(living_pawn))
		return AI_UNABLE_TO_RUN
	if(INCAPACITATED_IGNORING(living_pawn, INCAPABLE_GRAB))
		return AI_UNABLE_TO_RUN
	if(LAZYLEN(living_pawn.do_afters))
		return AI_UNABLE_TO_RUN | AI_PREVENT_CANCEL_ACTIONS
	return NONE

// --- Job controllers --------------------------------------------------------------------------

/// Medical staff: treat injured crew they can see, otherwise behave like base crew inside medical.
/datum/ai_controller/sp_crew/medical
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_medical.bt.json"

/datum/ai_controller/sp_crew/medical/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/medical_areas = list(
		/area/station/medical/medbay/central,
		/area/station/medical/medbay/lobby,
		/area/station/medical/medbay/aft,
		/area/station/medical/treatment_center,
		/area/station/medical/storage,
		/area/station/medical/exam_room,
		/area/station/medical/office,
		/area/station/medical/break_room,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, medical_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Anyone hurt? Come to medbay.",
			"Remember to take your pills.",
			"Please don't bleed on the floor.",
			"Where did I leave that health analyzer?",
		),
		BB_EMOTE_SEE = list("checks a clipboard.", "adjusts a pair of gloves."),
	))

/// Security: patrol the hallways and the brig instead of staying in one department.
/// Uses the base crew tree; only the wander areas and chatter differ.
/datum/ai_controller/sp_crew/security

/datum/ai_controller/sp_crew/security/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/patrol_areas
	if(isnull(patrol_areas))
		patrol_areas = typesof(/area/station/hallway) + typesof(/area/station/security)
	set_blackboard_key(BB_SP_WANDER_AREAS, patrol_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Nothing to see here, move along.",
			"Keep it civil, people.",
			"Anyone seen anything suspicious?",
			"Another quiet patrol. Too quiet.",
		),
		BB_EMOTE_SEE = list("scans the area.", "rests a hand on a baton."),
	))
