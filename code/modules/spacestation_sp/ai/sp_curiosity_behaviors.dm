// Idle behaviour every crew member has: wander the station, look in lockers, try doors that are not
// theirs. See sp_curiosity.dm for the helpers and the hooks an antagonist will override.

/// Wander off somewhere else on the station for a while.
/datum/bt_node/subtree/sp_crew_roam
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_roam.bt.json"

/// Open a locker or crate and pocket anything we fancy.
/datum/bt_node/subtree/sp_crew_rummage
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_rummage.bt.json"

/// Try a door we have no access to, and find out.
/datum/bt_node/subtree/sp_crew_try_door
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_try_door.bt.json"

// --- Roaming ---------------------------------------------------------------------------------------

/// Picks somewhere on the station that is not our department.
/datum/bt_node/ai_behavior/sp_pick_wander_turf/roam
	target_key = BB_SP_ROAM_TARGET
	areas_key = null

/datum/bt_node/ai_behavior/sp_pick_wander_turf/roam/perform(seconds_per_tick, datum/ai_controller/controller)
	// Anywhere but home: the department wander already covers home, and walking to the room you are
	// standing in is not much of an outing.
	var/area/home = controller.blackboard[BB_SP_HOME_AREA]
	var/list/elsewhere = sp_roaming_areas().Copy()
	if(home)
		elsewhere -= home.type
	fixed_areas = elsewhere
	return ..()

// --- Rummaging -------------------------------------------------------------------------------------

/// True when this crew member is in the mood to go through a locker.
/datum/bt_node/decorator/sp_is_nosy

/datum/bt_node/decorator/sp_is_nosy/check_condition(datum/ai_controller/controller)
	var/datum/ai_controller/sp_crew/crew_controller = controller
	return istype(crew_controller) && crew_controller.may_rummage()

/// Finds a shut locker, crate or box within sight that we could open.
/datum/bt_node/ai_behavior/sp_find_container
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_container/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/closet/container = sp_find_rummage_target(pawn, controller.blackboard[BB_SP_RUMMAGE_IGNORE])
	if(isnull(container))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_RUMMAGE_TARGET, container)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Opens it, has a look, takes what appeals, and shuts it again.
 *
 * Async because a locked closet takes two clicks — one to turn the lock over, one for the door — and a
 * second ClickOn() in the same tick is silently dropped.
 */
/datum/bt_node/ai_behavior/sp_rummage
	/// Snapshotted in perform() for perform_async().
	VAR_PRIVATE/obj/structure/closet/rummage_container

/datum/bt_node/ai_behavior/sp_rummage/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags

	var/mob/living/carbon/human/pawn = controller.pawn
	rummage_container = controller.blackboard[BB_SP_RUMMAGE_TARGET]
	controller.clear_blackboard_key(BB_SP_RUMMAGE_TARGET)
	if(!istype(pawn) || QDELETED(rummage_container) || !rummage_container.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// However it goes, we have now seen inside this one.
	controller.set_blackboard_key_assoc_lazylist(BB_SP_RUMMAGE_IGNORE, rummage_container, world.time + SP_RUMMAGE_IGNORE_TIME)
	pawn.face_atom(rummage_container)
	return start_async()

/datum/bt_node/ai_behavior/sp_rummage/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/ai_controller/sp_crew/crew_controller = controller
	var/obj/structure/closet/container = rummage_container
	sp_free_hands(pawn)

	if(container.locked)
		sp_ai_click(controller, container, list(RIGHT_CLICK = "1"))
	if(!container.opened)
		sp_ai_click(controller, container)
	if(!container.opened)
		if(async_still_valid())
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return

	var/list/obj/item/tempting = sp_tempting_contents(container, crew_controller)
	var/taken = 0
	var/list/names = list()
	for(var/obj/item/thing as anything in tempting)
		if(taken >= SP_RUMMAGE_TAKE_LIMIT)
			break
		if(!pawn.back || !thing.forceMove(pawn.back))
			if(!pawn.put_in_hands(thing))
				continue
		names |= thing.name
		taken++

	// Shut it behind us. An ordinary crew member is nosy, not a vandal — leaving lockers hanging open
	// is a greytide tell, and a greytide controller will want to skip this.
	if(container.opened)
		sp_ai_click(controller, container)

	if(!async_still_valid())
		return
	if(taken)
		sp_record("crew.pocketed")
		log_sp("[pawn.real_name] helped themselves to [english_list(names)] from [container.name] in [get_area_name(container)]")
		crew_controller.remark_on_find(names)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_rummage/finish_action(datum/ai_controller/controller, succeeded)
	rummage_container = null
	return ..()

/// Says something about a find, now and then. Kept off the radio: this is muttering, not a report.
/datum/ai_controller/sp_crew/proc/remark_on_find(list/names)
	var/mob/living/carbon/human/human_pawn = pawn
	var/quiet_until = blackboard[BB_SP_NOSY_SPEAK_COOLDOWN] || 0
	if(!istype(human_pawn) || world.time < quiet_until || !prob(40))
		return
	set_blackboard_key(BB_SP_NOSY_SPEAK_COOLDOWN, world.time + 45 SECONDS)
	sp_crew_speak(human_pawn, pick(
		"Oh, [english_list(names)]. Don't mind if I do.",
		"Nobody's going to miss this.",
		"Finders keepers.",
		"Somebody left [english_list(names)] lying about.",
	))

// --- Trying doors ----------------------------------------------------------------------------------

/// True when this crew member is the sort to try a handle that is not theirs.
/datum/bt_node/decorator/sp_tries_doors

/datum/bt_node/decorator/sp_tries_doors/check_condition(datum/ai_controller/controller)
	var/datum/ai_controller/sp_crew/crew_controller = controller
	return istype(crew_controller) && crew_controller.may_try_doors()

/// Finds a shut door within sight that will not open for us.
/datum/bt_node/ai_behavior/sp_find_locked_door
	time_between_perform = 10 SECONDS

/datum/bt_node/ai_behavior/sp_find_locked_door/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/machinery/door/airlock/door = sp_find_door_to_try(pawn, controller.blackboard[BB_SP_DOOR_IGNORE])
	if(isnull(door))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_DOOR_TARGET, door)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Tries it. The door refuses, which is the whole point.
/datum/bt_node/ai_behavior/sp_try_door

/datum/bt_node/ai_behavior/sp_try_door/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/ai_controller/sp_crew/crew_controller = controller
	var/obj/machinery/door/airlock/door = controller.blackboard[BB_SP_DOOR_TARGET]
	controller.clear_blackboard_key(BB_SP_DOOR_TARGET)
	if(!istype(pawn) || !istype(crew_controller) || QDELETED(door) || !door.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	pawn.face_atom(door)
	sp_free_hands(pawn)
	controller.ai_interact(door, combat_mode = FALSE)
	// Leave it alone for a good while: the access will not have changed by the next corridor.
	controller.set_blackboard_key_assoc_lazylist(BB_SP_DOOR_IGNORE, door, world.time + SP_DOOR_IGNORE_TIME)

	if(!door.density)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED // it opened after all; nothing to be sour about
	sp_record("crew.door_refused")
	log_sp("[pawn.real_name] tried [door.name] in [get_area_name(door)] and was refused")
	crew_controller.on_door_denied(door)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
