// Bodies: medbay's and the detective's side of sp_body.dm. The witness side is in sp_scan_threats (sp_crew_behaviors.dm).

// --- Medbay ----------------------------------------------------------------------------------------------

/// A body called in: one medic goes, whoever is free and hears it first, the way a house call works.
/datum/ai_controller/sp_crew/medical/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	if(reporter == pawn)
		return
	var/datum/weakref/body_ref = incident[SP_INCIDENT_BODY]
	take_body(body_ref?.resolve(), reporter)

/// Takes a body on, if free to and nobody else has. TRUE if taken.
/datum/ai_controller/sp_crew/medical/proc/take_body(mob/living/carbon/human/body, mob/living/carbon/human/told_by)
	var/mob/living/carbon/human/medic = pawn
	if(!istype(medic) || !sp_is_body(body) || body.z != medic.z || blackboard[BB_SP_BODY] == body || busy_with_work())
		return FALSE
	if(!isnull(sp_body_taken_by(body, medic)))
		return FALSE
	set_blackboard_key(BB_SP_BODY, body)
	set_blackboard_key(BB_SP_BODY_AT, world.time)
	sp_record("med.body_call")
	log_sp("[medic.real_name] is going to [body.real_name] in [get_area_name(body)][istype(told_by) ? ", called by [told_by.real_name]" : ""]")
	sp_crew_speak(medic, "On my way to [body.name] in [get_area_name(body)].", RADIO_CHANNEL_COMMON)
	return TRUE

/// Chemists stay at the bench.
/datum/ai_controller/sp_crew/medical/chemist/take_body(mob/living/carbon/human/body, mob/living/carbon/human/told_by)
	return FALSE

/// The AI medic already seeing to this body, other than `other_than`, or null.
/proc/sp_body_taken_by(mob/living/carbon/human/body, mob/living/carbon/human/other_than)
	for(var/mob/living/carbon/human/medic as anything in GLOB.human_list)
		if(medic == other_than)
			continue
		var/datum/ai_controller/sp_crew/medical/their_ai = medic.ai_controller
		if(istype(their_ai) && their_ai.blackboard[BB_SP_BODY] == body)
			return medic
	return null

/// Forgets the body we were seeing to, done with or not.
/proc/sp_drop_body(datum/ai_controller/controller)
	controller?.clear_blackboard_key(BB_SP_BODY)
	controller?.clear_blackboard_key(BB_SP_BODY_AT)
	controller?.clear_blackboard_key(BB_SP_MORGUE)
	controller?.clear_blackboard_key(BB_SP_MORGUE_SPOT)

/// See to a body: go to it, try the paddles, and failing that the morgue. Above patients: a body has a window.
/datum/bt_node/subtree/sp_medical_body
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_body.bt.json"

/// The body we are seeing to, if it is still a body lying somewhere we might get to. Clears it otherwise.
/datum/bt_node/ai_behavior/sp_find_body
	time_between_perform = 2 SECONDS

/datum/bt_node/ai_behavior/sp_find_body/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/carbon/human/body = controller.blackboard[BB_SP_BODY]
	if(!istype(pawn) || isnull(body))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Gone, back with us by somebody else's hand, or on a tray already: nothing left for us either way.
	if(QDELETED(body) || body.stat != DEAD || body.z != pawn.z || !isturf(body.loc))
		sp_drop_body(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(world.time - (controller.blackboard[BB_SP_BODY_AT] || 0) > SP_BODY_CALL_TIME)
		log_sp("[pawn.real_name] gave up on getting to [body.real_name] in [get_area_name(body)]")
		sp_drop_body(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * Beside the body: the paddles, if TG says they would work and we have them; otherwise the morgue, with the body in
 * tow. Succeeds only when there is a morgue trip to make. A body revived, or one nothing can be done for and nowhere
 * to take, ends the visit here. Async.
 */
/datum/bt_node/ai_behavior/sp_see_to_body
	VAR_PRIVATE/mob/living/carbon/human/body

/datum/bt_node/ai_behavior/sp_see_to_body/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	body = controller.blackboard[BB_SP_BODY]
	if(!istype(pawn) || !sp_is_body(body) || !body.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_see_to_body/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(sp_try_revive(controller, body))
		if(async_still_valid())
			sp_drop_body(controller)
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(!async_still_valid())
		return
	if(QDELETED(body) || !sp_is_body(body))
		sp_drop_body(controller)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	var/obj/structure/bodycontainer/morgue/slab = sp_find_morgue(body)
	var/turf/spot = isnull(slab) ? null : sp_morgue_spot(slab, pawn)
	if(isnull(spot))
		log_sp("[pawn.real_name] has nowhere to take [body.real_name]: no free morgue tray")
		sp_crew_speak(pawn, "There's nothing I can do for [body.name], and nowhere to take [body.p_them()].")
		sp_drop_body(controller)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	if(pawn.pulling != body && !pawn.start_pulling(body))
		log_sp("[pawn.real_name] could not take hold of [body.real_name]")
		sp_drop_body(controller)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.set_blackboard_key(BB_SP_MORGUE, slab)
	controller.set_blackboard_key(BB_SP_MORGUE_SPOT, spot)
	log_sp("[pawn.real_name] is taking [body.real_name] to the morgue from [get_area_name(body)]")
	sp_crew_speak(pawn, pick("I'm sorry. I'll take [body.name] to the morgue.", "Too late for [body.name]. Make way, please."))
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_see_to_body/finish_action(datum/ai_controller/controller, succeeded)
	body = null
	return ..()

/// A walk with somebody in tow: no diagonal steps, so the pull survives corners (/datum/ai_movement/jps/sp_crew/escort).
/datum/bt_node/ai_behavior/move_to_target/sp_reported/sp_hauling
	movement_type = /datum/ai_movement/jps/sp_crew/escort

/**
 * Beside the tray with the body: in it goes (sp_store_in_morgue). A pull lost on the way is taken again if the body is
 * still in reach, and the trip starts over from the body if not. Async.
 */
/datum/bt_node/ai_behavior/sp_store_body
	VAR_PRIVATE/mob/living/carbon/human/body
	VAR_PRIVATE/obj/structure/bodycontainer/morgue/slab

/datum/bt_node/ai_behavior/sp_store_body/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	body = controller.blackboard[BB_SP_BODY]
	slab = controller.blackboard[BB_SP_MORGUE]
	if(!istype(pawn) || QDELETED(body) || QDELETED(slab) || !body.Adjacent(pawn))
		// The tray is gone or the body was lost on the way: back to the body, and another look for a tray.
		controller.clear_blackboard_key(BB_SP_MORGUE)
		controller.clear_blackboard_key(BB_SP_MORGUE_SPOT)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(pawn.pulling != body)
		pawn.start_pulling(body)
	return start_async()

/datum/bt_node/ai_behavior/sp_store_body/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/stored = sp_store_in_morgue(controller, body, slab)
	if(!async_still_valid())
		return
	if(!stored && !QDELETED(body))
		log_sp("[pawn.real_name] could not get [body.real_name] into the morgue; leaving them in [get_area_name(body)]")
	sp_drop_body(controller)
	finish_async(AI_BEHAVIOR_DELAY | (stored ? AI_BEHAVIOR_SUCCEEDED : AI_BEHAVIOR_FAILED))

/datum/bt_node/ai_behavior/sp_store_body/finish_action(datum/ai_controller/controller, succeeded)
	body = null
	slab = null
	return ..()

// --- The detective ---------------------------------------------------------------------------------------

/// Security's investigator: an officer in every other respect, who goes to look at a body before anything else.
/datum/ai_controller/sp_crew/security/detective
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_detective.bt.json"

/datum/ai_controller/sp_crew/security/detective/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	. = ..()
	var/datum/weakref/body_ref = incident[SP_INCIDENT_BODY]
	take_scene(body_ref?.resolve())

/// Takes a body as a scene to look over, once, when no other is on. TRUE if taken.
/datum/ai_controller/sp_crew/security/detective/proc/take_scene(mob/living/carbon/human/body)
	var/mob/living/carbon/human/detective = pawn
	if(!istype(detective) || !sp_is_body(body) || body.z != detective.z || blackboard_key_exists(BB_SP_SCENE) || GLOB.sp_investigated_bodies[REF(body)])
		return FALSE
	set_blackboard_key(BB_SP_SCENE, body)
	set_blackboard_key(BB_SP_SCENE_AT, world.time)
	set_blackboard_key(BB_SP_SCENE_TURF, get_turf(body))
	sp_record("det.scene_taken")
	log_sp("[detective.real_name] is going to look at [body.real_name] in [get_area_name(body)]")
	sp_crew_speak(detective, "I'll have a look at [get_area_name(body)].", RADIO_CHANNEL_SECURITY)
	return TRUE

/datum/ai_controller/sp_crew/security/detective/busy_with_work()
	return ..() || blackboard_key_exists(BB_SP_SCENE)

/// Forgets the scene.
/proc/sp_drop_scene(datum/ai_controller/controller)
	controller?.clear_blackboard_key(BB_SP_SCENE)
	controller?.clear_blackboard_key(BB_SP_SCENE_AT)
	controller?.clear_blackboard_key(BB_SP_SCENE_TURF)
	controller?.clear_blackboard_key(BB_SP_SCENE_GOAL)

/// Look a scene over: go to the body, or to where it lay, and read it. Above the rest of security's work.
/datum/bt_node/subtree/sp_detective_scene
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_detective_scene.bt.json"

/**
 * Where to go: the body while it is lying somewhere, and once a medic has it on a tray, the tile it lay on, where
 * whatever was dropped still is. Clears the scene when there is nothing left to look at.
 */
/datum/bt_node/ai_behavior/sp_find_scene
	time_between_perform = 2 SECONDS

/datum/bt_node/ai_behavior/sp_find_scene/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/mob/living/carbon/human/body = controller.blackboard[BB_SP_SCENE]
	var/turf/where = controller.blackboard[BB_SP_SCENE_TURF]
	if(!istype(pawn) || isnull(body))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(QDELETED(body) || body.stat != DEAD || GLOB.sp_investigated_bodies[REF(body)])
		sp_drop_scene(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(world.time - (controller.blackboard[BB_SP_SCENE_AT] || 0) > SP_BODY_CALL_TIME)
		log_sp("[pawn.real_name] gave up on getting to [body.real_name]'s scene")
		sp_drop_scene(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/goal = (isturf(body.loc) && body.z == pawn.z) ? body : where
	if(isnull(goal) || goal.z != pawn.z)
		sp_drop_scene(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_SCENE_GOAL] != goal)
		controller.set_blackboard_key(BB_SP_SCENE_GOAL, goal)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// At the scene: read it (sp_investigate_scene). Async.
/datum/bt_node/ai_behavior/sp_investigate_scene
	VAR_PRIVATE/mob/living/carbon/human/body
	VAR_PRIVATE/turf/where

/datum/bt_node/ai_behavior/sp_investigate_scene/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	body = controller.blackboard[BB_SP_SCENE]
	where = controller.blackboard[BB_SP_SCENE_TURF]
	var/atom/goal = controller.blackboard[BB_SP_SCENE_GOAL]
	if(!istype(pawn) || QDELETED(body) || QDELETED(goal) || !goal.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_investigate_scene/perform_async(datum/ai_controller/controller)
	sp_investigate_scene(controller, body, where)
	if(!async_still_valid())
		return
	sp_drop_scene(controller)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_investigate_scene/finish_action(datum/ai_controller/controller, succeeded)
	body = null
	where = null
	return ..()
