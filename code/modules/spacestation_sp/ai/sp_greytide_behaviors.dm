// Behaviour-tree leaves and subtrees for the assistants' greytide. The helpers are in sp_greytide.dm.

/// Assistant: a trip to tool storage for gloves and a tool, early in the shift.
/datum/bt_node/subtree/sp_greytide_gear_up
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_greytide_gear_up.bt.json"

/// Assistant: a little harmless mischief every few minutes.
/datum/bt_node/subtree/sp_greytide_mischief
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_greytide_mischief.bt.json"

/// Assistant: rummaging twice as often as the rest of the crew, and leaving the lockers open.
/datum/bt_node/subtree/sp_greytide_rummage
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_greytide_rummage.bt.json"

/// Assistant: trying doors twice as often as the rest of the crew.
/datum/bt_node/subtree/sp_greytide_try_door
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_greytide_try_door.bt.json"

// --- Tool storage ----------------------------------------------------------------------------------

/// Passes while an assistant still wants something from tool storage and has not given up on it.
/datum/bt_node/decorator/sp_wants_gear

/datum/bt_node/decorator/sp_wants_gear/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || controller.blackboard[BB_SP_GEARED_UP])
		return FALSE
	return (controller.blackboard[BB_SP_GEAR_TRIPS] || 0) < SP_GEAR_MAX_TRIPS && length(sp_gear_wanted(pawn))

/// Picks the next thing to fetch from tool storage into BB_SP_GEAR_TARGET, and the tile to reach it from.
/datum/bt_node/ai_behavior/sp_pick_gear

/datum/bt_node/ai_behavior/sp_pick_gear/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Every trip counts, whether or not it works out, so a trip that cannot be made is not made forever.
	controller.set_blackboard_key(BB_SP_GEAR_TRIPS, (controller.blackboard[BB_SP_GEAR_TRIPS] || 0) + 1)
	for(var/list/types as anything in sp_gear_wanted(pawn))
		var/list/found = sp_find_gear(pawn, types)
		if(isnull(found))
			continue
		controller.set_blackboard_key(BB_SP_GEAR_TARGET, found[1])
		controller.set_blackboard_key(BB_SP_GEAR_SPOT, found[2])
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	// Nothing left in tool storage that will do: no point going back for it.
	controller.set_blackboard_key(BB_SP_GEARED_UP, TRUE)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// Standing by it: takes the item, gloves on and a tool in the bag, and is pleased about it.
/datum/bt_node/ai_behavior/sp_take_gear

/datum/bt_node/ai_behavior/sp_take_gear/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/thing = controller.blackboard[BB_SP_GEAR_TARGET]
	controller.clear_blackboard_key(BB_SP_GEAR_TARGET)
	controller.clear_blackboard_key(BB_SP_GEAR_SPOT)
	if(!istype(pawn) || !sp_take_gear_item(pawn, thing))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("tide.geared")
	log_sp("[pawn.real_name] helped themselves to [thing.name] in [get_area_name(pawn)]")
	if(prob(50))
		if(istype(thing, /obj/item/clothing/gloves))
			sp_crew_speak(pawn, pick("Insuls! Don't mind if I do.", "Now I'm basically an engineer.", "Every assistant needs a pair of these."))
		else
			sp_crew_speak(pawn, pick("That'll come in handy.", "Mine now.", "Now we're talking."))
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Mischief --------------------------------------------------------------------------------------

/// Passes when an assistant is due to think about another prank.
/datum/bt_node/decorator/sp_mischief_due

/datum/bt_node/decorator/sp_mischief_due/check_condition(datum/ai_controller/controller)
	return world.time >= (controller.blackboard[BB_SP_MISCHIEF_NEXT] || 0)

/**
 * Decides on a prank, if the assistant is in the mood and security is not about: one of whatever is on offer
 * where they are standing (sp_mischief_options). The next one is a few minutes off whatever happens.
 */
/datum/bt_node/ai_behavior/sp_plan_mischief

/datum/bt_node/ai_behavior/sp_plan_mischief/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_MISCHIEF_NEXT, world.time + rand(SP_MISCHIEF_INTERVAL_MIN, SP_MISCHIEF_INTERVAL_MAX))
	if(!prob(SP_MISCHIEF_MOOD_CHANCE))
		log_sp("[pawn.real_name] is not in the mood for mischief")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(sp_security_watching(pawn))
		// Not with an officer in sight; security walks on, and so will they. Look again in a minute.
		controller.set_blackboard_key(BB_SP_MISCHIEF_NEXT, world.time + SP_MISCHIEF_RETRY_TIME)
		log_sp("[pawn.real_name] thinks better of it, with security about")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/options = sp_mischief_options(pawn)
	if(!length(options))
		// Nothing to be done here. They will be somewhere else soon enough.
		controller.set_blackboard_key(BB_SP_MISCHIEF_NEXT, world.time + SP_MISCHIEF_RETRY_TIME)
		log_sp("[pawn.real_name] found nothing to get up to in [get_area_name(pawn)]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/choice = pick(options)
	log_sp("[pawn.real_name] is up to something: [choice[1]] in [get_area_name(choice[3])]")
	controller.set_blackboard_key(BB_SP_MISCHIEF, choice[1])
	controller.set_blackboard_key(BB_SP_MISCHIEF_TARGET, choice[2])
	controller.set_blackboard_key(BB_SP_MISCHIEF_SPOT, choice[3])
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Standing at the spot: pulls the prank (sp_prank_*) and records it.
/datum/bt_node/ai_behavior/sp_do_mischief
	/// The prank and what it is done to, held across the async half.
	var/kind
	var/atom/target

/datum/bt_node/ai_behavior/sp_do_mischief/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	kind = controller.blackboard[BB_SP_MISCHIEF]
	target = controller.blackboard[BB_SP_MISCHIEF_TARGET]
	var/turf/spot = controller.blackboard[BB_SP_MISCHIEF_SPOT]
	controller.clear_blackboard_key(BB_SP_MISCHIEF)
	controller.clear_blackboard_key(BB_SP_MISCHIEF_TARGET)
	controller.clear_blackboard_key(BB_SP_MISCHIEF_SPOT)
	// An officer turning up on the way puts an end to it.
	if(!istype(pawn) || isnull(kind) || QDELETED(target) || get_turf(pawn) != spot || sp_security_watching(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_PRANKING, kind)
	return start_async()

/datum/bt_node/ai_behavior/sp_do_mischief/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/done = FALSE
	switch(kind)
		if(SP_MISCHIEF_GRAFFITI)
			done = sp_prank_graffiti(controller, target)
		if(SP_MISCHIEF_LIGHTS)
			done = sp_prank_lights(controller, target)
		if(SP_MISCHIEF_KNOCK)
			done = sp_prank_knock(controller, target)
		if(SP_MISCHIEF_BELL)
			done = sp_prank_bell(controller, target)
		if(SP_MISCHIEF_HONK)
			done = sp_prank_honk(controller, target)
		if(SP_MISCHIEF_VANDALISM)
			done = sp_prank_vandalism(controller, target)
	// Cleared even when the tree has moved on: the key is only ever set while a prank is running.
	controller.clear_blackboard_key(BB_SP_PRANKING)
	if(!async_still_valid())
		return
	if(!done)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("tide.[kind]")
	sp_station_event("[kind]", pawn, pawn)
	log_sp("[pawn.real_name] pulled a prank ([kind]) in [get_area_name(pawn)]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_do_mischief/finish_action(datum/ai_controller/controller, succeeded)
	kind = null
	target = null
	return ..()
