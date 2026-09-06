/**
 * Base AI controller for Spacestation SP crew members (real /mob/living/carbon/human pawns).
 *
 * Phase 2 ("ambient crew"): stay alive, escape restraints, wander, and chatter.
 * Job-specific behaviour is added in subtypes / subtrees in later phases.
 */
/datum/ai_controller/sp_crew
	ai_movement = /datum/ai_movement/jps
	movement_delay = 0.4 SECONDS
	// Keep planning even when no player is nearby: a singleplayer station should feel alive everywhere.
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew.bt.json"
	blackboard = list(
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
	return ..()

/datum/ai_controller/sp_crew/UnpossessPawn(destroy)
	if(!isnull(pawn))
		UnregisterSignal(pawn, list(COMSIG_ATOM_WAS_ATTACKED, COMSIG_MOB_INCAPACITATE_CHANGED, COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	return ..()

/// Remember who hurt us. Later phases use this for fight/flee and for reporting to security.
/datum/ai_controller/sp_crew/proc/on_attacked(datum/source, atom/attacker)
	SIGNAL_HANDLER
	if(!isliving(attacker) || attacker == pawn)
		return
	add_blackboard_key_lazylist(BB_BASIC_MOB_RETALIATE_LIST, attacker)

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
