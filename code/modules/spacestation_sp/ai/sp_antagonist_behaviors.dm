// Antagonist behaviour: pursuing a scheme (sp_antagonist.dm). The worked example is theft; the shape —
// find the goal, get to it, take it, then lie low — is what other schemes will reuse.

/// A crew member with a hidden agenda. Any job could carry a scheme; this is the dedicated example that
/// spends its shift on one, and it is what the admin verb spawns.
/datum/ai_controller/sp_crew/antagonist
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_antagonist.bt.json"

/// The scheme's target is worth taking even though it is on nobody's interest list.
/datum/ai_controller/sp_crew/antagonist/wants_item(obj/item/thing)
	var/datum/sp_scheme/steal/scheme = blackboard[BB_SP_SCHEME]
	if(istype(scheme) && !isnull(scheme.target_type) && istype(thing, scheme.target_type))
		return TRUE
	return ..()

/// Bolder than the ordinary crew: an antagonist rummages and tries doors wherever it helps the scheme.
/datum/ai_controller/sp_crew/antagonist/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	set_blackboard_key(BB_SP_WANDER_AREAS, typesof(/area/station/hallway) + typesof(/area/station/maintenance))
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 1,
		BB_EMOTE_SAY = list("Just passing through.", "Don't mind me.", "Busy day."),
		BB_EMOTE_SEE = list("glances over their shoulder.", "checks a pocket."),
	))

/// A schemer keeps their head down: they are as busy as anyone with real work, so chatter does not pull them off it.
/datum/ai_controller/sp_crew/antagonist/busy_with_work()
	var/datum/sp_scheme/scheme = blackboard[BB_SP_SCHEME]
	return istype(scheme) && !scheme.complete

// --- The subtree -----------------------------------------------------------------------------------

/// Pursue the scheme: find what to go for, get there, take it, lie low. Ranks below self-preservation.
/datum/bt_node/subtree/sp_crew_scheme
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_scheme.bt.json"

/// Passes while there is a scheme still to finish.
/datum/bt_node/decorator/sp_has_active_scheme

/datum/bt_node/decorator/sp_has_active_scheme/check_condition(datum/ai_controller/controller)
	var/datum/sp_scheme/scheme = controller.blackboard[BB_SP_SCHEME]
	return istype(scheme) && !scheme.complete

/**
 * Works out what the scheme wants us at right now. Latches completion first (so the shift we picked the
 * item up we stop here and go back to looking innocent), then asks the scheme for its goal atom: the item,
 * or the locker it sits in. Fails when there is nothing to go to.
 */
/datum/bt_node/ai_behavior/sp_find_scheme_goal
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_find_scheme_goal/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/sp_scheme/scheme = controller.blackboard[BB_SP_SCHEME]
	if(!istype(pawn) || !istype(scheme))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(scheme.check_progress(controller))
		controller.clear_blackboard_key(BB_SP_SCHEME_TARGET)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/goal = scheme.current_goal_atom(controller)
	if(isnull(goal))
		controller.clear_blackboard_key(BB_SP_SCHEME_TARGET)
		sp_note_scheme_stuck(controller, scheme)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Walk to the thing, or to the locker it is shut in.
	var/atom/movable/reach = goal
	if(isturf(goal.loc) || ismob(goal.loc))
		reach = goal
	else if(istype(goal.loc, /obj/structure/closet))
		reach = goal.loc
	controller.set_blackboard_key(BB_SP_SCHEME_TARGET, reach)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Standing by the target: take it. Opens a locker it is shut in, pockets it, and gets caught if seen. Async.
/datum/bt_node/ai_behavior/sp_take_scheme_item
	/// Held across the async half.
	VAR_PRIVATE/atom/movable/reach

/datum/bt_node/ai_behavior/sp_take_scheme_item/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_SCHEME_TARGET]
	if(!istype(pawn) || QDELETED(reach) || !reach.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_take_scheme_item/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/sp_scheme/steal/scheme = controller.blackboard[BB_SP_SCHEME]
	if(!istype(scheme) || isnull(scheme.target_type))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_free_hands(pawn)
	// A locker in the way is opened (and unlocked first if our own ID will do it).
	if(istype(reach, /obj/structure/closet))
		var/obj/structure/closet/locker = reach
		if(locker.locked && locker.allowed(pawn))
			sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
		if(!locker.opened)
			sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(pawn))
		return
	var/obj/item/prize = sp_reachable_item(pawn, scheme.target_type)
	if(QDELETED(prize))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	// The theft itself takes a moment, the way rifling something out of a locker does.
	if(!do_after(pawn, SP_THEFT_TIME, prize, timed_action_flags = IGNORE_HELD_ITEM))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!async_still_valid() || QDELETED(pawn) || QDELETED(prize) || !prize.Adjacent(pawn))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/where = get_area_name(prize)
	var/what = prize.name
	if(!(pawn.back && prize.forceMove(pawn.back)) && !pawn.put_in_hands(prize))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("antag.stole")
	log_sp("[pawn.real_name] stole [what] from [where]")
	// Somebody may have seen that, and a witness who did knows what to tell security was taken.
	sp_crime_seen(pawn, SP_CRIME_THEFT, "take [what]", get_turf(pawn), taken = prize)
	scheme.check_progress(controller)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_take_scheme_item/finish_action(datum/ai_controller/controller, succeeded)
	reach = null
	return ..()

/**
 * Says so in the log when a scheme has nothing to go to, at most once every couple of minutes.
 *
 * The first antagonist of the first round was a mime on the arrival shuttle told to steal something on the
 * station below: the goal search came back empty every three seconds and said nothing, which in a log reads
 * exactly like an antagonist who simply has not started yet.
 */
/proc/sp_note_scheme_stuck(datum/ai_controller/sp_crew/controller, datum/sp_scheme/scheme)
	if(world.time < (controller.blackboard[BB_SP_SCHEME_STUCK_LOG] || 0))
		return
	controller.set_blackboard_key(BB_SP_SCHEME_STUCK_LOG, world.time + SP_SCHEME_STUCK_LOG_EVERY)
	var/mob/living/pawn = controller.pawn
	log_sp("[pawn?.real_name || "someone"] cannot get at what they are after ([scheme?.name]) from [get_area_name(pawn)]")

/// The nearest instance of `item_type` within reach: on us, on our tile or an adjacent one (an open locker's).
/proc/sp_reachable_item(mob/living/carbon/human/pawn, item_type)
	var/obj/item/carried = locate(item_type) in pawn.get_all_contents_type(item_type)
	if(!QDELETED(carried))
		return carried
	for(var/obj/item/candidate in range(1, pawn))
		if(istype(candidate, item_type) && candidate.Adjacent(pawn))
			return candidate
	return null
