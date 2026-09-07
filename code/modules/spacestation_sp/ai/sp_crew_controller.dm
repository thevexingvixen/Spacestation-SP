/**
 * Base AI controller for Spacestation SP crew members (real /mob/living/carbon/human pawns).
 *
 * Ambient crew: stay alive, escape restraints, react to attackers (report + flee), go to medbay
 * when hurt, keep away from armed people, answer people who address us by name, wander our
 * department, and chatter. Job subtypes add work behaviour (medical, security, engineering).
 */
/datum/ai_controller/sp_crew
	ai_movement = /datum/ai_movement/jps
	movement_delay = 0.4 SECONDS
	// Keep planning even when no player is nearby: a singleplayer station should feel alive everywhere.
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew.bt.json"
	blackboard = list(
		BB_SP_HURT_THRESHOLD = 60,
		BB_SP_THREAT_MIN_DISTANCE = 4,
		BB_SP_THREAT_MAX_DISTANCE = 7,
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

/// Someone hurt us: remember them so the defense subtree can report and flee (or, for security, fight back).
/datum/ai_controller/sp_crew/proc/on_attacked(datum/source, atom/attacker)
	SIGNAL_HANDLER
	if(!isliving(attacker) || attacker == pawn)
		return
	add_blackboard_key_lazylist(BB_BASIC_MOB_RETALIATE_LIST, attacker)
	set_blackboard_key(BB_SP_ATTACKER, attacker)
	set_blackboard_key(BB_SP_ATTACKED_AT, world.time)

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

	// Radio speakers arrive wrapped in a virtualspeaker; unwrap to the real mob where we can.
	var/atom/movable/real_speaker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/virtual = speaker
		real_speaker = virtual.source || speaker

	// Another AI crew member reporting an incident? They store the structured version for us.
	if(ishuman(real_speaker))
		var/mob/living/carbon/human/human_speaker = real_speaker
		var/datum/ai_controller/sp_crew/other = human_speaker.ai_controller
		if(istype(other))
			var/list/incident = other.blackboard[BB_SP_LAST_INCIDENT]
			if(length(incident) && world.time - incident[SP_INCIDENT_TIME] < 5 SECONDS)
				on_heard_incident(human_speaker, incident)
				return
	// A player (or anyone without our structured report) calling for help.
	if(isliving(real_speaker) && sp_message_is_distress(raw_message))
		on_heard_distress(real_speaker, raw_message, is_radio)

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

/// Another crew member reported an attack within earshot (or on a channel we hear). Base crew ignore it.
/datum/ai_controller/sp_crew/proc/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	return

/// Someone (usually the player) shouted words that sound like a call for help. Base crew ignore it.
/datum/ai_controller/sp_crew/proc/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	return

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

/// Security: patrol hallways and the brig, respond to reports, subdue and cuff attackers.
/datum/ai_controller/sp_crew/security
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_security.bt.json"

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

/// Security fights back instead of fleeing: whoever hits us becomes the suspect.
/datum/ai_controller/sp_crew/security/on_attacked(datum/source, atom/attacker)
	. = ..()
	if(!isliving(attacker) || attacker == pawn)
		return
	set_blackboard_key(BB_SP_INCIDENT_TARGET, attacker)
	set_blackboard_key(BB_SP_INCIDENT_LOCATION, get_turf(attacker))

/datum/ai_controller/sp_crew/security/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	if(reporter == pawn)
		return
	var/datum/weakref/attacker_ref = incident[SP_INCIDENT_ATTACKER]
	var/mob/living/attacker = attacker_ref?.resolve()
	var/turf/where = incident[SP_INCIDENT_TURF]
	if(!isnull(attacker) && attacker != pawn)
		set_blackboard_key(BB_SP_INCIDENT_TARGET, attacker)
	if(!isnull(where))
		set_blackboard_key(BB_SP_INCIDENT_LOCATION, where)
	acknowledge_report()

/datum/ai_controller/sp_crew/security/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	if(speaker == pawn || blackboard_key_exists(BB_SP_INCIDENT_TARGET))
		return
	var/turf/where = get_turf(speaker)
	if(isnull(where))
		return
	set_blackboard_key(BB_SP_INCIDENT_LOCATION, where)
	acknowledge_report()

/// Says "on my way" over the security channel, at most once every 20 seconds.
/datum/ai_controller/sp_crew/security/proc/acknowledge_report()
	var/ready_at = blackboard[BB_SP_ACK_COOLDOWN]
	if(!isnull(ready_at) && ready_at > world.time)
		return
	set_blackboard_key(BB_SP_ACK_COOLDOWN, world.time + 20 SECONDS)
	var/area/target_area = get_area(blackboard[BB_SP_INCIDENT_LOCATION])
	sp_crew_speak(pawn, "Copy, responding[target_area ? " to [target_area.name]" : ""].", RADIO_CHANNEL_SECURITY)

/// Engineering: keep the engine running and the SMES charged; otherwise wander engineering.
/datum/ai_controller/sp_crew/engineer
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_engineer.bt.json"

/datum/ai_controller/sp_crew/engineer/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	var/static/list/engineering_areas = list(
		/area/station/engineering/main,
		/area/station/engineering/engine_smes,
		/area/station/engineering/hallway,
		/area/station/engineering/storage,
		/area/station/engineering/storage_shared,
		/area/station/engineering/break_room,
		/area/station/engineering/lobby,
		/area/station/engineering/supermatter/room,
		/area/station/engineering/atmos,
	)
	set_blackboard_key(BB_SP_WANDER_AREAS, engineering_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Who left this wire exposed?",
			"The engine sounds fine. I think.",
			"If the lights flicker, that's normal. Probably.",
			"Has anyone seen my welding fuel?",
		),
		BB_EMOTE_SEE = list("checks a gauge.", "taps a wrench against a pipe."),
	))
