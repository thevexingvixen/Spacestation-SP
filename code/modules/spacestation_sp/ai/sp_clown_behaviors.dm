// Behaviour for the AI clown: honk at people, and leave a peel where somebody will find it.
//
// The clown starts a shift with one banana and a horn, so asking botany for more goes through the same
// request system every other department already uses (GLOB.sp_requestable_plants). Where a peel lands is
// the only line drawn: the halls, the commons and the service end are fair game, medbay and the brig are
// not, because a doctor going over on their way to a patient is somebody's emergency rather than a joke.

/// Honk at somebody, leave a peel somewhere public, and ask botany for more bananas.
/datum/bt_node/subtree/sp_clown_antics
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_clown_antics.bt.json"

/// Clown: honks, drops peels, and keeps themselves in bananas.
/datum/ai_controller/sp_crew/clown
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_clown.bt.json"

// --- Helpers ---------------------------------------------------------------------------------------

/**
 * Where a peel is a joke rather than a hazard.
 *
 * The hallways, the commons and the service end of the station only. Medbay, security, engineering and
 * atmospherics are left alone: somebody going over in any of those is a shift ruined rather than a laugh,
 * and a clown who cannot tell the difference gets shot by security in about four minutes.
 */
/proc/sp_clown_prank_spot(atom/where)
	var/area/here = get_area(where)
	if(isnull(here))
		return FALSE
	var/static/list/allowed = typecacheof(list(/area/station/hallway, /area/station/commons, /area/station/service))
	return !!allowed[here.type]

/// The banana we are carrying, if any.
/proc/sp_carried_banana(mob/living/carbon/human/pawn)
	var/list/carried = pawn?.get_all_contents_type(/obj/item/food/grown/banana)
	return length(carried) ? carried[1] : null

// --- The antics ------------------------------------------------------------------------------------

/// Honks at whoever is nearby. The horn is harmless: no force, no hitsound, just the noise.
/datum/bt_node/ai_behavior/sp_clown_honk
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_clown_honk/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/mob/living/carbon/human/audience
	for(var/mob/living/carbon/human/nearby in oview(SP_CLOWN_HONK_RANGE, pawn))
		if(nearby.stat != STABLE || !can_see(pawn, nearby, SP_CLOWN_HONK_RANGE))
			continue
		audience = nearby
		break
	if(isnull(audience))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/horn = sp_equip_from_inventory(pawn, list(/obj/item/bikehorn, /obj/item/instrument/bikehorn))
	if(isnull(horn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	pawn.face_atom(audience)
	// Used in hand rather than swung at them: the squeak component honks, and nobody has been hit.
	horn.attack_self(pawn)
	sp_record("clown.honk")
	log_sp("[pawn.real_name] honked at [audience.real_name] in [get_area_name(pawn)]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Leaves a banana peel underfoot, somewhere it is only funny.
/datum/bt_node/ai_behavior/sp_clown_peel

/datum/bt_node/ai_behavior/sp_clown_peel/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !sp_clown_prank_spot(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/food/grown/banana/banana = sp_carried_banana(pawn)
	if(QDELETED(banana) || isnull(banana.trash_type))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// The clown eats the banana and drops the skin. TG models that as eating, which a clown mask is in the
	// way of, so the change is made directly: the peel is the banana's own trash type, and it is slippery
	// because TG made it so, not because we made it so.
	var/obj/item/peel = new banana.trash_type(get_turf(pawn))
	qdel(banana)
	sp_record("clown.peel")
	sp_station_event("peel", pawn)
	log_sp("[pawn.real_name] left [peel.name] in [get_area_name(pawn)]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Out of bananas: ask botany, the way every other department asks for what it has run out of.
/datum/bt_node/ai_behavior/sp_clown_restock

/datum/bt_node/ai_behavior/sp_clown_restock/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !isnull(sp_carried_banana(pawn)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// The line has to name botany and the plant, which is what sp_plant_asked_for() listens for.
	sp_crew_speak(pawn, pick(
		"Botany, a clown with no bananas is just a man in makeup. Bananas, please.",
		"Any bananas going, botany? Asking for a friend. The friend is me.",
		"Botany! Bananas. It is a professional requirement, I have paperwork.",
	), RADIO_CHANNEL_SERVICE)
	sp_record("clown.asked")
	log_sp("[pawn.real_name] asked botany for bananas")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
