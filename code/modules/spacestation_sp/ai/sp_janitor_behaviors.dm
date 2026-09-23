// Behaviour for the AI janitor: fetch a mop, keep it wet, and work through what the station spills.
//
// MetaStation has no custodial closet at all, so the mop and the janitorial cart in the janitor's office are
// the whole kit, and the map's own decals -- some five hundred of them, mostly dirt -- are the work. It never
// runs out, so the order matters more than the total: maintenance comes last, because the crew see the
// hallways, and litter comes first, because somebody can slip on that.

/// Fetch a mop, and water to put in it.
/datum/bt_node/subtree/sp_janitor_supplies
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_janitor_supplies.bt.json"

/// Pick up the litter, then mop the nearest mess.
/datum/bt_node/subtree/sp_janitor_clean
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_janitor_clean.bt.json"

/// Janitor: fetches a mop, keeps it wet, and works through the mess.
/datum/ai_controller/sp_crew/janitor
	behavior_tree_json = "code/modules/spacestation_sp/ai/sp_crew_janitor.bt.json"

/**
 * Somewhere to fill up, found once while the shift is still quiet.
 *
 * A sink is the reliable one: it fills itself at Initialize and tops itself back up. A mop bucket and the
 * janitorial cart both start the round bone dry on this map, cart included, so "go back to your own cart"
 * is only useful once somebody has filled it. This is one scan of the neighbourhood per janitor per shift,
 * against a search of the whole station every time the mop runs out.
 */
/datum/ai_controller/sp_crew/janitor/setup_job_blackboard(mob/living/carbon/human/human_pawn)
	. = ..()
	var/atom/home
	for(var/obj/structure/sink/candidate in range(SP_MOP_HOME_RANGE, human_pawn))
		if(isnull(home) || get_dist(human_pawn, candidate) < get_dist(human_pawn, home))
			home = candidate
	if(isnull(home))
		for(var/obj/structure/mop_bucket/candidate in range(SP_MOP_HOME_RANGE, human_pawn))
			if(isnull(home) || get_dist(human_pawn, candidate) < get_dist(human_pawn, home))
				home = candidate
	if(!isnull(home))
		set_blackboard_key(BB_SP_WATER_HOME, home)

/// Mid-job for a janitor is a mess in hand: a chat can wait until the floor is done.
/datum/ai_controller/sp_crew/janitor/busy_with_work()
	return blackboard_key_exists(BB_SP_MESS) || blackboard_key_exists(BB_SP_LITTER) || blackboard_key_exists(BB_SP_WATER)

// --- Helpers ---------------------------------------------------------------------------------------

/// The mop we are carrying, wherever it is stowed.
/proc/sp_carried_mop(mob/living/carbon/human/pawn)
	var/list/carried = pawn?.get_all_contents_type(/obj/item/mop)
	return length(carried) ? carried[1] : null

/// Whether a mop has anything in it. mop.dm refuses to clean below 0.1 and tells the mopper it is dry.
/proc/sp_mop_is_wet(obj/item/mop/mop)
	return !QDELETED(mop) && mop.reagents?.total_volume >= SP_MOP_DRY

/// Whether there is anything in a sink, bucket or cart to fill a mop from.
/proc/sp_holds_water(atom/source)
	return !QDELETED(source) && source.reagents?.total_volume >= SP_MOP_DRY

/**
 * How much a mess wants cleaning: how far off it is, with maintenance pushed to the back of the queue.
 * A janitor who simply took the nearest would spend the shift in the tunnels, where nobody sees the floor.
 */
/proc/sp_mess_priority(atom/mess, mob/living/pawn)
	var/area/where = get_area(mess)
	return get_dist(pawn, mess) + (istype(where, /area/station/maintenance) ? SP_MESS_MAINT_PENALTY : 0)

/**
 * Says, once a minute at most, why there is nothing being cleaned.
 *
 * A janitor with no work looks exactly like a janitor that is broken: both stand about. The first live round
 * with one in it produced a mop, a fill, and then twelve minutes of silence, which said nothing about which
 * of the two it was.
 */
/proc/sp_janitor_note(datum/ai_controller/controller, reason)
	if(controller.blackboard[BB_SP_JANI_NOTE] == reason && world.time - (controller.blackboard[BB_SP_JANI_NOTE_AT] || 0) < SP_JANI_NOTE_GAP)
		return
	controller.set_blackboard_key(BB_SP_JANI_NOTE, reason)
	controller.set_blackboard_key(BB_SP_JANI_NOTE_AT, world.time)
	var/mob/living/pawn = controller.pawn
	log_sp("[pawn?.real_name] is not cleaning: [reason] (in [get_area_name(pawn)])")

/// Litter that is picked up by hand rather than mopped. A peel first of all: people slip on those.
/proc/sp_litter_typecache()
	var/static/list/litter = typecacheof(list(/obj/item/grown/bananapeel, /obj/item/trash))
	return litter

// --- Supplies --------------------------------------------------------------------------------------

/// True when we have no mop, or the one we have is dry.
/datum/bt_node/decorator/sp_needs_supplies

/datum/bt_node/decorator/sp_needs_supplies/check_condition(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return FALSE
	return !sp_mop_is_wet(sp_carried_mop(pawn))

/// Finds a mop lying about. Mops put themselves in GLOB.janitor_devices, so there is no search to do.
/datum/bt_node/ai_behavior/sp_find_mop
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_mop/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || !isnull(sp_carried_mop(pawn)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED // we have one; it is water we are short of
	var/obj/item/mop/best
	var/best_dist = SP_MOP_SEARCH_RANGE + 1
	for(var/obj/item/mop/candidate as anything in GLOB.janitor_devices)
		// Only one lying on a floor: a mop in somebody's hands, or inside a locker, is not ours to take.
		if(!istype(candidate) || !isturf(candidate.loc) || candidate.z != pawn.z)
			continue
		var/dist = get_dist(pawn, candidate)
		if(dist >= best_dist)
			continue
		best = candidate
		best_dist = dist
	if(isnull(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_MOP, best)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Picks the mop up.
/datum/bt_node/ai_behavior/sp_take_mop

/datum/bt_node/ai_behavior/sp_take_mop/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/mop/mop = controller.blackboard[BB_SP_MOP]
	controller.clear_blackboard_key(BB_SP_MOP)
	if(!istype(pawn) || QDELETED(mop) || !mop.Adjacent(pawn) || !pawn.put_in_hands(mop))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	sp_record("jani.mop")
	log_sp("[pawn.real_name] picked up [mop.name] in [get_area_name(pawn)]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// A bucket, the office cart or any sink: all of them fill a mop.
/datum/bt_node/ai_behavior/sp_find_water
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_water/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || isnull(sp_carried_mop(pawn)))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/atom/best
	var/best_dist = SP_MESS_RANGE + 1
	for(var/obj/structure/mop_bucket/bucket in range(SP_MESS_RANGE, pawn))
		// An empty bucket is a walk for nothing, and every bucket on this map starts empty.
		if(!sp_holds_water(bucket))
			continue
		var/dist = get_dist(pawn, bucket)
		if(dist < best_dist)
			best = bucket
			best_dist = dist
	for(var/obj/structure/sink/sink in range(SP_MESS_RANGE, pawn))
		if(!sp_holds_water(sink))
			continue
		var/dist = get_dist(pawn, sink)
		if(dist < best_dist)
			best = sink
			best_dist = dist
	// Nothing to hand: back to the sink they found at the start of the shift.
	if(isnull(best) && sp_holds_water(controller.blackboard[BB_SP_WATER_HOME]))
		best = controller.blackboard[BB_SP_WATER_HOME]
	if(QDELETED(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_WATER, best)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Fills the mop. TG does the filling; this is the walk up to it and the check that it worked.
/datum/bt_node/ai_behavior/sp_wet_mop

/datum/bt_node/ai_behavior/sp_wet_mop/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	var/atom/water = controller.blackboard[BB_SP_WATER]
	var/obj/item/mop/mop = sp_carried_mop(pawn)
	if(!istype(pawn) || QDELETED(water) || QDELETED(mop) || !water.Adjacent(pawn))
		controller.clear_blackboard_key(BB_SP_WATER)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(pawn.get_active_held_item() != mop && isnull(sp_equip_from_inventory(pawn, list(/obj/item/mop))))
		controller.clear_blackboard_key(BB_SP_WATER)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	return start_async()

/datum/bt_node/ai_behavior/sp_wet_mop/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/atom/water = controller.blackboard[BB_SP_WATER]
	// A sink douses a mop on a plain click. A bucket or a cart wants the other one: mop_bucket.dm hangs
	// filling a mop off item_interaction_secondary, so a left click on one does nothing at all.
	var/list/modifiers = istype(water, /obj/structure/mop_bucket) ? list(RIGHT_CLICK = "1") : null
	sp_ai_click(controller, water, modifiers)
	if(!async_still_valid())
		return
	controller.clear_blackboard_key(BB_SP_WATER)
	if(!sp_mop_is_wet(sp_carried_mop(pawn)))
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	sp_record("jani.filled")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

// --- Cleaning --------------------------------------------------------------------------------------

/// The nearest mess worth walking to, maintenance last, skipping any we have already failed to reach.
/datum/bt_node/ai_behavior/sp_find_mess
	time_between_perform = 3 SECONDS

/datum/bt_node/ai_behavior/sp_find_mess/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/obj/item/mop/mop = sp_carried_mop(pawn)
	if(!sp_mop_is_wet(mop))
		sp_janitor_note(controller, isnull(mop) ? "no mop in hand or bag" : "the mop is dry")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// A mess behind a door we cannot open is somebody else's problem for a while, rather than a walk we
	// keep starting. The same shape as the engineer's unreachable breaches.
	var/atom/attempting = controller.blackboard[BB_SP_MESS_ATTEMPT]
	var/attempt_started = controller.blackboard[BB_SP_MESS_ATTEMPT_AT] || 0
	if(!QDELETED(attempting) && world.time - attempt_started > SP_MESS_ATTEMPT_TIMEOUT)
		controller.set_blackboard_key_assoc_lazylist(BB_SP_MESS_IGNORE, attempting, world.time + SP_MESS_IGNORE_TIME)
		controller.clear_blackboard_key(BB_SP_MESS_ATTEMPT)
		log_sp("[pawn.real_name] gave up on the mess in [get_area_name(attempting)] for now")
	var/list/ignored = controller.blackboard[BB_SP_MESS_IGNORE]
	var/list/shut_rooms = controller.blackboard[BB_SP_AREA_IGNORE]
	var/obj/effect/decal/cleanable/best
	var/best_score = SP_MESS_RANGE + SP_MESS_MAINT_PENALTY + 1
	for(var/obj/effect/decal/cleanable/mess in range(SP_MESS_RANGE, pawn))
		if(LAZYACCESS(ignored, mess) > world.time || LAZYACCESS(shut_rooms, get_area(mess)) > world.time)
			continue
		var/score = sp_mess_priority(mess, pawn)
		if(score >= best_score)
			continue
		best = mess
		best_score = score
	if(isnull(best))
		controller.clear_blackboard_key(BB_SP_MESS)
		sp_janitor_note(controller, "nothing within [SP_MESS_RANGE] tiles worth mopping")
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(controller.blackboard[BB_SP_MESS] != best)
		log_sp("[pawn.real_name] set off to clean [best.name] in [get_area_name(best)], [get_dist(pawn, best)] tiles off")
	controller.set_blackboard_key(BB_SP_MESS, best)
	if(controller.blackboard[BB_SP_MESS_ATTEMPT] != best)
		controller.set_blackboard_key(BB_SP_MESS_ATTEMPT, best)
		controller.set_blackboard_key(BB_SP_MESS_ATTEMPT_AT, world.time)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Mops it. The cleaning is TG's own: the mop's cleaner component runs a do_after and the decal goes.
/datum/bt_node/ai_behavior/sp_mop_mess
	/// When the mopping started, so one that never comes back is given up on rather than held forever.
	VAR_PRIVATE/started_at = 0

/datum/bt_node/ai_behavior/sp_mop_mess/perform(seconds_per_tick, datum/ai_controller/controller)
	var/async_flags = handle_async()
	if(async_flags)
		// A cleaning that never finishes holds this leaf, and the leaf holds the whole tree: a janitor that
		// set off to clean and then did nothing for eight minutes is what sent me looking for this.
		if(started_at && world.time - started_at > SP_MOP_TIMEOUT)
			log_sp("[controller.pawn] gave up mid-mop after [(world.time - started_at) / 10] seconds")
			started_at = 0
			controller.clear_blackboard_key(BB_SP_MESS)
			finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
			return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
		return async_flags
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/effect/decal/cleanable/mess = controller.blackboard[BB_SP_MESS]
	var/obj/item/mop/mop = sp_carried_mop(pawn)
	if(!istype(pawn) || QDELETED(mess) || !sp_mop_is_wet(mop) || !mess.Adjacent(pawn))
		controller.clear_blackboard_key(BB_SP_MESS)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	if(pawn.get_active_held_item() != mop && isnull(sp_equip_from_inventory(pawn, list(/obj/item/mop))))
		controller.clear_blackboard_key(BB_SP_MESS)
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	started_at = world.time
	return start_async()

/datum/bt_node/ai_behavior/sp_mop_mess/perform_async(datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/effect/decal/cleanable/mess = controller.blackboard[BB_SP_MESS]
	var/where = get_area_name(mess)
	var/turf/floor = get_turf(mess)
	// The floor, not the stain: a mop cleans a turf and everything on it, which is what a player clicks, and
	// the stain is what disappears half way through.
	controller.ai_interact(floor, combat_mode = FALSE)
	// Then wait for it to actually happen. TG runs the cleaning through INVOKE_ASYNC of its own, so the click
	// returns within the same tick and the mopping goes on behind it -- and walking off to the next stain
	// cancels the do_after that is still running. Four rounds of a janitor losing a unit of water per stain
	// and cleaning none of them came down to this: the leaf has to wait for the effect, not for the call.
	var/deadline = world.time + SP_MOP_TIMEOUT
	while(world.time < deadline && !QDELETED(mess))
		sleep(0.2 SECONDS)
		if(!async_still_valid())
			// Something outranked us mid-mop and the tree took the leaf back.
			log_sp("[pawn?.real_name] was pulled off the mopping in [where]")
			controller.clear_blackboard_key(BB_SP_MESS)
			return
	started_at = 0
	controller.clear_blackboard_key(BB_SP_MESS)
	if(!QDELETED(mess))
		log_sp("[pawn.real_name] mopped at [mess.name] in [where] and it is still there")
		finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED)
		return
	controller.clear_blackboard_key(BB_SP_MESS_ATTEMPT)
	sp_record("jani.cleaned")
	log_sp("[pawn.real_name] cleaned up in [where]")
	finish_async(AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED)

/// A banana peel or a wrapper on the floor nearby.
/datum/bt_node/ai_behavior/sp_find_litter
	time_between_perform = 5 SECONDS

/datum/bt_node/ai_behavior/sp_find_litter/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	// Litter we have been failing to reach is left alone for a while. Without this, one bag of popcorn behind
	// a wall in maintenance starved the mopping for a whole round: this branch outranks the mess, so it won
	// every few seconds, failed the walk, and cancelled the walk to the mess that had just started.
	var/atom/attempting = controller.blackboard[BB_SP_LITTER_ATTEMPT]
	var/attempt_started = controller.blackboard[BB_SP_LITTER_ATTEMPT_AT] || 0
	if(!QDELETED(attempting) && world.time - attempt_started > SP_LITTER_ATTEMPT_TIMEOUT)
		controller.set_blackboard_key_assoc_lazylist(BB_SP_LITTER_IGNORE, attempting, world.time + SP_MESS_IGNORE_TIME)
		controller.clear_blackboard_key(BB_SP_LITTER_ATTEMPT)
		log_sp("[pawn.real_name] gave up on [attempting.name] in [get_area_name(attempting)] for now")
	var/list/ignored = controller.blackboard[BB_SP_LITTER_IGNORE]
	var/list/wanted = sp_litter_typecache()
	var/obj/item/best
	var/best_dist = SP_LITTER_RANGE + 1
	for(var/obj/item/litter in range(SP_LITTER_RANGE, pawn))
		if(!wanted[litter.type] || !isturf(litter.loc))
			continue
		if(LAZYACCESS(ignored, litter) > world.time)
			continue
		var/dist = get_dist(pawn, litter)
		if(dist >= best_dist)
			continue
		best = litter
		best_dist = dist
	if(isnull(best))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.set_blackboard_key(BB_SP_LITTER, best)
	if(controller.blackboard[BB_SP_LITTER_ATTEMPT] != best)
		controller.set_blackboard_key(BB_SP_LITTER_ATTEMPT, best)
		controller.set_blackboard_key(BB_SP_LITTER_ATTEMPT_AT, world.time)
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/// Bins it. A peel in a bag is one nobody slips on, which is the whole point of picking it up.
/datum/bt_node/ai_behavior/sp_take_litter

/datum/bt_node/ai_behavior/sp_take_litter/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/litter = controller.blackboard[BB_SP_LITTER]
	controller.clear_blackboard_key(BB_SP_LITTER)
	if(!istype(pawn) || QDELETED(litter) || !litter.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/list/bags = pawn.get_all_contents_type(/obj/item/storage/bag/trash)
	var/obj/item/storage/bag/trash/bag = length(bags) ? bags[1] : null
	var/stowed = FALSE
	if(!isnull(bag))
		stowed = bag.atom_storage?.attempt_insert(litter, pawn, override = TRUE)
	if(!stowed && !(pawn.back && litter.forceMove(pawn.back)) && !pawn.put_in_hands(litter))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	controller.clear_blackboard_key(BB_SP_LITTER_ATTEMPT)
	sp_record("jani.litter")
	log_sp("[pawn.real_name] picked up [litter.name] in [get_area_name(pawn)]")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_SUCCEEDED

/**
 * The mess could not be got to: remember the room rather than the stain.
 *
 * One stain in atmospherics is every stain in atmospherics, and a janitor's ID opens neither. Marking them
 * one at a time cost forty-five seconds each and there are dozens, so a round went by with the mop wet and
 * the floor dirty. Always fails: this is a note, not a job.
 */
/datum/bt_node/ai_behavior/sp_mess_unreachable

/datum/bt_node/ai_behavior/sp_mess_unreachable/perform(seconds_per_tick, datum/ai_controller/controller)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/effect/decal/cleanable/mess = controller.blackboard[BB_SP_MESS]
	controller.clear_blackboard_key(BB_SP_MESS)
	// Gone, or we did get there and the mopping itself failed: neither says anything about the room.
	if(!istype(pawn) || QDELETED(mess) || mess.Adjacent(pawn))
		return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED
	var/area/shut = get_area(mess)
	if(!isnull(shut))
		controller.set_blackboard_key_assoc_lazylist(BB_SP_AREA_IGNORE, shut, world.time + SP_MESS_IGNORE_TIME)
		controller.clear_blackboard_key(BB_SP_MESS_ATTEMPT)
		log_sp("[pawn.real_name] cannot get into [shut.name]; leaving that whole room for a few minutes")
	return AI_BEHAVIOR_DELAY | AI_BEHAVIOR_FAILED

