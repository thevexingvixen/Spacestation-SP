/**
 * Favours: standing spent on things the crew do for you.
 *
 * Conversation changes how people feel about you (sp_conversation.dm); this is where that turns into something you
 * can use. A crew member who thinks well enough of you will come with you, open a door their ID opens and yours
 * does not, fetch you something from their own department, or call medbay for you. Each is asked for in a written
 * dialogue (ask_follow, ask_door, ask_fetch, ask_doctor), which decides who says yes and what it costs them to like
 * you afterwards; its "favour" effect hands the job to this subtree, which does it in the world, where you can watch.
 *
 * A favour sits above the job but below emergencies and conversation (sp_crew_core): work that turns up ends it with
 * a word, and so does the person it is for saying thanks, or that's all. One favour at a time.
 */

/datum/bt_node/subtree/sp_crew_favour
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_favour.bt.json"

/// Every favour a dialogue file may ask for.
GLOBAL_LIST_INIT(sp_favours, list(SP_FAVOUR_FOLLOW, SP_FAVOUR_DOOR, SP_FAVOUR_FETCH, SP_FAVOUR_DOCTOR))

/**
 * Accesses nobody opens a door with for somebody who lacks them: security, command, the vault, the AI, the engine,
 * and the airlocks out into space.
 */
GLOBAL_LIST_INIT(sp_never_opened_for_others, list(
	ACCESS_ARMORY, ACCESS_BRIG, ACCESS_BRIG_ENTRANCE, ACCESS_SECURITY, ACCESS_WEAPONS, ACCESS_DETECTIVE,
	ACCESS_CAPTAIN, ACCESS_HOS, ACCESS_HOP, ACCESS_CE, ACCESS_CMO, ACCESS_RD, ACCESS_QM, ACCESS_COMMAND, ACCESS_KEYCARD_AUTH,
	ACCESS_VAULT, ACCESS_AI_UPLOAD, ACCESS_MINISAT, ACCESS_TELEPORTER, ACCESS_GATEWAY, ACCESS_EVA, ACCESS_TCOMMS,
	ACCESS_ENGINE_EQUIP, ACCESS_EXTERNAL_AIRLOCKS,
))

// --- What each job will do ---------------------------------------------------------------------------

/// Whether this job does favours at all.
/datum/ai_controller/sp_crew/proc/does_favours()
	return TRUE

/// Security are on duty, and nobody's errand boy.
/datum/ai_controller/sp_crew/security/does_favours()
	return FALSE

/// What this job would fetch for somebody from its own department (BB_SP_WANDER_AREAS), best first.
/datum/ai_controller/sp_crew/proc/fetchables()
	return null

/// What this job carries and would hand straight over.
/datum/ai_controller/sp_crew/proc/spares()
	return null

/// Whether this particular one of the things above is fit to hand somebody.
/datum/ai_controller/sp_crew/proc/fetch_ok(obj/item/thing)
	return TRUE

/// Medbay storage keeps its medkits out on the tables, and the lobby its gauze and mesh.
/datum/ai_controller/sp_crew/medical/fetchables()
	return list(/obj/item/storage/medkit/regular, /obj/item/storage/medkit/brute, /obj/item/stack/medical/wrap/gauze, /obj/item/stack/medical/mesh, /obj/item/stack/medical/suture)

/// Insulated gloves, the thing every assistant asks an engineer for.
/datum/ai_controller/sp_crew/engineer/fetchables()
	return list(/obj/item/clothing/gloves/color/yellow, /obj/item/storage/toolbox/electrical, /obj/item/storage/toolbox/mechanical, /obj/item/stack/cable_coil)

/datum/ai_controller/sp_crew/botanist/fetchables()
	return list(/obj/item/food/grown)

/datum/ai_controller/sp_crew/botanist/spares()
	return list(/obj/item/food/grown)

/// Something off the counter: food that is cooked, not the ingredients for it.
/datum/ai_controller/sp_crew/chef/fetchables()
	return list(/obj/item/food)

/datum/ai_controller/sp_crew/chef/fetch_ok(obj/item/food/thing)
	return istype(thing) && !istype(thing, /obj/item/food/grown) && !(thing.foodtypes & RAW)

/// The clown always has a banana about them. It is what they are for.
/datum/ai_controller/sp_crew/clown/spares()
	return list(/obj/item/food/grown/banana)

/// A drink somebody has poured and nobody has picked up.
/datum/ai_controller/sp_crew/bartender/fetchables()
	return list(/obj/item/reagent_containers/cup/glass/drinkingglass)

/datum/ai_controller/sp_crew/bartender/fetch_ok(obj/item/reagent_containers/thing)
	return istype(thing) && thing.reagents?.total_volume > 0

// --- Is it possible at all -------------------------------------------------------------------------

/**
 * Whether `controller` could do this favour for `player` just now: the thing a dialogue checks before offering it
 * (the can_favour condition). What a door or a fetch turned out to be is handed back through `found`, so the
 * dialogue can name it and the favour can go straight to it.
 */
/proc/sp_favour_possible(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/player, kind, list/found)
	if(!istype(controller))
		return FALSE
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !istype(player) || !controller.does_favours() || controller.blackboard_key_exists(BB_SP_FAVOUR))
		return FALSE
	if(pawn.z != player.z)
		return FALSE
	switch(kind)
		if(SP_FAVOUR_FOLLOW)
			return TRUE
		if(SP_FAVOUR_DOOR)
			var/obj/machinery/door/airlock/door = sp_favour_door(pawn, player)
			if(isnull(door))
				return FALSE
			if(found)
				found["target"] = door
			return TRUE
		if(SP_FAVOUR_FETCH)
			var/obj/item/thing = sp_favour_fetchable(controller)
			if(isnull(thing))
				return FALSE
			if(found)
				found["target"] = thing
			return TRUE
		if(SP_FAVOUR_DOCTOR)
			// A medic does not call a medic; and somebody with no headset has nobody to call.
			return !istype(controller, /datum/ai_controller/sp_crew/medical) && istype(pawn.ears, /obj/item/radio/headset) && !isnull(sp_medic_to_call(pawn))
	return FALSE

/// A shut airlock near `player` that `crew` can open and they cannot, and that crew will open for somebody else.
/proc/sp_favour_door(mob/living/carbon/human/crew, mob/living/player)
	var/obj/machinery/door/airlock/best
	for(var/obj/machinery/door/airlock/door in range(SP_FAVOUR_DOOR_RANGE, player))
		if(!door.density || door.locked || door.welded || door.operating || !door.hasPower())
			continue
		if(!door.allowed(crew) || door.allowed(player) || sp_door_off_limits(door))
			continue
		if(isnull(best) || get_dist(player, door) < get_dist(player, best))
			best = door
	return best

/// Whether a door is one nobody opens for somebody else: it needs an access on the list above.
/proc/sp_door_off_limits(obj/machinery/door/airlock/door)
	for(var/access in GLOB.sp_never_opened_for_others)
		if((access in door.req_access) || (access in door.req_one_access))
			return TRUE
	return FALSE

/**
 * Something this crew member would fetch: one they carry and would hand straight over, or the nearest one lying
 * about in their own department -- loose on a floor or a table, not in anybody's hands or shut in a locker. Null
 * when there is nothing to be had.
 */
/proc/sp_favour_fetchable(datum/ai_controller/sp_crew/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	for(var/spare_type in controller.spares())
		for(var/obj/item/spare as anything in pawn.get_all_contents_type(spare_type))
			if(controller.fetch_ok(spare))
				return spare
	var/list/wanted = controller.fetchables()
	var/list/areas = controller.blackboard[BB_SP_WANDER_AREAS]
	if(!length(wanted) || !length(areas))
		return null
	// The room around them first -- where they work is the likeliest place, and area turf lists are not kept for
	// every room (one loaded from a template after the map, say) -- then the rest of the department.
	var/list/turf/spots = list()
	for(var/turf/nearby in range(7, pawn))
		var/area/nearby_area = get_area(nearby)
		if(is_type_in_list(nearby_area, areas))
			spots += nearby
	// Added rather than merged: a turf looked at twice costs less than keeping the list unique.
	for(var/area_type in areas)
		spots += get_area_turfs(area_type, pawn.z, TRUE)
	var/obj/item/best
	var/best_dist = INFINITY
	for(var/turf/spot as anything in spots)
		for(var/obj/item/thing in spot)
			if(!is_type_in_list(thing, wanted) || thing.anchored || HAS_TRAIT(thing, TRAIT_NODROP) || !controller.fetch_ok(thing))
				continue
			var/dist = get_dist(pawn, spot)
			if(dist < best_dist)
				best = thing
				best_dist = dist
	return best

/// Somebody who would come if called: an AI medic, not a chemist, with the kit to see a patient.
/proc/sp_medic_to_call(mob/living/carbon/human/called_by)
	for(var/mob/living/carbon/human/medic as anything in SSspacestation_sp.ai_crew)
		var/datum/ai_controller/sp_crew/medical/their_ai = medic.ai_controller
		if(!istype(their_ai) || istype(their_ai, /datum/ai_controller/sp_crew/medical/chemist))
			continue
		if(medic.stat == STABLE && medic.z == called_by.z && sp_medic_equipped(medic))
			return medic
	return null

// --- Starting and ending ----------------------------------------------------------------------------

/// Takes a favour on. Returns TRUE if it was taken.
/proc/sp_start_favour(datum/ai_controller/sp_crew/controller, kind, mob/living/carbon/human/player, atom/target)
	var/mob/living/carbon/human/pawn = controller?.pawn
	if(!istype(pawn) || !istype(player) || !(kind in GLOB.sp_favours) || controller.blackboard_key_exists(BB_SP_FAVOUR))
		return FALSE
	controller.set_blackboard_key(BB_SP_FAVOUR, kind)
	controller.set_blackboard_key(BB_SP_FAVOUR_FOR, player)
	var/static/list/allowed_time = list(
		SP_FAVOUR_FOLLOW = SP_FAVOUR_FOLLOW_TIME,
		SP_FAVOUR_DOOR = SP_FAVOUR_DOOR_TIME,
		SP_FAVOUR_FETCH = SP_FAVOUR_FETCH_TIME,
		SP_FAVOUR_DOCTOR = 30 SECONDS,
	)
	controller.set_blackboard_key(BB_SP_FAVOUR_UNTIL, world.time + allowed_time[kind])
	if(!isnull(target))
		controller.set_blackboard_key(BB_SP_FAVOUR_TARGET, target)
	controller.set_blackboard_key(BB_SP_FAVOUR_PROGRESS_AT, world.time)
	sp_record("favour.[kind]")
	log_sp("[pawn.real_name] agreed to [kind] for [player.real_name][target ? " ([target])" : ""]")
	return TRUE

/// Gives a favour up or calls it done, with a word to them if there is one to say.
/proc/sp_end_favour(datum/ai_controller/sp_crew/controller, line, reason)
	var/mob/living/carbon/human/pawn = controller?.pawn
	var/mob/living/player = controller?.blackboard[BB_SP_FAVOUR_FOR]
	var/kind = controller?.blackboard[BB_SP_FAVOUR]
	if(isnull(kind))
		return
	for(var/key in list(BB_SP_FAVOUR, BB_SP_FAVOUR_FOR, BB_SP_FAVOUR_UNTIL, BB_SP_FAVOUR_TARGET, BB_SP_FAVOUR_STAGE, BB_SP_FAVOUR_BEST_DIST, BB_SP_FAVOUR_PROGRESS_AT))
		controller.clear_blackboard_key(key)
	controller.ai_movement?.stop_moving_towards(controller)
	if(istype(pawn) && line)
		if(!QDELETED(player))
			pawn.face_atom(player)
		sp_crew_speak(pawn, line)
	log_sp("[pawn?.real_name] finished the [kind] favour for [player?.real_name || "somebody"]: [reason || "done"]")

/// What we call the person we are doing a favour for (sp_what_we_call()).
/proc/sp_favour_name(datum/ai_controller/sp_crew/controller, mob/living/player)
	return sp_what_we_call(controller, player)

/// Whether somebody is letting us off: thanks, or "that's all".
/proc/sp_releases_favour(list/words)
	if(sp_speech_intent(words) == SP_INTENT_THANKS)
		return TRUE
	for(var/phrase in list("that s all", "that ll be all", "that will be all", "that s it", "you can go", "stop following", "off you go", "go back", "dismissed"))
		if(sp_said(words, phrase))
			return TRUE
	return FALSE

// --- Doing it ---------------------------------------------------------------------------------------

/**
 * Walks towards `target` until within `distance` of it. Returns TRUE once there, FALSE while on the way, and null
 * for a walk that has stopped getting any closer for SP_FAVOUR_STUCK -- a locked door in the way, somebody who keeps
 * walking off -- which the favour then gives up.
 */
/proc/sp_favour_walk(datum/ai_controller/sp_crew/controller, atom/target, distance)
	var/mob/living/pawn = controller.pawn
	var/dist = get_dist(pawn, target)
	if(dist <= distance)
		controller.clear_blackboard_key(BB_SP_FAVOUR_BEST_DIST)
		controller.set_blackboard_key(BB_SP_FAVOUR_PROGRESS_AT, world.time)
		return TRUE
	var/best = controller.blackboard[BB_SP_FAVOUR_BEST_DIST]
	if(isnull(best) || dist < best)
		controller.set_blackboard_key(BB_SP_FAVOUR_BEST_DIST, dist)
		controller.set_blackboard_key(BB_SP_FAVOUR_PROGRESS_AT, world.time)
	else if(world.time - controller.blackboard[BB_SP_FAVOUR_PROGRESS_AT] > SP_FAVOUR_STUCK)
		return null
	controller.ai_movement.start_moving_towards(controller, target, distance)
	return FALSE

/// Doing whatever favour is in hand, a step at a time. Ends it when it is done, given up, or overtaken by work.
/datum/bt_node/ai_behavior/sp_do_favour

/datum/bt_node/ai_behavior/sp_do_favour/perform(seconds_per_tick, datum/ai_controller/sp_crew/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/kind = controller.blackboard[BB_SP_FAVOUR]
	var/mob/living/carbon/human/player = controller.blackboard[BB_SP_FAVOUR_FOR]
	if(!istype(pawn) || !istype(controller) || isnull(kind))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(QDELETED(player) || player.stat == DEAD)
		sp_end_favour(controller, null, "they are gone")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/their_name = sp_favour_name(controller, player)
	if(controller.busy_with_work())
		sp_end_favour(controller, pick("Sorry, [their_name], something's come up.", "Got to go, [their_name]. Work."), "work came up")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(world.time > controller.blackboard[BB_SP_FAVOUR_UNTIL])
		sp_end_favour(controller, pick("Right, I've got to get back, [their_name].", "That's me done, [their_name]. Work to do."), "ran out of time")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	var/going
	switch(kind)
		if(SP_FAVOUR_FOLLOW)
			going = sp_favour_follow(controller, player)
		if(SP_FAVOUR_DOOR)
			going = sp_favour_hold_door(controller, player)
		if(SP_FAVOUR_FETCH)
			going = sp_favour_fetch(controller, player)
		if(SP_FAVOUR_DOCTOR)
			going = sp_favour_call_doctor(controller, player)
	if(going)
		return AI_BEHAVIOR_DELAY
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Coming with them: staying a step or two behind wherever they go, until let off, lost, or out of time.
/proc/sp_favour_follow(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/player)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(player.z != pawn.z || get_dist(pawn, player) > SP_FAVOUR_LOST_RANGE)
		sp_end_favour(controller, null, "lost them")
		return FALSE
	var/arrived = sp_favour_walk(controller, player, 1)
	if(isnull(arrived))
		sp_end_favour(controller, pick("I can't get through there, [sp_favour_name(controller, player)].", "Lost you. I'll head back."), "could not keep up")
		return FALSE
	if(controller.blackboard[BB_SP_FAVOUR_STAGE] != "with them" && arrived)
		controller.set_blackboard_key(BB_SP_FAVOUR_STAGE, "with them")
		sp_record("favour.followed")
	return TRUE

/**
 * Opening a door for them: walk to their side of it, open it with our own ID -- nothing is opened that the card on
 * our chest would not open -- and keep it open until they have gone through.
 */
/proc/sp_favour_hold_door(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/player)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/door/airlock/door = controller.blackboard[BB_SP_FAVOUR_TARGET]
	if(QDELETED(door) || door.locked || door.welded || !door.hasPower())
		sp_end_favour(controller, "That door's not having it, sorry.", "the door would not open")
		return FALSE
	if(get_dist(player, door) > SP_FAVOUR_LOST_RANGE)
		sp_end_favour(controller, null, "they went elsewhere")
		return FALSE
	var/stage = controller.blackboard[BB_SP_FAVOUR_STAGE]
	if(isnull(stage))
		if(get_dist(pawn, door) > 1)
			// Up to the door from whichever side they can reach: doors sit in walls, so "beside it" is one of its
			// two passage tiles, never the awkward diagonal sp_reach_spot() exists for.
			var/arrived = sp_favour_walk(controller, door, 1)
			if(isnull(arrived))
				sp_end_favour(controller, "I can't get to it from here, sorry.", "could not reach the door")
				return FALSE
			if(!arrived)
				return TRUE
		controller.ai_movement.stop_moving_towards(controller)
		if(!door.allowed(pawn))
			sp_end_favour(controller, "My card won't do that one after all.", "no access after all")
			return FALSE
		pawn.face_atom(door)
		if(door.density)
			INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, open))
		controller.set_blackboard_key(BB_SP_FAVOUR_STAGE, "holding")
		sp_crew_speak(pawn, pick("There you go.", "After you.", "In you go. Quick, before anyone sees."))
		sp_record("favour.door_opened")
		log_sp("[pawn.real_name] opened [door] in [get_area_name(door)] for [player.real_name]")
		return TRUE
	// Through, once they have stood in the doorway or are past it on the far side.
	var/turf/doorway = get_turf(door)
	if(get_turf(player) == doorway || sp_past_door(door, pawn, player))
		sp_end_favour(controller, null, "they are through")
		sp_record("favour.let_through")
		return FALSE
	// It shut on them before they went: open it again, the way you would hold it.
	if(door.density && !door.operating && door.allowed(pawn))
		INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, open))
	return TRUE

/// Whether `who` is on the far side of a door from somebody standing at it.
/proc/sp_past_door(atom/door, atom/holder, atom/who)
	switch(get_dir(holder, door))
		if(NORTH)
			return who.y > door.y
		if(SOUTH)
			return who.y < door.y
		if(EAST)
			return who.x > door.x
		if(WEST)
			return who.x < door.x
	return FALSE

/// Fetching something: go and get it -- unless it is already in our pockets -- then bring it back and hand it over.
/proc/sp_favour_fetch(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/player)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/their_name = sp_favour_name(controller, player)
	var/obj/item/thing = controller.blackboard[BB_SP_FAVOUR_TARGET]
	if(QDELETED(thing) || (get(thing, /mob) != pawn && !isturf(thing.loc)))
		// Somebody else got there first. Look again, once.
		thing = controller.blackboard[BB_SP_FAVOUR_STAGE] == "looked again" ? null : sp_favour_fetchable(controller)
		if(isnull(thing))
			sp_end_favour(controller, "Couldn't find you one, [their_name], sorry.", "nothing left to fetch")
			return FALSE
		controller.set_blackboard_key(BB_SP_FAVOUR_TARGET, thing)
		controller.set_blackboard_key(BB_SP_FAVOUR_STAGE, "looked again")
	if(get(thing, /mob) != pawn)
		var/arrived = thing.Adjacent(pawn)
		if(!arrived)
			var/turf/spot = sp_reach_spot(thing, pawn)
			arrived = sp_favour_walk(controller, spot || thing, spot ? 0 : 1)
		if(isnull(arrived))
			sp_end_favour(controller, null, "could not get to [thing]")
			return FALSE
		if(!arrived || !thing.Adjacent(pawn))
			return TRUE
		controller.ai_movement.stop_moving_towards(controller)
		if(!pawn.put_in_hands(thing))
			sp_end_favour(controller, null, "hands full")
			return FALSE
		controller.clear_blackboard_key(BB_SP_FAVOUR_BEST_DIST)
		sp_record("favour.fetched")
		log_sp("[pawn.real_name] picked up [thing] in [get_area_name(pawn)] for [player.real_name]")
		return TRUE
	// Bringing it back to them.
	var/arrived = sp_favour_walk(controller, player, 1)
	if(isnull(arrived))
		sp_end_favour(controller, null, "could not find them again")
		return FALSE
	if(!arrived)
		return TRUE
	controller.ai_movement.stop_moving_towards(controller)
	pawn.face_atom(player)
	pawn.temporarilyRemoveItemFromInventory(thing, force = TRUE)
	if(!player.put_in_hands(thing))
		thing.forceMove(get_turf(player))
	sp_record("favour.handed_over")
	sp_end_favour(controller, pick("Here you go, [their_name].", "One [thing.name], as promised.", "There. Don't say I never do anything for you."), "handed over [thing]")
	return FALSE

/// Calling medbay for them: a word on the radio, carried to the medics the way an incident is to security.
/proc/sp_favour_call_doctor(datum/ai_controller/sp_crew/controller, mob/living/carbon/human/player)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/list/radio_call = list()
	radio_call[SP_CALL_KIND] = SP_FAVOUR_DOCTOR
	radio_call[SP_CALL_WHO] = WEAKREF(player)
	radio_call[SP_CALL_TIME] = world.time
	// Set before speaking: the line goes out through INVOKE_ASYNC, and the listeners read the call off us.
	controller.override_blackboard_key(BB_SP_LAST_CALL, radio_call)
	var/who = sp_knows_name(controller, player) ? player.real_name : "somebody"
	sp_crew_speak(pawn, "Medbay, [who] needs a doctor in [get_area_name(player)].", RADIO_CHANNEL_COMMON)
	sp_record("favour.doctor_called")
	sp_end_favour(controller, null, "called medbay")
	return FALSE

// --- Hearing a call ------------------------------------------------------------------------------------

/// Somebody asked on the radio for our department's help. Most of the crew leave it to that department.
/datum/ai_controller/sp_crew/proc/on_heard_call(mob/living/carbon/human/called_by, list/radio_call)
	return

/**
 * Medbay asked to come to somebody: one medic goes, whoever hears it first and is free, and says so. They then come
 * to that person wherever they are, as though they were in sight (sp_find_patient()).
 */
/datum/ai_controller/sp_crew/medical/on_heard_call(mob/living/carbon/human/called_by, list/radio_call)
	if(radio_call[SP_CALL_KIND] != SP_FAVOUR_DOCTOR || busy_with_work() || !sp_medic_equipped(pawn))
		return
	var/datum/weakref/patient_ref = radio_call[SP_CALL_WHO]
	var/mob/living/carbon/human/patient = patient_ref?.resolve()
	if(!istype(patient) || patient.z != pawn.z)
		return
	for(var/mob/living/carbon/human/medic as anything in SSspacestation_sp.ai_crew)
		var/datum/ai_controller/their_ai = medic.ai_controller
		if(their_ai && their_ai != src && their_ai.blackboard[BB_SP_HOUSE_CALL] == patient)
			return
	set_blackboard_key(BB_SP_HOUSE_CALL, patient)
	set_blackboard_key(BB_SP_HOUSE_CALL_AT, world.time)
	sp_record("med.house_call")
	log_sp("[pawn] is going to see [patient.real_name] in [get_area_name(patient)], called by [called_by.real_name]")
	sp_crew_speak(pawn, "On my way to [get_area_name(patient)].", RADIO_CHANNEL_COMMON)

/// Chemists stay at the bench: the call is for somebody who can see a patient.
/datum/ai_controller/sp_crew/medical/chemist/on_heard_call(mob/living/carbon/human/called_by, list/radio_call)
	return
