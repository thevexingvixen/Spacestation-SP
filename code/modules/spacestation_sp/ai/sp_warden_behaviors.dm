/**
 * The warden: the one member of security who does not patrol.
 *
 * They keep the brig -- a prisoner let out when their time is up, an escape called in, an empty cell shut again,
 * evidence filed -- and they keep the armoury: opened at red for the officers to draw from, locked again while nobody
 * should be in it. Reports from elsewhere on the station are somebody else's; the brig is theirs (on_heard_incident()).
 */
/datum/controller/subsystem/spacestation_sp
	/// Who is serving time where: entries of SP_PRISONER_* keys. sp_jail_target() writes them; the warden reads them.
	var/list/prisoners = list()

/datum/ai_controller/sp_crew/security/warden
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_warden.bt.json"

/// The belt out of their own locker, which on MetaStation is the armoury too.
/datum/ai_controller/sp_crew/security/warden/kit_wanted()
	return list(/obj/item/storage/belt/security = /obj/structure/closet/secure_closet/warden)

/datum/ai_controller/sp_crew/security/warden/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	. = ..()
	var/static/list/brig_areas = list(
		/area/station/security/brig,
		/area/station/security/warden,
		/area/station/security/holding_cell,
		/area/station/security/evidence,
		/area/station/security/office,
	)
	// Over the patrol areas the officer setup just wrote: a list value goes in with override_blackboard_key.
	override_blackboard_key(BB_SP_WANDER_AREAS, brig_areas)
	override_blackboard_key(BB_BASIC_MOB_SPEAK_LINES, list(
		BB_SPEAK_CHANCE = 2,
		BB_EMOTE_SAY = list(
			"Cells are quiet. For now.",
			"Nobody draws from the armoury without asking me.",
			"Visiting hours are never.",
			"If you're not under arrest, you're in the wrong room.",
		),
		BB_EMOTE_SEE = list("checks a cell timer.", "counts the lockers.", "polishes a cell door."),
	))

/// On duty while seeing to a cell or the armoury, as well as everything an officer counts.
/datum/ai_controller/sp_crew/security/warden/busy_with_work()
	return ..() || blackboard_key_exists(BB_SP_CELL_DUTY) || blackboard_key_exists(BB_SP_ARMOURY_TARGET)

/// Only what happens in the brig is the warden's to answer. The rest of the station has officers.
/datum/ai_controller/sp_crew/security/warden/on_heard_incident(mob/living/carbon/human/reporter, list/incident)
	if(!sp_in_brig(incident[SP_INCIDENT_TURF]))
		return
	return ..()

/datum/ai_controller/sp_crew/security/warden/on_heard_distress(mob/living/speaker, raw_message, is_radio)
	if(!sp_in_brig(speaker))
		return
	return ..()

/// Whether something is in security's own rooms.
/proc/sp_in_brig(atom/thing)
	var/area/place = get_area(thing)
	return istype(place, /area/station/security)

// --- The cells -------------------------------------------------------------------------------------------

/// Notes who was put in which cell and until when, for the warden.
/proc/sp_note_prisoner(mob/living/prisoner, obj/machinery/status_display/door_timer/cell, sentence, mob/living/officer)
	if(QDELETED(prisoner) || QDELETED(cell))
		return
	var/list/entry = list()
	entry[SP_PRISONER_WHO] = WEAKREF(prisoner)
	entry[SP_PRISONER_CELL] = WEAKREF(cell)
	entry[SP_PRISONER_UNTIL] = world.time + sentence
	entry[SP_PRISONER_OFFICER] = officer?.real_name
	SSspacestation_sp.prisoners += list(entry)

/// The entry for whoever is, or was, in this cell.
/proc/sp_prisoner_entry(obj/machinery/status_display/door_timer/cell)
	for(var/list/entry as anything in SSspacestation_sp.prisoners)
		var/datum/weakref/cell_ref = entry[SP_PRISONER_CELL]
		if(cell_ref?.resolve() == cell)
			return entry
	return null

/// Whether somebody is inside a cell: past its door on the inside, and near it.
/proc/sp_in_cell(mob/living/who, obj/machinery/status_display/door_timer/cell)
	var/list/doorway = sp_cell_doorway(cell)
	var/turf/here = get_turf(who)
	if(!length(doorway) || isnull(here) || here.z != cell.z)
		return FALSE
	var/turf/inside = doorway[1]
	var/turf/outside = doorway[2]
	if(get_dist(here, inside) > SP_CELL_REACH)
		return FALSE
	// Which side of the door they stand on: how far along the way in they lie from the tile just outside it.
	var/toward = (here.x - outside.x) * (inside.x - outside.x) + (here.y - outside.y) * (inside.y - outside.y)
	return toward > 0

/// Whether any of a cell's doors stands open.
/proc/sp_cell_open(obj/machinery/status_display/door_timer/cell)
	for(var/datum/weakref/door_ref as anything in cell?.doors)
		var/obj/machinery/door/door = door_ref.resolve()
		if(!QDELETED(door) && !door.density)
			return TRUE
	return FALSE

/// Whether anybody alive is in the cell.
/proc/sp_cell_occupied(obj/machinery/status_display/door_timer/cell)
	for(var/mob/living/who in range(SP_CELL_REACH, cell))
		if(who.stat != DEAD && sp_in_cell(who, cell))
			return TRUE
	return FALSE

/datum/bt_node/subtree/sp_warden_duty
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_warden_duty.bt.json"

/**
 * Looks over the cells. An escape is called in on the spot. A sentence that has run its course, or an empty cell left
 * standing open, is a walk over (BB_SP_CELL_DUTY), which the rest of the sequence makes and sp_warden_cell_duty ends.
 */
/datum/bt_node/ai_behavior/sp_warden_check_cells
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_warden_check_cells/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard_key_exists(BB_SP_CELL_DUTY))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	for(var/list/entry as anything in SSspacestation_sp.prisoners.Copy())
		var/datum/weakref/cell_ref = entry[SP_PRISONER_CELL]
		var/datum/weakref/who_ref = entry[SP_PRISONER_WHO]
		var/obj/machinery/status_display/door_timer/cell = cell_ref?.resolve()
		var/mob/living/prisoner = who_ref?.resolve()
		if(QDELETED(cell) || cell.z != pawn.z)
			SSspacestation_sp.prisoners -= list(entry)
			continue
		var/alive = !QDELETED(prisoner) && prisoner.stat != DEAD
		if(cell.timing)
			if(alive && !sp_in_cell(prisoner, cell))
				sp_warden_call_escape(controller, entry, prisoner, cell)
			continue
		var/datum/record/crew/record = alive ? find_record(prisoner.real_name) : null
		var/list/doorway = sp_cell_doorway(cell)
		if(!length(doorway))
			SSspacestation_sp.prisoners -= list(entry)
			continue
		var/duty
		if(record?.wanted_status == WANTED_PRISONER)
			duty = SP_CELL_DUTY_RELEASE
		else if(sp_cell_open(cell) && !sp_cell_occupied(cell))
			duty = SP_CELL_DUTY_RESET
		else if(!sp_cell_open(cell))
			SSspacestation_sp.prisoners -= list(entry) // shut again with nobody to let out: nothing left to do here
		if(isnull(duty))
			continue
		controller.set_blackboard_key(BB_SP_CELL_DUTY, cell)
		controller.set_blackboard_key(BB_SP_CELL_DUTY_KIND, duty)
		controller.set_blackboard_key(BB_SP_CELL_DUTY_SPOT, doorway[2])
		log_sp("[pawn.real_name] is going to [cell.name] to [duty == SP_CELL_DUTY_RELEASE ? "let [prisoner.real_name] out" : "shut it again"]")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

/// A prisoner out of their cell before their time: put on the arrest list, called in, and the cell freed up.
/proc/sp_warden_call_escape(datum/ai_controller/sp_crew/controller, list/entry, mob/living/prisoner, obj/machinery/status_display/door_timer/cell)
	var/mob/living/carbon/human/pawn = controller.pawn
	SSspacestation_sp.prisoners -= list(entry)
	sp_mark_for_arrest(prisoner)
	cell.timer_end(forced = TRUE)
	sp_record("warden.escape")
	log_sp("[pawn.real_name] found [prisoner.real_name] out of [cell.name] with time left, and called it in")
	sp_crew_speak(pawn, "[prisoner.real_name] is out of [cell.name] before their time. Bring them back.", RADIO_CHANNEL_SECURITY)

/// Lets go of a cell duty, done or not.
/proc/sp_clear_cell_duty(datum/ai_controller/controller)
	controller?.clear_blackboard_key(BB_SP_CELL_DUTY)
	controller?.clear_blackboard_key(BB_SP_CELL_DUTY_KIND)
	controller?.clear_blackboard_key(BB_SP_CELL_DUTY_SPOT)

/**
 * At the cell: a release is a word and the record cleared, and a reset shuts the door again. A cell door does not
 * shut itself: TG's timer opens it when the sentence ends and nothing closes it after, so a used cell stood open
 * for the rest of the shift.
 */
/datum/bt_node/ai_behavior/sp_warden_cell_duty
	/// Held across the async half.
	VAR_PRIVATE/obj/machinery/status_display/door_timer/reach

/datum/bt_node/ai_behavior/sp_warden_cell_duty/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_CELL_DUTY]
	var/turf/spot = controller.blackboard[BB_SP_CELL_DUTY_SPOT]
	if(!istype(pawn) || QDELETED(reach) || isnull(spot) || get_dist(pawn, spot) > 1)
		sp_clear_cell_duty(controller)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_warden_cell_duty/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/machinery/status_display/door_timer/cell = reach
	var/kind = controller.blackboard[BB_SP_CELL_DUTY_KIND]
	var/list/entry = sp_prisoner_entry(cell)
	var/datum/weakref/who_ref = entry?[SP_PRISONER_WHO]
	var/mob/living/prisoner = who_ref?.resolve()
	pawn.face_atom(cell)
	if(kind == SP_CELL_DUTY_RELEASE)
		var/datum/record/crew/record = QDELETED(prisoner) ? null : find_record(prisoner.real_name)
		if(record?.wanted_status == WANTED_PRISONER)
			record.wanted_status = WANTED_NONE
			update_matching_security_huds(prisoner.real_name)
		sp_record("warden.released")
		log_sp("[pawn.real_name] let [prisoner?.real_name || "the prisoner"] out of [cell.name]")
		if(!QDELETED(prisoner) && get_dist(pawn, prisoner) <= SP_CELL_REACH + 1)
			sp_crew_speak(pawn, "[sp_first_name(prisoner)], time's up. Out you go, and stay out of trouble.")
		else
			sp_crew_speak(pawn, "[prisoner?.real_name || "The prisoner"]'s time is up. Released.", RADIO_CHANNEL_SECURITY)
	else
		for(var/datum/weakref/door_ref as anything in cell.doors)
			var/obj/machinery/door/window/door = door_ref.resolve()
			if(!istype(door))
				continue
			if(!door.density && !door.operating)
				INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door/window, close))
		if(entry)
			SSspacestation_sp.prisoners -= list(entry)
		sp_record("warden.cell_reset")
		log_sp("[pawn.real_name] shut [cell.name] again")
	sp_clear_cell_duty(controller)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_warden_cell_duty/finish_action(datum/ai_controller/controller, succeeded)
	reach = null
	return ..()

// --- The armoury ----------------------------------------------------------------------------------------

/**
 * An armoury locker standing unlocked on a shift that is not red: something to lock up again. Their own belt comes
 * out of one at the start of the shift (kit_wanted()), and this is what shuts it behind them.
 */
/datum/bt_node/ai_behavior/sp_warden_find_open_armoury
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_warden_find_open_armoury/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || SSsecurity_level.get_current_level_as_number() >= SEC_LEVEL_RED)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/structure/closet/best
	var/best_dist = INFINITY
	for(var/obj/structure/closet/candidate as anything in GLOB.roundstart_station_closets)
		if(!GLOB.sp_armoury_lockers[candidate.type] || candidate.locked || candidate.broken || candidate.welded || !candidate.allowed(pawn))
			continue
		var/turf/there = get_turf(candidate)
		if(isnull(there) || there.z != pawn.z)
			continue
		var/dist = get_dist(pawn, candidate)
		if(dist < best_dist)
			best = candidate
			best_dist = dist
	if(isnull(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_ARMOURY_TARGET] != best)
		log_sp("[pawn.real_name] set off to lock [best.name] in [get_area_name(best)]")
	controller.set_blackboard_key(BB_SP_ARMOURY_TARGET, best)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Shutting and locking it. Async, for the clicks.
/datum/bt_node/ai_behavior/sp_warden_secure_locker
	/// Held across the async half.
	VAR_PRIVATE/atom/movable/reach

/datum/bt_node/ai_behavior/sp_warden_secure_locker/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	reach = controller.blackboard[BB_SP_ARMOURY_TARGET]
	if(!istype(pawn) || QDELETED(reach) || !reach.Adjacent(pawn))
		controller.clear_blackboard_key(BB_SP_ARMOURY_TARGET)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_warden_secure_locker/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/structure/closet/locker = reach
	if(!istype(locker))
		controller.clear_blackboard_key(BB_SP_ARMOURY_TARGET)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_free_hands(pawn)
	if(locker.opened)
		sp_ai_click(controller, locker)
	if(!async_still_valid() || QDELETED(locker))
		return
	if(!locker.opened && !locker.locked && locker.allowed(pawn))
		sp_ai_click(controller, locker, list(RIGHT_CLICK = "1"))
	if(!async_still_valid() || QDELETED(locker))
		return
	controller.clear_blackboard_key(BB_SP_ARMOURY_TARGET)
	if(!locker.locked)
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("warden.armoury_locked")
	log_sp("[pawn.real_name] locked [locker.name] in [get_area_name(locker)]")
	sp_crew_speak(pawn, "Armoury's locked up.", RADIO_CHANNEL_SECURITY)
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/datum/bt_node/ai_behavior/sp_warden_secure_locker/finish_action(datum/ai_controller/controller, succeeded)
	reach = null
	return ..()
