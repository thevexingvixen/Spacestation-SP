/**
 * The officer's side of searches and evidence (sp_search.dm): the pat-down after an arrest, and filing what it found.
 */

/// Carrying evidence: take it to the closet, or to somebody who can open it.
/datum/bt_node/subtree/sp_security_evidence
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_security_evidence.bt.json"

/**
 * Patting down somebody just cuffed, before the walk to the cell. Always succeeds -- there being nothing to take is
 * no reason to leave them on the floor -- and once per arrest (BB_SP_SEARCHED).
 */
/datum/bt_node/ai_behavior/sp_search_prisoner
	/// Held across the async half.
	VAR_PRIVATE/mob/living/carbon/human/reach

/datum/bt_node/ai_behavior/sp_search_prisoner/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_PRISONER] || controller.blackboard[BB_SP_INCIDENT_TARGET]
	if(!istype(pawn) || !istype(reach) || reach.stat == DEAD || !reach.Adjacent(pawn) || controller.blackboard[BB_SP_SEARCHED] == reach)
		return AI_BEHAVIOR_INSTANT | AI_BEHAVIOR_SUCCEEDED
	controller.set_blackboard_key(BB_SP_SEARCHED, reach)
	return start_async()

/datum/bt_node/ai_behavior/sp_search_prisoner/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/carbon/human/prisoner = reach
	sp_hold_still(prisoner, pawn, 30 SECONDS)
	sp_crew_speak(pawn, pick("Pockets out.", "Hold still. Let's see what you've got on you.", "Arms up."))
	sp_search_person(controller, prisoner, controller.blackboard[BB_SP_SUSPECT_ITEM])
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_search_prisoner/finish_action(datum/ai_controller/controller, succeeded)
	reach = null
	return ..()

/**
 * Where the evidence we carry goes (sp_evidence_home()). Fails when there is nowhere at all, which leaves it in our
 * bag, and counts the walks that came to nothing so a keeper who cannot be reached is given up on for a locker.
 */
/datum/bt_node/ai_behavior/sp_find_evidence_home

/datum/bt_node/ai_behavior/sp_find_evidence_home/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/ai_controller/sp_crew/crew = controller
	if(!istype(pawn) || !istype(crew))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/carried = sp_evidence_carried(crew)
	if(!length(carried))
		sp_forget_evidence(crew)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/home = sp_evidence_home(crew)
	if(isnull(home))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_EVIDENCE_HOME] == home)
		// Back here with the same place in mind means the last walk did not end in filing.
		controller.set_blackboard_key(BB_SP_EVIDENCE_TRIES, (controller.blackboard[BB_SP_EVIDENCE_TRIES] || 0) + 1)
	else
		log_sp("[pawn.real_name] set off to file [sp_item_names(carried)] with [home] in [get_area_name(home)]")
	controller.set_blackboard_key(BB_SP_EVIDENCE_HOME, home)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Lets go of the evidence keys: it is filed, handed on, or no longer on us.
/proc/sp_forget_evidence(datum/ai_controller/sp_crew/controller)
	controller?.clear_blackboard_key(BB_SP_EVIDENCE)
	controller?.clear_blackboard_key(BB_SP_EVIDENCE_HOME)
	controller?.clear_blackboard_key(BB_SP_EVIDENCE_TRIES)

/**
 * Filing it: into the closet, which is locked again behind it, or into the keeper's hands, who then has it to file.
 * Async, because the clicks wait out their cooldowns.
 */
/datum/bt_node/ai_behavior/sp_file_evidence
	/// Held across the async half.
	VAR_PRIVATE/atom/reach

/datum/bt_node/ai_behavior/sp_file_evidence/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_EVIDENCE_HOME]
	if(!istype(pawn) || QDELETED(reach) || !reach.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_file_evidence/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/ai_controller/sp_crew/crew = controller
	var/list/evidence = sp_evidence_carried(crew)
	if(!length(evidence))
		sp_forget_evidence(crew)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/names = sp_item_names(evidence)
	if(ismob(reach))
		var/mob/living/carbon/human/keeper = reach
		var/datum/ai_controller/sp_crew/keeper_ai = keeper.ai_controller
		var/list/given = list()
		for(var/obj/item/thing as anything in evidence)
			if(sp_take_from_person(keeper, pawn, thing))
				given += thing
		if(!length(given))
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return
		if(istype(keeper_ai))
			sp_hold_evidence(keeper_ai, given)
		sp_record("sec.evidence_handed", length(given))
		log_sp("[pawn.real_name] handed [sp_item_names(given)] to [keeper.real_name] for evidence")
		sp_crew_speak(pawn, "[sp_first_name(keeper)], [sp_item_names(given)] for evidence.")
		sp_crew_speak(keeper, pick("I'll see to it.", "Leave it with me.", "Into the locker it goes."))
		sp_forget_evidence(crew)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)
		return
	var/obj/structure/closet/locker = reach
	if(!istype(locker))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_free_hands(pawn)
	if(locker.locked && locker.allowed(pawn))
		sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
	if(!async_still_valid() || QDELETED(locker))
		return
	if(!locker.opened)
		sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(locker))
		return
	if(!locker.opened)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	// An open closet holds nothing: everything on its tile is swept in as it shuts.
	var/turf/spot = get_turf(locker)
	var/filed = 0
	for(var/obj/item/thing as anything in evidence)
		if(thing.loc == pawn && !pawn.temporarilyRemoveItemFromInventory(thing, force = TRUE))
			continue
		if(thing.forceMove(spot))
			filed++
	sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(locker))
		return
	if(!locker.opened && !locker.locked && locker.allowed(pawn))
		sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
	if(!async_still_valid())
		return
	sp_record("sec.evidence_filed", filed)
	log_sp("[pawn.real_name] filed [names] in [locker.name] in [get_area_name(locker)][locker.locked ? ", locked" : ""]")
	sp_crew_speak(pawn, "[capitalize(names)] logged into evidence.", RADIO_CHANNEL_SECURITY)
	sp_forget_evidence(crew)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_file_evidence/finish_action(datum/ai_controller/controller, succeeded)
	reach = null
	return ..()
