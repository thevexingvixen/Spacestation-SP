// Behavior-tree leaves, subtrees and targeting strategies used by Spacestation SP crew.

// --- Subtree declarations (trees live next to this file) --------------------------------------

/// Walk to a random turf inside our department (or the areas in BB_SP_WANDER_AREAS), then linger.
/datum/bt_node/subtree/sp_department_wander
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_department_wander.bt.json"

/// When hurt: shout for help and walk to medbay.
/datum/bt_node/subtree/sp_crew_safety
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_safety.bt.json"

/// When someone addresses us by name: face them and answer.
/datum/bt_node/subtree/sp_crew_social
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_social.bt.json"

/// Medical: find a treatable patient, equip the right medical stack, walk over and apply it.
/datum/bt_node/subtree/sp_medical_treat
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_medical_treat.bt.json"

// --- Leaves -----------------------------------------------------------------------------------

/**
 * Picks a random walkable turf inside one of a set of areas and stores it in target_key.
 * Areas come from the blackboard list in areas_key, else from fixed_areas, else from the type
 * of BB_SP_HOME_AREA (including subtypes).
 */
/datum/bt_node/ai_behavior/sp_pick_wander_turf
	/// Blackboard key to write the chosen turf into.
	var/target_key = BB_SP_WANDER_TARGET
	/// Blackboard key holding a list of /area typepaths to choose from. Optional.
	var/areas_key = BB_SP_WANDER_AREAS
	/// Fixed list of /area typepaths, used when areas_key yields nothing. Optional.
	var/list/fixed_areas
	/// How many random turfs to test before giving up on an area.
	var/attempts = 12

/datum/bt_node/ai_behavior/sp_pick_wander_turf/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	var/turf/pawn_turf = get_turf(pawn)
	if(isnull(pawn_turf))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/area_types = list()
	var/include_subtypes = FALSE
	var/list/from_bb = areas_key ? controller.blackboard[areas_key] : null
	if(length(from_bb))
		area_types = from_bb.Copy()
	else if(length(fixed_areas))
		area_types = fixed_areas.Copy()
	else
		var/area/home = controller.blackboard[BB_SP_HOME_AREA]
		if(isnull(home))
			home = get_area(pawn)
		if(isnull(home))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		area_types = list(home.type)
		include_subtypes = TRUE

	// Try a few areas in random order; some will not exist on this z-level.
	area_types = shuffle(area_types)
	for(var/area_type in area_types)
		var/list/turfs = get_area_turfs(area_type, pawn_turf.z, include_subtypes)
		if(!length(turfs))
			continue
		for(var/i in 1 to attempts)
			var/turf/candidate = pick(turfs)
			if(candidate == pawn_turf || candidate.density || isgroundlessturf(candidate))
				continue
			if(candidate.is_blocked_turf(exclude_mobs = TRUE))
				continue
			controller.set_blackboard_key(target_key, candidate)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// Medbay variant with a fixed area list, used by the safety subtree.
/datum/bt_node/ai_behavior/sp_pick_wander_turf/medbay
	target_key = BB_SP_MEDBAY_TARGET
	areas_key = null
	fixed_areas = list(
		/area/station/medical/treatment_center,
		/area/station/medical/medbay/central,
		/area/station/medical/medbay/lobby,
		/area/station/medical/medbay/aft,
		/area/station/medical/exam_room,
	)

/**
 * Says one of `lines`, optionally facing the atom in face_key first.
 * "%TARGET%" in a line is replaced with that atom's name.
 */
/datum/bt_node/ai_behavior/sp_say
	/// Lines to pick from.
	var/list/lines
	/// Optional blackboard key holding an atom to face / name in the line.
	var/face_key

/datum/bt_node/ai_behavior/sp_say/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/pawn = controller.pawn
	if(!istype(pawn) || !length(lines))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/target = face_key ? controller.blackboard[face_key] : null
	var/line = pick(lines)
	if(!QDELETED(target))
		pawn.face_atom(target)
		line = replacetext(line, "%TARGET%", target.name)
	INVOKE_ASYNC(src, PROC_REF(speak), pawn, line)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/datum/bt_node/ai_behavior/sp_say/proc/speak(mob/living/pawn, line)
	pawn.say(line, forced = "AI Controller")

/datum/bt_node/ai_behavior/sp_say/need_medic
	lines = list(
		"I need a doctor!",
		"Medic! Somebody get a medic!",
		"Ow... I'm heading to medbay.",
		"Is there a doctor around? I'm hurt.",
	)

/datum/bt_node/ai_behavior/sp_say/greet
	face_key = BB_SP_ATTENTION_TARGET
	lines = list(
		"Yes, %TARGET%?",
		"What do you need, %TARGET%?",
		"Hm? Oh, hello %TARGET%.",
		"I'm a bit busy, %TARGET%, but go ahead.",
		"You called?",
	)

/**
 * Medical: puts a suitable medical stack into our hands for the patient in patient_key.
 * Searches our whole inventory (medkits included). Stores the item in target_key.
 */
/datum/bt_node/ai_behavior/sp_equip_medical_item
	/// Blackboard key holding the patient.
	var/patient_key = BB_SP_PATIENT
	/// Blackboard key to write the equipped item into.
	var/target_key = BB_SP_MEDICAL_ITEM
	/// Brute-treating stacks, best first.
	var/static/list/brute_types = list(/obj/item/stack/medical/suture, /obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/wrap/gauze)
	/// Burn-treating stacks, best first.
	var/static/list/burn_types = list(/obj/item/stack/medical/mesh, /obj/item/stack/medical/ointment, /obj/item/stack/medical/aloe)

/datum/bt_node/ai_behavior/sp_equip_medical_item/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/pawn = controller.pawn
	var/mob/living/patient = controller.blackboard[patient_key]
	if(!iscarbon(pawn) || QDELETED(patient))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/wanted = list()
	if(patient.get_brute_loss() >= patient.get_fire_loss())
		wanted = brute_types + burn_types
	else
		wanted = burn_types + brute_types
	if(patient.get_brute_loss() <= 0)
		wanted -= brute_types
	if(patient.get_fire_loss() <= 0)
		wanted -= burn_types
	if(!length(wanted))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	var/list/carried = pawn.get_all_contents_type(/obj/item/stack/medical)
	var/obj/item/chosen
	for(var/wanted_type in wanted)
		for(var/obj/item/candidate as anything in carried)
			if(istype(candidate, wanted_type))
				chosen = candidate
				break
		if(chosen)
			break
	if(isnull(chosen))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

	if(pawn.is_holding(chosen))
		if(pawn.get_active_held_item() != chosen)
			pawn.swap_hand()
		controller.set_blackboard_key(target_key, chosen)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

	if(!pawn.put_in_hands(chosen))
		// Both hands full; free the active one and try again.
		var/obj/item/active = pawn.get_active_held_item()
		if(isnull(active) || !pawn.dropItemToGround(active) || !pawn.put_in_hands(chosen))
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(pawn.get_active_held_item() != chosen)
		pawn.swap_hand()
	controller.set_blackboard_key(target_key, chosen)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

// --- Targeting --------------------------------------------------------------------------------

/// Living, not us, not dead, and carrying enough brute or burn damage for a medical stack to matter.
/datum/targeting_strategy/sp_treatable_patient
	/// Minimum brute or burn damage before we bother.
	var/minimum_damage = 10

/datum/targeting_strategy/sp_treatable_patient/is_valid_target(mob/living/living_mob, atom/target, vision_range, datum/ai_controller/controller = null)
	. = ..()
	if(!.)
		return FALSE
	if(target == living_mob || !isliving(target))
		return FALSE
	var/mob/living/patient = target
	if(patient.stat == DEAD)
		return FALSE
	return (patient.get_brute_loss() >= minimum_damage) || (patient.get_fire_loss() >= minimum_damage)
